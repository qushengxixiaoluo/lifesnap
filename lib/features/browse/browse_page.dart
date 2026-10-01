/// 浏览与搜索页（真实实现）：搜索框 → 标签云 + 心情筛选 → 结果列表。
///
/// 契约（阶段 0 钉死）：公开类 [BrowsePage]、无参 const 构造——
/// router.dart 的 '/browse' 路由与地图页 AppBar 的 explore 入口都依赖此签名。
///
/// 价值：AI 生成的 tags 此前从未被浏览过——标签云是本页主角，
/// 出现次数直接写在云上（「#海风 ×2」），点一下即筛选，再点取消。
/// 筛选与搜索的逻辑全部住在 browse_providers.dart，本文件只管渲染。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../widgets/hand_card.dart';
import '../day_detail/day_detail_launcher.dart';
import 'browse_providers.dart';

class BrowsePage extends ConsumerStatefulWidget {
  const BrowsePage({super.key});

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  /// 搜索框文案放 widget 侧：清空按钮、清除筛选都要直接操作输入框；
  /// 筛选语义（query/tag/mood）则统一在 [browseFilterProvider]。
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 空输入框 + 复位筛选：两处清空入口（后缀小叉、清除筛选按钮）共用。
  void _clearAll() {
    _controller.clear();
    ref.read(browseFilterProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summariesAsync = ref.watch(browseSummariesProvider);

    final page = Scaffold(
      appBar: AppBar(title: const Text('浏览与搜索')),
      body: SafeArea(
        child: summariesAsync.when(
          loading: () => const Center(child: Text('加载中…')),
          error: (err, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('总结载入失败：$err', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(browseSummariesProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
          data: (_) => _body(theme),
        ),
      ),
    );

    // 与设置页同一兜底：已有 ProviderScope 则复用（测试的 override 生效），
    // 没有才补挂——编排者在 main.dart 挂上后自动走复用分支。
    return _hasProviderScope(context) ? page : ProviderScope(child: page);
  }

  // ---------------------------------------------------------------- 主体

  Widget _body(ThemeData theme) {
    final filter = ref.watch(browseFilterProvider);
    final tagCounts = ref.watch(browseTagCountsProvider);
    final results = ref.watch(browseResultsProvider);

    return Column(
      children: [
        // —— 1. 搜索框：输入即过滤 ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: (v) => ref.read(browseFilterProvider.notifier).setQuery(v),
            // 敲回车收起键盘（过滤本来就随输入实时生效，不需要 submit 才搜）
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: '搜索标题、正文、标签、瞬间',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () =>
                          ref.read(browseFilterProvider.notifier).setQuery(''),
                    ),
            ),
          ),
        ),

        // —— 2. 标签云 + 心情筛选 + 清除入口 ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: HandCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('标签云', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '点标签只看那一天群，再点取消',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (tagCounts.isEmpty)
                      Text('还没有标签', style: theme.textTheme.bodySmall),
                    for (final e in tagCounts.entries)
                      _tagChip(
                        theme,
                        label: '#${e.key} ×${e.value}',
                        selected: filter.tag == e.key,
                        onTap: () =>
                            ref.read(browseFilterProvider.notifier).toggleTag(e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('心情', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in AiSummary.moodIcons.entries)
                      _tagChip(
                        theme,
                        label: '${e.value} ${e.key}',
                        selected: filter.mood == e.key,
                        onTap: () =>
                            ref.read(browseFilterProvider.notifier).toggleMood(e.key),
                      ),
                  ],
                ),
                if (filter.isActive) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: const Text('清除筛选'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // —— 3. 结果列表 ——
        Expanded(
          child: results.isEmpty ? _emptyView(theme) : _resultList(theme, results),
        ),
      ],
    );
  }

  /// 标签/心情两朵云共用的胶囊（选中态走主题强调色，画风换肤自适应）。
  Widget _tagChip(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      selectedColor: theme.colorScheme.secondaryContainer,
    );
  }

  /// 空结果：无论无数据还是筛选没命中，都给同一句明确交代。
  Widget _emptyView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 36, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text('没有找到匹配的记录', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _resultList(ThemeData theme, List<AiSummary> results) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _resultCard(context, theme, results[index]),
    );
  }

  /// 单条结果：中文日期 + 标题 + 正文前两行 + 标签小字；点击进日详情。
  Widget _resultCard(BuildContext context, ThemeData theme, AiSummary s) {
    return HandCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      onTap: () => showDayDetail(context, s.dayKey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dayKeyToChinese(s.dayKey), style: theme.textTheme.labelMedium),
              const SizedBox(width: 6),
              // 心情符只放图标：文字版「☀ 晴」会与心情筛选胶囊撞文案，
              // 断言/点选都会歧义，图标则天然不重复。
              Text(
                s.moodIcon,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            s.narrative,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (s.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s.tags.map((t) => '#$t').join(' '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// context 上方是否已有 ProviderScope（找不到会抛 StateError）。
bool _hasProviderScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } on StateError {
    return false;
  }
}
