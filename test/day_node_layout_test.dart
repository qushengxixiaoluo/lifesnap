/// C 轨布局算法单测：确定性、顺序、间距硬约束、等比映射。
///
/// 这些用例锁的是「闯关地图的骨架」：
/// 一旦有人改了种子/蛇形/松弛参数，这里会立刻告诉他用户看到的地图变了。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/features/calendar_map/day_node_layout.dart';

void main() {
  // 四种天数月：28（平年二月）/ 29（闰年二月）/ 30 / 31。
  const months = <(int, int, int)>[
    (2026, 2, 28),
    (2024, 2, 29),
    (2026, 9, 30),
    (2026, 1, 31),
  ];

  // 常见画布：手机竖屏、大屏手机、桌面横窗、宽屏。
  const canvases = <CanvasSize>[
    CanvasSize(360, 640),
    CanvasSize(390, 760),
    CanvasSize(800, 600),
    CanvasSize(1280, 720),
  ];

  group('确定性', () {
    test('同一 (year, month) 两次调用结果完全一致（两份独立缓存）', () {
      const size = CanvasSize(390, 720);
      final a = MonthLayoutCache().layoutMonth(2026, 9, size);
      final b = MonthLayoutCache().layoutMonth(2026, 9, size);

      expect(a.length, b.length);
      expect(a, b); // NodePosition 实现了 ==，逐字段比较
    });

    test('同月重复调用命中缓存，返回同一批实例（不重掷随机数）', () {
      final cache = MonthLayoutCache();
      const size = CanvasSize(390, 720);
      final a = cache.layoutMonth(2026, 9, size);
      final b = cache.layoutMonth(2026, 9, size);
      expect(identical(a, b), isTrue);
      expect(cache.contains(2026, 9), isTrue);
    });

    test('不同月份种子不同：抖动结果确实不一样', () {
      const size = CanvasSize(390, 720);
      // 两个 30 天的月，长度一致，比的就只剩「落点」本身。
      final sep = MonthLayoutCache().layoutMonth(2026, 9, size);
      final apr = MonthLayoutCache().layoutMonth(2026, 4, size);
      expect(sep.length, apr.length);
      // 首节点坐标不同即证明随机抖动真的由 (year, month) 驱动。
      expect(sep.first == apr.first, isFalse);
    });

    test('窗口尺寸变化只做等比映射，不重掷随机数', () {
      const base = CanvasSize(400, 800);
      const resized = CanvasSize(800, 600);

      final cache = MonthLayoutCache();
      final before = cache.layoutMonth(2026, 9, base);
      final after = cache.layoutMonth(2026, 9, resized);

      expect(after.length, before.length);
      const sx = 800 / 400;
      const sy = 600 / 800;
      final s = sy; // 半径取两轴较小比例
      for (var i = 0; i < before.length; i++) {
        expect(after[i].day, before[i].day);
        expect(after[i].x, closeTo(before[i].x * sx, 1e-9));
        expect(after[i].y, closeTo(before[i].y * sy, 1e-9));
        expect(after[i].radius, closeTo(before[i].radius * s, 1e-9));
      }
    });
  });

  group('顺序与天数', () {
    test('节点顺序 = 1 号到月末，数量覆盖 28/29/30/31 天', () {
      const size = CanvasSize(390, 760);
      for (final (year, month, days) in months) {
        final nodes = MonthLayoutCache().layoutMonth(year, month, size);

        expect(nodes.length, days,
            reason: '$year-$month 应有 $days 个节点');
        expect(
          [for (final n in nodes) n.day],
          List<int>.generate(days, (i) => i + 1),
          reason: '$year-$month 必须按 1 号到月末排列',
        );
        // 与契约里的天数函数对齐，避免自己算错月长。
        expect(daysInMonth(year, month), days);
      }
    });
  });

  group('间距硬约束', () {
    test('任意两节点中心距 ≥ 节点直径 × 1.25（全部画布 × 全部月长）', () {
      for (final size in canvases) {
        for (final (year, month, _) in months) {
          // 每个组合独立缓存：验证的是「从零算」的结论，不被缩放结果带偏。
          final nodes = MonthLayoutCache().layoutMonth(year, month, size);
          expect(nodes.length, greaterThan(0));

          for (var i = 0; i < nodes.length; i++) {
            for (var j = i + 1; j < nodes.length; j++) {
              final d = nodes[i].distanceTo(nodes[j]);
              final minDist = 1.25 * nodes[i].diameter;
              expect(
                d + 1e-6,
                greaterThanOrEqualTo(minDist),
                reason: '$year-$month @ $size：节点 ${nodes[i].day} 与 '
                    '${nodes[j].day} 相距 ${d.toStringAsFixed(2)}，'
                    '要求 ≥ ${minDist.toStringAsFixed(2)}',
              );
            }
          }
        }
      }
    });

    test('所有节点都落在画布内（含留白）', () {
      const size = CanvasSize(360, 640);
      final nodes = MonthLayoutCache().layoutMonth(2026, 3, size);
      for (final n in nodes) {
        expect(n.x - n.radius, greaterThanOrEqualTo(-0.01));
        expect(n.y - n.radius, greaterThanOrEqualTo(-0.01));
        expect(n.x + n.radius, lessThanOrEqualTo(size.width + 0.01));
        expect(n.y + n.radius, lessThanOrEqualTo(size.height + 0.01));
        expect(n.radius, greaterThan(0));
      }
    });

    test('非法画布尺寸返回空列表，不产出 NaN', () {
      final cache = MonthLayoutCache();
      expect(cache.layoutMonth(2026, 9, const CanvasSize(0, 600)), isEmpty);
      expect(cache.layoutMonth(2026, 9, const CanvasSize(800, 0)), isEmpty);
      // 非法尺寸不得污染缓存：正常尺寸来时仍要能算出来。
      final ok = cache.layoutMonth(2026, 9, const CanvasSize(390, 720));
      expect(ok.length, 30);
    });
  });
}
