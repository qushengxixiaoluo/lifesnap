/// ThemeData 工厂（A 轨交付版：组件级排版 + 星夜对比度适配 + 画风轴）。
///
/// 约定：
/// 1) 所有会随「天色 × 画风」变化的值一律由 tokensFor/textColorFor 推导；
/// 2) 层次一律用「纸色深浅 + 手绘描边」表达——所有组件 elevation: 0，
///    禁止 Material 默认阴影营造层次（画风是平涂手绘，不是拟物投影）；
/// 3) 星夜适配：纸面转墨蓝、主色反转为「暖纸金底 + 深墨字」，
///    保证深色环境下按钮/文字对比度依然 ≥ 4.5:1 的方向；
/// 4) 油墨旧纸适配：结构色直接取该档天色的三段「旧纸」渐变，
///    组件底色与天空同出一张纸（不会天是旧纸、卡片却是水彩纸）。
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
    final isAged = artStyle == ArtStyle.agedInk;
    final sky = tokensFor(style, artStyle);
    final text = textColorFor(style, artStyle);
    // 次级文字：星夜下纸白压到 72% 仍足够亮，日间墨棕 62% 做弱化层
    final subtleText = text.withValues(alpha: isNight ? 0.72 : 0.62);

    // —— 结构底色 ——
    // 糖果：星夜转深墨蓝、日间水彩纸（观感不得回退）；
    // 油墨旧纸：直接取本档天色的三段纸渐变——top 最深（受潮）、mid 是纸面、
    // horizon 最浅（边角），于是卡片/对话框/输入框与天空同源同纸。
    final bg =
        isAged ? sky.mid : (isNight ? const Color(0xFF1A2138) : ShiguangColors.paper);
    // 抬升面（对话框/菜单/底表）：夜里亮一档、日间浅一档，始终比 bg 好分辨
    final elevated = isAged
        ? sky.horizon
        : (isNight ? const Color(0xFF253054) : ShiguangColors.paper);
    // 输入框底：旧纸取最深的受潮块；糖果星夜压深一档、日间用纸影色
    final inputFill = isAged
        ? sky.top
        : (isNight
            ? const Color(0xFF141B31)
            : ShiguangColors.paperDeep.withValues(alpha: 0.55));

    // 主色策略：糖果日间墨棕底配纸白字，星夜反转成暖纸金底配深墨字；
    // 旧纸白天用墨色按钮配浅纸字，夜里反过来用淡纸色按钮配墨字——
    // 深色环境里深棕按钮会沉进背景，必须把按钮点亮才点得动
    final primary = isAged
        ? (isNight
            ? ShiguangColors.agedPaperText
            : ShiguangColors.agedInkText)
        : (isNight ? const Color(0xFFE9C9A0) : ShiguangColors.inkBrown);
    final onPrimary = isAged
        ? (isNight ? sky.top : sky.horizon)
        : (isNight ? const Color(0xFF2B2216) : ShiguangColors.paper);
    // 强调色：糖果用叶绿；旧纸用朱砂——旧信纸上唯一允许跳出来的颜色
    final secondary = isAged
        ? (isNight
            ? ShiguangColors.cinnabarBright
            : ShiguangColors.cinnabar)
        : (isNight ? const Color(0xFF93C48C) : ShiguangColors.leafDark);
    final onSecondary = isAged
        ? (isNight ? sky.top : sky.horizon)
        : (isNight ? const Color(0xFF16220F) : ShiguangColors.paper);
    final outline = isAged
        ? (isNight
            ? ShiguangColors.agedPaperText.withValues(alpha: 0.30)
            : ShiguangColors.agedInkText.withValues(alpha: 0.45))
        : (isNight
            ? ShiguangColors.paper.withValues(alpha: 0.30)
            : ShiguangColors.wood.withValues(alpha: 0.55));
    final dividerC = isAged
        ? (isNight
            ? ShiguangColors.agedPaperText.withValues(alpha: 0.16)
            : ShiguangColors.agedInkText.withValues(alpha: 0.28))
        : (isNight
            ? ShiguangColors.paper.withValues(alpha: 0.16)
            : ShiguangColors.wood.withValues(alpha: 0.30));

    // 油墨旧纸的容器色阶：旧纸三段色本身就是一条「深→浅」的纸纹坡，
    // 按亮/暗主题各排一次，保证列表/菜单层层可分（糖果仍走原靛蓝/纸色阶）。
    final containerLowest = isAged
        ? (isNight
            ? sky.top
            : Color.lerp(sky.horizon, const Color(0xFFFFFFFF), 0.4)!)
        : (isNight ? const Color(0xFF0F1530) : const Color(0xFFFAF5EA));
    final containerHigh = isAged
        ? (isNight
            ? Color.lerp(sky.horizon, const Color(0xFFFFFFFF), 0.07)!
            : sky.mid)
        : (isNight ? const Color(0xFF2A3560) : ShiguangColors.paperDeep);
    final containerHighest = isAged
        ? (isNight
            ? Color.lerp(sky.horizon, const Color(0xFFFFFFFF), 0.14)!
            : sky.top)
        : sky.horizon; // 糖果：借用天空地平线色（日间暖奶油、星夜靛蓝）

    final colorScheme = ColorScheme(
      // 暗墨夜读与糖果星夜一样走深色：底色是深墨褐纸，组件必须按暗色系排
      brightness: isNight ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: isAged
          ? (isNight
              ? Color.lerp(sky.horizon, const Color(0xFFFFFFFF), 0.10)!
              : sky.top)
          : (isNight
              ? const Color(0xFF3A4468)
              : ShiguangColors.paperDeep),
      onPrimaryContainer: text,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: isAged
          ? secondary.withValues(alpha: isNight ? 0.30 : 0.18)
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
      surfaceDim: isAged
          ? sky.top
          : (isNight ? const Color(0xFF111732) : ShiguangColors.paperDeep),
      surfaceBright: isAged
          ? sky.horizon
          : (isNight ? elevated : const Color(0xFFFBF6EA)),
      surfaceContainerLowest: containerLowest,
      surfaceContainerLow: isAged
          ? (isNight ? sky.mid : sky.horizon)
          : (isNight ? const Color(0xFF1C2545) : ShiguangColors.paper),
      surfaceContainer: isAged || !isNight ? elevated : const Color(0xFF232D50),
      surfaceContainerHigh: containerHigh,
      surfaceContainerHighest: containerHighest,
      outline: outline,
      outlineVariant: dividerC,
      // 反相面：糖果星夜是「亮纸压暗字」，旧纸夜读同样要一张浅纸反相过来
      inverseSurface: isAged
          ? (isNight
              ? ShiguangColors.agedPaperText
              : ShiguangColors.agedInkText)
          : (isNight ? ShiguangColors.paper : ShiguangColors.inkBrown),
      onInverseSurface: isAged
          ? (isNight
              ? ShiguangColors.agedInkText
              : sky.horizon)
          : (isNight
              ? ShiguangColors.inkBrown
              : ShiguangColors.paper),
      inversePrimary: isAged
          ? (isNight
              ? ShiguangColors.cinnabar
              : ShiguangColors.cinnabarBright)
          : ShiguangColors.leafDark,
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: text.withValues(alpha: 0.2),
          disabledForegroundColor: subtleText,
          elevation: 0,
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
          side: BorderSide(color: outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: outline, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // —— 对话框 / 卡片：纸面 + 手绘描边边框，elevation 0 ——
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline),
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
          side: BorderSide(color: outline),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline),
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
          side: BorderSide(color: outline),
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
        // 旧纸夜里改用「比纸面亮一档的褐色」——靛蓝压在旧纸上会色温脱轨
        backgroundColor: isAged
            ? (isNight
                ? const Color(0xFF4A3B29)
                : ShiguangColors.agedInkText)
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
