/// 日详情启动器（E 轨真实实现）。
///
/// C 轨（闯关地图）只允许调用 [showDayDetail]，不得直接 import 详情面板内部，
/// 保证两轨并行时接口稳定。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'day_detail_sheet.dart';

/// 展开某一天的详情：可拖拽的底部面板。
///
/// - isScrollControlled：让面板可以占到接近全屏，否则 showModalBottomSheet
///   默认被限制在半屏，内部 DraggableScrollableSheet 拖不上去。
/// - 初始 45%（日期+总结一眼可见）、最低保持 45%（不给误触收起）、最高 95%
///   （顶端留一线天空，拖满也能看出底下还是地图）。
/// - 背景透明：透出 A 轨的天空，纸面板悬浮其上，和整册「手账」画风一致。
void showDayDetail(BuildContext context, int dayKey) {
  Widget content = DraggableScrollableSheet(
    initialChildSize: 0.45,
    minChildSize: 0.45,
    maxChildSize: 0.95,
    expand: false,
    builder: (context, controller) => DayDetailSheet(
      dayKey: dayKey,
      scrollController: controller,
    ),
  );

  // 阶段 0 的 main.dart 还没挂 ProviderScope，而本轨禁改 main.dart：
  // 这里「已有则复用、没有则补挂」兜底，避免面板的 ConsumerStatefulWidget
  // 直接抛 No ProviderScope。编排者日后在 main 补上后，自动走复用分支。
  if (!_hasProviderScope(context)) {
    content = ProviderScope(child: content);
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => content,
  );
}

/// 当前 context 上方是否已有 ProviderScope（找不到会抛 StateError）。
bool _hasProviderScope(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false);
    return true;
  } on StateError {
    return false;
  }
}
