import 'model_value_parser.dart';

/// 单词默写记录模型，字段与 README 的 record 表一一对应。
///
/// 每次提交默写结果都会产生一条记录；同一单词在同一天可以有多条记录。
/// 首页统计今日复习数量时按 [wordId] 去重。
class Record {
  const Record({
    required this.id,
    required this.module,
    required this.wordId,
    required this.isCorrect,
    required this.wrongCount,
    required this.hintCount,
    required this.difficultyBefore,
    required this.difficultyAfter,
    required this.createdAt,
    required this.createdDate,
  });

  /// 自增主键。
  final int id;

  /// 来源模块，目前只有单词默写。
  final String module;

  /// 所属单词主键。
  final int wordId;

  /// 本次答题过程中是否没有选错候选项。
  final bool isCorrect;

  /// 本次错误次数。
  final int wrongCount;

  /// 本次提示次数。
  final int hintCount;

  /// 变动前难度。
  final int difficultyBefore;

  /// 变动后难度。
  final int difficultyAfter;

  /// 写入时间（毫秒时间戳）。
  final int createdAt;

  /// 本地日期，格式 'YYYY-MM-DD'。
  final String createdDate;

  /// 从原生记录数据创建模型。
  factory Record.fromMap(Map<Object?, Object?> map) {
    final id = readOptionalInt(map['id'], 'Record.id');
    if (id == null) throw const FormatException('Record.id 不能为空');

    final wordId = readOptionalInt(map['word_id'], 'Record.word_id');
    if (wordId == null) {
      throw const FormatException('Record.word_id 不能为空');
    }

    return Record(
      id: id,
      module: map['module']?.toString() ?? 'dictation',
      wordId: wordId,
      isCorrect:
          map['is_correct'] == true ||
          (map['is_correct'] is num && (map['is_correct'] as num).toInt() == 1),
      wrongCount:
          readOptionalInt(map['wrong_count'], 'Record.wrong_count') ?? 0,
      hintCount: readOptionalInt(map['hint_count'], 'Record.hint_count') ?? 0,
      difficultyBefore:
          readOptionalInt(
            map['difficulty_before'],
            'Record.difficulty_before',
          ) ??
          0,
      difficultyAfter:
          readOptionalInt(map['difficulty_after'], 'Record.difficulty_after') ??
          0,
      createdAt: readOptionalInt(map['created_at'], 'Record.created_at') ?? 0,
      createdDate: map['created_date']?.toString() ?? '',
    );
  }
}
