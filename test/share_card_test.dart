/// 分享卡片导出单测（新交互：渲染 → 去向面板）。
///
/// 三条关键路径：
/// 1. 日详情 →「导出卡片」→ 渲染完成弹出去向面板（保存到相册 / 分享… /
///    保存为文件——测试宿主按 Android 语义渲染，三个动作都在）；
/// 2. 「保存为文件」→ 行内「已保存到文件：<路径>」且文件真实存在
///    （io 环境 path_provider 未注册时回退 Directory.systemTemp，照样可断言）；
/// 3. ShareCard 纯渲染：固定尺寸宿主里日期/标题/落款上屏。
///
/// 「保存到相册」「分享…」依赖平台通道（photo_manager / share_plus），
/// 测试宿主里必然抛 MissingPluginException——断言其被转成「操作失败」
/// 行内提示而不是崩溃，就是对错误路径的回归锁定。
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
  InMemoryPhotoIndexStore store,
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

/// 导出按钮在总结卡标题行，面板 45% 高度即可见，无须滚动。
///
/// 交替推进两种时钟：pump 推假时间（导出内部 2×300ms 延迟与 endOfFrame
/// 只认假时钟），runAsync 给真实事件循环转几圈（引擎 toImage/toByteData
/// 的完成回调只在真实事件循环上送达——纯 pump 下截图链会永远挂起）。
Future<void> _tapExport(WidgetTester tester) async {
  await tester.tap(find.byTooltip('导出卡片'));
  await tester.pump(); // 先构建 OverlayEntry
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pumpAndSettle();
}

/// 行内提示在照片网格下方，先拖到底再断言。
Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pumpAndSettle();
}

/// 点击去向动作后的推进：关面板走假时钟，动作里的平台通道
/// （path_provider / photo_manager）回包或异常只在真实事件循环送达。
Future<void> _settleAfterAction(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('导出卡片：渲染后弹出去向面板，三动作齐全', (tester) async {
    const dayKey = 20260920;
    final store = await _storeWithDay(dayKey);
    await _openSheet(tester, store, dayKey);

    await _tapExport(tester);

    // 离屏渲染完成后卡片应被摘掉，不许留残影
    expect(find.byType(ShareCard), findsNothing);
    expect(find.text('卡片已生成，选择去向'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(find.text('分享…'), findsOneWidget);
    expect(find.text('保存为文件'), findsOneWidget);
  });

  testWidgets('保存为文件：行内提示路径且文件真实存在', (tester) async {
    const dayKey = 20260920;
    final store = await _storeWithDay(dayKey);
    await _openSheet(tester, store, dayKey);

    await _tapExport(tester);
    await tester.tap(find.text('保存为文件'));
    await _settleAfterAction(tester);
    await _scrollToBottom(tester);

    // 行内提示给出完整路径（成败两色中的成功绿），文件必须真实落盘
    final text = find.textContaining('已保存到文件：');
    expect(text, findsOneWidget);
    final shown = tester
        .widget<Text>(text)
        .data!
        .replaceFirst('已保存到文件：', '');
    expect(File(shown).existsSync(), isTrue, reason: '提示的路径必须真实存在');
  });

  testWidgets('保存到相册：平台通道缺失时转行内错误提示，不崩溃', (tester) async {
    const dayKey = 20260920;
    final store = await _storeWithDay(dayKey);
    await _openSheet(tester, store, dayKey);

    await _tapExport(tester);
    await tester.tap(find.text('保存到相册'));
    await _settleAfterAction(tester);
    await _scrollToBottom(tester);

    // 测试宿主没有 photo_manager 通道 → MissingPluginException →
    // 被 _runExportAction 兜成「操作失败：…」，绝不允许冒泡成红屏
    expect(find.textContaining('操作失败'), findsOneWidget);
  });

  testWidgets('ShareCard 纯渲染：日期/标题/落款上屏', (tester) async {
    final summary = AiSummary(
      dayKey: 20260920,
      title: '海边的午后',
      narrative: '浪声把一下午拉得很长。',
      tags: const ['海风'],
      mood: '晴',
      highlights: const ['捡到一枚贝壳'],
      model: 'm',
      photoSig: '',
      createdAtMs: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: shareCardWidth,
            height: shareCardHeight,
            child: ShareCard(dayKey: 20260920, summary: summary),
          ),
        ),
      ),
    );
    expect(find.text('海边的午后'), findsOneWidget);
    expect(find.textContaining('2026年9月20日'), findsOneWidget);
    expect(find.text('拾光手册'), findsOneWidget);
  });
}
