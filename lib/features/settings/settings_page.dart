/// 设置页（E 轨整体重写：照片源 / AI 配置 / 批量生成 / 外观）。
///
/// 契约（阶段 0 钉死）：类名 [SettingsPage] 与无参 const 构造不变，
/// 路由 '/settings' 与 C 轨的入口按钮继续直接 new 它。
///
/// photoStoreProvider 是 FutureProvider，所有消费方一律走
/// async.when(loading/data/error) 三态，error 给中文重试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/hand_card.dart';
import 'settings_ai_config.dart';
import 'settings_appearance.dart';
import 'settings_batch.dart';
import 'settings_photo_sources.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      appBar: AppBar(title: const Text('设置')),
      // 不再包 SkyBackground（A 轨活动实现，60s 循环动画）：它不在本轨
      // 只读契约清单内，且循环动画导致本轨单测永远无法 pumpAndSettle。
      // 设置页用主题纯色底即可——内容全是卡片表单，天空动效是地图页的事。
      body: SafeArea(
        // 单列整体滚动而非 ListView：四个分区都要进 widget 树，
        // 单测才能一次性断言四区渲染（ListView 会按视口懒建）。
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              HandCard(child: PhotoSourceSection()),
              SizedBox(height: 12),
              HandCard(child: AiConfigSection()),
              SizedBox(height: 12),
              HandCard(child: BatchSection()),
              SizedBox(height: 12),
              HandCard(child: AppearanceSection()),
            ],
          ),
        ),
      ),
    );

    // 阶段 0 的 main.dart 尚未挂 ProviderScope（本轨禁改 main.dart）：
    // 「已有则复用、没有则补挂」兜底；编排者补上后自动走复用分支。
    return _hasProviderScope(context) ? page : ProviderScope(child: page);
  }
}

/// context 上方是否已有 ProviderScope（找不到会抛 StateError）。
bool _hasProviderScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } on StateError {
    return false;
  }
}
