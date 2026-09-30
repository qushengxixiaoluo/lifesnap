/// 宣纸噪点层 painter（静态）：明暗细点 + 几缕横向纤维纹。
///
/// 画法思路：
/// 1) 为什么静态——噪点一动就变成电视雪花，宣纸的肌理必须「钉」在画面上；
///    固定种子只在同一尺寸下生成同一图案，shouldRepaint 除尺寸外恒 false，
///    循环动画的每帧重建完全不会惊动这一层（它从不重绘）；
/// 2) 明暗两种点交错：亮点模拟纸面反光的纤维白，暗点模拟纸浆的杂点，
///    透明度压在 2%~5% 之间——盖在任何皮肤的天空上都只是「质感」不是「脏」；
/// 3) 纤维纹用极淡的横向划痕，手抄纸的帘纹方向感。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hand_draw.dart';

class PaperGrainPainter extends CustomPainter {
  const PaperGrainPainter({this.seed = 4207});

  /// 图案种子：换种子等于换一张纸。
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rng = math.Random(seed);

    // 点数随面积缩放：小窗不浪费、大屏不稀疏
    final dots = (size.width * size.height / 700).clamp(260, 1100).toInt();
    for (var i = 0; i < dots; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final light = rng.nextBool();
      final alpha = 0.018 + rng.nextDouble() * 0.034;
      final r = 0.6 + rng.nextDouble() * 1.3;
      final color = light ? const Color(0xFFFFFFFF) : const Color(0xFF2A2114);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = color.withValues(alpha: alpha));
    }

    // 横向纤维纹：八道极淡的短划痕，纸张的帘纹
    for (var i = 0; i < 8; i++) {
      final y = rng.nextDouble() * size.height;
      final x0 = rng.nextDouble() * size.width;
      final len = 40 + rng.nextDouble() * 160;
      canvas.drawLine(
        Offset(x0, y),
        Offset(x0 + len, y + handJitter(rng, 2.5)),
        handStroke(color: const Color(0xFF2A2114), width: 1.0, alpha: 0.03),
      );
    }
  }

  @override
  bool shouldRepaint(PaperGrainPainter oldDelegate) =>
      oldDelegate.seed != seed;

  @override
  // 静态纹理没有语义，恒 false
  bool shouldRebuildSemantics(PaperGrainPainter oldDelegate) => false;
}
