/// API Key 安全存取（阶段 0 完整实现，任何轨都不得修改；E 轨写入、D 轨读取）。
///
/// - 首选 flutter_secure_storage（Android Keystore / Windows DPAPI / iOS Keychain）
/// - Web 或 secure storage 失败时降级 SharedPreferences（键名带 _insecure_ 标记，
///   便于日后审计识别非加密存储）
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiKeyStore {
  ApiKeyStore._();

  static const _secureKey = 'anthropic_or_openai_api_key';
  static const _insecureKey = 'api_key_insecure_fallback';
  static const _secure = FlutterSecureStorage();

  /// 读取 API Key；无值返回 null。
  static Future<String?> read() async {
    try {
      final v = await _secure.read(key: _secureKey);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {/* 平台不支持时走降级 */}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_insecureKey);
  }

  /// 保存（传空串视为清除）。
  static Future<void> write(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await delete();
      return;
    }
    try {
      await _secure.write(key: _secureKey, value: trimmed);
      // 成功后清掉可能存在的降级副本，避免双源不一致
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_insecureKey);
      return;
    } catch (_) {/* 降级 */}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_insecureKey, trimmed);
  }

  /// 清除。
  static Future<void> delete() async {
    try {
      await _secure.delete(key: _secureKey);
    } catch (_) {/* 忽略 */}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_insecureKey);
  }

  /// 是否已存有 key（设置页显示「已保存 ✓」、缺 key 弹窗判断）。
  static Future<bool> exists() async => (await read()) != null;
}
