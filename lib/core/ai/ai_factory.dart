/// AI 适配器工厂（D 轨填充；阶段 0 钉死的签名保持不变）。
///
/// 【钉死的签名】E 轨设置页「测试连接」与阶段 2 集成盲写对接，D 轨必须保持签名不变。
library;

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'ai_client.dart';
import 'ai_provider.dart';
import 'anthropic_adapter.dart';
import 'openai_adapter.dart';

class AiFactory {
  AiFactory._();

  /// 由配置 + 明文 key 构造对应平台的 AiProvider。
  /// key 从 ApiKeyStore 读出后传入；本函数不负责存取 key。
  static AiProvider create(AiConfig config, String apiKey) =>
      createWithClient(config, apiKey);

  /// 与 [create] 等价，但可注入 [client]（单测传假客户端）或已配好的 [aiClient]
  /// （仓库希望复用同一个超时/退避策略时使用）。
  ///
  /// 为什么多开一个方法：`create` 的签名是阶段 0 钉死的契约不能动，
  /// 而测试必须能注入 HTTP 替身，于是把可选项放到这里。
  static AiProvider createWithClient(
    AiConfig config,
    String apiKey, {
    http.Client? client,
    AiClient? aiClient,
  }) {
    final resolved = aiClient ?? AiClient(client: client);
    switch (config.provider) {
      case AiProviderKind.anthropic:
        return AnthropicAdapter(config, apiKey, client: resolved);
      case AiProviderKind.openai:
        return OpenAIAdapter(config, apiKey, client: resolved);
    }
  }
}
