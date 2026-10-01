/// 拾光手册 · 核心数据模型
///
/// 全部跨模块共享的数据结构集中于此（沿用 gushici 项目 models.dart 单文件先例），
/// 是「阶段 0 契约地基」的一部分：五条并行开发轨都只依赖本文件的类型，
/// 各轨不得修改本文件，需要新增字段时上报编排者统一修改。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

// ============================================================================
// 日期工具：dayKey 是全应用的日期主键
// ============================================================================

/// 把任意时刻归一化为本地日期的 yyyymmdd 整数（如 2026-09-29 → 20260929）。
///
/// 用整数而非字符串做 key：内存 Map 索引更快，范围查询（某月 BETWEEN）直观。
int dayKeyOf(DateTime local) => local.year * 10000 + local.month * 100 + local.day;

/// dayKey 还原为 DateTime（当天 00:00）。
DateTime dayKeyToDateTime(int dayKey) =>
    DateTime(dayKey ~/ 10000, (dayKey ~/ 100) % 100, dayKey % 100);

/// 某年某月的天数。
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// dayKey → 「2026-09-29」展示串。
String dayKeyToString(int dayKey) {
  final s = dayKey.toString();
  return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';
}

/// dayKey → 「9月29日」展示串。
String dayKeyToChinese(int dayKey) =>
    '${(dayKey ~/ 100) % 100}月${dayKey % 100}日';

/// 当日照片集合指纹：path|mtime 排序后拼接取 sha1。
///
/// AI 总结落库时同时存此值；照片增删改后指纹变化 → 总结被标记失效，
/// 节点提示「照片有更新，点击重新生成」。
String computePhotoSig(List<Photo> photos) {
  final canonical = photos.map((p) => '${p.path}|${p.mtimeMs}').toList()..sort();
  return sha1.convert(utf8.encode(canonical.join('\n'))).toString();
}

// ============================================================================
// Photo：照片索引的最小事实单元
// ============================================================================

/// 一张已入索引的照片。
///
/// path 的平台约定：
/// - 桌面：绝对路径，如 `D:\PhotoSamples\a.jpg`
/// - 移动相册：`pm://{assetId}`（photo_manager 资产 id）
/// - Web：`web://{相对所选根目录的路径}`（浏览器无真实文件系统路径）
class Photo {
  final int id;
  final String path;
  final int fileSize;
  final int mtimeMs;
  final int takenAtMs; // EXIF DateTimeOriginal 优先，失败回退 mtime
  final int dayKey; // takenAt 的本地日期 yyyymmdd
  final int sourceId;
  final int? width;
  final int? height;

  const Photo({
    this.id = 0,
    required this.path,
    required this.fileSize,
    required this.mtimeMs,
    required this.takenAtMs,
    required this.dayKey,
    required this.sourceId,
    this.width,
    this.height,
  });

  DateTime get takenAt => DateTime.fromMillisecondsSinceEpoch(takenAtMs);

  /// 增量扫描指纹：路径 + 修改时间 + 体积。三者任一变化即视为新文件。
  String get signature => '$path|$mtimeMs|$fileSize';

  Photo copyWith({int? id}) => Photo(
        id: id ?? this.id,
        path: path,
        fileSize: fileSize,
        mtimeMs: mtimeMs,
        takenAtMs: takenAtMs,
        dayKey: dayKey,
        sourceId: sourceId,
        width: width,
        height: height,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'path': path,
        'file_size': fileSize,
        'mtime_ms': mtimeMs,
        'taken_at_ms': takenAtMs,
        'day_key': dayKey,
        'source_id': sourceId,
        'width': width,
        'height': height,
      };

  factory Photo.fromMap(Map<String, Object?> m) => Photo(
        id: (m['id'] as num?)?.toInt() ?? 0,
        path: m['path'] as String,
        fileSize: (m['file_size'] as num).toInt(),
        mtimeMs: (m['mtime_ms'] as num).toInt(),
        takenAtMs: (m['taken_at_ms'] as num).toInt(),
        dayKey: (m['day_key'] as num).toInt(),
        sourceId: (m['source_id'] as num).toInt(),
        width: (m['width'] as num?)?.toInt(),
        height: (m['height'] as num?)?.toInt(),
      );
}

// ============================================================================
// DayMeta / DayRecord：月视图聚合 与 详情页数据包
// ============================================================================

/// 月视图内存索引中的一天（启动时全量载入，体积极小：约 365 行/年）。
class DayMeta {
  final int dayKey;
  final int photoCount;
  final String? thumbPath; // 当日首张 256px 缩略图，节点预览用
  final bool hasSummary; // 该日已有 AI 总结（节点金勾依据；实现方在 refreshDayIndex 填充）
  final bool hasNote; // 该日已有手写补记（无照片的手记日也会进索引）

