/// 闯关地图 · 本页的 Riverpod 状态
///
/// 只放「地图页专属」的状态；全局服务一律从 `app/providers.dart` 取，
/// 避免各轨自己 new 服务实例（阶段 2 集成时会统一注入真实现）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models/models.dart';
import 'day_node_layout.dart';

// ============================================================================
// 月份换算：PageView 的页号 ↔ 年月
// ============================================================================

/// 地图可翻到的起止年份：2000–2099 共 1200 个月。
/// 用固定区间而不是「用户照片的年份范围」：PageView 需要有限且稳定的
/// itemCount，区间足够宽就永远翻不到头，又不必维护动态范围。
const int kMapStartYear = 2000;
const int kMapEndYear = 2099;
const int kMapMonthCount = (kMapEndYear - kMapStartYear + 1) * 12;

/// 年月 → 页号。
int monthToIndex(int year, int month) =>
    (year - kMapStartYear) * 12 + (month - 1);

/// 页号 → (年, 月)。
(int, int) monthFromIndex(int index) =>
    (kMapStartYear + index ~/ 12, index % 12 + 1);

/// 夹到合法页号，箭头按钮在首尾月时据此置灰。
int clampMonthIndex(int index) {
  if (index < 0) return 0;
  if (index >= kMapMonthCount) return kMapMonthCount - 1;
  return index;
}

// ============================================================================
// 当前月
// ============================================================================

/// 当前展示的月份（state = yyyymm 单键整数，如 202609）。
///
/// 放在 provider 而不是 StatefulWidget 里：头部、PageView、
/// 以及后续「跳到某月」的入口（比如从详情页返回）都要读同一个值。
class CurrentMonthNotifier extends Notifier<int> {
  @override
  int build() {
    final now = DateTime.now();
    return now.year * 100 + now.month;
  }

  /// 由 PageView.onPageChanged 驱动。
  void setIndex(int index) {
    final (y, m) = monthFromIndex(clampMonthIndex(index));
    state = y * 100 + m;
  }

  void setMonth(int year, int month) {
    var m = month < 1 ? 1 : (month > 12 ? 12 : month);
    final (y, mm) = monthFromIndex(clampMonthIndex(monthToIndex(year, m)));
    state = y * 100 + mm;
  }
}

final currentMonthProvider =
    NotifierProvider<CurrentMonthNotifier, int>(CurrentMonthNotifier.new);

// ============================================================================
// 布局缓存
// ============================================================================

/// 每个 ProviderScope 一份缓存：换肤/重建不会重掷随机数，
/// 窗口尺寸变化时只做等比映射（见 day_node_layout.dart）。
final layoutCacheProvider = Provider<MonthLayoutCache>((ref) {
  return MonthLayoutCache();
});

// ============================================================================
// 某月的日索引
// ============================================================================

/// 读取某月每一天的 [DayMeta]（key = yyyymm）。
///
/// 为什么要合并一次 AI 总结：
/// 契约里 `DayMeta.hasSummary` 由存储层在 refreshDayIndex 填充，
/// 但阶段 0 的 InMemoryPhotoIndexStore 只从照片重建聚合、不回读总结表，
/// 直接用会出现「明明存了总结却没金勾」。这里以 store.summaryOf 兜底，
/// 阶段 2 真实实现若已回填，就只是一次 31 行的快查询。
///
/// autoDispose：翻走即释放，翻回来重查，保证扫描/生成总结后回到该月能看到新状态。
final monthDayIndexProvider = FutureProvider.autoDispose
    .family<Map<int, DayMeta>, int>((ref, yearMonthKey) async {
  final year = yearMonthKey ~/ 100;
  final month = yearMonthKey % 100;

  // store 打不开时这里会抛错 → 页面按「全部空日」渲染，地图照样好看。
  final store = await ref.watch(photoStoreProvider.future);

  final count = daysInMonth(year, month);
  final result = <int, DayMeta>{};
  for (var day = 1; day <= count; day++) {
    final dayKey = year * 10000 + month * 100 + day;
    final base = store.dayIndex[dayKey];
    var hasSummary = base?.hasSummary ?? false;
    if (!hasSummary) {
      hasSummary = await store.summaryOf(dayKey) != null;
    }
    result[dayKey] = DayMeta(
      dayKey: dayKey,
      photoCount: base?.photoCount ?? 0,
      thumbPath: base?.thumbPath,
      hasSummary: hasSummary,
    );
  }
  return result;
});
