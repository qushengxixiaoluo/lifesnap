/// 那年今日 · 数据层
///
/// 候选日 = 往年同月同日，从 1 年前往上翻、最多 10 年；
/// 只把「有实质记录」的日子交给 UI（photoCount>0 || 有总结 || 有手记）。
/// 全局服务一律从 `app/providers.dart` 取（阶段 0 约束：各轨不 new 服务实例）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models/models.dart';

/// 一条「往年今日」的回顾记录（已过滤掉无记录的候选年）。
class OnThisDayEntry {
  /// 距今几年（1..10，1 = 去年今天）。
  final int yearsAgo;

  /// 候选日日期主键 yyyymmdd。
  final int dayKey;

  /// 当日照片数（0 = 纯总结/纯手记日）。
  final int photoCount;

  /// 当日首张缩略图源路径（无照片时为 null，UI 走占位图标）。
  final String? thumbPath;

  /// 卡片标题：AI 总结标题 → 手记正文首行 → 「N 张照片」。
  final String title;

  const OnThisDayEntry({
    required this.yearsAgo,
    required this.dayKey,
    required this.photoCount,
    required this.thumbPath,
    required this.title,
  });
}

/// 那年今日的全部有效记录，按 yearsAgo 升序（最近的年份在上）。
///
/// autoDispose：翻走即释放，翻回来重查——扫描补完照片后回到本页能看到新记录。
final onThisDayEntriesProvider =
    FutureProvider.autoDispose<List<OnThisDayEntry>>((ref) async {
  // store 打不开时错误向上抛，页面给中文重试。
  final store = await ref.watch(photoStoreProvider.future);

  final now = DateTime.now();
  final entries = <OnThisDayEntry>[];
  for (var yearsAgo = 1; yearsAgo <= 10; yearsAgo++) {
    // 2月29日只在闰年有对应日：非闰年的 DateTime 构造会归一到 3月1日，
    // 用「月日没被归一」当有效性检查，不成立就跳过该年。
    final day = DateTime(now.year - yearsAgo, now.month, now.day);
    if (day.month != now.month || day.day != now.day) continue;

    final dayKey = dayKeyOf(day);
    final meta = store.dayIndex[dayKey];
    final photoCount = meta?.photoCount ?? 0;

    // hasSummary/hasNote 以 dayIndex 标志为准，但补一次回读兜底：
    // 阶段 0 内存实现的 dayIndex 只从照片与手记聚合，「只有总结」的日子
    // 进不了索引（同 map_providers 的兜底理由）；真实实现已回填时这只是两次快查。
    var hasSummary = meta?.hasSummary ?? false;
    var hasNote = meta?.hasNote ?? false;
    if (!hasSummary) hasSummary = await store.summaryOf(dayKey) != null;
    if (!hasNote) hasNote = await store.noteOf(dayKey) != null;
    if (photoCount == 0 && !hasSummary && !hasNote) continue;

    final summary = hasSummary ? await store.summaryOf(dayKey) : null;
    final note = hasNote ? await store.noteOf(dayKey) : null;
    entries.add(OnThisDayEntry(
      yearsAgo: yearsAgo,
      dayKey: dayKey,
      photoCount: photoCount,
      thumbPath: meta?.thumbPath,
      title: _titleOf(summary, note, photoCount),
    ));
  }
  return entries;
});

/// 卡片标题优先级：AI 总结标题 → 手记正文首行 → 「N 张照片」。
///
/// 总结标题理论上非空，但已被用户编辑过就可能清掉，空串落到下一级。
String _titleOf(AiSummary? summary, ManualNote? note, int photoCount) {
  final summaryTitle = summary?.title.trim() ?? '';
  if (summaryTitle.isNotEmpty) return summaryTitle;

  if (note != null) {
    final firstLine = note.body
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) return firstLine;
  }
  return '$photoCount 张照片';
}
