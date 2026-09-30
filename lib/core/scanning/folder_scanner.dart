/// 本地文件夹扫描器（io 平台：Android/iOS/Windows/macOS/Linux）。
///
/// 性能设计（目标：几千到几万张照片、支持增量）：
/// 1. 遍历整棵树放在 Isolate.run 里跑，主 isolate 只收结果，UI 不掉帧；
/// 2. 遍历阶段顺手取 stat（size + mtime），先用 knownPathToMtime 过滤，
///    未变化的文件完全跳过 EXIF 解析（增量扫描的大头开销就在读图解析）；
/// 3. 只有新/变更文件才进第二批 isolate 按 200 条一批解析 EXIF，逐批回传落库，
///    进度帧与内存峰值都被批大小压住；
/// 4. EXIF DateTimeOriginal 读取失败（损坏、无 EXIF、HEIC 无元数据）一律回退文件 mtime；
/// 5. 遍历用逐目录手工递归而非 listSync(recursive:true)：下钻前剪枝隐藏/系统目录，
///    单个子目录无权限只跳过该分支；根目录不存在/不可读则报错退出并跳过删除检测
///    （详见 listPhotoEntries 与 scan 的注释）；
/// 6. 「读不到 ≠ 删了」贯穿两层：根目录失败整次扫描作废；子分支失败时
///    listPhotoEntries 会带回失败前缀清单，scan 计算删除时把这些前缀下的
///    已知路径排除——否则一次临时的权限拒绝就会把该分支的历史索引清掉，
///    权限恢复后还得再等一次全量扫描才找得回图（详见 [PhotoListing]）；
/// 7. 扫描收尾把本轮跳过项计数（failedDirs/unreadableFiles 数）挂进
///    [ScanProgressWithSkips] 帧回传——跳过不能无声，上层据此可提示
///    「本轮有 N 处没扫到」（ScanProgress 本体在共享 models.dart 禁改，
///    故用子类携带计数，取舍见 scanner_contracts 注释）。
///
/// 本文件 import dart:io，仅能被 io 分支编译（scanner_platform_io.dart 经条件导入接入）。
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:exif/exif.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'scan_filters.dart';
import 'scan_sink.dart';
import 'scanner_contracts.dart';

/// 遍历结果的最小数据单元：只带标量，跨 isolate 拷贝零负担。
class RawPhotoEntry {
  const RawPhotoEntry(this.path, this.size, this.mtimeMs);

  final String path;
  final int size;
  final int mtimeMs;
}

/// 一次遍历的完整产物：条目 +「本轮没读到」的路径清单。
///
/// 为什么要带失败清单：枚举时跳过的分支只是「读不到」，不是「盘上删了」。
/// 若不把这些路径报回来，scan 的删除检测会把该分支下所有历史索引当已删清出
/// ——权限是暂时的，索引却没了，权限恢复后照片要等下一次全量比对才回来。
/// failedDirs 存目录前缀（该目录整棵子树都没进 present），unreadableFiles
/// 存「名字读得到、stat 读不到」的单文件，二者在删除检测里逐一排除。
class PhotoListing {
  const PhotoListing({
    required this.entries,
    required this.failedDirs,
    required this.unreadableFiles,
  });

  /// 成功枚举并取到 stat 的照片条目。
  final List<RawPhotoEntry> entries;

  /// listSync 失败的子目录路径（整支未枚举，其下已知路径不得判删）。
  final List<String> failedDirs;

  /// statSync 失败的文件路径（枚举到了但属性读不到，同样不得判删）。
  final List<String> unreadableFiles;
}

class FolderScanner implements PhotoSourceScanner {
  FolderScanner({required PhotoScanSink sink}) : _sink = sink;

  final PhotoScanSink _sink;

  /// 文件夹扫描在所有 io 平台都可用（Web 无真实路径，见 WebPickScanner）。
  @override
  bool get supported => true;

