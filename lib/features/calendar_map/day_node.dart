/// 闯关地图 · 单个日节点（糖果风五状态视觉实现）
///
/// 风格圣经：保卫萝卜 / 燃烧的蔬菜 Q版糖果塔防——节点是「按下去会弹的
/// 软糖圆扣」：上亮下暗果冻渐变 + 4px 厚描边 + 顶部高光弧 +
/// 底部实心厚阴影（不是 Material elevation）。
///
/// 描边色走画风感知的 [outlineNow]（不是写死的 outlineNow()）：
/// 糖果 = 深巧克力棕、LowPoly = #141414 近黑——画风一换，整组扣的轮廓
/// 跟着换；页面外层已监听 ArtStyleNotifier，重建即取到新描边。
///
/// 五种状态与视觉语义：
/// | 状态 | 视觉 | 为什么这样画 |
/// |------|------|--------------|
/// | [DayNodeStatus.withSummary] | 金橙果冻扣 + 右上金星徽章 | 通关 = 金色星星，比勾更「关卡」 |
/// | [DayNodeStatus.withPhotos]  | 圆形裁切首图 + 白厚描边      | 有素材未总结 = 待办，白描边够醒目 |
/// | [DayNodeStatus.pastEmpty]   | 奶油素扣 + 棕数字            | 过去空白日 = 素扣，不刺眼 |
/// | [DayNodeStatus.today]       | 大一圈粉扣 + 彩带徽章脉冲    | 只有今日会动，视线第一落点 |
/// | [DayNodeStatus.future]      | 灰扣 + 小锁泡泡              | 未解锁的关卡，暗示「还没到」 |
///
/// 性能取舍：
/// - 脉冲用独立 AnimationController（1.6s 循环），只重绘自己这一个小方块；
///   外层由页面包 RepaintBoundary，天空与路径层完全不参与重绘。
/// - 节点自身**不挂手势**：命中统一交给页面的 Rect 列表层，
///   既避免 31 个 GestureDetector 抢手势竞技场，也让命中逻辑可批量测试。
///   「按下反馈」因此由页面把 pressed 状态下发（见 calendar_map_page）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import '../../core/models/models.dart';
import '../../core/thumbnails/thumb_image.dart';
import 'candy_colors.dart';
import 'day_node_layout.dart';

// ============================================================================
// 状态定义
// ============================================================================

enum DayNodeStatus {
  withSummary, // 已有 AI 总结
  withPhotos, // 有照片、无总结
  pastEmpty, // 过去的空白日
  today, // 今日
  future, // 未来（未解锁）
}

/// 由日期 + 元数据推导节点状态（纯函数，单测直接覆盖）。
///
/// 判定顺序有讲究：今日 > 未来 > 有总结 > 有照片 > 空白，
/// 因为「今天」是最强的导航信息，即使它已经有总结也要显示脉冲与徽章。
DayNodeStatus statusOfDay({
  required int dayKey,
  required int todayKey,
  bool hasSummary = false,
  int photoCount = 0,
}) {
  if (dayKey == todayKey) return DayNodeStatus.today;
  if (dayKey > todayKey) return DayNodeStatus.future;
  if (hasSummary) return DayNodeStatus.withSummary;
  if (photoCount > 0) return DayNodeStatus.withPhotos;
  return DayNodeStatus.pastEmpty;
}

/// 状态 → 中文语义（无障碍标签与 tooltip 复用）。
String statusLabelOf(DayNodeStatus status) {
  switch (status) {
    case DayNodeStatus.withSummary:
      return '已总结';
    case DayNodeStatus.withPhotos:
      return '有照片';
    case DayNodeStatus.pastEmpty:
      return '空白日';
    case DayNodeStatus.today:
      return '当前关卡';
    case DayNodeStatus.future:
      return '未解锁';
  }
}

/// 今日圆体比常规大一圈的倍率：视线第一落点要「跳出来」，
/// 但 1.12 控制在命中半径（1.2r）内，不侵占相邻节点的命中圆。
const double kTodayScale = 1.12;

// ============================================================================
// 节点组件
// ============================================================================

