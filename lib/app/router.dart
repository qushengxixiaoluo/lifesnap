/// 简单路由表（页面少，不引 go_router，沿用户三个项目的 Navigator 直推先例）。
library;

import 'package:flutter/material.dart';

import '../features/calendar_map/calendar_map_page.dart';
import '../features/settings/settings_page.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const CalendarMapPage(),
        settings: (_) => const SettingsPage(),
      };
}
