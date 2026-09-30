/// D 轨 · 宽容 JSON 解析（三级降级 + 收敛裁剪）。
///
/// 现实里模型会给出：裸 JSON、```json 围栏、先说一句话再给 JSON、
/// 甚至把 JSON 截断——本文件把这些形态全部锁死。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/ai/ai_provider.dart';
import 'package:shiguang_handbook/core/ai/ai_schemas.dart';

const int dayKey = 20260930;
const String model = 'claude-opus-5-5';
const String sig = 'abc123';

String bareJson({
  String title = '晒棉被的下午',
  String narrative = '阳光把阳台晒得发烫，你把去年冬天的棉被搭在栏杆上，'
      '拍了拍扬起的灰尘，楼下收废品的三轮车叮叮当当地过去，'
      '整条街都像被熨平了一样安静，连猫都懒得挪窝。',
  List<String> tags = const <String>['晴天', '家务'],
  String mood = '多云',
  List<String> highlights = const <String>['晒棉被'],
}) =>
    jsonEncode(<String, Object?>{
      'title': title,
      'narrative': narrative,
      'tags': tags,
      'mood': mood,
      'highlights': highlights,
    });

void main() {
  group('三级解析降级链', () {
    test('第一级：裸 JSON 字符串', () {
      final s = parseAiSummary(bareJson(), dayKey, model, sig);
      expect(s.title, '晒棉被的下午');
      expect(s.narrative, contains('阳台'));
      expect(s.tags, <String>['晴天', '家务']);
      expect(s.mood, '多云');
      expect(s.highlights, <String>['晒棉被']);
      expect(s.dayKey, dayKey);
      expect(s.model, model);
      expect(s.photoSig, sig);
    });

    test('第一级：结构化对象直传（Map）', () {
      final s = parseAiSummary(
        <String, Object?>{
          'title': '结构化直传',
          'narrative': '这是直接给到的结构化字段，不经过任何字符串解析，'
              '用于兼容那些已经帮我们解好 JSON 的中转服务。',
          'tags': <String>['直传'],
          'mood': '彩虹',
          'highlights': <String>['直传'],
        },
        dayKey,
        model,
        sig,
      );
      expect(s.title, '结构化直传');
      expect(s.mood, '彩虹');
    });

    test('第二级：拼接 content 块数组（Anthropic 回执形态）', () {
      final s = parseAiSummary(
        <Object?>[
          <String, Object?>{'type': 'text', 'text': '这是第一段说明文字，本身不是 JSON。'},
          <String, Object?>{'type': 'text', 'text': bareJson()},
        ],
        dayKey,
        model,
        sig,
      );
      expect(s.title, '晒棉被的下午');
    });

    test('第二级：{content: "..."} 外壳', () {
      final s = parseAiSummary(
        <String, Object?>{'content': bareJson()},
        dayKey,
        model,
        sig,
      );
      expect(s.title, '晒棉被的下午');
    });

    test('第三级：剥掉 markdown 代码围栏', () {
      final fenced = '```json\n${bareJson()}\n```';
      final s = parseAiSummary(fenced, dayKey, model, sig);
      expect(s.title, '晒棉被的下午');
    });

    test('第三级：围栏 + 前面还有废话', () {
      final text = '好的，我看完这一天的照片了，下面是总结：\n'
          '```json\n${bareJson()}\n```\n希望你喜欢。';
      final s = parseAiSummary(text, dayKey, model, sig);
      expect(s.title, '晒棉被的下午');
    });

    test('第三级：截首个 { 到末个 } 的垃圾前缀', () {
      final text = 'assistant 说：好的，这一天给我印象很深。\n'
          '以下是 JSON 输出：\n${bareJson()}\n（完）';
      final s = parseAiSummary(text, dayKey, model, sig);
      expect(s.title, '晒棉被的下午');
    });

    test('三级全失败 → AiFormatException', () {
      // 真·截断：右花括号被吃掉，任何一级都还原不出来
      final truncated = '照着要求给你总结：${bareJson().substring(0, 40)}';
      expect(
        () => parseAiSummary(truncated, dayKey, model, sig),
        throwsA(isA<AiFormatException>()),
      );
      expect(
        () => parseAiSummary('我今天不想写总结。', dayKey, model, sig),
        throwsA(isA<AiFormatException>()),
      );
      expect(
        () => parseAiSummary(<Object?>[], dayKey, model, sig),
        throwsA(isA<AiFormatException>()),
      );
      expect(
        () => parseAiSummary(null, dayKey, model, sig),
        throwsA(isA<AiFormatException>()),
      );
    });
  });

  group('宽容收敛', () {
    test('标题超 12 字被截断，tags/highlights 超上限被裁', () {
      final s = parseAiSummary(
        bareJson(
          title: '这是一个非常非常长的以至于一定会超过十二个字的标题',
          tags: <String>['一', '二', '三', '四', '五', '六', '七', '八'],
          highlights: <String>['甲', '乙', '丙', '丁', '戊'],
        ),
        dayKey,
        model,
        sig,
      );
      expect(s.title.length, 12);
      expect(s.tags, hasLength(6));
      expect(s.highlights, hasLength(3));
    });

    test('标题第 12 字是 emoji 时按码点截断，不产生孤立代理项', () {
      // JSON Schema 的 maxLength 按码点计数：12 码点里含 emoji 属合法输入，
      // 按 UTF-16 码元 substring(0,12) 会把代理对劈一半，
      // 落库 jsonEncode / utf8 编码会产出坏数据、界面显示乱码。
      final s = parseAiSummary(
        bareJson(title: '一二三四五六七八九😀🎉🚀还有一长串废话'),
        dayKey,
        model,
        sig,
      );
      expect(s.title.runes.length, 12, reason: '上限按码点计数');
      expect(
        s.title.runes.any((r) => r >= 0xD800 && r <= 0xDFFF),
        isFalse,
        reason: '截断处不得残留半个 emoji（孤立代理项）',
      );
      expect(s.title, '一二三四五六七八九😀🎉🚀');
    });

    test('非法 mood 回落「晴」，合法 mood 保留', () {
      final bad = parseAiSummary(bareJson(mood: '暴风雨'), dayKey, model, sig);
      expect(bad.mood, '晴');
      final good = parseAiSummary(bareJson(mood: '星夜'), dayKey, model, sig);
      expect(good.mood, '星夜');
    });

    test('tags 是逗号/顿号连写的字符串也能读', () {
      final s = parseAiSummary(
        jsonEncode(<String, Object?>{
          'title': '逗号连写',
          'narrative': '模型有时不给数组，直接给一个用顿号连起来的字符串，'
              '这里必须能兜住，否则用户看到的就是一张空标签卡片。',
          'tags': '海边、黄昏、单车',
          'mood': '晴',
          'highlights': '追风,分冰棍',
        }),
        dayKey,
        model,
        sig,
      );
      expect(s.tags, <String>['海边', '黄昏', '单车']);
      expect(s.highlights, <String>['追风', '分冰棍']);
    });

    test('缺 title 或 narrative 不算日总结 → 继续降级直至失败', () {
      expect(
        () => parseAiSummary(
          jsonEncode(<String, Object?>{'title': '只有标题', 'tags': <String>[]}),
          dayKey,
          model,
          sig,
        ),
        throwsA(isA<AiFormatException>()),
      );
    });

    test('createdAtMs 会被填上（落库排序依赖它）', () {
      final s = parseAiSummary(bareJson(), dayKey, model, sig);
      expect(s.createdAtMs, greaterThan(0));
    });
  });
}
