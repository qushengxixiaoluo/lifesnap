/// 天空背景组合组件（A 轨交付版）。
///
/// 【钉死的签名】C/E 轨盲写对接：内部自监听 AppStyleNotifier.current 与
/// ArtStyleNotifier.current（天色、画风两轴），调用方无需传参；child 叠在天空之上。
///
/// 性能纪律：
/// 1) 单个 60s 循环 AnimationController 驱动全部循环动画（云漂移 / 光束呼吸 /
///    星闪），从同一相位推导——多控制器会各自漂移，久了时间轴对不齐；
/// 2) 每层之间都套 RepaintBoundary：云动只重绘云层自己的位图；
/// 3) child 放在 AnimatedBuilder 外面：循环 tick 既不 rebuild child，
///    也不触发它的 paint——地图层被云「带着重绘」是本组件最要避免的事；
/// 4) 换天色/换画风共用同一个 600ms crossfade（过渡不是循环动画，
///    不占循环时间轴），颜色逐通道插值 = 整幅画面同步过渡。
///
/// 无约束保护：若被放进无界容器（滚动区），直接退化为裸 child，
/// 避免 Stack(fit: expand) 的无限尺寸断言。
library;

import 'package:flutter/material.dart';

import '../app/app_style.dart';
import 'painters/cloud_painter.dart';
import 'painters/hills_painter.dart';
import 'painters/paper_grain_painter.dart';
import 'painters/sky_gradient_painter.dart';
import 'painters/stars_painter.dart';
import 'painters/sun_rays_painter.dart';

class SkyBackground extends StatefulWidget {
  const SkyBackground({super.key, required this.child});

  /// 叠在天空之上的内容（月度地图等）；天空动画不触发它重绘。
  final Widget child;

  @override
  State<SkyBackground> createState() => _SkyBackgroundState();
}

