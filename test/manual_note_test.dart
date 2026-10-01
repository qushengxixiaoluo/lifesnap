/// 手写补记（ManualNote）UI 单测。
///
/// 三个关键场景：
/// 1) 无照片的过去日：纯手写「写点什么 → 写手记 → 落库 → 卡片展示」，
///    以及空正文保存的校验拦截；
/// 2) 手记卡的编辑与删除（删除需二次确认，删完 store 归 null）；
/// 3) 手记与 AI 总结并存：删手记绝不连带删总结。
///
/// 脚手架沿用 day_detail_test.dart 的 _storeWith / _openSheet 模式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/day_detail/day_detail_launcher.dart';

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

AiSummary _summary(int dayKey, List<Photo> photos) => AiSummary(
      dayKey: dayKey,
      title: '灯还亮着',
      narrative: '夜里的灯还亮着，两个人把一本书读完了。',
      tags: const ['夜读'],
      mood: '星夜',
      highlights: const [],
      model: 'm',
      photoSig: computePhotoSig(photos),
      createdAtMs: 1768800000000,
    );

Future<InMemoryPhotoIndexStore> _storeWith({
  List<Photo> photos = const [],
  AiSummary? summary,
  ManualNote? note,
}) async {
  final store = InMemoryPhotoIndexStore();
  await store.init();
  if (photos.isNotEmpty) await store.upsertPhotos(photos);
  if (summary != null) await store.putSummary(summary);
  if (note != null) await store.putNote(note);
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

/// 面板初始只有 45% 高，先向上拖把内容拉到底。
Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // 平台通道在单测里没有实现：先换成内存偏好，避免 MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('无照片日：写点什么 → 保存落库 → 卡片展示；空正文不让保存', (tester) async {
    const dayKey = 20260910;
    final store = await _storeWith();

    await _openSheet(tester, store, dayKey);

    // 空态：文案 + 主按钮
    expect(find.text('这一天没有留下照片'), findsOneWidget);
    expect(find.text('写点什么'), findsOneWidget);
    expect(find.text('手记'), findsNothing);

    // 打开「写手记」对话框，输入正文后保存
    await tester.tap(find.text('写点什么'));
    await tester.pumpAndSettle();
    expect(find.text('写手记'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '今天只有一行字。');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 对话框关闭，卡片展示正文，存储已落库
    expect(find.text('写手记'), findsNothing);
    expect(find.text('今天只有一行字。'), findsOneWidget);
    expect(find.text('手记'), findsOneWidget);
    final saved = await store.noteOf(dayKey);
    expect(saved, isNotNull);
    expect(saved!.body, '今天只有一行字。');
    expect(saved.dayKey, dayKey);
    expect(saved.updatedAtMs, greaterThan(0));

    // 再次编辑：正文清空后保存 → 校验报错、对话框不关、不写库
    await tester.tap(find.byTooltip('编辑手记'));
    await tester.pumpAndSettle();
    expect(find.text('编辑手记'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('手记内容不能为空'), findsOneWidget);
    expect(find.text('编辑手记'), findsOneWidget); // 还开着
    final still = await store.noteOf(dayKey);
    expect(still!.body, '今天只有一行字。');
  });

  testWidgets('手记卡：编辑改字保存后刷新；删除经确认后手记消失', (tester) async {
    const dayKey = 20260911;
    final store = await _storeWith(
      note: ManualNote(
        dayKey: dayKey,
        body: '原手记内容',
        updatedAtMs: 1768100000000,
      ),
    );

    await _openSheet(tester, store, dayKey);
    expect(find.text('手记'), findsOneWidget);
    expect(find.text('原手记内容'), findsOneWidget);

    // 编辑：改字保存
    await tester.tap(find.byTooltip('编辑手记'));
    await tester.pumpAndSettle();
    expect(find.text('编辑手记'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '改过的手记内容');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('改过的手记内容'), findsOneWidget);
    expect(find.text('原手记内容'), findsNothing);
    final edited = await store.noteOf(dayKey);
    expect(edited!.body, '改过的手记内容');
    expect(edited.updatedAtMs, greaterThan(1768100000000)); // 每次保存刷新

    // 删除：先确认
    await tester.tap(find.byTooltip('删除手记'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条手记？'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 手记消失，回到无手记空态，存储归 null
    expect(find.text('手记'), findsNothing);
    expect(find.text('改过的手记内容'), findsNothing);
    expect(find.text('这一天没有留下照片'), findsOneWidget);
    expect(find.text('写点什么'), findsOneWidget);
    expect(await store.noteOf(dayKey), isNull);
  });

  testWidgets('手记与总结并存：两卡都在；删手记后总结仍在', (tester) async {
    const dayKey = 20260912;
    final photos = [
      _photo(path: 'n1.jpg', dayKey: dayKey, takenMs: 1768200000000),
    ];
    final store = await _storeWith(
      photos: photos,
      summary: _summary(dayKey, photos),
      note: ManualNote(
        dayKey: dayKey,
        body: '手记写的另一面。',
        updatedAtMs: 1768200100000,
      ),
    );

    await _openSheet(tester, store, dayKey);

    // 总结卡在顶部
    expect(find.text('灯还亮着'), findsOneWidget);

    // 手记卡在总结卡下方（面板只有 45% 高，往上拖一点让两卡同框）
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.text('灯还亮着'), findsOneWidget);
    expect(find.text('手记'), findsOneWidget);
    expect(find.text('手记写的另一面。'), findsOneWidget);

    // 删掉手记：确认后手记没了，总结原样保留
    await tester.tap(find.byTooltip('删除手记'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条手记？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('手记'), findsNothing);
    expect(find.text('手记写的另一面。'), findsNothing);
    expect(await store.noteOf(dayKey), isNull);
    // 总结绝不受手记删除影响
    final summary = await store.summaryOf(dayKey);
    expect(summary, isNotNull);
    expect(summary!.title, '灯还亮着');
    expect(find.text('灯还亮着'), findsOneWidget);
  });

  testWidgets('有照片无手记：照片网格下方给「添加手记」入口', (tester) async {
    const dayKey = 20260913;
    final store = await _storeWith(
      photos: [
        _photo(path: 'n2.jpg', dayKey: dayKey, takenMs: 1768300000000),
      ],
    );

    await _openSheet(tester, store, dayKey);
    expect(find.text('添加手记'), findsNothing); // 还在网格下方，未滚到

    await _scrollToBottom(tester);
    expect(find.text('添加手记'), findsOneWidget);
    expect(find.text('生成今日总结'), findsOneWidget);

    // 从无到有写一篇手记
    await tester.tap(find.text('添加手记'));
    await tester.pumpAndSettle();
    expect(find.text('写手记'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '凭空补上的一段。');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await store.noteOf(dayKey);
    expect(saved!.body, '凭空补上的一段。');
    expect(find.text('凭空补上的一段。'), findsOneWidget);
  });

  testWidgets('未来日期：不给手记入口', (tester) async {
    const dayKey = 20991230;
    final store = await _storeWith();

    await _openSheet(tester, store, dayKey);
    expect(find.text('这一天尚未到来'), findsOneWidget);
    expect(find.text('写点什么'), findsNothing);
    expect(find.text('添加手记'), findsNothing);
    expect(find.text('手记'), findsNothing);
    expect(find.byTooltip('编辑手记'), findsNothing);
  });
}
