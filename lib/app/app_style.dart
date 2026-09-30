/// 拾光手册 · 皮肤样式与色彩令牌（阶段 0 地基文件）
///
/// 画风定位：吉卜力（水彩纸、手绘描边、大地色）× 新海诚（天空渐变、光晕、饱和光感）。
///
/// 【双维度模型】（用户纠正后的正确形态——画风不是天色的第四个枚举值）：
/// - 天色轴 [AppStyle]：日光 / 黄昏 / 星夜——天空的时间，枚举与语义完全不动；
/// - 画风轴 [ArtStyle]：糖果手绘（现状）/ LowPoly 描边——画面的材质。
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
/// 画风回答「这幅画用什么材质画」。日光下的低多边形、黄昏下的低多边形、
/// 星夜下的低多边形是三张不同的画面——只有两根独立的轴才表达得出来。
enum ArtStyle {
  candy, // 糖果手绘：保卫萝卜式厚描边果冻漆面（现状，默认）
  lowPoly, // LowPoly 描边：低多边形平面色块 + #141414 近黑描边（贴纸感）
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
  ///
  /// 迁移说明：第二画风曾叫 agedInk（油墨旧纸），按用户指令整体替换为
  /// lowPoly 后，老用户 prefs 里仍存着旧值 'agedInk'。这里做一次性映射
  /// （键 artMode 不变）——不映射的话旧值会掉进 orElse 被打回糖果默认，
  /// 等于升级后静默换肤。一天的迁移窗口：下次 save 就会写成新名。
  static Future<void> load(SharedPreferences prefs) async {
    final v = prefs.getString(_prefsKey);
    if (v != null) {
      final normalized = v == 'agedInk' ? ArtStyle.lowPoly.name : v;
      current.value = ArtStyle.values.firstWhere(
        (a) => a.name == normalized,
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

  // —— 画风描边的两个端点（见 [outlineFor]：一切形状描边只从这里取）——
  /// 糖果描边：深巧克力棕（与地图轨 CandyColors.outline 同值，单一来源）。
  static const candyOutline = Color(0xFF4A2C17);

  /// LowPoly 描边：近黑——低多边形的面与面之间靠黑线分界（贴纸/赛璐璐感）。
  static const polyOutline = Color(0xFF141414);

  // —— LowPoly 文字 ——
  /// LowPoly 星夜的冷白字：压在深蓝底上，与黑描边同一套「无彩」墨色体系。
  static const polyNightText = Color(0xFFE9F0FA);

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
/// - candy 分支原样返回既有三档值：糖果画风的观感不得因换画风轴回退；
/// - lowPoly 分支按「低多边形平面风」给三档天色各配一组高饱和平涂色
///   （见 [_lowPolyTokens]，色值即用户给定的六边形调色板）。
SkyTokens tokensFor(AppStyle time, ArtStyle art) {
  switch (art) {
    case ArtStyle.candy:
      return _candyTokens(time);
    case ArtStyle.lowPoly:
      return _lowPolyTokens(time);
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

/// LowPoly × 三档天色：低多边形平面风——饱和度高、色块干净，
/// 三段色本身就是可以**直接平涂**的硬色带（天空层据此画三条水平带，见
/// SkyGradientPainter），山/云也只用这组色做明暗面与 #141414 描边。
///
/// 星 / 光束开关沿用糖果画风各天色的现行为（用户约定：lowPoly 有星有束的
/// 档照旧，即每档与 _candyTokens 同档完全一致——由测试逐档坐实）。
SkyTokens _lowPolyTokens(AppStyle time) {
  switch (time) {
    case AppStyle.dayLight:
      return const SkyTokens(
        top: Color(0xFF5FA8E0), // 天顶蓝（平涂带①）
        mid: Color(0xFF8FC8EF), // 中段天蓝（平涂带②）
        horizon: Color(0xFFC8E8FA), // 地平浅蓝（平涂带③）
        glow: Color(0xFFFFE066), // 正午光斑黄
        grass: Color(0xFF4CAF50), // 鲜绿草地
        showStars: false,
        showSunRays: false,
      );
    case AppStyle.sunset:
      return const SkyTokens(
        top: Color(0xFFFF7E42), // 晚霞橙
        mid: Color(0xFFFFA85C),
        horizon: Color(0xFFFFD29B),
        glow: Color(0xFFFFB347), // 落日橙金
        grass: Color(0xFF6B5B95), // 紫褐草地（黄昏的冷阴影）
        showStars: false,
        showSunRays: false,
      );
    case AppStyle.night:
      return const SkyTokens(
        top: Color(0xFF162447), // 深靛夜空
        mid: Color(0xFF27406E),
        horizon: Color(0xFF3B5B94),
        glow: Color(0xFFA8C8FF), // 月光蓝
        grass: Color(0xFF1F5C4C), // 深青草地
        showStars: true, // 与糖果星夜一致：这一档本来就有星
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
/// LowPoly 亮底（日光/黄昏）压近黑字、星夜压冷白字——与黑描边同一套墨色体系。
Color textColorFor(AppStyle time, ArtStyle art) {
  if (art == ArtStyle.lowPoly) {
    return time == AppStyle.night
        ? ShiguangColors.polyNightText
        : ShiguangColors.polyOutline;
  }
  return time == AppStyle.night
      ? ShiguangColors.paper
      : ShiguangColors.inkBrown;
}

/// 文字色全局入口：与 [skyOf] 同构，读当前画风后转发 [textColorFor]。
Color textColorOf(AppStyle time) =>
    textColorFor(time, ArtStyleNotifier.current.value);

/// 画风感知的描边色（纯函数，形态照 [tokensFor] / [textColorFor]）：
/// candy = 深巧克力棕（玩具漆面描边，现值）、lowPoly = #141414 近黑。
///
/// 为什么要有它：地图三件套（day_node / calendar_map_page / map_path_painter）
/// 以前写死 CandyColors.outline，换画风时描边纹丝不动——现在全部改调本函数，
/// 于是「糖果棕描边 ↔ 黑描边」跟着画风走，调用点不用各自 if/else。
Color outlineFor(ArtStyle art) => art == ArtStyle.lowPoly
    ? ShiguangColors.polyOutline
    : ShiguangColors.candyOutline;

/// 描边全局入口：与 [skyOf] 同构，读当前画风后转发 [outlineFor]。
Color outlineNow() => outlineFor(ArtStyleNotifier.current.value);