  @override
  Stream<ScanProgress> scan(
    PhotoSource source, {
    required Map<String, int> knownPathToMtime,
  }) async* {
    final root = source.path;
    final sourceId = source.id;

    // 根目录不存在（外置盘未挂载、路径改名、权限变更）必须报错退出：
    // 若把「读不到」当「空目录」继续走下面的删除检测，库里所有路径都会被判成
    // 「盘上已删」，一次在盘未挂载时触发的扫描就把该源整库清空。
    // 只有根目录确认可读、枚举结果确实为空时，才允许全删。
    if (!Directory(root).existsSync()) {
      yield ScanProgress(
        phase: ScanPhase.error,
        errorMessage: '文件夹不存在或未挂载「$root」，本次扫描取消（跳过删除检测以免误清索引）',
      );
      return;
    }

    // —— 阶段一：Isolate 里递归枚举 ——
    yield const ScanProgress(phase: ScanPhase.listing);
    PhotoListing listing;
    try {
      listing = await Isolate.run(() => listPhotoEntries(root));
    } catch (e) {
      // 根目录不可读 / 遍历期间出错：同样必须在删除检测之前退出，理由同上
      yield ScanProgress(
        phase: ScanPhase.error,
        errorMessage: '无法遍历目录「$root」：$e（跳过删除检测以免误清索引）',
      );
      return;
    }
    final entries = listing.entries;
    yield ScanProgress(phase: ScanPhase.listing, scanned: entries.length);

    // —— 删除检测：库里有、盘上已删的批量移除（扫描是唯一的失忆时机；
    //    走到这里说明根目录可读，枚举为空=文件真没了，允许收缩）——
    //    例外：failedDirs 前缀下与 unreadableFiles 里的已知路径「本轮读不到」
    //    而非「确认已删」，必须排除——与根目录失败跳过删除检测是同一条原则，
    //    只是范围收窄到真正受影响的分支，其余分支的正常删图照常收缩。
    final present = {for (final e in entries) e.path};
    final removed = [
      for (final knownPath in knownPathToMtime.keys)
        if (!present.contains(knownPath) &&
            !listing.unreadableFiles.contains(knownPath) &&
            !listing.failedDirs.any(
              (dir) => knownPath == dir || p.isWithin(dir, knownPath),
            ))
          knownPath,
    ];
    if (removed.isNotEmpty) await _sink.onRemoved(removed);

    // —— 阶段二/三：按批解析 + 逐批落库 ——
    var scanned = 0;
    var added = 0;
    const batchSize = 200;
    for (var start = 0; start < entries.length; start += batchSize) {
      final batch =
          entries.sublist(start, min(start + batchSize, entries.length));

      // 增量核心：mtime 与库里完全一致的文件直接跳过（连 EXIF 都不读）
      final changed = [
        for (final e in batch)
          if (knownPathToMtime[e.path] != e.mtimeMs) e,
      ];

      if (changed.isNotEmpty) {
        yield ScanProgress(
          phase: ScanPhase.parsing,
          scanned: scanned,
          added: added,
          currentPath: changed.first.path,
        );
        // EXIF 解析是纯 CPU + 小 IO，放独立 isolate；每 200 张一个批次回传
        final photos =
            await Isolate.run(() => parsePhotoBatch(changed, sourceId));
        if (photos.isNotEmpty) {
          await _sink.onPhotos(photos);
          added += photos.length;
        }
      }

      scanned += batch.length;
      yield ScanProgress(
        phase: ScanPhase.indexing,
        scanned: scanned,
        added: added,
        currentPath: batch.last.path,
      );
    }

    // 收尾帧携带跳过项计数：本轮因无权限/读取失败被整支跳过的分支数——
    // 跳过不能无声，上层（测试/后续 UI）可据此提示「有 N 处没扫到」。
    // ScanProgress 本体在共享 models.dart（禁改），计数走 scanner_contracts
    // 里的 ScanProgressWithSkips 子类：向上转型对现有消费方完全透明。
    yield ScanProgressWithSkips(
      phase: ScanPhase.done,
      scanned: scanned,
      added: added,
      skippedDirs: listing.failedDirs.length,
      skippedFiles: listing.unreadableFiles.length,
    );
  }
}

