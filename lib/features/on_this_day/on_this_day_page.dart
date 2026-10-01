/// 那年今日页：往年今天（1–10 年前）的照片与总结回顾。
///
/// 契约：公开类 [OnThisDayPage]、无参 const 构造——router.dart 依赖此签名。
/// 数据全部来自 [onThisDayEntriesProvider]（本页专属 autoDispose FutureProvider），
/// 点击卡片经 [showDayDetail] 进入日详情，与地图页同一套详情入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_style.dart';
import '../../core/models/models.dart';
import '../../core/thumbnails/thumb_image.dart';
import '../../widgets/hand_card.dart';
import '../day_detail/day_detail_launcher.dart';
import 'on_this_day_provider.dart';

class OnThisDayPage extends ConsumerWidget {
  const OnThisDayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(onThisDayEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('那年今日')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          // 存储打不开之类的错误只给中文提示，细节留在控制台
          message: '加载失败，请重试',
          onRetry: () => ref.invalidate(onThisDayEntriesProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('往年的今天还没有记录'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _EntryCard(entry: entries[index]),
          );
        },
      ),
    );
  }
}

/// 加载失败态：中文文案 + 重试（与设置页等处的错误风格一致）。
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 单条「N 年前」的回顾卡片。
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final OnThisDayEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 例：「1 年前 · 2025年9月29日」——dayKeyToChinese 只到月日，年份由 dayKey 补
    final dateLine =
        '${entry.yearsAgo} 年前 · ${entry.dayKey ~/ 10000}年'
        '${dayKeyToChinese(entry.dayKey)}';

    return Semantics(
      button: true,
      label: '$dateLine，${entry.title}',
      child: HandCard(
        onTap: () => showDayDetail(context, entry.dayKey),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _thumb(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateLine, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    entry.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text('${entry.photoCount} 张照片',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  /// 有照片用缩略图，纯总结/手记日给一枚占位图标（ThumbImage 需要真实源路径）。
  Widget _thumb() {
    final path = entry.thumbPath;
    if (path == null) {
      return const SizedBox(
        width: 56,
        height: 56,
        child: ColoredBox(
          color: ShiguangColors.paperDeep,
          child: Center(child: Icon(Icons.history, size: 24)),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: ThumbImage(
          sourcePath: path,
          size: 128,
          placeholderColor: ShiguangColors.paperDeep,
        ),
      ),
    );
  }
}
