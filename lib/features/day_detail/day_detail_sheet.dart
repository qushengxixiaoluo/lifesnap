/// 日详情底部面板内容（E 轨交付）。
///
/// 数据装配：从 photoStoreProvider 拿到存储后，用 photosOfDay + summaryOf 组成
/// [DayRecord]；并把 summary.photoSig 与 computePhotoSig(photos) 对比得到 stale
/// ——照片被增删改后，AI 总结卡顶部会横幅提示「照片有更新，点击重新生成」。
///
/// 结构（自上而下）：日期标题 → AI 总结卡 → 照片网格 → 生成按钮。
/// 三类空态：未来日期 / 有照片无总结 / 无照片空日。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_style.dart';
import '../../app/providers.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/models/models.dart';
import '../../core/storage/photo_index_store.dart';
import '../../core/thumbnails/thumb_image.dart';
import '../../widgets/hand_card.dart';
import '../settings/settings_page.dart';
import 'edit_summary_dialog.dart';
import 'photo_viewer.dart';
import 'share_card.dart';

/// 展开某一天详情的底部面板（由 day_detail_launcher 嵌进 DraggableScrollableSheet）。
class DayDetailSheet extends ConsumerStatefulWidget {
  /// 目标日期主键 yyyymmdd。
  final int dayKey;

  /// 由 DraggableScrollableSheet 下发的滚动控制器：面板拖拽与内容滚动共用一套
  /// 手势，避免「拖面板」和「滑内容」打架。
  final ScrollController scrollController;

  const DayDetailSheet({
    super.key,
    required this.dayKey,
    required this.scrollController,
  });

  @override
  ConsumerState<DayDetailSheet> createState() => _DayDetailSheetState();
}

/// 组装某日完整数据包：当日照片 + 缓存总结 + 失效标记。
///
/// stale 判定放在这里统一做，面板与将来的分享/导出路径共用同一语义。
Future<DayRecord> loadDayRecord(PhotoIndexStore store, int dayKey) async {
  final photos = await store.photosOfDay(dayKey);
  final summary = await store.summaryOf(dayKey);
  // photo_sig 不一致 → 照片集合变过，旧总结只能算「过期草稿」
  final stale =
      summary != null && summary.photoSig != computePhotoSig(photos);
  return DayRecord(
    dayKey: dayKey,
    photos: photos,
    summary: summary,
    summaryStale: stale,
  );
}

class _DayDetailSheetState extends ConsumerState<DayDetailSheet> {
  /// 缓存存储实例：生成成功后要拿同一实例重读，不能中途换容器。
  PhotoIndexStore? _store;

  Future<DayRecord>? _recordFuture;
  bool _generating = false;
  String? _notice; // 生成失败等行内提示（放行内而不是 SnackBar：SnackBar 会被面板盖住）

  void _bindStore(PhotoIndexStore store) {
    if (!identical(_store, store)) {
      _store = store;
      _recordFuture = loadDayRecord(store, widget.dayKey);
    }
  }

  void _reloadRecord() {
    if (_store == null) return;
    setState(() {
      _recordFuture = loadDayRecord(_store!, widget.dayKey);
      _notice = null;
    });
  }

  /// 「生成今日总结」/ stale 横幅的统一入口。
  ///
  /// 先查 key 再发请求：没有 key 时白跑一次网络只会得到 401，
  /// 直接弹窗引导去设置页更省事。
  Future<void> _generate({required bool force}) async {
    if (_generating || _store == null) return;
    // 进门就同步上闩：ApiKeyStore.exists 是异步的，若等它回来再置
    // _generating，这段空窗里按钮仍可点，快速双击（或 stale 横幅与底部
    // 按钮同时触发）会让两次都穿过守卫、各发一次 repo.generate——缓存
    // 尚未写回前产生重复 API 请求，双倍花费。
    setState(() {
      _generating = true;
      _notice = null;
    });

    final bool hasKey;
    try {
      hasKey = await ApiKeyStore.exists();
    } catch (e) {
      // 查 key 本身炸了也要复位，否则按钮永久卡在「正在生成…」
      if (mounted) {
        setState(() {
          _generating = false;
          _notice = '读取 API Key 失败：$e';
        });
      }
      return;
    }
    // widget 已销毁：State 随之丢弃，无须（也不能）再 setState 复位
    if (!mounted) return;
    if (!hasKey) {
      // 无 key：先解锁再弹引导，弹窗期间用户仍可操作面板
      setState(() => _generating = false);
      await _showKeyGuide();
      return;
    }

    // 读 key 之后才碰 WidgetRef：dispose 后不能再读 provider
    final repo = ref.read(summaryRepositoryProvider);
    final store = _store!;
    try {
      final record = await loadDayRecord(store, widget.dayKey);
      await repo.generate(record: record, force: force);
      if (!mounted) return;
      setState(() {
        _generating = false;
        _recordFuture = loadDayRecord(store, widget.dayKey);
      });
    } on AiException catch (e) {
      // D 轨适配器抛出的中文文案直接展示，不再二次翻译
      if (mounted) {
        setState(() {
          _generating = false;
          _notice = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _notice = '生成失败：$e';
        });
      }
    }
  }

