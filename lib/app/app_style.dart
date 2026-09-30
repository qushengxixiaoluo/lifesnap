/// 拾光手册 · 皮肤样式与色彩令牌（阶段 0 地基文件）
///
/// 画风定位：吉卜力（水彩纸、手绘描边、大地色）× 新海诚（天空渐变、光晕、饱和光感）。
///
/// 【双维度模型】（用户纠正后的正确形态——画风不是天色的第四个枚举值）：
/// - 天色轴 [AppStyle]：日光 / 黄昏 / 星夜——天空的时间，枚举与语义完全不动；
/// - 画风轴 [ArtStyle]：糖果手绘（现状）/ 油墨旧纸——画面的材质。
/// 两轴正交，共 2×3 令牌矩阵：每种画风都必须适配三档天色（见 [tokensFor]）。
///
/// 并行纪律：五条轨只 import 不修改；配色调整上报编排者统一改。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// 天色枚举 + 全局 ValueNotifier（沿 interview_calendar AppTheme.styleListenable 先例）
// ============================================================================

enum AppStyle {
  dayLight, // 日光：新海诚正午蓝天 + 鲜绿草坡
  sunset, // 黄昏：橙金天际 + 暖云
  night, // 星夜：靛蓝夜空 + 星光
}

class AppStyleNotifier {
  /// 根级换肤开关：main.dart 用 ValueListenableBuilder 包住 MaterialApp。
  static final ValueNotifier<AppStyle> current =
      ValueNotifier<AppStyle>(AppStyle.dayLight);

  static const _prefsKey = 'skinMode';

  /// 启动时从 SharedPreferences 恢复（main 里 await 调用）。
  static Future<void> load(SharedPreferences prefs) async {
    final v = prefs.getString(_prefsKey);
    if (v != null) {
      current.value =
          AppStyle.values.firstWhere((s) => s.name == v, orElse: () => AppStyle.dayLight);
    }
  }

  static Future<void> save(SharedPreferences prefs, AppStyle style) async {
    current.value = style;
    await prefs.setString(_prefsKey, style.name);
  }
}

// ============================================================================
// 画风枚举 + 全局 ValueNotifier（与天色轴正交的第二根轴）
// ============================================================================

/// 渲染画风（第二根轴，与 [AppStyle] 天色轴正交）。
///
/// 为什么不并进 AppStyle 当「第四个皮肤」：天色回答「现在是什么时候」，
/// 画风回答「这幅画用什么材质画」。日光下的旧信纸、黄昏下的旧信纸、
/// 星夜下的旧信纸是三张不同的画面——只有两根独立的轴才表达得出来。
enum ArtStyle {
  candy, // 糖果手绘：保卫萝卜式厚描边果冻漆面（现状，默认）
  agedInk, // 油墨旧纸：老式油墨印在泛黄信纸上，旧书插图味
}

/// 画风全局开关（形态照抄 [AppStyleNotifier]，但持久化键分开）。
class ArtStyleNotifier {
  /// 根级换画风开关：main.dart 用 ValueListenableBuilder 包住 MaterialApp，
  /// 设置页与 SkyBackground 各自监听——任一轴变化都整树/整层刷新。
  static final ValueNotifier<ArtStyle> current =
      ValueNotifier<ArtStyle>(ArtStyle.candy);

  /// 与 skinMode 分键：天色与画风两轴各存各的，启动加载互不干扰、互不覆盖。
  static const _prefsKey = 'artMode';

  /// 启动时从 SharedPreferences 恢复（main 里 await 调用）。
  static Future<void> load(SharedPreferences prefs) async {
    final v = prefs.getString(_prefsKey);
    if (v != null) {
      current.value = ArtStyle.values.firstWhere(
        (a) => a.name == v,
        orElse: () => ArtStyle.candy,
      );
    }
  }

  static Future<void> save(SharedPreferences prefs, ArtStyle art) async {
    current.value = art;
    await prefs.setString(_prefsKey, art.name);
  }
}

// ============================================================================
// 色彩令牌
// ============================================================================

class ShiguangColors {
  ShiguangColors._();

