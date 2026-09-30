/// Web 平台的扫描器装配（条件导入的 web 分支）。
///
/// 浏览器没有 dart:io 文件系统路径，文件夹扫描不可用；
/// photo_manager 是移动端插件，Web 上也拿不到——两者都用 UnsupportedScanner
/// 兜底，保证 Web 构建不包含 dart:io / photo_manager 的任何代码。
library;

import '../models/models.dart';
import 'scan_sink.dart';
import 'scanner_contracts.dart';
import 'unsupported_scanner.dart';
import 'web_pick_scanner.dart';

/// Web 无相册概念，恒为 false（设置页据此隐藏相册按钮）。
bool get gallerySupported => false;

/// 按源类型构造扫描器：Web 只有 webPick 是真实现。
PhotoSourceScanner buildScanner(SourceType type, PhotoScanSink sink) =>
    switch (type) {
      SourceType.folder => const UnsupportedScanner(
          '浏览器无法直接扫描本地目录，请用「网页手动导入」选择照片',
        ),
      SourceType.gallery => const UnsupportedScanner(
          '网页端不支持读取手机相册',
        ),
      SourceType.webPick => WebPickScanner(sink: sink),
    };
