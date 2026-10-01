/// 那年今日页（占位壳，功能由并行开发轨填充）。
///
/// 契约：公开类 [OnThisDayPage]、无参 const 构造——router.dart 依赖此签名。
library;

import 'package:flutter/material.dart';

class OnThisDayPage extends StatelessWidget {
  const OnThisDayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('那年今日')),
      body: const Center(child: Text('建设中')),
    );
  }
}
