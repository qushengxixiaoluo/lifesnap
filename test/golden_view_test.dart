/// 视觉快照测试：用 flutter_test 的 Skia 软渲染直接出图，
/// 绕开无头浏览器画布时灵时不灵的问题。
///
/// 用法：
///   flutter test --update-goldens test/golden_view_test.dart   # 生成快照
///   flutter test test/golden_view_test.dart                     # 比对快照
///
/// 注意：测试环境文字用 Ahem 字体（实心方块），字形不作数，
/// 但尺寸/位置/配色/层次都是真实渲染——足以验证节点大小与数字居中。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/app/app_style.dart';
import 'package:shiguang_handbook/app/app_theme.dart';
import 'package:shiguang_handbook/features/calendar_map/calendar_map_page.dart';

void main() {
  testWidgets('地图首页糖果风快照（1280x800）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ValueListenableBuilder<AppStyle>(
        valueListenable: AppStyleNotifier.current,
        builder: (context, style, _) {
          return ProviderScope(
            child: MaterialApp(
              theme: AppTheme.build(style),
              home: const CalendarMapPage(),
            ),
          );
        },
      ),
    );

    // 有限次 pump：天空动画是无限循环，pumpAndSettle 会永远等下去
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // 诊断：设置页到底在不在树里？
    // 在 → 说明有代码把设置页压上了路由栈；不在 → 是截图捕获张冠李戴。
    expect(find.text('设置'), findsNothing, reason: '树里混进了设置页！');
    expect(find.byType(CalendarMapPage), findsOneWidget);

    await expectLater(
      find.byType(CalendarMapPage),
      matchesGoldenFile('goldens/candy_home.png'),
    );
  });
}
