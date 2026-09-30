/// 闯关地图主页（C 轨正式实现，替换了阶段 0 占位）
///
/// 结构：
///   SkyBackground（天空层）
///     └ 头部「‹ 2026年9月 · 拾光地图 ›」
///     └ PageView（横滑翻月，每页 = 一个月的地图）
///          路径层(RepaintBoundary) → 31 个节点(各自 RepaintBoundary) → Rect 命中层
///
/// 数据流：photoStoreProvider(异步) → monthDayIndexProvider(按月缓存 DayMeta)
///        → 每节点取 photoCount/thumbPath/hasSummary；store 为空时全部按空日渲染。
///
/// 契约：类名 CalendarMapPage 与无参 const 构造保持不变（路由 '/' 依赖它）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// 注意：此处不再 import shared_preferences——换肤已统一由设置页
// （AppearanceSection）负责，地图页删除 palette 快捷按钮后无需再持有该依赖。

import '../../app/app_style.dart';
import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../widgets/sky_background.dart';
import '../day_detail/day_detail_launcher.dart';
import 'day_node.dart';
import 'day_node_layout.dart';
import 'map_path_painter.dart';
import 'map_providers.dart';

/// 根路由页面（router '/' 依赖其类名与无参 const 构造，二者是不可变不变式）。
///
/// 职责：挂载地图状态——上层已有根 [ProviderScope]（main 集成后的生产形态）则复用，
/// 无根时才自建页面级 scope 兜底；并把「打开某日详情」的回调绑定到**外层 context**
/// 下发——详情面板挂在 Navigator/Overlay 路由下，不归页面级 scope 管，
/// context 选错会红屏（见 build 注释）。
class CalendarMapPage extends StatelessWidget {
  const CalendarMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 自适应 scope：main.dart 阶段 2 集成后已在根部挂 ProviderScope（photoStore
    // override 单实例 store），正常生产走「上层已有 → 直接复用」分支；
    // 「没有才自建」仅保留给无根 scope 的嵌入场景（历史回归用例仍覆盖它），
    // 有根时此分支不触发，等价于 no-op。
    //
    // 为什么 openDay 绑定的是**外层** context（本 build 方法拿到的、
    // ProviderScope 之上的这个 context）：详情面板由 showModalBottomSheet 挂到
    // Navigator/Overlay 路由下，物理上不在页面级 scope 的子树里。若把内层
    // context 传给 showDayDetail，它的「已有 scope 则不再兜底」判断会被页面级
    // scope 骗过，DayDetailSheet 首帧 ref.watch(photoStoreProvider) 就会抛
    // No ProviderScope（无根场景点任意节点红屏）。传外层 context 时：
    // - 无根 scope → 判断为 false → launcher 自己补兜底 scope；
    // - 有根 scope（当前生产形态）→ 判断为 true → 面板本就在根 scope 下，
    //   与地图共享同一 container（单实例 store、状态互通）。
    // 两个分支都正确，集成测试「根 ProviderScope 集成」对后者做了坐实。
    void openDay(int dayKey) => showDayDetail(context, dayKey);

    return _hasProviderScope(context)
        ? _MapHome(openDay: openDay)
        : ProviderScope(child: _MapHome(openDay: openDay));
  }

  static bool _hasProviderScope(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
      return true;
    } on StateError {
      return false;
    }
  }
}

// ============================================================================
// 页面外壳：天空 + 头部 + 横滑地图
// ============================================================================

class _MapHome extends ConsumerStatefulWidget {
  /// 打开某日详情的回调：由 [CalendarMapPage.build] 用外层 context 绑定，
  /// 保证详情面板的兜底 scope 判断不被页面级 scope 误导（原因见彼处注释）。
  final ValueChanged<int> openDay;

  const _MapHome({required this.openDay});

  @override
  ConsumerState<_MapHome> createState() => _MapHomeState();
}

