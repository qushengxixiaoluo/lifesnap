/// AI 请求构造与响应宽容解析（纯函数，不碰网络，便于逐字段单测）。
///
/// 为什么单独成文件：请求体是「Anthropic / OpenAI 双格式」最容易写错的地方，
/// 做成纯函数后可以在不发真请求的前提下断言 headers 与 image block；
/// 解析侧同理——三家模型输出 JSON 的习惯都不一样，容错链必须只有一份实现。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import 'ai_provider.dart';

/// 官方 Anthropic 端点（AiConfig.baseUrl 为空时回落到这里）。
const String anthropicOrigin = 'https://api.anthropic.com';

/// 日总结 JSON Schema。
///
/// 为什么共用一份：Anthropic 的 `output_config.format` 与提示词必须描述
/// 完全相同的字段，否则模型在「结构化输出」和「文字要求」之间会摇摆。
const Map<String, Object?> daySummaryJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['title', 'narrative', 'tags', 'mood', 'highlights'],
  'properties': <String, Object?>{
    'title': <String, Object?>{
      'type': 'string',
      'description': '当日标题，不超过 12 个字',
      'maxLength': 12,
    },
    'narrative': <String, Object?>{
      'type': 'string',
      'description': '80-200 字的中文散文式总结',
    },
    'tags': <String, Object?>{
      'type': 'array',
      'maxItems': 6,
      'items': <String, Object?>{'type': 'string', 'description': '2-4 字标签'},
    },
    'mood': <String, Object?>{
      'type': 'string',
      'enum': <String>['晴', '多云', '小雨', '彩虹', '星夜'],
    },
    'highlights': <String, Object?>{
      'type': 'array',
      'maxItems': 3,
      'items': <String, Object?>{
        'type': 'string',
        'description': '不超过 10 字的瞬间短语',
      },
    },
  },
};

/// 一次可直接发送的 HTTP 请求（纯数据对象，单测可断言 url/headers/body）。
class AiHttpRequest {
  final String url;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  const AiHttpRequest({
    required this.url,
    required this.headers,
    required this.body,
  });

  /// 发送前统一编码为 JSON。
  String encodeBody() => jsonEncode(body);
}

/// 拼接端点 URL。
///
/// 为什么特判 `/v1`：很多用户会把 `https://xxx/v1` 整段填进 Base URL，
/// 直接再拼 `/v1/...` 会得到 `/v1/v1/...` 从而 404，这里做一次幂等处理。
String buildEndpoint(String baseUrl, String path, {required String fallbackOrigin}) {
  var base = baseUrl.trim();
  if (base.isEmpty) base = fallbackOrigin;
  base = base.replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return path;
  if (path.startsWith('/v1/') && base.endsWith('/v1')) return base + path.substring(3);
  return base + path;
}

/// 配置里的模型名（空串回落平台默认），请求体与回执解析共用。
String modelOf(AiConfig config, {required String fallback}) {
  final m = config.model.trim();
  return m.isEmpty ? fallback : m;
}

/// effort 只接受 low/medium/high；设置页是自由输入，脏值一律降级为 low，
/// 免得把无效值原样发给 Anthropic 换一个 400。
String effortOf(AiConfig config) {
  final e = config.effort.trim();
  return (e == 'low' || e == 'medium' || e == 'high') ? e : 'low';
}

/// 中文任务文本：日期星期、本次照片张数、写作风格要求。
///
/// 为什么由构造器统一生成：两家请求体里这段文字必须一致，
/// 否则同一份照片在两个平台上会得到风格不同的总结。
String buildDayPrompt({
  required DateTime date,
  required int photoCount,
  required String dayContext,
}) {
  const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final weekday = weekdays[date.weekday - 1];
  final dateLine = '${date.year}年${date.month}月${date.day}日 $weekday';
  final context = dayContext.trim();
  final contextBlock = context.isEmpty ? '' : '\n补充信息：$context\n';
  return '请为下面这一天生成一份「拾光手册」的中文每日总结。\n'
      '\n'
      '$dateLine\n'
      '本次提交 $photoCount 张照片。$contextBlock\n'
      '要求：\n'
      '1. 先通读全部照片，抓住这一天的主线，而不是逐张描述；\n'
      '2. narrative 写成 80-200 字的中文散文，克制、具体、有画面感，像电影旁白；\n'
      '3. title 不超过 12 个字；\n'
      '4. tags 不超过 6 个（每个 2-4 字）；\n'
      '5. mood 只能取 晴 / 多云 / 小雨 / 彩虹 / 星夜 之一；\n'
      '6. highlights 不超过 3 条（每条不超过 10 字）。\n'
      '\n'
      '只输出一个 JSON 对象，不要解释、不要 Markdown 代码围栏。';
}

