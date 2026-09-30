/// 增量扫描测试：在临时目录造几个「EXIF 必然解析失败」的假 jpg，
/// 走完整的 ScannerServiceImpl 链路验证三件事：
/// ① 首扫全量入库（EXIF 失败回退 mtime，takenAt == mtime）；
/// ② 二扫零新增（knownPathToMtime 命中即跳过，added == 0）；
/// ③ 改 mtime 再扫恰好 1 新增、删除文件后索引同步收缩。
///
/// 顺带锁定：隐藏目录/非图片扩展名被过滤、桌面宿主 gallerySupported == false。
///
/// 二轮修复补的常驻回归（原为一次性探针，防再次无预警回归）：
/// ④ 根目录被删后重扫 = error 且索引不收缩（「读不到 ≠ 删了」根目录版）；
/// ⑤ 子目录 ACL 拒绝访问：listPhotoEntries 不抛错、.git 被剪枝、
///    失败分支以 failedDirs 回报且其下已知文件不清出（分支版同原则，
///    只在 Windows 上跑——需要 icacls 造真实拒绝访问），
///    且扫描收尾帧把跳过项计数进 ScanProgressWithSkips（跳过不能无声）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/models/models.dart';
import 'package:shiguang_handbook/core/scanning/folder_scanner.dart';
import 'package:shiguang_handbook/core/scanning/scanner_contracts.dart';
import 'package:shiguang_handbook/core/scanning/scanner_service.dart';
import 'package:shiguang_handbook/core/storage/photo_index_store.dart';