  const DayMeta({
    required this.dayKey,
    required this.photoCount,
    this.thumbPath,
    this.hasSummary = false,
    this.hasNote = false,
  });

  DayMeta copyWith({
    int? photoCount,
    String? thumbPath,
    bool? hasSummary,
    bool? hasNote,
  }) =>
      DayMeta(
        dayKey: dayKey,
        photoCount: photoCount ?? this.photoCount,
        thumbPath: thumbPath ?? this.thumbPath,
        hasSummary: hasSummary ?? this.hasSummary,
        hasNote: hasNote ?? this.hasNote,
      );
}

/// 打开某个节点时组装的完整数据包。
class DayRecord {
  final int dayKey;
  final List<Photo> photos;
  final AiSummary? summary;
  final bool summaryStale; // photo_sig 与当前照片集合不一致 → 需要重新生成

  const DayRecord({
    required this.dayKey,
    required this.photos,
    this.summary,
    this.summaryStale = false,
  });

  bool get hasPhotos => photos.isNotEmpty;
}

// ============================================================================
// AiSummary：AI 每日总结的结构化结果
// ============================================================================

/// 一天的 AI 总结（生成后写入缓存，photo_sig 用于失效判断）。
class AiSummary {
  final int dayKey;
  final String title; // ≤12 字当日标题
  final String narrative; // 80-200 字中文散文式总结
  final List<String> tags; // ≤6 个标签
  final String mood; // 晴 | 多云 | 小雨 | 彩虹 | 星夜
  final List<String> highlights; // ≤3 个瞬间
  final String model; // 生成时使用的模型名
  final String photoSig; // 当日照片集合指纹（排序后 path|mtime 拼接的哈希）
  final int createdAtMs;

  const AiSummary({
    required this.dayKey,
    required this.title,
    required this.narrative,
    required this.tags,
    required this.mood,
    required this.highlights,
    required this.model,
    required this.photoSig,
    required this.createdAtMs,
  });

  /// 心情 → 节点/详情页的展示符号（新海诚式天气隐喻）。
  static const moodIcons = <String, String>{
    '晴': '☀',
    '多云': '☁',
    '小雨': '☂',
    '彩虹': '🌈',
    '星夜': '✦',
  };

  String get moodIcon => moodIcons[mood] ?? '☀';

  Map<String, Object?> toMap() => {
        'day_key': dayKey,
        'title': title,
        'narrative': narrative,
        'tags_json': tags,
        'mood': mood,
        'highlights_json': highlights,
        'model': model,
        'photo_sig': photoSig,
        'created_at': createdAtMs,
      };

