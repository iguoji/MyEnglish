///
/// 当天四种复习模式共用的固定单词计划。
///
/// [wordIds] 的顺序就是四个模块当天共同使用的答题顺序；[dailyGoal]
/// 在首次生成时冻结，设置中途变化只影响第二天的新计划。[selectionVersion]
/// 用来识别这批顺序由哪一版选词规则生成，规则升级时可以可靠重建一次。
///
class DailyReviewPlan {
  /// 创建一份每日公共复习计划。
  const DailyReviewPlan({
    required this.planDate,
    required this.dailyGoal,
    required this.wordIds,
    required this.selectionVersion,
    this.createdAt,
  });

  /// 设备本地日期，格式固定为 yyyy-MM-dd。
  final String planDate;

  /// 当天首次创建计划时使用的每日复习量。
  final int dailyGoal;

  /// 当天共用的单词主键快照，顺序不可变。
  final List<int> wordIds;

  /// 生成这份固定顺序时使用的选词规则版本；0 表示升级前的历史计划。
  final int selectionVersion;

  /// 原生数据库创建计划的时间，仅用于诊断。
  final DateTime? createdAt;

  ///
  /// 把原生 MethodChannel 返回的数据转换成强类型模型。
  ///
  /// @param  `Map<Object?, Object?>`  map 原生计划数据。
  /// @return DailyReviewPlan 完成校验的每日复习计划。
  ///
  factory DailyReviewPlan.fromMap(Map<Object?, Object?> map) {
    final planDate = map['plan_date']?.toString() ?? '';
    if (planDate.isEmpty) throw const FormatException('每日复习计划缺少 plan_date');
    final rawGoal = map['daily_goal'];
    if (rawGoal is! num || rawGoal.toInt() < 0) {
      throw const FormatException('每日复习计划 daily_goal 无效');
    }
    final rawIds = map['word_ids'];
    if (rawIds is! List) throw const FormatException('每日复习计划 word_ids 必须是数组');
    final ids = <int>[];
    for (final value in rawIds) {
      if (value is! num) throw const FormatException('每日复习计划单词 id 必须是数字');
      ids.add(value.toInt());
    }
    // 版本 11 以前没有 selection_version，缺失时按 0 处理以触发一次规则升级。
    final rawSelectionVersion = map['selection_version'] ?? 0;
    if (rawSelectionVersion is! num || rawSelectionVersion.toInt() < 0) {
      throw const FormatException('每日复习计划 selection_version 无效');
    }
    final rawCreatedAt = map['created_at'];
    return DailyReviewPlan(
      planDate: planDate,
      dailyGoal: rawGoal.toInt(),
      wordIds: List<int>.unmodifiable(ids),
      selectionVersion: rawSelectionVersion.toInt(),
      createdAt: rawCreatedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(rawCreatedAt.toInt())
          : null,
    );
  }
}
