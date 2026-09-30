/// 非敏感设置存取（阶段 0 完整实现，任何轨都不得修改；E 轨读写，D 轨读取）。
///
/// 只放非敏感配置：AI provider/baseUrl/model/图数上限/effort、皮肤已在
/// AppStyleNotifier 管理。API key 一律走 ApiKeyStore，绝不进 SharedPreferences 明文区。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class SettingsStore {
  SettingsStore._();

  static const _aiConfigKey = 'aiConfig';

  /// 读取 AI 配置（无存档返回 Anthropic 官方默认：opus-5-5）。
  static Future<AiConfig> loadAiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aiConfigKey);
    if (raw == null || raw.isEmpty) return AiConfig.anthropicDefault;
    try {
      return AiConfig.fromMap(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return AiConfig.anthropicDefault; // 损坏即回默认，不让启动崩溃
    }
  }

  static Future<void> saveAiConfig(AiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiConfigKey, jsonEncode(config.toMap()));
  }
}
