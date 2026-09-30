/// D 轨 · 图片预处理：均匀采样 + 最长边 1568 + JPEG q85。
///
/// 这条是交付清单里「ai_image_preparer」的直接验证：
/// 不验证的话，压图这条链路一旦静默失败，生产环境只会表现为「请求超大被拒」。
library;

import 'dart:io';
import 'dart:typed_data';

// package:image 已是 pubspec.yaml 的显式直接依赖（image: ^4.10.1），
// 不再是交付初期的传递依赖，压 lint 的 ignore 随之删除。
import 'package:image/image.dart' as img;

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/ai/ai_image_preparer.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/models/models.dart';

Photo buildPhoto(String path, int takenAtMs) => Photo(
      path: path,
      fileSize: 1,
      mtimeMs: takenAtMs,
      takenAtMs: takenAtMs,
      dayKey: 20260930,
      sourceId: 1,
    );

/// 造一张有内容的图（纯色会被 JPEG 压到几乎没字节，断言会失真）。
img.Image makeImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 255) ~/ width, (y * 255) ~/ height, (x ^ y) & 0xFF);
    }
  }
  return image;
}

void main() {
  group('samplePhotosEvenly', () {
    test('20 张取 4 张：首尾保留、按拍摄时间升序、间距均匀', () {
      final photos = <Photo>[
        for (var i = 0; i < 20; i++) buildPhoto('p$i.jpg', 1000 + i * 60000),
      ];
      final picked = samplePhotosEvenly(photos, 4);
      expect(picked, hasLength(4));
      expect(picked.first.path, 'p0.jpg');
      expect(picked.last.path, 'p19.jpg');
      for (var i = 1; i < picked.length; i++) {
        expect(picked[i].takenAtMs, greaterThan(picked[i - 1].takenAtMs));
      }
      // 均匀：相邻间隔应该相等（0 → 6 → 12 → 19 索引附近）
      expect(picked[1].path, 'p6.jpg');
      expect(picked[2].path, 'p13.jpg');
    });

    test('张数不足上限时全量返回；边界参数返回空', () {
      final photos = <Photo>[buildPhoto('a.jpg', 1), buildPhoto('b.jpg', 2)];
      expect(
        samplePhotosEvenly(photos, 12).map((e) => e.path),
        <String>['a.jpg', 'b.jpg'],
      );
      expect(samplePhotosEvenly(const <Photo>[], 12), isEmpty);
      expect(samplePhotosEvenly(photos, 0), isEmpty);
      expect(samplePhotosEvenly(photos, 1).single.path, 'a.jpg');
    });

    test('输入列表不会被排序副作用污染', () {
      final photos = <Photo>[
        buildPhoto('late.jpg', 9000),
        buildPhoto('early.jpg', 1000),
      ];
      samplePhotosEvenly(photos, 2);
      expect(photos.first.path, 'late.jpg', reason: '不能原地排序调用方的列表');
    });
  });

  group('compressToJpeg', () {
    test('2000×1000 → 最长边 1568 的 JPEG，体积变小', () async {
      final source = makeImage(2000, 1000);
      final encoded = img.encodeJpg(source, quality: 95);

      final out = await compressToJpeg(encoded);
      expect(out, isNotNull);

      // JPEG 魔数
      expect(out![0], 0xFF);
      expect(out[1], 0xD8);

      final decoded = img.decodeImage(out);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1568, reason: '最长边必须压到 1568');
      expect(decoded.height, lessThanOrEqualTo(1568));
      // 宽高比保持
      expect(
        (decoded.width / decoded.height) / (2000 / 1000),
        inInclusiveRange(0.99, 1.01),
      );
      expect(out.length, lessThan(encoded.length), reason: '压缩后应更小');
    });

    test('小于上限的图不放大也不变形', () async {
      final source = makeImage(800, 600);
      final encoded = img.encodeJpg(source, quality: 95);
      final out = await compressToJpeg(encoded);
      final decoded = img.decodeImage(out!);
      expect(decoded!.width, 800);
      expect(decoded.height, 600);
    });

    test('无法解码的字节返回 null（上层据此报「格式暂不支持」）', () async {
      expect(await compressToJpeg(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
      expect(await compressToJpeg(Uint8List(0)), isNull);
    });

    test('package:image 不认、dart:ui 认的格式走 ui 回退仍能出 JPEG', () async {
      // WBMP（无线位图）：package:image 没有它的解码器，但 Skia/系统编解码器
      // 认——这条用例锁住 HEIC 修复所依赖的同一条回退链路
      // （img 解码失败 → dart:ui instantiateImageCodec 兜底 → image 编码）。
      // 8×8 单色 WBMP：type/fixHeader 各 0，宽高各 1 字节 MultiByteInt，
      // 随后 8 行位图（每行 1 字节，高位在前）。
      final wbmp = Uint8List.fromList(<int>[
        0x00, 0x00, 0x08, 0x08,
        0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55,
      ]);

      final out = await compressToJpeg(wbmp);
      expect(out, isNotNull, reason: 'dart:ui 兜底后必须产出可送审的 JPEG');
      expect(out![0], 0xFF); // JPEG 魔数
      expect(out[1], 0xD8);
      final decoded = img.decodeImage(out);
      expect(decoded, isNotNull);
      expect(decoded!.width, 8);
      expect(decoded.height, 8);
    });
  });

  group('looksLikeHeic', () {
    /// 造一个最小 ISO BMFF 头：size(4) + 'ftyp'(4) + major brand(4)。
    Uint8List ftypHeader(String brand) => Uint8List.fromList(<int>[
          0x00, 0x00, 0x00, 0x18, // box size = 24
          0x66, 0x74, 0x79, 0x70, // 'ftyp'
          ...brand.codeUnits,
        ]);

    test('HEIF 家族 brand（heic/mif1/hevc…）识别为真', () {
      for (final brand in ['heic', 'mif1', 'hevc', 'msf1', 'heix']) {
        expect(looksLikeHeic(ftypHeader(brand)), isTrue, reason: brand);
      }
    });

    test('同为 ftyp 的 MP4/AVIF brand 不误报', () {
      for (final brand in ['isom', 'mp42', 'avif', 'M4V ']) {
        expect(looksLikeHeic(ftypHeader(brand)), isFalse, reason: brand);
      }
    });

    test('JPEG 魔数、非 ftyp box、过短字节都判否', () {
      expect(
        looksLikeHeic(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])),
        isFalse,
        reason: 'JPEG SOI 不是 ftyp',
      );
      expect(looksLikeHeic(Uint8List.fromList(<int>[0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0])),
          isFalse, reason: 'offset 4 不是 ftyp');
      expect(looksLikeHeic(Uint8List.fromList(<int>[0x66, 0x74, 0x79, 0x70])),
          isFalse, reason: '不足 12 字节');
      expect(looksLikeHeic(Uint8List(0)), isFalse);
    });
  });

  group('prepare · HEIC 点名报错', () {
    test('全天 HEIC 解不开时抛点名 HEIC 的 AiException，而非笼统「格式暂不支持」',
        () async {
      // 最小 HEIC 头：魔数嗅探认、两级解码都解不开——正是
      // 「iPhone 原片拷到 Windows」场景的失败形态。
      final dir = await Directory.systemTemp.createTemp('heic_prep_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/IMG_0001.HEIC');
      file.writeAsBytesSync(<int>[
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
        0x68, 0x65, 0x69, 0x63, // 'heic'
        0x00, 0x00, 0x00, 0x00, 0x6D, 0x69, 0x66, 0x31,
      ]);

      final photos = <Photo>[buildPhoto(file.path, 1000)];
      await expectLater(
        const AiImagePreparer().prepare(photos: photos, maxImages: 1),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('HEIC'))),
      );
    });

    test('非 HEIC 的解不开字节仍走笼统「格式暂不支持」文案', () async {
      final dir = await Directory.systemTemp.createTemp('badimg_prep_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/broken.jpg');
      file.writeAsBytesSync(List<int>.generate(64, (i) => i & 0xFF));

      final photos = <Photo>[buildPhoto(file.path, 1000)];
      await expectLater(
        const AiImagePreparer().prepare(photos: photos, maxImages: 1),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('格式暂不支持'))
            .having((e) => e.message, 'message', isNot(contains('HEIC')))),
      );
    });

    test('部分成功时正常出图，不因个别 HEIC 失败而抛错', () async {
      final dir = await Directory.systemTemp.createTemp('mix_prep_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      // 一张能解的 JPEG + 一张解不开的 HEIC，中途失败不应中断整天的总结
      final jpgPath = '${dir.path}/ok.jpg';
      File(jpgPath).writeAsBytesSync(
        img.encodeJpg(makeImage(64, 48), quality: 95),
      );
      final heicPath = '${dir.path}/IMG_0002.HEIC';
      File(heicPath).writeAsBytesSync(<int>[
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
        0x68, 0x65, 0x69, 0x63,
      ]);

      final photos = <Photo>[
        buildPhoto(jpgPath, 1000),
        buildPhoto(heicPath, 2000),
      ];
      final out = await const AiImagePreparer()
          .prepare(photos: photos, maxImages: 2);
      expect(out, hasLength(1), reason: 'JPEG 那张必须送出去');
      expect(out.single[0], 0xFF);
      expect(out.single[1], 0xD8);
    });
  });
}
