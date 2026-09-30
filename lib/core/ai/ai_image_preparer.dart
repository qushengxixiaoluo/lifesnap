/// 送审前的图片预处理：均匀采样 → 解码 → 最长边 1568 → JPEG q85。
///
/// 为什么必须压：
/// 1. 12MP 原图单张 5-10MB，base64 后翻 1.33 倍，一天 12 张会直接撑爆请求体；
/// 2. 多模态模型的视觉输入超过约 1568px 就会被再采样一次，先缩等于省 token；
/// 3. q85 是肉眼几乎无损与体积的甜点位，再低文字/二维码就开始糊。
///
/// 为什么放 Isolate.run：JPEG 编解码是纯 CPU 重活，几十张连拍放在主线程
/// 会掉帧到 UI 卡死；Web 不支持 Isolate.run，那里自动回退到当前线程。
library;

import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

// package:image 已由集成方显式写进 pubspec.yaml 的 dependencies（image: ^4.10.1，
// pubspec.lock 中为 direct main），不再是交付初期的「传递依赖」，因此当初
// 压 depend_on_referenced_packages 的 ignore 已删除——依赖声明到位后再留着
// 反而会掩盖真正的漏依赖。test/ai_image_test.dart 同步处理；缩略图轨
// thumb_generator_io.dart 里的同款 ignore 属他轨文件，由其轨道自行删除。
import 'package:image/image.dart' as img;

import '../models/models.dart';
import 'ai_provider.dart';
// 条件导入：默认（Web）用 photo_bytes_web，检测到 dart:io 时换成桌面/移动实现。
// 直接 import dart:io 会让 Web 编译炸掉，这是全仓共享代码的铁律。
import 'photo_bytes_web.dart' if (dart.library.io) 'photo_bytes_io.dart' as bytes;

/// 采样与压缩的最大边长与质量。
const int kMaxImageEdge = 1568;
const int kJpegQuality = 85;

/// 从当日照片里按拍摄时间均匀采样至多 [maxImages] 张。
///
/// 为什么按时间而不是取前 N 张：一天的照片往往早晚密、中午稀，
/// 均匀取点才能让模型看到「从早到晚」的完整弧线，而不是某个时段的切片。
List<Photo> samplePhotosEvenly(List<Photo> photos, int maxImages) {
  if (photos.isEmpty || maxImages <= 0) return const <Photo>[];
  final sorted = List<Photo>.of(photos)
    ..sort((a, b) => a.takenAtMs.compareTo(b.takenAtMs));
  if (sorted.length <= maxImages) return sorted;
  if (maxImages == 1) return <Photo>[sorted.first];

  final picked = <Photo>[];
  for (var i = 0; i < maxImages; i++) {
    final idx = (i * (sorted.length - 1) / (maxImages - 1)).round();
    final candidate = sorted[idx];
    // 极端紧凑时 round() 可能撞同一张，去重保证「至多 maxImages 张」
    if (!picked.contains(candidate)) picked.add(candidate);
  }
  return picked;
}

class AiImagePreparer {
  const AiImagePreparer();

  /// 产出可直接塞进请求的 JPEG 字节。
  ///
  /// 全部照片都读不到字节时抛中文 [AiException]，让上层能区分
  /// 「这天没照片」与「照片读不出来 / 格式不支持」；全部解码失败且嗅探到
  /// HEIC 魔数时给点名 HEIC 的提示——本工具链两级解码器（package:image、
  /// dart:ui/Skia）实测都不认 HEIC，笼统的「格式暂不支持」会把
  /// 「iPhone 原片拷到 Windows」这种可自行转格式的场景淹掉。
  Future<List<Uint8List>> prepare({
    required List<Photo> photos,
    required int maxImages,
    void Function(int current, int total)? onProgress,
  }) async {
    final sampled = samplePhotosEvenly(photos, maxImages);
    final total = sampled.length;
    if (total == 0) return const <Uint8List>[];

    final out = <Uint8List>[];
    var readable = 0;
    var sawHeic = false; // 只要有一张 HEIC 解不开就记下，供报错点名用
    for (var i = 0; i < total; i++) {
      final raw = await bytes.readPhotoBytes(sampled[i].path);
      if (raw != null && raw.isNotEmpty) {
        readable++;
        final jpeg = await compressToJpeg(raw);
        if (jpeg != null && jpeg.isNotEmpty) {
          out.add(jpeg);
        } else if (looksLikeHeic(raw)) {
          sawHeic = true;
        }
      }
      onProgress?.call(i + 1, total);
    }

    if (out.isEmpty && readable > 0) {
      if (sawHeic) {
        throw const AiException(
          '检测到 HEIC（iPhone 原片），当前平台暂不支持解码，请先转为 JPG 再生成总结',
        );
      }
      throw const AiException('照片格式暂不支持（请使用 JPEG / PNG / WebP）');
    }
    if (out.isEmpty) {
      throw const AiException('读不到当天照片的文件内容，请检查存储权限或照片路径');
    }
    return out;
  }
}

