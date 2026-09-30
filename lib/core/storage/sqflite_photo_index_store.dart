/// sqflite 版照片索引存储（Android / iOS 专用）。
///
/// 为什么移动端用 sqflite：系统媒体库里几万张照片时 SQL 聚合（COUNT/GROUP BY）
/// 比全量内存遍历省电省内存；且 sqflite 在移动端是系统自带 SQLite，无原生库分发问题
/// （桌面端才需要 hive 规避 sqlite3 下载坑，见 hive_photo_index_store.dart）。
///
/// 表结构严格对齐 PhotoIndexStore 注释字段；path 唯一约束即 path 索引，
/// day_key / source_id 单列索引支撑 photosOfDay 与 knownSignatures 两个热点查询。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'photo_index_store.dart';

class SqflitePhotoIndexStore implements PhotoIndexStore {
  Database? _db;

  /// 内存日索引：与 hive/内存实现同语义，月视图同步读取不打 IO。
  final _dayIndex = <int, DayMeta>{};

  @override
  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      '$dbPath/shiguang_index.db',
      version: 1,
      onCreate: (db, _) => _createSchema(db),
    );
    _db = db;
    await refreshDayIndex();
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('SqflitePhotoIndexStore 未初始化，请先 await init()');
    }
    return db;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE photos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        file_size INTEGER NOT NULL,
        mtime_ms INTEGER NOT NULL,
        taken_at_ms INTEGER NOT NULL,
        day_key INTEGER NOT NULL,
        source_id INTEGER NOT NULL,
        width INTEGER,
        height INTEGER
      )
    ''');
    // path 的 UNIQUE 约束会自动建唯一索引，这里不再重复建，避免双份维护开销
    await db.execute('CREATE INDEX idx_photos_day_key ON photos(day_key)');
    await db.execute('CREATE INDEX idx_photos_source_id ON photos(source_id)');

    await db.execute('''
      CREATE TABLE sources(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        path TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_scan_ms INTEGER
      )
    ''');

    // tags/highlights 在 SQL 里存 JSON 文本，AiSummary.fromMap 兼容两种编码
    await db.execute('''
      CREATE TABLE summaries(
        day_key INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        narrative TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        mood TEXT NOT NULL,
        highlights_json TEXT NOT NULL,
        model TEXT NOT NULL,
        photo_sig TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // —— 扫描源 ————————————————————————————————————————

  @override
  Future<List<PhotoSource>> loadSources() async {
    final rows = await _database.query('sources', orderBy: 'id');
    return rows.map(PhotoSource.fromMap).toList();
  }

  @override
  Future<int> addSource(PhotoSource source) async {
    // 不传 id，交给 AUTOINCREMENT；PhotoSource.toMap 的 id=0 会干扰主键，先剔除
    final map = source.toMap()..remove('id');
    return _database.insert('sources', map);
  }

  @override
  Future<void> removeSource(int id) async {
    final db = _database;
    await db.transaction((txn) async {
      await txn.delete('sources', where: 'id = ?', whereArgs: [id]);
      // 连带删照片：源没了照片留着只会让日索引虚高
      await txn.delete('photos', where: 'source_id = ?', whereArgs: [id]);
    });
    await refreshDayIndex();
  }

  @override
  Future<void> markSourceScanned(int id, int atMs) async => _database.update(
        'sources',
        {'last_scan_ms': atMs},
        where: 'id = ?',
        whereArgs: [id],
      );

  @override
  Future<Map<String, int>> knownSignatures(int sourceId) async {
    final rows = await _database.query(
      'photos',
      columns: ['path', 'mtime_ms'],
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    return {
      for (final r in rows)
        r['path'] as String: (r['mtime_ms'] as num).toInt(),
    };
  }

  // —— 照片写入/查询 ————————————————————————————————————

  @override
  Future<void> upsertPhotos(List<Photo> photos) async {
    if (photos.isEmpty) return;
    await _database.transaction((txn) async {
      for (final p in photos) {
        final values = p.toMap()..remove('id');
        // 先 UPDATE：命中则保留原自增 id（UI 的 ValueKey 依赖 id 稳定）
        final updated = await txn.update(
          'photos',
          values,
          where: 'path = ?',
          whereArgs: [p.path],
        );
        if (updated == 0) {
          await txn.insert('photos', values);
        }
      }
    });
    await refreshDayIndex();
  }

  @override
  Future<void> removePhotos(List<String> paths) async {
    if (paths.isEmpty) return;
    final placeholders = List.filled(paths.length, '?').join(',');
    await _database.delete(
      'photos',
      where: 'path IN ($placeholders)',
      whereArgs: paths,
    );
    await refreshDayIndex();
  }

  @override
  Future<List<Photo>> photosOfDay(int dayKey) async {
    final rows = await _database.query(
      'photos',
      where: 'day_key = ?',
      whereArgs: [dayKey],
      orderBy: 'taken_at_ms',
    );
    return rows.map(Photo.fromMap).toList();
  }

  // —— 日索引 ————————————————————————————————————————

  @override
  Map<int, DayMeta> get dayIndex => Map.unmodifiable(_dayIndex);

  @override
  Future<void> refreshDayIndex() async {
    final db = _database;
    // 一次全表扫按 (day_key, taken_at_ms) 排序：既能 COUNT 分组，
    // 又能顺手拿到每天最早一张做 thumbPath（避免窗口函数，兼容老 Android 的 SQLite 版本）
    final rows = await db.rawQuery(
      'SELECT day_key, path, taken_at_ms FROM photos '
      'ORDER BY day_key ASC, taken_at_ms ASC, path ASC',
    );
    final summaryRows =
        await db.rawQuery('SELECT day_key FROM summaries');
    final summaryKeys = {
      for (final r in summaryRows) (r['day_key'] as num).toInt(),
    };

    _dayIndex.clear();
    for (final r in rows) {
      final dayKey = (r['day_key'] as num).toInt();
      final cur = _dayIndex[dayKey];
      if (cur == null) {
        _dayIndex[dayKey] = DayMeta(
          dayKey: dayKey,
          photoCount: 1,
          thumbPath: r['path'] as String,
          hasSummary: summaryKeys.contains(dayKey),
        );
      } else {
        _dayIndex[dayKey] = cur.copyWith(photoCount: cur.photoCount + 1);
      }
    }
  }

  // —— AI 总结缓存 ————————————————————————————————————

  @override
  Future<AiSummary?> summaryOf(int dayKey) async {
    final rows = await _database.query(
      'summaries',
      where: 'day_key = ?',
      whereArgs: [dayKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AiSummary.fromMap(rows.first);
  }

  @override
  Future<void> putSummary(AiSummary summary) async {
    final m = summary.toMap();
    await _database.insert(
      'summaries',
      {
        ...m,
        // SQL 列是 TEXT，这里把 List 编码成 JSON 数组字符串
        'tags_json': jsonEncode(summary.tags),
        'highlights_json': jsonEncode(summary.highlights),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // 立刻刷新：设置页马上要读 dayIndex.hasSummary
    await refreshDayIndex();
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _dayIndex.clear();
  }
}