/// 单个日节点：五状态视觉的绘制容器，只负责画，不挂任何手势——
/// 点击命中由页面的 Rect 列表层统一处理（不变式，见文件头注释）。
class DayNode extends StatefulWidget {
  /// 节点落点（圆心/半径由布局算法给出，全图等半径）。
  final NodePosition position;

  /// 日期主键 yyyymmdd，同时用于页面侧的 ValueKey 精确定位。
  final int dayKey;

  /// 五状态之一，决定圆体样式、光环与徽章。
  final DayNodeStatus status;

  /// 当日首图路径；为空（或该状态不展示图）时回退为果冻圆。
  final String? thumbPath;

  /// 是否已有 AI 总结——只影响「今日」节点是否补一枚金星徽章
  ///（其它状态本身就是由 hasSummary 推导出来的）。
  final bool hasSummary;

  /// 是否处于按下态（由页面命中层下发，节点自己不挂手势）。
  /// 按下 = 整颗糖扣下移变矮，模拟软糖被按进去。
  final bool pressed;

  const DayNode({
    super.key,
    required this.position,
    required this.dayKey,
    required this.status,
    this.thumbPath,
    this.hasSummary = false,
    this.pressed = false,
  });

  @override
  State<DayNode> createState() => _DayNodeState();
}

class _DayNodeState extends State<DayNode> with SingleTickerProviderStateMixin {
  /// 今日脉冲：1.6s 一个循环，光环扩张并淡出。
  /// 只在 status == today 时启动，避免另外 30 个节点空转耗电。
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(DayNode old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _syncPulse();
  }

