/// 分享卡片动作的 web 分支：浏览器没有相册，触发下载即「保存」。
library;

import 'dart:typed_data';

import 'share_export_web.dart';

Future<String> saveShareCardToGallery(Uint8List bytes, int dayKey) async {
  final name = await saveShareCardPng(bytes, dayKey);
  return '已开始下载：$name';
}

Future<String> saveShareCardFile(Uint8List bytes, int dayKey) =>
    saveShareCardToGallery(bytes, dayKey);
