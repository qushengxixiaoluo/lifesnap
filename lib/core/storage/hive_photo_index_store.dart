/// hive_ce 版照片索引存储（桌面 Windows/macOS/Linux 与 Web 共用的纯 Dart 实现）。
///
/// 为什么用 hive 而不是 sqflite：桌面端 sqlite3 需要随包分发原生动态库，
/// 在 Windows 上会踩「首次运行下载/加载 sqlite3.dll 失败」的一堆坑；
/// hive_ce 是纯 Dart + 自带文件格式，零原生依赖，跨平台行为一致。
///
/// box 设计（全部 key 为 String，value 为原生 Map，hive 内置 Map/List 适配器直存）：
/// - photos    ：path → Photo.toMap()（path 即主键，天然唯一，天然支持按 path 覆盖写）
/// - sources   ：sourceId → PhotoSource.toMap()
/// - summaries ：dayKey → AiSummary.toMap()（AI 总结缓存）
/// - days      ：dayKey → DayMeta 投影（持久化日索引，启动秒开；仍会由 refreshDayIndex 全量重算兜底）
/// - meta      ：自增 id 计数器（hive 没有 SQL 自增，用 meta box 模拟）
///
/// 本文件同时被 io（桌面）与 web 分支 import，因此 **禁止 import dart:io**；
/// 目录创建等平台操作由 open_store_io.dart / 测试代码负责。
library;

import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'photo_index_store.dart';

class HivePhotoIndexStore implements PhotoIndexStore {
  /// [homePath]：桌面端传数据目录；Web 端传 null（hive_ce 自动走 IndexedDB）。
  HivePhotoIndexStore(this.homePath);

  final String? homePath;

  static const _boxPhotos = 'photos';
  static const _boxSources = 'sources';
  static const _boxSummaries = 'summaries';
  static const _boxDays = 'days';
  static const _boxMeta = 'meta';

  Box? _photos;
  Box? _sources;
  Box? _summaries;
  Box? _days;
  Box? _meta;

  /// 内存日索引：月视图每次打开都要用，绝不能每次读 box（几万照片会卡帧）。
  final _dayIndex = <int, DayMeta>{};

