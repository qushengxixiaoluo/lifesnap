/// AI 总结编辑对话框：生成的总结是草稿，不是定稿。
///
/// 用户在日详情的总结卡上点「编辑」即可改写标题、心情、正文、标签与瞬间。
/// 写库经 [onSave] 回调在对话框内完成：失败时错误显示在对话框里、不关闭，
/// 用户的修改不会因为一次磁盘错误而丢失。
///
/// 交互护栏：
/// - `barrierDismissible: false`：点外面不关（改了一半误触丢失 + 写库中关窗两头防）；
/// - [PopScope]：有未保存修改时系统返回键先弹「放弃修改」二次确认；
/// - 标题、正文必填，输入即清除旧错误提示。
///
/// 编辑只动内容字段：photo_sig / model / created_at 原样保留——
/// 失效判定只看照片集合变没变，人手改文案不该把总结标成「过期」。
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';

/// 打开编辑对话框。
///
/// [onSave] 负责把修改落库（失败抛出，错误在对话框内展示）。
/// 返回 null = 取消/放弃修改；保存成功返回写入后的 [AiSummary]。
Future<AiSummary?> showEditSummaryDialog(
  BuildContext context,
  AiSummary summary, {
  required Future<void> Function(AiSummary edited) onSave,
}) {
  return showDialog<AiSummary>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EditSummaryDialog(summary: summary, onSave: onSave),
  );
}

class EditSummaryDialog extends StatefulWidget {
  const EditSummaryDialog({
    super.key,
    required this.summary,
    required this.onSave,
  });

  final AiSummary summary;
  final Future<void> Function(AiSummary edited) onSave;

  @override
  State<EditSummaryDialog> createState() => _EditSummaryDialogState();
}

class _EditSummaryDialogState extends State<EditSummaryDialog> {
  late final TextEditingController _title;
  late final TextEditingController _narrative;
  late final TextEditingController _tags;
  late final TextEditingController _highlights;
  late String _mood;
  bool _showError = false; // 校验失败（标题/正文为空）
  bool _saving = false;
  String? _saveError; // 落库失败的行内提示

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.summary.title);
    _narrative = TextEditingController(text: widget.summary.narrative);
    _tags = TextEditingController(text: widget.summary.tags.join('、'));
    _highlights =
        TextEditingController(text: widget.summary.highlights.join('\n'));
    _mood = widget.summary.mood;
    // 每次输入重建：脏判定、错误自动消除、保存中禁用都要跟着刷新
    for (final c in [_title, _narrative, _tags, _highlights]) {
      c.addListener(_onEdited);
    }
  }

  void _onEdited() {
    if (!mounted) return;
    setState(() {
      if (_showError) _showError = false; // 开始输入即撤掉「不能为空」
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _narrative, _tags, _highlights]) {
      c.removeListener(_onEdited);
      c.dispose();
    }
    super.dispose();
  }

  /// 有没有用户改动（与打开时的原文逐字段比）。
  /// 关闭拦截只认这个，不认「点了保存」——保存成功才关窗。
  bool get _dirty =>
      _title.text != widget.summary.title ||
      _narrative.text != widget.summary.narrative ||
      _tags.text != widget.summary.tags.join('、') ||
      _highlights.text != widget.summary.highlights.join('\n') ||
      _mood != widget.summary.mood;

  /// 组装保存结果：只替换内容字段，指纹/模型/创建时间三者原样带回。
  AiSummary _buildResult() {
    final s = widget.summary;
    return AiSummary(
      dayKey: s.dayKey,
      title: _title.text.trim(),
      narrative: _narrative.text.trim(),
      tags: _splitTags(_tags.text),
      mood: _mood,
      highlights: _splitLines(_highlights.text),
      model: s.model,
      photoSig: s.photoSig,
      createdAtMs: s.createdAtMs,
    );
  }

  /// 标签分隔符宽容处理：中英文顿号、逗号、分号、换行都算分隔。
  static List<String> _splitTags(String raw) => raw
      .split(RegExp(r'[,，、;；\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 瞬间按行分隔（对话框里一项一行）。
  static List<String> _splitLines(String raw) => raw
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 保存：校验 → 经回调落库 → 成功才关窗；失败留在窗内展示原因。
  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _narrative.text.trim().isEmpty) {
      setState(() => _showError = true);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(_buildResult());
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '保存失败：$e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(_buildResult());
  }

  /// 有未保存修改时按返回：先问要不要放弃。
  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('还没保存的修改将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // 保存中也不许关：写库到一半被关窗会让「成功没成功」变成悬案
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        _confirmDiscard();
      },
      child: AlertDialog(
        title: const Text('编辑今日总结'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 落库失败提示放最上面：一出错立刻可见，不用滚
                if (_saveError != null) ...[
                  Text(
                    _saveError!,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: '标题',
                    hintText: '一句话概括这一天',
                    border: const OutlineInputBorder(),
                    errorText: _showError && _title.text.trim().isEmpty
                        ? '标题不能为空'
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _mood,
                  decoration: const InputDecoration(
                    labelText: '心情',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in AiSummary.moodIcons.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.value} ${e.key}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _mood = v ?? _mood),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _narrative,
                  decoration: InputDecoration(
                    labelText: '正文',
                    hintText: '这一天的故事…',
                    border: const OutlineInputBorder(),
                    errorText: _showError && _narrative.text.trim().isEmpty
                        ? '正文不能为空'
                        : null,
                  ),
                  minLines: 4,
                  maxLines: 8,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    hintText: '多个标签用、或,分隔',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _highlights,
                  decoration: const InputDecoration(
                    labelText: '瞬间（可选）',
                    hintText: '一项一行',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}
