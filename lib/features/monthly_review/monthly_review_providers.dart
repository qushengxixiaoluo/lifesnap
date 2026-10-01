/// 月度回顾 · Riverpod 状态（本功能专属；全局服务仍从 app/providers.dart 取）。
///
/// 两个 provider：
/// - [monthlyReviewRepositoryProvider]：等 photoStore 就绪后造仓库
///   （与日总结仓库同源：photoStoreProvider 在 main 里已 override 成全局唯一 store）；
/// - [monthlyReviewViewProvider]：某月（key = yyyymm）的展示视图——
///   已有月报 + 当月日总结指纹 + 是否失效，UI 据此渲染横幅与结果卡。
///
/// 生成动作是「一次调用」不入批量队列，放在设置页本地态里驱动，
/// 成功后 invalidate 视图 provider 刷新缓存展示。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/ai/monthly_review_repository.dart';
import '../../core/models/models.dart';

/// 月度回顾仓库（FutureProvider：photoStore 本身是异步打开的）。
final monthlyReviewRepositoryProvider =
    FutureProvider<MonthlyReviewRepository>((ref) async {
  final store = await ref.watch(photoStoreProvider.future);
  return MonthlyReviewRepository(store: store);
});

/// 某月月报展示视图。
class MonthlyReviewView {
  /// 已落库的月报（从未生成过则为 null）。
  final MonthlyReview? review;

  /// 当月日总结的内容指纹（当月没有日总结则为 null）。
  final String? inputSig;

  /// 当月日总结条数。
  final int dayCount;

  const MonthlyReviewView({
    required this.review,
    required this.inputSig,
    required this.dayCount,
  });

  /// 月报存在但指纹已对不上 → 日总结有增删改，月报标失效。
  /// inputSig 为 null（当月日总结被删光）同样算失效：
  /// 否则一篇依据已不存在的日总结写成的月报会以「有效」姿态继续展示。
  bool get stale =>
      review != null && (inputSig == null || review!.inputSig != inputSig);

  bool get hasDaySummaries => dayCount > 0;
}

/// 读某月（key = year * 100 + month）的月报缓存与失效状态。
///
/// autoDispose：年月下拉切走即释放，切回来重查，
/// 生成月报 / 编辑日总结后 invalidate 一次就能看到新状态。
final monthlyReviewViewProvider = FutureProvider.autoDispose
    .family<MonthlyReviewView, int>((ref, yearMonthKey) async {
  final year = yearMonthKey ~/ 100;
  final month = yearMonthKey % 100;
  final store = await ref.watch(photoStoreProvider.future);

  final days = <AiSummary>[
    for (final s in await store.allSummaries())
      if (s.dayKey ~/ 10000 == year && (s.dayKey ~/ 100) % 100 == month) s,
  ];
  final review = await store.monthlyReviewOf(year, month);
  return MonthlyReviewView(
    review: review,
    inputSig: days.isEmpty ? null : computeMonthlyInputSig(days),
    dayCount: days.length,
  );
});
