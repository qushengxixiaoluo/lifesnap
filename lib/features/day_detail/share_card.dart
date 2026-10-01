/// 分享卡片导出：把某天的 AI 总结渲染成一张 750×1000 竖版图片并写到本地。
///
/// 渲染管线（[exportDayShareCard]）：
/// 1. 构造固定尺寸的 [ShareCard]（纯展示 widget，不依赖主题上下文之外的东西）；
/// 2. 经 OverlayEntry 挂到屏幕外（left: -20000）——不遮挡用户，但仍会参与
///    布局与绘制，RepaintBoundary 才有图层可截；
/// 3. 等两帧 + 数百毫秒，给 ThumbImage 异步生成首图留窗口
///    （图没赶上也不阻塞导出：占位纸色底照样成图）；
/// 4. RepaintBoundary.toImage(pixelRatio: 2) → PNG 字节；
/// 5. 平台分支落盘：io 写应用文档目录 / web Blob 下载（条件导入）。
///
/// 失败语义：任何一步抛错都会冒泡给调用方（日详情面板）展示「导出失败：…」，
/// OverlayEntry 保证在 finally 里摘除，不会在界面上留残影。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/app_style.dart';
import '../../core/models/models.dart';
import '../../core/thumbnails/thumb_image.dart';
import 'share_export_web.dart'
    if (dart.library.io) 'share_export_io.dart' as exporter;

/// 卡片逻辑尺寸：竖版 3:4，主流社交平台友好。
const double shareCardWidth = 750;
const double shareCardHeight = 1000;

/// 顶部首图区域高度（全宽；cover 裁切由 ThumbImage 内部保证）。
const double _photoHeight = 360;