  // —— 新海诚光感（天空 / 光）——
  static const skyTopDay = Color(0xFF4A90D9); // 正午天顶蓝
  static const skyMidDay = Color(0xFF8EC5F0); // 中段天蓝
  static const skyHorizon = Color(0xFFFFE3B3); // 地平线暖光
  static const sunsetOrange = Color(0xFFFF9E5E); // 黄昏主橙
  static const sunsetRose = Color(0xFFF7B2A6); // 晚霞玫瑰
  static const sunGlow = Color(0xFFFFF3C4); // 日光辉
  static const cloudWhite = Color(0xFFFCFBF6); // 云白（微暖）
  static const nightTop = Color(0xFF101B3A); // 夜空靛蓝
  static const nightMid = Color(0xFF2C3E6B); // 夜空中段
  static const starWhite = Color(0xFFFDFDF6); // 星白
  static const grassGreen = Color(0xFF7FB069); // 新海诚式鲜绿草坡

  // —— 吉卜力大地色（纸 / 手绘）——
  static const paper = Color(0xFFF6EFDD); // 水彩纸底
  static const paperDeep = Color(0xFFEADFC6); // 纸面阴影
  static const inkBrown = Color(0xFF4A3F35); // 手绘描边棕（代替纯黑）
  static const wood = Color(0xFFB98B5E); // 木色（卡片骨架）
  static const leafDark = Color(0xFF4E7A4A); // 深叶绿（强调）

  // —— 油墨旧纸（旧信纸画风）——
  static const agedInkText = Color(0xFF2B2620); // 旧信纸正文墨色（黑褐墨，非纯黑）
  static const agedPaperText = Color(0xFFE7DCC2); // 暗墨夜读下淡纸色文字
  static const cinnabar = Color(0xFFB5432E); // 朱砂：旧信纸印泥色的日间点缀
  static const cinnabarBright = Color(0xFFD9785F); // 朱砂提亮：暗底上的同一位点缀

  // —— 状态语义色 ——
  static const completedGold = Color(0xFFE3B23C); // 已完成节点金描边
  static const todayPulse = Color(0xFFFFD98E); // 今日脉冲光环
  static const futureMist = Color(0xFFBFD3E6); // 未来节点雾色
  static const danger = Color(0xFFC0605F); // 错误/删除
}

// ============================================================================
// （天色 × 画风）→ 天空令牌映射
// ============================================================================

/// 一套「天色 × 画风」的天空参数（A 轨 painter 直接消费）。
class SkyTokens {
  final Color top;
  final Color mid;
  final Color horizon;
  final Color glow; // 光晕/太阳色
  final Color grass;
  final bool showStars;
  final bool showSunRays;

  const SkyTokens({
    required this.top,
    required this.mid,
    required this.horizon,
    required this.glow,
    required this.grass,
    this.showStars = false,
    this.showSunRays = false,
  });
}

/// 天色 × 画风 → 天空令牌的 **纯函数**（2×3 矩阵，不读任何全局状态，可直接单测）。
///
/// - candy 分支原样返回既有三档值：糖果画风的观感不得因新增画风轴回退；
/// - agedInk 分支按「旧信纸」立意给三档天色各配一张纸（见 [_agedInkTokens]）。
SkyTokens tokensFor(AppStyle time, ArtStyle art) {
  switch (art) {
    case ArtStyle.candy:
      return _candyTokens(time);
    case ArtStyle.agedInk:
      return _agedInkTokens(time);
  }
}

