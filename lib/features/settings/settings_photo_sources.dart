/// 设置页 · 照片源分区（E 轨）。
///
/// 职责：来源列表（含上次扫描时间）、添加/删除文件夹、手机相册开关、
/// 单源/全部重扫，以及 ScanProgress 的实时进度与中文文案。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_style.dart';
import '../../app/providers.dart';
import '../../core/models/models.dart';
import '../../core/storage/photo_index_store.dart';
import 'settings_utils.dart';

class PhotoSourceSection extends ConsumerStatefulWidget {
  const PhotoSourceSection({super.key});

  @override
  ConsumerState<PhotoSourceSection> createState() =>
      _PhotoSourceSectionState();
}

class _PhotoSourceSectionState extends ConsumerState<PhotoSourceSection> {
  PhotoIndexStore? _store;
  Future<List<PhotoSource>>? _sourcesFuture;
  StreamSubscription<ScanProgress>? _scanSub;
  ScanProgress? _scan;
  String? _opError; // 添加/删除等操作的失败提示

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  /// 绑定当前 store 并建立列表 future。
  ///
  /// 不能每次 build 都调 store.loadSources()：FutureBuilder 换了 future
  /// 就会退回 loading 态，界面每帧闪一次转圈。
  void _bind(PhotoIndexStore store) {
    if (!identical(_store, store)) {
      _store = store;
      _sourcesFuture = store.loadSources();
    }
  }

  void _reload() {
    final store = _store;
    if (store == null) return;
    setState(() => _sourcesFuture = store.loadSources());
  }

  // ------------------------------------------------------------ 增删

