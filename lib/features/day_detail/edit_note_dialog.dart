/// 手写补记编辑对话框：没有照片的日子，也能用几行字留住这一天。
///
/// 与 AI 总结并存互不覆盖——这里只写 [ManualNote] 自己的记录，
/// 落库经 [onSave] 回调在对话框内完成：失败时错误显示在对话框里、不关闭，
/// 用户写的字不会因为一次磁盘错误而丢失。
///
/// 交互护栏（与 edit_summary_dialog 同一套）：
/// - `barrierDismissible: false`：点外面不关（写了一半误触丢失 + 写库中关窗两头防）；
/// - [PopScope]：有未保存修改时系统返回键先弹「放弃修改」二次确认；
/// - 正文 trim 后非空才允许保存，输入即清除旧错误提示。
///
/// 新建与编辑共用本对话框：[note] 为 null 即「从无到有写」，
/// 标题随之切换为「写手记 / 编辑手记」。
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';

/// 打开手记编辑对话框。
///
/// [dayKey] 一律取当前面板的日期；[note] 为 null 表示新建。
/// [onSave] 负责把手记落库（失败抛出，错误在对话框内展示）。
/// 返回 null = 取消/放弃修改；保存成功返回写入后的 [ManualNote]。
Future<ManualNote?> showEditNoteDialog(
  BuildContext context, {
  required int dayKey,
  ManualNote? note,
  required Future<void> Function(ManualNote note) onSave,
}) {
  return showDialog<ManualNote>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EditNoteDialog(dayKey: dayKey, note: note, onSave: onSave),
  );
}

class EditNoteDialog extends StatefulWidget {
  const EditNoteDialog({
    super.key,
    required this.dayKey,
    required this.onSave,
    this.note,
  });

  /// 目标日期主键 yyyymmdd（被编辑的 dayKey 一律来自日详情面板）。
  final int dayKey;

  /// 已有手记（null = 新建）。
  final ManualNote? note;

  /// 落库回调：保存时把组装好的 [ManualNote] 写进存储。
  final Future<void> Function(ManualNote note) onSave;

  @override
  State<EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<EditNoteDialog> {
  late final TextEditingController _body;
  bool _showError = false; // 校验失败（正文为空）
  bool _saving = false;
  String? _saveError; // 落库失败的行内提示

  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.note?.body ?? '');
    // 每次输入重建：脏判定、错误自动消除、保存中禁用都要跟着刷新
    _body.addListener(_onEdited);
  }

  void _onEdited() {
    if (!mounted) return;
    setState(() {
      if (_showError) _showError = false; // 开始输入即撤掉「不能为空」
    });
  }

  @override
  void dispose() {
    _body.removeListener(_onEdited);
    _body.dispose();
    super.dispose();
  }

  /// 有没有用户改动（与打开时的原文比）。
  /// 关闭拦截只认这个，不认「点了保存」——保存成功才关窗。
  bool get _dirty => _body.text != (widget.note?.body ?? '');

  /// 组装保存结果：新建/每次保存都刷新 updatedAtMs。
  ManualNote _buildResult() => ManualNote(
        dayKey: widget.dayKey,
        body: _body.text.trim(),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  /// 保存：校验 → 经回调落库 → 成功才关窗；失败留在窗内展示原因。
  Future<void> _save() async {
    if (_body.text.trim().isEmpty) {
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
        title: Text(widget.note == null ? '写手记' : '编辑手记'),
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
                  controller: _body,
                  decoration: InputDecoration(
                    labelText: '正文',
                    hintText: '写下这一天想记住的事…',
                    border: const OutlineInputBorder(),
                    errorText: _showError && _body.text.trim().isEmpty
                        ? '手记内容不能为空'
                        : null,
                  ),
                  minLines: 5,
                  maxLines: 10,
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
