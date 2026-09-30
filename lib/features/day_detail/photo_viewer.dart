/// 全屏照片查看器：黑底原图级显示 + 双指缩放 + 删除入口。
///
/// 「原图流式加载」策略（用户拍板的清晰度方案）：
/// - 占位先上：1280 档缩略图即时可见，不等原图；
/// - 本地文件：读原图字节 → dart:ui 按「屏幕物理宽度」**降采样解码**
///   （不是整图解码——8000px 原图全量进内存会炸，降采样后既清晰又可控）；
/// - 相册资产：photo_manager 的 originBytes 原图接口（老毛病 thumbnailData
///   是系统小图，放大必糊，已在生成链一并更换）；
/// - Web 拿不到原始字节 → 停留在占位缩略图（诚实降级，不假装原图）。
///
/// 删除：右上角垃圾桶 → 确认后从索引移除（**不碰系统相册/磁盘原文件**），
/// 返回 true 让详情面板重载记录。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/thumbnails/original_loader.dart';
import '../../core/thumbnails/thumb_image.dart';

/// 全屏查看照片；返回 true 表示用户删除了这张（调用方应重载数据）。
Future<bool?> showPhotoViewer(BuildContext context, String sourcePath) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => PhotoViewerPage(sourcePath: sourcePath),
  );
}

class PhotoViewerPage extends ConsumerStatefulWidget {
  const PhotoViewerPage({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  ConsumerState<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends ConsumerState<PhotoViewerPage> {
  ui.Image? _image; // 降采样解码后的原图（就绪前显示 1280 占位）
  bool _loading = true;
  bool _loadFailed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadOriginal();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadOriginal() async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logicalW = MediaQuery.sizeOf(context).width;
    // 目标解码宽度 = 屏幕物理宽度（1:1 像素），再封 4096 防极端大屏爆内存
    final targetPx = (logicalW * dpr).round().clamp(720, 4096);

    Uint8List? bytes;
    try {
      bytes = await loadOriginalBytes(widget.sourcePath);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
      return;
    }
    try {
      // 降采样解码：targetWidth 只在源图更宽时缩，不放大（Skia 语义）
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetPx,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('从记录中移除这张照片？'),
        content: const Text('只从拾光手册的这一天里移除，不会删除系统相册或磁盘里的原文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final store = await ref.read(photoStoreProvider.future);
    await store.removePhotos([widget.sourcePath]);
    if (!mounted) return;
    Navigator.of(context).pop(true); // 关查看器并通知详情面板重载
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final img = _image;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screen.width,
                maxHeight: screen.height,
              ),
              child: img != null
                  ? InteractiveViewer(
                      maxScale: 8,
                      minScale: 1,
                      clipBehavior: Clip.none,
                      child: AspectRatio(
                        aspectRatio: img.width / img.height,
                        child: RawImage(image: img, fit: BoxFit.contain),
                      ),
                    )
                  // 占位：1280 档缩略图（原图解码完成前闪一下，不挡交互）
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        ThumbImage(
                          sourcePath: widget.sourcePath,
                          size: 1280,
                          placeholderColor: const Color(0xFF1A2138),
                        ),
                        if (_loading)
                          CircularProgressIndicator(
                            color: Colors.white.withValues(alpha: 0.72),
                            strokeWidth: 2.5,
                          ),
                      ],
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
          // 右上角删除（从记录移除）
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: IconButton(
              tooltip: '从记录中移除',
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 26),
              onPressed: _confirmDelete,
            ),
          ),
          // 底部状态提示
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            left: 0,
            right: 0,
            child: Text(
              _loadFailed
                  ? '原图加载失败，当前显示缩略图 · 双指缩放 · 点外侧关闭'
                  : (img != null
                      ? '原图已加载 · 双指缩放 · 拖动查看 · 点外侧关闭'
                      : '正在加载原图…'),
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
