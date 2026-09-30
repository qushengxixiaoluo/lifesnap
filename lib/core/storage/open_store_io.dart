/// 桌面/移动端存储入口（条件导入的 io 分支）。
///
/// 平台分流（阶段 0 桩已按计划替换为真实现）：
/// - Android/iOS → sqflite（系统 SQLite，移动端聚合查询省电省内存）
/// - Windows/macOS/Linux → hive_ce（纯 Dart，避开桌面 sqlite3 原生库分发坑）
///
/// 本文件只被非 Web 编译单元引用，import dart:io 安全（Web 走 open_store_web.dart）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'hive_photo_index_store.dart';
import 'photo_index_store.dart';
import 'sqflite_photo_index_store.dart';

Future<PhotoIndexStore> openPhotoIndexStore() async {
  // 移动端走 SQL：几万张照片的 GROUP BY 聚合由 SQLite 完成
  if (Platform.isAndroid || Platform.isIOS) {
    final store = SqflitePhotoIndexStore();
    await store.init();
    return store;
  }

  // 桌面端走 hive_ce：hive 会把 .hive 文件写在 homePath 下，目录必须先存在
  String home;
  try {
    final support = await getApplicationSupportDirectory();
    home = p.join(support.path, 'shiguang_index');
  } catch (_) {
    // path_provider 插件未注册（如部分单元测试宿主）时退回系统临时目录，保证仍可用
    home = p.join(Directory.systemTemp.path, 'shiguang_index');
  }
  await Directory(home).create(recursive: true);

  final store = HivePhotoIndexStore(home);
  await store.init();
  return store;
}
