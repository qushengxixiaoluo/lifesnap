/// 浏览与搜索页单测（标签云 + 心情筛选 + 全文搜索 + 结果点进日详情）。
///
/// 三类关键场景：
/// - case1：标签云计数与点选筛选（含再点取消、心情叠加、清除筛选）；
/// - case2：搜索只命中一条 / 无命中空态 / 清空恢复；
/// - case3：点结果条目打开日详情面板（断言中文日期落在面板头部）。
///
/// 数据一律走 InMemoryPhotoIndexStore + photoStoreProvider.overrideWith，
/// 不依赖真实扫描与磁盘（沿 test/day_detail_test.dart 装配先例）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_handbook/app/providers.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';
import 'package:shiguang_handbook/features/browse/browse_page.dart';

/// 预置的三条总结：不同 dayKey、不同 tags/mood、不同正文关键词。
/// tags 里「海风」出现两次（×2），其余标签各一次（×1），计数断言两种都有样本。
List<AiSummary> _seedSummaries() => [
      AiSummary(
        dayKey: 20260920,
        title: '海边的午后',
        narrative: '浪声把一下午拉得很长，鞋里全是沙。',
        tags: const ['海风', '落日'],
        mood: '晴',
        highlights: const ['捡到一枚贝壳'],
        model: 'm',
        photoSig: '',
        createdAtMs: 1,
      ),
      AiSummary(
        dayKey: 20260918,
        title: '山间清晨',
        narrative: '雾气从松林间漫上来，鸟鸣清脆。',
        tags: const ['徒步'],
        mood: '小雨',
        highlights: const ['看见一只松鼠'],
        model: 'm',
        photoSig: '',
        createdAtMs: 1,
      ),
      AiSummary(
        dayKey: 20260916,
        title: '海边夜跑',
        narrative: '路灯与潮声一路作伴，影子被拉得很长。',
        tags: const ['海风', '夜跑'],
        mood: '星夜',
        highlights: const ['跑到灯塔'],
        model: 'm',
        photoSig: '',
        createdAtMs: 1,
      ),
    ];

Future<InMemoryPhotoIndexStore> _storeWith(List<AiSummary> summaries) async {
  final store = InMemoryPhotoIndexStore();
  await store.init();
  for (final s in summaries) {
    await store.putSummary(s);
  }
  return store;
}

/// 起一个挂了 BrowsePage 的最小宿主，等数据落地。
Future<void> _pumpBrowse(WidgetTester tester, PhotoIndexStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      // 注入预置数据的内存存储：不依赖真实扫描也能驱动 allSummaries
      overrides: [photoStoreProvider.overrideWith((ref) async => store)],
      child: const MaterialApp(home: BrowsePage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 某条文案当前在树里有几处（结果卡与日详情面板头部都可能带日期）。
int _count(String text) => find.text(text).evaluate().length;

void main() {
  setUpAll(() {
    // 平台通道在单测里没有实现：先换成内存偏好，避免 MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('case1 标签云计数正确，点选筛选、再点恢复，可与心情叠加', (tester) async {
    final store = await _storeWith(_seedSummaries());
    await _pumpBrowse(tester, store);

    // —— 计数：全量统计，与筛选无关 ——
    expect(find.text('#海风 ×2'), findsOneWidget);
    expect(find.text('#落日 ×1'), findsOneWidget);
    expect(find.text('#徒步 ×1'), findsOneWidget);
    expect(find.text('#夜跑 ×1'), findsOneWidget);
    // 五个心情胶囊齐活（图标 + 字，取自 AiSummary.moodIcons）
    for (final label in const ['☀ 晴', '☁ 多云', '☂ 小雨', '🌈 彩虹', '✦ 星夜']) {
      expect(find.text(label), findsOneWidget);
    }

    // —— 默认无筛选：day_key 降序，最近在上 ——
    expect(_count('海边的午后'), 1); // 20260920
    expect(_count('海边夜跑'), 1); // 20260916
    expect(
      tester.getTopLeft(find.text('海边的午后')).dy,
      lessThan(tester.getTopLeft(find.text('海边夜跑')).dy),
    );
    expect(find.text('清除筛选'), findsNothing); // 无筛选不显示清除入口

    // —— 点标签：只剩含「海风」的两条 ——
    await tester.tap(find.text('#海风 ×2'));
    await tester.pumpAndSettle();
    expect(_count('海边的午后'), 1);
    expect(_count('海边夜跑'), 1);
    expect(_count('山间清晨'), 0);
    expect(find.text('清除筛选'), findsOneWidget);

    // —— 再点同标签：取消筛选，恢复全部 ——
    await tester.tap(find.text('#海风 ×2'));
    await tester.pumpAndSettle();
    expect(_count('山间清晨'), 1);
    expect(find.text('清除筛选'), findsNothing);

    // —— 心情筛选：只看「星夜」 ——
    await tester.tap(find.text('✦ 星夜'));
    await tester.pumpAndSettle();
    expect(_count('海边夜跑'), 1);
    expect(_count('海边的午后'), 0);

    // —— 与标签叠加：海风 ∩ 星夜 = 只剩海边夜跑（另一条海风是「晴」，被心情滤掉）——
    await tester.tap(find.text('#海风 ×2'));
    await tester.pumpAndSettle();
    expect(_count('海边夜跑'), 1);
    expect(_count('海边的午后'), 0);

    // —— 清除筛选：一次清干净 ——
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(_count('山间清晨'), 1);
    expect(_count('海边夜跑'), 1);
    expect(find.text('清除筛选'), findsNothing);
  });

  testWidgets('case2 搜索只命中一条；无命中显示空态；清空恢复', (tester) async {
    final store = await _storeWith(_seedSummaries());
    await _pumpBrowse(tester, store);

    // 关键词只出现在「山间清晨」的正文里
    await tester.enterText(find.byType(TextField).first, '松林');
    await tester.pumpAndSettle();
    expect(_count('山间清晨'), 1);
    expect(_count('海边的午后'), 0);
    expect(_count('海边夜跑'), 0);
    expect(find.text('清除筛选'), findsOneWidget);

    // 点后缀小叉：清空输入，全部恢复
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(_count('海边的午后'), 1);
    expect(_count('山间清晨'), 1);
    expect(find.text('清除筛选'), findsNothing);

    // 无命中：空态文案，且一条结果都不剩
    await tester.enterText(find.byType(TextField).first, '龙虾火锅');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的记录'), findsOneWidget);
    expect(_count('海边的午后'), 0);
    expect(_count('山间清晨'), 0);
    expect(_count('海边夜跑'), 0);
  });

  testWidgets('case3 点结果条目打开日详情（面板头部带中文日期）', (tester) async {
    final store = await _storeWith(_seedSummaries());
    await _pumpBrowse(tester, store);

    // 列表里已有 20260920 的日期；点开面板后头部再出现一次，共两处
    expect(_count('9月20日'), 1);

    await tester.tap(find.text('海边的午后'));
    await tester.pumpAndSettle();

    expect(_count('9月20日'), 2);
    // 面板确实展开：该日没有照片，落到「无照片」空态
    expect(find.text('这一天没有留下照片'), findsOneWidget);
  });
}
