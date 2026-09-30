/// 全屏照片查看器：详情网格点开 → 黑底大图（1280 档）+ 双指缩放/拖动。
///
/// 交互取舍：
/// - 用 showDialog 而不是新路由页：点遮罩即关（barrierDismissible 默认开），
///   返回键/左上角关闭按钮同样可用，不打断底部详情面板的栈；
/// - InteractiveViewer 内的图以「屏内适配」为初始约束，放大后可平移，
///   双击暂不做（要双击定点缩放需要捕捉点击位置，后续有需要再加）。
library;

import 'package:flutter/material.dart';

import '../../core/thumbnails/thumb_image.dart';

/// 全屏查看 [sourcePath] 的照片。
void showPhotoViewer(BuildContext context, String sourcePath) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (_) => PhotoViewerPage(sourcePath: sourcePath),
  );
}

class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 主体：缩放到 1280 档，初始约束限制在屏内（fit 进屏幕），可放大 6 倍
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screen.width,
                maxHeight: screen.height,
              ),
              child: InteractiveViewer(
                maxScale: 6,
                minScale: 1,
                clipBehavior: Clip.none,
                child: ThumbImage(
                  sourcePath: sourcePath,
                  size: 1280,
                  placeholderColor: const Color(0xFF1A2138),
                ),
              ),
            ),
          ),
          // 左上角关闭
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            child: IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          // 底部操作提示
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            left: 0,
            right: 0,
            child: Text(
              '双指缩放 · 拖动查看 · 点击外侧关闭',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
