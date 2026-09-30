/// Web 目录/多选扫描器（仅浏览器分支编译本文件，见 scanner_platform_web.dart）。
///
/// 主路径：File System Access API 的 window.showDirectoryPicker() 递归遍历
/// （仅 Chromium 系支持），身份键为相对路径 `web://相对/路径.jpg`，
/// 能保留目录结构，增量签名与桌面端同构。
///
/// 降级路径：API 缺失（Firefox/Safari）或遍历抛错 → file_picker 多选图片，
/// 身份键退化为 `web://文件名`（浏览器不暴露真实相对路径）。
/// 用户主动取消（DOMException AbortError）不算错误，直接以 done 收尾。
///
/// 拍摄时间：Web 上 package:exif 依赖 dart:io 无法编译，不读 EXIF，
/// 统一用文件 lastModified 兜底（详见 deviations）。
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import '../models/models.dart';
import 'scan_filters.dart';
import 'scan_sink.dart';
import 'scanner_contracts.dart';

/// 一次扫描的文件数上限：控制目录句柄迭代次数与索引条目规模
///（字节不再读入内存，OOM 主要来自索引而非扫描过程）；超限即停，已扫部分照常落库。
const _maxFiles = 10000;

/// 落库/进度回传的批大小，与 folder_scanner 保持一致，进度条节奏统一。
const _batchSize = 200;

class WebPickScanner implements PhotoSourceScanner {
  WebPickScanner({required PhotoScanSink sink}) : _sink = sink;

  final PhotoScanSink _sink;

  @override
  bool get supported => true; // 仅 web 分支会 import 本文件

  @override
  Stream<ScanProgress> scan(
    PhotoSource source, {
    required Map<String, int> knownPathToMtime,
  }) async* {
    yield const ScanProgress(phase: ScanPhase.listing);

    List<_WebPickFile>? picked;
    try {
      picked = await _pickDirectory();
    } catch (e) {
      // 取消选择器会以 AbortError 拒绝 promise：这是用户操作，不是故障
      if (e.toString().contains('Abort')) {
        yield const ScanProgress(phase: ScanPhase.done);
        return;
      }
      picked = null; // API 存在但遍历失败 → 落到 file_picker 多选
    }
    picked ??= await _pickManyFallback();
    if (picked == null || picked.isEmpty) {
      yield const ScanProgress(phase: ScanPhase.done);
      return;
    }

    yield ScanProgress(phase: ScanPhase.listing, scanned: picked.length);

    // 删除检测：web 源不做（并集语义，只增不删），与 folder「文件真没了才删」
    // 保持同向。原因：web 身份键无法证明「这次没选中 = 盘上没了」——
    // 降级路径的键只有文件名（记不住目录），主路径每次也只遍历用户这次选的
    // 子树；按「未选中即已删」处理，先导入 100 张再补选 3 张会立刻把前 97 张
    // 清出索引（静默丢照）。任务书/规格中也没有「以最后一次导入为准」的约定。

    var scanned = 0;
    var added = 0;
    for (var start = 0; start < picked.length; start += _batchSize) {
      final batch = picked.sublist(start, min(start + _batchSize, picked.length));
      yield ScanProgress(
        phase: ScanPhase.parsing,
        scanned: scanned,
        added: added,
        currentPath: batch.first.relativePath,
      );
      final fresh = <Photo>[];
      for (final f in batch) {
        final path = 'web://${f.relativePath}';
        if (knownPathToMtime[path] == f.mtimeMs) continue; // 增量：未变即跳过
        fresh.add(Photo(
          path: path,
          fileSize: f.sizeBytes,
          mtimeMs: f.mtimeMs,
          takenAtMs: f.mtimeMs, // Web 无 EXIF（dart:io 限制），回退 lastModified
          dayKey: dayKeyOf(DateTime.fromMillisecondsSinceEpoch(f.mtimeMs)),
          sourceId: source.id,
        ));
      }
      if (fresh.isNotEmpty) {
        await _sink.onPhotos(fresh);
        added += fresh.length;
      }
      scanned += batch.length;
      yield ScanProgress(
        phase: ScanPhase.indexing,
        scanned: scanned,
        added: added,
        currentPath: batch.last.relativePath,
      );
    }

    yield ScanProgress(phase: ScanPhase.done, scanned: scanned, added: added);
  }

  // —— 主路径：showDirectoryPicker 递归遍历 ————————————————————————

  Future<List<_WebPickFile>?> _pickDirectory() async {
    final window = web.window as JSObject;
    // 先取函数引用再调用：Firefox 未实现该 API 时属性为 undefined，直接调会抛 TypeError
    final pickerFn = window.getProperty<JSFunction?>('showDirectoryPicker'.toJS);
    if (pickerFn == null) return null;

    final handle = await _await(
      pickerFn.callAsFunction(window) as JSPromise<JSObject>,
    );
    final out = <_WebPickFile>[];
    await _walk(handle, '', out);
    return out;
  }