void main() {
  late Directory root;
  late InMemoryPhotoIndexStore store;
  late ScannerServiceImpl service;
  late PhotoSource source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('shiguang_scan_');
    store = InMemoryPhotoIndexStore();
    await store.init();
    service = ScannerServiceImpl(store);
    final id = await store.addSource(
      PhotoSource(type: SourceType.folder, path: root.path),
    );
    source = (await store.loadSources()).firstWhere((s) => s.id == id);
  });

  tearDown(() async {
    await store.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 假 jpg：非 JPEG 魔数开头 → package:exif 判定格式无法识别 → 必然走 mtime 回退。
  List<int> fakeJpeg(int seed) =>
      List<int>.generate(96, (i) => (seed * 37 + i * 17 + 5) & 0xff);

  void writePhoto(String name, {int seed = 1}) =>
      File('${root.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(fakeJpeg(seed));

  test('桌面宿主上相册扫描不可用（UI 据此隐藏入口）', () {
    expect(service.gallerySupported, isFalse, reason: '测试宿主是桌面平台');
  });

  test('首扫全量 / 二扫 0 新增 / 改 mtime 后 1 新增（EXIF 失败回退 mtime）',
      () async {
    writePhoto('a.jpg', seed: 1);
    writePhoto('b.jpg', seed: 2);
    writePhoto('c.png', seed: 3);
    // 必须被过滤：隐藏目录 + 非图片扩展名
    Directory('${root.path}${Platform.pathSeparator}.hidden')
        .createSync(recursive: true);
    File('${root.path}${Platform.pathSeparator}.hidden${Platform.pathSeparator}secret.jpg')
        .writeAsBytesSync(fakeJpeg(9));
    File('${root.path}${Platform.pathSeparator}note.txt')
        .writeAsStringSync('不是照片');

    // —— 首扫：全量 ——
    final first = await service.scanSource(source).toList();
    expect(first.last.phase, ScanPhase.done, reason: '必须以 done 收尾');
    expect(first.last.added, 3, reason: '隐藏目录与 txt 被过滤后恰好 3 张');
    expect(first.last.scanned, 3);
    expect(
      first.any((p) => p.phase == ScanPhase.parsing),
      isTrue,
      reason: '增量为空的首扫必须走 parsing 阶段',
    );

    final photos = <Photo>[
      for (final dayKey in store.dayIndex.keys) ...await store.photosOfDay(dayKey),
    ];
    expect(photos, hasLength(3));
    for (final p in photos) {
      expect(
        p.takenAtMs,
        p.mtimeMs,
        reason: '假 jpg 无 EXIF：拍摄时间必须回退文件 mtime（${p.path}）',
      );
      expect(p.dayKey, dayKeyOf(DateTime.fromMillisecondsSinceEpoch(p.mtimeMs)));
    }

    // markSourceScanned 已由门面写回
    expect((await store.loadSources()).single.lastScanMs, isNotNull);

    // —— 二扫：0 新增 ——
    final second = await service.scanSource(source).toList();
    expect(second.last.phase, ScanPhase.done);
    expect(second.last.added, 0, reason: 'mtime 未变 → knownPathToMtime 全命中，零新增');
    expect(second.last.scanned, 3);
    expect(await _totalPhotos(store), 3, reason: '二扫不得产生重复记录');

    // —— 改 mtime：恰好 1 新增 ——
    final oldA = (await _allPhotos(store)).firstWhere((p) => p.path.endsWith('a.jpg'));
    final touched = DateTime.now().add(const Duration(minutes: 7));
    File('${root.path}${Platform.pathSeparator}a.jpg')
        .setLastModifiedSync(touched);
    final third = await service.scanSource(source).toList();
    expect(third.last.phase, ScanPhase.done);
    expect(third.last.added, 1, reason: '仅被改动的 a.jpg 重新解析入库');
    expect(await _totalPhotos(store), 3, reason: '同路径覆盖，总数不变');

    final dayOfA = (await _allPhotos(store))
        .firstWhere((p) => p.path.endsWith('a.jpg'));
    expect(
      (dayOfA.mtimeMs - touched.millisecondsSinceEpoch).abs(),
      lessThan(2000),
      reason: '新 mtime 已落库（允许文件系统毫秒级精度差）',
    );
    expect(dayOfA.mtimeMs, isNot(oldA.mtimeMs), reason: 'mtime 确实发生了变化');
    expect(dayOfA.takenAtMs, dayOfA.mtimeMs, reason: '改动后的文件同样回退 mtime');
  });

  test('删除文件后再扫：索引同步收缩（删除检测）', () async {
    writePhoto('a.jpg', seed: 1);
    writePhoto('b.jpg', seed: 2);
    await service.scanSource(source).toList();
    expect(await _totalPhotos(store), 2);

    File('${root.path}${Platform.pathSeparator}b.jpg').deleteSync();
    final rescan = await service.scanSource(source).toList();
    expect(rescan.last.phase, ScanPhase.done);
    expect(rescan.last.added, 0);
    expect(await _totalPhotos(store), 1, reason: '盘上消失的文件必须从索引移除');
    expect(store.dayIndex.values.fold<int>(0, (sum, m) => sum + m.photoCount), 1);
  });

  test('根目录被删后重扫：error 收尾且索引不收缩（读不到≠删了）', () async {
    writePhoto('a.jpg', seed: 1);
    writePhoto('b.jpg', seed: 2);
    final first = await service.scanSource(source).toList();
    expect(first.last.phase, ScanPhase.done);
    expect(await _totalPhotos(store), 2);

    // 模拟外置盘拔出/路径失效：根目录整体消失
    root.deleteSync(recursive: true);
    final rescan = await service.scanSource(source).toList();
    expect(rescan.last.phase, ScanPhase.error,
        reason: '根目录不存在必须报错，绝不能当「空目录」走删除检测');
    expect(rescan.last.errorMessage, contains(root.path),
        reason: '错误信息要带上路径，方便用户排查是哪个源');
    expect(await _totalPhotos(store), 2,
        reason: '一次读不到不得清空历史索引——盘挂回来照片还得在');
    // error 帧不打新时间戳：首扫时间戳保留，没扫完就标已扫会掩盖问题
    expect((await store.loadSources()).single.lastScanMs, isNotNull);
  });

  test(
    '子目录拒绝访问：listPhotoEntries 不抛错、.git 剪枝、失败分支不清出索引',
    () async {
      final sep = Platform.pathSeparator;
      // 造两支对照：denied（稍后 ACL 拒绝）、.git（隐藏剪枝，永远不进）
      final deniedDir = Directory('${root.path}${sep}denied')..createSync();
      File('${deniedDir.path}${sep}x.jpg').writeAsBytesSync(fakeJpeg(7));
      final gitDir = Directory('${root.path}$sep.git')..createSync();
      File('${gitDir.path}${sep}secret.jpg').writeAsBytesSync(fakeJpeg(8));
      writePhoto('a.jpg', seed: 1);

      // 首扫时 denied 还可读：恰好 2 张（.git 被剪枝过滤）
      final first = await service.scanSource(source).toList();
      expect(first.last.phase, ScanPhase.done);
      expect(first.last.added, 2, reason: '.git/secret.jpg 必须被隐藏目录剪枝挡下');
      expect(await _totalPhotos(store), 2);

      // 用真实 ACL 拒绝制造「读不到」——手工 mock 覆盖不到 dart:io 的真实异常路径。
      // 用 Everyone 的 SID（*S-1-1-0）而非名称，中文系统 icacls 也能解析
      final deny = await Process.run(
        'icacls',
        [deniedDir.path, '/deny', '*S-1-1-0:F'],
      );
      expect(deny.exitCode, 0, reason: 'icacls 施加拒绝失败：${deny.stderr}');
      try {
        // ① 底层枚举：拒绝目录整支不抛错，失败前缀以 failedDirs 回报
        final listing = listPhotoEntries(root.path);
        expect(
          listing.entries.any((e) => e.path.endsWith('a.jpg')),
          isTrue,
          reason: '未受影响分支照常枚举',
        );
        expect(
          listing.entries.any((e) => e.path.contains('${sep}denied$sep')),
          isFalse,
          reason: '拒绝目录内的文件枚举不到（预期），但整体不得抛错',
        );
        expect(
          listing.failedDirs,
          contains(deniedDir.path),
          reason: '失败前缀必须回报，删除检测才能排除该分支',
        );
        expect(
          listing.entries.any((e) => e.path.contains('$sep.git$sep')),
          isFalse,
          reason: '.git 整棵子树被剪枝，不进枚举也不占失败清单',
        );
        expect(listing.unreadableFiles, isEmpty, reason: '本场景只有目录级失败');

        // ② 全链路重扫：单分支拒绝不炸整次扫描，且分支下已知文件不清出
        final rescan = await service.scanSource(source).toList();
        expect(rescan.last.phase, ScanPhase.done,
            reason: '单个子目录无权限只跳过该分支，不得让整次扫描失败');
        expect(rescan.last.added, 0);
        expect(
          await _totalPhotos(store),
          2,
          reason: 'denied/x.jpg 只是本轮读不到，不是删了——权限恢复前索引必须保留',
        );
        expect(
          (await _allPhotos(store)).any((p) => p.path.endsWith('a.jpg')),
          isTrue,
        );

        // ③ 收尾帧把跳过项计数进 ScanProgress：跳过不能无声，
        //    上层据此可知「本轮有几处没扫到」（ScanProgressWithSkips 子类携带）
        final done = rescan.last;
        expect(done, isA<ScanProgressWithSkips>(),
            reason: 'folder 扫描收尾必须是带跳过计数的帧');
        final skips = done as ScanProgressWithSkips;
        expect(skips.skippedDirs, 1,
            reason: '恰好 denied 一支因无权限被跳过，计数进收尾帧');
        expect(skips.skippedFiles, 0, reason: '本场景无文件级 stat 失败');
        expect(skips.skippedTotal, 1);
      } finally {
        // 恢复继承 ACL：否则 tearDown 的递归删除会因 DELETE 被拒而炸
        final reset = await Process.run('icacls', [deniedDir.path, '/reset']);
        expect(reset.exitCode, 0, reason: 'icacls 恢复失败：${reset.stderr}');
      }
    },
    skip: Platform.isWindows ? false : '仅 Windows：需要 icacls 造真实拒绝访问 ACL',
  );
}

Future<int> _totalPhotos(PhotoIndexStore store) async {
  final photos = await _allPhotos(store);
  return photos.length;
}

Future<List<Photo>> _allPhotos(PhotoIndexStore store) async {
  final out = <Photo>[];
  for (final dayKey in store.dayIndex.keys) {
    out.addAll(await store.photosOfDay(dayKey));
  }
  return out;
}
