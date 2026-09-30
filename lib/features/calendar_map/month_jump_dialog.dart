/// 月份跳转对话框：点地图头部的月份标题弹出，选好年月一步到位。
///
/// 交互取舍：
/// - 年份用 ‹ 2026 › 左右步进（地图范围 2000-2099，比滚轮快）；
/// - 12 个月按钮点一下立即返回 (year, month)，不设「确认」二次点击——
///   选月是高频轻操作，多按一次确认纯属多余；
/// - 关闭：点遮罩/取消按钮，返回 null（调用方不动当前月）。
library;

import 'package:flutter/material.dart';

import 'map_providers.dart';

class MonthJumpDialog extends StatefulWidget {
  const MonthJumpDialog({super.key, required this.initialYear});

  /// 打开时预选的年份（当前正在看的月份所在年）。
  final int initialYear;

  /// 弹出并返回选中的 (year, month)；取消返回 null。
  static Future<(int, int)?> show(BuildContext context, {required int initialYear}) {
    return showDialog<(int, int)>(
      context: context,
      builder: (_) => MonthJumpDialog(initialYear: initialYear),
    );
  }

  @override
  State<MonthJumpDialog> createState() => _MonthJumpDialogState();
}

class _MonthJumpDialogState extends State<MonthJumpDialog> {
  late int _year = widget.initialYear.clamp(kMapStartYear, kMapEndYear);

  void _stepYear(int delta) {
    final next = _year + delta;
    if (next < kMapStartYear || next > kMapEndYear) return;
    setState(() => _year = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('跳转到月份', textAlign: TextAlign.center),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // —— 年份步进 ——
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一年',
                  icon: const Icon(Icons.chevron_left),
                  onPressed:
                      _year > kMapStartYear ? () => _stepYear(-1) : null,
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '$_year 年',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      // 必须用 onSurface 随主题走：写死 inkBrown（深棕）在
                      // 星夜的近黑对话框底上几乎不可见（用户反馈「黄色太浅」）
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      _year < kMapEndYear ? () => _stepYear(1) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // —— 12 个月：4×3 糖果按钮网格，点了即返回 ——
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.35,
              children: [
                for (var m = 1; m <= 12; m++)
                  _monthButton(m),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _monthButton(int month) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () => Navigator.of(context).pop((_year, month)),
      child: Text('$month 月'),
    );
  }
}
