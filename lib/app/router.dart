/// 简单路由表（页面少，不引 go_router，沿用户三个项目的 Navigator 直推先例）。
library;

import 'package:flutter/material.dart';

import '../features/browse/browse_page.dart';
import '../features/calendar_map/calendar_map_page.dart';
import '../features/on_this_day/on_this_day_page.dart';
import '../features/settings/settings_page.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const settings = '/settings';

  /// 浏览与搜索：标签云 / 心情 / 全文检索，结果点进日详情。
  static const browse = '/browse';

  /// 那年今日：往年今天的照片与总结回顾。
  static const onThisDay = '/on-this-day';

  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const CalendarMapPage(),
        settings: (_) => const SettingsPage(),
        browse: (_) => const BrowsePage(),
        onThisDay: (_) => const OnThisDayPage(),
      };
}