/// OpenAI 侧的 system 说明（Chat Completions 没有 output_config，只能靠提示词约束）。
const String openaiSystemPrompt =
    '你是「拾光手册」的日总结作者，把一天的照片写成简短的中文散文。'
    '只输出一个 JSON 对象，包含 title、narrative、tags、mood、highlights 五个字段，'
    '不要输出 Markdown 代码围栏，不要输出任何解释。';

// ---------------------------------------------------------------------------
// 月度回顾：提示词 + 双格式请求 + 宽容解析
// ---------------------------------------------------------------------------

/// 月报 JSON Schema（Anthropic structured output 用；与提示词描述保持同一份）。
const Map<String, Object?> monthlyReviewJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['title', 'narrative', 'tags', 'highlights'],
  'properties': <String, Object?>{
    'title': <String, Object?>{
      'type': 'string',
      'description': '月报标题，不超过 12 个字，如「九月的风」',
      'maxLength': 12,
    },
    'narrative': <String, Object?>{
      'type': 'string',
      'description': '300-600 字的中文月度散文',
    },
    'tags': <String, Object?>{
      'type': 'array',
      'maxItems': 6,
      'items': <String, Object?>{
        'type': 'string',
        'description': '2-4 字的当月主题标签',
      },
    },
    'highlights': <String, Object?>{
      'type': 'array',
      'maxItems': 5,
      'items': <String, Object?>{
        'type': 'string',
        'description': '不超过 14 字的当月亮点',
      },
    },
  },
};

/// 月报的 system 说明（两家适配器共用同一段文字，风格与日总结提示词对齐）。
const String monthlySystemPrompt =
    '你是「拾光手册」的月度回顾作者，把一个月的日总结浓缩成一篇中文月度散文。'
    '不要逐日复述，要提炼当月的主线、情绪起伏与反复出现的主题。'
    '只输出一个 JSON 对象，包含 title、narrative、tags、highlights 四个字段，'
    '不要输出 Markdown 代码围栏，不要输出任何解释。';

/// 月报 user 文本：逐日列出（日期、标题、正文、标签、心情、瞬间）。
///
/// 为什么由构造器统一生成：两家请求体里这段文字必须一致，
/// 同一批日总结在两个平台上才会有风格相同的月报。
String buildMonthlyPrompt({
  required int year,
  required int month,
  required List<AiSummary> days,
}) {
  const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final buf = StringBuffer()
    ..writeln('请为下面这个月生成一份「拾光手册」的月度回顾。')
    ..writeln()
    ..writeln('$year 年 $month 月，共 ${days.length} 天日总结：');
  for (final d in days) {
    final date = dayKeyToDateTime(d.dayKey);
    final weekday = weekdays[date.weekday - 1];
    buf
      ..writeln()
      ..writeln('【${date.month}月${date.day}日 $weekday】${d.title}')
      ..writeln(d.narrative);
    if (d.tags.isNotEmpty) buf.writeln('标签：${d.tags.join('、')}');
    buf.writeln('心情：${d.mood}');
    if (d.highlights.isNotEmpty) {
      buf.writeln('瞬间：${d.highlights.join('、')}');
    }
  }
  buf
    ..writeln()
    ..writeln('要求：')
    ..writeln('1. 通读全部日总结，提炼整月的主线与情绪走向，不要逐日流水账；')
    ..writeln('2. narrative 写成 300-600 字的中文散文，克制、具体、有画面感；')
    ..writeln('3. title 不超过 12 个字（如「九月的风」）；')
    ..writeln('4. tags 不超过 6 个当月主题标签（每个 2-4 字）；')
    ..writeln('5. highlights 不超过 5 条当月亮点（每条不超过 14 字）。')
    ..writeln()
    ..writeln('只输出一个 JSON 对象，不要解释、不要 Markdown 代码围栏。');
  return buf.toString();
}