class _MapHomeState extends ConsumerState<_MapHome> {
  /// 翻月由 PageController 驱动（动画跟手），provider 只记录「现在是哪个月」。
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _pageController = PageController(
      initialPage: clampMonthIndex(monthToIndex(now.year, now.month)),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final target = clampMonthIndex(index);
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthKey = ref.watch(currentMonthProvider);
    final year = monthKey ~/ 100;
    final month = monthKey % 100;
    final pageIndex = clampMonthIndex(monthToIndex(year, month));

    return Scaffold(
      // 天空要从状态栏一路铺到底，背景与工具栏都留空给 SkyBackground。
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('拾光手册'),
        actions: [
          // 唯一入口：设置页承载 照片源/AI配置/批量/换肤（AppearanceSection）。
          // 走命名路由而非直接 import SettingsPage——跨轨只经 router 收口，
          // 既避免地图页重复持有设置页依赖，也消掉跨轨直接 import 的耦合。
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
        // 换肤快捷键已删：AppearanceSection 统一接管三套皮肤，
        // 地图页不再保留第二处换肤 UI（见 git 历史中的 palette 按钮）。
      ),
      body: SkyBackground(
        // 整层监听皮肤：换肤时路径发光色、文字色一起刷新，
        // 但节点布局仍从缓存秒出，不会重新抖动。
        child: ValueListenableBuilder<AppStyle>(
          valueListenable: AppStyleNotifier.current,
          builder: (context, style, _) {
            return Padding(
              // 为什么只用 padding.top 而不加 kToolbarHeight：
              // 打开 extendBodyBehindAppBar 后，Scaffold 的 _BodyBuilder 会把
              // body 的 MediaQuery.padding.top 直接抬到 AppBar 底边
              // （max(状态栏, AppBar 实际高度)），再叠一次工具栏高度会凭空多出 56px 缝隙。
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: Column(
                children: [
                  _MonthHeader(
                    year: year,
                    month: month,
                    canPrev: pageIndex > 0,
                    canNext: pageIndex < kMapMonthCount - 1,
                    onPrev: () => _goTo(pageIndex - 1),
                    onNext: () => _goTo(pageIndex + 1),
                  ),
                  Expanded(
                    // 地图层单独一层光栅：翻月/脉冲重绘不会牵动天空层。
                    child: RepaintBoundary(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: kMapMonthCount,
                        onPageChanged: (i) =>
                            ref.read(currentMonthProvider.notifier).setIndex(i),
                        itemBuilder: (context, i) {
                          final (y, m) = monthFromIndex(i);
                          return _MapMonthView(
                            year: y,
                            month: m,
                            style: style,
                            openDay: widget.openDay,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// 头部：‹ 2026年9月 · 拾光地图 ›
// ============================================================================

class _MonthHeader extends StatelessWidget {
  final int year;
  final int month;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.year,
    required this.month,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          // 半透明纸条压在天空上，保证深浅皮肤下文字都读得清。
          color: ShiguangColors.paper.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: ShiguangColors.wood.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一月',
              // 文字/图标固定墨棕：纸条底色不随皮肤变化，跟着变白反而会看不见。
              color: ShiguangColors.inkBrown,
              disabledColor: ShiguangColors.inkBrown.withValues(alpha: 0.3),
              onPressed: canPrev ? onPrev : null,
            ),
            Expanded(
              child: Text(
                '$year年$month月 · 拾光地图',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: ShiguangColors.inkBrown,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一月',
              color: ShiguangColors.inkBrown,
              disabledColor: ShiguangColors.inkBrown.withValues(alpha: 0.3),
              onPressed: canNext ? onNext : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 单月地图：路径 + 节点 + 命中层
// ============================================================================

class _MapMonthView extends ConsumerWidget {
  final int year;
  final int month;
  final AppStyle style;

  /// 打开某日详情（透传 [CalendarMapPage] 绑定的外层 context 回调）。
  final ValueChanged<int> openDay;

  const _MapMonthView({
    required this.year,
    required this.month,
    required this.style,
    required this.openDay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 数据与布局分开取：布局在 LayoutBuilder 里（依赖尺寸），
    // 数据在外面 watch（异步到达后 setState 重建本页）。
    // 加载中/出错 → 空 Map → 整月按空日渲染，地图照样完整好看。
    final metas = ref
            .watch(monthDayIndexProvider(year * 100 + month))
            .value ??
        const <int, DayMeta>{};
    final cache = ref.watch(layoutCacheProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final positions = cache.layoutMonth(
          year,
          month,
          CanvasSize(constraints.maxWidth, constraints.maxHeight),
        );
        if (positions.isEmpty) return const SizedBox.expand();

        final todayKey = dayKeyOf(DateTime.now());
        final statuses = <DayNodeStatus>[];
        final dayKeys = <int>[];
        // 命中用 Rect 列表层：半径取 1.2r；最小中心距是 2.5r，
        // 因此任意两个命中圆互不相交，点中谁就是谁，不会串节点。
        final hitRects = <Rect>[];

        for (final p in positions) {
          final dayKey = year * 10000 + month * 100 + p.day;
          final meta = metas[dayKey];
          dayKeys.add(dayKey);
          statuses.add(
            statusOfDay(
              dayKey: dayKey,
              todayKey: todayKey,
              hasSummary: meta?.hasSummary ?? false,
              photoCount: meta?.photoCount ?? 0,
            ),
          );
          hitRects.add(
            Rect.fromCircle(
              center: Offset(p.x, p.y),
              radius: p.radius * 1.2,
            ),
          );
        }

        return Stack(
          // 徽章、光环、节点阴影都要溢出各自的方块。
          clipBehavior: Clip.none,
          children: [
            // 1) 路径层：整月只有一层光栅。
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: MapPathPainter(
                    nodes: positions,
                    statuses: statuses,
                    style: style,
                  ),
                ),
              ),
            ),

            // 2) 节点层：每个节点各自一层光栅，脉冲只重绘今日那一个。
            for (var i = 0; i < positions.length; i++)
              Positioned(
                left: positions[i].x - positions[i].radius,
                top: positions[i].y - positions[i].radius,
                width: positions[i].radius * 2,
                height: positions[i].radius * 2,
                child: RepaintBoundary(
                  child: DayNode(
                    key: ValueKey('day-node-${dayKeys[i]}'),
                    position: positions[i],
                    dayKey: dayKeys[i],
                    status: statuses[i],
                    thumbPath: metas[dayKeys[i]]?.thumbPath,
                    hasSummary: metas[dayKeys[i]]?.hasSummary ?? false,
                  ),
                ),
              ),

            // 3) 命中层：统一拦下点击，按 Rect 找最近的节点。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTap(
                  details.localPosition,
                  positions,
                  dayKeys,
                  hitRects,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onTap(
    Offset point,
    List<NodePosition> positions,
    List<int> dayKeys,
    List<Rect> rects,
  ) {
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < rects.length; i++) {
      if (!rects[i].contains(point)) continue;
      final dx = point.dx - positions[i].x;
      final dy = point.dy - positions[i].y;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    // 详情入口走 openDay 回调（外层 context），绝不用本层 context：
    // 一旦走到「无根 scope 自建页面级 scope」的兜底分支，本层就在页面级
    // scope 之下，会让 showDayDetail 的兜底 scope 判断失效（详见 CalendarMapPage.build）。
    if (best >= 0) openDay(dayKeys[best]);
  }
}
