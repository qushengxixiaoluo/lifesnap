/// C 轨页面冒烟测试：状态判定 + 地图渲染 + 翻月 + 点节点。
///
/// 注意：今日节点的脉冲动画是无限循环，**不能用 pumpAndSettle**（会等到超时），
/// 统一用固定帧数的 pump 推进时间。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/calendar_map/calendar_map_page.dart';
import 'package:shiguang_handbook/features/calendar_map/day_node.dart';
import 'package:shiguang_handbook/widgets/sky_background.dart';

Photo _photo(String path, int dayKey) => Photo(
      path: path,
      fileSize: 1024,
      mtimeMs: 1000,
      takenAtMs: 1000,
      dayKey: dayKey,
      sourceId: 1,
    );

/// 推进若干帧（每帧 100ms）：翻月动画、SnackBar 入场都需要多帧。
Future<void> _pumpFor(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

(int, int) _nextMonth(int year, int month) =>
    month == 12 ? (year + 1, 1) : (year, month + 1);

void main() {
  group('statusOfDay 五种状态', () {
    const todayKey = 20260915;
    const yesterdayKey = 20260914;
    const tomorrowKey = 20260916;

    test('今日优先于一切内容状态', () {
      expect(
        statusOfDay(
          dayKey: todayKey,
          todayKey: todayKey,
          hasSummary: true,
          photoCount: 9,
        ),
        DayNodeStatus.today,
      );
    });

    test('未来即使有照片也是未解锁（时钟异常的防御）', () {
      expect(
        statusOfDay(
          dayKey: tomorrowKey,
          todayKey: todayKey,
          photoCount: 3,
        ),
        DayNodeStatus.future,
      );
    });

    test('过去：有总结 > 有照片 > 空白', () {
      expect(
        statusOfDay(
          dayKey: yesterdayKey,
          todayKey: todayKey,
          hasSummary: true,
          photoCount: 0,
        ),
        DayNodeStatus.withSummary,
      );
      expect(
        statusOfDay(
          dayKey: yesterdayKey,
          todayKey: todayKey,
          hasSummary: false,
          photoCount: 4,
        ),
        DayNodeStatus.withPhotos,
      );
      expect(
        statusOfDay(dayKey: yesterdayKey, todayKey: todayKey),
        DayNodeStatus.pastEmpty,
      );
    });

    test('总结标记优先于仅有照片', () {
      expect(
        statusOfDay(
          dayKey: yesterdayKey,
          todayKey: todayKey,
          hasSummary: true,
          photoCount: 4,
        ),
        DayNodeStatus.withSummary,
      );
    });
  });

  testWidgets('预置数据：渲染无异常、左右滑动换月、点节点打开详情', (tester) async {
    final now = DateTime.now();
    int keyOf(int day) => now.year * 10000 + now.month * 100 + day;

    // 数据预置在「本月」：PageView 初始页就是今天所在月，开屏即可见。
    final dayToday = now.day; // 今日
    final dayWithSummary = now.day >= 2 ? now.day - 1 : 1; // 昨天（有总结）
    final dayWithPhotos = now.day >= 3 ? now.day - 2 : 1; // 前天（只有照片）

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoStoreProvider.overrideWith((ref) async {
            final store = InMemoryPhotoIndexStore();
            await store.init();
            await store.upsertPhotos([
              _photo('photos/today.jpg', keyOf(dayToday)),
              _photo('photos/summary.jpg', keyOf(dayWithSummary)),
              _photo('photos/photos-only.jpg', keyOf(dayWithPhotos)),
            ]);
            await store.putSummary(
              AiSummary(
                dayKey: keyOf(dayWithSummary),
                title: '秋日散步',
                narrative: '一段被记录下来的秋日。',
                tags: const ['秋日'],
                mood: '晴',
                highlights: const ['晚风'],
                model: 'unit-test',
                photoSig: '',
                createdAtMs: 1,
              ),
            );
            return store;
          }),
        ],
        child: const MaterialApp(home: CalendarMapPage()),
      ),
    );

    // 让 photoStoreProvider 与月份索引两层异步都落地。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: '首屏渲染不应抛异常');

    // 1) 头部显示「今天所在月 · 拾光地图」，且正好贴在 AppBar 下沿：
    //    低于 AppBar = 被工具栏压住；高出太多 = 重复叠了工具栏高度（曾踩过 56px 空档）。
    final appbarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final headerTop = tester.getTopLeft(find.byIcon(Icons.chevron_left)).dy;
    expect(headerTop, greaterThanOrEqualTo(appbarBottom - 1));
    expect(headerTop, lessThanOrEqualTo(appbarBottom + 40));
    // 标题带 ▾ 提示可点（点它弹年月跳转选择器）
    expect(
      find.text('${now.year}年${now.month}月 · 拾光地图　▾'),
      findsOneWidget,
    );
    expect(find.byType(SkyBackground), findsOneWidget, reason: '天空层打底');

    // 2) 节点都画出来了（key 上带 dayKey，可精确定位）
    expect(find.byKey(ValueKey('day-node-${keyOf(1)}')), findsOneWidget);
    expect(find.byKey(ValueKey('day-node-${keyOf(dayToday)}')), findsOneWidget);

    // 3) 今日节点处于「当前关卡」状态
    expect(
      find.byWidgetPredicate(
        (w) => w is DayNode && w.status == DayNodeStatus.today,
      ),
      findsOneWidget,
    );

    // 4) 预置的两天按真实状态渲染（1 号/2 号当天没有「过去日」，跳过断言）
    if (now.day >= 2) {
      expect(
        find.byWidgetPredicate(
          (w) => w is DayNode && w.status == DayNodeStatus.withSummary,
        ),
        findsOneWidget,
        reason: '昨天应显示为「已有总结」的金勾节点',
      );
    }
    if (now.day >= 3) {
      expect(
        find.byWidgetPredicate(
          (w) => w is DayNode && w.status == DayNodeStatus.withPhotos,
        ),
        findsOneWidget,
        reason: '前天应显示为「有照片无总结」的白描边节点',
      );
    }

    // 5) 左滑 → 下个月
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await _pumpFor(tester);
    final next = _nextMonth(now.year, now.month);
    expect(
      find.text('${next.$1}年${next.$2}月 · 拾光地图　▾'),
      findsOneWidget,
      reason: '左滑后应切到下个月',
    );
    expect(tester.takeException(), isNull);

    // 6) 右滑 → 回到本月
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await _pumpFor(tester);
    expect(find.text('${now.year}年${now.month}月 · 拾光地图　▾'), findsOneWidget);

    // 7) 点击节点 → 走 showDayDetail 契约（E 轨已交付：展开详情底部面板）
    // warnIfMissed: false —— 节点自己不参与命中（由 Rect 列表层统一命中），
    // 所以「点不到节点 widget」是设计使然，真正的点击落点是上层命中层。
    await tester.tap(
      find.byKey(ValueKey('day-node-${keyOf(dayWithSummary)}')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DraggableScrollableSheet), findsOneWidget,
        reason: '点节点应展开详情面板');
    // 面板抬头是 dayKeyToChinese(dayKey)，用它校验打开的是「这一天」
    expect(
      find.textContaining(dayKeyToChinese(keyOf(dayWithSummary))),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('store 尚未就绪时整月按空日渲染，不崩溃', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // async 抛错 → 以失败 Future 交付，FutureProvider 必然转成 AsyncError，
          // 不依赖「同步抛错是否被捕获」的实现细节。
          photoStoreProvider
              .overrideWith((ref) async => throw StateError('存储未就绪')),
        ],
        child: const MaterialApp(home: CalendarMapPage()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // 存储打不开也照样有地图与节点（空日样式），而不是白屏或红屏。
    expect(find.byType(PageView), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is DayNode),
      findsWidgets,
    );
  });

  testWidgets('今日「当前关卡」徽章压在圆下沿外探，不遮住日号', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: const MaterialApp(home: CalendarMapPage())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    final now = DateTime.now();
    final todayKey = now.year * 10000 + now.month * 100 + now.day;
    final todayFinder = find.byKey(ValueKey('day-node-$todayKey'));
    final todayNode = tester.widget<DayNode>(todayFinder);
    expect(todayNode.status, DayNodeStatus.today, reason: '当前月视图里应有今日节点');
    final r = todayNode.position.radius;

    // 徽章药丸 = 直接包着「当前关卡」文案的那个 Container（遮罩/语义标签都不是 Text）。
    final pillFinder = find.byWidgetPredicate(
      (w) => w is Container && w.child is Text && (w.child as Text).data == '当前关卡',
      description: '当前关卡徽章药丸',
    );
    expect(pillFinder, findsOneWidget);

    // 几何防回归：节点 box 正好 2r × 2r、圆体占满，所以圆底边 = 顶边 + 2r。
    final circleBottom = tester.getTopLeft(todayFinder).dy + r * 2;
    final badgeTop = tester.getTopLeft(pillFinder).dy;
    final badgeBottom = tester.getBottomLeft(pillFinder).dy;

    expect(
      badgeTop,
      greaterThanOrEqualTo(circleBottom - 8),
      reason: '徽章顶边最多压入圆内 8px；曾因 top 误写成 r-6 落在节点中部盖住日号',
    );
    expect(
      badgeBottom,
      greaterThanOrEqualTo(circleBottom),
      reason: '徽章应越过圆底边向外探出（「压下沿 + 外探」，而不是整个缩在圆内）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('兜底路径：无根 ProviderScope 时点节点仍能打开详情面板', (tester) async {
    // 回归背景：main.dart 集成后已挂根 ProviderScope，但本页与 launcher 都保留
    // 「无根则自建/补挂 scope」的兜底（覆盖无根嵌入场景）。showModalBottomSheet
    // 的内容挂在 Navigator/Overlay 路由下，不在页面级 scope 里——若详情入口用
    // 页面内层 context 调 showDayDetail，它的兜底 scope 判断会被骗过 →
    // DayDetailSheet 首帧抛 No ProviderScope → 红屏。本用例持续守住该兜底分支；
    // 生产主路径（根 scope 在场）由下一条「根 ProviderScope 集成」用例覆盖。
    await tester.pumpWidget(const MaterialApp(home: CalendarMapPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: '首屏渲染不应抛异常');

    final now = DateTime.now();
    final dayOneKey = now.year * 10000 + now.month * 100 + 1;

    // 命中由节点上方的 Rect 层统一接管，点节点中心即可（warnIfMissed 关掉）。
    await tester.tap(
      find.byKey(ValueKey('day-node-$dayOneKey')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(DraggableScrollableSheet),
      findsOneWidget,
      reason: '无根 scope 时详情面板也必须能展开（launcher 兜底 scope 或根 scope 二选一）',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: '面板首帧 ref.watch 不应抛 No ProviderScope——若此处红屏，'
          '说明详情入口又用回了页面内层 context',
    );
  });

  testWidgets('根 ProviderScope 集成：点节点打开详情且与地图共享同一 container', (tester) async {
    // 集成坐实（一审高危的最终形态）：main.dart 现已挂根 ProviderScope +
    // photoStoreProvider.overrideWith 单实例 store。此用例按同样的挂法装配
    // 整棵树，点节点打开详情，并断言两件事：
    // 1) 面板正常展开、无异常——根 scope 在场时 launcher 必须走「复用」分支，
    //    不能再往面板里塞兜底 scope，也不能抛 No ProviderScope；
    // 2) 面板与地图读到**同一个 ProviderContainer / 同一个 store 实例**——
    //    这正是当初高危的病灶（页面级 scope 与兜底 scope 双开、状态不共享），
    //    container 相同才说明「单实例 store、纯内存状态互通」在生产主路径成立。
    final store = InMemoryPhotoIndexStore();
    await store.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoStoreProvider.overrideWith((ref) async => store),
        ],
        child: const MaterialApp(home: CalendarMapPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: '根 scope 下首屏渲染不应抛异常');

    // 命中由节点上方的 Rect 层统一接管，点节点中心即可（warnIfMissed 关掉）。
    final now = DateTime.now();
    final dayOneKey = now.year * 10000 + now.month * 100 + 1;
    await tester.tap(
      find.byKey(ValueKey('day-node-$dayOneKey')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DraggableScrollableSheet), findsOneWidget,
        reason: '根 scope 在场时点节点应正常展开详情底部面板');
    expect(tester.takeException(), isNull,
        reason: '面板首帧不应抛 No ProviderScope 或其它异常');

    // container 同一性：若 launcher 误挂了兜底 scope，或页面误建了页面级 scope，
    // 面板就近解析到的 container 会与地图侧不同——此断言让「双开」无法复发。
    final pageContainer = ProviderScope.containerOf(
      tester.element(find.byType(CalendarMapPage)),
      listen: false,
    );
    final sheetContainer = ProviderScope.containerOf(
      tester.element(find.byType(DraggableScrollableSheet)),
      listen: false,
    );
    expect(
      identical(sheetContainer, pageContainer),
      isTrue,
      reason: '详情面板必须与地图共享同一 ProviderContainer（否则 store 双开、状态不互通）',
    );

    // 再坐实单实例 store：两边解析出的必须是 override 里那同一个对象。
    final storeFromPage = await pageContainer.read(photoStoreProvider.future);
    final storeFromSheet = await sheetContainer.read(photoStoreProvider.future);
    expect(identical(storeFromPage, storeFromSheet), isTrue,
        reason: '地图与面板读到的 store 必须是同一实例');
    expect(identical(storeFromPage, store), isTrue,
        reason: 'override 注入的单实例 store 应被生产主路径原样共享');
  });
}
