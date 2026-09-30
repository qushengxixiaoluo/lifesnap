/// 底部双层草坡 painter（换肤变色、不参与循环动画）。
///
/// 画法思路：
/// 1) 每层坡 = 两个不同频率正弦叠加的剖面线，按 6px 步长采样成折线，
///    顶点带固定种子抖动（横向 ±1.6px、纵向 ±2.4px）——视觉上是
///    「手抖画出来的一笔」而不是数学上完美的曲线；
/// 2) 远坡混入地平线光（更亮更灰）制造空气透视，近坡用纯草色压住画面底部；
/// 3) 近坡顶缘画草叶小簇：三根一撮的二次贝塞尔甩笔，让坡线不呆板；
/// 4) 该层没有 progress 参数：循环 tick 时指纹不变，shouldRepaint 恒 false，
///    云动/星闪都不会惊动它，只有换肤的 600ms crossfade 才逐帧重绘。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import 'hand_draw.dart';

class HillsPainter extends CustomPainter {
  HillsPainter({
    required this.back,
    required this.front,
    this.seed = 7001,
  });

  /// 远坡色（草色混地平线光）。
  final Color back;

  /// 近坡色（纯草色）。
  final Color front;

  /// 顶点抖动种子。
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 先远后近：远坡先画，被近坡自然遮挡出层次（无 Material 阴影）
    _drawHill(
      canvas,
      size,
      baseFrac: 0.75,
      ampFrac: 0.042,
      phase: 0.7,
      fill: back,
      strokeAlpha: 0.18,
      seed: seed,
      tufts: false,
    );
    _drawHill(
      canvas,
      size,
      baseFrac: 0.87,
      ampFrac: 0.055,
      phase: 2.3,
      fill: front,
      strokeAlpha: 0.34,
      seed: seed + 1,
      tufts: true,
    );
  }

  /// 画一层坡：剖面采样 → 填充体（封到画布底）→ 顶缘描边 + 铅笔复线。
  void _drawHill(
    Canvas canvas,
    Size size, {
    required double baseFrac,
    required double ampFrac,
    required double phase,
    required Color fill,
    required double strokeAlpha,
    required int seed,
    required bool tufts,
  }) {
    final rng = math.Random(seed);
    final w = size.width;
    final h = size.height;

    // 剖面函数：两个不同频率的正弦叠加，起伏不重复、不机械
    double profile(double x) {
      final u = x / w;
      return baseFrac * h -
          ampFrac * h *
              (0.62 * math.sin(u * math.pi * 2 * 1.15 + phase) +
                  0.38 * math.sin(u * math.pi * 2 * 2.6 + phase * 1.7));
    }

    final fillPath = Path();
    final edgePath = Path();
    for (var x = -6.0; x <= w + 6; x += 6) {
      final px = x + handJitter(rng, 1.6);
      final py = profile(x) + handJitter(rng, 2.4);
      if (x <= -6.0) {
        fillPath.moveTo(px, py);
        edgePath.moveTo(px, py);
      } else {
        fillPath.lineTo(px, py);
        edgePath.lineTo(px, py);
      }
    }

    // 填充体向下封到画布外，保证坡底没有缝
    fillPath
      ..lineTo(w + 8, h + 8)
      ..lineTo(-8, h + 8)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fill);

    // 顶缘主描边（墨棕，像钢笔勾过的轮廓）
    canvas.drawPath(
      edgePath,
      handStroke(color: ShiguangColors.inkBrown, width: 1.4, alpha: strokeAlpha),
    );
    // 铅笔复线：整体错位一点再压一条更淡的粗线
    canvas.drawPath(
      edgePath.shift(const Offset(1.2, 1.6)),
      handStroke(color: ShiguangColors.inkBrown, width: 2.6, alpha: strokeAlpha * 0.55),
    );

    if (tufts) {
      _drawTufts(canvas, profile, rng, w);
    }
  }

  /// 近坡顶缘撒六撮草叶：三根一撮，二次贝塞尔向天甩出。
  void _drawTufts(
    Canvas canvas,
    double Function(double x) profile,
    math.Random rng,
    double w,
  ) {
    final ink = Color.lerp(ShiguangColors.leafDark, ShiguangColors.inkBrown, 0.35)!;
    for (var i = 0; i < 6; i++) {
      final tx = w * (0.07 + 0.16 * i) + handJitter(rng, 16);
      final ty = profile(tx) + 2;
      final blades = Path();
      for (var b = 0; b < 3; b++) {
        final dx = (b - 1) * 5.5 + handJitter(rng, 3);
        final len = 9 + rng.nextDouble() * 8;
        blades
          ..moveTo(tx, ty)
          ..quadraticBezierTo(
            tx + dx * 0.5,
            ty - len * 0.55,
            tx + dx,
            ty - len,
          );
      }
      canvas.drawPath(
        blades,
        handStroke(color: ink, width: 1.5, alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(HillsPainter oldDelegate) =>
      oldDelegate.back != back ||
      oldDelegate.front != front ||
      oldDelegate.seed != seed;

  @override
  // 纯装饰层没有语义，恒 false 避免换肤过渡期无谓的语义树更新
  bool shouldRebuildSemantics(HillsPainter oldDelegate) => false;
}
