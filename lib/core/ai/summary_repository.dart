/// 总结仓库实现：把「照片索引 + AI 配置 + API Key + 适配器」串成一条线。
///
/// 职责边界：
/// - 缓存读取与 photoSig 失效判断（照片增删改后总结自动标脏）；
/// - 压图（成本护栏 maxImagesPerDay 在这里生效）；
/// - 单日按需生成、整月并发 3 的批量生成与进度推送。
/// 请求格式本身完全交给 AiFactory 造出来的 AiProvider，本文件不碰 HTTP。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../storage/photo_index_store.dart';
import '../storage/settings_store.dart';
import 'ai_factory.dart';
import 'ai_provider.dart';
import 'api_key_store.dart';
import 'ai_client.dart';
import 'ai_image_preparer.dart';

class SummaryRepositoryImpl implements SummaryRepository {
  /// [client] 注入 HTTP 客户端（单测用假客户端，不发真实网络请求）。
  /// [preparer] 注入压图器，单测里可替换为直接返回字节的桩。
  SummaryRepositoryImpl({
    required PhotoIndexStore store,
    http.Client? client,
    AiImagePreparer preparer = const AiImagePreparer(),
  })  : _store = store,
        _httpClient = client,
        _preparer = preparer;

  final PhotoIndexStore _store;
  final http.Client? _httpClient;
  final AiImagePreparer _preparer;

  /// 只建一次：每次生成都 new 一个 http.Client 会漏 socket。
  late final AiClient _ai = AiClient(client: _httpClient);

  @override
  Future<AiSummary?> cached(int dayKey) => _store.summaryOf(dayKey);

  @override
  Future<AiSummary> generate({
    required DayRecord record,
    bool force = false,
    void Function(int current, int total)? onImageProgress,
  }) async {
    final photos = record.photos;
    if (photos.isEmpty) throw const AiException('这一天没有照片，无需总结');

    // 指纹必须先算：它是「缓存是否还有效」的唯一判据，
    // 照片增删改（path/mtime 变化）都会让它翻转。
    final sig = computePhotoSig(photos);
    if (!force) {
      final existing = await _store.summaryOf(record.dayKey);
      if (existing != null && existing.photoSig == sig) return existing;
    }

    // 顺序说明：规格写的是「压图 → 读配置」，但压图要先知道 maxImagesPerDay
    // （成本护栏），所以配置必须提前读；key 则放到真正要发请求前才读，
    // 免得纯缓存命中也去碰安全存储。
    final config = await SettingsStore.loadAiConfig();
    final images = await _preparer.prepare(
      photos: photos,
      maxImages: config.maxImagesPerDay,
      onProgress: onImageProgress,
    );

    final apiKey = await ApiKeyStore.read();
    if (apiKey == null || apiKey.trim().isEmpty) throw const AiAuthException();

    final provider =
        AiFactory.createWithClient(config, apiKey.trim(), aiClient: _ai);
    final generated = await provider.generateDaySummary(
      imagesJpeg: images,
      date: dayKeyToDateTime(record.dayKey),
      dayContext: _dayContext(photos),
    );

    // 适配器并不知道当日照片全集，photoSig 与 created_at 统一在这里回填，
    // 保证落库的指纹一定等于「本次生成所依据的那批照片」。
    final summary = AiSummary.fromMap(<String, Object?>{
      ...generated.toMap(),
      'day_key': record.dayKey,
      'photo_sig': sig,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _store.putSummary(summary);
    return summary;
  }

  @override
  Stream<MonthBatchProgress> generateMonth({required int year, required int month}) {
    final controller = StreamController<MonthBatchProgress>();
    controller.onListen = () {
      _runMonth(controller, year, month);
    };
    return controller.stream;
  }

  /// 整月批量：并发 3，每完成一天推一帧进度，最后必推 finished 帧并关流。
  Future<void> _runMonth(
    StreamController<MonthBatchProgress> controller,
    int year,
    int month,
  ) async {
    var total = 0;
    var done = 0;
    var failed = 0;
    try {
      final dayPhotos = <int, List<Photo>>{};
      final lastDay = daysInMonth(year, month);
      for (var d = 1; d <= lastDay; d++) {
        final dayKey = year * 10000 + month * 100 + d;
        final photos = await _store.photosOfDay(dayKey);
        if (photos.isNotEmpty) dayPhotos[dayKey] = photos;
      }
      // total = 有照片的天数（契约字段释义）；缓存仍有效的天直接计入 done，
      // 这样进度条第一天就是真实位置，也能一路走到 total。
      total = dayPhotos.length;
      final pending = <int>[];
      for (final entry in dayPhotos.entries) {
        final existing = await _store.summaryOf(entry.key);
        if (existing != null && existing.photoSig == computePhotoSig(entry.value)) {
          done++;
        } else {
          pending.add(entry.key);
        }
      }
      pending.sort();
      controller.add(
        MonthBatchProgress(total: total, done: done, failed: failed, currentDayKey: 0),
      );

      final gate = _Semaphore(3);
      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          final i = cursor++;
          if (i >= pending.length) return;
          final dayKey = pending[i];
          await gate.acquire();
          try {
            final photos = dayPhotos[dayKey]!;
            final record = DayRecord(
              dayKey: dayKey,
              photos: photos,
              summary: await _store.summaryOf(dayKey),
            );
            try {
              await generate(record: record);
              done++;
            } catch (_) {
              // 单天失败（限流、格式不认…）不拖垮整批，计数后继续
              failed++;
            }
          } finally {
            gate.release();
          }
          controller.add(
            MonthBatchProgress(
              total: total,
              done: done,
              failed: failed,
              currentDayKey: dayKey,
            ),
          );
        }
      }

      await Future.wait(<Future<void>>[worker(), worker(), worker()]);
    } catch (_) {
      // 整月读库等意外：已完成部分照实收尾，不让 UI 卡在进度条上
    } finally {
      controller.add(
        MonthBatchProgress(
          total: total,
          done: done,
          failed: failed,
          currentDayKey: 0,
          finished: true,
        ),
      );
      await controller.close();
    }
  }

  /// 提示词里的补充信息：拍摄时间跨度让模型知道这是「一整天」还是「一个下午」。
  static String _dayContext(List<Photo> photos) {
    if (photos.isEmpty) return '';
    final times = photos.map((p) => p.takenAt).toList()
      ..sort((a, b) => a.compareTo(b));
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '当天共 ${photos.length} 张照片，拍摄时间从 ${hm(times.first)} 到 ${hm(times.last)}。';
  }
}

/// 极简信号量：批量并发闸门。
///
/// 为什么不引 package:async：它不是本项目的直接依赖（引了会触发
/// depend_on_referenced_packages），而这里只需要 20 行。
class _Semaphore {
  _Semaphore(int permits)
      : _permits = permits,
        _available = permits;

  final int _permits;
  int _available;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // 槽位直接移交给排队者，可用数保持不变
      _waiters.removeAt(0).complete();
    } else {
      _available++;
    }
    assert(_available <= _permits, '信号量释放次数多于申请次数');
  }
}