  /// 目录句柄的异步迭代协议：handle.values → iterator.next() → {done, value}。
  /// package:web 未导出 values/getFile 句柄细节，这里用 js_interop_unsafe 手搓协议。
  Future<void> _walk(
    JSObject dirHandle,
    String prefix,
    List<_WebPickFile> out,
  ) async {
    if (out.length >= _maxFiles) return;
    final valuesFn = dirHandle.getProperty<JSFunction>('values'.toJS);
    final iterator = valuesFn.callAsFunction(dirHandle)! as JSObject;
    final nextFn = iterator.getProperty<JSFunction>('next'.toJS);

    while (out.length < _maxFiles) {
      final step =
          await _await(nextFn.callAsFunction(iterator) as JSPromise<JSObject>);
      // IteratorResult.done 缺失时按结束处理，避免空值强转炸掉整次扫描
      if ((step['done'] as JSBoolean?)?.toDart ?? true) break;

      final entry = step['value'] as JSObject?;
      if (entry == null) break;
      final kind = (entry['kind'] as JSString?)?.toDart ?? '';
      final name = (entry['name'] as JSString?)?.toDart ?? '';

      if (kind == 'directory') {
        if (isHiddenOrSystemName(name)) continue;
        await _walk(entry, '$prefix$name/', out);
      } else if (kind == 'file' && isPhotoFileName(name)) {
        final getFile = entry['getFile'] as JSFunction?;
        if (getFile == null) continue;
        final file = await _await(
          getFile.callAsFunction(entry) as JSPromise<JSObject>,
        );
        // 只取元数据、绝不 arrayBuffer()：Web 缩略图生成恒返回 null，这些字节
        // 没有任何下游用途，而每张 1-8MB 原片读进 Dart 堆驻留到扫描结束，
        // 几百张就足以把标签页 OOM 掉。size 是 File 自带属性，零拷贝。
        var sizeBytes = 0;
        try {
          sizeBytes = file
              .getProperty<JSNumber>('size'.toJS)
              .toDartDouble
              .toInt();
        } catch (_) {/* 取不到就记 0，只影响列表展示的大小 */}

        // File.lastModified 是属性：用带类型的 getProperty 直取，
        // 异常（缺失/类型不符）时兜底当前时刻，避免 JS 类型 is 检查的跨端不一致
        var mtimeMs = DateTime.now().millisecondsSinceEpoch;
        try {
          mtimeMs = file
              .getProperty<JSNumber>('lastModified'.toJS)
              .toDartDouble
              .toInt();
        } catch (_) {/* 取不到就用 now */}
        out.add(_WebPickFile('$prefix$name', sizeBytes, mtimeMs));
      }
    }
  }

  // —— 降级路径：file_picker 多选 ————————————————————————————————

  Future<List<_WebPickFile>?> _pickManyFallback() async {
    try {
      // file_picker 13 起 pickFiles 是 FilePicker 的静态方法（无 .platform 中转）；
      // 取消时返回空列表而不是 null
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty) return null; // 用户取消
      final now = DateTime.now().millisecondsSinceEpoch;
      final out = <_WebPickFile>[];
      for (final f in result) {
        // 与主路径同理：只取元数据，不 readAsBytes 拉整图进堆。
        // web 实现里 lengthSync 直接来自浏览器 File.size，不触发任何 IO
        var sizeBytes = 0;
        try {
          sizeBytes = f.lengthSync() ?? await f.length() ?? 0;
        } catch (_) {/* 取不到就记 0，只影响列表展示的大小 */}
        var mtimeMs = now;
        try {
          mtimeMs = (await f.xFile.lastModified()).millisecondsSinceEpoch;
        } catch (_) {/* 部分浏览器不暴露 lastModified → 用 now */}
        out.add(_WebPickFile(f.name, sizeBytes, mtimeMs));
      }
      return out;
    } catch (_) {
      return null; // 取消或插件异常都按「没选到」处理，不打断流程
    }
  }

  Future<JSObject> _await(JSPromise<JSObject> promise) => promise.toDart;
}

/// Web 扫描的中间产物：相对路径 + 字节数 + 修改时间。
/// 刻意不保存文件字节：扫描只需 fileSize/mtime 建索引，Web 缩略图恒走占位，
/// 字节读进来也没有消费方；全程驻留只会放大 OOM 风险。
class _WebPickFile {
  const _WebPickFile(this.relativePath, this.sizeBytes, this.mtimeMs);

  final String relativePath;
  final int sizeBytes;
  final int mtimeMs;
}
