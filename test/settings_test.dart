/// E 轨 · 设置页单测。
///
/// 1) 四个分区全部渲染（用超大视口 + SingleChildScrollView，保证整页进树）；
/// 2) 缺 API Key 点「测试连接」：出现中文错误文案而不是崩溃；
/// 3) 批量生成：注入 SummaryBindings 假实现，点击后能看到 x/N 进度文案。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/settings/settings_page.dart';

/// 只实现批量流的假仓库：阶段 2 前让批量区也能被真实点击验证。
class _FakeSummaryRepository implements SummaryRepository {
  @override
  Future<AiSummary?> cached(int dayKey) async => null;

  @override
  Future<AiSummary> generate({
    required DayRecord record,
    bool force = false,
    void Function(int current, int total)? onImageProgress,
  }) async {
    throw const AiException('假实现：单日生成不参与本测试');
  }

  @override
  Stream<MonthBatchProgress> generateMonth({
    required int year,
    required int month,
  }) {
    return Stream.fromIterable(const [
      MonthBatchProgress(
          total: 3, done: 1, failed: 0, currentDayKey: 20260901),
      MonthBatchProgress(
          total: 3, done: 3, failed: 0, currentDayKey: 20260902,
          finished: true),
    ]);
  }
}

/// flutter_secure_storage 的方法通道（只读契约，不可改其源码）。
const _secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUp(() {
    // 每个用例重置：单测里平台通道没有实现，先换成内存偏好
    SharedPreferences.setMockInitialValues({});
    // widget 测试（FakeAsync）里，未注册 mock 的原生通道永不回包，
    // ApiKeyStore.exists 会卡死 → AI 分区转圈 → pumpAndSettle 超时。
    // 这里让它立即回 null：ApiKeyStore 随即走 SharedPreferences 降级路径，
    // 语义等价于「设备上还没存过 key」。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async => null);
  });

  tearDown(() {
    SummaryBindings.instance = null; // 静态注入点用完即清，避免污染同文件后续用例
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  Future<InMemoryPhotoIndexStore> seedStore() async {
    final store = InMemoryPhotoIndexStore();
    await store.init();
    await store.addSource(PhotoSource(
      type: SourceType.folder,
      path: r'D:\Photos\旅行',
      lastScanMs: DateTime(2026, 9, 1, 10, 30).millisecondsSinceEpoch,
    ));
    return store;
  }

  /// 有限次 pump，等页面上的异步链路收敛。
  ///
  /// 历史上不能用 pumpAndSettle，是因为当时设置页还包着 SkyBackground
  /// （A 轨交付，60s 循环动画，帧永远处于 scheduled 状态）；
  /// 修复 3 已把 SkyBackground 从设置页移除，该理由对当前被测树不再成立。
  /// 这里仍保留有限次 pump：它对被测树里是否混入常驻动画不敏感
  /// （其他轨若再往页面挂循环动画也不会让测试挂住），
  /// 且固定帧数让耗时确定、不依赖 pumpAndSettle 的超时配置。
  Future<void> settle(WidgetTester tester, {int frames = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpSettings(
    WidgetTester tester,
    PhotoIndexStore store,
  ) async {
    // 视口拉到 3400 逻辑高：四区一次性进树，断言不依赖滚动
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [photoStoreProvider.overrideWith((ref) async => store)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await settle(tester);
  }

  testWidgets('四个分区都渲染，且列出已有照片源', (tester) async {
    final store = await seedStore();
    await pumpSettings(tester, store);

    expect(find.text('照片源'), findsOneWidget);
    expect(find.text('AI 配置'), findsOneWidget);
    expect(find.text('批量生成'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);

    // 来源展示名（路径末段）与上次扫描时间
    expect(find.text('旅行'), findsOneWidget);
    expect(
      find.textContaining('上次扫描 2026-09-01 10:30'),
      findsOneWidget,
    );
  });

  testWidgets('缺 API Key 点测试连接：出现错误文案且不崩溃', (tester) async {
    final store = await seedStore();
    await pumpSettings(tester, store);

    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    // 让 SharedPreferences / 安全存储两条异步链跑完
    await settle(tester, frames: 20);

    expect(find.text('请先填写并保存 API Key'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量生成：点击后展示进度文案', (tester) async {
    SummaryBindings.instance = _FakeSummaryRepository();
    final store = await seedStore();
    await pumpSettings(tester, store);

    await tester.ensureVisible(find.text('生成本月全部总结'));
    await tester.tap(find.text('生成本月全部总结'));
    await settle(tester, frames: 20);

    // 假流最后一帧是 finished(3/3)，进度文案应停在终态
    expect(find.text('进度 3/3'), findsOneWidget);
  });
}
