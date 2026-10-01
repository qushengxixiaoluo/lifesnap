/// 缩略图组件（阶段 0 桩 → B 轨真实现）。
///
/// 【钉死的签名】C 轨（节点预览）与 E 轨（详情网格）盲写对接，B 轨必须保持
/// 类名与构造参数不变：ThumbImage({sourcePath, size, placeholderColor})。
///
/// 行为约定（按阶段 0 文档实现）：
/// - sourcePath 先查内存 LRU → 磁盘缓存 → 未命中入队异步生成；
/// - 生成期间显示水彩占位色块，完成后**仅该 key 的监听者**原地刷新
///   （ValueNotifier 精准通知，不做整树 setState）；
/// - size 映射到 256/512 两档缓存（见 thumb_paths.dart）。
///
/// 静态 key→notifier 注册表：同一张图的网格与 hero 各自一个 notifier，
/// 生成一次两边同时命中；淘汰回调（ThumbCache.onEvict）把落选键置空，
/// 字节才真正随 LRU 释放，避免 notifier 把 48MB 上限架空。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/app_style.dart';
import 'thumb_cache.dart';
import 'thumb_generator.dart' show generateThumb;
import 'thumb_paths.dart';

class ThumbImage extends StatelessWidget {
  /// 照片源路径（桌面绝对路径 / pm:// assetId / web:// 相对路径）。
  final String sourcePath;

  /// 目标边长（CSS 像素），实现方映射到 256/512 档缓存。
  final double size;

  /// 占位色（水彩感默认即可，调用方可传纸色）。
  final Color? placeholderColor;

  /// 图片填充方式：网格/节点用 cover 裁切填满，分享卡等需要
  /// 完整展示的场景传 [BoxFit.contain]（默认 cover，原有调用不变）。
  final BoxFit fit;

  const ThumbImage({
    super.key,
    required this.sourcePath,
    required this.size,
    this.placeholderColor,
    this.fit = BoxFit.cover,
  });

  /// key → 该缩略图的字节通知器（静态：跨组件实例共享，滚动复用不丢状态）。
  static final _notifiers = <String, ValueNotifier<Uint8List?>>{};

  /// 正在读缓存/生成中的 key：防止 build 高频触发重复 IO。
  static final _inflight = <String>{};

  /// 生成已确认失败的 key（Web 占位、源文件被删）：本会话不再重试，杜绝重试风暴。
  static final _failed = <String>{};

  /// LRU 淘汰 → 把对应 notifier 置空：可见项会立即回退占位并重新走缓存读取
  /// （磁盘还在则瞬间回来），不可见项下次挂载时自然重建。
  static bool _evictHookInstalled = false;

  @override
  Widget build(BuildContext context) {
    if (!_evictHookInstalled) {
      _evictHookInstalled = true;
      ThumbCache.onEvict = (key) {
        _notifiers[key]?.value = null;
      };
    }

    final bucket = normalizeThumbSize(size);
    final key = ThumbCache.cacheKey(sourcePath, bucket);
    final notifier = _notifiers.putIfAbsent(
      key,
      // 构造时先看内存 LRU：图片常在滚动中被复用，首帧直接出图不用等异步
      () => ValueNotifier<Uint8List?>(ThumbCache.memoryGet(sourcePath, bucket)),
    );
    if (notifier.value == null) {
      unawaited(_load(key, sourcePath, bucket, notifier));
    }

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: notifier,
      builder: (context, bytes, _) {
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: fit,
            gaplessPlayback: true, // 复用时避免闪回占位色
            errorBuilder: (_, _, _) => _placeholder(),
          );
        }
        return _placeholder();
      },
    );
  }

  Widget _placeholder() => ColoredBox(
        color: placeholderColor ?? ShiguangColors.paperDeep, // 纸色水彩底
        child: const Center(child: Icon(Icons.image_outlined, size: 20)),
      );

  /// 内存 → 磁盘 → 生成 的三级查找；结果写回 notifier 完成原地刷新。
  static Future<void> _load(
    String key,
    String sourcePath,
    int bucket,
    ValueNotifier<Uint8List?> notifier,
  ) async {
    if (notifier.value != null ||
        _inflight.contains(key) ||
        _failed.contains(key)) {
      return;
    }
    _inflight.add(key);
    try {
      final cached = await ThumbCache.get(sourcePath, bucket);
      if (cached != null) {
        notifier.value = cached;
        return;
      }
      final generated = await generateThumb(sourcePath, bucket);
      if (generated != null) {
        await ThumbCache.put(sourcePath, bucket, generated);
        notifier.value = generated;
      } else {
        _failed.add(key); // 生成不了就安静地保持占位
      }
    } catch (_) {
      _failed.add(key);
    } finally {
      _inflight.remove(key);
    }
  }
}
