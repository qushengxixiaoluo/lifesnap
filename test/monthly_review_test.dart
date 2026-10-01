/// 月度回顾 · 单测：宽容解析 + 双格式请求 + 仓库缓存/指纹/鉴权（禁止真实网络）。
///
/// 铁律与 summary_repository_test 相同：HTTP 全部走 FakeHttpClient，
/// ApiKey 走 SharedPreferences 降级键，不碰任何真实端点。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/ai/ai_schemas.dart';
import 'package:shiguang_handbook/core/ai/monthly_review_repository.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';

import 'ai_test_helpers.dart';

// ---------------------------------------------------------------------------
// 罐头数据
// ---------------------------------------------------------------------------

const String model = 'claude-opus-5-5';

/// 一段合法的月报 JSON（供两级响应体拼装）。
String monthlyJson({
  String title = '九月的风',
  String narrative = '这个月从一场雨开始，又在一场雨里结束。'
      '你在旧单车的铃声里穿过堤岸，把冰棍分给晚风，'
      '月末的最后一个下午阳光正好，你把晾好的棉被抱回屋里，'
      '整个月份都散发着被太阳晒过的味道，'
      '像一封写得很慢却始终没有寄出的信，落在九月的信箱里。',
  List<String> tags = const <String>['海边', '日常', '雨季'],
  List<String> highlights = const <String>['堤岸追风', '晒棉被'],
}) =>
    jsonEncode(<String, Object?>{
      'title': title,
      'narrative': narrative,
      'tags': tags,
      'highlights': highlights,
    });

/// Anthropic 成功回执（content 是 text block 数组）。
http.Response anthropicMonthlyOk({String modelName = model}) => jsonResponse(
      <String, Object?>{
        'id': 'msg_monthly_test',
        'type': 'message',
        'role': 'assistant',
        'model': modelName,
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': monthlyJson()},
        ],
        'stop_reason': 'end_turn',
      },
    );

