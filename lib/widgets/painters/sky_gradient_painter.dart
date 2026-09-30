/// 天空渐变层 painter：三段垂直线性渐变（天顶 → 中段 → 地平线）。
///
/// 画法思路：新海诚的天空靠「上冷下暖」的三段色建立光感——
/// 天顶压冷色、地平线托暖光，中间段停在约 52% 处（略高于画面中线），
/// 让亮部集中在地图内容所在的中下区域。
/// 该层不做循环动画，只在换肤 crossfade 的 600ms 内逐帧变色，
/// 所以 shouldRepaint 只比较三个颜色指纹，循环 tick 完全不会惊动它。
library;

import 'package:flutter/material.dart';

class SkyGradientPainter extends CustomPainter {
  SkyGradientPainter({
    required this.top,
    required this.mid,
    required this.horizon,
  });

  /// 天顶色。
  final Color top;

  /// 中段色。
  final Color mid;

  /// 地平线色。
  final Color horizon;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

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
      oldDelegate.horizon != horizon;

  @override
  // 纯装饰层没有语义，恒 false 避免动画期间每帧触发语义树更新
  bool shouldRebuildSemantics(SkyGradientPainter oldDelegate) => false;
}
