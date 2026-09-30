/// 缩略图生成（Web 分支桩）。
///
/// Web 源路径是 `web://相对路径`，浏览器不提供随机读取该路径的能力：
/// File System Access 的目录句柄只在本次会话有效且无法随索引持久化，
/// 重新拿句柄需要用户交互，不能在缩略图生成这种静默路径里做。
/// 因此恒返回 null → ThumbImage 保持水彩占位（不报错、不重试风暴）。
library;

import 'dart:typed_data';

Future<Uint8List?> generateThumb(String sourcePath, int bucketSize) async =>
    null;
