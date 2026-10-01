/// 浏览与搜索页（占位壳，功能由并行开发轨填充）。
///
/// 契约：公开类 [BrowsePage]、无参 const 构造——router.dart 依赖此签名。
library;

import 'package:flutter/material.dart';

class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('浏览与搜索')),
      body: const Center(child: Text('建设中')),
    );
  }
}
