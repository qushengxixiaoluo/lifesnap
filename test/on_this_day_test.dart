/// 那年今日页单测。
///
/// 页面用 DateTime.now() 现算候选日（无法注入假时钟），测试侧同步动态算出
/// 「去年同月同日」的 dayKey 做预置与断言，避免日期漂移导致用例过期。
/// 两个场景：去年有记录（列表卡 + 点开日详情）/ 完全无记录（空态文案）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/on_this_day/on_this_day_page.dart';

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

/// 去年同月同日（页面循环的第一个候选日；2月29日遇非闰年会归一到 3月1日，
/// 与页面侧的归一化行为一致，断言跟着同一条规则走）。
int _lastYearKey() =>
    dayKeyOf(DateTime(DateTime.now().year - 1, DateTime.now().month,
        DateTime.now().day));

/// 起最小宿主 App：ProviderScope 注入预置数据的内存存储。
Future<void> _pumpPage(WidgetTester tester, PhotoIndexStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [photoStoreProvider.overrideWith((ref) async => store)],
      child: const MaterialApp(home: OnThisDayPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // 平台通道在单测里没有实现：先换成内存偏好，避免 MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('去年有记录：展示「1 年前」卡片，点击打开日详情', (tester) async {
    final dayKey = _lastYearKey();
    final year = dayKey ~/ 10000;
    final photos = [
      _photo(path: 'a.jpg', dayKey: dayKey, takenMs: 1768000000000),
    ];
    final store = InMemoryPhotoIndexStore();
    await store.init();
    await store.upsertPhotos(photos);
    await store.putSummary(AiSummary(
      dayKey: dayKey,
      title: '去年今日',
      narrative: '去年今天拍了照片。',
      tags: const ['回顾'],
      mood: '晴',
      highlights: const ['第一张'],
      model: 'claude-opus-5-5',
      photoSig: computePhotoSig(photos),
      createdAtMs: 1768000200000,
    ));

    await _pumpPage(tester, store);

    // 相对年份 + 中文日期（去年那一张在，前年及更早无记录则不出现）
    expect(find.textContaining('1 年前'), findsOneWidget);
    expect(
      find.textContaining(
        '$year年${dayKeyToChinese(dayKey)}',
      ),
      findsOneWidget,
    );
    expect(find.text('去年今日'), findsOneWidget);
    expect(find.textContaining('2 年前'), findsNothing);

    // 点卡片 → 日详情面板打开，头部出现该日中文日期
    await tester.tap(find.text('去年今日'));
    await tester.pumpAndSettle();
    expect(find.text(dayKeyToChinese(dayKey)), findsOneWidget);
  });

  testWidgets('往年今天全无记录：显示空态文案', (tester) async {
    final store = InMemoryPhotoIndexStore();
    await store.init();

    await _pumpPage(tester, store);

    expect(find.text('往年的今天还没有记录'), findsOneWidget);
    expect(find.textContaining('1 年前'), findsNothing);
  });
}
