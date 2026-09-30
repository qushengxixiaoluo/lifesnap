/// 缩略图生成入口（条件导入门面）。
///
/// io 分支：读源文件 → isolate 解码缩放 → JPEG q80 编码；
/// Web 分支：web:// 源没有可随机读取的文件句柄（File System Access 的句柄
/// 不跨会话持久化），恒返回 null，由 ThumbImage 维持水彩占位。
library;

import 'dart:typed_data';

import 'thumb_generator_io.dart'
    if (dart.library.html) 'thumb_generator_web.dart' as impl;

/// 生成目标档位（256/512）的 JPEG 字节；任何一步失败返回 null（不抛给 UI）。
Future<Uint8List?> generateThumb(String sourcePath, int bucketSize) =>
    impl.generateThumb(sourcePath, bucketSize);
