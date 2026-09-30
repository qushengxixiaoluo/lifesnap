/// 照片扫描 · 抽象契约（阶段 0 地基文件）
///
/// 三种实现（B 轨交付），对上层暴露同一进度流：
/// - FolderScanner    本地文件夹递归（Isolate.run + EXIF）
/// - GalleryScanner   手机相册（photo_manager，仅 Android/iOS 编译）
/// - WebPickScanner   Web 目录选择器（Chromium File System Access API）/ 手动多选降级
///
/// 并行纪律：五条轨只 import 不修改。
library;

import '../models/models.dart';

abstract class PhotoSourceScanner {
  /// 当前平台是否支持该扫描方式（如桌面端 gallery → false，UI 隐藏按钮）。
  bool get supported;

  /// 执行扫描，逐帧推送进度直至 `ScanPhase.done` / `error`。
  ///
  /// [knownPathToMtime] 来自 PhotoIndexStore.knownSignatures(source.id)：
  /// 未变化的文件直接跳过 EXIF 解析（增量扫描核心）。
  Stream<ScanProgress> scan(
    PhotoSource source, {
    required Map<String, int> knownPathToMtime,
  });
}

/// 带「本轮跳过项」计数的扫描帧：folder 扫描在收尾（done）时把因无权限/
/// 读取失败被整支跳过的分支数挂回来，让上层能看到「哪些没扫到」。
///
/// 为什么不直接给 ScanProgress 加 skipped 字段：ScanProgress 定义在共享的
/// models.dart，属跨轨禁改文件；本子类向上转型就是 ScanProgress，不认识
/// 跳过信息的消费方（设置页进度文案等）行为完全不变，需要计数的调用方对
/// 收尾帧做一次类型判断即可读到——用「加类型」代替「改契约」的取舍。
class ScanProgressWithSkips extends ScanProgress {
  const ScanProgressWithSkips({
    required super.phase,
    super.scanned,
    super.added,
    super.currentPath,
    super.errorMessage,
    this.skippedDirs = 0,
    this.skippedFiles = 0,
  });

  /// listSync 失败被整支跳过的子目录数（「读不到 ≠ 删了」，其下索引保留）。
  final int skippedDirs;

  /// statSync 失败被跳过的文件数（同上，只跳过不判删）。
  final int skippedFiles;

  /// 跳过项合计，方便进度文案一行展示。
  int get skippedTotal => skippedDirs + skippedFiles;
}

/// 扫描服务门面：串联「读已知签名 → 扫描器 → 落库 → 重算日索引」。
/// 【B 轨实现】；设置页只依赖此门面，不直接触扫描器。
abstract class ScannerService {
  bool get gallerySupported;

  /// 对单个源执行完整扫描流程（进度随流推送，扫描结果已落库）。
  Stream<ScanProgress> scanSource(PhotoSource source);

  /// 顺序扫描全部启用的源（设置页「重新扫描」入口）。
  Stream<ScanProgress> scanAll();
}
