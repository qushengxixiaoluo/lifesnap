/// 画风轴（ArtStyle）测试：
/// 1) tokensFor 纯函数矩阵——旧纸三档与糖果不同、一律无星无光束、夜纸是深色；
/// 2) 两轴持久化分键（skinMode / artMode）的 save/load 往返；
/// 3) 画风切换与天色切换同样走 600ms crossfade（渲染无异常、星层随画风挂卸）；
/// 4) 设置页两行选择器——点「油墨旧纸」落 ArtStyleNotifier，天色行逻辑不动。
///
/// 注意：SkyBackground 内部是 60s repeat 动画，绝不能 pumpAndSettle（永不收敛），
/// 只用定长 pump 推帧。全局 Notifier 是进程级静态量，每个用例进出都归位。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/app_style.dart';
import 'package:shiguang_handbook/features/settings/settings_appearance.dart';
import 'package:shiguang_handbook/widgets/painters/stars_painter.dart';
import 'package:shiguang_handbook/widgets/sky_background.dart';

void main() {
  setUp(() {
    // 全局静态量归位：画风/天色都从「糖果 + 日光」出发，避免用例间串扰
    SharedPreferences.setMockInitialValues({});
    ArtStyleNotifier.current.value = ArtStyle.candy;
    AppStyleNotifier.current.value = AppStyle.dayLight;
  });

  tearDown(() {
    ArtStyleNotifier.current.value = ArtStyle.candy;
    AppStyleNotifier.current.value = AppStyle.dayLight;
  });

  group('tokensFor 令牌矩阵', () {
    test('旧纸日光与糖果日光不是同一张画面', () {
      final candy = tokensFor(AppStyle.dayLight, ArtStyle.candy);
      final aged = tokensFor(AppStyle.dayLight, ArtStyle.agedInk);
      expect(aged.top, isNot(candy.top));
      expect(aged.mid, isNot(candy.mid));
      expect(aged.grass, isNot(candy.grass));
      // 糖果日光的观感不得回退：仍是既有正午天顶蓝
      expect(candy.top, ShiguangColors.skyTopDay);
    });

    test('旧纸三档一律不挂星、不打光束', () {
      for (final time in AppStyle.values) {
        final t = tokensFor(time, ArtStyle.agedInk);
        expect(t.showStars, isFalse, reason: '$time 旧纸不应有星');
        expect(t.showSunRays, isFalse, reason: '$time 旧纸不应有光束');
      }
      // 对照：糖果星夜仍要星星（既有画风不得回退）
      expect(tokensFor(AppStyle.night, ArtStyle.candy).showStars, isTrue);
    });

    test('暗墨夜读的 top 是深色纸（不是靛蓝夜空也不是亮纸）', () {
      final night = tokensFor(AppStyle.night, ArtStyle.agedInk);
      final day = tokensFor(AppStyle.dayLight, ArtStyle.agedInk);
      expect(night.top.computeLuminance(), lessThan(0.1),
          reason: '夜读纸顶必须压得足够深');
      expect(day.top.computeLuminance(), greaterThan(0.5),
          reason: '日光信纸必须够亮');
      expect(night.top, isNot(ShiguangColors.nightTop), reason: '旧纸夜不是靛蓝夜空');
    });

    test('三档旧纸互不相同（2×3 矩阵每格都有自己的纸）', () {
      final tops = {
        for (final time in AppStyle.values) tokensFor(time, ArtStyle.agedInk).top
      };
      expect(tops.length, AppStyle.values.length);
    });
  });

  group('文字色矩阵', () {
    test('旧纸：日间墨色、星夜淡纸色；糖果逻辑原样保留', () {
      expect(textColorFor(AppStyle.dayLight, ArtStyle.agedInk),
          ShiguangColors.agedInkText);
      expect(textColorFor(AppStyle.sunset, ArtStyle.agedInk),
          ShiguangColors.agedInkText);
      expect(textColorFor(AppStyle.night, ArtStyle.agedInk),
          ShiguangColors.agedPaperText);
      expect(textColorFor(AppStyle.dayLight, ArtStyle.candy),
          ShiguangColors.inkBrown);
      expect(textColorFor(AppStyle.night, ArtStyle.candy),
          ShiguangColors.paper);
    });

    test('textColorOf / skyOf 跟随全局画风（包装层读 Notifier）', () {
      // 旧画风：包装层应与纯函数同值——既有调用点零改动即可自动换色
      ArtStyleNotifier.current.value = ArtStyle.agedInk;
      expect(textColorOf(AppStyle.dayLight), ShiguangColors.agedInkText);
      expect(skyOf(AppStyle.dayLight).top,
          tokensFor(AppStyle.dayLight, ArtStyle.agedInk).top);

      ArtStyleNotifier.current.value = ArtStyle.candy;
      expect(textColorOf(AppStyle.dayLight), ShiguangColors.inkBrown);
      expect(skyOf(AppStyle.night).top,
          tokensFor(AppStyle.night, ArtStyle.candy).top);
    });
  });

  group('两轴持久化分键', () {
    test('artMode / skinMode 各存各的，save→load 往返一致', () async {
      final prefs = await SharedPreferences.getInstance();

      await ArtStyleNotifier.save(prefs, ArtStyle.agedInk);
      await AppStyleNotifier.save(prefs, AppStyle.night);
      expect(prefs.getString('artMode'), 'agedInk');
      expect(prefs.getString('skinMode'), 'night',
          reason: '画风绝不能写进天色的键');

      // 归位后再 load：两轴各自从自己的键恢复
      ArtStyleNotifier.current.value = ArtStyle.candy;
      AppStyleNotifier.current.value = AppStyle.dayLight;
      await ArtStyleNotifier.load(prefs);
      await AppStyleNotifier.load(prefs);
      expect(ArtStyleNotifier.current.value, ArtStyle.agedInk);
      expect(AppStyleNotifier.current.value, AppStyle.night);
    });

    test('未知/缺失键回落到默认值（糖果 + 日光）', () async {
      SharedPreferences.setMockInitialValues({
        'artMode': '不存在的画风',
        'skinMode': '不存在的天色',
      });
      final prefs = await SharedPreferences.getInstance();
      await ArtStyleNotifier.load(prefs);
      await AppStyleNotifier.load(prefs);
      expect(ArtStyleNotifier.current.value, ArtStyle.candy);
      expect(AppStyleNotifier.current.value, AppStyle.dayLight);
    });
  });

  group('画风切换的天空过渡', () {
    testWidgets('同一档天色下换画风：crossfade 无异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SkyBackground(child: SizedBox())),
      );
      await tester.pump(const Duration(milliseconds: 100));

      ArtStyleNotifier.current.value = ArtStyle.agedInk;
      // 700ms > 600ms crossfade：过渡结束后各层仍在稳定绘制
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);

      ArtStyleNotifier.current.value = ArtStyle.candy;
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });

    testWidgets('画风切换进行中再切天色（接力淡入）无异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SkyBackground(child: SizedBox())),
      );

      ArtStyleNotifier.current.value = ArtStyle.agedInk;
      await tester.pump(const Duration(milliseconds: 300)); // fade 过半
      AppStyleNotifier.current.value = AppStyle.night;
      await tester.pump(const Duration(milliseconds: 200)); // 再次打断
      ArtStyleNotifier.current.value = ArtStyle.candy;
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('星层随画风挂卸：旧纸星夜无星、糖果星夜有星', (tester) async {
      AppStyleNotifier.current.value = AppStyle.night;

      // StarsPainter 是 CustomPainter 不是 Widget，只能按 CustomPaint.painter 找
      final stars = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is StarsPainter,
        description: '星空层 CustomPaint',
      );

      // 糖果 × 星夜：过渡结束后星层挂载
      await tester.pumpWidget(
        const MaterialApp(home: SkyBackground(child: SizedBox())),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(stars, findsOneWidget);

      // 油墨旧纸 × 星夜：暗纸夜读，星层必须卸载。
      // 先短推一帧让 fade 的 ticker 起表（首帧只记起点不前进），
      // 再推过完整 600ms——单次长 pump 会把 elapsed 全算进起表帧，fade 反而停在 0。
      ArtStyleNotifier.current.value = ArtStyle.agedInk;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 700));
      expect(stars, findsNothing,
          reason: '旧纸不挂星，600ms 后星层应完全退出');
      expect(tester.takeException(), isNull);
    });
  });

  group('设置页两行选择器', () {
    testWidgets('点「油墨旧纸」切画风，天色行三卡仍在', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AppearanceSection()),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 两行标题 + 两张画风卡 + 三张天色卡
      expect(find.text('画风'), findsOneWidget);
      expect(find.text('天色'), findsOneWidget);
      expect(find.text('糖果手绘'), findsOneWidget);
      expect(find.text('油墨旧纸'), findsOneWidget);
      expect(find.text('日光'), findsOneWidget);
      expect(find.text('黄昏'), findsOneWidget);
      expect(find.text('星夜'), findsOneWidget);

      await tester.ensureVisible(find.text('油墨旧纸'));
      await tester.tap(find.text('油墨旧纸'));
      // 保存链路是 async（getInstance → setString），推帧等它落地
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ArtStyleNotifier.current.value, ArtStyle.agedInk);
      expect(tester.takeException(), isNull);

      // 天色行仍可点、仍写 AppStyleNotifier（逻辑不动）
      await tester.ensureVisible(find.text('星夜'));
      await tester.tap(find.text('星夜'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(AppStyleNotifier.current.value, AppStyle.night);
      expect(tester.takeException(), isNull);
    });
  });
}
