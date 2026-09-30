/// 天空层 painter：糖果 = 三段垂直渐变，LowPoly = 三段硬边平涂色带。
///
/// 画法思路：
/// - candy：新海诚的天空靠「上冷下暖」的三段色建立光感——天顶压冷色、
///   地平线托暖光，中间段停在约 52% 处（略高于画面中线），让亮部集中在
///   地图内容所在的中下区域；
/// - lowPoly：低多边形的天空是**平涂色块**，同样的三段色改成三条水平硬边带
///   （不做羽化渐变、不压暗角——色块必须干净），分界沿用渐变的观感节奏。
///
/// 该层不做循环动画，只在换肤 crossfade 的 600ms 内逐帧变色，
/// 所以 shouldRepaint 比较颜色指纹 + poly（形状开关），循环 tick 不会惊动它。
library;

import 'package:flutter/material.dart';

class SkyGradientPainter extends CustomPainter {
  SkyGradientPainter({
    required this.top,
    required this.mid,
    required this.horizon,
    this.poly = 0,
  });

  /// 天顶色。
  final Color top;

  /// 中段色。
  final Color mid;

  /// 地平线色。
  final Color horizon;

  /// LowPoly 度 0~1：0 = 糖果渐变，≥0.5 = 三段硬边色带。
  ///
  /// 形状没法逐帧插值，所以取「crossfade 过半即换形」的阈值——
  /// 阈值点前后颜色仍在 lerp，肉眼看到的是色带逐渐分化而不是硬跳。
  final double poly;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    if (poly >= 0.5) {
      // LowPoly：三条水平硬边带（分界 44% / 74%），纯平涂，无渐变无暗角
      final band = Paint();
      void drawBand(double from, double to, Color color) {
        band.color = color;
        canvas.drawRect(
          Rect.fromLTRB(0, size.height * from, size.width, size.height * to),
          band,
        );
      }

      drawBand(0, 0.44, top);
      drawBand(0.44, 0.74, mid);
      drawBand(0.74, 1, horizon);
      return;
    }

    // 三段渐变：stop 停在 0.52 而非 0.5，给地平线暖光带留更宽的呼吸区
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, mid, horizon],
      stops: const [0.0, 0.52, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);

    // 顶部极淡压深：像宣纸吸光的暗角，把视线压向画面中下部的地图内容。
    // 用渐变而非 Material 阴影——整个画风禁止用 elevation 造层次。
    final vignette = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF000000).withValues(alpha: 0.05),
        const Color(0xFF000000).withValues(alpha: 0),
      ],
      stops: const [0.0, 0.38],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = vignette);
  }

  @override
  bool shouldRepaint(SkyGradientPainter oldDelegate) =>
      oldDelegate.top != top ||
      oldDelegate.mid != mid ||
      oldDelegate.horizon != horizon ||
      oldDelegate.poly != poly;

  @override
  // 纯装饰层没有语义，恒 false 避免动画期间每帧触发语义树更新
  bool shouldRebuildSemantics(SkyGradientPainter oldDelegate) => false;
}
