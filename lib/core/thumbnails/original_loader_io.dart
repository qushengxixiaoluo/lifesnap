/// 原图字节读取（io 平台：桌面文件 / 移动相册）。
///
/// 相册资产优先 originBytes（原图），失败才退回 thumbnailData——
/// 之前的生成链直接用 thumbnailData 就是「放大看着糊」的根源之一。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

Future<Uint8List?> loadOriginalBytes(String sourcePath) async {
  if (sourcePath.startsWith('pm://')) {
    try {
      final asset = await AssetEntity.fromId(sourcePath.substring(5));
      if (asset == null) return null;
      final origin = await asset.originBytes; // 原图字节（大，仅查看器用）
      if (origin != null && origin.isNotEmpty) return origin;
      return await asset.thumbnailData; // 原图拿不到时的兜底
    } catch (_) {
      return null; // 权限过期 / 桌面无插件实现
    }
  }
  try {
    return await File(sourcePath).readAsBytes();
  } catch (_) {
    return null; // 文件被删/无权限
  }
}
