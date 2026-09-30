/// 扫描服务门面实现：串联「读已知签名 → 扫描器 → 落库 → markSourceScanned → refreshDayIndex」。
///
/// 平台差异全部收在 scanner_platform_io / scanner_platform_web 两个条件导入文件里，
/// 本文件不含任何 dart:io / photo_manager / js_interop，Web 与移动端共用同一份编排逻辑。
///
/// 阶段 2 集成：调用 [ScannerServiceImpl.install] 把实例注入 providers.dart 的
/// ScannerBindings（providers.dart 是只读契约，绑定动作只能发生在本文件）。
library;

import '../../app/providers.dart';
import '../models/models.dart';
import '../storage/photo_index_store.dart';
import 'scan_sink.dart';
import 'scanner_contracts.dart';
import 'scanner_platform_io.dart'
    if (dart.library.html) 'scanner_platform_web.dart' as platform;

class ScannerServiceImpl implements ScannerService {
  ScannerServiceImpl(this._store);

  final PhotoIndexStore _store;

  /// 集成注入点：main 启动时 ScannerServiceImpl.install(store)。
  static void install(PhotoIndexStore store) =>
      ScannerBindings.instance = ScannerServiceImpl(store);

  @override
  bool get gallerySupported => platform.gallerySupported;

  @override
  Stream<ScanProgress> scanSource(PhotoSource source) async* {
    // 落库通道每次扫描现绑：sink 生命周期与本次扫描一致，避免并发扫描互相写串
    final sink = PhotoScanSink(
      onPhotos: _store.upsertPhotos,
      onRemoved: _store.removePhotos,
    );
    final scanner = platform.buildScanner(source.type, sink);
    if (!scanner.supported) {
      yield const ScanProgress(
        phase: ScanPhase.error,
        errorMessage: '当前平台不支持该扫描方式',
      );
      return;
    }

    try {
      // 增量前提：先取该源的 path → mtime 快照，扫描器据此跳过未变化文件
      final known = await _store.knownSignatures(source.id);
      await for (final progress
          in scanner.scan(source, knownPathToMtime: known)) {
        if (progress.phase == ScanPhase.done) {
          // 收尾必须发生在 done 帧之前：上层监听到 finished 停止订阅后，
          // 生成器会被挂起，markSourceScanned 就永远不会执行
          await _store.markSourceScanned(
            source.id,
            DateTime.now().millisecondsSinceEpoch,
          );
          await _store.refreshDayIndex();
          yield progress;
          return;
        }
        if (progress.phase == ScanPhase.error) {
          yield progress; // 失败不打时间戳：没扫完就标记已扫会掩盖问题
          return;
        }
        yield progress;
      }
      // 扫描器空流（防御分支）：仍按完成收尾，避免 UI 永远等不到 finished
      await _store.markSourceScanned(
        source.id,
        DateTime.now().millisecondsSinceEpoch,
      );
      await _store.refreshDayIndex();
      yield const ScanProgress(phase: ScanPhase.done);
    } catch (e) {
      yield ScanProgress(
        phase: ScanPhase.error,
        errorMessage: '扫描「${source.displayName}」失败：$e',
      );
    }
  }

  @override
  Stream<ScanProgress> scanAll() async* {
    final enabled = [
      for (final s in await _store.loadSources())
        if (s.enabled) s,
    ];
    if (enabled.isEmpty) {
      yield const ScanProgress(phase: ScanPhase.done);
      return;
    }
    for (var i = 0; i < enabled.length; i++) {
      final isLast = i == enabled.length - 1;
      await for (final p in scanSource(enabled[i])) {
        // 吞掉中间源的 done 帧：设置页把 finished 当整体结束信号，
        // 多源顺序扫描时若逐源透传，第一个源扫完就会被误判为全部完成
        if (p.phase == ScanPhase.done && !isLast) continue;
        yield p;
        if (p.phase == ScanPhase.error) return; // 一个源失败即整体失败，避免连环报错刷屏
      }
    }
  }
}
