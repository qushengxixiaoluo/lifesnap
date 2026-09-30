/// io 平台（Android/iOS/桌面）的扫描器装配（条件导入的 io 分支）。
///
/// 文件夹与相册是真实实现；webPick 是浏览器专属能力，桌面端用
/// UnsupportedScanner 明确告知原因，避免 UI 出现「点了没反应」的死按钮。
library;

import '../models/models.dart';
import 'folder_scanner.dart';
import 'gallery_scanner.dart';
import 'scan_sink.dart';
import 'scanner_contracts.dart';
import 'unsupported_scanner.dart';

/// 相册能力是否可用（运行时判断：仅 Android/iOS 为 true）。
bool get gallerySupported => GalleryScanner.platformSupported;

/// 按源类型构造扫描器；每次扫描新建实例，sink 绑定本次扫描的落库通道。
PhotoSourceScanner buildScanner(SourceType type, PhotoScanSink sink) =>
    switch (type) {
      SourceType.folder => FolderScanner(sink: sink),
      SourceType.gallery => GalleryScanner(sink: sink),
      SourceType.webPick => const UnsupportedScanner(
          '网页多选导入仅在浏览器中可用，请改用文件夹扫描',
        ),
    };