/// 递归枚举目录内所有符合白名单的照片文件（在 isolate 中执行）。
/// 用同步 API 是刻意的：本函数整体跑在后台 isolate，同步遍历比事件循环
/// 交替更省上下文切换，且不会占用主 isolate。
///
/// 为什么不用 listSync(recursive:true)：dart:io 的原生递归遇到任一拒绝访问的
/// 子目录会直接抛 PathAccessException 且一个结果都不返回——扫盘根时
/// System Volume Information 之类无权限目录会让整次扫描失败。改成逐目录手工
/// 递归后：下钻前剪枝隐藏/系统目录（不再空跑 .git/$RECYCLE.BIN），单个子目录
/// 列举失败只跳过该分支，只有根目录本身不可读才向上抛（由 scan 转成 error 并
/// 跳过删除检测，防止「读不到」被当成「全删了」）。
///
/// 跳过的分支不能「无声跳过」：失败目录与 stat 失败文件要随 [PhotoListing]
/// 一并报回，否则它们不在 present 里，会被 scan 的删除检测当成盘上已删清出
/// 索引——根目录失败跳过删除检测防的是同一种误删，只是这里精确到分支粒度。
@pragma('vm:entry-point')
PhotoListing listPhotoEntries(String root) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) {
    // 不返回空列表：空列表会触发删除检测全删，必须让调用方按错误处理
    throw FileSystemException('根目录不存在或不可访问', root);
  }
  final out = <RawPhotoEntry>[];
  // 「读不到」回执：供删除检测排除，见 PhotoListing 注释
  final failedDirs = <String>[];
  final unreadableFiles = <String>[];
  // 显式栈代替系统递归：每一层都能单独 catch，坏一个目录只丢一支
  final pending = <String>[root];
  var isRoot = true;

  while (pending.isNotEmpty) {
    final dirPath = pending.removeLast();
    List<FileSystemEntity> children;
    if (isRoot) {
      // 根列举失败不捕获：整次扫描没有意义，且必须走 error 分支跳过删除检测
      children = rootDir.listSync(followLinks: false);
      isRoot = false;
    } else {
      try {
        children = Directory(dirPath).listSync(followLinks: false);
      } catch (_) {
        // 子目录无权限/被占用/盘符中途消失：跳过该分支，其余照扫。
        // 记下前缀——该分支下的已知文件只是没读到，不是删了
        failedDirs.add(dirPath);
        continue;
      }
    }

    for (final entity in children) {
      if (entity is Directory) {
        // 下钻前剪枝：隐藏/系统目录整个子树不进栈。root 自身不参与判断
        //（root 可能天然带点，如 .config），其下的段由各自的父级把关
        if (isHiddenOrSystemName(p.basename(entity.path))) continue;
        pending.add(entity.path);
      } else if (entity is File) {
        final name = p.basename(entity.path);
        if (isHiddenOrSystemName(name)) continue;
        if (!isPhotoFileName(name)) continue;
        try {
          final stat = entity.statSync();
          out.add(RawPhotoEntry(
            entity.path,
            stat.size,
            stat.modified.millisecondsSinceEpoch,
          ));
        } catch (_) {
          // 文件被占用/权限不足：跳过而不是让整次扫描失败；
          // 同样记入回执，防止该文件被删除检测误清
          unreadableFiles.add(entity.path);
        }
      }
    }
  }
  return PhotoListing(
    entries: out,
    failedDirs: failedDirs,
    unreadableFiles: unreadableFiles,
  );
}

/// 批量解析拍摄时间并组装 Photo（在 isolate 中执行）。
@pragma('vm:entry-point')
Future<List<Photo>> parsePhotoBatch(
  List<RawPhotoEntry> entries,
  int sourceId,
) async {
  final out = <Photo>[];
  for (final e in entries) {
    final takenAtMs = await _readTakenAtMs(e);
    out.add(Photo(
      path: e.path,
      fileSize: e.size,
      mtimeMs: e.mtimeMs,
      takenAtMs: takenAtMs,
      dayKey: dayKeyOf(DateTime.fromMillisecondsSinceEpoch(takenAtMs)),
      sourceId: sourceId,
    ));
  }
  return out;
}

/// EXIF DateTimeOriginal 优先；任何失败（无 EXIF/损坏/格式不识别）回退文件 mtime。
Future<int> _readTakenAtMs(RawPhotoEntry e) async {
  try {
    // package:exif 的流式读取只按需取段，不会把整张大图读进内存
    final tags = await readExifFromFile(File(e.path));
    final tag = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
    if (tag != null) {
      final ms = _parseExifDateTime(tag.printable);
      if (ms != null) return ms;
    }
  } catch (_) {
    // 解析抛错 = EXIF 损坏，按约定静默回退 mtime
  }
  return e.mtimeMs;
}

/// 解析 `2023:07:15 08:30:00` 形式的 EXIF 时间串（视为本地时间）。
int? _parseExifDateTime(String raw) {
  final m = RegExp(r'(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
      .firstMatch(raw);
  if (m == null) return null;
  final dt = DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
  // 0000:00:00 之类占位值会让日期归零，视同无效
  if (dt.year < 1971) return null;
  return dt.millisecondsSinceEpoch;
}
