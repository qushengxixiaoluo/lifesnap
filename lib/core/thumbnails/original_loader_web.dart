/// 原图字节读取（Web）：浏览器拿不到本地文件原始路径，
/// 返回 null 让查看器停留在 1280 档缩略图占位（诚实降级）。
library;

import 'dart:typed_data';

Future<Uint8List?> loadOriginalBytes(String sourcePath) async => null;
