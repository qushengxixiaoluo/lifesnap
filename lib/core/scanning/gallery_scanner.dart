/// 手机相册扫描器（photo_manager）。
///
/// 关键取舍：
/// - 走 AssetEntity.createDateTime 而不是读 EXIF：photo_manager 相册侧已建好
///   创建时间索引，免去把原图拉回 Dart 层解析，几万张相册也只要分页枚举；
/// - 增量身份用 assetId（路径 pm://assetId）：同一张图 id 恒定，二扫时
///   knownPathToMtime 命中即跳过，只对新增/时间被修正的资产重建记录；
/// - fileSize 只能填 0：photo_manager 3.12 没有轻量的字节数 API，
///   拉原图取大小得不偿失，签名 path|mtime|0 依旧稳定（详见 deviations）。
///
/// 本文件 import dart:io 与 photo_manager，仅能被 io 分支编译；
/// 桌面/Web 通过 supported=false（运行时判断）与条件导入（编译期）双重兜底。
library;

import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../models/models.dart';
import 'scan_sink.dart';
import 'scanner_contracts.dart';

class GalleryScanner implements PhotoSourceScanner {
  GalleryScanner({required PhotoScanSink sink}) : _sink = sink;

  final PhotoScanSink _sink;

  /// 相册能力仅移动端开放：桌面平台 photo_manager 没有插件实现，
  /// macOS 虽有 PhotoKit 但按本产品设计归入「桌面 → 用文件夹扫描」。
  static bool get platformSupported => Platform.isAndroid || Platform.isIOS;

  @override
  bool get supported => platformSupported;

  @override
  Stream<ScanProgress> scan(
    PhotoSource source, {
    required Map<String, int> knownPathToMtime,
  }) async* {
    if (!platformSupported) {
      yield const ScanProgress(
        phase: ScanPhase.error,
        errorMessage: '当前平台不支持相册扫描，请改用文件夹扫描',
      );
      return;
    }

    yield const ScanProgress(phase: ScanPhase.listing);

    // 权限流：requestPermissionExtend 一次完成 询问/跳转设置/返回状态 的闭环。
    // 已知坑：国产 ROM（MIUI/ColorOS 等）从系统设置授权后返回应用，
    // photo_manager 的权限状态往往还停在旧值——所以首次读到「无权限」时
    // 不立刻判死，等一拍重查一次再下结论。
    var permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      permission = await PhotoManager.requestPermissionExtend();
    }
    if (!permission.hasAccess) {
      yield ScanProgress(
        phase: ScanPhase.error,
        errorMessage:
            '相册权限未生效。请到 系统设置→应用→拾光手册→权限 允许「照片和视频」，'
            '若选了「仅选定的照片」请选择全部；授权后完全关闭本应用再重新打开扫描。'
            '（当前状态：${permission.name}）',
      );
      return;
    }

    // 权限之后的查询也可能抛 PermissionException（部分 ROM 授权瞬间查询会炸），
    // 统一兜底成中文可操作提示，而不是把原始异常甩给用户
    final List<AssetPathEntity> albums;
    try {
      albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true, // 只要「最近项目」全量视图，避免遍历每个相册造成重复
      );
    } catch (e) {
      yield ScanProgress(
        phase: ScanPhase.error,
        errorMessage: '读取相册列表失败（$e）。请完全退出应用后重试；'
            '若仍失败，检查系统设置中是否授予了「照片和视频」权限。',
      );
      return;
    }
    if (albums.isEmpty) {
      yield const ScanProgress(phase: ScanPhase.done);
      return;
    }
    final album = albums.first;

    var scanned = 0;
    var added = 0;
    var page = 0;
    const pageSize = 200;
    final present = <String>{};

    while (true) {
      final assets =
          await album.getAssetListPaged(page: page, size: pageSize);
      if (assets.isEmpty) break;
      page++;

      final fresh = <Photo>[];
      for (final asset in assets) {
        final path = 'pm://${asset.id}';
        present.add(path);
        scanned++;

        final takenAt = asset.createDateTime;
        final mtimeMs = takenAt.millisecondsSinceEpoch;
        // assetId 增量：已知且创建时间一致 → 跳过；时间被系统修正过则重建
        if (knownPathToMtime[path] == mtimeMs) continue;

        fresh.add(Photo(
          path: path,
          fileSize: 0, // 见文件头：3.12 无轻量字节数 API，以 0 占位保签名稳定
          mtimeMs: mtimeMs,
          takenAtMs: mtimeMs,
          dayKey: dayKeyOf(takenAt),
          sourceId: source.id,
          width: asset.width,
          height: asset.height,
        ));
      }

      if (fresh.isNotEmpty) {
        await _sink.onPhotos(fresh);
        added += fresh.length;
      }
      yield ScanProgress(
        phase: ScanPhase.parsing,
        scanned: scanned,
        added: added,
        currentPath: assets.last.id,
      );
      if (assets.length < pageSize) break;
    }

    // 删除检测：系统相册里已删掉的资产要从索引里同步移除
    final removed = [
      for (final knownPath in knownPathToMtime.keys)
        if (!present.contains(knownPath)) knownPath,
    ];
    if (removed.isNotEmpty) await _sink.onRemoved(removed);

    yield ScanProgress(phase: ScanPhase.indexing, scanned: scanned, added: added);
    yield ScanProgress(phase: ScanPhase.done, scanned: scanned, added: added);
  }
}
