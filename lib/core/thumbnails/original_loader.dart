/// 原图字节读取（条件导入的统一入口）。
///
/// 用途：全屏查看器要显示「原图级」清晰度——本地文件直接读原图字节，
/// 相册资产走 photo_manager 的 originBytes（原图，而非 thumbnailData）。
/// Web 无文件系统访问，返回 null，查看器降级为 1280 档缩略图占位。
library;

import 'dart:typed_data';

import 'original_loader_io.dart'
    if (dart.library.html) 'original_loader_web.dart' as impl;

/// 读取 [sourcePath] 的原图字节；读不到返回 null（调用方降级显示缩略图）。
Future<Uint8List?> loadOriginalBytes(String sourcePath) =>
    impl.loadOriginalBytes(sourcePath);
