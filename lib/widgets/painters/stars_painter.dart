/// 星空 painter：固定种子生成的星星，各自以 2~5s 的随机相位闪烁。
///
/// 画法思路：
/// 1) 星位/大小/周期/相位全部来自固定种子——每次绘制完全一致，不会帧间乱跳；
/// 2) 周期取 60/n（n∈[12,30]）而非任意小数：基循环是 60s，
///    周期不整除 60 的话，循环回到 0 时所有星星相位会突变（集体闪一下）；
///    60/n 既落在 2~5s 区间，又保证循环点严格连续；
/// 3) 亮度曲线用 sin(π·k)，k∈[0,1]：在缝合点两侧亮度都归到最低，连续无跳变；
/// 4) 亮星在峰值时叠十字星芒，是新海诚夜空的标志性闪法。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class StarsPainter extends CustomPainter {
  StarsPainter({
    required this.progress,
    required this.opacity,
    required this.color,
  });

  /// 0~1 的 60s 循环相位。
  final double progress;

  /// 换肤 crossfade 得出的透明度：非星夜为 0（该层不挂载）。
  final double opacity;

  /// 星色（星白）。
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.003 || size.isEmpty) return;

    const count = 44;
    final rng = math.Random(20260930); // 固定种子：星位每次绘制一致
    final maxY = size.height * 0.62; // 只撒在天区，草坡上不落星

    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * maxY;
      final radius = 0.7 + rng.nextDouble() * 1.4;
      final cycles = 12 + rng.nextInt(19); // 60/cycles ∈ [2,5]s 且整除 60
      final phase = rng.nextDouble();
      final base = 0.55 + rng.nextDouble() * 0.45; // 每颗星的基础亮度差异

      final k = (progress * cycles + phase) % 1.0;
      final twinkle = math.sin(math.pi * k); // 0→1→0，缝合点两侧同为 0
      final alpha = opacity * base * (0.15 + 0.85 * twinkle);
      if (alpha <= 0.012) continue;

      final paint = Paint()..color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);

      // 亮星加十字星芒：只在接近峰值时出现，闪烁更有节奏
      if (radius > 1.65 && twinkle > 0.55) {
        final spark = Paint()
          ..color = color.withValues(alpha: alpha * 0.55)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        final len = radius * 3.4;
        canvas.drawLine(Offset(x - len, y), Offset(x + len, y), spark);
        canvas.drawLine(Offset(x, y - len), Offset(x, y + len), spark);
      }
    }
  }

  @override
  bool shouldRepaint(StarsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.opacity != opacity ||
      oldDelegate.color != color;

  @override
  // 纯装饰层没有语义，恒 false 避免闪烁动画期间每帧触发语义树更新
  bool shouldRebuildSemantics(StarsPainter oldDelegate) => false;
}
