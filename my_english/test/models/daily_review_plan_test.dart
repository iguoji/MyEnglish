// flutter_test 提供 test、expect 与异常匹配器。
import 'package:flutter_test/flutter_test.dart';
// DailyReviewPlan 是本文件验证的平台返回值解析模型。
import 'package:my_english/models/daily_review_plan.dart';

///
/// 注册每日公共复习计划模型的版本兼容测试。
///
/// @return void
///
void main() {
  // 版本 10 保存的历史计划没有 selection_version，解析时必须兼容并标记为旧规则。
  test('treats a plan without selection version as legacy version zero', () {
    // 构造升级前原生层会返回的数据结构。
    final plan = DailyReviewPlan.fromMap(<Object?, Object?>{
      'plan_date': '2026-08-19',
      'daily_goal': 100,
      'word_ids': <int>[3, 2, 1],
      'created_at': 1,
    });

    // 0 会让首页在第一次进入复习模块时按当前规则重新生成一次。
    expect(plan.selectionVersion, 0);
  });

  // 新数据库返回的规则版本必须原样进入模型，供首页判断计划是否仍然有效。
  test('parses the persisted selection version', () {
    // 构造版本 11 原生层返回的完整数据结构。
    final plan = DailyReviewPlan.fromMap(<Object?, Object?>{
      'plan_date': '2026-08-19',
      'daily_goal': 100,
      'word_ids': <int>[1, 2, 3],
      'selection_version': 1,
      'created_at': 1,
    });

    // 当前计划应保留数据库中的版本 1，而不是被误判为历史计划。
    expect(plan.selectionVersion, 1);
  });
}
