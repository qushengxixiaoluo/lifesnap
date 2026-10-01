/// 月度回顾仓库：把「当月日总结 + AI 配置 + API Key + 适配器」串成一条线。
///
/// 职责边界（沿 SummaryRepositoryImpl 的范式）：
/// - 过滤当月日总结并算内容指纹 inputSig（任何一条日总结变，月报即标失效）；
/// - inputSig 命中缓存 → 直接返回，不花 API 钱；
/// - 未命中才读 key / 配置 → 造适配器 → 生成 → 落库（回填 inputSig/createdAtMs）。
/// 请求格式本身完全交给 AiFactory 造出来的 AiProvider，本文件不碰 HTTP。
library;

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../storage/photo_index_store.dart';
import '../storage/settings_store.dart';
import 'ai_client.dart';
import 'ai_factory.dart';
import 'ai_provider.dart';
import 'api_key_store.dart';

class MonthlyReviewRepository {
  /// [client] 注入 HTTP 客户端（单测用假客户端，不发真实网络请求）。
  MonthlyReviewRepository({
    required PhotoIndexStore store,
    http.Client? client,
  })  : _store = store,
        _httpClient = client;

  final PhotoIndexStore _store;
  final http.Client? _httpClient;

  /// 只建一次：每次生成都 new 一个 http.Client 会漏 socket。
  late final AiClient _ai = AiClient(client: _httpClient);

  /// 生成（或读缓存）[year] 年 [month] 月的月度回顾。
  ///
  /// [force]=false 且缓存 inputSig 仍等于当前日总结指纹 → 直接返回缓存；
  /// [force]=true 跳过缓存（「重新生成」按钮）。
  Future<MonthlyReview> generate({
    required int year,
    required int month,
    bool force = false,
  }) async {
    // 全量读口按 day_key 升序，过滤后仍保持升序（提示词按时间逐日列出）。
    final monthDays = <AiSummary>[
      for (final s in await _store.allSummaries())
        if (s.dayKey ~/ 10000 == year && (s.dayKey ~/ 100) % 100 == month) s,
    ];
    if (monthDays.isEmpty) {
      throw const AiException('本月还没有日总结，先补全再生成回顾');
    }

    // 指纹必须先算：它是「缓存是否还有效」的唯一判据。
    final sig = computeMonthlyInputSig(monthDays);
    if (!force) {
      final existing = await _store.monthlyReviewOf(year, month);
      if (existing != null && existing.inputSig == sig) return existing;
    }

    // key 放到真正要发请求前才读，纯缓存命中不去碰安全存储。
    final apiKey = await ApiKeyStore.read();
    if (apiKey == null || apiKey.trim().isEmpty) throw const AiAuthException();

    final config = await SettingsStore.loadAiConfig();
    final provider =
        AiFactory.createWithClient(config, apiKey.trim(), aiClient: _ai);
    final generated = await provider.generateMonthlyReview(
      year: year,
      month: month,
      days: monthDays,
    );

    // 适配器并不知道「本次依据了哪些日总结」，inputSig 与 created_at 统一
    // 在这里回填，保证落库的指纹一定等于本次生成的输入。
    final review = MonthlyReview.fromMap(<String, Object?>{
      ...generated.toMap(),
      'year': year,
      'month': month,
      'input_sig': sig,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _store.putMonthlyReview(review);
    return review;
  }

  /// 读缓存（不触发生成、不花 API 钱）。
  Future<MonthlyReview?> cached(int year, int month) =>
      _store.monthlyReviewOf(year, month);
}
