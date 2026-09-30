/// 闯关地图 · 月份节点布局（纯 Dart，不依赖 Flutter / dart:ui）
///
/// 为什么做成纯 Dart：
/// 1. 布局是「确定性算法 + 数学」，抽出来可以脱离 widget 树做毫秒级单测；
/// 2. 后续若要在桌面端做离线预计算/导出，也能直接复用。
///
/// 算法要点（与交付说明一一对应）：
/// - 种子固定为 `Random(year * 100 + month)`：同一个月永远长同一个样，
///   不会因为窗口重绘/换皮肤而「跳一下」，用户对地图形成肌肉记忆。
/// - 6 列蛇形折返：奇数行反转，1 号在左上、月末在左下或右下，
///   路径自然像贪吃蛇一样来回折返，才有「闯关」的走线感。
/// - 抖动 ±11% 列宽 / ±30% 行高：行高抖动更大是因为竖向行距本来富余，
///   横向列距更紧张（一屏只有 6 列），所以横向收着抖。
/// - 3 轮最小间距松弛：抖动会让相邻节点过近，用「对推」把它们推开；
///   交替扫描方向（奇偶轮反向）让修正能从两端同时向中间传，
///   3 轮即可覆盖一整行 6 个节点的连锁位移。
/// - 缓存 + 等比映射：窗口 resize 只做坐标缩放、绝不重掷随机数，
///   否则用户拖窗口时整张地图会「洗牌」，很晃眼。
library;

import 'dart:math' as math;

import '../../core/models/models.dart';

// ============================================================================
// 数值参数（集中在此，便于统一调参与单测）
// ============================================================================

/// 一行 6 天：手机竖屏一屏刚好放下，桌面也不至于拉得太稀。
const int kMapColumns = 6;

/// 横向抖动幅度（占列宽的比例，±11%）。
const double kMapJitterXRatio = 0.11;

/// 纵向抖动幅度（占行高的比例，±30%）。
const double kMapJitterYRatio = 0.30;

/// 节点直径 = 0.72 × min(列宽, 行高)：留出抖动与对推所需的空隙。
const double kMapNodeToCellRatio = 0.72;

/// 最小间距轮数（交付约定 3 轮）。
const int kMapRelaxRounds = 3;

/// 最小中心距 = 节点直径 × 1.25，换算成半径的倍数：1.25 × 2r = 2.5r。
const double kMapMinDistPerRadius = 2.5;

// ============================================================================
// 基础值对象
// ============================================================================

/// 画布逻辑尺寸。自定义而不是用 `dart:ui` 的 Size，纯 Dart 也能 import 单测。
class CanvasSize {
  /// 画布宽（逻辑像素；必须为正且有限，见 [isUsable]）。
  final double width;

  /// 画布高（逻辑像素；必须为正且有限，见 [isUsable]）。
  final double height;

  const CanvasSize(this.width, this.height);

  /// 宽高必须为正且有限，否则除法会产出 NaN，把整张地图画到虚空里。
  bool get isUsable =>
      width.isFinite && height.isFinite && width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is CanvasSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() =>
      'CanvasSize(${width.toStringAsFixed(1)}×${height.toStringAsFixed(1)})';
}

/// 一个日节点在地图上的落点。
///
/// [radius] 单独存而不是常量：极端画布下可能触发「整体微缩半径」的兜底，
/// 届时所有节点同步变小，但仍是正圆、仍满足 1.25×直径 的间距硬约束。
class NodePosition {
  /// 日号（1..31），列表顺序即 1 号到月末。
  final int day;

  /// 圆心 x（逻辑像素，相对当前画布左上角，已夹在留边范围内）。
  final double x;

  /// 圆心 y（逻辑像素，相对当前画布左上角，已夹在留边范围内）。
  final double y;

  /// 节点半径（逻辑像素，恒为正；全图等半径，极端画布下整体微缩）。
  final double radius;

  const NodePosition({
    required this.day,
    required this.x,
    required this.y,
    required this.radius,
  });

  double get diameter => radius * 2;

  /// 与另一节点的中心距（单测直接复用，避免和画笔各算一套公式）。
  double distanceTo(NodePosition other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is NodePosition &&
      other.day == day &&
      other.x == x &&
      other.y == y &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(day, x, y, radius);

  @override
  String toString() =>
      'NodePosition(day: $day, x: ${x.toStringAsFixed(1)}, '
      'y: ${y.toStringAsFixed(1)}, r: ${radius.toStringAsFixed(1)})';
}

// ============================================================================
// 缓存
// ============================================================================

/// 某个月在「基准画布」上算好的结果。
class _CachedLayout {
  final CanvasSize canvas;
  final List<NodePosition> positions;