/// Anthropic 月报请求体（纯文本：system + 单条 user 文本，不带图片）。
AiHttpRequest anthropicMonthlyRequest({
  required AiConfig config,
  required String apiKey,
  required int year,
  required int month,
  required List<AiSummary> days,
  bool withFallbackBeta = true,
}) =>
    AiHttpRequest(
      url: buildEndpoint(config.baseUrl, '/v1/messages', fallbackOrigin: anthropicOrigin),
      headers: <String, String>{
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (withFallbackBeta) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body: <String, Object?>{
        'model': modelOf(config, fallback: 'claude-opus-5-5'),
        'max_tokens': 4096,
        'system': monthlySystemPrompt,
        'output_config': <String, Object?>{
          'effort': effortOf(config),
          'format': <String, Object?>{
            'type': 'json_schema',
            'schema': monthlyReviewJsonSchema,
          },
        },
        if (effortOf(config) == 'high')
          'thinking': <String, Object?>{'type': 'adaptive'},
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': buildMonthlyPrompt(year: year, month: month, days: days),
              },
            ],
          },
        ],
        if (withFallbackBeta) 'fallbacks': 'default',
      },
    );

/// OpenAI 月报请求体（system + user 纯文本，response_format=json_object）。
AiHttpRequest openaiMonthlyRequest({
  required AiConfig config,
  required String apiKey,
  required int year,
  required int month,
  required List<AiSummary> days,
}) {
  _requireBaseUrl(config);
  return AiHttpRequest(
    url: buildEndpoint(config.baseUrl, '/v1/chat/completions', fallbackOrigin: ''),
    headers: <String, String>{
      'content-type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: <String, Object?>{
      'model': modelOf(config, fallback: 'gpt-4o'),
      'max_tokens': 4096,
      'response_format': <String, Object?>{'type': 'json_object'},
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': monthlySystemPrompt},
        <String, Object?>{
          'role': 'user',
          'content': buildMonthlyPrompt(year: year, month: month, days: days),
        },
      ],
    },
  );
}

/// 把模型返回的任意形态文本解析成 [MonthlyReview]（宽容链与 [parseAiSummary] 同构）。
///
/// 依次尝试（全部失败才抛 [AiFormatException]）：
/// 1. 直接是结构化对象（Map / 已经是合法 JSON 字符串）；
/// 2. content 块数组或嵌套外壳 → 拼接成字符串后再走同一条链；
/// 3. 剥掉 ```json ... ``` 代码围栏；
/// 4. 截取首个 `{` 到末个 `}` 再 jsonDecode。
///
/// 解析成功后做宽容收敛：标题截到 12 字、tags 截到 6、highlights 截到 5。
/// inputSig / createdAtMs 不在此处决定——它们属于「本次生成依据了哪些日总结」，
/// 由 MonthlyReviewRepository 落库时统一回填。
MonthlyReview parseMonthlySummary(
  Object? text,
  int year,
  int month,
  String model,
) {
  final review = _tryParseMonthly(text, year, month, model, allowNesting: true);
  if (review != null) return review;
  throw const AiFormatException();
}

MonthlyReview? _tryParseMonthly(
  Object? raw,
  int year,
  int month,
  String model, {
  required bool allowNesting,
}) {
  if (raw is Map) {
    final direct = _monthlyFromMap(raw, year, month, model);
    if (direct != null) return direct;
    if (allowNesting) {
      // 结构化外壳：{content: ...} / {message: {content: ...}} / {review: {...}}
      for (final key in const <String>['content', 'message', 'review', 'result']) {
        if (!raw.containsKey(key)) continue;
        final nested = _tryParseMonthly(
          raw[key],
          year,
          month,
          model,
          allowNesting: false,
        );
        if (nested != null) return nested;
      }
    }
    return null;
  }
  if (raw is List) {
    final joined = _joinBlocks(raw);
    if (joined.isEmpty) return null;
    return _tryParseMonthly(joined, year, month, model, allowNesting: allowNesting);
  }
  if (raw is! String) return null;

  for (final candidate in _candidates(raw)) {
    Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (_) {
      continue; // 这一级没解出来，继续尝试更宽松的下一级
    }
    if (decoded is Map) {
      final s = _monthlyFromMap(decoded, year, month, model);
      if (s != null) return s;
      if (allowNesting) {
        final nested = _tryParseMonthly(
          decoded,
          year,
          month,
          model,
          allowNesting: false,
        );
        if (nested != null) return nested;
      }
    }
  }
  return null;
}

