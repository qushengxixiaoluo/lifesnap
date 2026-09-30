/// 闯关地图 · 节点连线（Catmull-Rom 样条 → 三次贝塞尔）
///
/// 路径为什么用样条而不是直线：
/// 节点本身带随机抖动、又是蛇形折返，直线会像心电图一样生硬；
/// Catmull-Rom 保证曲线**穿过**每个节点（关卡必须踩在线上），
/// 同时切线连续，视觉上像一条手绘的探险路线。
///
/// 糖果公路画法（风格圣经第 5 条）：三层叠加——
/// 1. 底层：画风描边色粗线（糖果=深巧克力棕、LowPoly=近黑，圆头线帽）；
/// 2. 上层：奶油色路面（行车道）；
/// 3. 路中央：糖果橙圆点分道线（短虚线 + 圆头帽，像糖豆撒在路上）。
///
/// 三段状态渲染（按「较早那个节点」的状态决定这一段的画法）：
/// - 过去 + 有照片/总结/今日：标准宽糖果公路（走过的路铺好了）；
/// - 过去 + 空白日：细一号的素路（走过但没留下痕迹）；
/// - 未来：整条公路虚线化 + 卡通雾罩（未解锁的锁定感）。
///
/// 性能：本层被页面单独包进 RepaintBoundary，
/// 换肤/数据刷新只重绘这条线，不会牵动天空与 31 个节点。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import 'candy_colors.dart';
import 'day_node.dart';
import 'day_node_layout.dart';

/// 路径的三种渲染风格。
enum _PathStyle { road, faint, locked }

/// 整月节点连线画笔：用 Catmull-Rom 样条把各节点串成一条糖果公路，
/// 按「较早那个节点」的状态分三段渲染（标准/素路/虚线雾）。
/// 不变式：[nodes] 与 [statuses] 必须等长，页面单独包 RepaintBoundary 控制重绘。
class MapPathPainter extends CustomPainter {
  /// 节点落点序列（顺序 = 1 号到月末，与 [statuses] 一一对应）。
  final List<NodePosition> nodes;

  /// 每个节点的状态（决定第 i 段路径的画法，见 [_styleOf]）。
  final List<DayNodeStatus> statuses;

  /// 当前皮肤：糖果公路本身不随皮肤变，但雾罩底色跟天空走，
  /// 换肤后 shouldRepaint 靠它感知（见 [shouldRepaint]）。
  final AppStyle style;

  /// 当前画风：雾罩色温同样跟「天色 × 画风」的光晕走，描边也从它取
  /// （outlineFor：糖果棕 ↔ 近黑）——只带 style 不带 art 的话，
  /// LowPoly↔糖果切换时光晕与描边都变了却判「不用重绘」。
  final ArtStyle art;

  MapPathPainter({
    required this.nodes,
    required this.statuses,
    required this.style,
    required this.art,
  });

  /// 段 i 连接节点 i → i+1，取**较早**节点的状态：
  /// 「你已经走到哪」由前一个节点决定，路的后半段属于未来。
  static _PathStyle _styleOf(DayNodeStatus status) {
    switch (status) {
      case DayNodeStatus.withSummary:
      case DayNodeStatus.withPhotos:
      case DayNodeStatus.today:
        return _PathStyle.road;
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

    // 逐段建 Path，再把连续同风格的段合并，减少 drawPath 次数。
    final groups = <_PathStyle, Path>{};
    for (var i = 0; i < nodes.length - 1; i++) {
      final styleKind = _styleOf(statuses[i]);
      final bucket = groups[styleKind] ??= Path();
      bucket.addPath(_bezierSegment(i), Offset.zero);
    }

    for (final entry in groups.entries) {
      switch (entry.key) {
        case _PathStyle.road:
          _paintRoad(canvas, entry.value);
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
  // 三种画法：糖果公路的三层结构
  // ---------------------------------------------------------------------

  /// 标准糖果公路：深棕路基 → 奶油路面 → 橙色糖豆分道线。
  /// 三层都用圆头线帽，拐弯处才是圆润的「软管」而不是断头折线。
  void _paintRoad(Canvas canvas, Path path) {
    // ① 路基：画风描边色粗线（outlineFor(art)），比路面宽出一圈 = 公路的「护边」。
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..color = outlineFor(art);
    canvas.drawPath(path, base);

    // ② 路面：奶油色，压在路基上形成「铺装路面」。
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round
      ..color = CandyColors.cream;
    canvas.drawPath(path, road);

    // ③ 分道线：糖果橙短虚线（近似糖豆串），圆头帽。
    final dots = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = CandyColors.orange;
    _drawDashed(canvas, path, dots, 3, 9);
  }

  /// 过去空白日：细一号的素路——路基/路面都收窄，分道线换成极淡棕点，
  /// 「走过但没留下痕迹」的路不该和通关路一样热闹。
  void _paintFaint(Canvas canvas, Path path) {
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = outlineFor(art).withValues(alpha: 0.75);
    canvas.drawPath(path, base);

    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = CandyColors.creamDark;
    canvas.drawPath(path, road);

    final dots = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = outlineFor(art).withValues(alpha: 0.4);
    _drawDashed(canvas, path, dots, 2, 10);
  }

  /// 未来：整条公路按「路基/路面/分道线」同步虚线化（像还没铺完的路段），
  /// 再罩一层卡通雾（淡蓝白，跟当前皮肤的天空微调色温）。
  void _paintLocked(Canvas canvas, Path path) {
    // 雾罩先铺底：压在公路之下，边缘比公路宽一圈，形成柔光包边。
    final fog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..color = _fogColor().withValues(alpha: 0.4);
    canvas.drawPath(path, fog);

    // 路基虚线（深棕短节）。
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..color = outlineFor(art).withValues(alpha: 0.85);
    _drawDashed(canvas, path, base, 14, 10);

    // 路面虚线（奶油短节，与路基同节奏但窄一圈）。
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round
      ..color = CandyColors.cream.withValues(alpha: 0.9);
    _drawDashed(canvas, path, road, 14, 10);

    // 分道线：灰蓝点，和雾同色系（锁定感）。
    final dots = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = CandyColors.mist.withValues(alpha: 0.95);
    _drawDashed(canvas, path, dots, 3, 11);
  }

  /// 雾的卡通配色：日间/黄昏偏暖白、星夜偏月光蓝——跟「天色 × 画风」
  /// 的天空辉光色插值一档，换肤/换画风后锁定段不显得「色温脱轨」。
  Color _fogColor() {
    final glow = tokensFor(style, art).glow;
    return Color.lerp(CandyColors.mist, glow, 0.35)!;
  }

  /// Flutter 没有原生 dash，用 PathMetrics 按「实 on / 空 off」切段画。
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
    if (old.style != style) return true; // 换天色 → 雾罩色温变化
    if (old.art != art) return true; // 换画风 → 同一档天色的光晕也不同
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
