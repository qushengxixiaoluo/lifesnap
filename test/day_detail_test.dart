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
