/// 闯关地图 · 单个日节点（五种状态的视觉实现）
///
/// 五种状态与视觉语义：
/// | 状态 | 视觉 | 为什么这样画 |
/// |------|------|--------------|
/// | [DayNodeStatus.withSummary] | 圆形裁切首图 + 金描边 + 金勾 | 有总结 = 通关，金色是完成令牌 |
/// | [DayNodeStatus.withPhotos]  | 圆形裁切首图 + 白描边          | 有素材未总结 = 待办，白描边够醒目 |
/// | [DayNodeStatus.pastEmpty]   | 纸色空心圆 + 数字              | 过去空白日 = 纸面留白，不刺眼 |
/// | [DayNodeStatus.today]       | 脉冲光环 + 「当前关卡」徽章    | 只有今日会动，视线第一落点 |
/// | [DayNodeStatus.future]      | 雾化 + 小锁                   | 未解锁的关卡，暗示「还没到」 |
///
/// 性能取舍：
/// - 脉冲用独立 AnimationController（1.6s 循环），只重绘自己这一个小方块；
///   外层由页面包 RepaintBoundary，天空与路径层完全不参与重绘。
/// - 节点自身**不挂手势**：命中统一交给页面的 Rect 列表层，
///   既避免 31 个 GestureDetector 抢手势竞技场，也让命中逻辑可批量测试。
library;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import '../../core/models/models.dart';
import '../../core/thumbnails/thumb_image.dart';
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

  /// 当日首图路径；为空（或该状态不展示图）时回退为纸色圆。
  final String? thumbPath;

  /// 是否已有 AI 总结——只影响「今日」节点是否补一枚金勾
  ///（其它状态本身就是由 hasSummary 推导出来的）。
  final bool hasSummary;

  const DayNode({
    super.key,
    required this.position,
    required this.dayKey,
    required this.status,
    this.thumbPath,
    this.hasSummary = false,
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
            if (status == DayNodeStatus.today) _buildPulseRing(r),
            _buildCircle(r, hasThumb: hasThumb),
            if (status == DayNodeStatus.today) _buildLevelBadge(r),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 今日：脉冲光环
  // ---------------------------------------------------------------------

  Widget _buildPulseRing(double r) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // easeOut 起手快、收尾慢，像光在空气里散开。
        final t = Curves.easeOut.transform(_pulse.value);
        return Transform.scale(scale: 1 + 0.38 * t, child: child);
      },
      child: Container(
        width: (r + 6) * 2,
        height: (r + 6) * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ShiguangColors.todayPulse.withValues(alpha: 0.8),
            width: 3,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 今日：当前关卡徽章
  // ---------------------------------------------------------------------

  Widget _buildLevelBadge(double r) {
    return Positioned(
      // 外层 Stack 被 SizedBox 钉成 2r 高、圆体占满 [0, 2r]，所以偏移必须以
      // 2r 为基准：顶边 = 圆底边上方 6px（「压在圆下沿」），其余 ~14px 向外探出
      // （行距净空 ≈75px，远大于外探量，糊不到下一行）。
      // 曾误写成 top: r - 6（把 2r 的偏移写成了 r），药丸落在节点垂直中部、
      // 正好盖住今日的日号数字——今日是视线第一落点，几何断言已进单测防回归。
      top: r * 2 - 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ShiguangColors.todayPulse,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ShiguangColors.paper.withValues(alpha: 0.9),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: ShiguangColors.inkBrown.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const Text(
          '当前关卡',
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w700,
            // 金底深字：任何皮肤下都清晰，且不随换肤变白而丢失对比度。
            color: ShiguangColors.inkBrown,
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
          fill: ShiguangColors.paper,
          borderColor: ShiguangColors.completedGold,
          borderWidth: 2.6,
          child: hasThumb ? _thumb() : _number(r),
          overlay: _topRight(_checkBadge(r)),
        );

      case DayNodeStatus.withPhotos:
        return _circle(
          r: r,
          fill: ShiguangColors.paper,
          borderColor: ShiguangColors.cloudWhite, // 白描边在蓝天上最跳
          borderWidth: 2.4,
          child: hasThumb ? _thumb() : _number(r),
        );

      case DayNodeStatus.pastEmpty:
        return _circle(
          r: r,
          // 「纸色空心圆」：纸底微透，天空能透出来，但数字仍清晰。
          fill: ShiguangColors.paper.withValues(alpha: 0.88),
          borderColor: ShiguangColors.wood.withValues(alpha: 0.8),
          borderWidth: 2,
          child: _number(r),
        );

      case DayNodeStatus.today:
        // 今日圆体照常显示内容（有图给图、已总结给勾），
        // 光环与徽章在 build() 里外挂，形成「当前关卡」的强调。
        return _circle(
          r: r,
          fill: ShiguangColors.paper,
          borderColor: ShiguangColors.todayPulse,
          borderWidth: 3,
          child: hasThumb ? _thumb() : _number(r),
          overlay: hasThumb && widget.hasSummary ? _topRight(_checkBadge(r)) : null,
        );

      case DayNodeStatus.future:
        return _circle(
          r: r,
          fill: ShiguangColors.paper.withValues(alpha: 0.55),
          borderColor: ShiguangColors.futureMist.withValues(alpha: 0.9),
          borderWidth: 2,
          child: _number(r, alpha: 0.75),
          // 雾化叠层：自下而上越来越浓，像关卡被雾锁住。
          overlay: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        ShiguangColors.futureMist.withValues(alpha: 0.18),
                        ShiguangColors.futureMist.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(right: -2, top: -2, child: _lockBadge(r)),
            ],
          ),
        );
    }
  }

  /// 统一的圆形容器。
  ///
  /// Container 在有 border 时会把 border 尺寸自动转成 child 的内边距，
  /// 所以 child（缩略图 / 数字）正好落在内圆里，不必手动算 inset；
  /// [overlay] 用 Positioned.fill 铺满**内圆**，其内部再自行定位角标。
  Widget _circle({
    required double r,
    required Color fill,
    required Color borderColor,
    required double borderWidth,
    required Widget child,
    Widget? overlay,
  }) {
    return Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          // 轻投影 = 手绘贴纸浮在地图上；星夜皮肤下也能和背景拉开层次。
          BoxShadow(
            color: ShiguangColors.inkBrown.withValues(alpha: 0.22),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClipOval(child: SizedBox.expand(child: child)),
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
        placeholderColor: ShiguangColors.paperDeep,
      );

  Widget _number(double r, {double alpha = 1}) {
    final day = widget.dayKey % 100;
    return Text(
      '$day',
      style: TextStyle(
        fontSize: (r * 0.78).clamp(9.0, 34.0).toDouble(),
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: ShiguangColors.inkBrown.withValues(alpha: alpha),
      ),
    );
  }

  /// 已总结：右上角金色勾。
  Widget _checkBadge(double r) {
    final size = (r * 0.62).clamp(13.0, 30.0).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ShiguangColors.completedGold,
        border: Border.all(
          color: ShiguangColors.paper.withValues(alpha: 0.95),
          width: 1.6,
        ),
      ),
      child: Icon(
        Icons.check_rounded,
        size: size * 0.68,
        color: ShiguangColors.paper,
      ),
    );
  }

  /// 未来：右上角小锁。
  Widget _lockBadge(double r) {
    final size = (r * 0.58).clamp(12.0, 28.0).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ShiguangColors.futureMist,
        border: Border.all(
          color: ShiguangColors.paper.withValues(alpha: 0.9),
          width: 1.4,
        ),
      ),
      child: Icon(
        Icons.lock_rounded,
        size: size * 0.62,
        color: ShiguangColors.inkBrown,
      ),
    );
  }
}
