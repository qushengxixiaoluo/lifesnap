/// 太阳光束 painter：放射状光束 + 中心光斑，4s 一个呼吸来回，screen 混合叠加。
///
/// 画法思路（新海诚式的通透光感）：
/// 1) 光是「加光」不是盖漆——先 saveLayer 并指定 BlendMode.screen，
///    光束叠回天空时只提亮底色、不遮盖渐变，才有穿透感；
/// 2) 九束光合成一条 Path，用「以太阳为中心向外衰减」的径向渐变一把画完，
///    避免逐束创建 shader 的开销；
/// 3) 呼吸 = sin(2π·elapsed/4s)。基循环 60s ÷ 4s = 15 个整周期，
///    循环回到 0 时相位严格连续，不会在缝上突然跳亮；
/// 4) 光束角度/长度按固定种子生成 + 极缓的整周期摇摆，手绘感与稳定并存。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SunRaysPainter extends CustomPainter {
  SunRaysPainter({
    required this.progress,
    required this.opacity,
    required this.glow,
  });

  /// 0~1 的 60s 循环相位。
  final double progress;

  /// 换肤 crossfade 得出的透明度：星夜无日光（0 时直接跳过整层绘制）。
  final double opacity;

  /// 光束/光斑颜色（日光辉或黄昏金）。
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.003 || size.isEmpty) return;

    // 太阳纵向位置（占画布高度比例）：中心点与下方光束径向渐变的 Alignment
    // 共用这一个常量——单一事实来源。原先渐变中心写成
    // (height*0.30/height)*2-1（height 相除恒等于 -0.4 的常量），
    // 只改 center 的 0.30 时渐变中心不会跟着动，加光与光源会悄然脱节。
    const sunYFrac = 0.30;
    final center = Offset(size.width * 0.5, size.height * sunYFrac);

    // 4s 呼吸：60s 基周期内正好 15 个整周期 → 循环点连续
    final breath = 0.5 + 0.5 * math.sin(progress * math.pi * 2 * 15);
    final rayAlpha = opacity * (0.14 + 0.26 * breath);

    // screen 混合：本层内容只做加亮合成，不覆盖下面的天空渐变
    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.screen);

    // 中心光斑：径向渐变由内向外化开，边缘融进天空
    final glowRadius = math.min(size.width, size.height) * 0.34;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glow.withValues(alpha: 0.55 * opacity * (0.7 + 0.3 * breath)),
          glow.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 九束光：角度微差由种子决定；sway 是整周期缓摆（sin(2π·progress)），循环无缝
    final rng = math.Random(5709);
    double jitter() => (rng.nextDouble() - 0.5) * 6.0;
    final maxLen = math.max(size.width, size.height) * 1.05;
    final rays = Path();
    for (var i = 0; i < 9; i++) {
      final base = i * (math.pi * 2 / 9) + (rng.nextDouble() - 0.5) * 0.24;
      final sway = math.sin(progress * math.pi * 2) * 0.035;
      final angle = base + sway;
      final halfWidth = 0.05 + rng.nextDouble() * 0.05;
      final len = maxLen * (0.70 + rng.nextDouble() * 0.30);

      final apex = center + Offset(jitter(), jitter());
      final leftTip = center +
          Offset(math.cos(angle - halfWidth) * len,
                 math.sin(angle - halfWidth) * len) +
          Offset(jitter(), jitter());
      final rightTip = center +
          Offset(math.cos(angle + halfWidth) * len,
                 math.sin(angle + halfWidth) * len) +
          Offset(jitter(), jitter());
      // 两条边中点各带抖动外凸的二次贝塞尔：比直线更像手绘光束
      final midLeft = Offset(
        (apex.dx + leftTip.dx) / 2 + jitter(),
        (apex.dy + leftTip.dy) / 2 + jitter(),
      );
      final midRight = Offset(
        (apex.dx + rightTip.dx) / 2 + jitter(),
        (apex.dy + rightTip.dy) / 2 + jitter(),
      );

      rays
        ..moveTo(apex.dx, apex.dy)
        ..quadraticBezierTo(midLeft.dx, midLeft.dy, leftTip.dx, leftTip.dy)
        ..lineTo(rightTip.dx, rightTip.dy)
        ..quadraticBezierTo(midRight.dx, midRight.dy, apex.dx, apex.dy)
        ..close();
    }

    // 光束上色：以太阳为圆心的径向渐变，根部亮、梢部化掉
    final rayPaint = Paint()
      ..shader = RadialGradient(
        // Alignment 纵轴 [-1,1] 对应 [0,height]：太阳在 sunYFrac*height 处
        center: Alignment(0, sunYFrac * 2 - 1),
        radius: 1.2,
        colors: [
          glow.withValues(alpha: rayAlpha),
          glow.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(rays, rayPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(SunRaysPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.opacity != opacity ||
      oldDelegate.glow != glow;

  @override
  // 纯装饰层没有语义，恒 false 避免呼吸动画期间每帧触发语义树更新
  bool shouldRebuildSemantics(SunRaysPainter oldDelegate) => false;
}