  void _syncPulse() {
    if (widget.status == DayNodeStatus.today) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double get _r => widget.position.radius;

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final status = widget.status;
    final hasThumb = widget.thumbPath != null;
    final isToday = status == DayNodeStatus.today;
    // 今日大一圈：圆心不变，只放大绘制半径（布局算法不动，位置不变）。
    final bodyR = isToday ? r * kTodayScale : r;

    return Semantics(
      // 点击由页面统一的命中层负责，这里只负责「读出来是哪一天、什么状态」。
      label: '${dayKeyToChinese(widget.dayKey)}，${statusLabelOf(status)}',
      excludeSemantics: true,
      child: SizedBox(
        width: r * 2,
        height: r * 2,
        child: Stack(
          clipBehavior: Clip.none, // 徽章与光环要溢出节点方块，不能被裁
          alignment: Alignment.center,
          children: [
            if (isToday) _buildPulseRing(bodyR),
            _buildPressed(bodyR, hasThumb: hasThumb),
            if (isToday) _buildLevelBadge(r, bodyR),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 按下反馈（页面命中层下发 pressed，这里只做视觉）
  // ---------------------------------------------------------------------

  /// 按下时以底边为锚缩到 0.92——糖扣「陷进去」，放手回弹。
  /// 用底边锚点而不是中心：中心缩会让人觉得节点在漂，底边缩才像被按住。
  Widget _buildPressed(double bodyR, {required bool hasThumb}) {
    return AnimatedScale(
      scale: widget.pressed ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: _buildCircle(bodyR, hasThumb: hasThumb),
    );
  }

  // ---------------------------------------------------------------------
  // 今日：脉冲光环（糖果粉）
  // ---------------------------------------------------------------------

  Widget _buildPulseRing(double bodyR) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // easeOut 起手快、收尾慢，像光在空气里散开。
        final t = Curves.easeOut.transform(_pulse.value);
        return Transform.scale(scale: 1 + 0.38 * t, child: child);
      },
      child: Container(
        width: (bodyR + 6) * 2,
        height: (bodyR + 6) * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: CandyColors.pink.withValues(alpha: 0.8),
            width: 3.5,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 今日：当前关卡彩带徽章
  // ---------------------------------------------------------------------

  Widget _buildLevelBadge(double r, double bodyR) {
    return Positioned(
      // 外层 Stack 被 SizedBox 钉成 2r 高、圆心在 (r, r)：
      // 放大后的圆底边 = r + bodyR（今日 bodyR = 1.12r ≈ 2.12r 处），
      // 徽章顶边压在圆底边上方 6px（「压在圆下沿」），其余向外探出
      // （行距净空远大于外探量，糊不到下一行）。
      // 几何断言在 calendar_map_test：badgeTop ≥ 2r-8 且 badgeBottom ≥ 2r——
      // r + bodyR - 6 ≥ 2r - 8 恒成立（bodyR ≥ r），r 小到 4 也守住。
      top: r + bodyR - 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          // 彩带徽章：粉底白字，任何皮肤下都是最跳的一枚。
          gradient: CandyColors.pinkFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: outlineNow(),
            width: 2.4,
          ),
          boxShadow: [
            // 实心厚阴影（blur 0）＝玩具贴纸感，不是 Material elevation。
            BoxShadow(
              color: outlineNow().withValues(alpha: 0.9),
              blurRadius: 0,
              offset: const Offset(0, 2.5),
            ),
          ],
        ),
        child: const Text(
          '当前关卡',
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w800,
            // 粉底白字（风格圣经第 8 条）：厚描边已把字框住，白字最醒目。
            color: CandyColors.glossWhite,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 圆体（按状态分流）
  // ---------------------------------------------------------------------

  Widget _buildCircle(double r, {required bool hasThumb}) {
    switch (widget.status) {
      case DayNodeStatus.withSummary:
        return _circle(
          r: r,
          fill: CandyColors.goldFill,
          borderWidth: 4,
          child: hasThumb ? _thumb() : _number(r, onColor: true),
          overlay: _topRight(_starBadge(r)),
        );

      case DayNodeStatus.withPhotos:
        return _circle(
          // 有图白描边：白扣在任何天空上都跳得出。
          r: r,
          fill: CandyColors.creamFill,
          borderColor: CandyColors.glossWhite,
          borderWidth: 4,
          child: hasThumb ? _thumb() : _number(r),
        );

      case DayNodeStatus.pastEmpty:
        // 「无照片记录」专属形态（用户要求有别于有图日）：
        // 整体缩到 0.86 再压到 60% 不透明度——地图上一眼能数出
        // 哪些天有记录、哪些天空着，比只换描边颜色醒目得多。
        return Transform.scale(
          scale: 0.86,
          child: Opacity(
            opacity: 0.6,
            child: _circle(
              r: r,
              fill: CandyColors.creamFill,
              borderWidth: 3,
              child: _number(r),
            ),
          ),
        );

      case DayNodeStatus.today:
        // 今日圆体照常显示内容（有图给图、已总结给星），
        // 光环与徽章在 build() 里外挂，形成「当前关卡」的强调。
        return _circle(
          r: r,
          fill: CandyColors.pinkFill,
          borderWidth: 4,
          child: hasThumb ? _thumb() : _number(r, onColor: true),
          overlay:
              hasThumb && widget.hasSummary ? _topRight(_starBadge(r)) : null,
        );

      case DayNodeStatus.future:
        return _circle(
          r: r,
          fill: CandyColors.grayFill,
          borderWidth: 3.5,
          child: _number(r, alpha: 0.75),
          overlay: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(right: -2, top: -2, child: _lockBadge(r)),
            ],
          ),
        );
    }
  }

  /// 统一的果冻圆形容器：
  /// 果冻渐变填充 + 厚描边（有图态换白描边）+ 底部实心厚阴影。
  ///
  /// Container 在有 border 时会把 border 尺寸自动转成 child 的内边距，
  /// 所以 child（缩略图 / 数字）正好落在内圆里，不必手动算 inset；
  /// [overlay] 用 Positioned.fill 铺满**内圆**，其内部再自行定位角标。
  ///
  /// [borderColor] 为 null 时取当前画风描边（outlineNow）。不能写成默认值：
  /// Dart 的可选参数默认值必须是 const，而描边色是运行时读全局画风得来的。
  Widget _circle({
    required double r,
    required Gradient fill,
    required double borderWidth,
    required Widget child,
    Color? borderColor,
    Widget? overlay,
  }) {
    final line = borderColor ?? outlineNow();
    return Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: fill, // 上亮下暗 = 软糖的受光面
        border: Border.all(color: line, width: borderWidth),
        boxShadow: [
          // 底部实心厚阴影：blur 0 + 当前画风描边色，糖果塔防的「玩具投影」；
          // 禁止 Material elevation（全仓铁律，靠描边+投影自己画层次）。
          BoxShadow(
            color: outlineNow().withValues(alpha: 0.92),
            blurRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClipOval(child: SizedBox.expand(child: child)),
          // 顶部高光弧压在内容之上、徽章之下：像糖面反光。
          Positioned.fill(child: CustomPaint(painter: _TopGlossPainter(r))),
          if (overlay != null) Positioned.fill(child: overlay),
        ],
      ),
    );
  }

  /// 把右上角角标包成「铺满父级 + 定位」的图层。
  Widget _topRight(Widget badge) => Stack(
        clipBehavior: Clip.none,
        children: [Positioned(right: -3, top: -3, child: badge)],
      );

  Widget _thumb() => ThumbImage(
        sourcePath: widget.thumbPath!,
        size: 128,
        placeholderColor: CandyColors.creamDark,
      );

  /// 日号数字：粗体圆润（w800）+ 一圈描边感阴影（模拟细描边字）。
  /// 果冻底上用白字，奶油素扣上用画风描边色字（对比度 ≥ 4.5 的方向）。
  Widget _number(double r, {double alpha = 1, bool onColor = false}) {
    final day = widget.dayKey % 100;
    final base = onColor ? CandyColors.glossWhite : outlineNow();
    // 必须包 Center：裸 Text 放进 SizedBox.expand 会被压成
    // 「宽度顶满 + 高度顶满」，文字按 start 对齐画在左上角（数字错位的根因）。
    return Center(
      child: Text(
      '$day',
      style: TextStyle(
        fontSize: (r * 0.78).clamp(9.0, 34.0).toDouble(),
        fontWeight: FontWeight.w800,
        height: 1.0,
        color: base.withValues(alpha: alpha),
        shadows: [
          Shadow(
            // 白字压深影、深字压淡影：都补一圈「描边」，字不糊在底色上。
            color: outlineNow().withValues(
              alpha: onColor ? 0.45 : 0.25,
            ),
            offset: const Offset(0, 1.2),
            blurRadius: 0,
          ),
        ],
        ),
      ),
    );
  }

  /// 已总结：右上角金色星星徽章（通关令牌）。
  Widget _starBadge(double r) {
    final size = (r * 0.62).clamp(13.0, 30.0).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CandyColors.glossWhite,
        border: Border.all(color: outlineNow(), width: 2.2),
        boxShadow: [
          BoxShadow(
            color: outlineNow().withValues(alpha: 0.9),
            blurRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.star_rounded,
        size: size * 0.72,
        color: CandyColors.gold,
      ),
    );
  }

  /// 未来：右上角小锁泡泡。
  Widget _lockBadge(double r) {
    final size = (r * 0.58).clamp(12.0, 28.0).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CandyColors.glossWhite,
        border: Border.all(color: outlineNow(), width: 2.2),
        boxShadow: [
          BoxShadow(
            color: outlineNow().withValues(alpha: 0.9),
            blurRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.lock_rounded,
        size: size * 0.64,
        color: outlineNow(),
      ),
    );
  }
}

// ============================================================================
// 顶部高光弧
// ============================================================================

/// 沿圆顶部画一段半透明白色圆头弧——软糖/玻璃珠的「高光」。
/// 只画这一层不重绘节点内容（CustomPaint 是叶子，换肤无关时可缓存）。
class _TopGlossPainter extends CustomPainter {
  /// 圆半径（决定弧的半径与笔宽）。
  final double radius;

  _TopGlossPainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stroke = (radius * 0.14).clamp(2.0, 6.0);
    // 弧整体内缩：留出厚描边与高光自己的笔宽，压在果冻填充区上沿。
    final rect = (Offset.zero & size).deflate(stroke + radius * 0.10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round // 圆头线帽 = 糖果感的关键细节
      ..color = CandyColors.glossWhite.withValues(alpha: 0.55);
    // 画布角度：0 = 右、顺时针增大（y 向下），1.5π = 正上方。
    // 起点 1.15π、扫过 0.7π → 弧横跨顶部约 126°。
    canvas.drawArc(rect, math.pi * 1.15, math.pi * 0.7, false, paint);
  }

  @override
  bool shouldRepaint(_TopGlossPainter old) => old.radius != radius;
}
