/// 设置页公共小工具（E 轨私有）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_style.dart';

/// 当前是否移动平台：控制「手机相册」开关的显隐。
///
/// 为什么不用 dart:io 的 Platform：铁律禁止共享代码直接 import dart:io
/// （Web 编译会炸）。foundation 的 defaultTargetPlatform 走条件导入，
/// Windows/macOS/Linux/Android/iOS/Web 六端都能正常编译判定。
/// 单测环境它恒为 Android，所以测试里会看到相册开关，属预期。
bool get isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 字节数 → 人类可读（缓存占用展示）。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 毫秒时间戳 → 「2026-09-01 10:30」（上次扫描时间）。
///
/// 手写格式化而不引 intl 的 DateFormat：后者默认 locale 是 en_US，
/// 要中文月份还得额外初始化 locale 数据，这里只需要数字，没必要拉依赖。
String formatTimeMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// 分区标题：图标 + 文案，四个分区视觉统一。
///
/// 文字色走主题（textTheme），随日光/黄昏/星夜皮肤自动切换，
/// 不写死墨棕，否则星夜皮肤下标题会糊在深底上。
Widget sectionTitle(BuildContext context, IconData icon, String title,
    {String? subtitle}) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 18, color: ShiguangColors.leafDark),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.titleMedium),
        ],
      ),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: theme.textTheme.bodySmall),
        ),
    ],
  );
}
