/// AI 轨单测公共替身：假 http.Client（铁律：单测禁止真实网络）。
///
/// 为什么用 BaseClient 子类而不是 Mock：BaseClient 只需要覆写 send()，
/// post()/get() 都会自动落到 send()，请求体、headers 都能原样拿到做断言。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// 记录全部出站请求、按序回放预设响应的假客户端。
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._responder);

  /// 每次请求的处理函数；第二个请求起可返回不同响应以模拟「重试后成功」。
  final Future<http.Response> Function(int call, http.Request request) _responder;

  final List<http.Request> requests = <http.Request>[];

  int get callCount => requests.length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requests.add(req);
    final resp = await _responder(requests.length, req);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[resp.bodyBytes]),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

/// 读 header（大小写不敏感，package:http 内部会把键规范化）。
String? headerOf(http.BaseRequest request, String name) {
  final lower = name.toLowerCase();
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

/// JSON 响应工厂。
http.Response jsonResponse(
  Map<String, Object?> body, {
  int status = 200,
  Map<String, String> headers = const <String, String>{},
}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json', ...headers},
    );

/// 一段合法的日总结 JSON（供两级响应体拼装）。
String daySummaryJson({
  String title = '海风与旧单车',
  String narrative = '傍晚的风从堤岸那边吹过来，把晾在绳子上的衬衫吹得鼓鼓的，'
      '你推着那辆掉了漆的旧单车经过小卖部，玻璃罐里的冰棍还剩最后一根，'
      '于是我们停下来分着吃完，天边的云被烧成橘红色，海面亮得像一整块锡纸。',
  List<String> tags = const <String>['海边', '黄昏', '单车'],
  String mood = '晴',
  List<String> highlights = const <String>['堤岸追风', '分冰棍'],
}) =>
    jsonEncode(<String, Object?>{
      'title': title,
      'narrative': narrative,
      'tags': tags,
      'mood': mood,
      'highlights': highlights,
    });

/// Anthropic Messages 成功回执（content 是 text block 数组）。
http.Response anthropicOk({String model = 'claude-opus-5-5'}) => jsonResponse(
      <String, Object?>{
        'id': 'msg_test',
        'type': 'message',
        'role': 'assistant',
        'model': model,
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': daySummaryJson()},
        ],
        'stop_reason': 'end_turn',
        'usage': <String, Object?>{'input_tokens': 10, 'output_tokens': 20},
      },
    );

/// OpenAI Chat Completions 成功回执（content 是纯字符串）。
http.Response openaiOk({String model = 'gpt-4o'}) => jsonResponse(
      <String, Object?>{
        'id': 'chatcmpl_test',
        'object': 'chat.completion',
        'model': model,
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'message': <String, Object?>{
              'role': 'assistant',
              'content': daySummaryJson(),
            },
            'finish_reason': 'stop',
          },
        ],
      },
    );
