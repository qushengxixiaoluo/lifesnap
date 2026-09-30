/// 拾光手册 · 应用入口
///
/// 结构沿 interview_calendar / Emotion 先例：
/// - 根级 `ValueListenableBuilder<AppStyle>` 换天色、内层再监听
///   `ArtStyleNotifier.current` 换画风（两轴任一变化都整树重建主题）
/// - SharedPreferences 分键持久化天色（skinMode）与画风（artMode）
/// - flutter_localizations 中文 Material 组件
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_style.dart';
import 'app/app_theme.dart';
import 'app/batch_service.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'core/ai/summary_repository.dart';
import 'core/scanning/scanner_service.dart';
import 'core/storage/photo_index_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 两轴分键加载，互不覆盖：skinMode 恢复天色、artMode 恢复画风
  await AppStyleNotifier.load(prefs);
  await ArtStyleNotifier.load(prefs);

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
    // 天色与画风都是全局令牌：用 ValueListenable 独立于 Riverpod，
    // 两轴任一变化即整树重建主题（画风是第二根轴，不是天色的第四个值）
    return ValueListenableBuilder<AppStyle>(
      valueListenable: AppStyleNotifier.current,
      builder: (context, style, _) {
        return ValueListenableBuilder<ArtStyle>(
          valueListenable: ArtStyleNotifier.current,
          builder: (context, art, _) {
            return MaterialApp(
              title: '拾光手册',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(style, art: art),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              routes: AppRoutes.routes,
              initialRoute: AppRoutes.home,
              // 每次启动检查落盘的批量残队：上次没跑完的「补全缺失总结」
              // 在这里自动续跑（用户要求：退出软件后从头到尾仍要补完）。
              builder: (context, child) => _BatchAutoResume(child: child),
            );
          },
        );
      },
    );
  }
}

/// 启动即检查批量任务残队（无残队时是零开销 no-op）。
/// 挂在 MaterialApp.builder 下：位于 Navigator 之上、根 ProviderScope 之内。
class _BatchAutoResume extends ConsumerStatefulWidget {
  const _BatchAutoResume({this.child});

  final Widget? child;

  @override
  ConsumerState<_BatchAutoResume> createState() => _BatchAutoResumeState();
}

class _BatchAutoResumeState extends ConsumerState<_BatchAutoResume> {
  @override
  void initState() {
    super.initState();
    // 等首帧后再恢复：让 store/绑定先就绪，也避免启动动画期间抢网络
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(batchServiceProvider.notifier).resumeIfPending();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
