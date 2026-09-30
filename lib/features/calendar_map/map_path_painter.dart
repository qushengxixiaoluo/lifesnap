/// 闯关地图 · 节点连线（Catmull-Rom 样条 → 三次贝塞尔）
///
/// 路径为什么用样条而不是直线：
/// 节点本身带随机抖动、又是蛇形折返，直线会像心电图一样生硬；
/// Catmull-Rom 保证曲线**穿过**每个节点（关卡必须踩在线上），
/// 同时切线连续，视觉上像一条手绘的探险路线。
///
/// 三段状态渲染（按「较早那个节点」的状态决定这一段的画法）：
/// - 过去 + 有照片：双描边发光实线（走过的路有光）；
/// - 过去 + 空白日：细淡实线（走过但没留下痕迹的路）；
/// - 未来：虚线 + 半透明雾（未解锁的锁定感）。
///
/// 性能：本层被页面单独包进 RepaintBoundary，
/// 换肤/数据刷新只重绘这条线，不会牵动天空与 31 个节点。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import 'day_node.dart';
import 'day_node_layout.dart';

/// 路径的三种渲染风格。
enum _PathStyle { glow, faint, locked }

/// 整月节点连线画笔：用 Catmull-Rom 样条把各节点串成一条探险路线，
/// 按「较早那个节点」的状态分三段渲染（发光/细淡/虚线雾）。
/// 不变式：[nodes] 与 [statuses] 必须等长，页面单独包 RepaintBoundary 控制重绘。
class MapPathPainter extends CustomPainter {
  /// 节点落点序列（顺序 = 1 号到月末，与 [statuses] 一一对应）。
  final List<NodePosition> nodes;

  /// 每个节点的状态（决定第 i 段路径的画法，见 [_styleOf]）。
  final List<DayNodeStatus> statuses;

  /// 当前皮肤：换肤后发光色随天空色走（夜=月光白，昼=日辉黄）。
  final AppStyle style;

  MapPathPainter({
    required this.nodes,
    required this.statuses,
    required this.style,
  });

  /// 段 i 连接节点 i → i+1，取**较早**节点的状态：
  /// 「你已经走到哪」由前一个节点决定，路的后半段属于未来。
  static _PathStyle _styleOf(DayNodeStatus status) {
    switch (status) {
      case DayNodeStatus.withSummary:
      case DayNodeStatus.withPhotos:
      case DayNodeStatus.today:
        return _PathStyle.glow;
      case DayNodeStatus.pastEmpty:
        return _PathStyle.faint;
      case DayNodeStatus.future:
        return _PathStyle.locked;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 防御：页面保证两者等长，若上游漏传就干脆不画，绝不抛异常刷红屏。
    if (nodes.length < 2 || statuses.length != nodes.length) return;

    final sky = skyOf(style); // 换肤后发光色跟着天空走（夜=月光白，昼=日辉黄）

    // 逐段建 Path，再把连续同风格的段合并，减少 drawPath 次数。
    final groups = <_PathStyle, Path>{};
    for (var i = 0; i < nodes.length - 1; i++) {
      final styleKind = _styleOf(statuses[i]);
      final bucket = groups[styleKind] ??= Path();
      bucket.addPath(_bezierSegment(i), Offset.zero);
    }

    for (final entry in groups.entries) {
      switch (entry.key) {
        case _PathStyle.glow:
          _paintGlow(canvas, entry.value, sky);
        case _PathStyle.faint:
          _paintFaint(canvas, entry.value);
        case _PathStyle.locked:
          _paintLocked(canvas, entry.value);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Catmull-Rom → 三次贝塞尔
  // ---------------------------------------------------------------------

  /// 由 P(i-1)..P(i+2) 求 P(i)→P(i+1) 的控制点（均匀参数化，tension=1）：
  /// C1 = P1 + (P2 - P0) / 6，C2 = P2 - (P3 - P1) / 6。
  /// 首尾点用端点复制，保证曲线也穿过 1 号与月末节点。
  Path _bezierSegment(int i) {
    Offset at(int idx) {
      // 首尾复制端点：Catmull-Rom 需要前后各借一个点，端点外没有邻居。
      final k = idx < 0
          ? 0
          : (idx >= nodes.length ? nodes.length - 1 : idx);
      return Offset(nodes[k].x, nodes[k].y);
    }

    final p0 = at(i - 1);
    final p1 = at(i);
    final p2 = at(i + 1);
    final p3 = at(i + 2);

    final c1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final c2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );

    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }

  // ---------------------------------------------------------------------
  // 三种画法
  // ---------------------------------------------------------------------

  /// 过去有照片：双描边 = 外发光 + 实线主干。
  void _paintGlow(Canvas canvas, Path path, SkyTokens sky) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = sky.glow.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glow);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..color = ShiguangColors.completedGold; // 金色主干 = 已通关的路
    canvas.drawPath(path, core);
  }

  /// 过去空白日：细淡实线，像铅笔轻轻带过。
  void _paintFaint(Canvas canvas, Path path) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = ShiguangColors.inkBrown.withValues(alpha: 0.35);
    canvas.drawPath(path, paint);
  }

  /// 未来：雾色底 + 虚线。雾底给「这扇门还没开」的锁定感。
  void _paintLocked(Canvas canvas, Path path) {
    final fog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = ShiguangColors.futureMist.withValues(alpha: 0.28);
    canvas.drawPath(path, fog);

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = ShiguangColors.futureMist.withValues(alpha: 0.85);
    _drawDashed(canvas, path, dash, 7, 6);
  }

  /// Flutter 没有原生 dash，用 PathMeasure 按「实 7 / 空 6」切段画。
  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint,
    double on,
    double off,
  ) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + on, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + off;
      }
    }
  }

  // ---------------------------------------------------------------------
  // 重绘判定
  // ---------------------------------------------------------------------

  @override
  bool shouldRepaint(MapPathPainter old) {
    if (old.style != style) return true; // 换肤 → 发光色变化
    if (old.nodes.length != nodes.length) return true;
    if (old.statuses.length != statuses.length) return true;
    // 布局来自缓存：同月同尺寸是同一批实例，identity 比较几乎零成本。
    for (var i = 0; i < nodes.length; i++) {
      if (!identical(old.nodes[i], nodes[i])) return true;
    }
    for (var i = 0; i < statuses.length; i++) {
      if (old.statuses[i] != statuses[i]) return true;
    }
    return false;
  }
}
