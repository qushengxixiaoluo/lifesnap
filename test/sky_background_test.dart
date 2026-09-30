/// A 轨画风基础设施冒烟测试：
/// 天空背景渲染、三皮肤 crossfade 切换、HandCard 点击回调。
///
/// 注意：SkyBackground 内部是 60s repeat 动画，绝不能 pumpAndSettle（永不收敛），
/// 只用定长 pump 推帧。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiguang_handbook/app/app_style.dart';
import 'package:shiguang_handbook/widgets/hand_card.dart';
import 'package:shiguang_handbook/widgets/sky_background.dart';

void main() {
  setUp(() {
    // 皮肤是全局静态量：每个用例从日光开始，避免用例间串扰
    AppStyleNotifier.current.value = AppStyle.dayLight;
  });

  tearDown(() {
    AppStyleNotifier.current.value = AppStyle.dayLight;
  });

  testWidgets('SkyBackground 渲染无异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SkyBackground(child: SizedBox())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    // 推过数秒循环相位：云漂移 / 光束呼吸 / 纸纹路径都实际执行一遍
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);

    // 跨过 60s 循环缝合点：验证取模漂移 / 相位取模在回卷时不炸
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('三皮肤切换无异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SkyBackground(child: SizedBox())),
    );

    for (final style in AppStyle.values) {
      AppStyleNotifier.current.value = style;
      // 700ms > 600ms crossfade：确保过渡结束后各层仍在稳定绘制
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    }
    // 星夜下星层已挂载，再推几帧覆盖星闪绘制分支
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('换肤进行中再次换肤（接力淡入）无异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SkyBackground(child: SizedBox())),
    );

    // 日光→星夜进行到一半时插队黄昏，再插队回日光：
    // 起点必须冻结成当前中间态而非上一次的目标皮肤，这里覆盖该代码路径
    AppStyleNotifier.current.value = AppStyle.night;
    await tester.pump(const Duration(milliseconds: 300)); // fade 过半
    AppStyleNotifier.current.value = AppStyle.sunset;
    await tester.pump(const Duration(milliseconds: 200)); // 再次打断
    AppStyleNotifier.current.value = AppStyle.dayLight;
    // 推过完整 600ms：确认接力淡入收敛且各层稳定绘制
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('HandCard 点击回调触发', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: HandCard(
            onTap: () => tapped = true,
            child: const SizedBox(width: 120, height: 60),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(HandCard));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
