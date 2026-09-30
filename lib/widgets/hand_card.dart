/// 手绘风卡片组件（A 轨交付版）。
///
/// 【钉死的签名】E 轨详情/设置面板盲写对接：水彩纸底 + 手绘描边 + 可选点击。
///
/// 设计取舍：
/// 1) 颜色走 Theme（colorScheme.surface / outline）而不是写死纸色——
///    星夜皮肤下 surface 自动转深墨蓝，卡片不会在深夜顶着一块白纸刺眼；
///    日间/黄昏则回到水彩纸本色。单一颜色来源在 app_theme.dart；
/// 2) 层次全靠「手绘投影 + 二次描边」自己画：投影是偏移 3.5/4.5px 的
///    极淡墨棕一笔，不是 Material elevation 阴影（全仓禁止用默认阴影造层次）；
/// 3) 描边是抖动边：沿圆角矩形轮廓按弧长采样，逐点向法线方向按固定种子
///    偏移 ±1.4px——每次重建抖动一致，不闪；再压一条错位的铅笔复线。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_style.dart';
import 'painters/hand_draw.dart';

class HandCard extends StatelessWidget {
  const HandCard({super.key, required this.child, this.padding, this.onTap});

  /// 卡片内容。
  final Widget child;

  /// 内边距（默认 16，与阶段 0 桩一致）。
  final EdgeInsetsGeometry? padding;

  /// 点击回调：null 时整卡不可点（详情页纯展示用）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = CustomPaint(
      painter: _HandCardPainter(
        fill: scheme.surface,
        line: scheme.outline,
        shadow: ShiguangColors.inkBrown,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      // opaque：内边距区域也算命中，点卡片空白处也有反馈
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

/// 卡片绘制：手绘投影 → 水彩纸底 → 抖动描边 + 铅笔复线。
class _HandCardPainter extends CustomPainter {
  _HandCardPainter({
    required this.fill,
    required this.line,
    required this.shadow,
  });

  /// 纸底色（来自主题，随皮肤深浅）。
  final Color fill;

  /// 描边色。
  final Color line;

  /// 手绘投影色（墨棕）。
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // 四边各留 6px：给偏移投影和描边笔宽留出墨量，不被画布边缘裁掉
    final rect = (Offset.zero & size).deflate(6);
    final path = _jitteredRRect(rect, 16, 1.4, 9527);

    // 1) 手绘投影：向右下错一笔极淡的墨——纸片「浮」起来（非 Material 阴影）
    canvas.drawPath(
      path.shift(const Offset(3.5, 4.5)),
      Paint()..color = shadow.withValues(alpha: 0.09),
    );

    // 2) 水彩纸底：纯色平涂
    canvas.drawPath(path, Paint()..color = fill);

    // 3) 纸张厚度：底部一线极淡暗边，卡片才像一张有厚度的纸
    final rectPath = path.getBounds();
    final edge = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF000000).withValues(alpha: 0),
        const Color(0xFF000000).withValues(alpha: 0.055),
      ],
    ).createShader(rectPath);
    canvas.drawPath(path, Paint()..shader = edge);

    // 4) 手绘主描边（抖动边）+ 铅笔复线，草稿感的两件套
    canvas.drawPath(path, handStroke(color: line, width: 1.5, alpha: 0.85));
    canvas.drawPath(
      path.shift(const Offset(1.1, 1.4)),
      handStroke(color: line, width: 2.6, alpha: 0.22),
    );
  }

  /// 沿圆角矩形轮廓采样成抖动折线：
  /// 每 12px 取一个点，沿法线按固定种子偏移 ±amp。
  /// 用 PathMetrics 取法线而不是自己算——圆角处的法线方向才正确。
  Path _jitteredRRect(Rect rect, double radius, double amp, int seed) {
    final rng = math.Random(seed);
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    final out = Path();
    var started = false;
    for (final metric in base.computeMetrics()) {
      final len = metric.length;
      if (len <= 0) continue;
      final steps = math.max(12, math.min(120, (len / 12).ceil()));
      for (var i = 0; i <= steps; i++) {
        final tangent = metric.getTangentForOffset(len * i / steps);
        if (tangent == null) continue;
        // Tangent 没有现成法线：把切向量转 90° 再归一化即得（抖动是 ±对称的，
        // 取哪个方向的垂线都得到同样幅度的手绘毛边）
        final v = tangent.vector;
        final normal =
            v == Offset.zero ? Offset.zero : Offset(-v.dy, v.dx) / v.distance;
        final off = handJitter(rng, amp);
        final p = tangent.position + normal * off;
        if (!started) {
          out.moveTo(p.dx, p.dy);
          started = true;
        } else {
          out.lineTo(p.dx, p.dy);
        }
      }
    }
    if (!started) out.addRect(rect); // 理论到不了：空路径时兜底，避免画出空卡
    out.close();
    return out;
  }

  @override
  bool shouldRepaint(_HandCardPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.line != line ||
      oldDelegate.shadow != shadow;

  @override
  // 纯装饰没有语义，恒 false
  bool shouldRebuildSemantics(_HandCardPainter oldDelegate) => false;
}