class _SkyBackgroundState extends State<SkyBackground>
    with TickerProviderStateMixin {
  /// 循环基周期：60s。云漂移一整圈、光束呼吸 15 个来回、星闪周期（60/n）
  /// 全部整除它——所有循环动画共用这一个时间轴，缝合点天然连续。
  static const Duration _loopPeriod = Duration(seconds: 60);

  /// 换肤 crossfade 时长（产品要求 600ms）。
  static const Duration _fadeDuration = Duration(milliseconds: 600);

  late final AnimationController _loopCtrl;
  late final AnimationController _fadeCtrl;

  /// crossfade 的起点/终点画面状态：fade=0 取 [_from]，fade=1 取 [_to]。
  ///
  /// 为什么存可插值的混合态而不是 AppStyle 枚举：过渡进行到一半时，
  /// 屏幕上是「50% 混色」的中间画面，枚举表达不了它。把当前显示态
  /// 冻结成 [_BlendState] 后，连续换肤才能从真实起点接力淡入（见 [_onSkinChanged]）。
  _BlendState _from = _BlendState.of(
      AppStyleNotifier.current.value, ArtStyleNotifier.current.value);
  _BlendState _to = _BlendState.of(
      AppStyleNotifier.current.value, ArtStyleNotifier.current.value);

  /// 目标「天色 × 画风」，仅用于去重判断（防止同组合重复 setState 重启 fade）。
  AppStyle _toStyle = AppStyleNotifier.current.value;
  ArtStyle _toArt = ArtStyleNotifier.current.value;

  @override
  void initState() {
    super.initState();
    _loopCtrl = AnimationController(vsync: this, duration: _loopPeriod)
      ..repeat();
    _fadeCtrl = AnimationController(vsync: this, duration: _fadeDuration);
    // 内部自监听两根轴：调用方只管换 Notifier，本组件负责平滑过渡。
    // 换画风与换天色走同一条 600ms crossfade 路径（不闪屏）。
    AppStyleNotifier.current.addListener(_onSkinChanged);
    ArtStyleNotifier.current.addListener(_onSkinChanged);
  }

  void _onSkinChanged() {
    final nextStyle = AppStyleNotifier.current.value;
    final nextArt = ArtStyleNotifier.current.value;
    // 去重要同时比天色与画风：只比天色会漏掉「同一档天色下换画风」，
    // 旧纸↔糖果就不再触发过渡（画面干跳一下）。
    if (!mounted || (nextStyle == _toStyle && nextArt == _toArt)) return;
    // 关键：按当前 fade 进度把「屏幕上正在显示的插值中间态」快照成新起点。
    // 旧写法 _from = _to 拿的是上一次的目标皮肤：日光→星夜进行到一半再点黄昏，
    // 画面会先整幅跳成星夜再往黄昏淡，肉眼可见一次色阶突跳。
    final snapshot = _blendAt(_fadeCtrl.value);
    setState(() {
      _from = snapshot;
      // 此刻两个 Notifier 都已是新值：tokensFor 读到的目标即下一帧的终态
      _to = _BlendState.of(nextStyle, nextArt);
      _toStyle = nextStyle;
      _toArt = nextArt;
    });
    // forward(from:0)：从冻结的真实起点重新开始 600ms 接力淡入，全程无跳变
    _fadeCtrl.forward(from: 0);
  }

  /// 当前显示态快照：按 fade 进度在 [_from]→[_to] 之间插值。
  _BlendState _blendAt(double t) => _BlendState.lerp(_from, _to, t);

  @override
  void dispose() {
    AppStyleNotifier.current.removeListener(_onSkinChanged);
    ArtStyleNotifier.current.removeListener(_onSkinChanged);
    _loopCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 无界约束（滚动容器内）：Stack 的 expand 会断言崩溃，退化为裸 child
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return widget.child;
        }
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            // 背景层组整体再套一层 RepaintBoundary：内部怎么闹都传不出去
            RepaintBoundary(
              child: AnimatedBuilder(
                // 唯一循环时间轴 + 换肤过渡，合并成一个监听源
                animation: Listenable.merge([_loopCtrl, _fadeCtrl]),
                builder: (context, _) => _buildSky(size),
              ),
            ),
            widget.child, // 地图层：不在 AnimatedBuilder 内，逐帧零参与
          ],
        );
      },
    );
  }

  /// 组合六层画面（自下而上）：渐变 → 光束 → 星空 → 云 → 草坡 → 纸纹。
  Widget _buildSky(Size size) {
    final t = _fadeCtrl.value;
    // 颜色逐通道插值 + 开关量线性过渡 = 整幅画面的 600ms crossfade
    final s = _blendAt(t);

    final top = s.top;
    final mid = s.mid;
    final horizon = s.horizon;
    final glow = s.glow;
    final grass = s.grass;

    // 布尔开关（星/光束）没法插值，改成透明度渐入渐出，层的挂载/卸载不可见
    final rayOp = s.rayOp;
    final starOp = s.starOp;
    // 夜色程度：决定云的灰蓝深浅（日/黄昏云白，星夜云转月光色）
    final night = s.night;

    // 云色随画风走：糖果是「保卫萝卜泡云」（灰蓝描边），
    // 旧纸是「纸上晕开的淡墨团」（暖褐描边）——两套各自按夜色深浅调完，
    // 再按画风过渡量 s.aged 插值，换画风时云也一起 600ms 渐变而不是硬切。
    final candyFill = Color.lerp(
      ShiguangColors.cloudWhite,
      ShiguangColors.nightTop,
      night * 0.5,
    )!;
    final agedFill = Color.lerp(
      const Color(0xFFF8F1DC), // 干纸上的淡云
      const Color(0xFF4E4230), // 暗纸上的云：比夜纸亮一档才有体积
      night,
    )!;
    final candyLine = Color.lerp(
      const Color(0xFFA9B7C7),
      ShiguangColors.nightMid,
      night,
    )!;
    final agedLine = Color.lerp(
      const Color(0xFF9A8A6B), // 旧云的褐线（插图描线）
      const Color(0xFF6A5B44),
      night,
    )!;
    final cloudFill = Color.lerp(candyFill, agedFill, s.aged)!;
    final cloudLine = Color.lerp(candyLine, agedLine, s.aged)!;
    // 远坡混入地平线光 = 空气透视（近坡用纯草色）
    final hillBack = Color.lerp(grass, horizon, 0.42)!;

    final p = _loopCtrl.value; // 全部循环动画的唯一相位来源

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1) 天空三段渐变（静态层：仅换肤时重绘，引擎可缓存）
        RepaintBoundary(
          child: CustomPaint(
            painter: SkyGradientPainter(top: top, mid: mid, horizon: horizon),
            isComplex: true,
          ),
        ),
        // 2) 太阳光束（呼吸 + 摇摆，逐帧）
        if (rayOp > 0.003)
          RepaintBoundary(
            child: CustomPaint(
              painter: SunRaysPainter(progress: p, opacity: rayOp, glow: glow),
              willChange: true,
            ),
          ),
        // 3) 星空（逐帧）
        if (starOp > 0.003)
          RepaintBoundary(
            child: CustomPaint(
              painter: StarsPainter(
                progress: p,
                opacity: starOp,
                color: ShiguangColors.starWhite,
              ),
              willChange: true,
            ),
          ),
        // 4) 云（漂移逐帧；独立边界 = 地图层不陪跑）
        RepaintBoundary(
          child: CustomPaint(
            painter: CloudPainter(progress: p, fill: cloudFill, line: cloudLine),
            willChange: true,
          ),
        ),
        // 5) 双层草坡（静态层：换肤变色，循环 tick 指纹不变不重绘）
        RepaintBoundary(
          child: CustomPaint(
            painter: HillsPainter(back: hillBack, front: grass),
            isComplex: true,
          ),
        ),
        // 6) 宣纸噪点（完全静态）
        const RepaintBoundary(
          child: CustomPaint(painter: PaperGrainPainter(), isComplex: true),
        ),
      ],
    );
  }
}

