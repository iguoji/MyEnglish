// flutter_test 提供 test、group 和 expect，使用方式类似 PHPUnit 的测试与断言。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的日期 helper，类似 PHPUnit 测试 require 业务函数文件。
import 'package:my_english/common/date.dart';

/// 测试程序入口；这里只登记测试用例，不会启动 Flutter 页面。
void main() {
  // 验证公用完整日期时间格式，首页和未来页面应复用该函数。
  group('formatFullDateTime', () {
    // 验证所有不足两位的字段都会补零。
    test('uses a fixed yyyy年MM月dd日 HH:mm:ss format', () {
      // 固定本地时间，避免断言受当前时间影响。
      final dateTime = DateTime(2026, 1, 2, 3, 4, 5);
      // 输出必须包含完整年月日和时分秒。
      expect(formatFullDateTime(dateTime), '2026年01月02日 03:04:05');
    });
  });

  // group 把同一个函数的测试归在一起，类似 PHPUnit 测试类。
  group('formatWordDate', () {
    // 固定“当前时间”，避免测试结果随着实际年份变化。
    final now = DateTime(2026, 7, 26, 12);

    // 验证今年的日期不显示年份，并且月份、日期会补零。
    test('uses MM.dd for a date in the current year', () {
      // expect 对应 PHPUnit assertSame：实际值必须等于期望值。
      expect(formatWordDate(DateTime(2026, 1, 2), now), '01.02');
      // 月日已经是两位时保持原值。
      expect(formatWordDate(DateTime(2026, 7, 26), now), '07.26');
    });

    // 验证非今年的日期会在前面增加四位年份。
    test('adds the year for a date outside the current year', () {
      // 去年的日期应显示年份。
      expect(formatWordDate(DateTime(2025, 7, 26), now), '2025.07.26');
      // 未来年份也应显示年份，避免逻辑只照顾历史数据。
      expect(formatWordDate(DateTime(2027, 1, 2), now), '2027.01.02');
    });
  });
}