/// 某日总结的分享卡（纯展示）。
///
/// 固定 750×1000：调用方负责用 SizedBox/Overlay 给足约束。
/// photoPath 为 null 时不占图片区（内容自然上移），仍可正常成图。
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.dayKey,
    required this.summary,
    this.photoPath,
  });

  /// 目标日期主键 yyyymmdd。
  final int dayKey;

  /// 当日 AI 总结（标题/心情/正文/标签/瞬间）。
  final AiSummary summary;

  /// 当日首图路径；null = 无图日（理论上按钮不会出现，纯渲染仍兜底）。
  final String? photoPath;

  String _dateLine() {
    // models.dart 只负责到「几月几日」，年份与星期在卡片侧补齐
    const names = [
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    ];
    final weekday = names[dayKeyToDateTime(dayKey).weekday - 1];
    return '${dayKey ~/ 10000}年${dayKeyToChinese(dayKey)} · $weekday';
  }

  @override
  Widget build(BuildContext context) {
    final ink = ShiguangColors.inkBrown;
    return Container(
      width: shareCardWidth,
      height: shareCardHeight,
      color: ShiguangColors.paper, // 水彩纸底：导出图不随 App 深浅皮肤变化
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photoPath != null)
                SizedBox(
                  width: shareCardWidth,
                  height: _photoHeight,
                  child: ColoredBox(
                    // contain 的留白用纸色打底，与卡片底一致不留黑边
                    color: ShiguangColors.paperDeep,
                    child: ThumbImage(
                      sourcePath: photoPath!,
                      size: 512, // 与照片网格同档；750 宽在 pixelRatio 2 下足够锐
                      // 完整展示当日首图，不做 cover 裁切——用户要能看见整张照片
                      fit: BoxFit.contain,
                      placeholderColor: ShiguangColors.paperDeep,
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    52,
                    photoPath != null ? 36 : 64,
                    52,
                    40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateLine(),
                        style: TextStyle(
                          fontSize: 26,
                          height: 1.3,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                          color: ShiguangColors.wood,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 新海诚式天气隐喻心情符，与详情页同源
                          Text(
                            summary.moodIcon,
                            style: const TextStyle(
                              fontSize: 38,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              summary.title,
                              style: TextStyle(
                                fontSize: 42,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 正文 + 标签 + 亮点整体进弹性区，从上往下排：
                      // OverflowBox 放行超高内容、ClipRect 在底边统一裁切——
                      // 不再用 Spacer 抢空间（那会让正文只拿到一半高度被裁），
                      // 也不会 RenderFlex 溢出报错。落款独立钉在卡片底部。
                      Expanded(
                        child: ClipRect(
                          child: OverflowBox(
                            maxHeight: double.infinity,
                            alignment: Alignment.topLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  summary.narrative,
                                  style: TextStyle(
                                    fontSize: 25,
                                    height: 1.65,
                                    color: ink.withValues(alpha: 0.92),
                                  ),
                                ),
                                if (summary.tags.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      for (final t in summary.tags)
                                        _tagChip(t),
                                    ],
                                  ),
                                ],
                                if (summary.highlights.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  for (final h in summary.highlights)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        '✨ $h',
                                        style: TextStyle(
                                          fontSize: 23,
                                          height: 1.4,
                                          color: ink.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          '拾光手册',
                          style: TextStyle(
                            fontSize: 21,
                            letterSpacing: 8,
                            color: ShiguangColors.wood.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 细描边内框：压在纸底与首图之上的手绘感边线（纯装饰，不吃手势）
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: ink.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: ShiguangColors.leafDark.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ShiguangColors.leafDark.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 20,
          color: ShiguangColors.leafDark,
        ),
      ),
    );
  }
}

/// 离屏渲染 [record] 的分享卡，返回 PNG 字节（1500×2000，pixelRatio 2）。
///
/// 返回 null 仅当当天没有总结（调用方本不该在无总结时发起导出）。
/// 渲染/编码失败抛错，由调用方转成行内提示。
Future<Uint8List?> renderShareCardPng(
  BuildContext context,
  DayRecord record,
) async {
  final summary = record.summary;
  if (summary == null) return null;
  final photoPath = record.photos.isEmpty ? null : record.photos.first.path;

  final overlay = Overlay.of(context);
  final boundaryKey = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // 挂到屏幕外：不挡用户，但照常布局与绘制（截图靠的是图层，不是可见）。
      // width/height 必须写死：不给的话 Positioned 只约束 left/top，
      // 卡片会被屏幕尺寸钳住（手机屏高 < 1000 是常态），正文弹性区塌缩、
      // 照片文字被挤出画布——真机「被卡掉一部分」的根因。
      left: -20000,
      top: 0,
      width: shareCardWidth,
      height: shareCardHeight,
      child: RepaintBoundary(
        key: boundaryKey,
        child: ShareCard(
          dayKey: record.dayKey,
          summary: summary,
          photoPath: photoPath,
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // 首图缩略图是异步生成的：给两段等待 + 两帧，让已就绪的字节画上去；
    // 没赶上就截占位底——图片加载失败绝不阻塞导出
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;

    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    // 渲染/编码失败必须抛错：return null 会被调用方误读成「当天没有总结」，
    // 把真正的故障报成一句不相干的文案（按钮本来就只在有总结时出现）
    if (boundary == null) {
      throw StateError('卡片尚未完成布局，稍后重试');
    }
    final image = await boundary.toImage(pixelRatio: 2); // 1500×2000 成图
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('卡片图像编码失败');
    }
    return byteData.buffer.asUint8List();
  } finally {
    entry.remove(); // 无论成败都摘掉离屏层，避免残影与图层泄漏
  }
}

/// 离屏渲染并落盘为文件（「保存为文件」动作 / 桌面兜底），返回路径。
///
/// 返回 null 仅当当天没有总结；其余失败一律抛错。
Future<String?> exportDayShareCard(
  BuildContext context,
  DayRecord record,
) async {
  final bytes = await renderShareCardPng(context, record);
  if (bytes == null) return null;
  return exporter.saveShareCardPng(bytes, record.dayKey);
}
