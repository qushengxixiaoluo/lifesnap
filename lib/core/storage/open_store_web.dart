/// Web 端存储入口（条件导入的 web 分支）。
///
/// hive_ce 在浏览器上自动选用 IndexedDB 后端（homePath 传 null 即可），
/// 实现与桌面端同一套 box 结构，跨端数据语义一致。
///
/// 降级策略：隐私模式 / IndexedDB 被禁用时 openBox 会抛错，
/// 此时退回阶段 0 的内存实现——功能可用但不持久，写进 deviations 说明。
library;

import 'hive_photo_index_store.dart';
import 'photo_index_store.dart';

Future<PhotoIndexStore> openPhotoIndexStore() async {
  try {
    final store = HivePhotoIndexStore(null); // null → IndexedDB
    await store.init();
    return store;
  } catch (_) {
    // IndexedDB 不可用（隐私模式/被策略禁用）：宁可内存降级也不让应用起不来
    final store = InMemoryPhotoIndexStore();
    await store.init();
    return store;
  }
}