/// 构造一条日总结（day_key 升序喂给仓库）。
AiSummary buildDay(int dayKey, {String title = '海风与旧单车'}) => AiSummary(
      dayKey: dayKey,
      title: title,
      narrative: '傍晚的风从堤岸那边吹过来，你推着掉了漆的旧单车经过小卖部，'
          '玻璃罐里的冰棍还剩最后一根，于是我们停下来分着吃完。',
      tags: const <String>['海边', '黄昏'],
      mood: '晴',
      highlights: const <String>['堤岸追风'],
      model: model,
      photoSig: 'sig-$dayKey',
      createdAtMs: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ApiKeyStore / SettingsStore 都读 SharedPreferences；
    // flutter_secure_storage 在测试里没有平台实现，会自动落到这个降级键。
    SharedPreferences.setMockInitialValues(
      <String, Object>{'api_key_insecure_fallback': 'sk-unit-test'},
    );
  });

  Future<InMemoryPhotoIndexStore> makeStore(List<AiSummary> days) async {
    final store = InMemoryPhotoIndexStore();
    await store.init();
    for (final d in days) {
      await store.putSummary(d);
    }
    return store;
  }

  // -----------------------------------------------------------------------
  // 解析：宽容降级链（与 parseAiSummary 同构）
  // -----------------------------------------------------------------------
  group('parseMonthlySummary 宽容解析', () {
    test('第一级：裸 JSON 字符串', () {
      final r = parseMonthlySummary(monthlyJson(), 2026, 9, model);
      expect(r.year, 2026);
      expect(r.month, 9);
      expect(r.title, '九月的风');
      expect(r.narrative, contains('九月'));
      expect(r.tags, <String>['海边', '日常', '雨季']);
      expect(r.highlights, <String>['堤岸追风', '晒棉被']);
      expect(r.model, model, reason: 'model 字段回填所用模型名');
      expect(r.createdAtMs, greaterThan(0));
    });

    test('第三级：代码块围栏包裹的变体', () {
      final fenced = '```json\n${monthlyJson()}\n```';
      final r = parseMonthlySummary(fenced, 2026, 9, model);
      expect(r.title, '九月的风');
    });

    test('第三级：围栏 + 前面还有废话', () {
      final text = '好的，我读完了这个月的全部日总结：\n'
          '```json\n${monthlyJson()}\n```\n以上是月度回顾。';
      final r = parseMonthlySummary(text, 2026, 9, model);
      expect(r.title, '九月的风');
      expect(r.model, model);
    });

    test('第二级：content 块数组（Anthropic 回执形态）', () {
      final r = parseMonthlySummary(
        <Object?>[
          <String, Object?>{'type': 'text', 'text': '以下是本月回顾。'},
          <String, Object?>{'type': 'text', 'text': monthlyJson()},
        ],
        2026,
        9,
        model,
      );
      expect(r.title, '九月的风');
    });

    test('第二级：{content: "..."} 外壳', () {
      final r = parseMonthlySummary(
        <String, Object?>{'content': monthlyJson()},
        2026,
        9,
        model,
      );
      expect(r.title, '九月的风');
    });

    test('宽容收敛：标题截 12 字、tags 截 6、highlights 截 5', () {
      final r = parseMonthlySummary(
        monthlyJson(
          title: '这是一个非常非常长的一定会超过十二个字的月报标题',
          tags: const <String>['一', '二', '三', '四', '五', '六', '七', '八'],
          highlights: const <String>['甲', '乙', '丙', '丁', '戊', '己', '庚'],
        ),
        2026,
        9,
        model,
      );
      expect(r.title.length, 12);
      expect(r.tags, hasLength(6));
      expect(r.highlights, hasLength(5));
    });

    test('三级全失败 → AiFormatException', () {
      expect(
        () => parseMonthlySummary('我这个月不想写回顾。', 2026, 9, model),
        throwsA(isA<AiFormatException>()),
      );
      expect(
        () => parseMonthlySummary(null, 2026, 9, model),
        throwsA(isA<AiFormatException>()),
      );
      expect(
        () => parseMonthlySummary(<Object?>[], 2026, 9, model),
        throwsA(isA<AiFormatException>()),
      );
      expect(
        () => parseMonthlySummary(
          jsonEncode(<String, Object?>{'title': '只有标题'}),
          2026,
          9,
          model,
        ),
        throwsA(isA<AiFormatException>()),
        reason: '缺 narrative 不算月报 → 继续降级直至失败',
      );
    });
  });

  // -----------------------------------------------------------------------
  // 请求构造：纯文本、双格式、提示词一致
  // -----------------------------------------------------------------------
  group('月报请求构造', () {
    test('anthropicMonthlyRequest：system + 单条 user 文本，不带图片', () {
      final days = <AiSummary>[buildDay(20260901), buildDay(20260902)];
      final req = anthropicMonthlyRequest(
        config: AiConfig.anthropicDefault,
        apiKey: 'sk-unit-test',
        year: 2026,
        month: 9,
        days: days,
      );
      expect(req.url, 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], 'sk-unit-test');
      expect(req.body['system'], contains('月度回顾作者'));

      final messages = req.body['messages'] as List<Object?>;
      expect(messages, hasLength(1));
      final content =
          (messages.first as Map<String, Object?>)['content'] as List<Map>;
      expect(content, hasLength(1), reason: '月报是纯文本调用，不带图片');
      expect(content.single['type'], 'text');
      final prompt = content.single['text'] as String;
      expect(prompt, contains('2026 年 9 月'));
      expect(prompt, contains('【9月1日'));
      expect(prompt, contains('海风与旧单车'));
      expect(prompt, contains('300-600 字'));
      expect(prompt, contains('只输出一个 JSON 对象'));

      final outputConfig = req.body['output_config'] as Map<String, Object?>;
      final format = outputConfig['format'] as Map<String, Object?>;
      expect(format['type'], 'json_schema');
      final schema = format['schema'] as Map<String, Object?>;
      final properties = schema['properties'] as Map<String, Object?>;
      expect(properties.keys,
          containsAll(<String>['title', 'narrative', 'tags', 'highlights']));
      expect(properties.containsKey('mood'), isFalse, reason: '月报没有 mood 字段');
    });

    test('openaiMonthlyRequest：system + user 纯文本 + json_object', () {
      const openai = AiConfig(
        provider: AiProviderKind.openai,
        baseUrl: 'https://proxy.example.com',
        model: 'gpt-4o',
      );
      final req = openaiMonthlyRequest(
        config: openai,
        apiKey: 'sk-openai',
        year: 2026,
        month: 9,
        days: <AiSummary>[buildDay(20260901)],
      );
      expect(req.url, 'https://proxy.example.com/v1/chat/completions');
      expect(req.headers['Authorization'], 'Bearer sk-openai');
      expect(req.body['response_format'], <String, Object?>{'type': 'json_object'});
      final messages = req.body['messages'] as List<Object?>;
      expect(messages, hasLength(2));
      expect((messages.first as Map<String, Object?>)['role'], 'system');
      expect((messages.first as Map<String, Object?>)['content'],
          contains('月度回顾作者'));
      expect((messages.last as Map<String, Object?>)['content'],
          contains('海风与旧单车'));
    });
  });

  // -----------------------------------------------------------------------
  // 仓库：空月 / 缓存命中 / 指纹失效 / 缺 key
  // -----------------------------------------------------------------------
  group('MonthlyReviewRepository', () {
    test('① 月内无日总结 → 抛「本月还没有日总结，先补全再生成回顾」', () async {
      // store 里只有 10 月的总结，9 月为空
      final store = await makeStore(<AiSummary>[buildDay(20261001)]);
      final client = FakeHttpClient((_, _) async => anthropicMonthlyOk());
      final repo = MonthlyReviewRepository(store: store, client: client);

      await expectLater(
        repo.generate(year: 2026, month: 9),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          '本月还没有日总结，先补全再生成回顾',
        )),
      );
      expect(client.callCount, 0, reason: '空月不该发任何请求');
    });

    test('② 缓存命中（inputSig 相同）→ 不发请求直接返回', () async {
      final days = <AiSummary>[buildDay(20260901), buildDay(20260902)];
      final store = await makeStore(days);
      final sig = computeMonthlyInputSig(days);
      await store.putMonthlyReview(MonthlyReview(
        year: 2026,
        month: 9,
        title: '缓存里的旧月报',
        narrative: '这是之前生成过、指纹仍然匹配的月报，不该再花 API 钱。',
        tags: const <String>['缓存'],
        highlights: const <String>['命中'],
        model: model,
        inputSig: sig,
        createdAtMs: 1,
      ));

      final client = FakeHttpClient((_, _) async => anthropicMonthlyOk());
      final repo = MonthlyReviewRepository(store: store, client: client);

      final out = await repo.generate(year: 2026, month: 9);
      expect(out.title, '缓存里的旧月报');
      expect(client.callCount, 0, reason: '指纹匹配时不得发网络请求');

      // force=true 跳过缓存（「重新生成」入口）
      final forced = await repo.generate(year: 2026, month: 9, force: true);
      expect(client.callCount, 1);
      expect(forced.title, '九月的风', reason: 'force 应取模型新返回的月报');
    });

    test('③ inputSig 不同 → 走请求 → putMonthlyReview 落库且 inputSig 正确', () async {
      final days = <AiSummary>[buildDay(20260901), buildDay(20260902)];
      final store = await makeStore(days);
      // 预置一条指纹过期的月报（日总结后来被编辑过）
      await store.putMonthlyReview(MonthlyReview(
        year: 2026,
        month: 9,
        title: '过期的旧月报',
        narrative: '旧内容。',
        tags: const <String>[],
        highlights: const <String>[],
        model: model,
        inputSig: 'stale-sig',
        createdAtMs: 1,
      ));

      final client = FakeHttpClient((_, _) async => anthropicMonthlyOk());
      final repo = MonthlyReviewRepository(store: store, client: client);

      final out = await repo.generate(year: 2026, month: 9);
      expect(client.callCount, 1, reason: '指纹不匹配必须重新生成');
      expect(out.title, '九月的风');
      expect(out.inputSig, computeMonthlyInputSig(days),
          reason: '落库指纹必须等于本次生成所依据的日总结');

      final stored = await store.monthlyReviewOf(2026, 9);
      expect(stored, isNotNull);
      expect(stored!.inputSig, computeMonthlyInputSig(days));
      expect(stored.title, '九月的风');
      expect(stored.createdAtMs, greaterThan(1));

      // 请求体断言：纯文本月报提示词确实发出去了
      final body = jsonDecode(client.requests.single.body) as Map<String, Object?>;
      final messages = body['messages'] as List<Object?>;
      final content =
          (messages.first as Map<String, Object?>)['content'] as List<Object?>;
      final textBlock = content.single as Map<String, Object?>;
      expect(textBlock['text'] as String, contains('月度回顾'));
    });

    test('④ 无 key → AiAuthException', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await makeStore(<AiSummary>[buildDay(20260901)]);
      final client = FakeHttpClient((_, _) async => anthropicMonthlyOk());
      final repo = MonthlyReviewRepository(store: store, client: client);

      await expectLater(
        repo.generate(year: 2026, month: 9),
        throwsA(isA<AiAuthException>()),
      );
      expect(client.callCount, 0, reason: '没 key 不该发请求');
    });

    test('只取所选月份：相邻月的日总结不混入指纹', () async {
      final days = <AiSummary>[buildDay(20260901), buildDay(20261001)];
      final store = await makeStore(days);
      final client = FakeHttpClient((_, _) async => anthropicMonthlyOk());
      final repo = MonthlyReviewRepository(store: store, client: client);

      await repo.generate(year: 2026, month: 9);
      final sep = await store.monthlyReviewOf(2026, 9);
      expect(sep!.inputSig, computeMonthlyInputSig(<AiSummary>[days.first]),
          reason: '9 月指纹只应包含 9 月的日总结');
      final oct = await store.monthlyReviewOf(2026, 10);
      expect(oct, isNull, reason: '不该顺手生成 10 月的月报');
    });
  });
}
