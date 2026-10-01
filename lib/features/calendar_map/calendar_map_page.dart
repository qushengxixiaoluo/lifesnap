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
import 'candy_colors.dart';
import 'day_node.dart';
import 'day_node_layout.dart';
import 'map_path_painter.dart';
import 'map_providers.dart';
import 'month_jump_dialog.dart';

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

  /// 点头部月份标题 → 年月选择对话框 → 直接跳到目标月。
  /// 跨年长距离跳转靠 animateToPage 滑过中间月份（观感是「翻地图」而非闪现）。
  Future<void> _pickMonth() async {
    final monthKey = ref.read(currentMonthProvider);
    final picked = await MonthJumpDialog.show(
      context,
      initialYear: monthKey ~/ 100,
    );
    if (picked == null || !mounted) return;
    final (year, month) = picked;
    ref.read(currentMonthProvider.notifier).setMonth(year, month);
    _goTo(monthToIndex(year, month));
  }

  @override
  Widget build(BuildContext context) {
    final monthKey = ref.watch(currentMonthProvider);
    final year = monthKey ~/ 100;
    final month = monthKey % 100;
    final pageIndex = clampMonthIndex(monthToIndex(year, month));
    // 本月「有照片的天数」：头部副行展示（用户要求月份上显示记录情况）
    final photoDays = ref
            .watch(monthDayIndexProvider(monthKey))
            .value
            ?.values
            .where((m) => m.photoCount > 0)
            .length ??
        0;

    return Scaffold(
      // 天空要从状态栏一路铺到底，背景与工具栏都留空给 SkyBackground。
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('拾光手册'),
        actions: [
          // 浏览与搜索：标签云 / 心情 / 全文检索（页面自己实现，这里只管入口）
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: '浏览与搜索',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.browse),
          ),
          // 那年今日：往年今天的照片与总结
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '那年今日',
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.onThisDay),
          ),
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
        // 整层监听天色 + 画风两根轴：换肤/换画风时路径发光色、文字色一起刷新，
        // 但节点布局仍从缓存秒出，不会重新抖动。
        child: ValueListenableBuilder<AppStyle>(
          valueListenable: AppStyleNotifier.current,
          builder: (context, style, _) {
            return ValueListenableBuilder<ArtStyle>(
              valueListenable: ArtStyleNotifier.current,
              builder: (context, art, _) {
                return Padding(
                  // 为什么只用 padding.top 而不加 kToolbarHeight：
                  // 打开 extendBodyBehindAppBar 后，Scaffold 的 _BodyBuilder 会把
                  // body 的 MediaQuery.padding.top 直接抬到 AppBar 底边
                  // （max(状态栏, AppBar 实际高度)），再叠一次工具栏高度会凭空多出 56px 缝隙。
                  padding:
                      EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                  child: Column(
                    children: [
                      _MonthHeader(
                        year: year,
                        month: month,
                        photoDays: photoDays,
                        style: style,
                        art: art,
                        canPrev: pageIndex > 0,
                        canNext: pageIndex < kMapMonthCount - 1,
                        onPrev: () => _goTo(pageIndex - 1),
                        onNext: () => _goTo(pageIndex + 1),
                        onPickMonth: _pickMonth,
                      ),
                      Expanded(
                        // 地图层单独一层光栅：翻月/脉冲重绘不会牵动天空层。
                        child: RepaintBoundary(
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: kMapMonthCount,
                            onPageChanged: (i) => ref
                                .read(currentMonthProvider.notifier)
                                .setIndex(i),
                            itemBuilder: (context, i) {
                              final (y, m) = monthFromIndex(i);
                              return _MapMonthView(
                                year: y,
                                month: m,
                                style: style,
                                art: art,
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

  /// 本月有照片记录的天数（副行文案用）。
  final int photoDays;

  /// 当前皮肤（副行文字/光晕色随皮肤走，保证任何天空下可读）。
  final AppStyle style;

  /// 当前画风（LowPoly 副行走画风矩阵文字色，糖果卡沿用原描边白）。
  final ArtStyle art;

  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  /// 点标题弹年月选择器（直接跳转任意月份）。
  final VoidCallback onPickMonth;

  const _MonthHeader({
    required this.year,
    required this.month,
    required this.photoDays,
    required this.style,
    required this.art,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onPickMonth,
  });

  @override
  Widget build(BuildContext context) {
    // 副行配色随「天色 × 画风」走，且浮在天空上（不在奶油胶囊里）：
    // - 糖果：日间/黄昏用糖果棕压白光晕，星夜用纯白压暗光晕（既有观感不动）；
    // - LowPoly：直接用画风矩阵的文字色——亮底近黑字、星夜冷白字，
    //   否则纯白字会把高饱和平涂天空读成「过曝」。
    final lightSkin = style != AppStyle.night;
    final statColor = art == ArtStyle.lowPoly
        ? textColorFor(style, art)
        : (lightSkin ? outlineNow() : CandyColors.glossWhite);
    final statShadow =
        lightSkin ? Colors.white.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.5);
    return Padding(
      // 上边距保持 6：测试断言 chevron 顶边必须贴在 AppBar 下沿
      // （≥ appbarBottom - 1 且 ≤ +40），加厚胶囊后仍留有余量。
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          // 木牌胶囊：奶油底 + 3.5px 深棕厚描边 + 底部实心厚阴影（blur 0），
          // 玩具感来自「厚边+硬影」而不是 Material elevation。
          gradient: CandyColors.panelFill,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: outlineNow(), width: 3.5),
          boxShadow: [
            BoxShadow(
              color: outlineNow().withValues(alpha: 0.9),
              blurRadius: 0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            _candyArrow(
              icon: Icons.chevron_left,
              tooltip: '上一月',
              enabled: canPrev,
              onPressed: onPrev,
            ),
            Expanded(
              // 点标题直接弹年月选择器跳转（不止左右翻月）
              child: Semantics(
                button: true,
                label: '选择月份跳转',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onPickMonth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '$year年$month月 · 拾光地图　▾',
                      textAlign: TextAlign.center,
                      // 非 const：字色取 outlineNow()（随画风切棕/黑）
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800, // 粗体圆润（风格圣经第 8 条）
                        letterSpacing: 1.1,
                        color: outlineNow(),
                        shadows: const [
                          // 细描边感用白影模拟：奶油底上描一圈白，字更「贴纸」。
                          Shadow(
                            color: CandyColors.glossWhite,
                            offset: Offset(0, 1),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _candyArrow(
              icon: Icons.chevron_right,
              tooltip: '下一月',
              enabled: canNext,
              onPressed: onNext,
            ),
          ],
          ),
          ),
          const SizedBox(height: 3),
          // 副行：本月记录情况（用户要求「月份上面显示有照片记录」）
          Text(
            photoDays > 0 ? '有照片记录 $photoDays 天' : '这个月还没有照片记录',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: statColor,
              shadows: [
                Shadow(color: statShadow, offset: const Offset(0, 1), blurRadius: 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 左右糖果圆钮：橙面果冻渐变 + 厚棕描边 + 底部实心投影的圆形按钮。
  /// 首尾月时换成灰面（不可点状态一眼可辨），图标固定白/淡棕保证对比度。
  Widget _candyArrow({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: enabled ? CandyColors.orangeFill : CandyColors.grayFill,
        border: Border.all(color: outlineNow(), width: 2.6),
        boxShadow: [
          BoxShadow(
            color: outlineNow().withValues(alpha: 0.9),
            blurRadius: 0,
            offset: const Offset(0, 2.5),
          ),
        ],
      ),
      child: IconButton(
        // 约束成 40×40 正圆：默认 48 会把胶囊撑高，chevron 顶边
        // 有贴 AppBar（+40px 内）的几何断言，见 build 顶部注释。
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        icon: Icon(icon),
        tooltip: tooltip,
        // 图标颜色跟按钮状态走：可用＝白（橙面上），禁用＝棕 35%（灰面上）。
        color: CandyColors.glossWhite,
        disabledColor: outlineNow().withValues(alpha: 0.35),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

// ============================================================================
// 单月地图：路径 + 节点 + 命中层
// ============================================================================

class _MapMonthView extends ConsumerStatefulWidget {
  final int year;
  final int month;
  final AppStyle style;
  final ArtStyle art; // 画风透传给路径层：雾罩光晕色随画风走，shouldRepaint 才能感知

  /// 打开某日详情（透传 [CalendarMapPage] 绑定的外层 context 回调）。
  final ValueChanged<int> openDay;

  const _MapMonthView({
    required this.year,
    required this.month,
    required this.style,
    required this.art,
    required this.openDay,
  });

  @override
  ConsumerState<_MapMonthView> createState() => _MapMonthViewState();
}

class _MapMonthViewState extends ConsumerState<_MapMonthView> {
  /// 当前按下的节点下标（-1 = 无）。
  ///
  /// 节点自身不挂手势（不变式），所以「按下变矮」的反馈由命中层
  /// 在 onTapDown/onTapUp 时把按下态下发给对应 DayNode——
  /// 只重绘这一个节点（各自 RepaintBoundary），天空与路径不陪跑。
  int _pressedIndex = -1;

  @override
  Widget build(BuildContext context) {
    // 数据与布局分开取：布局在 LayoutBuilder 里（依赖尺寸），
    // 数据在外面 watch（异步到达后 setState 重建本页）。
    // 加载中/出错 → 空 Map → 整月按空日渲染，地图照样完整好看。
    final metas = ref
            .watch(monthDayIndexProvider(widget.year * 100 + widget.month))
            .value ??
        const <int, DayMeta>{};
    final cache = ref.watch(layoutCacheProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final positions = cache.layoutMonth(
          widget.year,
          widget.month,
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
          final dayKey = widget.year * 10000 + widget.month * 100 + p.day;
          final meta = metas[dayKey];
          dayKeys.add(dayKey);
          statuses.add(
            statusOfDay(
              dayKey: dayKey,
              todayKey: todayKey,
              // 手写补记与 AI 总结同为「有记录」：金勾状态不区分内容来源
              hasSummary: (meta?.hasSummary ?? false) ||
                  (meta?.hasNote ?? false),
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
                    style: widget.style,
                    art: widget.art,
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
                    hasSummary: (metas[dayKeys[i]]?.hasSummary ?? false) ||
                        (metas[dayKeys[i]]?.hasNote ?? false),
                    // 按下反馈：命中层下发，节点只做「变矮」视觉。
                    pressed: _pressedIndex == i,
                  ),
                ),
              ),

            // 3) 命中层：统一拦下点击，按 Rect 找最近的节点。
            //    按下瞬间先点亮对应节点（软糖被按进去），抬手清态并开详情；
            //    拖动翻页被手势竞技场判走时走 onCancel，不留残按下态。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final hit = _hitAt(details.localPosition, positions, hitRects);
                  if (hit != _pressedIndex) {
                    setState(() => _pressedIndex = hit);
                  }
                },
                onTapUp: (details) {
                  final hit = _hitAt(details.localPosition, positions, hitRects);
                  if (_pressedIndex != -1) setState(() => _pressedIndex = -1);
                  // 详情入口走 openDay 回调（外层 context），绝不用本层 context：
                  // 一旦走到「无根 scope 自建页面级 scope」的兜底分支，本层就在页面级
                  // scope 之下，会让 showDayDetail 的兜底 scope 判断失效（详见 CalendarMapPage.build）。
                  if (hit >= 0) widget.openDay(dayKeys[hit]);
                },
                onTapCancel: () {
                  if (_pressedIndex != -1) {
                    setState(() => _pressedIndex = -1);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 命中判定：点落在哪个 Rect 里；多个候选（理论上不相交）取圆心最近的。
  /// 返回下标，未命中返回 -1（按下态用 -1 表示「没按到任何节点」）。
  int _hitAt(Offset point, List<NodePosition> positions, List<Rect> rects) {
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
    return best;
  }
}
