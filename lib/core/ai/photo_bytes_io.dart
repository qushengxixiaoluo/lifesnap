/// 照片字节读取 · 非 Web 平台实现（桌面绝对路径 / 手机相册 pm://）。
///
/// 为什么条件导入：共享代码直接 import dart:io 会让 Web 编译炸掉，
/// 所以 dart:io 只允许出现在这个只在 io 平台被加载的文件里。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';

/// 相册缩略图的目标边长：与 ai_image_preparer 的 kMaxImageEdge(1568) 对齐。
/// 不反向 import 那边的常量——本文件被 ai_image_preparer 条件导入，
/// 再 import 回去会成环，数值一致性靠这条注释守住。
const int _albumThumbEdge = 1568;

/// 读取照片原始字节；任何失败（路径不存在、相册没授权、格式不认）都返回 null，
/// 由调用方决定跳过还是给中文提示，不让单张坏图打断整天的总结。
Future<Uint8List?> readPhotoBytes(String path) async {
  try {
    if (path.startsWith('pm://')) {
      // 手机相册：photo_manager 的资产 id 需要在主 isolate 取（走平台通道）
      final asset = await AssetEntity.fromId(path.substring('pm://'.length));
      if (asset == null) return null;
      // 为什么不用 originBytes：iCloud 未下载原片、系统隐私策略等场景下它可能
      // 返回 null 或拿不到可解码数据（缩略图轨已注明该接口在部分场景的坑）。
      // 改取系统转码后的 JPEG 缩略图：HEIC→JPEG 由相册系统完成，
      // 出来的字节全平台的解码器都认，AI 压图链路不再挑原片格式。
      const size = ThumbnailSize.square(_albumThumbEdge);
      final option = (Platform.isIOS || Platform.isMacOS)
          // 显式 fit：thumbnailDataWithSize 把 resizeMode 硬编码成 fill
          // （aspectFill），横幅照片会被中心裁成方图——AI 要看的是整幅画面。
          ? ThumbnailOption.ios(
              size: size,
              format: ThumbnailFormat.jpeg,
              quality: 100,
              resizeContentMode: ResizeContentMode.fit,
            )
          : ThumbnailOption(
              size: size,
              format: ThumbnailFormat.jpeg,
              quality: 100,
            );
      return await asset.thumbnailDataWithOption(option);
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final resp = await http.get(Uri.parse(path));
      return resp.statusCode == 200 ? resp.bodyBytes : null;
    }
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
