/// 分享卡片下载入口（条件导入的 web 分支）。
///
/// 浏览器没有可写的「文档目录」，改走 Blob + `<a download>` 触发下载：
/// 文件名与 io 分支同款 `shiguang_yyyymmdd.png`，返回该文件名作为「路径」
/// 展示（行内提示显示「已导出：shiguang_20260920.png」）。
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 把 PNG 字节打包成 Blob 并触发浏览器下载，返回文件名。
Future<String> saveShareCardPng(Uint8List bytes, int dayKey) async {
  final fileName = 'shiguang_$dayKey.png';
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click(); // 触发下载
  anchor.remove();
  // 延迟释放对象 URL：click 返回时下载可能还没把 Blob 读完，
  // 立刻 revoke 在个别浏览器上会中断下载
  Future<void>.delayed(const Duration(seconds: 1), () {
    web.URL.revokeObjectURL(url);
  });
  return fileName;
}
