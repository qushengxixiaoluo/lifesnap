/// D 轨 · 总结仓库：缓存命中、photoSig 失效再生、批量进度（禁止真实网络）。
///
/// 注意本文件不匹配 `test/ai_*.dart` 白名单前缀，是交付清单里点名的
/// `test/summary_repository_test.dart`，由验收命令直接指定。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/core/ai/ai_image_preparer.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/ai/summary_repository.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';

import 'ai_test_helpers.dart';

/// 压图桩：不碰文件系统与 isolate，直接吐固定字节。
class _StubPreparer implements AiImagePreparer {
  int calls = 0;

  @override
  Future<List<Uint8List>> prepare({
    required List<Photo> photos,
    required int maxImages,
    void Function(int current, int total)? onProgress,
  }) async {
    calls++;
    final n = photos.length < maxImages ? photos.length : maxImages;
    onProgress?.call(n, n);
    return List<Uint8List>.generate(
      n,
      (_) => Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
    );
  }
}

Photo buildPhoto({
  required String path,
  required int dayKey,
  int takenAtMs = 0,
  int mtimeMs = 1,
}) =>
    Photo(
      path: path,
      fileSize: 1024,
      mtimeMs: mtimeMs,
      takenAtMs: takenAtMs,
      dayKey: dayKey,
      sourceId: 1,
    );

