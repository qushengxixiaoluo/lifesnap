/// 扫描结果落库回调束。
///
/// 为什么不直接给扫描器注入 PhotoIndexStore：PhotoSourceScanner.scan() 的签名
/// 是阶段 0 钉死的只读契约（只有 source 和 knownPathToMtime 两个入参），
/// 扫描产物只能走构造期注入。回调束让扫描器保持「只产数据、不碰存储」，
/// 落库时机（逐批 upsert / 批后清理删除项）仍由 ScannerServiceImpl 统一编排。
library;

import '../models/models.dart';

class PhotoScanSink {
  PhotoScanSink({required this.onPhotos, required this.onRemoved});

  /// 逐批写入新照片/变更照片（每批约 200 条，对应扫描流的 indexing 阶段）。
  final Future<void> Function(List<Photo> photos) onPhotos;

  /// 扫描时发现「库里有、盘上已没有」的路径批量删除（增量扫描的删除检测）。
  final Future<void> Function(List<String> paths) onRemoved;
}
