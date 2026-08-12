// flutter_test 提供 test 与 expect，用来验证 Word 编辑后的业务字段。
import 'package:flutter_test/flutter_test.dart';
// 引入需要验证的单词模型。
import 'package:my_english/models/word.dart';

///
/// 验证单词编辑时多对多分组不会被表单的单选界面意外破坏。
///
/// @return void
///
void main() {
  // 用户只改拼写且没有切换主分组时，应完整保留原来的多个分组。
  test('editing preserves all groups when primary group is unchanged', () {
    // 构造同时属于 3、7 两个分组的既有单词。
    const word = Word(id: 1, spelling: 'old', groupIds: <int>[3, 7]);
    // 表单只能回填第一个分组 3，再提交新的拼写。
    final edited = word.edited(spelling: 'new', meanings: const [], groupId: 3);
    // 拼写正常更新。
    expect(edited.spelling, 'new');
    // 第二个分组 7 不能因表单不可见而静默丢失。
    expect(edited.groupIds, <int>[3, 7]);
  });

  // 用户明确选择其他分组时，仍按表单语义整体移动到新分组。
  test('editing replaces groups when primary group changes', () {
    // 构造同一个多分组单词。
    const word = Word(id: 1, spelling: 'old', groupIds: <int>[3, 7]);
    // 用户在表单中明确改选分组 9。
    final edited = word.edited(spelling: 'old', meanings: const [], groupId: 9);
    // 明确切换应收敛为用户选择的新分组。
    expect(edited.groupIds, <int>[9]);
  });
}