/// 换肤/换画风 crossfade 的可插值画面状态快照（A 轨私有）。
///
/// 为什么不直接用 AppStyle 枚举做 crossfade 起点：枚举只能指向整套皮肤，
/// 过渡中途「50% 混色」的中间画面无法用枚举表达。把颜色与开关量拆成
/// 可 lerp 的字段后，任意时刻都能把屏幕上的真实显示态冻结成新起点，
/// 连续快速换肤（设置页连点皮肤/画风）因此不会出现色阶突跳。
class _BlendState {
  const _BlendState({
    required this.top,
    required this.mid,
    required this.horizon,
    required this.glow,
    required this.grass,
    required this.rayOp,
    required this.starOp,
    required this.night,
    required this.aged,
  });

  /// 从「天色 × 画风」令牌推导终态：
  /// 布尔开关折成 0/1，夜色与画风（旧纸度）也折成可插值的 0/1。
  ///
  /// 走 [tokensFor] 纯函数（显式传画风）而不是 skyOf 全局包装，
  /// 因为换画风的瞬间需要的是「目标画风」的令牌，而非可能尚未落定的全局读数。
  factory _BlendState.of(AppStyle style, ArtStyle art) {
    final tokens = tokensFor(style, art);
    return _BlendState(
      top: tokens.top,
      mid: tokens.mid,
      horizon: tokens.horizon,
      glow: tokens.glow,
      grass: tokens.grass,
      rayOp: tokens.showSunRays ? 1.0 : 0.0,
      starOp: tokens.showStars ? 1.0 : 0.0,
      night: style == AppStyle.night ? 1.0 : 0.0,
      aged: art == ArtStyle.agedInk ? 1.0 : 0.0,
    );
  }

  final Color top;
  final Color mid;
  final Color horizon;
  final Color glow;
  final Color grass;

  /// 光束层可见度（showSunRays 折成的 0/1）：过渡期按透明度淡入淡出。
  final double rayOp;

  /// 星空层可见度（showStars 折成的 0/1）：同上，层的挂载/卸载不可见。
  final double starOp;

  /// 夜色程度 0/1：决定云的灰蓝深浅（日/黄昏云白，星夜云转月光色）。
  final double night;

  /// 旧纸度 0/1（画风轴的可插值投影）：糖果 0 → 油墨旧纸 1，
  /// 决定云色等「画风特有」图层在 crossfade 中间的混入比例。
  final double aged;

  /// 两态按 t∈[0,1] 插值：颜色逐通道（Color.lerp），开关量线性过渡——
  /// 换天色、换画风与连续换肤共用这一条路径，保证任意时刻都能冻结中间态。
  static _BlendState lerp(_BlendState a, _BlendState b, double t) {
    return _BlendState(
      top: Color.lerp(a.top, b.top, t)!,
      mid: Color.lerp(a.mid, b.mid, t)!,
      horizon: Color.lerp(a.horizon, b.horizon, t)!,
      glow: Color.lerp(a.glow, b.glow, t)!,
      grass: Color.lerp(a.grass, b.grass, t)!,
      rayOp: a.rayOp + (b.rayOp - a.rayOp) * t,
      starOp: a.starOp + (b.starOp - a.starOp) * t,
      night: a.night + (b.night - a.night) * t,
      aged: a.aged + (b.aged - a.aged) * t,
    );
  }
}
