/// Anthropic Messages API 适配器（x-api-key + base64 image block）。
///
/// 兼容策略：默认带 `anthropic-beta: server-side-fallback-2026-07-01` 头与
/// body 的 `fallbacks:"default"`（官方端点支持，能让服务端在过载时自动降级）；
/// 国内中转常不认这两个字段，收到 400 且错误信息提到 beta/fallbacks 时
/// 会去掉它们重试一次，一次就够——再失败就是真的请求体有问题。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import 'ai_client.dart';
import 'ai_provider.dart';
import 'ai_schemas.dart';

class AnthropicAdapter implements AiProvider {
  AnthropicAdapter(this.config, this.apiKey, {AiClient? client})
      : _client = client ?? AiClient();

  final AiConfig config;
  final String apiKey;
  final AiClient _client;

  @override
  Future<AiSummary> generateDaySummary({
    required List<Uint8List> imagesJpeg,
    required DateTime date,
    required String dayContext,
  }) async {
    final payload = await _postWithBetaFallback(
      imagesJpeg: imagesJpeg,
      date: date,
      dayContext: dayContext,
    );
    // photoSig 由 SummaryRepository 生成后回填（它才知道当日照片全集）。
    return parseAiSummary(
      payload,
      dayKeyOf(date),
      modelOf(config, fallback: 'claude-opus-5-5'),
      '',
    );
  }

  @override
  Future<MonthlyReview> generateMonthlyReview({
    required int year,
    required int month,
    required List<AiSummary> days,
  }) async {
    final payload = await _postMonthlyWithBetaFallback(
      year: year,
      month: month,
      days: days,
    );
    // inputSig / createdAtMs 由 MonthlyReviewRepository 落库时回填。
    return parseMonthlySummary(
      payload,
      year,
      month,
      modelOf(config, fallback: 'claude-opus-5-5'),
    );
  }

  @override
  Future<String> testConnection() async {
    final resp = await _client.post(
      anthropicTestRequest(config: config, apiKey: apiKey),
    );
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final model = decoded['model'];
        if (model is String && model.trim().isNotEmpty) return model.trim();
      }
    } catch (_) {/* 回执不是预期 JSON 时仍算连通，回落配置里的模型名 */}
    return modelOf(config, fallback: 'claude-opus-5-5');
  }

  /// 发一次日总结请求；遇到「中转不认 beta 头」的 400 就去掉 beta 重试一次。
  Future<Object?> _postWithBetaFallback({
    required List<Uint8List> imagesJpeg,
    required DateTime date,
    required String dayContext,
  }) =>
      _postWithFallback(
        ({required bool withFallbackBeta}) => anthropicRequest(
          config: config,
          apiKey: apiKey,
          imagesJpeg: imagesJpeg,
          date: date,
          dayContext: dayContext,
          withFallbackBeta: withFallbackBeta,
        ),
      );

  /// 发一次月报请求（与日总结共用 beta 头降级重试）。
  Future<Object?> _postMonthlyWithBetaFallback({
    required int year,
    required int month,
    required List<AiSummary> days,
  }) =>
      _postWithFallback(
        ({required bool withFallbackBeta}) => anthropicMonthlyRequest(
          config: config,
          apiKey: apiKey,
          year: year,
          month: month,
          days: days,
          withFallbackBeta: withFallbackBeta,
        ),
      );

  /// 通用发送：先带 beta 头发一次，被 400 点名就去掉重试一次。
  Future<Object?> _postWithFallback(
    AiHttpRequest Function({required bool withFallbackBeta}) build,
  ) async {
    try {
      final resp = await _client.post(build(withFallbackBeta: true));
      return extractAssistantContent(resp.body);
    } on AiHttpException catch (e) {
      if (!_betaHeaderRejected(e)) rethrow;
      final resp = await _client.post(build(withFallbackBeta: false));
      return extractAssistantContent(resp.body);
    }
  }

  /// 判断 400 是不是「beta / fallbacks 不被识别」造成的。
  ///
  /// 为什么只认这两类词：其它 400（模型名错、schema 不支持）重试也没用，
  /// 直接把服务端原文透出去，用户才知道该改哪里。
  static bool _betaHeaderRejected(AiHttpException e) {
    if (e.statusCode != 400) return false;
    final text = e.rawBody.toLowerCase();
    return text.contains('beta') || text.contains('fallback');
  }
}