/// 解码 + 缩放 + JPEG 编码的三段调度：package:image 优先进后台 isolate，
/// dart:ui 兜底与 isolate 起不来的场景回退当前线程。
///
/// 为什么这样切（而不是像旧版那样把两级都塞进 isolate 再整段重跑）：
/// 本工具链（Flutter 3.38.5）里 dart:ui 的引擎解码注册表只挂在主 isolate，
/// `ui.instantiateImageCodec` 在后台 isolate 恒抛「Failed to access the
/// internal image decoder registry」（见 thumb_generator_io.dart 头注释的
/// 实测记录）——isolate 内注定走不到 ui 解码那一半，旧写法每次都会先在
/// isolate 抛错、再回主线程把 package:image 的解码+缩放+编码整段重跑一遍。
/// 现在 isolate 只跑纯 Dart 的 package:image，返回 null 即哨兵「pkg 解不开」，
/// 主线程收到哨兵只补 ui 解码那一半，不重复跑 pkg 那一半。
Future<Uint8List?> compressToJpeg(Uint8List raw) async {
  Uint8List? jpeg;
  try {
    jpeg = await Isolate.run(() => _decodeResizeEncodePkg(raw));
  } catch (_) {
    // Isolate.run 在 Web 上是 UnsupportedError，个别平台后台 isolate 也可能
    // 因资源紧张起不来——回退当前线程跑完整两级，功能不能因此中断
    // （与 thumb_generator_io.dart 的回退同构）。此处异常也覆盖 isolate 内
    // 未被吞掉的意外崩溃，宁可主线程重跑一遍也不能让单张图把链路打断。
    try {
      return await _decodeResizeEncodeCurrentThread(raw);
    } catch (_) {
      return null;
    }
  }
  if (jpeg != null) return jpeg;

  // 哨兵路径：package:image 已在 isolate 里证明解不开（HEIC、损坏头等）。
  // 纯 Dart 解码器的行为跨线程一致，主线程重跑 pkg 只会得到同样的 null，
  // 所以只补 dart:ui 这一半；ui 解不开的坏图在下面的 catch 归 null，
  // 单张坏图不该让整天的生成直接崩掉。
  // 已知取舍：整批 12MP HEIC 会在这条主线程路径上解码+缩放+JPEG 编码，
  // 可能引起 UI 掉帧——白名单内没有可用的 HEIF 解码器，彻底挪回后台
  // isolate 要等编排者对 HEIC 转码依赖的统一决策（见交付报告 deviations）。
  try {
    final decoded = await _decodeByUi(raw);
    if (decoded == null) return null;
    return _resizeEncode(decoded);
  } catch (_) {
    return null;
  }
}

/// isolate 内的纯计算体：package:image 一级解码 + 缩放 + JPEG 编码。
/// 必须是顶层/静态函数，捕获的只能是可发送的对象。
///
/// 返回 null 是哨兵而不是错误：package:image（4.10.1）没有 HEIF 解码器，
/// 这类格式注定解不开，交给 compressToJpeg 的主线程 ui 兜底去试——
/// 不能在这里抛，抛了会让 Isolate.run 误判成「isolate 起不来」而重跑全段。
Uint8List? _decodeResizeEncodePkg(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    return _resizeEncode(decoded);
  } catch (_) {
    return null; // 损坏头等解码异常与「不认这个格式」同等对待
  }
}

