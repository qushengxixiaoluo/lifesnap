/// ThemeData 工厂（A 轨交付版：组件级排版 + 星夜对比度适配）。
///
/// 约定：
/// 1) 所有会随皮肤变化的值一律由 AppStyle 推导（沿 interview_calendar 约定）；
/// 2) 层次一律用「纸色深浅 + 手绘描边」表达——所有组件 elevation: 0，
///    禁止 Material 默认阴影营造层次（画风是平涂手绘，不是拟物投影）；
/// 3) 星夜适配：纸面转墨蓝、主色反转为「暖纸金底 + 深墨字」，
///    保证深色环境下按钮/文字对比度依然 ≥ 4.5:1 的方向。
library;

import 'package:flutter/material.dart';

import 'app_style.dart';

class AppTheme {
  AppTheme._();

  /// 由皮肤构建完整主题。签名是契约：main.dart 与各页面依赖此函数。
  static ThemeData build(AppStyle style) {
    final isNight = style == AppStyle.night;
    final sky = skyOf(style);
    final text = textColorOf(style);
    // 次级文字：星夜下纸白压到 72% 仍足够亮，日间墨棕 62% 做弱化层
    final subtleText = text.withValues(alpha: isNight ? 0.72 : 0.62);

    // 结构底色：星夜转深墨蓝，避免亮纸在夜里刺眼
    final bg = isNight ? const Color(0xFF1A2138) : ShiguangColors.paper;
    // 抬升面（对话框/菜单/底表）：星夜亮一档，日间水彩纸
    final elevated = isNight ? const Color(0xFF253054) : ShiguangColors.paper;
    // 输入框底：星夜压深一档便于识别可输入区，日间用纸影色
    final inputFill = isNight
        ? const Color(0xFF141B31)
        : ShiguangColors.paperDeep.withValues(alpha: 0.55);

    // 主色策略：日间墨棕底配纸白字；星夜反过来用暖纸金底配深墨字——
    // 深色环境里深棕按钮会沉进背景，必须把按钮点亮才点得动
    final primary = isNight ? const Color(0xFFE9C9A0) : ShiguangColors.inkBrown;
    final onPrimary = isNight ? const Color(0xFF2B2216) : ShiguangColors.paper;
    final secondary = isNight ? const Color(0xFF93C48C) : ShiguangColors.leafDark;
    final onSecondary = isNight ? const Color(0xFF16220F) : ShiguangColors.paper;
    final outline = isNight
        ? ShiguangColors.paper.withValues(alpha: 0.30)
        : ShiguangColors.wood.withValues(alpha: 0.55);
    final dividerC = isNight
        ? ShiguangColors.paper.withValues(alpha: 0.16)
        : ShiguangColors.wood.withValues(alpha: 0.30);

    final colorScheme = ColorScheme(
      brightness: isNight ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: isNight
          ? const Color(0xFF3A4468)
          : ShiguangColors.paperDeep,
      onPrimaryContainer: text,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: isNight
          ? const Color(0xFF2E4033)
          : ShiguangColors.leafDark.withValues(alpha: 0.18),
      onSecondaryContainer: text,
      error: ShiguangColors.danger,
      onError: ShiguangColors.paper,
      errorContainer: ShiguangColors.danger.withValues(alpha: 0.16),
      onErrorContainer: text,
      surface: bg,
      onSurface: text,
      onSurfaceVariant: subtleText,
      surfaceDim: isNight ? const Color(0xFF111732) : ShiguangColors.paperDeep,
      surfaceBright: isNight ? elevated : const Color(0xFFFBF6EA),
      surfaceContainerLowest:
          isNight ? const Color(0xFF0F1530) : const Color(0xFFFAF5EA),
      surfaceContainerLow:
          isNight ? const Color(0xFF1C2545) : ShiguangColors.paper,
      surfaceContainer: isNight ? const Color(0xFF232D50) : elevated,
      surfaceContainerHigh:
          isNight ? const Color(0xFF2A3560) : ShiguangColors.paperDeep,
      // 最高层容器借用天空地平线色：日间暖奶油、星夜靛蓝，都是「有色纸」
      surfaceContainerHighest: sky.horizon,
      outline: outline,
      outlineVariant: dividerC,
      inverseSurface: isNight ? ShiguangColors.paper : ShiguangColors.inkBrown,
      onInverseSurface: isNight ? ShiguangColors.inkBrown : ShiguangColors.paper,
      inversePrimary: ShiguangColors.leafDark,
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
        // 深棕条在日间像墨签，星夜换成亮靛以免黑上加黑
        backgroundColor: isNight ? const Color(0xFF2E3A5E) : ShiguangColors.inkBrown,
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
