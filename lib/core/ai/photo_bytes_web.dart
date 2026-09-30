/// 照片字节读取 · Web 实现。
///
/// 为什么不用 dart:html：它已废弃，分析器会报 deprecated（本仓 analyze 把
/// info 视为失败）。package:http 在浏览器里走 BrowserClient（fetch），
/// 既能拿同源的 `web://` 资源，也能拿绝对 URL。
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 读取照片原始字节；任何失败都返回 null（与 io 实现保持同一契约）。
Future<Uint8List?> readPhotoBytes(String path) async {
  try {
    var target = path;
    if (target.startsWith('web://')) target = target.substring('web://'.length);
    if (target.isEmpty) return null;
    // 相对路径按当前页面地址解析（B 轨在 Web 上存的正是这种相对路径）
    final uri = target.startsWith('http://') || target.startsWith('https://')
        ? Uri.parse(target)
        : Uri.base.resolve(target);
    final resp = await http.get(uri);
    return resp.statusCode == 200 ? resp.bodyBytes : null;
  } catch (_) {
    return null;
  }
}
