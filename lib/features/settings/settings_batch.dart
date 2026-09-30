/// 设置页 · 批量生成分区（E 轨）。
///
/// 选月份 → 「生成本月全部总结」→ generateMonth 进度流（x/N）→
/// 失败天列表，逐天可重试。
///
/// 失败天怎么推断：MonthBatchProgress 只带聚合计数（total/done/failed）
/// 和「当前处理日」，没有失败明细，所以 failed 计数涨一格时，
/// 就把那一刻的 currentDayKey 记为失败日——这是流里能拿到的最接近信息。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_style.dart';
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
  bool _running = false;
  MonthBatchProgress? _progress;
  String? _error;
  final _failed = <int>[]; // 推断出的失败日 dayKey
  final _retrying = <int>{};
  final _retryError = <int, String>{};
  StreamSubscription<MonthBatchProgress>? _sub;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year; // 默认当月：多数人是补当月的漏
    _month = now.month;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    _sub?.cancel();
    setState(() {
      _running = true;
      _progress = null;
      _error = null;
      _failed.clear();
      _retryError.clear();
    });
    var prevFailed = 0;
    _sub = ref
        .read(summaryRepositoryProvider)
        .generateMonth(year: _year, month: _month)
        .listen(
      (p) {
        if (!mounted) return;
        if (p.failed > prevFailed) {
          prevFailed = p.failed;
          if (p.currentDayKey != 0 && !_failed.contains(p.currentDayKey)) {
            _failed.add(p.currentDayKey);
          }
        }
        setState(() {
          _progress = p;
          if (p.finished) _running = false;
        });
        if (p.finished) _sub?.cancel();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error = e is AiException ? e.message : '批量生成失败：$e';
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _running = false);
      },
    );
  }

  /// 单天重试：自己组 DayRecord 再调 generate(force:true)。
  /// 不整月重跑——重跑会把已成功的天再过一遍，浪费请求。
  Future<void> _retryDay(int dayKey) async {
    final store = ref.read(photoStoreProvider).value;
    if (store == null) return;
    final repo = ref.read(summaryRepositoryProvider);
    setState(() {
      _retrying.add(dayKey);
      _retryError.remove(dayKey);
    });
    try {
      final photos = await store.photosOfDay(dayKey);
      final summary = await store.summaryOf(dayKey);
      final record = DayRecord(
        dayKey: dayKey,
        photos: photos,
        summary: summary,
        summaryStale: summary != null &&
            summary.photoSig != computePhotoSig(photos),
      );
      await repo.generate(record: record, force: true);
      if (!mounted) return;
      setState(() {
        _failed.remove(dayKey);
        _retrying.remove(dayKey);
      });
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
  ///
  /// 不能写死固定几年（如 [2024..2028]）：那样 2023 及更早的照片永远
  /// 没法批量补总结，2029 年起又只剩兜底分支。改为从 dayIndex 的
  /// dayKey（yyyymmdd，高四位即年份）反推最早年份，跨年后自动延展。
  ///
  /// 库里还没照片（或 store 仍在加载）时退回「当前年起往前推 4 年」的
  /// 窗口——同样随系统时间滚动，不会像写死列表那样过期。
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
    // 降序排列：最常用的当前年排最上，老照片年份往下滑
    final years = <int>[
      for (var y = (minYear != null && minYear > now ? minYear : now);
          y >= from;
          y--)
        y,
    ];
    // 当前选中年不在区间内也补回去：DropdownButton 断言 value 必须有对应
    // item（测试里可注入任意年），缺了会直接崩。
    if (!years.contains(_year)) years.add(_year);
    return years;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = _yearOptions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(context, Icons.calendar_month_outlined, '批量生成',
            subtitle: '给整个月份补齐缺失的 AI 总结'),
        const SizedBox(height: 12),
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
                onChanged: _running
                    ? null
                    : (v) => setState(() => _year = v ?? _year),
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
                onChanged: _running
                    ? null
                    : (v) => setState(() => _month = v ?? _month),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _running ? null : _start,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(_running ? '生成中…' : '生成本月全部总结'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style:
                  const TextStyle(color: ShiguangColors.danger, fontSize: 13)),
        ],
        ..._progressBlock(theme),
      ],
    );
  }

  List<Widget> _progressBlock(ThemeData theme) {
    final p = _progress;
    if (p == null) return const [];
    final total = p.done + p.failed;
    final out = <Widget>[
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: p.total == 0 ? null : total / p.total,
        minHeight: 6,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 6),
      Text(
        p.total == 0
            ? '本月没有需要生成的总结'
            : '进度 ${p.done}/${p.total}${p.failed > 0 ? ' · 失败 ${p.failed}' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      if (!p.finished && p.currentDayKey != 0)
        Text(
          '正在处理 ${dayKeyToChinese(p.currentDayKey)}',
          style: theme.textTheme.bodySmall,
        ),
    ];
    for (final dayKey in _failed) {
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
              onPressed: _retrying.contains(dayKey)
                  ? null
                  : () => _retryDay(dayKey),
              child: Text(_retrying.contains(dayKey) ? '重试中…' : '重试'),
            ),
          ],
        ),
      ]);
    }
    return out;
  }
}
