/// 浏览与搜索页的 Riverpod 状态：数据口 + 筛选条件 + 派生结果。
///
/// 分层（沿地图轨 map_providers 的先例）：
/// - 数据只从 `app/providers.dart` 的 photoStoreProvider 取，不自己 new 存储；
/// - 筛选条件是纯内存 [Notifier]，无副作用、可被单测直接驱动；
/// - 标签云计数与结果列表全部由「数据 + 筛选」派生，页面只管渲染。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models/models.dart';

// ============================================================================
// 筛选条件
// ============================================================================

/// 页面的筛选条件：搜索串 + 单选标签 + 单选心情（三者可叠加）。
///
/// 为什么做成不可变值对象：三个字段彼此正交，任何一项变化都要保留其余
/// 两项，整对象替换比逐字段改写更不容易漏（参考日详情 DayRecord 的写法）。
class BrowseFilter {
  const BrowseFilter({this.query = '', this.tag, this.mood});

  /// 全文搜索串（原始输入，匹配时才 toLowerCase）。
  final String query;

  /// 单选标签（null = 不按标签筛；再点同标签即取消）。
  final String? tag;

  /// 单选心情（null = 不按心情筛；与标签筛选可叠加）。
  final String? mood;

  /// 是否有任何筛选/搜索激活——决定「清除筛选」按钮显不显示。
  bool get isActive => query.trim().isNotEmpty || tag != null || mood != null;

  /// 这条总结是否通过当前筛选。
  ///
  /// 匹配范围：title、narrative、tags、highlights 任一包含查询串即命中
  /// （大小写不敏感）；标签与心情是精确匹配，两者之间是「与」关系。
  bool matches(AiSummary s) {
    if (tag != null && !s.tags.contains(tag)) return false;
    if (mood != null && s.mood != mood) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (s.title.toLowerCase().contains(q)) return true;
    if (s.narrative.toLowerCase().contains(q)) return true;
    if (s.tags.any((t) => t.toLowerCase().contains(q))) return true;
    return s.highlights.any((h) => h.toLowerCase().contains(q));
  }
}

class BrowseFilterNotifier extends Notifier<BrowseFilter> {
  @override
  BrowseFilter build() => const BrowseFilter();

  /// 输入即过滤（个人日记量级无须防抖，见页内搜索框注释）。
  void setQuery(String query) =>
      state = BrowseFilter(query: query, tag: state.tag, mood: state.mood);

  /// 点选标签：单选，再点同标签取消。
  void toggleTag(String tag) => state = BrowseFilter(
        query: state.query,
        tag: state.tag == tag ? null : tag,
        mood: state.mood,
      );

  /// 点选心情：单选，再点同心情取消；与标签筛选叠加生效。
  void toggleMood(String mood) => state = BrowseFilter(
        query: state.query,
        tag: state.tag,
        mood: state.mood == mood ? null : mood,
      );

  /// 清除全部筛选；搜索框文案由页面侧同步清空。
  void reset() => state = const BrowseFilter();
}

final browseFilterProvider =
    NotifierProvider<BrowseFilterNotifier, BrowseFilter>(BrowseFilterNotifier.new);

// ============================================================================
// 数据与派生
// ============================================================================

/// 全部 AI 总结，按 day_key 降序（最近在上）——浏览页唯一数据入口。
///
/// 契约：store.allSummaries() 返回 day_key 升序；排序统一收在这一层，
/// 标签云 / 搜索 / 结果列表共享同一份顺序，页面不再各自排。
/// autoDispose：翻走即释放，重新进入重读，保证别处改了总结这里能看到。
final browseSummariesProvider = FutureProvider.autoDispose<List<AiSummary>>((
  ref,
) async {
  final store = await ref.watch(photoStoreProvider.future);
  final all = await store.allSummaries();
  return all.toList()..sort((a, b) => b.dayKey.compareTo(a.dayKey));
});

/// 当前数据快照：加载中/出错时给空表（页面骨架另用 browseSummariesProvider 三态渲染）。
List<AiSummary> _snapshot(Ref ref) =>
    ref.watch(browseSummariesProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <AiSummary>[],
        );

/// 标签云：全部总结里每个标签的出现次数。
///
/// 永远统计**全量**、不随筛选变化——筛选中的标签若从计数里消失，
/// 用户就找不到取消它的入口了。次数多的排前面（同次数按标签名排序，
/// 保证顺序稳定，测试可断言）。
final browseTagCountsProvider = Provider<Map<String, int>>((ref) {
  final counts = <String, int>{};
  for (final s in _snapshot(ref)) {
    for (final t in s.tags) {
      counts.update(t, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return {for (final e in sorted) e.key: e.value};
});

/// 应用「搜索 + 标签 + 心情」后的结果（保持 day_key 降序）。
final browseResultsProvider = Provider<List<AiSummary>>((ref) {
  final filter = ref.watch(browseFilterProvider);
  return [for (final s in _snapshot(ref)) if (filter.matches(s)) s];
});
