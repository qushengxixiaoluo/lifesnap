/// 分享卡片导出单测。
///
/// 两条关键路径：
/// 1. 日详情 →「导出卡片」→ 行内「已导出：<路径>」且文件真实存在
///    （io 环境 path_provider 未注册时回退 Directory.systemTemp，照样可断言）；
/// 2. ShareCard 纯渲染：固定尺寸宿主里日期/标题/落款上屏。
///
/// 导出内部有两段 Future.delayed(300ms) + endOfFrame，widget 测试的假时钟
/// 只随 pump 前进——pumpAndSettle 默认步长下可能提前返回，所以显式
/// pump(Duration)×N 手动推进，保证定时器全部触发、截图与写盘完成。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/day_detail/day_detail_launcher.dart';
import 'package:shiguang_handbook/features/day_detail/share_card.dart';

Photo _photo({required String path, required int dayKey, required int takenMs}) {
  return Photo(
    path: path,
    fileSize: 1024,
    mtimeMs: takenMs,
    takenAtMs: takenMs,
    dayKey: dayKey,
    sourceId: 1,
  );
}

/// 预置「有照片 + 有总结」的一天。
Future<InMemoryPhotoIndexStore> _storeWithDay(int dayKey) async {
  final store = InMemoryPhotoIndexStore();
  await store.init();
  final photos = [
    _photo(path: 'a.jpg', dayKey: dayKey, takenMs: 1768000000000),
  ];
  await store.upsertPhotos(photos);
  await store.putSummary(
    AiSummary(
      dayKey: dayKey,
      title: '海边的午后',
      narrative: '浪声把一下午拉得很长，鞋里全是沙。',
      tags: const ['海风', '落日'],
      mood: '晴',
      highlights: const ['捡到一枚贝壳'],
      model: 'claude-opus-5-5',
      photoSig: computePhotoSig(photos),
      createdAtMs: 1768000200000,
    ),
  );
  return store;
}

/// 起最小宿主 App 并打开日详情面板（沿 day_detail_test 脚手架）。
Future<void> _openSheet(
  WidgetTester tester,
  PhotoIndexStore store,
  int dayKey,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [photoStoreProvider.overrideWith((ref) async => store)],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDayDetail(ctx, dayKey),
                child: const Text('打开日详情'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开日详情'));
  await tester.pumpAndSettle();
}

/// 面板初始只有 45% 高，先向上拖把内容拉到底（与 day_detail_test 同法）。
Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // 平台通道在单测里没有实现：先换成内存偏好，避免 MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('导出卡片：点按后行内提示已导出，文件真实落盘', (tester) async {
    const dayKey = 20260920;
    final store = await _storeWithDay(dayKey);

    await _openSheet(tester, store, dayKey);
    expect(find.byTooltip('导出卡片'), findsOneWidget);

    await tester.tap(find.byTooltip('导出卡片'));
    await tester.pump(); // 先构建 OverlayEntry
    // 交替推进两种时钟：pump 推假时间（导出内部 2×300ms 延迟与 endOfFrame
    // 只认假时钟），runAsync 给真实事件循环转几圈（引擎 toImage/toByteData
    // 的完成回调与 path_provider 平台通道回包只在真实事件循环上送达——
    // 纯 pump 下 toByteData 永远等不到，导出链会卡在截图这一步）
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();

    // 离屏卡片必须已被 finally 摘掉，不能留残影
    expect(find.byType(ShareCard), findsNothing);

    await _scrollToBottom(tester);
    final notice = find.textContaining('已导出：');
    expect(notice, findsOneWidget);

    final text = tester.widget<Text>(notice).data!;
    final path = text.replaceFirst('已导出：', '');
    expect(File(path).existsSync(), isTrue);
    expect(path, endsWith('shiguang_20260920.png'));
  });

  testWidgets('无总结日：不出现导出入口', (tester) async {
    const dayKey = 20260925;
    final store = InMemoryPhotoIndexStore();
    await store.init();
    await store.upsertPhotos([
      _photo(path: 'c.jpg', dayKey: dayKey, takenMs: 1768500000000),
    ]);

    await _openSheet(tester, store, dayKey);
    expect(find.byTooltip('导出卡片'), findsNothing);
  });

  testWidgets('ShareCard 纯渲染：日期、标题与落款上屏', (tester) async {
    // 卡片 750×1000，先把测试画布撑到放得下的尺寸
    tester.view.physicalSize = const Size(900, 1250);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: shareCardWidth,
              height: shareCardHeight,
              child: ShareCard(
                dayKey: 20260920,
                summary: AiSummary(
                  dayKey: 20260920,
                  title: '海边的午后',
                  narrative: '浪声把一下午拉得很长，鞋里全是沙。',
                  tags: const ['海风', '落日'],
                  mood: '晴',
                  highlights: const ['捡到一枚贝壳'],
                  model: 'claude-opus-5-5',
                  photoSig: '',
                  createdAtMs: 1768000200000,
                ),
                // 无图日：不依赖缩略图管线，纯断言文字内容
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2026年9月20日'), findsOneWidget);
    expect(find.text('海边的午后'), findsOneWidget);
    expect(find.text('#海风'), findsOneWidget);
    expect(find.textContaining('✨ 捡到一枚贝壳'), findsOneWidget);
    expect(find.text('拾光手册'), findsOneWidget);
  });
}
