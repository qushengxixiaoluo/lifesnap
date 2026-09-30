/// 闯关地图 · 糖果风局部色板（保卫萝卜 / 燃烧的蔬菜 Q版糖果塔防风）
///
/// 为什么新建本文件而不是写进 ShiguangColors：
/// `lib/app/app_style.dart` 是跨轨只读契约（铁律：非设计轨禁改），
/// 而 C 轨白名单只有 `lib/features/calendar_map/**`——糖果色只能在本轨内
/// 自建一套私有令牌。命名与 ShiguangColors 对位（描边/奶油/强调各一名），
/// 便于日后设计轨统一收编时机械替换。
///
/// 为什么这些颜色不随 AppStyle 皮肤变：它们是「玩具本身」的漆面，
/// 三套皮肤（日光/黄昏/星夜）变的是天空（SkyBackground 在 A 轨），
/// 地图上的糖果扣与公路在任何天空下都保持同一套高饱和漆面，
/// 这正是糖果塔防「UI 是玩具、背景是舞台」的层次关系。
///
/// 例外只有一个：描边色。画风换到 LowPoly 时轮廓要变成 #141414 近黑，
/// 所以地图上的描边一律改调画风感知的 `outlineNow()/outlineFor(art)`
/// （app_style 提供），本文件的 [CandyColors.outline] 只作「糖果端点」的
/// 命名入口与单一来源（值取自 ShiguangColors.candyOutline，勿手改字面量）。
library;

import 'package:flutter/material.dart';

import '../../app/app_style.dart';

class CandyColors {
  CandyColors._();

  // —— 描边 / 底色（风格圣经第 1、2 条：深巧克力棕统一描边 + 奶黄面板底）——

  /// 统一描边：深巧克力棕。一切形状厚描边 3-5px 都用它，
  /// 代替旧版的墨棕细线，轮廓要「玩具感」不要「纸片感」。
  ///
  /// 只代表**糖果画风**这一端；需要随画风切换的描边请调 outlineNow()。
  static const outline = ShiguangColors.candyOutline;

  /// 奶油面板底（头部木牌、空日素扣的漆面基色）。
  static const cream = Color(0xFFFFF5DC);

  /// 奶油暗面：果冻按钮「上亮下暗」渐变的下缘色。
  static const creamDark = Color(0xFFF2DFB4);

  // —— 糖果强调色（高饱和明快，禁止莫兰迪）——

  /// 糖果橙：公路分道线、按钮强调。
  static const orange = Color(0xFFFF9A3C);
  static const orangeDark = Color(0xFFF07A18); // 橙的下缘暗色

  /// 糖果粉：今日关卡、彩带徽章。
  static const pink = Color(0xFFFF6FA5);
  static const pinkDark = Color(0xFFE84E8A);

  /// 糖果紫：备用强调（未来若加紫色钮可直接取用）。
  static const purple = Color(0xFFB07CF5);

  /// 星星金：已总结徽章。
  static const gold = Color(0xFFFFC93C);
  static const goldDark = Color(0xFFF0A21E);

  /// 高亮白：果冻顶部高光弧 / 有图节点的白描边。
  static const glossWhite = Color(0xFFFFFFFF);

  // —— 状态辅色 —

  /// 未解锁灰扣的上下缘（上亮下暗）。
  static const grayTop = Color(0xFFDDE1E8);
  static const grayBottom = Color(0xFFA8AEB8);

  /// 未来雾罩：卡通化后的淡蓝白（比旧 futureMist 更亮更奶）。
  static const mist = Color(0xFFD8ECFF);

  // —— 预置渐变（上亮下暗，风格圣经第 3 条「果冻按钮」）——

  /// 奶油素扣（空日）。
  static const creamFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFBEA), creamDark],
  );

  /// 金橙通关扣（已总结）。
  static const goldFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFD866), goldDark],
  );

  /// 糖果粉今日扣。
  static const pinkFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF8FB8), pinkDark],
  );

  /// 灰色未解锁扣。
  static const grayFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [grayTop, grayBottom],
  );

  /// 头部木牌 / 糖果圆钮的橙面。
  static const orangeFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFB55C), orangeDark],
  );

  /// 头部木牌的奶油底（标题胶囊）。
  static const panelFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFBEA), Color(0xFFFFEBBF)],
  );
}
