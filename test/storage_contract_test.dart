/// 存储契约测试：同一组断言分别打在
/// ① InMemoryPhotoIndexStore（阶段 0 永久测试替身）
/// ② HivePhotoIndexStore（桌面真实现，跑在临时目录上）
/// 两套实现语义必须一致，防止「测试用内存、线上用 hive」出现行为分叉。
///
/// hasSummary 特例：阶段 0 的 InMemory.refreshDayIndex 不读 summaries
/// （photo_index_store.dart 是只读契约，不能改），因此 InMemory 组对
/// hasSummary 只断言默认 false，hive 组断言真实翻转——差异原因写进交付报告。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/hive_photo_index_store.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';

void main() {
  group('InMemoryPhotoIndexStore 契约', () {
    _contractTests(
      open: () async {
        final store = InMemoryPhotoIndexStore();
        await store.init();
        return store;
      },
      hasSummaryFilled: false,
    );
  });

  group('HivePhotoIndexStore 契约（临时目录）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shiguang_store_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    _contractTests(
      open: () async {
        final store = HivePhotoIndexStore(tempDir.path);
        await store.init();
        return store;
      },
      hasSummaryFilled: true,
    );
  });
}

void _contractTests({
  required Future<PhotoIndexStore> Function() open,
  required bool hasSummaryFilled,
}) {
  test('源：增查、markSourceScanned', () async {
    final store = await open();
    expect(await store.loadSources(), isEmpty, reason: '初始应无扫描源');

    final id = await store.addSource(
      const PhotoSource(type: SourceType.folder, path: '/photos/2026'),
    );
    expect(id, greaterThan(0), reason: 'addSource 应返回自增 id');

    final sources = await store.loadSources();
    expect(sources, hasLength(1));
    expect(sources.first.path, '/photos/2026');
    expect(sources.first.type, SourceType.folder);
    expect(sources.first.enabled, isTrue);
    expect(sources.first.lastScanMs, isNull);

    await store.markSourceScanned(id, 1759200000000);
    expect(
      (await store.loadSources()).first.lastScanMs,
      1759200000000,
      reason: 'markSourceScanned 必须持久化扫描时间',
    );
    await store.close();
  });

  test('照片：upsert、按日升序查询、日索引计数与首图', () async {
    final store = await open();
    final sid = await store.addSource(
      const PhotoSource(type: SourceType.folder, path: '/photos'),
    );

    Photo photo(
      String path,
      int mtime,
      int takenAt,
      int dayKey,
    ) =>
        Photo(
          path: path,
          fileSize: 100,
          mtimeMs: mtime,
          takenAtMs: takenAt,
          dayKey: dayKey,
          sourceId: sid,
        );

    await store.upsertPhotos([
      photo('/photos/b.jpg', 2000, 2000, 20260901), // 故意乱序写入
      photo('/photos/a.jpg', 1000, 1000, 20260901),
      photo('/photos/c.jpg', 3000, 3000, 20260902),
    ]);

    // 按日查询：takenAt 升序（详情页时间线依赖此顺序）
    final day1 = await store.photosOfDay(20260901);
    expect(
      day1.map((p) => p.path).toList(),
      ['/photos/a.jpg', '/photos/b.jpg'],
    );

    // 日索引：计数 + 首图 + 初始无总结
    // thumbPath 断言「必属于当天照片集合」：InMemory（只读契约）取插入序首张、
    // hive 取 takenAt 最早——乱序写入时两者可能不同，但都必须是当天可用的预览图。
    expect(store.dayIndex.keys, containsAll([20260901, 20260902]));
    expect(store.dayIndex[20260901]!.photoCount, 2);
    expect(
      day1.map((p) => p.path).toList(),
      contains(store.dayIndex[20260901]!.thumbPath),
      reason: '节点预览图必须指向当天真实存在的照片',
    );
    expect(store.dayIndex[20260902]!.photoCount, 1);
    expect(store.dayIndex[20260901]!.hasSummary, isFalse);

    // knownSignatures：path → mtime（增量扫描的输入）
    expect(await store.knownSignatures(sid), {
      '/photos/a.jpg': 1000,
      '/photos/b.jpg': 2000,
      '/photos/c.jpg': 3000,
    });

    await store.close();
  });

  test('照片：同 path 覆盖更新时 id 稳定、mtime 指纹更新', () async {
    final store = await open();
    final sid = await store.addSource(
      const PhotoSource(type: SourceType.folder, path: '/photos'),
    );
    final original = Photo(
      path: '/photos/a.jpg',
      fileSize: 100,
      mtimeMs: 1000,
      takenAtMs: 1000,
      dayKey: 20260901,
      sourceId: sid,
    );
    await store.upsertPhotos([original]);
    final firstId = (await store.photosOfDay(20260901)).single.id;
    expect(firstId, greaterThan(0));

    // 模拟文件被覆盖：mtime 变了、路径没变
    await store.upsertPhotos([
      Photo(
        path: original.path,
        fileSize: 200,
        mtimeMs: 1500,
        takenAtMs: 1000, // EXIF 时间通常不变
        dayKey: 20260901,
        sourceId: sid,
      ),
    ]);
    final updated = (await store.photosOfDay(20260901)).single;
    expect(updated.id, firstId, reason: '覆盖更新不得重分配 id（UI key 依赖其稳定）');
    expect(updated.mtimeMs, 1500);
    expect(updated.fileSize, 200);
    expect(await store.knownSignatures(sid), {'/photos/a.jpg': 1500});
    await store.close();
  });

  test('照片：removePhotos 同步收缩日索引与已知签名', () async {
    final store = await open();
    final sid = await store.addSource(
      const PhotoSource(type: SourceType.folder, path: '/photos'),
    );
    await store.upsertPhotos([
      Photo(
        path: '/photos/a.jpg',
        fileSize: 1,
        mtimeMs: 1,
        takenAtMs: 1,
        dayKey: 20260901,
        sourceId: sid,
      ),
      Photo(
        path: '/photos/c.jpg',
        fileSize: 3,
        mtimeMs: 3,
        takenAtMs: 3,
        dayKey: 20260902,
        sourceId: sid,
      ),
    ]);
    expect(store.dayIndex[20260902]!.photoCount, 1);

    await store.removePhotos(['/photos/c.jpg']);
    expect(store.dayIndex.containsKey(20260902), isFalse, reason: '空日必须从索引消失');
    expect(await store.photosOfDay(20260902), isEmpty);
    expect(await store.knownSignatures(sid), {'/photos/a.jpg': 1});
    await store.close();
  });

  test('AI 总结：putSummary/summaryOf 往返 + hasSummary', () async {
    final store = await open();
    final sid = await store.addSource(
      const PhotoSource(type: SourceType.folder, path: '/photos'),
    );
    await store.upsertPhotos([
      Photo(
        path: '/photos/a.jpg',
        fileSize: 1,
        mtimeMs: 1,
        takenAtMs: 1,
        dayKey: 20260901,
        sourceId: sid,
      ),
    ]);
    expect(await store.summaryOf(20260901), isNull);

    const summary = AiSummary(
      dayKey: 20260901,
      title: '窗边的下午',
      narrative: '阳光斜切进屋，尘埃在光柱里慢慢转。',
      tags: ['居家', '晴'],
      mood: '晴',
      highlights: ['光柱里的尘埃'],
      model: 'unit-test',
      photoSig: 'sig-abc',
      createdAtMs: 1759200000000,
    );
    await store.putSummary(summary);

    final got = await store.summaryOf(20260901);
    expect(got, isNotNull);
    expect(got!.title, '窗边的下午');
    expect(got.tags, ['居家', '晴']);
    expect(got.mood, '晴');
    expect(got.photoSig, 'sig-abc');

    // putSummary 后日索引应立刻带金勾（hasSummary）
    if (hasSummaryFilled) {
      expect(store.dayIndex[20260901]!.hasSummary, isTrue);
    } else {
      // 阶段 0 InMemory 不读 summaries，且该文件为只读契约——锁定现状即可
      expect(store.dayIndex[20260901]!.hasSummary, isFalse);
    }
    await store.close();
  });

  test('removeSource 连带清除该源全部照片', () async {
    final store = await open();
    final sid = await store.addSource(
      const PhotoSource(type: SourceType.folder, path: '/photos'),
    );
    await store.upsertPhotos([
      Photo(
        path: '/photos/a.jpg',
        fileSize: 1,
        mtimeMs: 1,
        takenAtMs: 1,
        dayKey: 20260901,
        sourceId: sid,
      ),
    ]);
    await store.removeSource(sid);
    expect(await store.loadSources(), isEmpty);
    expect(store.dayIndex, isEmpty, reason: '源删除后不留孤儿照片');
    await store.close();
  });
}