  Future<void> _addFolder() async {
    try {
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: '选择照片文件夹',
      );
      if (dir == null || dir.isEmpty) return; // 用户取消：不打扰
      await _store!.addSource(PhotoSource(type: SourceType.folder, path: dir));
      if (!mounted) return;
      setState(() => _opError = null);
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _opError = '添加文件夹失败：$e');
    }
  }

  Future<void> _confirmDelete(PhotoSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('删除照片源'),
        content: Text(
          '确定移除「${source.displayName}」吗？\n该来源已扫描的照片索引也会一并删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      await _store!.removeSource(source.id);
      if (!mounted) return;
      setState(() => _opError = null);
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _opError = '删除失败：$e');
    }
  }

  Future<void> _toggleGallery(List<PhotoSource> gallery, bool on) async {
    final store = _store;
    if (store == null) return;
    // 双保险：开关禁用只是 UI 层，这里再挡一次。scanAll 在流开头就快照了
    // 源列表，此刻 removeSource 删源后扫描仍会 upsert 照片，把照片写回
    // 已删除的 sourceId → 产生无来源可管理的孤儿索引（删除按钮防的正是这个）。
    // _startScan 在点击当刻就同步置了占位帧，所以这道闸从扫描启动瞬间起
    // 就生效，连重建前的同帧双击也挡得住。
    if (_scan != null && !_scan!.finished) return;
    try {
      if (on) {
        // 开：没有相册源就补一个（path 约定 'gallery'，见 models.dart）
        if (gallery.isEmpty) {
          await store.addSource(
            const PhotoSource(type: SourceType.gallery, path: 'gallery'),
          );
        }
      } else {
        for (final g in gallery) {
          await store.removeSource(g.id);
        }
      }
      if (!mounted) return;
      setState(() => _opError = null);
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _opError = '相册开关切换失败：$e');
    }
  }

  // ------------------------------------------------------------ 扫描

  void _startScan(Stream<ScanProgress> stream) {
    _scanSub?.cancel();
    // 点击当刻就置一枚「扫描中」占位帧，而不是像原先那样清成 null 等首帧：
    // 进度流的第一个事件要等扫描器枚举一阵子才来，这段[listen → 首帧]空窗里
    // scanning 仍为 false——而 scanAll 恰在 listen 时就快照了源列表，此刻关相册
    // 触发 removeSource 正会留下孤儿索引（原审查竞态在空窗里复现）。占位帧让
    // 开关/删除/扫描按钮的 UI 置灰与 _toggleGallery 的双保险从点击当刻起就
    // 生效，不依赖重建时序；首帧到达后由下方监听回调自然覆盖。
    setState(() {
      _scan = const ScanProgress(phase: ScanPhase.listing);
    });
    _scanSub = stream.listen(
      (p) {
        if (!mounted) return;
        setState(() => _scan = p);
        // 扫描会改 lastScanMs 与照片集合：完成后重读来源列表
        if (p.finished) _reload();
      },
      onError: (Object e) {
        if (!mounted) return;
        // 底层扫描器抛非 ScanProgress 异常时，降级成一条错误进度帧展示
        setState(() {
          _scan = ScanProgress(
            phase: ScanPhase.error,
            scanned: _scan?.scanned ?? 0,
            added: _scan?.added ?? 0,
            errorMessage: '$e',
          );
        });
      },
      onDone: () {
        if (!mounted) return;
        // 契约防御：流关闭却始终没推过 done/error 收尾帧时，把占位帧补成
        // finished——否则 scanning 永远为 true，本区所有控件会被永久锁死，
        // 比竞态更糟。正常路径下收尾帧先于 done 事件到达，此分支不会进。
        final cur = _scan;
        if (cur != null && !cur.finished) {
          setState(() {
            _scan = ScanProgress(
              phase: ScanPhase.done,
              scanned: cur.scanned,
              added: cur.added,
            );
          });
        }
        _reload();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(photoStoreProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(context, Icons.photo_library_outlined, '照片源',
            subtitle: '选择要被拾光手册记录的照片位置'),
        const SizedBox(height: 12),
        storeAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('照片库载入失败：$err',
                  style: const TextStyle(color: ShiguangColors.danger)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(photoStoreProvider),
                  child: const Text('重试'),
                ),
              ),
            ],
          ),
          data: (store) {
            _bind(store);
            return _buildLoaded(context, theme);
          },
        ),
        if (_opError != null) ...[
          const SizedBox(height: 8),
          Text(_opError!,
              style: const TextStyle(color: ShiguangColors.danger, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildLoaded(BuildContext context, ThemeData theme) {
    return FutureBuilder<List<PhotoSource>>(
      future: _sourcesFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('照片源列表读取失败：${snap.error}',
              style: const TextStyle(color: ShiguangColors.danger));
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final sources = snap.data!;
        final gallery =
            sources.where((s) => s.type == SourceType.gallery).toList();
        final scanning = _scan != null && !_scan!.finished;
        final gallerySupported = ref.read(scannerServiceProvider).gallerySupported;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sources.isEmpty)
              Text('还没有照片源，先「添加文件夹」或开启手机相册',
                  style: theme.textTheme.bodySmall),
            for (final s in sources) _sourceRow(context, s, scanning),
            if (isMobilePlatform) ...[
              const Divider(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('手机相册'),
                subtitle: Text(
                  gallerySupported
                      ? '开启后，重新扫描会一并读取系统相册'
                      : '当前平台不支持手机相册（扫描服务未接入）',
                ),
                value: gallery.isNotEmpty && gallery.first.enabled,
                // gallerySupported=false 时锁死开关，避免用户开了却扫不出东西；
                // 扫描中同样锁死：关相册会同步删源及其照片，与正在进行的
                // scanAll（已快照源列表）赛跑会留下孤儿索引
                onChanged: (gallerySupported && !scanning)
                    ? (v) => _toggleGallery(gallery, v)
                    : null,
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: scanning ? null : _addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('添加文件夹'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      scanning || sources.isEmpty ? null : () => _startScan(ref.read(scannerServiceProvider).scanAll()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(scanning ? '扫描中…' : '重新扫描'),
                ),
              ],
            ),
            if (_scan != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _scan!.finished ? 1 : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text(
                _scanText(_scan!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _scan!.phase == ScanPhase.error
                      ? ShiguangColors.danger
                      : null,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _sourceRow(BuildContext context, PhotoSource s, bool scanning) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            s.type == SourceType.gallery
                ? Icons.photo_library_outlined
                : Icons.folder_open_outlined,
            size: 20,
            color: ShiguangColors.wood,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.displayName, style: theme.textTheme.bodyMedium),
                Text(
                  // 未扫描过给「尚未扫描」，比展示 1970 年友好
                  s.lastScanMs == null
                      ? '尚未扫描'
                      : '上次扫描 ${formatTimeMs(s.lastScanMs!)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: scanning
                ? null
                : () => _startScan(
                      ref.read(scannerServiceProvider).scanSource(s),
                    ),
            child: const Text('扫描'),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: scanning ? null : () => _confirmDelete(s),
          ),
        ],
      ),
    );
  }

  String _scanText(ScanProgress p) {
    final counts = '已检查 ${p.scanned} 张 · 新增 ${p.added} 张';
    switch (p.phase) {
      case ScanPhase.listing:
        return '正在枚举照片… $counts';
      case ScanPhase.parsing:
        return '正在解析拍摄时间… $counts';
      case ScanPhase.indexing:
        return '正在写入索引… $counts';
      case ScanPhase.done:
        return '扫描完成：$counts';
      case ScanPhase.error:
        return '扫描失败：${p.errorMessage ?? '未知错误'}';
      case ScanPhase.idle:
        return counts;
    }
  }
}