/// 糖果手绘 × 三档天色：新海诚天空 + 保卫萝卜草地（现状值逐字保留）。
SkyTokens _candyTokens(AppStyle time) {
  switch (time) {
    case AppStyle.dayLight:
      return const SkyTokens(
        top: ShiguangColors.skyTopDay,
        mid: ShiguangColors.skyMidDay,
        horizon: ShiguangColors.skyHorizon,
        glow: ShiguangColors.sunGlow,
        grass: ShiguangColors.grassGreen,
        // 关闭放射光束：保卫萝卜卡通风不要新海诚式细光束（用户嫌丑 + 风格圣经要求）
        showSunRays: false,
      );
    case AppStyle.sunset:
      return const SkyTokens(
        top: Color(0xFF7A6FBF), // 紫暮天顶
        mid: ShiguangColors.sunsetOrange,
        horizon: Color(0xFFFFD9A0), // 金色地平线
        glow: Color(0xFFFFC46B),
        grass: Color(0xFF6E9A5B), // 偏暗的草绿
        showSunRays: false, // 同日光：卡通平涂不要放射光束
      );
    case AppStyle.night:
      return const SkyTokens(
        top: ShiguangColors.nightTop,
        mid: ShiguangColors.nightMid,
        horizon: Color(0xFF3E5480), // 夜幕地平线
        glow: Color(0xFFE8ECF8), // 月光色
        grass: Color(0xFF3D5A40), // 夜色草坡
        showStars: true,
      );
  }
}

/// 油墨旧纸 × 三档天色：老式油墨印在泛黄信纸上，每档天色是一张不同的纸。
///
/// 立意：不做「天空」做「纸面」——三段微渐变是受潮旧纸的深浅，
/// 山峦像旧书插图的褪色版画；三档一律关星、关光束（旧纸不挂星、不打光束）。
SkyTokens _agedInkTokens(AppStyle time) {
  switch (time) {
    case AppStyle.dayLight:
      // 明亮信纸：日光下的泛黄信纸，受潮处深、纸面居中、边角浅
      return const SkyTokens(
        top: Color(0xFFE8D8AE),
        mid: Color(0xFFF0E1BD),
        horizon: Color(0xFFF5EACB),
        glow: Color(0xFFA08B6B), // 淡墨褐：旧书插图的晕染光
        grass: Color(0xFF9A9B6E), // 褪色橄榄：印旧了的绿
        showStars: false,
        showSunRays: false,
      );
    case AppStyle.sunset:
      // 琥珀旧纸：黄昏把纸烤出橘斑的受潮感
      return const SkyTokens(
        top: Color(0xFFE2C489),
        mid: Color(0xFFEDD6A4),
        horizon: Color(0xFFF0E0B8),
        glow: Color(0xFFC08A4A), // 橙褐：落日透过旧纸
        grass: Color(0xFF85855C), // 暗橄榄
        showStars: false,
        showSunRays: false,
      );
    case AppStyle.night:
      // 暗墨夜读：深墨褐纸 + 昏灯——夜里读旧信，不是靛蓝夜空
      return const SkyTokens(
        top: Color(0xFF2A231B),
        mid: Color(0xFF33291D),
        horizon: Color(0xFF3A2E20),
        glow: Color(0xFF9C8A66), // 昏灯色光晕
        grass: Color(0xFF4A4A38),
        showStars: false,
        showSunRays: false,
      );
  }
}

/// 全局入口：读当前画风后转发纯函数 [tokensFor]。
///
/// 为什么值得留这一层「读全局 Notifier」的耦合：skyOf 的调用点遍布
/// painter / 页面 / 主题，换画风必须零改动自动生效（所有旧调用点只换数据源
/// 不换签名）；而 2×3 矩阵本身被抽成纯函数 [tokensFor]，测试完全绕开全局态。
SkyTokens skyOf(AppStyle style) =>
    tokensFor(style, ArtStyleNotifier.current.value);

/// 文字色矩阵（纯函数）：糖果逻辑原样保留；
/// 旧信纸白天是纸上的墨字、星夜是暗纸上的淡字（夜读对比度）。
Color textColorFor(AppStyle time, ArtStyle art) {
  if (art == ArtStyle.agedInk) {
    return time == AppStyle.night
        ? ShiguangColors.agedPaperText
        : ShiguangColors.agedInkText;
  }
  return time == AppStyle.night
      ? ShiguangColors.paper
      : ShiguangColors.inkBrown;
}

/// 文字色全局入口：与 [skyOf] 同构，读当前画风后转发 [textColorFor]。
Color textColorOf(AppStyle time) =>
    textColorFor(time, ArtStyleNotifier.current.value);
