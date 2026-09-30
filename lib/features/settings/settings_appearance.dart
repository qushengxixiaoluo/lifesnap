/// 设置页 · 外观与关于分区（E 轨）。
///
/// 两行选择器（画风是独立于天色的第二根轴，不是第四个天色值）：
/// - 「画风」行：糖果手绘 / 油墨旧纸 两张卡（存 ArtStyleNotifier，键 artMode）；
/// - 「天色」行：日光 / 黄昏 / 星夜 三张卡（存 AppStyleNotifier，键 skinMode，逻辑不动）。
/// 两行都双监听（ValueListenable + Listenable）即时预览——预览渐变一律走
/// art 感知的 tokensFor，所以任何一张卡画的都是「该组合真实会长成的样子」。
/// 另有 关于块（缩略图缓存占用 / 一键清理）。
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

  static const _artNames = <ArtStyle, String>{
    ArtStyle.candy: '糖果手绘',
    ArtStyle.agedInk: '油墨旧纸',
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
        // —— 画风行（第二根轴）——
        // 双监听：画风变了要重排选中态，天色变了卡片预览渐变也要跟着换。
        ListenableBuilder(
          listenable: ArtStyleNotifier.current,
          builder: (context, _) {
            final artCurrent = ArtStyleNotifier.current.value;
            return ValueListenableBuilder<AppStyle>(
              valueListenable: AppStyleNotifier.current,
              builder: (context, time, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('画风', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final a in ArtStyle.values) ...[
                          if (a != ArtStyle.candy) const SizedBox(width: 8),
                          Expanded(child: _artCard(a, artCurrent, time)),
                        ],
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 16),
        // —— 天色行（原有三档，逻辑不动，只把预览改为 art 感知）——
        ValueListenableBuilder<AppStyle>(
          valueListenable: AppStyleNotifier.current,
          builder: (context, time, _) {
            return ListenableBuilder(
              listenable: ArtStyleNotifier.current,
              builder: (context, _) {
                final artCurrent = ArtStyleNotifier.current.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('天色', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final s in AppStyle.values) ...[
                          if (s != AppStyle.dayLight) const SizedBox(width: 8),
                          Expanded(child: _styleCard(s, time, artCurrent)),
                        ],
                      ],
                    ),
                  ],
                );
              },
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

  /// 画风卡：预览画的是「当前天色 × 本卡画风」的真实渐变——
  /// 两张卡并排就是同一天色下两种画风的直接对照。
  Widget _artCard(ArtStyle art, ArtStyle current, AppStyle time) {
    final selected = current == art;
    final sky = tokensFor(time, art);
    return _skinCard(
      selected: selected,
      sky: sky,
      label: _artNames[art] ?? art.name,
      labelColor: _labelColor(time, art),
      labelShadow: _labelShadow(time, art),
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        // 保存会同时更新 ArtStyleNotifier.current → 根级主题立即切换
        await ArtStyleNotifier.save(prefs, art);
      },
    );
  }

  /// 天色卡：预览画的是「本卡天色 × 当前画风」的真实渐变
  /// （tokensFor 显式传画风，切到旧纸后三张卡自动变成三张旧纸）。
  Widget _styleCard(AppStyle style, AppStyle current, ArtStyle art) {
    final selected = current == style;
    final sky = tokensFor(style, art);
    return _skinCard(
      selected: selected,
      sky: sky,
      label: _styleNames[style] ?? style.name,
      labelColor: _labelColor(style, art),
      labelShadow: _labelShadow(style, art),
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        // 保存会同时更新 AppStyleNotifier.current → 根级主题立即切换
        await AppStyleNotifier.save(prefs, style);
      },
    );
  }

  /// 卡片文字色：糖果沿用「白字 + 墨影」的既有观感；
  /// 旧纸卡按画风取墨字/淡纸字，压在自己的渐变上更像印在纸上。
  Color _labelColor(AppStyle time, ArtStyle art) => art == ArtStyle.agedInk
      ? textColorFor(time, art)
      : ShiguangColors.starWhite;

  /// 卡片文字影：与文字色反相——浅纸上压白影、暗纸上压墨影，任何渐变都读得清。
  Color _labelShadow(AppStyle time, ArtStyle art) {
    if (art != ArtStyle.agedInk) return ShiguangColors.inkBrown;
    return time == AppStyle.night
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.9);
  }

  /// 皮肤卡本体（画风/天色两行共用）：渐变预览 + 选中金框 + 金勾。
  Widget _skinCard({
    required bool selected,
    required SkyTokens sky,
    required String label,
    required Color labelColor,
    required Color labelShadow,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
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
                  label,
                  textAlign: TextAlign.center,
                  // 渐变从亮到浅，字压一层反相投影才读得清
                  style: TextStyle(
                    color: labelColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    shadows: [
                      Shadow(
                        color: labelShadow,
                        blurRadius: 4,
                        offset: const Offset(0, 1),
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
