/// 拾光手册 · 应用入口
///
/// 结构沿 interview_calendar / Emotion 先例：
/// - 根级 `ValueListenableBuilder<AppStyle>` 换肤（主题变化不经过状态管理包）
/// - SharedPreferences 持久化皮肤
/// - flutter_localizations 中文 Material 组件
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_style.dart';
import 'app/app_theme.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'core/ai/summary_repository.dart';
import 'core/scanning/scanner_service.dart';
import 'core/storage/photo_index_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await AppStyleNotifier.load(prefs);

  // 阶段 2 集成：全应用唯一 store 实例——
  // photoStoreProvider 用 override 指向它（UI 数据源），
  // 扫描/总结服务也注入它（写入方），读写同源，避免双实例并发写。
  final store = await openPhotoIndexStore();
  ScannerServiceImpl.install(store);
  SummaryBindings.instance = SummaryRepositoryImpl(store: store);

  runApp(
    ProviderScope(
      overrides: [
        photoStoreProvider.overrideWith((ref) async => store),
      ],
      child: const ShiguangApp(),
    ),
  );
}

class ShiguangApp extends StatelessWidget {
  const ShiguangApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 皮肤是全局令牌：用 ValueListenable 独立于 Riverpod，换肤即整树重建主题
    return ValueListenableBuilder<AppStyle>(
      valueListenable: AppStyleNotifier.current,
      builder: (context, style, _) {
        return MaterialApp(
          title: '拾光手册',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(style),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: AppRoutes.routes,
          initialRoute: AppRoutes.home,
        );
      },
    );
  }
}
