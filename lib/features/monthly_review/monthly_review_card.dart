/// 月度回顾结果卡：标题 + 正文 + 主题标签 chips + 亮点列表。
///
/// 展示结构参考日详情的总结卡（day_detail_sheet._summaryCard），
/// 但独立成组件，避免设置页与日详情互相牵连。
library;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import '../../core/models/models.dart';

class MonthlyReviewCard extends StatelessWidget {
  const MonthlyReviewCard({super.key, required this.review});

  final MonthlyReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShiguangColors.leafDark.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ShiguangColors.leafDark.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🗓', style: TextStyle(fontSize: 18, height: 1.2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${review.year} 年 ${review.month} 月',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(review.narrative, style: theme.textTheme.bodyMedium),
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in review.tags) _tagChip(t)],
            ),
          ],
          if (review.highlights.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final h in review.highlights)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 15, color: ShiguangColors.completedGold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(h,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 主题标签 chips（样式沿日总结卡的 _tagChip）。
  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ShiguangColors.leafDark.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ShiguangColors.leafDark.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 12,
          color: ShiguangColors.leafDark,
        ),
      ),
    );
  }
}
