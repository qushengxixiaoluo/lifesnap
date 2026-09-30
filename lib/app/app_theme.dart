/// ThemeData 工厂（A 轨交付版：组件级排版 + 星夜对比度适配 + 画风轴）。
///
/// 约定：
/// 1) 所有会随「天色 × 画风」变化的值一律由 tokensFor/textColorFor 推导；
/// 2) 层次一律用「色深浅 + 描边」表达——所有组件 elevation: 0，
///    禁止 Material 默认阴影营造层次（画风是平涂手绘，不是拟物投影）；
/// 3) 星夜适配：纸面转墨蓝、主色反转为「暖纸金底 + 深墨字」，
///    保证深色环境下按钮/文字对比度依然 ≥ 4.5:1 的方向；
/// 4) LowPoly 适配：卡片/对话框/按钮一律「平面色 + #141414 近黑描边」，
///    描边明显是黑色系（绝不退回糖果的巧克力棕），三档天色各给一版平面色：
///    亮底（日光/黄昏）白卡压黑边，星夜底压深蓝、卡片提亮一档后仍压黑边。
library;

import 'package:flutter/material.dart';

import 'app_style.dart';

class AppTheme {
  AppTheme._();

  /// 由「天色 × 画风」构建完整主题。签名是契约：main.dart 与各页面依赖此函数。
  ///
  /// [art] 缺省读全局 [ArtStyleNotifier.current]：既有单参调用点
  /// （金样张等）零改动拿到当前画风；测试可显式传入矩阵中的任意组合。
  static ThemeData build(AppStyle style, {ArtStyle? art}) {
    final artStyle = art ?? ArtStyleNotifier.current.value;
    final isNight = style == AppStyle.night;
    final isLow = artStyle == ArtStyle.lowPoly;
    final sky = tokensFor(style, artStyle);
    final text = textColorFor(style, artStyle);
    // 次级文字：星夜下纸白压到 72% 仍足够亮，日间墨棕 62% 做弱化层
    final subtleText = text.withValues(alpha: isNight ? 0.72 : 0.62);

    // —— LowPoly 平面色板（三档各一版：亮底黑描边 / 夜底提亮后仍压黑边）——
    // 只用纯色平涂：LowPoly 的语言是「面 + 黑线」，卡片底绝不用渐变。
    final polyBg = switch (style) {
      AppStyle.dayLight => const Color(0xFFE7F2FC), // 淡蓝底（天空的浅色带）
      AppStyle.sunset => const Color(0xFFFFEDDC), // 奶橘底
      AppStyle.night => const Color(0xFF162447), // 深靛底（同天空天顶）
    };
    // 抬升面：亮底用纯白卡；星夜把卡提亮到地平线蓝——黑边才看得见
    final polyElevated = switch (style) {
      AppStyle.dayLight => const Color(0xFFFFFFFF),
      AppStyle.sunset => const Color(0xFFFFFFFF),
      AppStyle.night => const Color(0xFF3B5B94),
    };
    // 输入框：比卡暗一档的同色系平面色（靠明度分层，不靠描边以外的影）
    final polyInput = switch (style) {
      AppStyle.dayLight => const Color(0xFFD6E9FB),
      AppStyle.sunset => const Color(0xFFFFDCC2),
      AppStyle.night => const Color(0xFF27406E),
    };

    // —— 结构底色 ——
    // 糖果：星夜转深墨蓝、日间水彩纸（观感不得回退）；
    // LowPoly：本档天色的平面底色（见 polyBg），与卡片同色系不同明度。
    final bg =
        isLow ? polyBg : (isNight ? const Color(0xFF1A2138) : ShiguangColors.paper);
    // 抬升面（对话框/菜单/底表）：夜里亮一档、日间浅一档，始终比 bg 好分辨
    final elevated = isLow
        ? polyElevated
        : (isNight ? const Color(0xFF253054) : ShiguangColors.paper);
    // 输入框底：LowPoly 取同色系暗一档的平面色；糖果沿用原值
    final inputFill = isLow
        ? polyInput
        : (isNight
            ? const Color(0xFF141B31)
            : ShiguangColors.paperDeep.withValues(alpha: 0.55));

    // 主色策略：糖果日间墨棕底配纸白字，星夜反转成暖纸金底配深墨字；
    // LowPoly 主按钮 = 该档天色的 glow 平涂 + 近黑字（亮钮黑字 = 贴纸钮），
    // 三档 glow 亮度都够，深色环境同样点得动。
    final primary = isLow
        ? sky.glow
        : (isNight ? const Color(0xFFE9C9A0) : ShiguangColors.inkBrown);
    final onPrimary = isLow
        ? ShiguangColors.polyOutline
        : (isNight ? const Color(0xFF2B2216) : ShiguangColors.paper);
    // 强调色：糖果用叶绿；LowPoly 用该档天色的 grass（高饱和平涂强调色）
    final secondary = isLow
        ? sky.grass
        : (isNight ? const Color(0xFF93C48C) : ShiguangColors.leafDark);
    // 强调底上的字：日光鲜绿压黑字，黄昏紫褐/星夜深青压白字（对比度方向）
    final onSecondary = isLow
        ? (style == AppStyle.dayLight
            ? ShiguangColors.polyOutline
            : Colors.white)
        : (isNight ? const Color(0xFF16220F) : ShiguangColors.paper);
    // 文字钮（TextButton）强调色：糖果沿用 primary；LowPoly 亮底把 grass
    // 压暗到可读对比度（鲜绿直出在白底上只有 2.5:1），星夜反过来用光亮色。
    final link = isLow
        ? (isNight
            ? sky.glow
            : Color.lerp(sky.grass, ShiguangColors.polyOutline, 0.4)!)
        : primary;
    // 描边：LowPoly 一律 #141414 近黑（黑色系身份，绝不退回巧克力棕）；
    // 糖果沿用原棕/纸白细边。
    final outline =
        isLow ? ShiguangColors.polyOutline : (isNight
            ? ShiguangColors.paper.withValues(alpha: 0.30)
            : ShiguangColors.wood.withValues(alpha: 0.55));
    // 分割线同为黑色系：亮底 35%、夜底 55%（压在提亮的容器行上仍可辨）
    final dividerC =
        isLow ? ShiguangColors.polyOutline.withValues(alpha: isNight ? 0.55 : 0.35) : (isNight
            ? ShiguangColors.paper.withValues(alpha: 0.16)
            : ShiguangColors.wood.withValues(alpha: 0.30));

    // 容器色阶：LowPoly 是「同色系平面色的明度台阶」——亮底白→淡蓝五级、
    // 夜底深靛→浅蓝五级（列表/菜单靠明度分层，糖果仍走原靛蓝/纸色阶）。
    final containerLowest = isLow
        ? (isNight ? const Color(0xFF27406E) : const Color(0xFFFFFFFF))
        : (isNight ? const Color(0xFF0F1530) : const Color(0xFFFAF5EA));
    final containerHigh = isLow
        ? (isNight ? const Color(0xFF4568A6) : const Color(0xFFEFF6FE))
        : (isNight ? const Color(0xFF2A3560) : ShiguangColors.paperDeep);
    final containerHighest = isLow
        ? (isNight ? const Color(0xFF4E72AE) : const Color(0xFFE1EDFA))
        : sky.horizon; // 糖果：借用天空地平线色（日间暖奶油、星夜靛蓝）

    final colorScheme = ColorScheme(
      // 星夜一律走深色：底色是深蓝/墨蓝，组件必须按暗色系排
      brightness: isNight ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: isLow
          ? (isNight ? const Color(0xFF4E72AE) : const Color(0xFFFFFFFF))
          : (isNight
              ? const Color(0xFF3A4468)
              : ShiguangColors.paperDeep),
      onPrimaryContainer: text,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: isLow
          ? secondary.withValues(alpha: isNight ? 0.45 : 0.25)
          : (isNight
              ? const Color(0xFF2E4033)
              : ShiguangColors.leafDark.withValues(alpha: 0.18)),
      onSecondaryContainer: text,
      error: ShiguangColors.danger,
      onError: ShiguangColors.paper,
      errorContainer: ShiguangColors.danger.withValues(alpha: 0.16),
      onErrorContainer: text,
      surface: bg,
      onSurface: text,
      onSurfaceVariant: subtleText,
      surfaceDim: isLow
          ? (isNight ? const Color(0xFF101B36) : const Color(0xFFDCE9F7))
          : (isNight ? const Color(0xFF111732) : ShiguangColors.paperDeep),
      surfaceBright: isLow
          ? (isNight ? const Color(0xFF3B5B94) : const Color(0xFFFFFFFF))
          : (isNight ? elevated : const Color(0xFFFBF6EA)),
      surfaceContainerLowest: containerLowest,
      surfaceContainerLow: isLow
          ? (isNight ? const Color(0xFF33527F) : const Color(0xFFF7FBFF))
          : (isNight ? const Color(0xFF1C2545) : ShiguangColors.paper),
      surfaceContainer: isLow || !isNight ? elevated : const Color(0xFF232D50),
      surfaceContainerHigh: containerHigh,
      surfaceContainerHighest: containerHighest,
      outline: outline,
      outlineVariant: dividerC,
      // 反相面：LowPoly 亮底反相成黑面板白字，星夜反相成冷白面板黑字
      inverseSurface: isLow
          ? (isNight
              ? ShiguangColors.polyNightText
              : ShiguangColors.polyOutline)
          : (isNight ? ShiguangColors.paper : ShiguangColors.inkBrown),
      onInverseSurface: isLow
          ? (isNight
              ? ShiguangColors.polyOutline
              : Colors.white)
          : (isNight
              ? ShiguangColors.inkBrown
              : ShiguangColors.paper),
      inversePrimary: isLow ? sky.glow : ShiguangColors.leafDark,
      shadow: Colors.black,
      scrim: Colors.black.withValues(alpha: 0.45),
    );

    // 中文正文用系统字体（google_fonts 国内网络不可靠，见 app_style 注释）
    const fallbacks = ['Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC'];
    final textTheme = TextTheme(
      // 大标题：加字距模拟海报手写体的呼吸感
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: 2,
        height: 1.25,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: 1.4,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: 1.2,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: text,
        letterSpacing: 0.8,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: text,
        letterSpacing: 0.6,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.7, color: text),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6, color: text),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: subtleText),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: text,
        letterSpacing: 1,
      ),
      labelMedium: TextStyle(fontSize: 12, color: subtleText, letterSpacing: 0.8),
      labelSmall: TextStyle(fontSize: 11, color: subtleText, letterSpacing: 0.6),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      fontFamilyFallback: const [...fallbacks],
      textTheme: textTheme,

      // —— 按钮组：统一 14px 圆角 + elevation 0，纸片感来自描边而非投影 ——
      // LowPoly 额外压一圈 1.6px 近黑描边（贴纸边）；糖果分支不带边，观感不动。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: text.withValues(alpha: 0.2),
          disabledForegroundColor: subtleText,
          elevation: 0,
          side: isLow
              ? const BorderSide(color: ShiguangColors.polyOutline, width: 1.6)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: elevated,
          foregroundColor: text,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          side: BorderSide(color: outline, width: isLow ? 1.6 : 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: outline, width: isLow ? 1.6 : 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: link,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // —— 对话框 / 卡片：纸面 + 描边边框，elevation 0 ——
      // LowPoly 的边是 1.6px 近黑硬边（贴纸轮廓），糖果保持原来的细边。
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline, width: isLow ? 1.6 : 1),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      cardTheme: CardThemeData(
        color: elevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline, width: isLow ? 1.6 : 1),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline, width: isLow ? 1.6 : 1),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: subtleText,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: outline, width: isLow ? 1.6 : 1),
        ),
      ),

      // —— 输入框：纸色填充 + 描边边框，聚焦换叶绿（选中=新芽） ——
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(color: subtleText, fontSize: 14),
        labelStyle: TextStyle(color: subtleText, fontSize: 14),
        floatingLabelStyle: TextStyle(
          color: secondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: secondary, width: 1.8),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: ShiguangColors.danger, width: 1.4),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: ShiguangColors.danger, width: 1.8),
        ),
      ),

      // —— 顶栏 / 列表 / 分割线 ——
      appBarTheme: AppBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: subtleText,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        titleTextStyle: textTheme.bodyLarge,
      ),
      dividerTheme: DividerThemeData(color: dividerC, thickness: 1, space: 1),

      // —— 轻反馈 / 状态 ——
      snackBarTheme: SnackBarThemeData(
        // 深棕条在日间像墨签，星夜换成亮靛以免黑上加黑；
        // LowPoly：亮底用纯黑签（白字），星夜用提亮的平涂蓝（深底上得先看得见）
        backgroundColor: isLow
            ? (isNight
                ? const Color(0xFF3B5B94)
                : ShiguangColors.polyOutline)
            : (isNight
                ? const Color(0xFF2E3A5E)
                : ShiguangColors.inkBrown),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: ShiguangColors.paper,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: secondary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: secondary.withValues(alpha: 0.35),
        selectionHandleColor: secondary,
      ),
    );
  }
}
