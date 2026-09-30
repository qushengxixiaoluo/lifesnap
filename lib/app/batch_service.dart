/// 批量生成全局服务：任务属于「应用」而不是「设置页」。
///
/// 解决两个用户反馈的问题：
/// 1. 退出界面任务被取消——任务订阅原先挂在 BatchSection 的 State 上，
///    dispose 即 cancel；现在循环跑在 Notifier 里，UI 只是观察者，
///    离开页面/切后台都不影响（进程活着就继续）。
/// 2. 退出软件任务丢失——队列（待生成 dayKey、已失败）每次推进都落
///    SharedPreferences；下次启动 main 里的 _BatchAutoResume 钩子
///    检测到未完成队列即自动续跑，实现「从头到尾补完」。
///
/// 任务范围：用户要求的「所有有照片但没有 AI 总结的日子」（升序从早到晚），
/// 不再局限于单月；单月按钮走 [startMonth]，只是把队列限定在一个月内。
///
/// 真·关机后台跑需要 Android 前台服务（原生插件），暂不做：
/// 进程被杀后重开自动续跑已覆盖「最终从头到尾补完」的目标。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ai/ai_provider.dart';
import '../core/models/models.dart';
import 'providers.dart';

/// 批量任务的对外状态（纯数据，UI 直接 watch）。
class BatchJobState {
  /// 是否正在生成（含恢复续跑）。
  final bool running;

  /// 本次任务应处理的总天数（启动时确定）。
  final int total;

  /// 已成功天数。
  final int done;

  /// 已失败天数（会留在 failedDays 里可单独重试）。
  final int failed;

  /// 正在处理的 dayKey（0 = 空闲）。
  final int currentDayKey;

  /// 失败明细（dayKey 升序）。
  final List<int> failedDays;

  /// 最近一次任务已跑完（用于显示「全部完成」）。
  final bool finished;

  /// 中止原因（如 Key 失效）——非 null 时任务已停、队列已保留可续。
  final String? abortedReason;

  /// 队列里还有没有待处理项（持久化的残队，重启后可续跑）。
  final bool hasPending;

  const BatchJobState({
    this.running = false,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
    this.currentDayKey = 0,
    this.failedDays = const [],
    this.finished = false,
    this.abortedReason,
    this.hasPending = false,
  });
}

class BatchGenerateNotifier extends Notifier<BatchJobState> {
  @override
  BatchJobState build() => const BatchJobState();

  static const _prefsKey = 'batch_job_v1';

  /// 执行闸门：防止「按钮狂点」或「恢复钩子 + 手动按钮」开双份任务。
  bool _executing = false;

  /// 用户主动停止：当前正在处理的这天跑完后收工，队列保留可续。
  bool _stopRequested = false;

  // ------------------------------------------------------------ 队列持久化

