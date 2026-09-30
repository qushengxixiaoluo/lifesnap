/// 照片索引存储 · 抽象契约（阶段 0 地基文件）
///
/// 平台实现走条件导入（沿 interview_calendar 的 database_io/database_web 先例）：
/// - io（Android/iOS）  → sqflite        【B 轨实现】
/// - io（Windows/macOS/Linux） → hive_ce 【B 轨实现】
/// - web → hive_ce(IndexedDB)            【B 轨实现】
///
/// 阶段 0 自带内存实现，保证空壳应用在 B 轨完成前可运行，也永久作为测试替身。
/// 五条并行轨只允许 import 本文件，不得修改。
library;

import '../../core/models/models.dart';
import 'open_store_io.dart' if (dart.library.html) 'open_store_web.dart' as opener;

/// 打开当前平台的索引存储（启动时调用一次）。
Future<PhotoIndexStore> openPhotoIndexStore() => opener.openPhotoIndexStore();

abstract class PhotoIndexStore {
  Future<void> init();

  // —— 扫描源 ——
  Future<List<PhotoSource>> loadSources();
  Future<int> addSource(PhotoSource source); // 返回自增 id
  Future<void> removeSource(int id);
  Future<void> markSourceScanned(int id, int atMs);

  /// 增量扫描核心：某源已知的 path → mtime 映射。
  /// 扫描器据此跳过未变化文件的 EXIF 解析。
  Future<Map<String, int>> knownSignatures(int sourceId);

  // —— 照片写入/查询 ——
  Future<void> upsertPhotos(List<Photo> photos);
  Future<void> removePhotos(List<String> paths);
  Future<List<Photo>> photosOfDay(int dayKey);

  // —— 日索引（启动全量载入内存，扫描后重算）——
  Map<int, DayMeta> get dayIndex;
  Future<void> refreshDayIndex();

  // —— AI 总结缓存 ——
  Future<AiSummary?> summaryOf(int dayKey);
  Future<void> putSummary(AiSummary summary);

  Future<void> close();
}

/// ---------------------------------------------------------------------------
/// 阶段 0 的内存实现：不落盘，进程内可用。
/// B 轨交付真实实现后，opener 文件改指真实现；本类保留为单测替身。
/// ---------------------------------------------------------------------------
class InMemoryPhotoIndexStore implements PhotoIndexStore {
  final _photos = <Photo>[];
  final _sources = <PhotoSource>[];
  final _summaries = <int, AiSummary>{};
  final _dayIndex = <int, DayMeta>{};
  int _nextId = 1;

  @override
  Future<void> init() async => refreshDayIndex();

  @override
  Future<List<PhotoSource>> loadSources() async => List.unmodifiable(_sources);

  @override
  Future<int> addSource(PhotoSource source) async {
    final id = _nextId++;
    _sources.add(PhotoSource(
      id: id,
      type: source.type,
      path: source.path,
      enabled: source.enabled,
      lastScanMs: source.lastScanMs,
    ));
    return id;
  }

  @override
  Future<void> removeSource(int id) async {
    _sources.removeWhere((s) => s.id == id);
    _photos.removeWhere((p) => p.sourceId == id);
    await refreshDayIndex();
  }

  @override
  Future<void> markSourceScanned(int id, int atMs) async {
    final i = _sources.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _sources[i] = PhotoSource(
        id: id,
        type: _sources[i].type,
        path: _sources[i].path,
        enabled: _sources[i].enabled,
        lastScanMs: atMs,
      );
    }
  }

  @override
  Future<Map<String, int>> knownSignatures(int sourceId) async => {
        for (final p in _photos)
          if (p.sourceId == sourceId) p.path: p.mtimeMs,
      };

  @override
  Future<void> upsertPhotos(List<Photo> photos) async {
    for (final p in photos) {
      final i = _photos.indexWhere((e) => e.path == p.path);
      if (i >= 0) {
        _photos[i] = p.copyWith(id: _photos[i].id);
      } else {
        _photos.add(p.copyWith(id: _nextId++));
      }
    }
    await refreshDayIndex();
  }

  @override
  Future<void> removePhotos(List<String> paths) async {
    _photos.removeWhere((p) => paths.contains(p.path));
    await refreshDayIndex();
  }

  @override
  Future<List<Photo>> photosOfDay(int dayKey) async {
    final list = _photos.where((p) => p.dayKey == dayKey).toList()
      ..sort((a, b) => a.takenAtMs.compareTo(b.takenAtMs));
    return list;
  }

  @override
  Map<int, DayMeta> get dayIndex => Map.unmodifiable(_dayIndex);

  @override
  Future<void> refreshDayIndex() async {
    _dayIndex.clear();
    for (final p in _photos) {
      final cur = _dayIndex[p.dayKey];
      _dayIndex[p.dayKey] = DayMeta(
        dayKey: p.dayKey,
        photoCount: (cur?.photoCount ?? 0) + 1,
        thumbPath: cur?.thumbPath ?? p.path, // 首张即预览，缩略图异步生成
      );
    }
  }

  @override
  Future<AiSummary?> summaryOf(int dayKey) async => _summaries[dayKey];

  @override
  Future<void> putSummary(AiSummary summary) async =>
      _summaries[summary.dayKey] = summary;

  @override
  Future<void> close() async {}
}
