/// 分享卡片动作的 io 分支（Android / iOS / Windows / macOS / Linux）。
///
/// 手机：photo_manager 写系统相册（Android 用 MediaStore，自己的文件无需
/// 存储权限；iOS 走 add-only 相册权限）。
/// 桌面：没有「相册」概念，落盘到导出目录并把完整路径交给提示文案。
library;

import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../settings/settings_utils.dart';
import 'share_export_io.dart';

Future<String> saveShareCardToGallery(Uint8List bytes, int dayKey) async {
  if (!isMobilePlatform) {
    final path = await saveShareCardPng(bytes, dayKey);
    return '已保存到文件：$path';
  }
  // 「仅添加到相册」权限：iOS 14+ 的有限授权（不给读整个相册）；
  // Android 10+ 插件内部视为已授权（插入自己的媒体不需要存储权限）。
  final perm = await PhotoManager.requestPermissionExtend(
    requestOption: const PermissionRequestOption(
      iosAccessLevel: IosAccessLevel.addOnly,
    ),
  );
  if (!perm.hasAccess) {
    throw Exception('没有相册写入权限，请到系统设置里开启');
  }
  await PhotoManager.editor.saveImage(
    bytes,
    filename: 'shiguang_$dayKey.png',
    title: '拾光手册',
  );
  return '已保存到相册';
}

Future<String> saveShareCardFile(Uint8List bytes, int dayKey) async {
  final path = await saveShareCardPng(bytes, dayKey);
  return '已保存到文件：$path';
}