  /// tags_json / highlights_json 在 SQL 实现里是 JSON 字符串，
  /// 这里统一支持「已是 List」与「JSON 字符串」两种输入，宽容解析。
  factory AiSummary.fromMap(Map<String, Object?> m) {
    List<String> strList(Object? v) {
      if (v is List) return v.cast<String>();
      if (v is String && v.isNotEmpty) {
        // 允许直接传 JSON 数组字符串
        final trimmed = v.trim();
        if (trimmed.startsWith('[')) {
          try {
            final decoded = _jsonDecodeList(trimmed);
            if (decoded != null) return decoded;
          } catch (_) {/* 落到下面的逗号分割 */}
        }
        return trimmed.split(',').map((e) => e.trim()).toList();
      }
      return const [];
    }

    return AiSummary(
      dayKey: (m['day_key'] as num).toInt(),
      title: m['title'] as String,
      narrative: m['narrative'] as String,
      tags: strList(m['tags_json'] ?? m['tags']),
      mood: m['mood'] as String? ?? '晴',
      highlights: strList(m['highlights_json'] ?? m['highlights']),
      model: m['model'] as String? ?? '',
      photoSig: m['photo_sig'] as String? ?? '',
      createdAtMs: (m['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// JSON 数组解码小工具（tags/highlights 在 SQL 实现里是 JSON 字符串）。
List<String>? _jsonDecodeList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.cast<String>();
  } catch (_) {/* 由调用方回退到逗号分割 */}
  return null;
}

// ============================================================================
// ManualNote：无照片日的手写补记（纯人写，与 AI 总结互不覆盖）
// ============================================================================

/// 一天的手写补记。与 [AiSummary] 是两条独立记录：
/// 重新生成 AI 总结不会动它，删除总结也不会删它（反之亦然）。
class ManualNote {
  final int dayKey;
  final String body; // 正文（纯文本，允许几百字）
  final int updatedAtMs;

  const ManualNote({
    required this.dayKey,
    required this.body,
    required this.updatedAtMs,
  });

  Map<String, Object?> toMap() => {
        'day_key': dayKey,
        'body': body,
        'updated_at': updatedAtMs,
      };

  factory ManualNote.fromMap(Map<String, Object?> m) => ManualNote(
        dayKey: (m['day_key'] as num).toInt(),
        body: m['body'] as String? ?? '',
        updatedAtMs: (m['updated_at'] as num?)?.toInt() ?? 0,
      );
}

// ============================================================================
// MonthlyReview：月度 AI 回顾（把当月的日总结再浓缩成一篇月报）
// ============================================================================

/// 一个月的 AI 回顾。inputSig 是成员日总结内容的指纹：
/// 任何一条日总结被编辑/重生成/删除，或月内新增总结，指纹都会变 → 月报标失效。
class MonthlyReview {
  final int year;
  final int month;
  final String title; // 月报标题，如「九月的风」
  final String narrative; // 300-600 字月度散文
  final List<String> tags; // 当月主题标签
  final List<String> highlights; // 当月亮点（≤5）
  final String model; // 生成模型
  final String inputSig; // 成员日总结内容指纹（computeMonthlyInputSig）
  final int createdAtMs;

  const MonthlyReview({
    required this.year,
    required this.month,
    required this.title,
    required this.narrative,
    required this.tags,
    required this.highlights,
    required this.model,
    required this.inputSig,
    required this.createdAtMs,
  });

  /// 存储主键 yyyyMM（与 sqflite 复合主键 / hive 字符串键对齐）。
  int get key => year * 100 + month;

  Map<String, Object?> toMap() => {
        'year': year,
        'month': month,
        'title': title,
        'narrative': narrative,
        'tags_json': tags,
        'highlights_json': highlights,
        'model': model,
        'input_sig': inputSig,
        'created_at': createdAtMs,
      };

  factory MonthlyReview.fromMap(Map<String, Object?> m) {
    List<String> strList(Object? v) {
      if (v is List) return v.cast<String>();
      if (v is String && v.isNotEmpty) {
        final trimmed = v.trim();
        if (trimmed.startsWith('[')) {
          try {
            final decoded = _jsonDecodeList(trimmed);
            if (decoded != null) return decoded;
          } catch (_) {/* 落到逗号分割 */}
        }
        return trimmed.split(',').map((e) => e.trim()).toList();
      }
      return const [];
    }

    return MonthlyReview(
      year: (m['year'] as num).toInt(),
      month: (m['month'] as num).toInt(),
      title: m['title'] as String? ?? '',
      narrative: m['narrative'] as String? ?? '',
      tags: strList(m['tags_json'] ?? m['tags']),
      highlights: strList(m['highlights_json'] ?? m['highlights']),
      model: m['model'] as String? ?? '',
      inputSig: m['input_sig'] as String? ?? '',
      createdAtMs: (m['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 月报输入指纹：当月日总结的「成员 + 内容」哈希。
///
/// 与 [computePhotoSig] 同一套失效哲学——内容驱动，不记时间戳：
/// 改一条日总结、补一条、删一条，都会让已生成的月报标为过期。
/// 只看用户可见内容（day_key/title/narrative/tags/mood/highlights），
/// 不含 model/photo_sig（换模型重生成同内容不算变化）。
String computeMonthlyInputSig(List<AiSummary> monthSummaries) {
  final canonical = monthSummaries.map((s) {
    return [
      s.dayKey,
      s.title,
      s.narrative,
      s.tags.join('、'),
      s.mood,
      s.highlights.join('、'),
    ].join('|');
  }).toList()
    ..sort();
  return sha1.convert(utf8.encode(canonical.join('\n'))).toString();
}

// ============================================================================
// PhotoSource：扫描源
// ============================================================================

enum SourceType {
  folder, // 本地文件夹（桌面/移动 SAF 目录）
  gallery, // 手机相册（photo_manager，仅移动端）
  webPick, // Web 手动多选（非 Chromium 降级）
}

/// 一个用户配置的照片来源。
class PhotoSource {
  final int id;
  final SourceType type;
  final String path; // 文件夹路径 / 'gallery' / 'web'
  final bool enabled;
  final int? lastScanMs;

  const PhotoSource({
    this.id = 0,
    required this.type,
    required this.path,
    this.enabled = true,
    this.lastScanMs,
  });

  /// 展示名：文件夹取末段，其它用固定文案。
  String get displayName {
    switch (type) {
      case SourceType.folder:
        final clean = path.replaceAll(RegExp(r'[\\/]+$'), '');
        return clean.split(RegExp(r'[\\/]')).last.isEmpty
            ? path
            : clean.split(RegExp(r'[\\/]')).last;
      case SourceType.gallery:
        return '手机相册';
      case SourceType.webPick:
        return '网页手动导入';
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'path': path,
        'enabled': enabled ? 1 : 0,
        'last_scan_ms': lastScanMs,
      };

  factory PhotoSource.fromMap(Map<String, Object?> m) => PhotoSource(
        id: (m['id'] as num?)?.toInt() ?? 0,
        type: SourceType.values.firstWhere(
          (t) => t.name == m['type'],
          orElse: () => SourceType.folder,
        ),
        path: m['path'] as String,
        enabled: ((m['enabled'] as num?)?.toInt() ?? 1) == 1,
        lastScanMs: (m['last_scan_ms'] as num?)?.toInt(),
      );
}

// ============================================================================
// ScanProgress：扫描进度（Stream 逐帧推送给设置页）
// ============================================================================

enum ScanPhase {
  idle,
  listing, // 正在枚举文件/资产
  parsing, // 正在解析 EXIF / 分组
  indexing, // 正在落库与重算聚合
  done,
  error,
}

class ScanProgress {
  final ScanPhase phase;
  final int scanned; // 已检查文件数
  final int added; // 本次新增/变更数
  final String? currentPath; // 当前处理项（可空）
  final String? errorMessage;

  const ScanProgress({
    required this.phase,
    this.scanned = 0,
    this.added = 0,
    this.currentPath,
    this.errorMessage,
  });

  bool get finished => phase == ScanPhase.done || phase == ScanPhase.error;
}

// ============================================================================
// AiConfig：AI 配置（敏感的 apiKey 不在此结构里，走 secure storage 单独存）
// ============================================================================

enum AiProviderKind {
  anthropic, // Anthropic Messages API
  openai, // OpenAI Chat Completions（含一切兼容中转）
}

class AiConfig {
  final AiProviderKind provider;
  final String baseUrl; // anthropic 可空→官方；openai 必填（兼容中转）
  final String model; // 默认 claude-opus-5-5
  final int maxImagesPerDay; // 每日送审图片上限（成本护栏）
  final String effort; // low | medium | high（Anthropic output_config.effort）

  const AiConfig({
    required this.provider,
    this.baseUrl = '',
    this.model = 'claude-opus-5-5',
    this.maxImagesPerDay = 12,
    this.effort = 'low',
  });

  /// 默认配置：Anthropic 官方端点 + opus 默认模型。
  static const anthropicDefault = AiConfig(provider: AiProviderKind.anthropic);

  /// OpenAI 兼容必须手填 baseUrl；model 预设留空由用户填。
  static const openaiPreset = AiConfig(
    provider: AiProviderKind.openai,
    model: 'gpt-4o',
  );

  /// 模型预设（设置页下拉）。费用差异由用户自行取舍。
  static const modelPresets = <(AiProviderKind, String, String)>[
    (AiProviderKind.anthropic, 'claude-opus-5-5', 'Claude Opus 5.5 · 最强理解力（默认）'),
    (AiProviderKind.anthropic, 'claude-sonnet-5-5', 'Claude Sonnet 5.5 · 日常够用，成本约半'),
    (AiProviderKind.openai, 'gpt-4o', 'GPT-4o · OpenAI 官方'),
  ];

  AiConfig copyWith({
    AiProviderKind? provider,
    String? baseUrl,
    String? model,
    int? maxImagesPerDay,
    String? effort,
  }) =>
      AiConfig(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        maxImagesPerDay: maxImagesPerDay ?? this.maxImagesPerDay,
        effort: effort ?? this.effort,
      );

  Map<String, Object?> toMap() => {
        'provider': provider.name,
        'base_url': baseUrl,
        'model': model,
        'max_images_per_day': maxImagesPerDay,
        'effort': effort,
      };

  factory AiConfig.fromMap(Map<String, Object?> m) => AiConfig(
        provider: AiProviderKind.values.firstWhere(
          (p) => p.name == m['provider'],
          orElse: () => AiProviderKind.anthropic,
        ),
        baseUrl: m['base_url'] as String? ?? '',
        model: m['model'] as String? ?? 'claude-opus-5-5',
        maxImagesPerDay: (m['max_images_per_day'] as num?)?.toInt() ?? 12,
        effort: m['effort'] as String? ?? 'low',
      );
}
