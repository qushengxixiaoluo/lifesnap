/// 分享卡片的「后一步」动作：渲染出 PNG 字节之后的去向。
///
/// - [saveShareCardToGallery]：手机写系统相册（photo_manager / MediaStore），
///   桌面没有相册概念 → 存文件，Web → 浏览器下载；
/// - [shareShareCard]：调起系统分享面板（share_plus）——微信 / QQ / 邮件
///   都在面板里，用户自己选；绝不集成某一家的 SDK。
///
/// 平台差异全部收在条件导入的 io/web 两个实现里，调用方只见本文件。
library;

import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../../core/models/models.dart';
import 'share_actions_web.dart'
    if (dart.library.io) 'share_actions_io.dart' as platform;

/// 保存卡片到相册（手机）/ 文件（桌面）/ 下载（Web），返回行内提示文案。
Future<String> saveShareCardToGallery(Uint8List bytes, int dayKey) =>
    platform.saveShareCardToGallery(bytes, dayKey);

/// 纯落盘：把 PNG 写成文件并返回路径（手机上的「保存为文件」动作 / 桌面兜底）。
Future<String> saveShareCardFile(Uint8List bytes, int dayKey) =>
    platform.saveShareCardFile(bytes, dayKey);

/// 调起系统分享面板把卡片分享出去（微信等第三方都在面板里）。
Future<void> shareShareCard(Uint8List bytes, int dayKey) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'shiguang_$dayKey.png',
        ),
      ],
      text: '拾光手册 · ${dayKeyToChinese(dayKey)}',
    ),
  );
}
