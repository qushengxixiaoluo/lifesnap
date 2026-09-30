/// 缩略图缓存测试：锁定两块最容易回归的纯逻辑——
/// ① 磁盘路径分桶（size → 256/512 档、sha1 前两位二级目录）；
/// ② 内存 LRU 淘汰顺序（命中回队尾、最久未用先淘汰、超限单项不死循环）；
/// ③ ThumbCache.clearAll / sizeBytes 的真实统计（设置页清缓存盲写对接）；
/// ④ generateThumb 端到端（二轮修复补的常驻回归，原为一次性探针）：
///    合法图片经「读源 → isolate 内 package:image 解码缩放 → JPEG 编码」
///    主链路出图——这条链曾把 dart:ui 解码塞进 isolate 恒抛失效，
///    必须有用例盯着，防止改回退逻辑时无声回归。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/thumbnails/thumb_cache.dart';
import 'package:shiguang_handbook/core/thumbnails/thumb_generator.dart';
import 'package:shiguang_handbook/core/thumbnails/thumb_paths.dart';

void main() {
  test('size 映射到 256/512 两档，中界 384', () {
    expect(normalizeThumbSize(200), 256);
    expect(normalizeThumbSize(256), 256);
    expect(normalizeThumbSize(383), 256);
    expect(normalizeThumbSize(384), 512);
    expect(normalizeThumbSize(512), 512);
    expect(normalizeThumbSize(1024), 512);
  });

  test('缓存相对路径：{档位}/{sha1前2位}/{sha1}.jpg', () {
    const source = r'D:\Photos\2026\a.jpg';
    final rel256 = thumbRelativePath(source, 256);
    final parts = rel256.split('/');
    expect(parts, hasLength(3), reason: '恰好三级：档位/分桶/文件');
    expect(parts[0], '256');
    expect(parts[1], hasLength(2), reason: '二级分桶取 sha1 前两位十六进制');
    expect(parts[2], matches(RegExp(r'^[0-9a-f]{40}\.jpg$')), reason: '文件名为完整 sha1');
    expect(parts[2].startsWith(parts[1]), isTrue, reason: '分桶与文件名同源');

    // 同一源路径 → 同一缓存文件（跨进程稳定）
    expect(thumbRelativePath(source, 256), rel256);
    // 不同档位 → 不同根目录，互不覆盖
    expect(thumbRelativePath(source, 512), startsWith('512/'));
    // 不同源路径 → 不同 sha1（取两个必然不同的输入）
    expect(
      thumbRelativePath('D:/Photos/a.jpg', 256) ==
          thumbRelativePath('D:/Photos/b.jpg', 256),
      isFalse,
    );
    // 门面与底层规则一致
    expect(ThumbCache.relativePathFor(source, 300), rel256, reason: '300px 归到 256 档');
    expect(ThumbCache.cacheKey(source, 512), '$source@512');
  });

  test('LRU：命中回队尾，最久未用先淘汰，单项超限不死循环', () {
    final lru = ThumbLru(maxBytes: 100);
    final evicted = <String>[];
    lru.onEvict = evicted.add;

    lru.put('a', Uint8List(40));
    lru.put('b', Uint8List(40));
    expect(lru.usedBytes, 80);
    expect(lru.keysInOrder, ['a', 'b']);

    expect(lru.get('a'), isNotNull); // 命中 a → a 变为最新
    expect(lru.keysInOrder, ['b', 'a']);

    lru.put('c', Uint8List(40)); // 120 > 100 → 淘汰最旧的 b
    expect(evicted, ['b'], reason: '淘汰回调只报真正被踢出的键');
    expect(lru.keysInOrder, ['a', 'c']);
    expect(lru.get('b'), isNull);
    expect(lru.usedBytes, 80);

    // 单项就超过上限：保留该项而不是永远淘汰不掉导致死循环
    final solo = ThumbLru(maxBytes: 10);
    solo.put('big', Uint8List(64));
    expect(solo.usedBytes, 64);
    expect(solo.get('big'), isNotNull);

    // 覆盖同键：按新旧差值计费
    final replace = ThumbLru(maxBytes: 100);
    replace.put('k', Uint8List(40));
    replace.put('k', Uint8List(10));
    expect(replace.usedBytes, 10);
    expect(replace.length, 1);
  });

  test('ThumbCache：put/get 走分桶文件，sizeBytes 统计、clearAll 真清空', () async {
    final dir = await Directory.systemTemp.createTemp('thumb_cache_');
    try {
      ThumbCache.debugReset(root: dir.path);
      final payload = Uint8List.fromList([1, 2, 3]);

      await ThumbCache.put('D:/p/a.jpg', 256, payload);
      expect(ThumbCache.memoryGet('D:/p/a.jpg', 256), isNotNull,
          reason: '内存 LRU 即时可读');

      final abs = await ThumbCache.absolutePathFor('D:/p/a.jpg', 256);
      expect(abs, isNotNull);
      expect(File(abs!).existsSync(), isTrue, reason: '磁盘分桶文件已写入');
      expect(abs.replaceAll('\\', '/'), contains('/256/'),
          reason: '路径落在 256 档目录');

      // 内存清掉后应能从磁盘回填
      ThumbCache.lru.clear();
      expect(ThumbCache.memoryGet('D:/p/a.jpg', 256), isNull);
      final fromDisk = await ThumbCache.get('D:/p/a.jpg', 256);
      expect(fromDisk, payload, reason: '磁盘两级缓存读回一致');

      expect(await ThumbCache.sizeBytes(), payload.length);
      final freed = await ThumbCache.clearAll();
      expect(freed, payload.length, reason: 'clearAll 返回释放字节数');
      expect(await ThumbCache.sizeBytes(), 0);
      expect(ThumbCache.memoryGet('D:/p/a.jpg', 256), isNull,
          reason: '内存层随 clearAll 一并清空');
      expect(dir.existsSync(), isFalse, reason: '缓存根目录被整体删除');
    } finally {
      ThumbCache.debugReset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('generateThumb 端到端：isolate 解码源图并输出 JPEG（缩略图主链路）', () async {
    final dir = await Directory.systemTemp.createTemp('thumb_gen_');
    try {
      // 源图用引擎画的合法 PNG：测试侧刻意不引 package:image 造图（生产链路
      // 的解码已由本用例断言覆盖，造图保持零额外依赖），也避免内嵌字节串
      // 损坏时测试假失败
      final src = File('${dir.path}${Platform.pathSeparator}src.png')
        ..writeAsBytesSync(await _makeSolidPng(48, 32));

      final out = await generateThumb(src.path, 256);
      expect(out, isNotNull,
          reason: '合法图片必须走通「读源 → isolate 解码缩放 → JPEG 编码」主链路');
      expect(out, isNotEmpty);
      expect(
        out!.sublist(0, 3),
        [0xFF, 0xD8, 0xFF],
        reason: '输出必须是 JPEG（SOI 魔数）——锁住 package:image encodeJpg 这一环',
      );
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}

/// 引擎画一张纯色小图导出 PNG 字节：测试侧唯一造图手段，零额外依赖。
/// Picture/Canvas 走 flutter_tester 内嵌引擎，无需初始化 binding。
Future<Uint8List> _makeSolidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (byteData == null) {
    throw StateError('引擎 PNG 编码失败（toByteData 返回空）');
  }
  return Uint8List.fromList(
    byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
  );
}
