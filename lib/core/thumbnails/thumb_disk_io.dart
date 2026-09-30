/// 缩略图磁盘层（io 平台实现）：真实文件读写与目录统计。
///
/// 单独成文件是为了让 thumb_cache.dart 不 import dart:io——
/// 缩略图门面必须能在 Web 上编译，平台 IO 走条件导入。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 缓存根目录的上级：系统临时目录（缩略图可再生，放 temp 让系统能自动清理）。
Future<String?> defaultThumbBaseDir() async {
  try {
    final dir = await getTemporaryDirectory();
    return dir.path;
  } catch (_) {
    // path_provider 插件未注册（单测宿主/极端启动场景）→ null，缓存降级为仅内存
    return null;
  }
}

Future<Uint8List?> readThumbFile(String absPath) async {
  final file = File(absPath);
  if (!file.existsSync()) return null;
  return file.readAsBytes();
}

Future<void> writeThumbFile(String absPath, Uint8List bytes) async {
  final file = File(absPath);
  await file.parent.create(recursive: true); // 分桶子目录首次写入时现建
  await file.writeAsBytes(bytes, flush: true); // flush：崩溃/强杀后不留半截文件
}

/// 递归统计目录占用字节数（设置页「缓存 12.3MB」的数据源）。
Future<int> measureDirBytes(String dir) async {
  final root = Directory(dir);
  if (!root.existsSync()) return 0;
  var total = 0;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {/* 竞态删除：忽略 */}
    }
  }
  return total;
}

/// 删除整个目录并返回释放字节数（先量后删，删失败也不影响返回值语义）。
Future<int> clearDirBytes(String dir) async {
  final freed = await measureDirBytes(dir);
  final root = Directory(dir);
  if (root.existsSync()) {
    try {
      await root.delete(recursive: true);
    } catch (_) {/* 个别文件被占用：剩余部分下次 clearAll 再清 */}
  }
  return freed;
}
