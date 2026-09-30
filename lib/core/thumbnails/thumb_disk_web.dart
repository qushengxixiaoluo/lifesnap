/// 缩略图磁盘层（Web 分支桩）：浏览器无 dart:io 文件系统，
/// 磁盘缓存整体停用，ThumbCache 自动降级为「仅内存 LRU」。
///
/// 返回值语义与 io 实现对齐：读永远 miss、写是无操作、统计恒 0，
/// 让 thumb_cache.dart 的主逻辑无需分支判断。
library;

import 'dart:typed_data';

Future<String?> defaultThumbBaseDir() async => null;

Future<Uint8List?> readThumbFile(String absPath) async => null;

Future<void> writeThumbFile(String absPath, Uint8List bytes) async {}

Future<int> measureDirBytes(String dir) async => 0;

Future<int> clearDirBytes(String dir) async => 0;
