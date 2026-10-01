/// OpenAI Chat Completions 适配器（Bearer + image_url data URI）。
///
/// 覆盖一切兼容端点：官方 OpenAI、DeepSeek、Moonshot、各类中转……
/// 它们的共同点是 Base URL 必填、走 `/v1/chat/completions`、
/// 用 `response_format: json_object` 约束输出。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import 'ai_client.dart';
import 'ai_provider.dart';
import 'ai_schemas.dart';

class OpenAIAdapter implements AiProvider {
  OpenAIAdapter(this.config, this.apiKey, {AiClient? client})
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
    final request = openaiRequest(
      config: config,
      apiKey: apiKey,
      imagesJpeg: imagesJpeg,
      date: date,
      dayContext: dayContext,
    );
    final resp = await _client.post(request);
    final payload = extractAssistantContent(resp.body);
    // photoSig 由 SummaryRepository 生成后回填（它才知道当日照片全集）。
    return parseAiSummary(
      payload,
      dayKeyOf(date),
      modelOf(config, fallback: 'gpt-4o'),
      '',
    );
  }

  @override
  Future<MonthlyReview> generateMonthlyReview({
    required int year,
    required int month,
    required List<AiSummary> days,
  }) async {
    final request = openaiMonthlyRequest(
      config: config,
      apiKey: apiKey,
      year: year,
      month: month,
      days: days,
    );
    final resp = await _client.post(request);
    final payload = extractAssistantContent(resp.body);
    // inputSig / createdAtMs 由 MonthlyReviewRepository 落库时回填。
    return parseMonthlySummary(
      payload,
      year,
      month,
      modelOf(config, fallback: 'gpt-4o'),
    );
  }

  @override
  Future<String> testConnection() async {
    final resp = await _client.post(
      openaiTestRequest(config: config, apiKey: apiKey),
    );
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final model = decoded['model'];
        if (model is String && model.trim().isNotEmpty) return model.trim();
      }
    } catch (_) {/* 回执不是预期 JSON 时仍算连通，回落配置里的模型名 */}
    return modelOf(config, fallback: 'gpt-4o');
  }
}
