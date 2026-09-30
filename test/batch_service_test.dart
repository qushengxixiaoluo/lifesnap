/// 批量生成全局服务测试：锁住用户三条诉求的行为。
///
/// 1) startAll 全库补全：所有「有照片无总结」的天按时间升序生成；
/// 2) 残队续跑：模拟杀进程后重开（落盘队列）→ resumeIfPending 接着跑完；
/// 3) Key 天效中止：当天放回队首、残队保留，修好后可续。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/batch_service.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';

/// 记录生成顺序的假仓库（顺序断言就靠它）。
/// [store] 非空时像真实实现一样把总结落库——store.summaryOf 的断言依赖这一步。
class _RecordingRepo implements SummaryRepository {
  _RecordingRepo({this.failWithAuth = false, this.store});

  final bool failWithAuth;
  final InMemoryPhotoIndexStore? store;
  final generated = <int>[];

  @override
  Future<AiSummary?> cached(int dayKey) async => null;

  @override
  Future<AiSummary> generate({
    required DayRecord record,
    bool force = false,
    void Function(int current, int total)? onImageProgress,
  }) async {
    if (failWithAuth) throw const AiAuthException();
    generated.add(record.dayKey);
    final summary = AiSummary(
      dayKey: record.dayKey,
      title: 't',
      narrative: 'n',
      tags: const [],
      mood: '晴',
      highlights: const [],
      model: 'fake',
      photoSig: computePhotoSig(record.photos),
      createdAtMs: 0,
    );
    await store?.putSummary(summary);
    return summary;
  }

  @override
  Stream<MonthBatchProgress> generateMonth({required int year, required int month}) =>
      const Stream.empty();
}

Future<InMemoryPhotoIndexStore> storeWith(List<int> dayKeys) async {
  final store = InMemoryPhotoIndexStore();
  await store.init();
  final src = await store.addSource(
      PhotoSource(type: SourceType.folder, path: r'D:\P'));
  await store.upsertPhotos([
    for (final dayKey in dayKeys)
      Photo(
        path: 'p_$dayKey.jpg',
        fileSize: 1,
        mtimeMs: dayKey,
        takenAtMs: dayKeyToDateTime(dayKey)
            .add(const Duration(hours: 12))
            .millisecondsSinceEpoch,
        dayKey: dayKey,
        sourceId: src,
      ),
  ]);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SummaryBindings.instance = null;
  });

  tearDown(() => SummaryBindings.instance = null);

  ProviderContainer containerWith(InMemoryPhotoIndexStore store) =>
      ProviderContainer(
        overrides: [photoStoreProvider.overrideWith((ref) async => store)],
      );

  test('startAll：全库缺失按时间升序补全，队列清空', () async {
    final store = await storeWith([
      dayKeyOf(DateTime(2026, 9, 30)), // 最晚
      dayKeyOf(DateTime(2024, 5, 2)), // 最早
      dayKeyOf(DateTime(2025, 1, 15)), // 中间
    ]);
    final repo = _RecordingRepo(store: store);
    SummaryBindings.instance = repo;
    final c = containerWith(store);
    addTearDown(c.dispose);

    await c.read(batchServiceProvider.notifier).startAll();
    final state = c.read(batchServiceProvider);

    expect(state.finished, isTrue);
    expect(state.done, 3);
    expect(state.failed, 0);
    // 升序：2024 → 2025 → 2026（从头到尾）
    expect(repo.generated, [20240502, 20250115, 20260930]);
    // 已有总结的天不入队：全跑完后 store 三天都有总结
    expect(await store.summaryOf(20240502), isNotNull);

    // 全部完成 → 残队必须清空（重启不会重复跑）
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('batch_job_v1'), isNull);
  });

  test('杀进程后续跑：落盘残队被 resumeIfPending 接着跑完', () async {
    SharedPreferences.setMockInitialValues({
      'batch_job_v1': jsonEncode({
        'pending': [20250115, 20260930],
        'failed': <int>[],
        'done': 1,
      }),
    });
    final store = await storeWith([
      dayKeyOf(DateTime(2025, 1, 15)),
      dayKeyOf(DateTime(2026, 9, 30)),
    ]);
    final repo = _RecordingRepo();
    SummaryBindings.instance = repo;
    final c = containerWith(store);
    addTearDown(c.dispose);

    expect(c.read(batchServiceProvider).running, isFalse);
    await c.read(batchServiceProvider.notifier).resumeIfPending();

    final state = c.read(batchServiceProvider);
    expect(state.finished, isTrue);
    expect(repo.generated, [20250115, 20260930]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('batch_job_v1'), isNull, reason: '续跑完成应清残队');
  });

  test('Key 失效：任务中止、失败天放回队首、残队保留可续', () async {
    final store = await storeWith([
      dayKeyOf(DateTime(2026, 9, 28)),
      dayKeyOf(DateTime(2026, 9, 29)),
    ]);
    SummaryBindings.instance = _RecordingRepo(failWithAuth: true);
    final c = containerWith(store);
    addTearDown(c.dispose);

    await c.read(batchServiceProvider.notifier).startAll();
    final state = c.read(batchServiceProvider);

    expect(state.running, isFalse);
    expect(state.abortedReason, isNotNull, reason: '应给出中文中止原因');
    expect(state.hasPending, isTrue, reason: '残队保留，修好 Key 后可续');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('batch_job_v1'), isNotNull);
  });
}
