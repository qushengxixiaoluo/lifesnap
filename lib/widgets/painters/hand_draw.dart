/// 手绘描边公共工具（A 轨内部共享）。
///
/// 为什么单独抽一个文件：六个天空 painter 与 HandCard 都需要同一套「手绘感」规则——
/// 圆角笔帽、固定种子顶点抖动、低透明度铅笔复线。集中定义保证全 app 的线条手感一致，
/// 也避免每个 painter 各抄一份导致风格漂移（换肤时云和山的抖动幅度必须一样大）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 主描边画笔：round cap / round join 是手绘线条的基本笔触——
/// 笔锋两端圆润、拐角不尖锐，模拟针管笔/马克笔的收笔。
///
/// [alpha] 单独给：传入的 [color] 应是不透明基色，透明度在此统一覆盖，
/// 调用方不必关心基色自带的 alpha。
Paint handStroke({
  required Color color,
  required double width,
  double alpha = 1.0,
}) {
  return Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width
    ..color = color.withValues(alpha: alpha);
}

/// 确定性抖动：返回 [-amp, +amp] 的偏移。
///
/// 为什么用固定种子的 Random 而不是 math.Random()：手绘感要求「每次绘制一致」——
/// 同一条路径在不同帧、不同皮肤切换后都必须抖在同样的位置，否则顶点会帧间闪烁。
/// 调用方自己 new math.Random(seed)，每轮按固定顺序取值即可保证完全复现。
double handJitter(math.Random rng, double amp) =>
    (rng.nextDouble() * 2 - 1) * amp;
