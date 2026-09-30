/// 设置页 · 批量生成分区。
///
/// 两个入口都跑在全局 [batchServiceProvider] 里（任务不属于本页面）：
/// - 「补全所有缺失总结」：全库有照片但没有 AI 总结的日子，从早到晚跑到底；
/// - 「生成本月全部总结」：只补所选月份（沿用原入口）。
/// 退出本页面/切后台任务照跑；中途杀掉 App，下次启动 main 的
/// _BatchAutoResume 钩子自动续跑（进度与失败明细都持久化）。
/// 本组件只 watch 服务状态做展示 + 单天重试的本地 UI 态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_style.dart';
import '../../app/batch_service.dart';
import '../../app/providers.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/models/models.dart';
import 'settings_utils.dart';

class BatchSection extends ConsumerStatefulWidget {
  const BatchSection({super.key});

  @override
  ConsumerState<BatchSection> createState() => _BatchSectionState();
}

class _BatchSectionState extends ConsumerState<BatchSection> {
  late int _year;
  late int _month;

  /// 上次点的是「单月」还是「全部」——空队列完成时的文案要分场合。
  bool _lastWasMonth = true;

  // 单天重试的本地 UI 态（任务态在 batchServiceProvider 里）
  final _retrying = <int>{};
  final _retryError = <int, String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  Future<void> _retryDay(int dayKey) async {
    setState(() {
      _retrying.add(dayKey);
      _retryError.remove(dayKey);
    });
    try {
      await ref.read(batchServiceProvider.notifier).retryDay(dayKey);
      if (!mounted) return;
      setState(() => _retrying.remove(dayKey));
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _retrying.remove(dayKey);
        _retryError[dayKey] = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _retrying.remove(dayKey);
        _retryError[dayKey] = '重试失败：$e';
      });
    }
  }

  /// 年份下拉的动态区间：库里最早照片的年份 → 当前年。
  /// 库里没照片时退回「当前年起往前推 4 年」的滚动窗口。
  List<int> _yearOptions() {
    final now = DateTime.now().year;
    final dayIndex = ref.watch(photoStoreProvider).value?.dayIndex;
    int? minYear;
    if (dayIndex != null) {
      for (final dayKey in dayIndex.keys) {
        final y = dayKey ~/ 10000;
        if (minYear == null || y < minYear) minYear = y;
      }
    }
    final from = minYear ?? now - 4;
    final years = <int>[
      for (var y = (minYear != null && minYear > now ? minYear : now);
          y >= from;
          y--)
        y,
    ];
    // DropdownButton 断言 value 必须有对应 item（测试可注入任意年），缺了会崩
    if (!years.contains(_year)) years.add(_year);
    return years;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = _yearOptions();
    final job = ref.watch(batchServiceProvider);
    final notifier = ref.read(batchServiceProvider.notifier);
    final running = job.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(context, Icons.calendar_month_outlined, '批量生成',
            subtitle: '补全所有有照片、缺 AI 总结的日子'),
        const SizedBox(height: 12),

        // —— 主入口：全库从头补到尾 ——
        FilledButton.icon(
          onPressed: running
              ? null
              : () {
                  _lastWasMonth = false;
                  notifier.startAll();
                },
          icon: running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(running ? '生成中…' : '补全所有缺失总结'),
        ),

        // —— 次入口：单月（保留原按钮文案，测试与老用户习惯都认它）——
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _year,
                items: [
                  for (final y in years)
                    DropdownMenuItem(value: y, child: Text('$y 年')),
                ],
                onChanged:
                    running ? null : (v) => setState(() => _year = v ?? _year),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _month,
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(value: m, child: Text('$m 月')),
                ],
                onChanged: running
                    ? null
                    : (v) => setState(() => _month = v ?? _month),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: running
              ? null
              : () {
                  _lastWasMonth = true;
                  notifier.startMonth(_year, _month);
                },
          icon: const Icon(Icons.event_note_outlined, size: 18),
          label: const Text('生成本月全部总结'),
        ),

        // —— 运行控制与残队提示 ——
        if (running) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: notifier.requestStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('停止（当前天跑完即收工，进度已保留）'),
            ),
          ),
        ] else if (job.hasPending) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: notifier.resumeIfPending,
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: Text('继续上次未完成（剩 ${job.total - job.done} 天）'),
            ),
          ),
        ],

        if (job.abortedReason != null) ...[
          const SizedBox(height: 8),
          Text(
            '任务中止：${job.abortedReason}（队列已保留，修好后重开应用或点上方继续）',
            style: const TextStyle(color: ShiguangColors.danger, fontSize: 13),
          ),
        ],

        ..._progressBlock(theme, job),
      ],
    );
  }

  List<Widget> _progressBlock(ThemeData theme, BatchJobState job) {
    if (!job.running && !job.finished && job.failedDays.isEmpty) {
      return const [];
    }
    final total = job.done + job.failed;
    final out = <Widget>[
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: job.total == 0 ? null : total / job.total,
        minHeight: 6,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 6),
      Text(
        job.total == 0
            ? (_lastWasMonth ? '本月没有需要生成的总结' : '没有缺失的总结，全部已补齐')
            : '进度 ${job.done}/${job.total}${job.failed > 0 ? ' · 失败 ${job.failed}' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      if (job.running && job.currentDayKey != 0)
        Text(
          '正在处理 ${dayKeyToChinese(job.currentDayKey)}',
          style: theme.textTheme.bodySmall,
        ),
      if (job.finished && job.total > 0 && job.failed == 0)
        Text(
          '全部生成完成 ✓',
          style: theme.textTheme.bodySmall?.copyWith(
            color: ShiguangColors.leafDark,
            fontWeight: FontWeight.w700,
          ),
        ),
    ];
    for (final dayKey in job.failedDays) {
      out.addAll([
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                '${dayKeyToChinese(dayKey)} 生成失败',
                style: const TextStyle(
                  fontSize: 13,
                  color: ShiguangColors.danger,
                ),
              ),
            ),
            if (_retryError[dayKey] != null)
              Flexible(
                child: Text(
                  _retryError[dayKey]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: ShiguangColors.danger),
                ),
              ),
            TextButton(
              onPressed:
                  _retrying.contains(dayKey) ? null : () => _retryDay(dayKey),
              child: Text(_retrying.contains(dayKey) ? '重试中…' : '重试'),
            ),
          ],
        ),
      ]);
    }
    return out;
  }
}