/// 当前线程的完整两级兜底（仅 isolate 起不来时走）：
/// 先 package:image，解不开再 dart:ui——顺序与 isolate 路径一致，
/// 保证 Web 与桌面行为相同。
Future<Uint8List?> _decodeResizeEncodeCurrentThread(Uint8List raw) async {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded != null) return _resizeEncode(decoded);
  } catch (_) {/* package:image 解不开（HEIC、损坏头）→ 交给 dart:ui 兜底 */}

  final decoded = await _decodeByUi(raw);
  if (decoded == null) return null;
  return _resizeEncode(decoded);
}

/// dart:ui 解码 → rawRgba → package:image 的 Image（与 thumb_generator_io 同桥接）。
Future<img.Image?> _decodeByUi(Uint8List raw) async {
  final codec = await ui.instantiateImageCodec(raw);
  ui.Image? image;
  try {
    final frame = await codec.getNextFrame();
    image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;
    // 复制出独立 buffer：toByteData 的底层 buffer 可能带偏移，
    // 直接交给 image 包会读串位。
    final rgba = Uint8List.fromList(
      byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    );
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      order: img.ChannelOrder.rgba,
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

/// 嗅探 HEIC/HEIF 魔数：ISO BMFF 容器 offset 4-7 为 'ftyp'，
/// major brand（offset 8-11）落在 HEIF 家族集合内。
///
/// 为什么需要嗅探而不是只看解码结果：本工具链 package:image 4.10.1 无任何
/// HEIF 解码器、Flutter 引擎二进制也无 HEIF 编解码符号（dart:ui 同样不认），
/// 两级解码对 HEIC 必然同时失败——prepare 据此把笼统的「格式暂不支持」
/// 升级为点名 HEIC 的可操作提示，用户才知道该先转成 JPG 而不是换浏览器重试。
/// 只做只读嗅探，不引入任何 HEIF 解码依赖（编排者对转码插件的决策未落地前，
/// 白名单内没有纯 Dart 解法，见交付报告 deviations）。
///
/// 参数名用 raw 而不是 bytes：本文件把照片字节读取模块前缀 import 成了
/// `bytes`，同名形参会遮蔽前缀，后续维护容易踩坑。
bool looksLikeHeic(Uint8List raw) {
  // 至少要有 size(4) + 'ftyp'(4) + major brand(4) 才能下判断
  if (raw.length < 12) return false;
  // offset 4..7 必须是 'ftyp'（0x66 0x74 0x79 0x70），否则是别的 box 类型
  if (raw[4] != 0x66 || raw[5] != 0x74 || raw[6] != 0x79 || raw[7] != 0x70) {
    return false;
  }
  final brand = String.fromCharCodes(raw.sublist(8, 12));
  // HEIF 家族 major brand：mif1 是 HEIF 通用壳，heic/heix 是 iPhone 静照主力，
  // 其余为序列/多视图变体。同为 ftyp 开头的 MP4（isom/mp42）、AVIF（avif）
  // 不在此列，避免把「解不开的视频/AVIF」误报成 HEIC。
  return const <String>{
    'heic', 'heix', 'hevc', 'hevx',
    'heim', 'heis', 'hevm', 'hevs',
    'mif1', 'msf1', 'heif',
  }.contains(brand);
}

/// 两级解码共用的后半段：最长边压到 1568 再编 JPEG q85。
Uint8List _resizeEncode(img.Image decoded) {
  final maxEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  final img.Image resized;
  if (maxEdge <= kMaxImageEdge) {
    resized = decoded;
  } else if (decoded.width > decoded.height) {
    resized = img.copyResize(
      decoded,
      width: kMaxImageEdge,
      interpolation: img.Interpolation.average,
    );
  } else {
    resized = img.copyResize(
      decoded,
      height: kMaxImageEdge,
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodeJpg(resized, quality: kJpegQuality);
}
