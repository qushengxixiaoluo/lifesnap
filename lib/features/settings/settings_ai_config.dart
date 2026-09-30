/// 设置页 · AI 配置分区（E 轨）。
///
/// 布局按用户要求统一为「三件套」固定平铺，两种请求格式都常显：
///   ① API 地址（Anthropic 留空=官方；OpenAI 必填，可指中转）
///   ② API Key（输入时遮蔽，保存后可一键显示/隐藏——用户要求能回显）
///   ③ 模型名称（自由文本，占位提示常用 id）
/// 外加显式「保存配置」按钮（用户要求：填完要有明确的保存动作）。
/// 服务商两卡只决定请求报文格式，不再隐藏/显示字段，也不再显示技术提醒。
/// 每次改动经 SettingsStore.saveAiConfig 落盘；key 只走 ApiKeyStore。
library;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import '../../core/ai/ai_factory.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/models/models.dart';
import '../../core/storage/settings_store.dart';
import 'settings_utils.dart';

class AiConfigSection extends StatefulWidget {
  const AiConfigSection({super.key});

  @override
  State<AiConfigSection> createState() => _AiConfigSectionState();
}

class _AiConfigSectionState extends State<AiConfigSection> {
  AiConfig? _config; // null = 还在读盘
  bool _keyExists = false;
  bool _replacingKey = false; // 已存 key 时是否正在输入新值（切换输入框显隐）
  bool _savingKey = false;
  bool _testing = false;
  bool _testOk = false;
  String? _keyTip; // 「已保存 ✓」或错误文案
  String? _testMsg;
  String? _saveTip; // 「保存配置」按钮的确认/报错文案

  // key 回显（用户明确要求：保存后可以查看，不必永远藏起来）
  String? _savedKey; // 已保存 key 的明文（仅内存，用于回显）
  bool _savedKeyVisible = false; // 已保存 key 当前是否处于明文显示
  bool _inputKeyVisible = false; // 输入框明文开关（输入时默认遮蔽）