AiSummary buildCached({
  required int dayKey,
  required String photoSig,
  String title = '缓存里的旧标题',
}) =>
    AiSummary(
      dayKey: dayKey,
      title: title,
      narrative: '这是之前生成过、仍然有效的缓存总结，'
          '只要照片集合指纹没变就不应该再次发起网络请求。',
      tags: const <String>['缓存'],
      mood: '晴',
      highlights: const <String>['命中'],
      model: 'claude-opus-5-5',
      photoSig: photoSig,
      createdAtMs: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ApiKeyStore / SettingsStore 都读 SharedPreferences；
    // flutter_secure_storage 在测试里没有平台实现，会自动落到这个降级键。
    SharedPreferences.setMockInitialValues(
      <String, Object>{'api_key_insecure_fallback': 'sk-unit-test'},
    );
  });

  Future<InMemoryPhotoIndexStore> makeStore(List<Photo> photos) async {
    final store = InMemoryPhotoIndexStore();
    await store.init();
    await store.upsertPhotos(photos);
    return store;
  }

  group('单日生成', () {
    test('无照片 → 抛出「这一天没有照片，无需总结」', () async {
      final store = await makeStore(const <Photo>[]);
      final repo = SummaryRepositoryImpl(
        store: store,
        client: FakeHttpClient((_, _) async => anthropicOk()),
        preparer: _StubPreparer(),
      );
      await expectLater(
        repo.generate(record: const DayRecord(dayKey: 20260930, photos: [])),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          '这一天没有照片，无需总结',
        )),
      );
    });

    test('缓存命中 → 不压图、不发请求', () async {
      final store = await makeStore(<Photo>[
        buildPhoto(path: 'a.jpg', dayKey: 20260930, takenAtMs: 100),
      ]);
      final photos = await store.photosOfDay(20260930);
      await store.putSummary(
        buildCached(dayKey: 20260930, photoSig: computePhotoSig(photos)),
      );

      final client = FakeHttpClient((_, _) async => anthropicOk());
      final preparer = _StubPreparer();
      final repo = SummaryRepositoryImpl(
        store: store,
        client: client,
        preparer: preparer,
      );

      final out = await repo.generate(
        record: DayRecord(dayKey: 20260930, photos: photos),
      );

      expect(out.title, '缓存里的旧标题');
      expect(client.callCount, 0, reason: '缓存有效时不得发网络请求');
      expect(preparer.calls, 0, reason: '缓存有效时不得重复压图');
      // cached() 直读存储，同样不该触发生成
      expect((await repo.cached(20260930))?.title, '缓存里的旧标题');
      expect(client.callCount, 0);
    });

    test('photoSig 变化 → 触发重新生成并落新指纹', () async {
      final store = await makeStore(<Photo>[
        buildPhoto(path: 'a.jpg', dayKey: 20260930, takenAtMs: 100, mtimeMs: 1),
      ]);
      final stalePhotos = await store.photosOfDay(20260930);
      await store.putSummary(
        buildCached(dayKey: 20260930, photoSig: computePhotoSig(stalePhotos)),
      );

      // 照片内容变了（mtime 更新）→ 指纹翻转 → 旧缓存必须失效
      await store.upsertPhotos(<Photo>[
        buildPhoto(path: 'a.jpg', dayKey: 20260930, takenAtMs: 100, mtimeMs: 999),
      ]);
      final freshPhotos = await store.photosOfDay(20260930);
      expect(computePhotoSig(freshPhotos), isNot(computePhotoSig(stalePhotos)));

      final client = FakeHttpClient((_, _) async => anthropicOk());
      final preparer = _StubPreparer();
      final repo = SummaryRepositoryImpl(
        store: store,
        client: client,
        preparer: preparer,
      );

      final out = await repo.generate(
        record: DayRecord(
          dayKey: 20260930,
          photos: freshPhotos,
          summary: buildCached(dayKey: 20260930, photoSig: computePhotoSig(stalePhotos)),
          summaryStale: true,
        ),
      );

      expect(client.callCount, 1);
      expect(preparer.calls, 1);
      expect(out.title, '海风与旧单车', reason: '应取模型新返回的标题');
      expect(out.photoSig, computePhotoSig(freshPhotos), reason: '落库指纹必须等于本次依据的照片');
      expect(out.dayKey, 20260930);
      // 落库后 cached() 读到的是新版本
      expect((await repo.cached(20260930))?.photoSig, computePhotoSig(freshPhotos));
    });

    test('force=true → 即便缓存有效也重新生成', () async {
      final store = await makeStore(<Photo>[
        buildPhoto(path: 'a.jpg', dayKey: 20260930, takenAtMs: 100),
      ]);
      final photos = await store.photosOfDay(20260930);
      await store.putSummary(
        buildCached(dayKey: 20260930, photoSig: computePhotoSig(photos)),
      );

      final client = FakeHttpClient((_, _) async => anthropicOk());
      final repo = SummaryRepositoryImpl(
        store: store,
        client: client,
        preparer: _StubPreparer(),
      );

      final out = await repo.generate(
        record: DayRecord(dayKey: 20260930, photos: photos),
        force: true,
      );
      expect(client.callCount, 1);
      expect(out.title, '海风与旧单车');
    });

    test('压图进度回调会把 total 报出去', () async {
      final store = await makeStore(<Photo>[
        buildPhoto(path: 'a.jpg', dayKey: 20260930, takenAtMs: 1),
        buildPhoto(path: 'b.jpg', dayKey: 20260930, takenAtMs: 2),
      ]);
      final photos = await store.photosOfDay(20260930);
      final repo = SummaryRepositoryImpl(
        store: store,
        client: FakeHttpClient((_, _) async => anthropicOk()),
        preparer: _StubPreparer(),
      );

      final seen = <(int, int)>[];
      await repo.generate(
        record: DayRecord(dayKey: 20260930, photos: photos),
        onImageProgress: (current, total) => seen.add((current, total)),
      );
      expect(seen, isNotEmpty);
      expect(seen.last.$2, 2);
      expect(seen.last.$1, 2);
    });
  });

  group('整月批量生成', () {
    test('total = 当月有照片的天数，缓存有效的天不发请求', () async {
      final store = await makeStore(<Photo>[
        buildPhoto(path: 'd1.jpg', dayKey: 20260901, takenAtMs: 1),
        buildPhoto(path: 'd2.jpg', dayKey: 20260902, takenAtMs: 2),
        buildPhoto(path: 'd3.jpg', dayKey: 20260903, takenAtMs: 3),
      ]);
      // 09-01 已有有效缓存
      final day1Photos = await store.photosOfDay(20260901);
      await store.putSummary(
        buildCached(dayKey: 20260901, photoSig: computePhotoSig(day1Photos), title: '已缓存'),
      );

      final client = FakeHttpClient((_, _) async => anthropicOk());
      final preparer = _StubPreparer();
      final repo = SummaryRepositoryImpl(
        store: store,
        client: client,
        preparer: preparer,
      );

      final events = await repo.generateMonth(year: 2026, month: 9).toList();

      expect(events, isNotEmpty);
      expect(events.last.finished, isTrue, reason: '流必须以 finished 帧收尾');
      expect(events.last.total, 3, reason: 'total = 有照片的天数');
      expect(events.last.done, 3, reason: '2 天新生成 + 1 天缓存命中');
      expect(events.last.failed, 0);
      expect(events.where((e) => e.finished), hasLength(1));
      expect(events.every((e) => e.total == 3), isTrue);

      // 首帧把已有进度交代清楚，UI 才不会从 0 跳到一半
      expect(events.first.finished, isFalse);
      expect(events.first.done, 1);
      expect(events.first.currentDayKey, 0);

      expect(client.callCount, 2, reason: '缓存有效的 09-01 不应发起请求');
      expect(preparer.calls, 2);

      // 每一帧的 done+failed 都不超过 total，且单调不减
      var lastDone = 0;
      for (final e in events) {
        expect(e.done + e.failed, lessThanOrEqualTo(e.total));
        expect(e.done, greaterThanOrEqualTo(lastDone));
        lastDone = e.done;
      }
      expect((await repo.cached(20260902))?.title, '海风与旧单车');
    });

    test('某天失败只计 failed，不拖垮整批', () async {
      final store = await makeStore(<Photo>[
        buildPhoto(path: 'd1.jpg', dayKey: 20260901, takenAtMs: 1),
        buildPhoto(path: 'd2.jpg', dayKey: 20260902, takenAtMs: 2),
      ]);

      final client = FakeHttpClient((call, _) async {
        if (call == 1) return anthropicOk();
        // 400 不可重试，失败立刻落定，免得用例真的去睡 1+2+4 秒退避
        return jsonResponse(
          <String, Object?>{
            'type': 'error',
            'error': <String, Object?>{
              'type': 'invalid_request_error',
              'message': 'bad image payload',
            },
          },
          status: 400,
        );
      });
      final repo = SummaryRepositoryImpl(
        store: store,
        client: client,
        preparer: _StubPreparer(),
      );

      final events = await repo.generateMonth(year: 2026, month: 9).toList();
      expect(events.last.finished, isTrue);
      expect(events.last.total, 2);
      expect(events.last.done + events.last.failed, 2);
      expect(events.last.failed, greaterThanOrEqualTo(1));
    });

    test('当月没有照片 → total=0 且正常收尾', () async {
      final store = await makeStore(const <Photo>[]);
      final repo = SummaryRepositoryImpl(
        store: store,
        client: FakeHttpClient((_, _) async => anthropicOk()),
        preparer: _StubPreparer(),
      );
      final events = await repo.generateMonth(year: 2026, month: 9).toList();
      // 首帧交代 total=0，末帧收尾 finished——UI 才知道该显示「本月没有可生成的天」
      expect(events, hasLength(2));
      expect(events.first.finished, isFalse);
      expect(events.first.total, 0);
      expect(events.last.finished, isTrue);
      expect(events.last.total, 0);
      expect(events.last.done, 0);
      expect(events.last.failed, 0);
    });
  });
}
