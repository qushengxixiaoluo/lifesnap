/// 缩略图路径规则与内存 LRU（纯 Dart，全平台可编译、可直接单测）。
///
/// 拆成独立文件的原因：路径分桶与 LRU 淘汰顺序是本轨最容易回归的两块逻辑，
/// 必须能在不碰文件系统/平台通道的前提下直接跑断言。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 目标边长 → 磁盘桶（256 = 节点/网格，512 = 详情 hero）。
///
/// 只保留两档：档位越少同目录文件越多、分桶越满，且两档恰好覆盖现有 UI 用途；
/// 384 为中界（两档中间），小于它的请求统一降到 256，避免出现 257 这种碎档。
int normalizeThumbSize(num size) => size < 384 ? 256 : 512;

/// 缓存相对路径：`{256|512}/{sha1前2位}/{sha1}.jpg`。
///
/// - sha1(sourcePath)：同一张图跨进程路径恒定，重命名源图即自然失效；
/// - 前 2 位做二级分桶：单目录文件数从 N 降到 N/256，
///   几万张缩略图时 Windows 资源管理器/文件系统遍历不会被单目录拖垮。
String thumbRelativePath(String sourcePath, int bucketSize) {
  final hex = sha1.convert(utf8.encode(sourcePath)).toString();
  return '$bucketSize/${hex.substring(0, 2)}/$hex.jpg';
}

/// 内存字节 LRU（约 48MB）：滚动相册时已解码源字节直接命中，
/// 不必每次回读磁盘；48MB 约等于 300 张 256px JPEG，足够一屏来回滚动。
class ThumbLru {
  ThumbLru({required this.maxBytes});

  final int maxBytes;

  /// LinkedHashMap 迭代顺序 = 插入顺序：get/put 时「删了再插」即把键挪到队尾，
  /// 队首自然就是最久未用者——不需要额外的链表结构。
  final _map = <String, Uint8List>{};

  int usedBytes = 0;

  /// 淘汰回调：ThumbImage 借此把对应 ValueNotifier 置空，释放强引用，
  /// 否则字节被 notifier 钉住，LRU 的上限就成了摆设。
  void Function(String evictedKey)? onEvict;

  int get length => _map.length;

  /// 由旧到新的键序（测试用：断言淘汰顺序）。
  List<String> get keysInOrder => _map.keys.toList();

  Uint8List? get(String key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value; // 命中即移到队尾（最新）
    return value;
  }

  void put(String key, Uint8List value) {
    final old = _map.remove(key);
    if (old != null) usedBytes -= old.length;
    _map[key] = value;
    usedBytes += value.length;

    // 淘汰到水位线以下；至少保留一项：单张超大图宁可超限也不无限循环
    while (usedBytes > maxBytes && _map.length > 1) {
      final eldestKey = _map.keys.first;
      final eldest = _map.remove(eldestKey)!;
      usedBytes -= eldest.length;
      onEvict?.call(eldestKey);
    }
  }

  void clear() {
    _map.clear();
    usedBytes = 0;
  }
}