MonthlyReview? _monthlyFromMap(Map m, int year, int month, String model) {
  final title = _text(m['title']);
  final narrative = _text(m['narrative']);
  if (title.isEmpty || narrative.isEmpty) return null; // 不像月报，换下一级候选

  final tags = _stringList(m['tags']);
  final highlights = _stringList(m['highlights']);
  return MonthlyReview(
    year: year,
    month: month,
    title: _clamp(title, 12),
    narrative: narrative,
    tags: tags.length > 6 ? tags.sublist(0, 6) : tags,
    highlights: highlights.length > 5 ? highlights.sublist(0, 5) : highlights,
    model: model,
    inputSig: '',
    createdAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Anthropic Messages 请求体（含 headers 与 url）。
///
/// [withFallbackBeta] 默认带 `anthropic-beta: server-side-fallback-2026-07-01`
/// 与 body 的 `fallbacks:"default"`；中转服务常不认这两个字段，
/// 适配器拿到 400 后会用 false 重建请求重试一次。
AiHttpRequest anthropicRequest({
  required AiConfig config,
  required String apiKey,
  required List<Uint8List> imagesJpeg,
  required DateTime date,
  required String dayContext,
  bool withFallbackBeta = true,
}) {
  final content = <Map<String, Object?>>[
    for (final img in imagesJpeg) _anthropicImageBlock(img),
    <String, Object?>{
      'type': 'text',
      'text': buildDayPrompt(
        date: date,
        photoCount: imagesJpeg.length,
        dayContext: dayContext,
      ),
    },
  ];
  return AiHttpRequest(
    url: buildEndpoint(config.baseUrl, '/v1/messages', fallbackOrigin: anthropicOrigin),
    headers: <String, String>{
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      if (withFallbackBeta) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    },
    body: <String, Object?>{
      'model': modelOf(config, fallback: 'claude-opus-5-5'),
      'max_tokens': 4096,
      'output_config': <String, Object?>{
        'effort': effortOf(config),
        'format': <String, Object?>{
          'type': 'json_schema',
          'schema': daySummaryJsonSchema,
        },
      },
      // thinking 只允许省略或 {type:adaptive}——传 disabled 会被 opus-5-5 判 400。
      // 默认省略（最稳，也不额外烧 token），只有用户主动把 effort 拉到 high 时才打开。
      if (effortOf(config) == 'high')
        'thinking': <String, Object?>{'type': 'adaptive'},
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': content},
      ],
      if (withFallbackBeta) 'fallbacks': 'default',
    },
  );
}

/// Anthropic「测试连接」用的最小请求（16 token 纯文本，不带图片与结构化输出）。
AiHttpRequest anthropicTestRequest({
  required AiConfig config,
  required String apiKey,
}) =>
    AiHttpRequest(
      url: buildEndpoint(config.baseUrl, '/v1/messages', fallbackOrigin: anthropicOrigin),
      headers: <String, String>{
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: <String, Object?>{
        'model': modelOf(config, fallback: 'claude-opus-5-5'),
        'max_tokens': 16,
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': '只回复：ok'},
        ],
      },
    );

/// OpenAI Chat Completions 请求体（含 headers 与 url）。
///
/// Base URL 必填：OpenAI 兼容服务（中转、DeepSeek、Ollama…）全都自定义端点，
/// 猜一个官方地址没有意义，宁可早失败并给出中文引导。
AiHttpRequest openaiRequest({
  required AiConfig config,
  required String apiKey,
  required List<Uint8List> imagesJpeg,
  required DateTime date,
  required String dayContext,
}) {
  _requireBaseUrl(config);
  final parts = <Map<String, Object?>>[
    for (final img in imagesJpeg) _openaiImagePart(img),
    <String, Object?>{
      'type': 'text',
      'text': buildDayPrompt(
        date: date,
        photoCount: imagesJpeg.length,
        dayContext: dayContext,
      ),
    },
  ];
  return AiHttpRequest(
    url: buildEndpoint(config.baseUrl, '/v1/chat/completions', fallbackOrigin: ''),
    headers: <String, String>{
      'content-type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: <String, Object?>{
      'model': modelOf(config, fallback: 'gpt-4o'),
      'max_tokens': 4096,
      // 兼容端点不一定支持 json_object，但支持时能显著降低「散文里夹解释」的概率；
      // 不支持的服务会直接 400，用户改设置即可（错误信息会原样带中文透出）。
      'response_format': <String, Object?>{'type': 'json_object'},
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': openaiSystemPrompt},
        <String, Object?>{'role': 'user', 'content': parts},
      ],
    },
  );
}

