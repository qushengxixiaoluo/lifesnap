/// 云层 painter：三朵云随 60s 基循环做水平漂移。
///
/// candy 画法（poly < 0.5）：
/// 1) 云形 = 微起伏底边 + 三段大 puff 的贝塞尔顶缘，所有锚点/控制点按固定种子抖动
///    —— 每次绘制形状完全一致（帧间不闪），但边缘带手绘毛边；
/// 2) 上色分三笔：先填云白，再压一圈主描边，最后错位一条更淡更粗的铅笔复线
///    （模拟草稿的双线感），全部 round cap/join。
///
/// lowPoly 画法（poly ≥ 0.5）：多边形云——六边形冠 + 梯形底两个平涂面
/// （底面暗一档），轮廓与接缝一律黑描边，不用曲线、不用复线。
///
/// 两种画法共用「跨距取模」漂移：progress 走完整数个跨距（含左右出屏余量），
/// 循环回到 0 时位置严格连续，看不出接缝。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hand_draw.dart';

/// 一朵云的静态配置（私有：只服务本 painter）。
class _CloudSpec {
  const _CloudSpec({
    required this.baseX,
    required this.yFrac,
    required this.scale,
    required this.seed,
  });

  /// 初始相位（0~1，跨距比例）——决定云的出发位置。
  final double baseX;

  /// 垂直位置（屏高比例），全部落在草坡之上。
  final double yFrac;

  /// 尺寸倍率：近云大、远云小，制造纵深。
  final double scale;

  /// 形状抖动种子。
  final int seed;
}

/// 三朵云错开相位与高度，避免同屏挤在一起或彼此重叠。
const List<_CloudSpec> _clouds = [
  _CloudSpec(baseX: 0.06, yFrac: 0.15, scale: 1.10, seed: 1103),
  _CloudSpec(baseX: 0.44, yFrac: 0.31, scale: 0.76, seed: 2207),
  _CloudSpec(baseX: 0.76, yFrac: 0.47, scale: 0.92, seed: 3301),
];

/// 出屏余量：云完全移出右沿后才取模回左侧，保证进出屏不穿帮。
const double _margin = 320.0;

class CloudPainter extends CustomPainter {
  CloudPainter({
    required this.progress,
    required this.fill,
    required this.line,
    this.poly = 0,
  });

  /// 0~1 的 60s 循环相位（由 SkyBackground 的唯一循环控制器推导）。
  final double progress;

  /// 云填充色（换肤时随之变化：星夜下云转月光灰蓝）。
  final Color fill;

  /// 描边色。
  final Color line;

  /// LowPoly 度 0~1：过 0.5 换成多边形云（形状不插值，颜色照常 lerp）。
  final double poly;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // 跨距 = 屏宽 + 左右各一份余量；progress 走完一整圈即无缝回到起点
    final span = size.width + _margin * 2;