  const _CachedLayout(this.canvas, this.positions);
}

/// 按年月键缓存布局结果。
///
/// 为什么要按年月缓存而不是按年月+尺寸：窗口尺寸变化时重算会重掷随机数，
/// 地图会整片重排；这里只把基准结果等比映射到新尺寸，视觉上是「平滑放大」。
class MonthLayoutCache {
  /// 1200 个月（2000–2099）没必要全留，留最近 48 个月足够来回翻。
  final int maxMonths;

  final Map<int, _CachedLayout> _entries = <int, _CachedLayout>{};

  MonthLayoutCache({this.maxMonths = 48});

  /// 取某月布局：未缓存则计算并缓存；尺寸不同则等比映射。
  List<NodePosition> layoutMonth(int year, int month, CanvasSize canvasSize) {
    if (!canvasSize.isUsable) return const <NodePosition>[];

    // 月份越界时夹到 1..12，避免 DateTime(2026, 0) 这类边界算出奇怪天数。
    var m = month;
    var y = year;
    if (m < 1) {
      m = 1;
    } else if (m > 12) {
      m = 12;
    }

    final key = y * 100 + m;
    final hit = _entries[key];
    if (hit != null) {
      if (hit.canvas.width == canvasSize.width &&
          hit.canvas.height == canvasSize.height) {
        return hit.positions;
      }
      return _scale(hit, canvasSize);
    }

    final positions = _compute(y, m, canvasSize);
    if (positions.isEmpty) return const <NodePosition>[];

    if (_entries.length >= maxMonths) {
      // 简单淘汰最早插入的月份（Dart Map 保持插入序）。
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CachedLayout(canvasSize, positions);
    return positions;
  }

  /// 是否已经缓存了某月（给测试/诊断用）。
  bool contains(int year, int month) => _entries.containsKey(year * 100 + month);

  /// 清空缓存（换季重排、单测隔离用）。
  void clear() => _entries.clear();

  /// 等比映射：x/y 各自按比例缩放，半径取两轴较小比例，保证仍是正圆。
  /// 注意这里**不会**重掷随机数，抖动形态保持不变。
  static List<NodePosition> _scale(_CachedLayout entry, CanvasSize to) {
    final sx = to.width / entry.canvas.width;
    final sy = to.height / entry.canvas.height;
    final s = math.min(sx, sy);
    return <NodePosition>[
      for (final p in entry.positions)
        NodePosition(
          day: p.day,
          x: p.x * sx,
          y: p.y * sy,
          radius: p.radius * s,
        ),
    ];
  }
}

/// 全局默认缓存（页面走 Provider 持有的实例，这里给直接调用者兜底）。
final MonthLayoutCache defaultMonthLayoutCache = MonthLayoutCache();

/// 任务书约定的入口签名：`layoutMonth(year, month, canvasSize)`。
List<NodePosition> layoutMonth(
  int year,
  int month,
  CanvasSize canvasSize, {
  MonthLayoutCache? cache,
}) =>
    (cache ?? defaultMonthLayoutCache).layoutMonth(year, month, canvasSize);

// ============================================================================
// 核心算法
// ============================================================================

List<NodePosition> _compute(int year, int month, CanvasSize canvas) {
  final w = canvas.width;
  final h = canvas.height;

  // 留边：地图像画在纸上，四边留一点空气，节点不会顶到屏幕边缘。
  final padX = w * 0.04;
  final padY = h * 0.05;
  final areaW = w - 2 * padX;
  final areaH = h - 2 * padY;
  if (areaW <= 0 || areaH <= 0) return const <NodePosition>[];

  final count = daysInMonth(year, month); // 天数用契约里的工具，和全 App 保持一致
  final rows = (count + kMapColumns - 1) ~/ kMapColumns;
  final colW = areaW / kMapColumns;
  final rowH = areaH / rows;

  // ---- 半径：三个上界取最小 ----
  // 1) 视觉上界：直径占一格 72%，太大会把「路径」挤没了；
  // 2) 横向可行上界：6 列要塞下 2.5r×5 + 2r ≤ 可用宽度；
  // 3) 纵向可行上界：行数要塞下 2.5r×(行数-1) + 2r ≤ 可用高度。
  // 再乘 0.96 留 4% 余量，让松弛一定有挪动空间（否则贴着边推不动）。
  final visualR = kMapNodeToCellRatio * math.min(colW, rowH) / 2;
  final feasibleH = areaW / (kMapMinDistPerRadius * (kMapColumns - 1) + 2);
  final feasibleV = areaH / (kMapMinDistPerRadius * (rows - 1) + 2);
  final r =
      math.max(4.0, math.min(visualR, math.min(feasibleH, feasibleV) * 0.96));

  final minCX = padX + r;
  final maxCX = w - padX - r;
  final minCY = padY + r;
  final maxCY = h - padY - r;

  // ---- 蛇形网格 + 抖动 ----
  final rng = math.Random(year * 100 + month); // 同月同种子 → 结果恒定
  final xs = List<double>.filled(count, 0);
  final ys = List<double>.filled(count, 0);

  for (var i = 0; i < count; i++) {
    final row = i ~/ kMapColumns;
    var col = i % kMapColumns;
    if (row.isOdd) col = kMapColumns - 1 - col; // 奇数行反转 = 蛇形折返

    final gridX = padX + colW * (col + 0.5);
    final gridY = padY + rowH * (row + 0.5);
    final jx = (rng.nextDouble() * 2 - 1) * kMapJitterXRatio * colW;
    final jy = (rng.nextDouble() * 2 - 1) * kMapJitterYRatio * rowH;

    xs[i] = _clamp(gridX + jx, minCX, maxCX);
    ys[i] = _clamp(gridY + jy, minCY, maxCY);
  }

  // ---- 3 轮最小间距松弛 ----
  _relax(xs, ys, r, minCX, maxCX, minCY, maxCY);

  // ---- 硬约束兜底：仍有过近的成对节点时整体微缩半径 ----
  // 间距公式里 r 也在右边（minDist = 2.5r），所以缩半径同样能满足
  // 「任意两节点 ≥ 1.25×直径」，且比继续推点更稳（极端画布推不动会贴边）。
  final finalR = _enforceSpacing(xs, ys, r);

  return <NodePosition>[
    for (var i = 0; i < count; i++)
      NodePosition(day: i + 1, x: xs[i], y: ys[i], radius: finalR),
  ];
}

/// 3 轮「对推」松弛：距离 < 2.5r 的成对节点各挪一半缺口。
///
/// 扫描方向奇偶轮交替：同向扫描时，左边的修正要靠后续轮次才传得到右边，
/// 反向扫描让位移能从右端回流，3 轮即可覆盖一整行的连锁位移。
void _relax(
  List<double> xs,
  List<double> ys,
  double r,
  double minX,
  double maxX,
  double minY,
  double maxY,
) {
  final n = xs.length;
  if (n < 2) return;
  final minDist = kMapMinDistPerRadius * r;

  for (var round = 0; round < kMapRelaxRounds; round++) {
    final forward = round.isEven;
    for (var step = 0; step < n; step++) {
      final i = forward ? step : n - 1 - step;
      for (var j = i + 1; j < n; j++) {
        var dx = xs[j] - xs[i];
        var dy = ys[j] - ys[i];
        var d = math.sqrt(dx * dx + dy * dy);
        if (d >= minDist) continue;

        if (d < 1e-9) {
          // 极端情况（两点完全重合）给一个由下标决定的固定方向推开，
          // 绝不引入新的随机数，否则同月两次调用就不再一致了。
          final ang = ((i * 37 + j * 17) % 360) * math.pi / 180;
          dx = math.cos(ang);
          dy = math.sin(ang);
          d = 1.0;
        }

        final push = (minDist - d) / 2;
        final ux = dx / d;
        final uy = dy / d;
        xs[i] = _clamp(xs[i] - push * ux, minX, maxX);
        ys[i] = _clamp(ys[i] - push * uy, minY, maxY);
        xs[j] = _clamp(xs[j] + push * ux, minX, maxX);
        ys[j] = _clamp(ys[j] + push * uy, minY, maxY);
      }
    }
  }
}

/// 兜底校验：返回能让「最小中心距 ≥ 2.5×半径」成立的最大半径。
double _enforceSpacing(List<double> xs, List<double> ys, double r) {
  final n = xs.length;
  if (n < 2) return r;

  final minDist = kMapMinDistPerRadius * r;
  var minSeen = double.infinity;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final dx = xs[j] - xs[i];
      final dy = ys[j] - ys[i];
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < minSeen) minSeen = d;
    }
  }

  if (minSeen >= minDist) return r; // 常规路径：松弛已经达标，不动半径
  if (!(minSeen > 0)) return r; // 理论上到不了这里，退化时保持原半径
  return minSeen / kMapMinDistPerRadius;
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);
