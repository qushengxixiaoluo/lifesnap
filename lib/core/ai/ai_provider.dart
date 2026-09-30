/// AI 层 · 抽象契约（阶段 0 地基文件）
///
/// 两个实现方向（D 轨交付）：
/// - AnthropicAdapter  Messages API（x-api-key，图片 base64 content block）
/// - OpenAIAdapter     Chat Completions（Bearer，image_url data URI，可配 base_url 兼容中转）
///
/// 上层（日详情、设置页、批量按钮）只依赖本文件的接口。
/// 并行纪律：五条轨只 import 不修改。
library;

import 'dart:typed_data';

import '../models/models.dart';

/// 单日总结生成器。实现方负责：请求构造、双格式适配、重试退避、宽容 JSON 解析。
abstract class AiProvider {
  /// 为一天生成总结。[imagesJpeg] 已压缩至 ≤1568px / q85。
  /// 实现方抛 [AiAuthException] / [AiRateLimitException] / [AiFormatException]
  /// 等，由 UI 层映射为中文文案。
  Future<AiSummary> generateDaySummary({
    required List<Uint8List> imagesJpeg,
    required DateTime date,
    required String dayContext,
  });

  /// 设置页「测试连接」：发最小请求，成功返回模型回执（如模型名），失败抛异常。
  Future<String> testConnection();
}

// ---------------------------------------------------------------------------
// 统一异常体系（D 轨抛出，UI 据此给中文文案；文案风格沿 llm_service.dart）
// ---------------------------------------------------------------------------

/// AI 调用异常基类。
class AiException implements Exception {
  final String message; // 已是面向用户的中文文案
  const AiException(this.message);
  @override
  String toString() => message;
}

/// 401/403：key 无效 —— UI 应弹窗引导重新输入。
class AiAuthException extends AiException {
  const AiAuthException() : super('API Key 无效或已过期，请到设置页检查');
}

/// 429：限流/配额 —— 退避重试耗尽后抛出。
class AiRateLimitException extends AiException {
  const AiRateLimitException()
      : super('请求过于频繁（429），请稍后再试或检查配额');
}

/// 200 但内容无法解析为 JSON。
class AiFormatException extends AiException {
  const AiFormatException()
      : super('AI 返回了无法识别的内容，请重试或更换模型');
}

/// 网络不可达（离线时 UI 可回退展示缓存）。
class AiNetworkException extends AiException {
  const AiNetworkException() : super('网络连接失败，请检查网络后重试');
}

/// 其余 4xx/5xx。
class AiServerException extends AiException {
  const AiServerException(super.detail);
}

// ---------------------------------------------------------------------------
// 总结仓库：缓存读取 + 按需生成 + 批量生成（D 轨实现，串起 store 与 AiProvider）
// ---------------------------------------------------------------------------

/// 批量生成进度（「生成本月全部总结」按钮的进度流）。
class MonthBatchProgress {
  final int total; // 应处理天数（有照片的天）
  final int done; // 已成功
  final int failed; // 已失败
  final int currentDayKey; // 正在处理
  final bool finished;

  const MonthBatchProgress({
    required this.total,
    required this.done,
    required this.failed,
    required this.currentDayKey,
    this.finished = false,
  });
}

abstract class SummaryRepository {
  /// 读缓存（不触发生成）。photo_sig 不匹配时由 DayRecord.summaryStale 呈现。
  Future<AiSummary?> cached(int dayKey);

  /// 生成单日总结并落缓存。
  /// [force]=false 且缓存有效 → 直接返回缓存；[onImageProgress] 用于压缩进度反馈。
  Future<AiSummary> generate({
    required DayRecord record,
    bool force = false,
    void Function(int current, int total)? onImageProgress,
  });

  /// 批量生成某月缺失/失效的总结（并发 3，进度随流推送）。
  Stream<MonthBatchProgress> generateMonth({required int year, required int month});
}
