/// 某平台不支持的扫描方式占位实现。
///
/// 为什么不是简单返回空流：ScannerService 会对每个源推进度帧，
/// 空流会让设置页一直转圈；直接推一帧 error 能把「为什么扫不了」讲清楚，
/// UI 也能立刻结束本次流程。supported=false 则让 UI 提前隐藏入口按钮。
library;

import '../models/models.dart';
import 'scanner_contracts.dart';

class UnsupportedScanner implements PhotoSourceScanner {
  const UnsupportedScanner(this.reason);

  /// 不支持原因（直接展示给用户的中文文案）。
  final String reason;

  @override
  bool get supported => false;

  @override
  Stream<ScanProgress> scan(
    PhotoSource source, {
    required Map<String, int> knownPathToMtime,
  }) async* {
    yield ScanProgress(phase: ScanPhase.error, errorMessage: reason);
  }
}
