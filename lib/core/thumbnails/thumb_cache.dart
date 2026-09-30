/// 缩略图缓存门面：内存 LRU + 磁盘二级分桶。
///
/// 【钉死的签名】E 轨设置页「清缓存」盲写对接：
/// `ThumbCache.clearAll()` / `ThumbCache.sizeBytes()` 的类名、静态方法名与签名
/// 与阶段 0 桩保持完全一致，只把返回 0 的占位逻辑换成真实统计。
///
/// 分层：thumb_paths（纯算法，可单测）→ thumb_disk_*（条件导入的平台 IO）→ 本文件（编排）。
library;

import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'thumb_disk_io.dart'
    if (dart.library.html) 'thumb_disk_web.dart' as disk;
import 'thumb_paths.dart';

class ThumbCache {
  ThumbCache._();

  /// 内存 LRU 上限 48MB：约等于 300 张 256px JPEG 源字节，一屏滚动全命中。
  static final ThumbLru lru = ThumbLru(maxBytes: 48 * 1024 * 1024);

  /// 淘汰钩子：ThumbImage 用它把落选键的 ValueNotifier 置空（见 thumb_image.dart）。
  static set onEvict(void Function(String key)? callback) => lru.onEvict = callback;

  /// 测试注入点：指定后覆盖 path_provider，直接读写临时目录。
  static String? debugRootOverride;

  static String? _cachedRoot;

  /// 缓存键：`源路径@档位`，256/512 各自独立计费。
  static String cacheKey(String sourcePath, num size) =>
      '$sourcePath@${normalizeThumbSize(size)}';

  /// 相对路径（与 thumbRelativePath 同规则，暴露给需要预判命中的调用方）。
  static String relativePathFor(String sourcePath, num size) =>
      thumbRelativePath(sourcePath, normalizeThumbSize(size));

  /// 绝对磁盘路径；根目录不可用（Web/无 path_provider）返回 null。
  static Future<String?> absolutePathFor(String sourcePath, num size) async {
    final root = await _root();
    if (root == null) return null;
    return p.join(root, thumbRelativePath(sourcePath, normalizeThumbSize(size)));
  }

  static Future<String?> _root() async {
    if (_cachedRoot != null) return _cachedRoot;
    if (debugRootOverride != null) {
      _cachedRoot = debugRootOverride;
      return _cachedRoot;
    }
    final base = await disk.defaultThumbBaseDir();
    _cachedRoot = base == null ? null : p.join(base, 'thumbs');
    return _cachedRoot;
  }

  /// 仅内存命中（同步路径：ThumbImage build 时首帧判定用）。
  static Uint8List? memoryGet(String sourcePath, num size) =>
      lru.get(cacheKey(sourcePath, size));

  /// 内存 → 磁盘 两级读取；都未命中返回 null（由调用方入队生成）。
  static Future<Uint8List?> get(String sourcePath, num size) async {
    final key = cacheKey(sourcePath, size);
    final hot = lru.get(key);
    if (hot != null) return hot;
    final abs = await absolutePathFor(sourcePath, size);
    if (abs == null) return null;
    final bytes = await disk.readThumbFile(abs);
    if (bytes != null) lru.put(key, bytes); // 回填内存，下次滚动零 IO
    return bytes;
  }

  /// 写入两级缓存（生成器产出后调用）。
  static Future<void> put(String sourcePath, num size, Uint8List bytes) async {
    lru.put(cacheKey(sourcePath, size), bytes);
    final abs = await absolutePathFor(sourcePath, size);
    if (abs != null) await disk.writeThumbFile(abs, bytes);
  }

  /// 清空全部磁盘缩略图缓存，返回释放字节数。
  static Future<int> clearAll() async {
    lru.clear(); // 内存层一起清：设置页「清缓存」语义 = 全部重来
    final root = await _root();
    if (root == null) return 0;
    return disk.clearDirBytes(root);
  }

  /// 当前缓存占用字节数（设置页展示；以磁盘为准，内存是其副本）。
  static Future<int> sizeBytes() async {
    final root = await _root();
    if (root == null) return 0;
    return disk.measureDirBytes(root);
  }

  /// 仅测试用：重置根目录缓存并切换到指定目录（null = 恢复自动探测）。
  static void debugReset({String? root}) {
    debugRootOverride = root;
    _cachedRoot = null;
    lru.clear();
    onEvict = null;
  }
}