  @override
  Future<void> init() async {
    // hive 全局单例：重复 init（测试连续开两个 store）时先关旧 box，
    // 否则 openBox 会直接返回上一个目录里的旧句柄，数据串台。
    for (final name in const [
      _boxPhotos,
      _boxSources,
      _boxSummaries,
      _boxDays,
      _boxMeta,
    ]) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
    }
    Hive.init(homePath); // Web 上 homePath=null 即使用 IndexedDB 后端
    _photos = await Hive.openBox(_boxPhotos);
    _sources = await Hive.openBox(_boxSources);
    _summaries = await Hive.openBox(_boxSummaries);
    _days = await Hive.openBox(_boxDays);
    _meta = await Hive.openBox(_boxMeta);
    await refreshDayIndex();
  }

  Box get _photosBox => _photos!;
  Box get _sourcesBox => _sources!;
  Box get _summariesBox => _summaries!;
  Box get _daysBox => _days!;
  Box get _metaBox => _meta!;

  // —— 扫描源 ————————————————————————————————————————

  @override
  Future<List<PhotoSource>> loadSources() async => [
        for (final raw in _sourcesBox.values)
          PhotoSource.fromMap(_asMap(raw)),
      ];

  @override
  Future<int> addSource(PhotoSource source) async {
    final id = (_metaBox.get('next_source_id') as int?) ?? 1;
    await _metaBox.put('next_source_id', id + 1);
    // PhotoSource 是不可变值对象且没有 copyWith（models.dart 为只读契约），手动带 id 落库
    await _sourcesBox.put(
      '$id',
      PhotoSource(
        id: id,
        type: source.type,
        path: source.path,
        enabled: source.enabled,
        lastScanMs: source.lastScanMs,
      ).toMap(),
    );
    return id;
  }

  @override
  Future<void> removeSource(int id) async {
    await _sourcesBox.delete('$id');
    // 连带清掉该源的照片，避免孤儿数据让日索引虚高
    final stale = [
      for (final e in _photosBox.toMap().entries)
        if (((e.value as Map)['source_id'] as num).toInt() == id) e.key as String,
    ];
    if (stale.isNotEmpty) await _photosBox.deleteAll(stale);
    await refreshDayIndex();
  }

  @override
  Future<void> markSourceScanned(int id, int atMs) async {
    final raw = _sourcesBox.get('$id');
    if (raw == null) return;
    final m = _asMap(raw);
    m['last_scan_ms'] = atMs;
    await _sourcesBox.put('$id', m);
  }

  @override
  Future<Map<String, int>> knownSignatures(int sourceId) async => {
        // 盒内数据常驻内存（hive Box 非 Lazy），全量遍历对几万张照片是毫秒级
        for (final e in _photosBox.toMap().entries)
          if (((e.value as Map)['source_id'] as num).toInt() == sourceId)
            e.key as String: ((e.value as Map)['mtime_ms'] as num).toInt(),
      };

  // —— 照片写入/查询 ————————————————————————————————————

  @override
  Future<void> upsertPhotos(List<Photo> photos) async {
    if (photos.isEmpty) return;
    var nextId = (_metaBox.get('next_photo_id') as int?) ?? 1;
    var idUsed = false;
    final writes = <String, Map>{};
    for (final p in photos) {
      final raw = _photosBox.get(p.path);
      final int id;
      if (raw != null) {
        // 已存在：保留原 id（UI 的 ValueKey 依赖 id 稳定），只覆盖可变字段
        id = ((raw as Map)['id'] as num).toInt();
      } else {
        id = nextId++;
        idUsed = true;
      }
      writes[p.path] = p.copyWith(id: id).toMap();
    }
    if (idUsed) await _metaBox.put('next_photo_id', nextId);
    await _photosBox.putAll(writes);
    await refreshDayIndex();
  }

  @override
  Future<void> removePhotos(List<String> paths) async {
    if (paths.isEmpty) return;
    await _photosBox.deleteAll(paths);
    await refreshDayIndex();
  }

  @override
  Future<List<Photo>> photosOfDay(int dayKey) async => (_photosBox.values
          .where((raw) => ((raw as Map)['day_key'] as num).toInt() == dayKey)
          .map((raw) => Photo.fromMap(_asMap(raw)))
          .toList())
      ..sort((a, b) => a.takenAtMs.compareTo(b.takenAtMs));

  // —— 日索引 ————————————————————————————————————————

  @override
  Map<int, DayMeta> get dayIndex => Map.unmodifiable(_dayIndex);

  @override
  Future<void> refreshDayIndex() async {
    _dayIndex.clear();
    // 总结集合先取出来：hasSummary 是节点金勾的依据，必须每次重算
    final summaryKeys = _summariesBox.keys.toSet();

    // thumbPath 用「当天 takenAt 最早的一张」：确定性输出，不受写入顺序影响，
    // 与 photosOfDay 的排序首项一致，节点预览和详情页首图对得上。
    final best = <int, Photo>{};
    for (final raw in _photosBox.values) {
      final m = _asMap(raw);
      final dayKey = (m['day_key'] as num).toInt();
      final photo = Photo.fromMap(m);
      final cur = best[dayKey];
      if (cur == null ||
          photo.takenAtMs < cur.takenAtMs ||
          (photo.takenAtMs == cur.takenAtMs && photo.path.compareTo(cur.path) < 0)) {
        best[dayKey] = photo;
      }
      final meta = _dayIndex[dayKey];
      _dayIndex[dayKey] = DayMeta(
        dayKey: dayKey,
        photoCount: (meta?.photoCount ?? 0) + 1,
        thumbPath: meta?.thumbPath ?? photo.path,
      );
    }

    // 先占位再回填 thumbPath：上面循环里首张只是插入序，这里统一换成确定性首张
    final dayWrites = <String, Map>{};
    for (final entry in _dayIndex.entries) {
      final first = best[entry.key];
      final hasSummary = summaryKeys.contains('${entry.key}');
      final meta = entry.value.copyWith(
        thumbPath: first?.path,
        hasSummary: hasSummary,
      );
      _dayIndex[entry.key] = meta;
      dayWrites['${entry.key}'] = {
        'photo_count': meta.photoCount,
        'thumb_path': meta.thumbPath,
        'has_summary': meta.hasSummary,
      };
    }
    await _daysBox.clear();
    if (dayWrites.isNotEmpty) await _daysBox.putAll(dayWrites);
  }

  // —— AI 总结缓存 ————————————————————————————————————

  @override
  Future<AiSummary?> summaryOf(int dayKey) async {
    final raw = _summariesBox.get('$dayKey');
    return raw == null ? null : AiSummary.fromMap(_asMap(raw));
  }

  @override
  Future<void> putSummary(AiSummary summary) async {
    await _summariesBox.put('${summary.dayKey}', summary.toMap());
    // 立刻刷新：设置页/节点马上要读 dayIndex.hasSummary，不能等下次扫描
    await refreshDayIndex();
  }

  @override
  Future<void> deleteSummary(int dayKey) async {
    await _summariesBox.delete('$dayKey');
    await refreshDayIndex(); // hasSummary 随之置 false（与 put 对称）
  }

  @override
  Future<void> close() async {
    // 逐个关闭而不是 Hive.close()：后者是全局的，会误伤同进程里的其他实例
    for (final box in [_photos, _sources, _summaries, _days, _meta]) {
      if (box != null && box.isOpen) await box.close();
    }
    _photos = _sources = _summaries = _days = _meta = null;
    _dayIndex.clear();
  }

  /// hive 读出的原始 Map 是动态键值对，统一转成模型层要的 String key 视图（浅拷贝，字段数个位数）。
  Map<String, Object?> _asMap(Object? raw) => Map<String, Object?>.from(raw as Map);
}