  /// 编辑总结：落库经对话框的 onSave 回调完成（失败留在对话框内提示），
  /// 保存成功返回后重载本日记录刷新卡片。
  /// photo_sig 不变，编辑不会把总结标成「照片有更新」。
  Future<void> _editSummary(AiSummary summary) async {
    if (_store == null) return;
    final store = _store!;
    final edited = await showEditSummaryDialog(
      context,
      summary,
      onSave: store.putSummary,
    );
    if (edited == null || !mounted) return;
    _reloadRecord();
  }

  /// 导出分享卡片：离屏渲染 750×1000 PNG 并写本地。
  /// 结果走 _notice 行内提示（SnackBar 会被本面板盖住，见字段注释）。
  Future<void> _exportShareCard(DayRecord record) async {
    try {
      final path = await exportDayShareCard(context, record);
      if (!mounted) return;
      setState(() {
        _notice = path == null ? '导出失败：当天没有总结' : '已导出：$path';
      });
    } catch (e) {
      if (mounted) setState(() => _notice = '导出失败：$e');
    }
  }

  Future<void> _showKeyGuide() async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('还差一步'),
        content: const Text('尚未保存 API Key。请先到设置页填入 API Key，再回来生成今日总结。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              // 跳到设置页；当前面板留在下面，填完 key 返回即可继续
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(photoStoreProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: ShiguangColors.wood.withValues(alpha: 0.55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: storeAsync.when(
        loading: () => _scrollShell([
          _handleBar(context),
          const SizedBox(height: 64),
          const Center(child: CircularProgressIndicator()),
        ]),
        error: (err, _) => _scrollShell([
          _handleBar(context),
          HandCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '照片库载入失败',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('$err', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(photoStoreProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ]),
        data: (store) {
          _bindStore(store);
          return _buildLoaded(context);
        },
      ),
    );
  }

  /// 统一滚动容器：所有状态共用 sheet 下发的 controller。
  Widget _scrollShell(List<Widget> children) {
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      children: children,
    );
  }

  Widget _handleBar(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: ShiguangColors.wood.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildLoaded(BuildContext context) {
    return FutureBuilder<DayRecord>(
      future: _recordFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (snap.hasError) {
            return _scrollShell([
              _handleBar(context),
              HandCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '这一天的记录读取失败',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('${snap.error}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _reloadRecord, child: const Text('重试')),
                  ],
                ),
              ),
            ]);
          }
          return _scrollShell([
            _handleBar(context),
            const SizedBox(height: 48),
            const Center(child: CircularProgressIndicator()),
          ]);
        }
        return _scrollShell([
          _handleBar(context),
          _buildHeader(context, snap.data!),
          ..._buildBody(context, snap.data!),
        ]);
      },
    );
  }

  // ---------------------------------------------------------------- 头部

  Widget _buildHeader(BuildContext context, DayRecord record) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // 标题与星期拆成两个 Text：调用方/C 轨断言时可精确匹配日期串
        Text(dayKeyToChinese(record.dayKey), style: theme.textTheme.titleLarge),
        const SizedBox(width: 8),
        Text('· ${_weekdayCN(record.dayKey)}', style: theme.textTheme.bodySmall),
        const Spacer(),
        Text(
          '${record.photos.length} 张',
          style: theme.textTheme.bodySmall,
        ),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  String _weekdayCN(int dayKey) {
    // models.dart 只负责到「几月几日」，星期留在 UI 侧补齐
    const names = [
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    ];
    return names[dayKeyToDateTime(dayKey).weekday - 1];
  }

  // ---------------------------------------------------------------- 主体

  List<Widget> _buildBody(BuildContext context, DayRecord record) {
    final isFuture = record.dayKey > dayKeyOf(DateTime.now());

    // 未来日期：只报到，不给生成入口（那天还没发生，谈不上总结）
    if (isFuture) {
      return [
        const SizedBox(height: 8),
        HandCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('这一天尚未到来',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('时间还没走到这一天，等它发生后再来看看吧。',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ];
    }

    // 空日：明确告知，不放生成按钮（没有素材，AI 也只能编）
    if (!record.hasPhotos) {
      return [
        const SizedBox(height: 8),
        HandCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('这一天没有留下照片',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('也许那天没有按下快门，或者照片还没被扫描进来。',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ];
    }

    return [
      const SizedBox(height: 4),
      _summaryCard(context, record),
      const SizedBox(height: 12),
      _photoGrid(record),
      const SizedBox(height: 16),
      _generateButton(),
      if (_notice != null) ...[
        const SizedBox(height: 8),
        Text(
          _notice!,
          style: const TextStyle(fontSize: 13, color: ShiguangColors.danger),
        ),
      ],
    ];
  }

  /// AI 总结卡：有总结展示内容，没总结给生成引导。
  Widget _summaryCard(BuildContext context, DayRecord record) {
    final theme = Theme.of(context);
    final summary = record.summary;

    return HandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (record.summaryStale) ...[
            // 失效横幅：点一下即 force 重新生成，省得用户去点底部按钮
            GestureDetector(
              onTap: _generating ? null : () => _generate(force: true),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: ShiguangColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: ShiguangColors.danger.withValues(alpha: 0.45),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sync_problem,
                        size: 16, color: ShiguangColors.danger),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '照片有更新，点击重新生成',
                        style: TextStyle(
                          fontSize: 13,
                          color: ShiguangColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (summary == null) ...[
            Text('这一天还没有总结', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '让 AI 用几句话留住这一天，点下方按钮试试。',
              style: theme.textTheme.bodySmall,
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 新海诚式天气隐喻心情符
                Text(
                  summary.moodIcon,
                  style: const TextStyle(fontSize: 20, height: 1.2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(summary.title, style: theme.textTheme.titleMedium),
                ),
                // AI 生成的是草稿：随时可改，改完原样写回缓存
                IconButton(
                  tooltip: '编辑总结',
                  onPressed: () => _editSummary(summary),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                // 总结卡 → 竖版分享图（750×1000 PNG 落盘，见 share_card.dart）
                IconButton(
                  tooltip: '导出卡片',
                  onPressed: () => _exportShareCard(record),
                  icon: const Icon(Icons.ios_share_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.narrative, style: theme.textTheme.bodyMedium),
            if (summary.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in summary.tags) _tagChip(t)],
              ),
            ],
            if (summary.highlights.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final h in summary.highlights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 15, color: ShiguangColors.completedGold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(h,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
            // 不再展示「由 xx 模型生成」：总结是给用户的，不该暴露生成来源
            //（model 字段仍入库，供批量清理/排障用，只是 UI 不显示）。
          ],
        ],
      ),
    );
  }

  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ShiguangColors.leafDark.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ShiguangColors.leafDark.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 12,
          color: ShiguangColors.leafDark,
        ),
      ),
    );
  }

  /// 照片网格：512 档缩略图（高分屏上 256 偏软，用户拍板升级），
  /// 点击进全屏查看器（原图流式加载），查看器里删除返回 true 时重载本日记录；
  /// 长按 = 直接「从记录移除」快捷入口。
  Widget _photoGrid(DayRecord record) {
    return GridView.builder(
      shrinkWrap: true,
      // 外层 ListView 负责滚动，网格自身不滚，避免手势嵌套冲突
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: record.photos.length,
      itemBuilder: (context, index) {
        final path = record.photos[index].path;
        return Semantics(
          button: true,
          label: '查看第 ${index + 1} 张照片，长按可移除',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final deleted = await showPhotoViewer(context, path);
              if (deleted == true && mounted) await _afterPhotoRemoved();
            },
            onLongPress: () => _confirmRemovePhoto(path),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ThumbImage(
                sourcePath: path,
                size: 512,
                placeholderColor: ShiguangColors.paperDeep,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 长按移除：与查看器里的删除同一套文案与语义（只移出记录，不动原文件）。
  Future<void> _confirmRemovePhoto(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('从记录中移除这张照片？'),
        content: const Text('只从拾光手册的这一天里移除，不会删除系统相册或磁盘里的原文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true || _store == null || !mounted) return;
    await _store!.removePhotos([path]);
    if (mounted) await _afterPhotoRemoved();
  }

  /// 照片被移除后的收尾：若当天已一张不剩，连同 AI 总结一起删——
  /// 没有素材的总结留着只会误导（这正是 deleteSummary 的主要用途）。
  Future<void> _afterPhotoRemoved() async {
    if (_store != null) {
      final left = await _store!.photosOfDay(widget.dayKey);
      if (left.isEmpty) await _store!.deleteSummary(widget.dayKey);
    }
    if (mounted) _reloadRecord();
  }

  Widget _generateButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        // force:false：已有且未失效的总结走缓存直接返回（repo 负责判定），不白花钱
        onPressed: _generating ? null : () => _generate(force: false),
        icon: _generating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: Text(_generating ? '正在生成…' : '生成今日总结'),
      ),
    );
  }
}