    for (final spec in _clouds) {
      final w = 240.0 * spec.scale;
      final h = 88.0 * spec.scale;
      final x = -_margin + ((spec.baseX + progress) * span) % span;
      final y = size.height * spec.yFrac;

      canvas.save();
      canvas.translate(x, y);

      if (poly >= 0.5) {
        _paintPolyCloud(canvas, w, h, spec.seed);
      } else {
        _paintHandCloud(canvas, w, h, spec.seed);
      }

      canvas.restore();
    }
  }

  /// candy 一笔：填充 → 主描边 → 错位铅笔复线（草稿感的三件套）。
  void _paintHandCloud(Canvas canvas, double w, double h, int seed) {
    final path = _cloudPath(w, h, seed);
    // 第一笔：云体填充（微透，让天空的光透上来一点）
    canvas.drawPath(path, Paint()..color = fill.withValues(alpha: 0.94));
    // 第二笔：主描边，勾出手绘轮廓
    canvas.drawPath(path, handStroke(color: line, width: 1.6, alpha: 0.55));
    // 第三笔：铅笔复线——错开约 1.5px 再描一条更淡的粗线，草稿感的关键
    canvas.translate(1.5, 1.8);
    canvas.drawPath(path, handStroke(color: line, width: 2.8, alpha: 0.16));
  }

  /// LowPoly 一笔：六边形冠（上块）+ 梯形底（下块）两块平涂面，
  /// 底面压暗一档造出「折下来的那个面」，块面与接缝统一黑描边。
  void _paintPolyCloud(Canvas canvas, double w, double h, int seed) {
    final (crown, base) = _polyCloudPaths(w, h, seed);
    final ink = line; // 此时 line 已是 #141414（SkyBackground 按 poly 插值过来）

    canvas.drawPath(crown, Paint()..color = fill);
    canvas.drawPath(
      base,
      Paint()
        ..color = Color.lerp(fill, const Color(0xFF1F3B63), 0.18)!.withValues(alpha: 1),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = ink;
    canvas.drawPath(crown, stroke);
    canvas.drawPath(base, stroke);
  }

  /// 多边形云的两个闭合面：整朵云的折线外轮廓 + 压在下缘的暗面梯形。
  ///
  /// 暗面**叠画**在外轮廓之上（而不是拼接），两块共用底边顶点——
  /// 这样无论折线怎么抖都不会在接缝处漏出天空底色。
  /// 锚点只抖 ±1.6px：折线要「硬」，抖多了就软回手绘云了。
  (Path, Path) _polyCloudPaths(double w, double h, int seed) {
    final rng = math.Random(seed);
    Offset pt(double x, double y) =>
        Offset(x * w + handJitter(rng, 1.6), y * h + handJitter(rng, 1.6));

    Path polygon(List<(double, double)> pts) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = pt(pts[i].$1, pts[i].$2);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      return path;
    }

    // 外轮廓：三处鼓包全部用折线（六边形冠 + 折线收底）
    final crown = polygon(const [
      (0.04, 0.68),
      (0.14, 0.34),
      (0.38, 0.10),
      (0.66, 0.06),
      (0.88, 0.26),
      (1.00, 0.54),
      (0.92, 0.84),
      (0.50, 0.94),
      (0.16, 0.88),
    ]);

    // 暗面：沿下缘切出的梯形（与外轮廓共用底边三点 + 起点 A）
    final base = polygon(const [
      (0.04, 0.68), // = 外轮廓起点 A
      (0.48, 0.62),
      (0.97, 0.60),
      (0.92, 0.84), // = 外轮廓底边
      (0.50, 0.94),
      (0.16, 0.88),
    ]);

    return (crown, base);
  }

  /// 构造单朵云的闭合路径：底边微起伏 → 右侧收拢 → 顶部三个 puff → 左侧回落。
  ///
  /// 归一化坐标（x:0~1 宽、y:0=云顶 1=云底）乘以宽高落位，puff 会略冲出
  /// [h] 的上界——那正是云的鼓包部分，实际高度约为 1.1h。
  /// 所有锚点（pt）抖 ±2.2px、控制点（cp）抖 ±3.0px——控制点抖得更多，
  /// 曲率变化更明显，毛边感集中在弧顶（手绘云最「手」的地方）。
  Path _cloudPath(double w, double h, int seed) {
    final rng = math.Random(seed);

    Offset pt(double x, double y) =>
        Offset(x * w + handJitter(rng, 2.2), y * h + handJitter(rng, 2.2));
    Offset cp(double x, double y) =>
        Offset(x * w + handJitter(rng, 3.0), y * h + handJitter(rng, 3.0));

    final path = Path();

    // Path 的 moveTo/cubicTo 收的是 double 而不是 Offset，包一层省掉 .dx/.dy 噪音
    void cubic(Offset c1, Offset c2, Offset end) =>
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

    // 起笔左下角 → 底边两段微起伏（云底从不是直线）
    final start = pt(0.03, 0.86);
    path.moveTo(start.dx, start.dy);
    cubic(cp(0.20, 1.02), cp(0.42, 0.97), pt(0.60, 0.94));
    cubic(cp(0.76, 0.91), cp(0.90, 0.98), pt(0.99, 0.88));

    // 右侧向上收拢到顶缘起点
    cubic(cp(1.06, 0.60), cp(1.03, 0.34), pt(0.90, 0.22));

    // 顶部三个大 puff（从右往左绕），控制点冲出上界形成鼓包
    cubic(cp(0.86, 0.02), cp(0.72, -0.05), pt(0.62, 0.16));
    cubic(cp(0.52, -0.09), cp(0.34, -0.07), pt(0.26, 0.20));
    cubic(cp(0.16, 0.03), cp(0.02, 0.14), pt(0.04, 0.44));

    // 左侧回落闭合
    cubic(cp(-0.05, 0.58), cp(-0.04, 0.78), pt(0.03, 0.86));
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(CloudPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fill != fill ||
      oldDelegate.line != line ||
      oldDelegate.poly != poly;

  @override
  // 纯装饰层没有语义，恒 false 避免每帧触发语义树更新
  bool shouldRebuildSemantics(CloudPainter oldDelegate) => false;
}