/// OpenAI「测试连接」用的最小请求。
AiHttpRequest openaiTestRequest({
  required AiConfig config,
  required String apiKey,
}) {
  _requireBaseUrl(config);
  return AiHttpRequest(
    url: buildEndpoint(config.baseUrl, '/v1/chat/completions', fallbackOrigin: ''),
    headers: <String, String>{
      'content-type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: <String, Object?>{
      'model': modelOf(config, fallback: 'gpt-4o'),
      'max_tokens': 16,
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': '只回复：ok'},
      ],
    },
  );
}

/// 从原始响应 body 里取出「助手内容」，交给 [parseAiSummary]。
///
/// 为什么不直接在适配器里取：两家的字段路径不同（content / choices[0].message.content），
/// 而且中转可能塞回任意一层，集中处理后容错链只需要写一次。
Object? extractAssistantContent(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return body; // 整段都不是 JSON → 原样交给解析器的花括号截取分支
  }
  if (decoded is! Map) return body;

  // Anthropic Messages：content 可能是 [{type:text,text:...}] 也可能是纯字符串
  final content = decoded['content'];
  if (content is List || content is String) return content;

  // OpenAI Chat Completions / 老式 completion
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final message = first['message'];
      if (message is Map) {
        final c = message['content'];
        if (c != null) return c;
      }
      final legacy = first['text'];
      if (legacy != null) return legacy;
    }
  }
  return decoded; // 兜底：让解析器走「结构化字段」分支
}

// ---------------------------------------------------------------------------
// 宽容解析：结构化字段 → 拼接 content → 剥代码围栏 → 截花括号
// ---------------------------------------------------------------------------

/// 把模型返回的任意形态文本解析成 [AiSummary]。
///
/// 依次尝试（全部失败才抛 [AiFormatException]）：
/// 1. 直接是结构化对象（Map / 已经是合法 JSON 字符串）；
/// 2. content 是块数组或嵌套对象 → 拼接成字符串后再走同一条链；
/// 3. 剥掉 ```json ... ``` 代码围栏；
/// 4. 截取首个 `{` 到末个 `}` 再 jsonDecode（对付「先说一句话再给 JSON」）。
///
/// 解析成功后还会做一次宽容收敛：标题截到 12 字、tags/highlights 截到上限、
/// 非法 mood 回落「晴」——模型偶尔不听话，但用户不该看到崩溃或空白。
AiSummary parseAiSummary(
  Object? text,
  int dayKey,
  String model,
  String photoSig,
) {
  final summary = _tryParse(text, dayKey, model, photoSig, allowNesting: true);
  if (summary != null) return summary;
  throw const AiFormatException();
}

AiSummary? _tryParse(
  Object? raw,
  int dayKey,
  String model,
  String photoSig, {
  required bool allowNesting,
}) {
  if (raw is Map) {
    final direct = _summaryFromMap(raw, dayKey, model, photoSig);
    if (direct != null) return direct;
    if (allowNesting) {
      // 结构化外壳：{content: ...} / {message: {content: ...}} / {summary: {...}}
      for (final key in const <String>['content', 'message', 'summary', 'result']) {
        if (!raw.containsKey(key)) continue;
        final nested = _tryParse(
          raw[key],
          dayKey,
          model,
          photoSig,
          allowNesting: false,
        );
        if (nested != null) return nested;
      }
    }
    return null;
  }
  if (raw is List) {
    // Anthropic content blocks：把所有 text 块拼起来
    final joined = _joinBlocks(raw);
    if (joined.isEmpty) return null;
    return _tryParse(joined, dayKey, model, photoSig, allowNesting: allowNesting);
  }
  if (raw is! String) return null;

  for (final candidate in _candidates(raw)) {
    Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (_) {
      continue; // 这一级没解出来，继续尝试更宽松的下一级
    }
    if (decoded is Map) {
      final s = _summaryFromMap(decoded, dayKey, model, photoSig);
      if (s != null) return s;
      if (allowNesting) {
        final nested = _tryParse(decoded, dayKey, model, photoSig, allowNesting: false);
        if (nested != null) return nested;
      }
    }
  }
  return null;
}

