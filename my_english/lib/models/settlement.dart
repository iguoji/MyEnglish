///
/// 结算页上的难度调整方向。
///
/// 这类数据属于业务结果，不属于某一个具体页面，所以单独放在模型层，
/// 让结算组件、会话进度和测试都能使用同一套值。
///
enum DifficultyAdjust {
  /// 难度增加 1。
  up,

  /// 难度减少 1。
  down,

  /// 难度不变。
  none,
}

///
/// 从难度变化量恢复结算页状态。
///
DifficultyAdjust difficultyAdjustFromDelta(int delta) {
  if (delta > 0) return DifficultyAdjust.up;
  if (delta < 0) return DifficultyAdjust.down;
  return DifficultyAdjust.none;
}

///
/// 把结算页状态转换成实际的难度变化量。
///
int difficultyAdjustDelta(DifficultyAdjust adjust) => switch (adjust) {
  DifficultyAdjust.up => 1,
  DifficultyAdjust.down => -1,
  DifficultyAdjust.none => 0,
};

///
/// 一条尚未正式写入单词难度的结算草稿。
///
/// 单词完成时先保存这条草稿，用户离开结算页时才真正修改 words 表。
/// 这样既能让结算页展示系统建议，也能在用户手动调整后保留最终选择。
class SettlementDraft {
  ///
  /// 创建结算草稿。
  const SettlementDraft({
    required this.sessionId,
    required this.wordId,
    required this.isCorrect,
    required this.streak,
    required this.difficultyBefore,
    required this.suggestedAdjustment,
    required this.adjustment,
    required this.manual,
    required this.usedTimeSeconds,
    this.recentResults = const <bool?>[],
  });

  /// 所属会话编号。
  final int sessionId;

  /// 所属单词编号。
  final int wordId;

  /// 本轮是否一次都没有答错。
  final bool isCorrect;

  /// 包含本轮在内的连续答对轮数。
  final int streak;

  /// 生成草稿时单词的难度。
  final int difficultyBefore;

  /// 系统建议的难度变化量。
  final int suggestedAdjustment;

  /// 当前最终会应用的难度变化量。
  final int adjustment;

  /// 用户是否在结算页手动改过建议。
  final bool manual;

  /// 本词本轮用时（秒）。
  final int usedTimeSeconds;

  /// 最近几轮结果，**从旧到新**：第 0 位最早，最后一个是最新一轮（也就是本轮）。
  ///
  /// 生活化解释：像一排排队的圆点，最右边那个是刚刚这一轮，
  /// 往左一个比一个早。练过的轮数不足五轮时，列表就有几个给几个，
  /// 界面会在右边补空心圈占位。
  final List<bool?> recentResults;

  /// 当前难度在结算后的值，最低不低于 0。
  int get difficultyAfter {
    final value = difficultyBefore + adjustment;
    return value < 0 ? 0 : value;
  }

  /// 按新的手动选择创建副本。
  SettlementDraft copyWithAdjust(DifficultyAdjust next) => SettlementDraft(
    sessionId: sessionId,
    wordId: wordId,
    isCorrect: isCorrect,
    streak: streak,
    difficultyBefore: difficultyBefore,
    suggestedAdjustment: suggestedAdjustment,
    adjustment: difficultyAdjustDelta(next),
    manual: true,
    usedTimeSeconds: usedTimeSeconds,
    recentResults: recentResults,
  );
}
