/// 缩略图生成（io 平台）：isolate 内 package:image 解码缩放 + JPEG q80 编码。
///
/// 为什么解码必须用 package:image 而不是 dart:ui：本工具链（Flutter 3.38.5）
/// 里 ui.instantiateImageCodec 在 Isolate.run 中恒抛
/// 「Failed to access the internal image decoder registry on this isolate」
/// ——引擎的解码注册表只挂在主 isolate，子 isolate 拿不到，之前把 dart:ui
/// 解码塞进 isolate 实际从未生效（失败被吞掉后回退主 isolate 阻塞执行）。
/// package:image 是纯 Dart，decode → copyResize → encodeJpg 整条链都能进
/// isolate，几万张列表滚动时像素工作不占主 isolate，滚动不掉帧。
///
/// 为什么保留 dart:ui 回退：package:image 不认 HEIC 等格式（decodeImage
/// 返回 null），这类格式只能回主 isolate 用 dart:ui 解码；解不开时占位图
/// 兜底，正确性优先于「绝不阻塞」。
///
/// 为什么编码走 package:image：dart:ui 只提供 PNG/RAW 编码（无 JPEG）；
/// package:image 已在 pubspec dependencies 正式声明，属直接依赖。
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

/// 生成目标档位缩略图；失败返回 null，不向上抛（占位图保持即可）。
Future<Uint8List?> generateThumb(String sourcePath, int bucketSize) async {
  final source = await _readSource(sourcePath);
  if (source == null || source.isEmpty) return null;

  // 主路径：纯 Dart 解码整条进 isolate——不碰 dart:ui 注册表，子 isolate 才跑得动
  try {
    final jpg =
        await Isolate.run(() => _decodeScaleEncodePure(source, bucketSize));
    if (jpg != null) return jpg; // null = 格式 package:image 不认 → 走回退
  } catch (_) {
    // isolate 起不来的宿主环境：不放弃，落回主 isolate 路径
  }

  // 回退：HEIC 等 package:image 不支持的格式，用主 isolate 的 dart:ui 解码
  //（引擎解码注册表只在主 isolate 存在，这条路不进子 isolate）
  try {
    return await _decodeScaleEncodeUi(source, bucketSize);
  } catch (_) {
    return null;
  }
}

/// 读取源字节：普通文件走 dart:io；pm:// 走 photo_manager **原图**接口
/// （originBytes——原先用 thumbnailData 是系统小图，缩略图/放大全糊的根源；
/// 原图字节较大，但整条解码链在 isolate 里，主 isolate 只过一次引用）。
Future<Uint8List?> _readSource(String sourcePath) async {
  if (sourcePath.startsWith('pm://')) {
    try {
      final asset = await AssetEntity.fromId(sourcePath.substring(5));
      if (asset == null) return null;
      final origin = await asset.originBytes;
      if (origin != null && origin.isNotEmpty) return origin;
      return await asset.thumbnailData; // 原图接口失败时的兜底
    } catch (_) {
      return null; // 桌面端无插件实现 / 权限过期：直接放弃生成
    }
  }
  final file = File(sourcePath);
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null; // 文件被删/无权限：占位图兜底
  }
}

/// isolate 内的纯计算：package:image 解码 → 缩放 → JPEG q80。
/// 返回 null 表示格式不被 package:image 识别（如 HEIC），交由调用方走 dart:ui 回退。
Uint8List? _decodeScaleEncodePure(Uint8List source, int bucketSize) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  // 只缩不放：小图放大只是白烧 CPU 与磁盘，列表瓦片反而更糊
  final scaled = decoded.width > bucketSize
      ? img.copyResize(decoded, width: bucketSize)
      : decoded;
  // q80：256px 网格图目视无损，体积约为 PNG 的 1/4，几千张不撑爆磁盘
  return img.encodeJpg(scaled, quality: 80);
}

/// 主 isolate 回退：dart:ui 解码（平台解码器支持的 HEIC 等走这里）
/// → package:image 缩放编码。
/// 像素解码由引擎 IO 线程执行，主 isolate 只承担 toByteData 拷贝与 JPEG 编码，
/// 会短暂占 CPU——但仅在 package:image 解不开时走到，量级可接受。
Future<Uint8List> _decodeScaleEncodeUi(Uint8List source, int bucketSize) async {
  final codec = await ui.instantiateImageCodec(source, targetWidth: bucketSize);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final width = image.width;
  final height = image.height;
  final byteData =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  codec.dispose();
  if (byteData == null) {
    throw StateError('toByteData 返回空（源图解码失败）');
  }
  // 复制出独立 buffer：toByteData 的底层 buffer 可能带偏移，直接交给 image 包会读串位
  final rgba = Uint8List.fromList(
    byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
  );
  final decoded = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(decoded, quality: 80);
}
