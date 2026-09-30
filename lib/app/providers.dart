/// 服务提供者（阶段 0 地基）——五轨统一从这里取依赖，禁止自行 new 服务实例。
///
/// 设计：
/// - [photoStoreProvider] 走条件导入 openPhotoIndexStore()：
///   阶段 0 返回内存实现；B 轨交付后自动升级为 sqflite/hive 真实存储，调用方零改动。
/// - 扫描/总结服务用「绑定式」：阶段 2 集成时注入真实实现；
///   并行开发期返回优雅空实现（推错误进度/空结果），UI 可先跑通不崩溃。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/ai_provider.dart';
import '../core/models/models.dart';
import '../core/scanning/scanner_contracts.dart';
import '../core/storage/photo_index_store.dart';

/// 照片索引存储（异步打开）。
final photoStoreProvider = FutureProvider<PhotoIndexStore>((ref) => openPhotoIndexStore());

/// 阶段 2 集成注入点：ScannerBindings.instance = RealScannerService(store);
class ScannerBindings {
  static ScannerService? instance;
}

/// 阶段 2 集成注入点：SummaryBindings.instance = RealSummaryRepository(...);
class SummaryBindings {
  static SummaryRepository? instance;
}

final scannerServiceProvider = Provider<ScannerService>(
  (ref) => ScannerBindings.instance ?? const _MissingScanner(),
);

final summaryRepositoryProvider = Provider<SummaryRepository>(
  (ref) => SummaryBindings.instance ?? const _MissingSummaryRepository(),
);

// ---------------------------------------------------------------------------
// 优雅空实现：并行期未接入时给出明确文案，不崩溃
// ---------------------------------------------------------------------------

class _MissingScanner implements ScannerService {
  const _MissingScanner();

  @override
  bool get gallerySupported => false;

  @override
  Stream<ScanProgress> scanSource(PhotoSource source) => Stream.value(
        const ScanProgress(
          phase: ScanPhase.error,
          errorMessage: '扫描服务尚未接入（阶段 2 集成后可用）',
        ),
      );

  @override
  Stream<ScanProgress> scanAll() => Stream.value(
        const ScanProgress(
          phase: ScanPhase.error,
          errorMessage: '扫描服务尚未接入（阶段 2 集成后可用）',
        ),
      );
}

class _MissingSummaryRepository implements SummaryRepository {
  const _MissingSummaryRepository();

  @override
  Future<AiSummary?> cached(int dayKey) async => null;

  @override
  Future<AiSummary> generate({required DayRecord record, bool force = false,
          void Function(int current, int total)? onImageProgress}) =>
      throw const AiException('总结服务尚未接入（阶段 2 集成后可用）');

  @override
  Stream<MonthBatchProgress> generateMonth({required int year, required int month}) =>
      Stream.value(MonthBatchProgress(
        total: 0, done: 0, failed: 0, currentDayKey: 0, finished: true,
      ));
}
