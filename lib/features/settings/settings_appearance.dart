/// 设置页 · 外观与关于分区（E 轨）。
///
/// 三套皮肤卡片（AppStyleNotifier 换肤，根级 ValueListenable 会整树重建，
/// 这里无需自己 setState）+ 关于块（缩略图缓存占用 / 一键清理）。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_style.dart';
import '../../core/thumbnails/thumb_cache.dart';
import 'settings_utils.dart';

class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  static const _styleNames = <AppStyle, String>{
    AppStyle.dayLight: '日光',
    AppStyle.sunset: '黄昏',
    AppStyle.night: '星夜',
  };

  int? _cacheBytes; // null = 还在读
  String? _tip;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await ThumbCache.sizeBytes();
    if (!mounted) return;
    setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    final freed = await ThumbCache.clearAll();
    if (!mounted) return;
    await _loadCacheSize();
    if (!mounted) return;
    setState(() => _tip = '已清理 ${formatBytes(freed)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(context, Icons.palette_outlined, '外观',
            subtitle: '天空的颜色，由你决定'),
        const SizedBox(height: 12),
        // 换肤状态挂在全局 ValueNotifier 上：这里只读它做选中高亮
        ValueListenableBuilder<AppStyle>(
          valueListenable: AppStyleNotifier.current,
          builder: (context, current, _) {
            return Row(
              children: [
                for (final s in AppStyle.values) ...[
                  if (s != AppStyle.dayLight) const SizedBox(width: 8),
                  Expanded(
                    child: _styleCard(s, current),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text('关于', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('缩略图缓存', style: theme.textTheme.bodySmall),
                  Text(
                    _cacheBytes == null ? '读取中…' : formatBytes(_cacheBytes!),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: _cacheBytes == null ? null : _clearCache,
              child: const Text('清理缓存'),
            ),
          ],
        ),
        if (_tip != null) ...[
          const SizedBox(height: 6),
          Text(_tip!,
              style: const TextStyle(
                  fontSize: 13, color: ShiguangColors.leafDark)),
        ],
      ],
    );
  }

  Widget _styleCard(AppStyle style, AppStyle current) {
    final selected = current == style;
    final sky = skyOf(style);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final prefs = await SharedPreferences.getInstance();
          // 保存会同时更新 AppStyleNotifier.current → 根级主题立即切换
          await AppStyleNotifier.save(prefs, style);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? ShiguangColors.completedGold
                  : ShiguangColors.wood.withValues(alpha: 0.5),
              width: selected ? 2.5 : 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [sky.top, sky.mid, sky.horizon],
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: ShiguangColors.completedGold
                          .withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Text(
                  _styleNames[style] ?? style.name,
                  textAlign: TextAlign.center,
                  // 渐变从亮到浅，白字压深色投影才读得清
                  style: const TextStyle(
                    color: ShiguangColors.starWhite,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    shadows: [
                      Shadow(
                        color: ShiguangColors.inkBrown,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: ShiguangColors.completedGold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
