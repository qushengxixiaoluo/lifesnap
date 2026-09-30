/// 阶段 0 冒烟测试：日期工具与照片指纹（契约行为锁定，五轨都依赖这些语义）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_handbook/core/models/models.dart';

void main() {
  test('dayKeyOf 归一化为 yyyymmdd 整数', () {
    expect(dayKeyOf(DateTime(2026, 9, 30)), 20260930);
    expect(dayKeyOf(DateTime(2026, 1, 5)), 20260105);
  });

  test('dayKey 往返转换', () {
    expect(dayKeyToDateTime(20260930), DateTime(2026, 9, 30));
    expect(dayKeyToString(20260930), '2026-09-30');
    expect(dayKeyToChinese(20260930), '9月30日');
  });

  test('daysInMonth 处理闰年', () {
    expect(daysInMonth(2026, 2), 28);
    expect(daysInMonth(2024, 2), 29);
    expect(daysInMonth(2026, 9), 30);
  });

  test('computePhotoSig 与顺序无关、内容敏感', () {
    Photo p(String path, int mtime) => Photo(
          path: path,
          fileSize: 1,
          mtimeMs: mtime,
          takenAtMs: mtime,
          dayKey: 20260930,
          sourceId: 1,
        );
    final a = [p('x.jpg', 1), p('y.jpg', 2)];
    final b = [p('y.jpg', 2), p('x.jpg', 1)]; // 顺序不同
    expect(computePhotoSig(a), computePhotoSig(b)); // 排序后应一致

    final c = [p('x.jpg', 1), p('y.jpg', 3)]; // mtime 变了
    expect(computePhotoSig(a), isNot(computePhotoSig(c)));
  });
}
