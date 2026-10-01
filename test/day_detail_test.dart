/// E 轨 · 日详情面板单测。
///
/// 三类关键场景：有照片+总结 / 有照片无总结 / 未来日——
/// 覆盖 showDayDetail → DraggableScrollableSheet → DayDetailSheet 的整条渲染链，
/// 断言面向用户的中文文案（契约行为锁定，防止后续重构改词改丢）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/day_detail/day_detail_launcher.dart';
import 'package:shiguang_handbook/features/day_detail/edit_summary_dialog.dart';

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

Future<InMemoryPhotoIndexStore> _storeWith({
  List<Photo> photos = const [],
  AiSummary? summary,
}) async {
  final store = InMemoryPhotoIndexStore();
  await store.init();
  if (photos.isNotEmpty) await store.upsertPhotos(photos);
  if (summary != null) await store.putSummary(summary);
  return store;
}

/// 起一个最小宿主 App，再点按钮打开日详情面板。
Future<void> _openSheet(
  WidgetTester tester,
  PhotoIndexStore store,
  int dayKey,
) async {
  await tester.pumpWidget(
    ProviderScope(
      // 注入预置数据的内存存储：不依赖真实扫描，也能覆盖 FutureProvider 三态
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

/// 面板初始只有 45% 高，先向上拖把内容拉到底，再断言底部按钮。
Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // 平台通道在单测里没有实现：先换成内存偏好，避免 MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('有照片+总结：展示日期、总结卡与生成按钮', (tester) async {
    const dayKey = 20260920;
    final photos = [
      _photo(path: 'a.jpg', dayKey: dayKey, takenMs: 1768000000000),
      _photo(path: 'b.jpg', dayKey: dayKey, takenMs: 1768000100000),
    ];
    final store = await _storeWith(
      photos: photos,
      summary: AiSummary(
        dayKey: dayKey,
        title: '海边的午后',
        narrative: '浪声把一下午拉得很长，鞋里全是沙。',
        tags: const ['海风', '落日'],
        mood: '晴',
        highlights: const ['捡到一枚贝壳'],
        model: 'claude-opus-5-5',
        // sig 与当前照片一致 → 不该出现「需要重新生成」横幅
        photoSig: computePhotoSig(photos),
        createdAtMs: 1768000200000,
      ),
    );

    await _openSheet(tester, store, dayKey);

    expect(find.text('9月20日'), findsOneWidget);
    expect(find.text('海边的午后'), findsOneWidget);
    expect(find.text('浪声把一下午拉得很长，鞋里全是沙。'), findsOneWidget);
    expect(find.text('#海风'), findsOneWidget);
    expect(find.text('照片有更新，点击重新生成'), findsNothing);
    expect(find.text('这一天尚未到来'), findsNothing);

    await _scrollToBottom(tester);
    expect(find.text('生成今日总结'), findsOneWidget);
  });

  testWidgets('总结可编辑：改标题保存后卡片与缓存同步更新', (tester) async {
    const dayKey = 20260921;
    final photos = [
      _photo(path: 'e.jpg', dayKey: dayKey, takenMs: 1768100000000),
    ];
    final sig = computePhotoSig(photos);
    final store = await _storeWith(
      photos: photos,
      summary: AiSummary(
        dayKey: dayKey,
        title: 'AI 起的标题',
        narrative: 'AI 写的正文。',
        tags: const ['标签A'],
        mood: '晴',
        highlights: const ['瞬间A'],
        model: 'claude-opus-5-5',
        photoSig: sig,
        createdAtMs: 1768100100000,
      ),
    );

    await _openSheet(tester, store, dayKey);
    expect(find.text('AI 起的标题'), findsOneWidget);

    // 打开编辑对话框，改标题后保存
    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pumpAndSettle();
    expect(find.text('编辑今日总结'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      '人手改过的标题',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 卡片刷新为新文案，且已写回缓存
    expect(find.text('人手改过的标题'), findsOneWidget);
    expect(find.text('AI 起的标题'), findsNothing);
    final saved = await store.summaryOf(dayKey);
    expect(saved, isNotNull);
    expect(saved!.title, '人手改过的标题');
    // 编辑不动指纹与创建时间：不触发「照片有更新」，也不冒充新生成
    expect(saved.photoSig, sig);
    expect(saved.createdAtMs, 1768100100000);
    expect(find.text('照片有更新，点击重新生成'), findsNothing);
  });

  testWidgets('编辑校验：标题为空不让保存', (tester) async {
    const dayKey = 20260922;
    final store = await _storeWith(
      photos: [
        _photo(path: 'f.jpg', dayKey: dayKey, takenMs: 1768200000000),
      ],
      summary: AiSummary(
        dayKey: dayKey,
        title: '原标题',
        narrative: '原正文。',
        tags: const [],
        mood: '晴',
        highlights: const [],
        model: 'm',
        photoSig: '',
        createdAtMs: 1,
      ),
    );

    await _openSheet(tester, store, dayKey);
    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pumpAndSettle();

    // 标题清成空白后点保存：弹出错误，对话框不关，不写库
    await tester.enterText(find.byType(TextField).first, ' ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('标题不能为空'), findsOneWidget);
    expect(find.text('编辑今日总结'), findsOneWidget);
    final saved = await store.summaryOf(dayKey);
    expect(saved!.title, '原标题');
  });

  testWidgets('编辑防误触：点对话框外不关；有修改时返回先问是否放弃', (tester) async {
    const dayKey = 20260923;
    final store = await _storeWith(
      photos: [
        _photo(path: 'g.jpg', dayKey: dayKey, takenMs: 1768300000000),
      ],
      summary: AiSummary(
        dayKey: dayKey,
        title: '原标题',
        narrative: '原正文。',
        tags: const [],
        mood: '晴',
        highlights: const [],
        model: 'm',
        photoSig: '',
        createdAtMs: 1,
      ),
    );

    await _openSheet(tester, store, dayKey);
    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pumpAndSettle();

    // 改了字：脏状态
    await tester.enterText(find.byType(TextField).first, '改过的标题');

    // 点对话框外（barrierDismissible: false）：不应关闭
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('编辑今日总结'), findsOneWidget);

    // 系统返回：PopScope 拦下，弹「放弃修改？」确认
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃修改？'), findsOneWidget);

    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.text('编辑今日总结'), findsNothing);

    // 放弃 = 没写库
    final saved = await store.summaryOf(dayKey);
    expect(saved!.title, '原标题');
  });

  testWidgets('编辑保存失败：错误显示在对话框内，不关闭、不丢修改', (tester) async {
    final summary = AiSummary(
      dayKey: 20260924,
      title: '原标题',
      narrative: '原正文。',
      tags: const [],
      mood: '晴',
      highlights: const [],
      model: 'm',
      photoSig: '',
      createdAtMs: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showEditSummaryDialog(
                  ctx,
                  summary,
                  // 落库抛错：对话框必须留在原地并展示原因
                  onSave: (_) async => throw Exception('磁盘炸了'),
                ),
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '改过的标题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('编辑今日总结'), findsOneWidget);
    // 用户的输入还在，可以直接再点一次保存
    expect(find.widgetWithText(TextField, '改过的标题'), findsOneWidget);
  });

  testWidgets('有照片无总结：给出生成引导与按钮', (tester) async {
    const dayKey = 20260925;
    final store = await _storeWith(
      photos: [
        _photo(path: 'c.jpg', dayKey: dayKey, takenMs: 1768500000000),
      ],
    );

    await _openSheet(tester, store, dayKey);

    expect(find.text('9月25日'), findsOneWidget);
    expect(find.text('这一天还没有总结'), findsOneWidget);
    expect(find.text('这一天没有留下照片'), findsNothing);

    await _scrollToBottom(tester);
    expect(find.text('生成今日总结'), findsOneWidget);
  });

  testWidgets('未来日期：提示尚未到来且不给生成入口', (tester) async {
    const dayKey = 20991231;
    final store = await _storeWith();

    await _openSheet(tester, store, dayKey);

    expect(find.text('12月31日'), findsOneWidget);
    expect(find.text('这一天尚未到来'), findsOneWidget);
    expect(find.text('生成今日总结'), findsNothing);
    expect(find.text('这一天没有留下照片'), findsNothing);
  });
}
