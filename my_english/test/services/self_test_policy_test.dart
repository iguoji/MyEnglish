// flutter_test 提供 test、expect 等测试 API。
import 'package:flutter_test/flutter_test.dart';

// 被测试的选词规则：四个自测模块共用，页面与开局服务都读它。
import 'package:my_english/services/self_test_policy.dart';

///
/// 自测选词范围的边界测试。
///
/// 生活化解释：自测是「自己圈一批词来考自己」，所以两头都要有闸门——
/// 太少（不足 5 个）考不出什么，太多（超过 100 个）一局根本做不完。
/// 这条规则以前只在页面上体现（按钮禁用），没有任何测试钉住它的边界，
/// 于是「上限到底是多少、是 100 还是 101」只能靠读代码。
///
/// 这里把两个闸门各测一遍：正好压线通过、越线一步就被拒。
void main() {
  ///
  /// 两头的档位来自同一个地方，改动时不会只改一半。
  test('上下限是 5 与 100', () {
    expect(SelfTestPolicy.minWords, 5);
    expect(SelfTestPolicy.maxWords, 100);
    // 提示文案里的范围由这两档拼出来，不另写一份数字。
    expect(SelfTestPolicy.rangeLabel, '5–100 个单词');
  });

  group('接受的数量', () {
    // 下界、上界、以及中间随便取一个。
    for (final count in <int>[5, 6, 50, 99, 100]) {
      test('$count 个通过', () {
        expect(SelfTestPolicy.accepts(count), isTrue);
        expect(SelfTestPolicy.unavailableReason(count), isNull);
      });
    }
  });

  group('被拒绝的数量', () {
    test('一个都没勾：提示先勾选', () {
      expect(SelfTestPolicy.accepts(0), isFalse);
      expect(SelfTestPolicy.unavailableReason(0), '请先勾选 5–100 个单词');
    });

    test('不足下限：提示还差几个', () {
      for (final count in <int>[1, 2, 4]) {
        expect(SelfTestPolicy.accepts(count), isFalse);
        expect(
          SelfTestPolicy.unavailableReason(count),
          '已选 $count 个，还需选择 ${5 - count} 个',
        );
      }
    });

    test('超过上限：提示最多可选几个', () {
      for (final count in <int>[101, 150, 1000]) {
        expect(SelfTestPolicy.accepts(count), isFalse);
        expect(
          SelfTestPolicy.unavailableReason(count),
          '已选 $count 个，最多可选 100 个',
        );
      }
    });
  });
}