  Future<void> _persist(List<int> pending, List<int> failedDays, int done) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pending.isEmpty && failedDays.isEmpty) {
        await prefs.remove(_prefsKey); // 全部收尾：清残队
      } else {
        await prefs.setString(
          _prefsKey,
          jsonEncode({
            'pending': pending,
            'failed': failedDays,
            'done': done,
          }),
        );
      }
    } catch (_) {/* 落盘失败不阻断生成：最坏情况重启后重新扫描队列 */}
  }

  Future<({List<int> pending, List<int> failed, int done})?>
      _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final pending =
          (m['pending'] as List?)?.map((e) => e as int).toList() ?? <int>[];
      final failed =
          (m['failed'] as List?)?.map((e) => e as int).toList() ?? <int>[];
      if (pending.isEmpty && failed.isEmpty) return null;
      return (pending: pending, failed: failed, done: m['done'] as int? ?? 0);
    } catch (_) {
      return null; // 存档损坏 → 当作没有，宁可重新排队也不崩
    }
  }

  // ------------------------------------------------------------ 任务入口

  /// 「补全所有缺失」：全库有照片且无总结的日子，升序从头跑到底。
  Future<void> startAll() => _start(buildQueue: _queueAllMissing);

  /// 单月批量（保留原入口，只是同样走全局服务）。
  Future<void> startMonth(int year, int month) =>
      _start(buildQueue: () => _queueMissingInMonth(year, month));

  /// 启动时/点击「继续」：捡起落盘的残队接着跑。
  Future<void> resumeIfPending() async {
    final saved = await _loadPersisted();
    if (saved == null || saved.pending.isEmpty) return;
    await _runQueue(saved.pending, saved.failed, saved.done,
        resumed: true);
  }

  /// 主动停止：当前天完成后收工（队列保留，hasPending=true 可续）。
  void requestStop() {
    if (!_executing) return;
    _stopRequested = true;
  }

  /// 失败明细里的单天重试（force 重新生成）。
  Future<void> retryDay(int dayKey) async {
    if (_executing) return;
    final store = await ref.read(photoStoreProvider.future);
    final repo = ref.read(summaryRepositoryProvider);
    final photos = await store.photosOfDay(dayKey);
    if (photos.isEmpty) return;
    try {
      final summary = await store.summaryOf(dayKey);
      await repo.generate(
        record: DayRecord(
          dayKey: dayKey,
          photos: photos,
          summary: summary,
          summaryStale: summary != null &&
              summary.photoSig != computePhotoSig(photos),
        ),
        force: true,
      );
      final newFailed = [...state.failedDays]..remove(dayKey);
      state = BatchJobState(
        running: state.running,
        total: state.total,
        done: state.done,
        failed: newFailed.length,
        currentDayKey: state.currentDayKey,
        failedDays: newFailed,
        finished: state.finished,
        hasPending: state.hasPending,
      );
      // 失败队列同步落盘，避免重启后又把重试过的天当成残队
      final saved = await _loadPersisted();
      if (saved != null) {
        await _persist(saved.pending, state.failedDays, state.done);
      }
    } on AiException {
      rethrow; // 交给 UI 显示中文文案
    }
  }

  // ------------------------------------------------------------ 队列构造

  /// 全库：有照片 && 还没有任何 AI 总结 的日子（升序 = 从头到尾）。
  Future<List<int>> _queueAllMissing() async {
    final store = await ref.read(photoStoreProvider.future);
    final keys = [
      for (final e in store.dayIndex.entries)
        if (e.value.photoCount > 0) e.key,
    ]..sort();
    final pending = <int>[];
    for (final dayKey in keys) {
      if (await store.summaryOf(dayKey) == null) pending.add(dayKey);
    }
    return pending;
  }

  /// 单月：有照片 && 无总结。
  Future<List<int>> _queueMissingInMonth(int year, int month) async {
    final store = await ref.read(photoStoreProvider.future);
    final pending = <int>[];
    for (var d = 1; d <= daysInMonth(year, month); d++) {
      final dayKey = year * 10000 + month * 100 + d;
      if ((store.dayIndex[dayKey]?.photoCount ?? 0) == 0) continue;
      if (await store.summaryOf(dayKey) == null) pending.add(dayKey);
    }
    return pending;
  }

  // ------------------------------------------------------------ 主循环

  Future<void> _start({
    required Future<List<int>> Function() buildQueue,
  }) async {
    if (_executing) return;
    final pending = await buildQueue();
    await _runQueue(pending, const [], 0, resumed: false);
  }

  /// 并发 3 的执行器：三个 worker 从共享队列头取任务。
  /// 任何时刻只允许一个任务实例在跑（_executing 闸门）。
  Future<void> _runQueue(
    List<int> pending,
    List<int> failed,
    int done, {
    required bool resumed,
  }) async {
    if (_executing) return;
    if (pending.isEmpty) {
      state = BatchJobState(
        total: 0,
        done: 0,
        failed: failed.length,
        failedDays: failed,
        finished: true,
        hasPending: false,
      );
      return;
    }
    _executing = true;
    _stopRequested = false;
    state = BatchJobState(
      running: true,
      total: pending.length + done,
      done: done,
      failed: failed.length,
      failedDays: failed,
      hasPending: true,
    );
    await _persist(pending, failed, done);

    final queue = [...pending]; // 共享队列（worker 抢头部）
    final failedDays = [...failed];
    var doneCount = done;
    String? abortReason;

    final store = await ref.read(photoStoreProvider.future);
    final repo = ref.read(summaryRepositoryProvider);

    Future<void> worker() async {
      while (true) {
        if (_stopRequested) return;
        if (queue.isEmpty) return;
        final dayKey = queue.removeAt(0);
        state = _copy(current: dayKey);
        try {
          final photos = await store.photosOfDay(dayKey);
          if (photos.isEmpty) {
            // 扫描后照片被删的边界：不算失败，直接跳过
            doneCount++;
          } else {
            final summary = await store.summaryOf(dayKey);
            await repo.generate(
              record: DayRecord(
                dayKey: dayKey,
                photos: photos,
                summary: summary,
                summaryStale: false,
              ),
            );
            doneCount++;
          }
        } on AiAuthException catch (e) {
          // Key 失效是「全任务级」故障：后面每一天都会同样失败，
          // 立刻中止并保留残队（修好 Key 后重开自动续跑）。
          abortReason = e.message;
          queue.insert(0, dayKey); // 当天放回队首，修好后从这里继续
          return;
        } on AiException {
          failedDays.add(dayKey); // 单天失败不拖垮整个任务
        } catch (_) {
          failedDays.add(dayKey);
        }
        state = _copy(done: doneCount, failedList: failedDays);
        await _persist(queue, failedDays, doneCount);
        if (abortReason != null) return;
      }
    }

    // 3 个 worker 并发消费（无第三方信号量依赖，队列本身即互斥）
    await Future.wait([worker(), worker(), worker()]);

    final stopped = _stopRequested;
    final remaining = [...queue];
    _executing = false;
    _stopRequested = false;
    await _persist(remaining, failedDays, doneCount);

    state = BatchJobState(
      running: false,
      total: state.total,
      done: doneCount,
      failed: failedDays.length,
      failedDays: failedDays,
      finished: !stopped && abortReason == null && remaining.isEmpty,
      abortedReason: abortReason,
      hasPending: remaining.isNotEmpty,
    );
  }

  /// 在当前状态上打补丁（worker 循环里逐天推进用）。
  BatchJobState _copy({
    int? current,
    int? done,
    List<int>? failedList,
  }) =>
      BatchJobState(
        running: true,
        total: state.total,
        done: done ?? state.done,
        failed: failedList?.length ?? state.failed,
        currentDayKey: current ?? state.currentDayKey,
        failedDays: failedList ?? state.failedDays,
        hasPending: true,
      );
}

/// 全局批量服务：设置页 watch 它，main 的恢复钩子调用它。
final batchServiceProvider =
    NotifierProvider<BatchGenerateNotifier, BatchJobState>(
  BatchGenerateNotifier.new,
);
