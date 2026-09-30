/// 画风轴（ArtStyle）测试：
/// 1) tokensFor 纯函数矩阵——LowPoly 三档给定色值、与糖果不同、
///    星/光束开关与糖果各天色逐档一致；
/// 2) 文字色矩阵（亮底近黑 / 星夜冷白）与描边矩阵（candy 棕 / lowPoly #141414）；
/// 3) 两轴持久化分键（skinMode / artMode）的 save/load 往返，
///    以及旧值 'agedInk' → lowPoly 的一次性迁移；
/// 4) 画风切换与天色切换同样走 600ms crossfade（渲染无异常、星层开关按矩阵走）；
/// 5) 设置页两行选择器——点「LowPoly 描边」落 ArtStyleNotifier，天色行逻辑不动。
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
    test('LowPoly 日光是给定的平涂色，且与糖果日光不是同一张画面', () {
      final candy = tokensFor(AppStyle.dayLight, ArtStyle.candy);
      final low = tokensFor(AppStyle.dayLight, ArtStyle.lowPoly);
      // 低多边形日光：纯色带三段 + 鲜绿 + 正午光斑黄
      expect(low.top, const Color(0xFF5FA8E0));
      expect(low.mid, const Color(0xFF8FC8EF));
      expect(low.horizon, const Color(0xFFC8E8FA));
      expect(low.grass, const Color(0xFF4CAF50));
      expect(low.glow, const Color(0xFFFFE066));
      // 与糖果不是同一张画面
      expect(low.top, isNot(candy.top));
      expect(low.mid, isNot(candy.mid));
      expect(low.grass, isNot(candy.grass));
      // 糖果日光的观感不得回退：仍是既有正午天顶蓝 + 既有草绿
      expect(candy.top, ShiguangColors.skyTopDay);
      expect(candy.grass, ShiguangColors.grassGreen);
    });

    test('LowPoly 黄昏是给定的橙紫配色', () {
      final low = tokensFor(AppStyle.sunset, ArtStyle.lowPoly);
      expect(low.top, const Color(0xFFFF7E42));
      expect(low.mid, const Color(0xFFFFA85C));
      expect(low.horizon, const Color(0xFFFFD29B));
      expect(low.grass, const Color(0xFF6B5B95));
      expect(low.glow, const Color(0xFFFFB347));
    });

    test('LowPoly 星夜是给定的深靛/深青配色', () {
      final low = tokensFor(AppStyle.night, ArtStyle.lowPoly);
      expect(low.top, const Color(0xFF162447));
      expect(low.mid, const Color(0xFF27406E));
      expect(low.horizon, const Color(0xFF3B5B94));
      expect(low.grass, const Color(0xFF1F5C4C));
      expect(low.glow, const Color(0xFFA8C8FF));
    });

    test('星/光束开关与糖果各天色逐档一致（有星有束的档照旧）', () {
      for (final time in AppStyle.values) {
        final low = tokensFor(time, ArtStyle.lowPoly);
        final candy = tokensFor(time, ArtStyle.candy);
        expect(low.showStars, candy.showStars,
            reason: '$time 的星开关必须与糖果一致');
        expect(low.showSunRays, candy.showSunRays,
            reason: '$time 的光束开关必须与糖果一致');
      }
      // 对照：糖果星夜仍要星星（既有画风不得回退），LowPoly 星夜因此也有星
      expect(tokensFor(AppStyle.night, ArtStyle.candy).showStars, isTrue);
      expect(tokensFor(AppStyle.night, ArtStyle.lowPoly).showStars, isTrue);
    });

    test('三档 LowPoly 互不相同（2×3 矩阵每格都有自己的天）', () {
      final tops = {
        for (final time in AppStyle.values) tokensFor(time, ArtStyle.lowPoly).top
      };
      expect(tops.length, AppStyle.values.length);
    });
  });

  group('文字色矩阵', () {
    test('LowPoly：亮底近黑字、星夜冷白字；糖果逻辑原样保留', () {
      expect(textColorFor(AppStyle.dayLight, ArtStyle.lowPoly),
          ShiguangColors.polyOutline);
      expect(textColorFor(AppStyle.sunset, ArtStyle.lowPoly),
          ShiguangColors.polyOutline);
      expect(textColorFor(AppStyle.night, ArtStyle.lowPoly),
          ShiguangColors.polyNightText);
      expect(textColorFor(AppStyle.dayLight, ArtStyle.candy),
          ShiguangColors.inkBrown);
      expect(textColorFor(AppStyle.night, ArtStyle.candy),
          ShiguangColors.paper);
    });

    test('textColorOf / skyOf 跟随全局画风（包装层读 Notifier）', () {
      // LowPoly：包装层应与纯函数同值——既有调用点零改动即可自动换色
      ArtStyleNotifier.current.value = ArtStyle.lowPoly;
      expect(textColorOf(AppStyle.dayLight), ShiguangColors.polyOutline);
      expect(skyOf(AppStyle.dayLight).top,
          tokensFor(AppStyle.dayLight, ArtStyle.lowPoly).top);

      ArtStyleNotifier.current.value = ArtStyle.candy;
      expect(textColorOf(AppStyle.dayLight), ShiguangColors.inkBrown);
      expect(skyOf(AppStyle.night).top,
          tokensFor(AppStyle.night, ArtStyle.candy).top);
    });
  });

  group('描边矩阵（黑描边是 LowPoly 的身份）', () {
    test('outlineFor：candy 巧克力棕 / lowPoly 近黑', () {
      expect(outlineFor(ArtStyle.candy), const Color(0xFF4A2C17));
      expect(outlineFor(ArtStyle.lowPoly), const Color(0xFF141414));
      // 近黑必须真的是黑系，不能是换了个名字的棕
      expect(outlineFor(ArtStyle.lowPoly).computeLuminance(), lessThan(0.02));
    });

    test('outlineNow 跟随全局画风（包装层读 Notifier）', () {
      ArtStyleNotifier.current.value = ArtStyle.lowPoly;
      expect(outlineNow(), const Color(0xFF141414));
      ArtStyleNotifier.current.value = ArtStyle.candy;
      expect(outlineNow(), const Color(0xFF4A2C17));
    });
  });

  group('两轴持久化分键', () {
    test('artMode / skinMode 各存各的，save→load 往返一致', () async {
      final prefs = await SharedPreferences.getInstance();

      await ArtStyleNotifier.save(prefs, ArtStyle.lowPoly);
      await AppStyleNotifier.save(prefs, AppStyle.night);
      expect(prefs.getString('artMode'), 'lowPoly');
      expect(prefs.getString('skinMode'), 'night',
          reason: '画风绝不能写进天色的键');

      // 归位后再 load：两轴各自从自己的键恢复
      ArtStyleNotifier.current.value = ArtStyle.candy;
      AppStyleNotifier.current.value = AppStyle.dayLight;
      await ArtStyleNotifier.load(prefs);
      await AppStyleNotifier.load(prefs);
      expect(ArtStyleNotifier.current.value, ArtStyle.lowPoly);
      expect(AppStyleNotifier.current.value, AppStyle.night);
    });

    test('旧值 agedInk 一次性映射到 lowPoly（升级不掉回糖果）', () async {
      // 老用户 prefs 里还是画风改名前的 'agedInk'
      SharedPreferences.setMockInitialValues({'artMode': 'agedInk'});
      final prefs = await SharedPreferences.getInstance();
      await ArtStyleNotifier.load(prefs);
      expect(ArtStyleNotifier.current.value, ArtStyle.lowPoly,
          reason: '迁移必须落到新画风，而不是 orElse 的糖果默认');

      // 迁移后再保存：落盘的是新名（下次启动直接命中枚举）
      await ArtStyleNotifier.save(prefs, ArtStyleNotifier.current.value);
      expect(prefs.getString('artMode'), 'lowPoly');
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

      ArtStyleNotifier.current.value = ArtStyle.lowPoly;
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

      ArtStyleNotifier.current.value = ArtStyle.lowPoly;
      await tester.pump(const Duration(milliseconds: 300)); // fade 过半
      AppStyleNotifier.current.value = AppStyle.night;
      await tester.pump(const Duration(milliseconds: 200)); // 再次打断
      ArtStyleNotifier.current.value = ArtStyle.candy;
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('星层按矩阵挂卸：星夜两种画风都有星，切到日光星层退出',
        (tester) async {
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

      // LowPoly × 星夜：矩阵约定「与糖果一致」，这一档同样有星——星层不卸。
      // 先短推一帧让 fade 的 ticker 起表（首帧只记起点不前进），
      // 再推过完整 600ms——单次长 pump 会把 elapsed 全算进起表帧，fade 反而停在 0。
      ArtStyleNotifier.current.value = ArtStyle.lowPoly;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 700));
      expect(stars, findsOneWidget, reason: 'LowPoly 星夜与糖果一样挂星');
      expect(tester.takeException(), isNull);

      // 同一画风切到日光：这一档矩阵里没有星，星层照旧退出（开关链路没坏）
      AppStyleNotifier.current.value = AppStyle.dayLight;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 700));
      expect(stars, findsNothing, reason: '日光不挂星，600ms 后星层应完全退出');
      expect(tester.takeException(), isNull);
    });
  });

  group('设置页两行选择器', () {
    testWidgets('点「LowPoly 描边」切画风，天色行三卡仍在', (tester) async {
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
      expect(find.text('LowPoly 描边'), findsOneWidget);
      expect(find.text('日光'), findsOneWidget);
      expect(find.text('黄昏'), findsOneWidget);
      expect(find.text('星夜'), findsOneWidget);

      await tester.ensureVisible(find.text('LowPoly 描边'));
      await tester.tap(find.text('LowPoly 描边'));
      // 保存链路是 async（getInstance → setString），推帧等它落地
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ArtStyleNotifier.current.value, ArtStyle.lowPoly);
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
