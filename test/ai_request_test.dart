/// D 轨 · 双格式请求构造与 HTTP 层行为（禁止真实网络，全部注入假 client）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shiguang_handbook/core/ai/ai_client.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/ai/ai_schemas.dart';
import 'package:shiguang_handbook/core/ai/anthropic_adapter.dart';
import 'package:shiguang_handbook/core/ai/openai_adapter.dart';
import 'package:shiguang_handbook/core/models/models.dart';

import 'ai_test_helpers.dart';

final List<Uint8List> sampleImages = <Uint8List>[
  Uint8List.fromList(<int>[1, 2, 3]),
  Uint8List.fromList(<int>[4, 5, 6]),
];

void main() {
  final date = DateTime(2026, 9, 30, 15, 30);

  // -----------------------------------------------------------------------
  // Anthropic Messages
  // -----------------------------------------------------------------------
  group('anthropicRequest', () {
    test('headers 带 x-api-key / anthropic-version / beta', () {
      final req = anthropicRequest(
        config: AiConfig.anthropicDefault,
        apiKey: 'sk-unit-test',
        imagesJpeg: sampleImages,
        date: date,
        dayContext: '下午去了海边',
      );
      expect(req.url, 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], 'sk-unit-test');
      expect(req.headers['anthropic-version'], '2023-06-01');
      expect(req.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      expect(req.headers['content-type'], 'application/json');
      expect(req.body['fallbacks'], 'default');
    });

    test('user content = N 个 base64 image block + 一条中文任务文本', () {
      final req = anthropicRequest(
        config: AiConfig.anthropicDefault,
        apiKey: 'k',
        imagesJpeg: sampleImages,
        date: date,
        dayContext: '',
      );
      final messages = req.body['messages'] as List<Object?>;
      expect(messages, hasLength(1));
      final content = (messages.first as Map<String, Object?>)['content']
          as List<Map<String, Object?>>;
      expect(content, hasLength(3));

      for (var i = 0; i < 2; i++) {
        final block = content[i];
        expect(block['type'], 'image');
        final source = block['source'] as Map<String, Object?>;
        expect(source['type'], 'base64');
        expect(source['media_type'], 'image/jpeg');
        // [1,2,3] 的 base64 是 AQID，逐字节断言编码正确
        expect(source['data'], base64Encode(sampleImages[i]));
      }

      final textBlock = content.last;
      expect(textBlock['type'], 'text');
      final prompt = textBlock['text'] as String;
      expect(prompt, contains('2026年9月30日 周三'));
      expect(prompt, contains('本次提交 2 张照片'));
      expect(prompt, contains('80-200 字'));
      expect(prompt, contains('只输出一个 JSON 对象'));
    });

    test('body 带 model / max_tokens / output_config(effort+json_schema)', () {
      final req = anthropicRequest(
        config: const AiConfig(
          provider: AiProviderKind.anthropic,
          model: 'claude-sonnet-5-5',
          effort: 'medium',
        ),
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: date,
        dayContext: '',
      );
      expect(req.body['model'], 'claude-sonnet-5-5');
      expect(req.body['max_tokens'], 4096);
      final outputConfig = req.body['output_config'] as Map<String, Object?>;
      expect(outputConfig['effort'], 'medium');
      final format = outputConfig['format'] as Map<String, Object?>;
      expect(format['type'], 'json_schema');
      final schema = format['schema'] as Map<String, Object?>;
      final properties = schema['properties'] as Map<String, Object?>;
      expect(properties.keys,
          containsAll(<String>['title', 'narrative', 'tags', 'mood', 'highlights']));
      final mood = properties['mood'] as Map<String, Object?>;
      expect(mood['enum'], <String>['晴', '多云', '小雨', '彩虹', '星夜']);
      // 默认 effort 不开 thinking（opus-5-5 只认 adaptive 或省略）
      expect(req.body.containsKey('thinking'), isFalse);
    });

    test('effort=high 时补 adaptive thinking，且绝不出现 disabled', () {
      final req = anthropicRequest(
        config: const AiConfig(provider: AiProviderKind.anthropic, effort: 'high'),
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: date,
        dayContext: '',
      );
      expect(req.body['thinking'], <String, Object?>{'type': 'adaptive'});
      expect(jsonEncode(req.body['thinking']), isNot(contains('disabled')));
    });

    test('withFallbackBeta=false 时移除 beta 头与 fallbacks 字段', () {
      final req = anthropicRequest(
        config: AiConfig.anthropicDefault,
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: date,
        dayContext: '',
        withFallbackBeta: false,
      );
      expect(req.headers.containsKey('anthropic-beta'), isFalse);
      expect(req.body.containsKey('fallbacks'), isFalse);
    });

    test('baseUrl 为空走官方端点；自定义端点拼 /v1/messages', () {
      final req = anthropicRequest(
        config: const AiConfig(
          provider: AiProviderKind.anthropic,
          baseUrl: 'https://proxy.example.com/',
        ),
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: date,
        dayContext: '',
      );
      expect(req.url, 'https://proxy.example.com/v1/messages');
    });
  });

  // -----------------------------------------------------------------------
  // OpenAI Chat Completions
  // -----------------------------------------------------------------------
  group('openaiRequest', () {
    const openai = AiConfig(
      provider: AiProviderKind.openai,
      baseUrl: 'https://proxy.example.com',
      model: 'gpt-4o',
    );

    test('headers 带 Bearer Authorization', () {
      final req = openaiRequest(
        config: openai,
        apiKey: 'sk-openai',
        imagesJpeg: sampleImages,
        date: date,
        dayContext: '',
      );
      expect(req.url, 'https://proxy.example.com/v1/chat/completions');
      expect(req.headers['Authorization'], 'Bearer sk-openai');
      expect(req.headers['content-type'], 'application/json');
    });

    test('user content 用 data:image/jpeg;base64 的 image_url', () {
      final req = openaiRequest(
        config: openai,
        apiKey: 'k',
        imagesJpeg: sampleImages,
        date: date,
        dayContext: '',
      );
      final messages = req.body['messages'] as List<Object?>;
      expect(messages, hasLength(2)); // system + user
      expect((messages.first as Map<String, Object?>)['role'], 'system');

      final parts = (messages.last as Map<String, Object?>)['content']
          as List<Map<String, Object?>>;
      expect(parts, hasLength(3));
      for (var i = 0; i < 2; i++) {
        final part = parts[i];
        expect(part['type'], 'image_url');
        final url = ((part['image_url'] as Map<String, Object?>)['url']) as String;
        expect(url, startsWith('data:image/jpeg;base64,'));
        expect(url, 'data:image/jpeg;base64,${base64Encode(sampleImages[i])}');
      }
      expect(parts.last['type'], 'text');
      expect((parts.last['text'] as String), contains('2026年9月30日 周三'));
    });

    test('带 response_format=json_object 与 max_tokens', () {
      final req = openaiRequest(
        config: openai,
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: date,
        dayContext: '',
      );
      expect(req.body['response_format'], <String, Object?>{'type': 'json_object'});
      expect(req.body['max_tokens'], 4096);
      expect(req.body['model'], 'gpt-4o');
    });

    test('Base URL 缺失时抛中文异常（不猜官方地址）', () {
      expect(
        () => openaiRequest(
          config: const AiConfig(provider: AiProviderKind.openai),
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: date,
          dayContext: '',
        ),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('Base URL'))),
      );
    });

    test('Base URL 已含 /v1 时不重复拼接', () {
      final req = openaiRequest(
        config: const AiConfig(
          provider: AiProviderKind.openai,
          baseUrl: 'https://proxy.example.com/v1/',
          model: 'gpt-4o',
        ),
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: date,
        dayContext: '',
      );
      expect(req.url, 'https://proxy.example.com/v1/chat/completions');
    });
  });

  // -----------------------------------------------------------------------
  // Anthropic 适配器：beta 头不被中转识别时的降级重试
  // -----------------------------------------------------------------------
  group('AnthropicAdapter beta 回退', () {
    test('400 提到 beta 时去掉 beta 头重试一次', () async {
      final client = FakeHttpClient((call, _) async {
        if (call == 1) {
          return jsonResponse(
            <String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'invalid_request_error',
                'message': 'anthropic-beta: unknown beta feature '
                    '"server-side-fallback-2026-07-01"',
              },
            },
            status: 400,
          );
        }
        return anthropicOk();
      });
      final adapter = AnthropicAdapter(
        AiConfig.anthropicDefault,
        'sk-unit',
        client: AiClient(client: client, backoff: const <Duration>[Duration.zero]),
      );

      final summary = await adapter.generateDaySummary(
        imagesJpeg: sampleImages,
        date: DateTime(2026, 9, 30),
        dayContext: '',
      );

      expect(client.callCount, 2);
      expect(headerOf(client.requests.first, 'anthropic-beta'), isNotNull);
      expect(headerOf(client.requests.last, 'anthropic-beta'), isNull);
      expect(
        (jsonDecode(client.requests.last.body) as Map<String, Object?>)
            .containsKey('fallbacks'),
        isFalse,
      );
      expect(summary.title, '海风与旧单车');
      expect(summary.mood, '晴');
      expect(summary.tags, <String>['海边', '黄昏', '单车']);
    });

    test('400 与 beta 无关时不重试，直接抛服务端详情', () async {
      final client = FakeHttpClient((_, _) async => jsonResponse(
            <String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'invalid_request_error',
                'message': 'model: unknown model "claude-nope"',
              },
            },
            status: 400,
          ));
      final adapter = AnthropicAdapter(
        const AiConfig(provider: AiProviderKind.anthropic, model: 'claude-nope'),
        'sk-unit',
        client: AiClient(client: client, backoff: const <Duration>[Duration.zero]),
      );

      await expectLater(
        adapter.generateDaySummary(
          imagesJpeg: sampleImages,
          date: DateTime(2026, 9, 30),
          dayContext: '',
        ),
        throwsA(isA<AiHttpException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('unknown model'))),
      );
      expect(client.callCount, 1);
    });

    test('testConnection 返回回执里的模型名', () async {
      final client = FakeHttpClient((_, _) async => anthropicOk(model: 'claude-opus-5-5'));
      final adapter = AnthropicAdapter(
        AiConfig.anthropicDefault,
        'sk-unit',
        client: AiClient(client: client),
      );
      final name = await adapter.testConnection();
      expect(name, 'claude-opus-5-5');
      final body = jsonDecode(client.requests.single.body) as Map<String, Object?>;
      expect(body['max_tokens'], 16);
      expect(client.requests.single.url.path, '/v1/messages');
    });
  });

  // -----------------------------------------------------------------------
  // OpenAI 适配器
  // -----------------------------------------------------------------------
  group('OpenAIAdapter', () {
    const openai = AiConfig(
      provider: AiProviderKind.openai,
      baseUrl: 'https://proxy.example.com',
      model: 'gpt-4o',
    );

    test('发 chat/completions 并从 choices[0].message.content 解析', () async {
      final client = FakeHttpClient((_, _) async => openaiOk());
      final adapter = OpenAIAdapter(
        openai,
        'sk-unit',
        client: AiClient(client: client),
      );
      final summary = await adapter.generateDaySummary(
        imagesJpeg: sampleImages,
        date: DateTime(2026, 9, 30),
        dayContext: '',
      );
      expect(summary.title, '海风与旧单车');
      expect(summary.model, 'gpt-4o');
      expect(client.requests.single.url.path, '/v1/chat/completions');
      expect(headerOf(client.requests.single, 'Authorization'), 'Bearer sk-unit');
    });

    test('testConnection 返回回执里的模型名', () async {
      final client = FakeHttpClient((_, _) async => openaiOk(model: 'gpt-4o-mini'));
      final adapter = OpenAIAdapter(
        openai,
        'sk-unit',
        client: AiClient(client: client),
      );
      expect(await adapter.testConnection(), 'gpt-4o-mini');
      final body = jsonDecode(client.requests.single.body) as Map<String, Object?>;
      expect(body['max_tokens'], 16);
    });
  });

  // -----------------------------------------------------------------------
  // HTTP 层：超时 / 退避 / 状态码映射
  // -----------------------------------------------------------------------
  group('AiClient 状态码与重试', () {
    // 全部用零退避，保证用例不真的睡 7 秒
    const noWait = <Duration>[Duration.zero, Duration.zero, Duration.zero];

    test('401/403 → AiAuthException', () async {
      for (final status in <int>[401, 403]) {
        final client = FakeHttpClient((_, _) async => http.Response('denied', status));
        final ai = AiClient(client: client, backoff: noWait);
        await expectLater(
          ai.post(anthropicRequest(
            config: AiConfig.anthropicDefault,
            apiKey: 'k',
            imagesJpeg: const <Uint8List>[],
            date: DateTime(2026, 9, 30),
            dayContext: '',
          )),
          throwsA(isA<AiAuthException>()),
        );
      }
    });

    test('429 重试 3 次后 → AiRateLimitException', () async {
      var calls = 0;
      final client = FakeHttpClient((_, _) async {
        calls++;
        return http.Response('rate limited', 429);
      });
      final ai = AiClient(client: client, backoff: noWait);
      await expectLater(
        ai.post(anthropicRequest(
          config: AiConfig.anthropicDefault,
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: DateTime(2026, 9, 30),
          dayContext: '',
        )),
        throwsA(isA<AiRateLimitException>()),
      );
      // 首次 + 3 次退避重试
      expect(calls, 4);
    });

    test('502 退避后成功 → 正常返回', () async {
      final client = FakeHttpClient((call, _) async {
        if (call <= 2) return http.Response('bad gateway', 502);
        return anthropicOk();
      });
      final ai = AiClient(client: client, backoff: noWait);
      final resp = await ai.post(anthropicRequest(
        config: AiConfig.anthropicDefault,
        apiKey: 'k',
        imagesJpeg: const <Uint8List>[],
        date: DateTime(2026, 9, 30),
        dayContext: '',
      ));
      expect(resp.statusCode, 200);
      expect(client.callCount, 3);
    });

    test('网络异常重试耗尽 → AiNetworkException', () async {
      final client = FakeHttpClient((_, _) async =>
          throw http.ClientException('connection refused'));
      final ai = AiClient(client: client, backoff: noWait);
      await expectLater(
        ai.post(anthropicRequest(
          config: AiConfig.anthropicDefault,
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: DateTime(2026, 9, 30),
          dayContext: '',
        )),
        throwsA(isA<AiNetworkException>()),
      );
      expect(client.callCount, 4);
    });

    test('其余 4xx/5xx → AiServerException 带中文详情', () async {
      final client = FakeHttpClient((_, _) async => jsonResponse(
            <String, Object?>{
              'error': <String, Object?>{'message': 'quota exhausted'},
            },
            status: 400,
          ));
      final ai = AiClient(client: client, backoff: noWait);
      await expectLater(
        ai.post(anthropicRequest(
          config: AiConfig.anthropicDefault,
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: DateTime(2026, 9, 30),
          dayContext: '',
        )),
        throwsA(isA<AiServerException>()
            .having((e) => e.message, 'message', contains('400'))
            .having((e) => e.message, 'message', contains('quota exhausted'))),
      );
    });

    test('预算等不起退避 → 立即抛中文超时，不睡过 deadline、不改报断网', () async {
      var calls = 0;
      final client = FakeHttpClient((_, _) async {
        calls++;
        throw http.ClientException('connection refused');
      });
      // 总预算 60ms、退避 200ms：首轮失败后这一觉会睡过 deadline，
      // 旧实现照样睡满再报「网络连接失败」，新实现立即按超时抛。
      final ai = AiClient(
        client: client,
        totalTimeout: const Duration(milliseconds: 60),
        backoff: const <Duration>[Duration(milliseconds: 200)],
      );
      await expectLater(
        ai.post(anthropicRequest(
          config: AiConfig.anthropicDefault,
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: DateTime(2026, 9, 30),
          dayContext: '',
        )),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('未响应'))
            .having((e) => e is AiNetworkException, 'isNetwork', isFalse)),
      );
      expect(calls, 1, reason: '预算不足再发一次，不该有第二次网络调用');
    });

    test('总预算为零 → 一次请求都不发，直接中文超时', () async {
      final client = FakeHttpClient((_, _) async => anthropicOk());
      final ai = AiClient(client: client, totalTimeout: Duration.zero);
      await expectLater(
        ai.post(anthropicRequest(
          config: AiConfig.anthropicDefault,
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: DateTime(2026, 9, 30),
          dayContext: '',
        )),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('未响应'))
            .having((e) => e is AiNetworkException, 'isNetwork', isFalse)),
      );
      expect(client.callCount, 0);
    });

    test('Base URL 缺协议头 → 发送前就抛配置错误，零重试零网络调用', () async {
      final client = FakeHttpClient((_, _) async => anthropicOk());
      // 默认退避是 1/2/4 秒：旧实现会睡满 7 秒再把它报成「网络连接失败」
      final ai = AiClient(client: client);
      await expectLater(
        ai.post(const AiHttpRequest(
          url: 'api.example.com/v1/messages',
          headers: <String, String>{},
          body: <String, Object?>{},
        )),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('请求地址无效'))
            .having((e) => e.message, 'message', contains('Base URL'))),
      );
      expect(client.callCount, 0, reason: '配置错误重试也没用，必须零网络调用');
    });

    test('非网络异常直接上抛：不重试、不改名成 AiNetworkException', () async {
      final client = FakeHttpClient((_, _) async => throw StateError('编码炸了'));
      final ai = AiClient(client: client, backoff: noWait);
      await expectLater(
        ai.post(anthropicRequest(
          config: AiConfig.anthropicDefault,
          apiKey: 'k',
          imagesJpeg: const <Uint8List>[],
          date: DateTime(2026, 9, 30),
          dayContext: '',
        )),
        throwsA(isA<StateError>()),
      );
      expect(client.callCount, 1, reason: '非网络错误不该进入 1/2/4s 重试');
    });
  });
}