/// 三级候选文本：原样 → 剥围栏 → 截花括号。
List<String> _candidates(String raw) {
  final out = <String>[];
  void push(String s) {
    final t = s.trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }

  push(raw);

  // ```json\n{...}\n``` 或 ```\n{...}\n```（整段就是一块围栏）
  final fence = RegExp(r'^```[a-zA-Z0-9_-]*\s*([\s\S]*?)\s*```$');
  final m = fence.firstMatch(raw.trim());
  if (m != null) push(m.group(1) ?? '');

  // 宽松剥围栏：任意位置的 ``` 都去掉（模型偶尔会多给一层）
  if (raw.contains('```')) push(raw.replaceAll('```', ''));

  // 首个左花括号到末个右花括号
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) push(raw.substring(start, end + 1));

  return out;
}

/// 把 content 块数组拼成一段纯文本。
String _joinBlocks(List<Object?> blocks) {
  final buf = StringBuffer();
  for (final b in blocks) {
    if (b is String) {
      buf.writeln(b);
      continue;
    }
    if (b is Map) {
      final t = b['text'];
      if (t is String) buf.writeln(t);
    }
  }
  return buf.toString().trim();
}

AiSummary? _summaryFromMap(
  Map m,
  int dayKey,
  String model,
  String photoSig,
) {
  final title = _text(m['title']);
  final narrative = _text(m['narrative']);
  if (title.isEmpty || narrative.isEmpty) return null; // 不像日总结，换下一级候选

  final tags = _stringList(m['tags']);
  final highlights = _stringList(m['highlights']);
  return AiSummary(
    dayKey: dayKey,
    title: _clamp(title, 12),
    narrative: narrative,
    tags: tags.length > 6 ? tags.sublist(0, 6) : tags,
    mood: _normalizeMood(m['mood']),
    highlights: highlights.length > 3 ? highlights.sublist(0, 3) : highlights,
    model: model,
    photoSig: photoSig,
    createdAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}

const Set<String> _moods = <String>{'晴', '多云', '小雨', '彩虹', '星夜'};

String _normalizeMood(Object? value) {
  final s = _text(value);
  return _moods.contains(s) ? s : '晴';
}

String _text(Object? value) => value is String ? value.trim() : '';

/// 按码点截断：substring(0,max) 按 UTF-16 码元切，第 max 字恰是 emoji
/// （占 2 码元、JSON Schema 的 maxLength 按码点计数所以属合法输入）时
/// 会切出孤立代理项——落库 jsonEncode / utf8 编码会产出坏数据，界面显示乱码。
String _clamp(String s, int max) => s.runes.length <= max
    ? s
    : String.fromCharCodes(s.runes.take(max));

/// tags / highlights 的宽容读取：数组、JSON 数组字符串、逗号连写都接受。
List<String> _stringList(Object? value) {
  if (value is List) {
    return <String>[
      for (final e in value)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  }
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return const <String>[];
    if (t.startsWith('[')) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is List) {
          return <String>[
            for (final e in decoded)
              if (e is String && e.trim().isNotEmpty) e.trim(),
          ];
        }
      } catch (_) {/* 落到分隔符切分 */}
    }
    return t
        .split(RegExp(r'[,、，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

// ---------------------------------------------------------------------------
// 私有小工具
// ---------------------------------------------------------------------------

void _requireBaseUrl(AiConfig config) {
  if (config.baseUrl.trim().isEmpty) {
    throw const AiException('OpenAI 兼容接口需要先在设置页填写 Base URL');
  }
}

Map<String, Object?> _anthropicImageBlock(Uint8List bytes) => <String, Object?>{
      'type': 'image',
      'source': <String, Object?>{
        'type': 'base64',
        'media_type': 'image/jpeg',
        'data': base64Encode(bytes),
      },
    };

Map<String, Object?> _openaiImagePart(Uint8List bytes) => <String, Object?>{
      'type': 'image_url',
      'image_url': <String, Object?>{
        'url': 'data:image/jpeg;base64,${base64Encode(bytes)}',
      },
    };
