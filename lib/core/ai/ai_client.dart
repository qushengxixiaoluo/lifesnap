/// AI HTTP 传输层：总超时、指数退避重试、状态码 → 统一异常。
///
/// 为什么单独抽一层：两个适配器只关心「请求长什么样」和「响应怎么读」，
/// 429/5xx 的退避与 401/403 的鉴权错误映射必须只有一份实现，否则迟早漏改。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';
import 'ai_schemas.dart';

/// 一次成功的 HTTP 响应（body 原样保留，交给适配器解析）。
class AiHttpResponse {
  final int statusCode;
  final String body;

  const AiHttpResponse(this.statusCode, this.body);
}

/// 非 2xx 且需要适配器进一步判断的异常。
///
/// 为什么不像 401/403/429 那样直接映射成固定异常：Anthropic 的 400 里
/// 可能是「中转不认 anthropic-beta 头」，适配器必须看到原始 body 才能
/// 决定是否去掉 beta 头重试一次。
class AiHttpException extends AiServerException {
  final int statusCode;
  final String rawBody;

  const AiHttpException(this.statusCode, this.rawBody, String detail)
      : super(detail);
}

class AiClient {
  /// [client] 可注入（单测用假客户端，不发真实网络请求）。
  ///
  /// [backoff] 是每次重试前的等待序列，默认 1s / 2s / 4s（共 3 次重试）；
  /// 测试里会注入零时长，避免用例真的睡 7 秒。
  AiClient({
    http.Client? client,
    this.totalTimeout = const Duration(seconds: 120),
    List<Duration>? backoff,
  })  : _http = client ?? http.Client(),
        _backoff = backoff ??
            const <Duration>[
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 4),
            ];

  final http.Client _http;

  /// 整个调用（含所有重试）的总预算。
  final Duration totalTimeout;

  final List<Duration> _backoff;

  /// 可重试的瞬时状态：限流与 5xx 家族（529 是 Anthropic 的 overloaded）。
  static const Set<int> retryableStatus = <int>{429, 500, 502, 503, 529};

  /// 发送请求；2xx 返回响应，否则按契约抛出 [AiException] 族。
  Future<AiHttpResponse> post(AiHttpRequest request) async {
    // 发送前先做地址预检：缺协议头、Uri 解析失败是「Base URL 填错」这类配置
    // 错误，放进循环里会被当网络错误睡 1+2+4 秒再报「连接失败」，
    // 白等 7 秒还把根因掩盖掉——配置错误必须零重试、早失败、给中文提示。
    final uri = _requestUri(request.url);
    // 预算先起表、再编码：JSON 编码也是要花时间的 CPU 活（十几张图的
    // base64 请求体有数 MB），把它算进总预算才是真正的「全程 120 秒」。
    // 顺带把编码提出重试循环——同一请求体每次重试内容不变，循环里逐次
    // 重编既白烧 CPU，又会让 .timeout（从 post 发出才起算）漏掉编码这段，
    // 重试叠加时实际耗时可能悄悄越过 deadline。
    final deadline = DateTime.now().add(totalTimeout);
    final body = request.encodeBody();
    var attempt = 0;

    /// 一次退避重试的等待：睡之前先对表——预算等不起这一觉就立即抛超时，
    /// 绝不睡过 deadline（旧实现会把剩余退避序列睡完，最坏超预算约 7 秒）。
    Future<void> backoff() async {
      final remaining = deadline.difference(DateTime.now());
      final wait = _backoff[attempt];
      if (wait >= remaining) throw _timeoutException();
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      attempt++;
    }

    while (true) {
      try {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) throw _timeoutException();
        final resp = await _http
            .post(uri, headers: request.headers, body: body)
            .timeout(remaining);

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return AiHttpResponse(resp.statusCode, resp.body);
        }
        if (retryableStatus.contains(resp.statusCode) &&
            attempt < _backoff.length) {
          await backoff();
          continue;
        }
        throw _mapStatus(resp.statusCode, resp.body);
      } on AiException {
        // 已经是面向业务的异常（含 429 重试耗尽、总超时），原样抛出不再兜圈
        rethrow;
      } on TimeoutException {
        // .timeout(remaining) 只可能在总预算耗尽时触发：这是「请求太慢」，
        // 不是「断网」——旧实现把它归进 AiNetworkException，误导用户查网络。
        throw _timeoutException();
      } on http.ClientException {
        // 只重试网络层瞬时错误：断连 / DNS / TLS（package:http 的 IOClient
        // 已把 SocketException 包成 ClientException 的子类，因此共享代码
        // 无需 import dart:io）。其余异常（请求体编码失败、插件 bug 等）
        // 不接——直接上抛，不浪费退避也绝不改名成「网络连接失败」。
        if (attempt < _backoff.length) {
          await backoff();
          continue;
        }
        throw const AiNetworkException();
      }
    }
  }

  /// 发送前的地址预检：无 authority 或非 http(s) 协议一律视为配置错误。
  static Uri _requestUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw AiException('请求地址无效：$url（Base URL 需以 http:// 或 https:// 开头）');
    }
    return uri;
  }

  /// 总预算耗尽的统一出口：中文「太慢」说明，与断网（AiNetworkException）区分。
  AiException _timeoutException() =>
      AiException('AI 请求超过 ${totalTimeout.inSeconds} 秒未响应');

  /// HTTP 状态 → 异常（401/403 鉴权、429 限流、其余带中文详情的 4xx/5xx）。
  AiException _mapStatus(int status, String body) {
    if (status == 401 || status == 403) return const AiAuthException();
    if (status == 429) return const AiRateLimitException();
    return AiHttpException(status, body, '服务端返回 $status：${_errorDetail(body)}');
  }

  /// 从错误响应体里抠出可读原因；抠不出来就给前 200 字符，避免整页 HTML 灌进 UI。
  static String _errorDetail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '无返回内容';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
          final type = error['type'];
          if (type is String && type.trim().isNotEmpty) return type.trim();
        }
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {/* 不是 JSON，落到截断展示 */}
    // 按码点截断：substring(0,200) 按 UTF-16 码元切，边界压在 emoji 代理对
    // 中间会切出孤立代理项，污染错误文案（与 ai_schemas._clamp 同类隐患）。
    return trimmed.runes.length <= 200
        ? trimmed
        : '${String.fromCharCodes(trimmed.runes.take(200))}…';
  }
}
