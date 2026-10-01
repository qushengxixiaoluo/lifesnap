/// 分享卡片本地落盘（条件导入的 io 分支）。
///
/// 路径约定：应用文档目录 `shiguang_handbook/exports/shiguang_yyyymmdd.png`。
/// path_provider 在部分单测宿主里没有实现（MissingPluginException），
/// 此时回退 `Directory.systemTemp`——导出仍成功，测试也能断言文件存在。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把 PNG 字节写到本地导出目录，返回绝对路径。
Future<String> saveShareCardPng(Uint8List bytes, int dayKey) async {
  Directory base;
  try {
    base = await getApplicationDocumentsDirectory();
  } catch (_) {
    // path_provider 插件未注册（单测宿主/极端启动场景）→ 退回系统临时目录
    base = Directory.systemTemp;
  }
  // mkdir 兜底：exports 目录首次导出时还不存在，recursive 对已存在目录幂等
  final dir = Directory(p.join(base.path, 'shiguang_handbook', 'exports'));
  dir.createSync(recursive: true);
  final file = File(p.join(dir.path, 'shiguang_$dayKey.png'));
  // 同步写：导出是一次性动作，几百 KB 不值得为它把状态机挂到事件循环上；
  // widget 测试的假异步下同步写也天然可完成（异步 IO 需要真实事件循环）
  file.writeAsBytesSync(bytes, flush: true);
  return file.absolute.path;
}