  final _keyCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await SettingsStore.loadAiConfig();
    final key = await ApiKeyStore.read(); // 存在才回显，没存读到 null
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _keyExists = key != null && key.isNotEmpty;
      _savedKey = key;
      _baseCtrl.text = cfg.baseUrl;
      _modelCtrl.text = cfg.model;
    });
  }

  /// 遮蔽展示：保留末 4 位便于核对，其余用圆点。
  String _maskKey(String? k) {
    if (k == null || k.isEmpty) return '（未保存）';
    if (k.length <= 8) return '•' * k.length;
    return '${'•' * 12}${k.substring(k.length - 4)}';
  }

  /// 显式「保存配置」：冲刷两个输入框 + 顺带保存输入中的 Key。
  /// （页面本身是即时落盘的，这个按钮是给用户一个明确的确认动作与校验入口。）
  Future<void> _saveAll() async {
    final cfg = _config;
    if (cfg == null) return;
    final model = _modelCtrl.text.trim();
    if (model.isEmpty) {
      setState(() => _saveTip = '模型名称不能为空');
      return;
    }
    // 输入框里躺着未保存的 Key → 一并写入安全存储
    final typedKey = _keyCtrl.text.trim();
    if ((!_keyExists || _replacingKey) && typedKey.isNotEmpty) {
      await ApiKeyStore.write(typedKey);
      final fresh = await ApiKeyStore.read();
      if (!mounted) return;
      setState(() {
        _keyExists = true;
        _replacingKey = false;
        _savedKey = fresh;
        _keyCtrl.clear();
      });
    }
    await _save(cfg.copyWith(baseUrl: _baseCtrl.text.trim(), model: model));
    if (!mounted) return;
    setState(() => _saveTip = '已保存 ✓');
  }

  List<(AiProviderKind, String, String)> _modelPresetsFor(AiProviderKind k) =>
      AiConfig.modelPresets.where((p) => p.$1 == k).toList();

  /// 所有配置改动的唯一出口：内存态 + 落盘。
  ///
  /// 落盘失败不弹错打断输入：SharedPreferences 在六端都有实现，
  /// 失败属极端环境，静默重试下一次改动即可。
  Future<void> _save(AiConfig next) async {
    setState(() => _config = next);
    try {
      await SettingsStore.saveAiConfig(next);
    } catch (_) {/* 内存态已生效，失败不影响 UI，下次改动会再写 */}
  }

  Future<void> _switchProvider(AiProviderKind kind) async {
    final cfg = _config;
    if (cfg == null) return;
    var next = cfg.copyWith(provider: kind);
    // 只有「对方平台的官方默认模型」才自动替换（claude-xxx 切到 OpenAI 时换 gpt 默认）；
    // 用户自己敲的自定义模型（如 mimo-v2.6-pro 中转）一律保留——
    // 中转服务模型名和报文格式是两回事，不能因为切个格式就清掉用户输入。
    const stockAnthropic = {'claude-opus-5-5', 'claude-sonnet-5-5'};
    const stockOpenai = {'gpt-4o'};
    final toReplace = kind == AiProviderKind.openai
        ? stockAnthropic.contains(next.model)
        : stockOpenai.contains(next.model);
    if (toReplace) {
      next = next.copyWith(model: _defaultModelFor(kind));
      _modelCtrl.text = next.model;
    }
    await _save(next);
  }

  /// 该平台的默认模型（modelPresets 第一项）。
  String _defaultModelFor(AiProviderKind kind) =>
      _modelPresetsFor(kind).first.$2;

  // ------------------------------------------------------------ API Key

  Future<void> _saveKey() async {
    final raw = _keyCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _keyTip = 'Key 不能为空');
      return;
    }
    setState(() => _savingKey = true);
    try {
      await ApiKeyStore.write(raw);
      final fresh = await ApiKeyStore.read();
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _keyExists = true;
        _replacingKey = false;
        _keyTip = '已保存 ✓';
        _savedKey = fresh; // 保存后可回显（用户要求），默认仍遮蔽、眼睛开关切换
        _savedKeyVisible = false;
        _keyCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _keyTip = '保存失败：$e';
      });
    }
  }

  Future<void> _clearKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('清除 API Key'),
        content: const Text('确定清除已保存的 API Key 吗？清除后需要重新填写才能生成总结。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    await ApiKeyStore.delete();
    if (!mounted) return;
    setState(() {
      _keyExists = false;
      _replacingKey = false;
      _keyTip = null;
      _savedKey = null;
      _savedKeyVisible = false;
      _keyCtrl.clear();
    });
  }

  // ------------------------------------------------------------ 测试连接

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testOk = false;
      _testMsg = null;
    });
    try {
      // 契约顺序：先读落盘配置 → 工厂造 provider → 最小请求测连
      final cfg = await SettingsStore.loadAiConfig();
      if (!mounted) return;
      if (cfg.provider == AiProviderKind.openai &&
          cfg.baseUrl.trim().isEmpty) {
        setState(() {
          _testing = false;
          _testMsg = 'OpenAI 兼容模式必须先填写 Base URL';
        });
        return;
      }
      final key = await ApiKeyStore.read();
      if (!mounted) return;
      if (key == null || key.isEmpty) {
        setState(() {
          _testing = false;
          _testMsg = '请先填写并保存 API Key';
        });
        return;
      }
      // 阶段 0 的工厂会抛 AiException（D 轨交付后自然工作），catch 展示即可
      final provider = AiFactory.create(cfg, key);
      final receipt = await provider.testConnection();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        _testMsg = '连接成功：$receipt';
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testMsg = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testMsg = '测试失败：$e';
      });
    }
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    if (cfg == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle(context, Icons.auto_awesome_outlined, 'AI 配置'),
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(context, Icons.auto_awesome_outlined, 'AI 配置',
            subtitle: '地址 · Key · 模型 三件套，两种格式通用'),
        const SizedBox(height: 12),
        _providerCards(context, cfg),
        // ① API 地址（两种格式都常显：Anthropic 留空即官方，OpenAI 指官方或中转）
        const SizedBox(height: 12),
        _baseUrlField(cfg),
        // ② API Key
        const SizedBox(height: 16),
        _apiKeyBlock(context),
        // ③ 模型名称（自由文本，随格式切换给推荐默认）
        const SizedBox(height: 12),
        _modelField(cfg),
        const SizedBox(height: 12),
        // 显式保存（用户要求：填完 AI 配置要有明确的保存动作）
        FilledButton.icon(
          onPressed: _saveAll,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存配置'),
        ),
        if (_saveTip != null) ...[
          const SizedBox(height: 6),
          Text(
            _saveTip!,
            style: TextStyle(
              fontSize: 13,
              color: _saveTip == '已保存 ✓'
                  ? ShiguangColors.leafDark
                  : ShiguangColors.danger,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _testBlock(),
        const SizedBox(height: 16),
        _guardBlock(context, cfg),
      ],
    );
  }

  /// 服务商两卡单选：选中用叶绿描边 + 对勾，比 radio 圆点更贴手绘风。
  Widget _providerCards(BuildContext context, AiConfig cfg) {
    return Row(
      children: [
        Expanded(
          child: _providerCard(cfg, AiProviderKind.anthropic, 'Anthropic'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _providerCard(cfg, AiProviderKind.openai, 'OpenAI 兼容'),
        ),
      ],
    );
  }

  Widget _providerCard(
    AiConfig cfg,
    AiProviderKind kind,
    String title,
  ) {
    final selected = cfg.provider == kind;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selected ? null : () => _switchProvider(kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? ShiguangColors.leafDark
                  : ShiguangColors.wood.withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
            color: selected
                ? ShiguangColors.leafDark.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle,
                        size: 16, color: ShiguangColors.leafDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ① API 地址：两种格式统一常显。
  /// Anthropic 留空 = 官方端点（适配器兜底）；OpenAI 必填（官方或中转）。
  Widget _baseUrlField(AiConfig cfg) {
    final isAnthropic = cfg.provider == AiProviderKind.anthropic;
    return TextField(
      controller: _baseCtrl,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: 'API 地址',
        hintText: isAnthropic
            ? 'https://api.anthropic.com（留空即官方，也可填中转地址）'
            : 'https://api.openai.com/v1（必填，可填兼容中转）',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) => _save(cfg.copyWith(baseUrl: v.trim())),
    );
  }

  /// ③ 模型名称：统一为自由文本输入（不再分裂成「下拉+自定义」两段）。
  /// 占位提示列出该格式的常用 id；服务商切换时已自动落入该格式默认值。
  Widget _modelField(AiConfig cfg) {
    final presets = _modelPresetsFor(cfg.provider);
    final examples =
        presets.take(3).map((p) => p.$2).join(' / ');
    return TextField(
      controller: _modelCtrl,
      decoration: InputDecoration(
        labelText: '模型名称',
        hintText: '例如 $examples',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        final t = v.trim();
        if (t.isNotEmpty) _save(cfg.copyWith(model: t));
      },
    );
  }

  Widget _apiKeyBlock(BuildContext context) {
    final theme = Theme.of(context);
    final hasInput = !_keyExists || _replacingKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('API Key', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 8),
            if (_keyTip == '已保存 ✓')
              const Text(
                '已保存 ✓',
                style: TextStyle(
                  fontSize: 13,
                  color: ShiguangColors.leafDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasInput)
          Row(
            children: [
              const Icon(Icons.verified, size: 16,
                  color: ShiguangColors.leafDark),
              const SizedBox(width: 6),
              Expanded(
                // 保存后允许回显（用户要求）：默认遮蔽留末 4 位，眼睛开关切换明文
                child: Text(
                  _savedKeyVisible ? (_savedKey ?? '') : _maskKey(_savedKey),
                  style: TextStyle(
                    fontSize: 13,
                    color: ShiguangColors.leafDark.withValues(alpha: 0.9),
                  ),
                ),
              ),
              IconButton(
                tooltip: _savedKeyVisible ? '隐藏 Key' : '显示 Key',
                icon: Icon(
                  _savedKeyVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _savedKeyVisible = !_savedKeyVisible),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _replacingKey = true;
                  _keyTip = null;
                }),
                child: const Text('更换'),
              ),
              TextButton(
                onPressed: _clearKey,
                child: const Text('清除'),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyCtrl,
                  // 输入时默认遮蔽；眼睛开关可切明文（用户要求可展示）
                  obscureText: !_inputKeyVisible,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: _keyExists ? '输入新 Key 以替换旧值' : 'sk-… / tp-…（本地加密保存）',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: _inputKeyVisible ? '隐藏' : '显示',
                      icon: Icon(
                        _inputKeyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _inputKeyVisible = !_inputKeyVisible),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _savingKey ? null : _saveKey,
                child: Text(_savingKey ? '保存中…' : '保存'),
              ),
            ],
          ),
          if (_keyTip != null) ...[
            const SizedBox(height: 6),
            Text(
              _keyTip!,
              style: TextStyle(
                fontSize: 13,
                color: _keyTip == '已保存 ✓'
                    ? ShiguangColors.leafDark
                    : ShiguangColors.danger,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _testBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check, size: 18),
          label: Text(_testing ? '测试中…' : '测试连接'),
        ),
        if (_testMsg != null) ...[
          const SizedBox(height: 6),
          Text(
            _testMsg!,
            style: TextStyle(
              fontSize: 13,
              color: _testOk
                  ? ShiguangColors.leafDark
                  : ShiguangColors.danger,
            ),
          ),
        ],
      ],
    );
  }

  /// 成本护栏：每日送图上限 + 思考强度。
  Widget _guardBlock(BuildContext context, AiConfig cfg) {
    final theme = Theme.of(context);
    const efforts = ['low', 'medium', 'high'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('每日送图上限', style: theme.textTheme.bodyMedium),
            ),
            IconButton(
              tooltip: '减少',
              onPressed: cfg.maxImagesPerDay > 1
                  ? () => _save(cfg.copyWith(
                        maxImagesPerDay: cfg.maxImagesPerDay - 1,
                      ))
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '${cfg.maxImagesPerDay} 张',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: '增加',
              onPressed: cfg.maxImagesPerDay < 50
                  ? () => _save(cfg.copyWith(
                        maxImagesPerDay: cfg.maxImagesPerDay + 1,
                      ))
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text('思考强度 effort', style: theme.textTheme.bodyMedium),
            ),
            DropdownButton<String>(
              value: efforts.contains(cfg.effort) ? cfg.effort : 'low',
              items: const [
                DropdownMenuItem(value: 'low', child: Text('low · 轻量')),
                DropdownMenuItem(value: 'medium', child: Text('medium · 均衡')),
                DropdownMenuItem(value: 'high', child: Text('high · 深思')),
              ],
              onChanged: (v) {
                if (v == null) return;
                _save(cfg.copyWith(effort: v));
              },
            ),
          ],
        ),
      ],
    );
  }
}
