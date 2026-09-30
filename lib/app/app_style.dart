/// 拾光手册 · 皮肤样式与色彩令牌（阶段 0 地基文件）
///
/// 画风定位：吉卜力（水彩纸、手绘描边、大地色）× 新海诚（天空渐变、光晕、饱和光感）。
/// 三套皮肤：日光 / 黄昏 / 星夜——只换「天空与文字」令牌，结构色（纸/墨）恒定。
///
/// 并行纪律：五条轨只 import 不修改；配色调整上报编排者统一改。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// 皮肤枚举 + 全局 ValueNotifier（沿 interview_calendar AppTheme.styleListenable 先例）
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

  // —— 状态语义色 ——
  static const completedGold = Color(0xFFE3B23C); // 已完成节点金描边
  static const todayPulse = Color(0xFFFFD98E); // 今日脉冲光环
  static const futureMist = Color(0xFFBFD3E6); // 未来节点雾色
  static const danger = Color(0xFFC0605F); // 错误/删除
}

// ============================================================================
// 皮肤 → 天空令牌映射
// ============================================================================

/// 一套皮肤的天空参数（A 轨 painter 直接消费）。
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

SkyTokens skyOf(AppStyle style) {
  switch (style) {
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

/// 文字色随皮肤微调：日间/黄昏用墨棕，星夜用纸白。
Color textColorOf(AppStyle style) => style == AppStyle.night
    ? ShiguangColors.paper
    : ShiguangColors.inkBrown;
