import 'model_value_parser.dart';

///
/// 单词默写记录模型，字段与 README 的 record 表一一对应。
///
/// 每次提交默写结果都会产生一条记录；同一单词在同一天可以有多条记录。
/// 首页统计今日复习数量时按 [wordId] 去重。
///
/// @property int id SQLite 自增主键。
/// @property int wordId 本次默写对应的单词主键。
/// @property bool isCorrect 本次是否零错误完成。
/// @property int wrongCount 本次选错次数。
/// @property int hintCount 本次使用提示次数。
///
class Record {
  ///
  /// 创建一条单词默写记录。
  ///
  /// @param  int  id SQLite 自增主键。
  /// @param  String  module 产生记录的业务模块。
  /// @param  int  wordId 所属单词主键。
  /// @param  bool  isCorrect 本次是否零错误完成。
  /// @param  int  wrongCount 本次选错次数。
  /// @param  int  hintCount 本次使用提示次数。
  /// @param  int  difficultyBefore 提交前难度。
  /// @param  int  difficultyAfter 提交后难度。
  /// @param  int  createdAt 写入时间的毫秒时间戳。
  /// @param  String  createdDate 写入日期的 yyyy-MM-dd 文本。
  ///
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

  ///
  /// 自增主键。
  ///
  /// @var int
  ///
  final int id;

  ///
  /// 来源模块，目前只有单词默写。
  ///
  /// @var String
  ///
  final String module;

  ///
  /// 所属单词主键。
  ///
  /// @var int
  ///
  final int wordId;

  ///
  /// 本次答题过程中是否没有选错候选项。
  ///
  /// @var bool
  ///
  final bool isCorrect;

  ///
  /// 本次错误次数。
  ///
  /// @var int
  ///
  final int wrongCount;

  ///
  /// 本次提示次数。
  ///
  /// @var int
  ///
  final int hintCount;

  ///
  /// 变动前难度。
  ///
  /// @var int
  ///
  final int difficultyBefore;

  ///
  /// 变动后难度。
  ///
  /// @var int
  ///
  final int difficultyAfter;

  ///
  /// 写入时间（毫秒时间戳）。
  ///
  /// @var int
  ///
  final int createdAt;

  ///
  /// 本地日期，格式 'YYYY-MM-DD'。
  ///
  /// @var String
  ///
  final String createdDate;

  ///
  /// 从原生记录数据创建模型。
  ///
  /// @param  `Map<Object?, Object?>`  map Android SQLite 返回的一行记录。
  /// @return Record 完成类型校验和默认值处理后的默写记录。
  ///
  factory Record.fromMap(Map<Object?, Object?> map) {
    // id 对应数据库主键，逻辑类似 Laravel 模型必须存在的 route key。
    final id = readOptionalInt(map['id'], 'Record.id');
    // 主键缺失时无法唯一识别记录，因此拒绝构造不完整模型。
    if (id == null) throw const FormatException('Record.id 不能为空');

    // word_id 是记录到单词的必填外键。
    final wordId = readOptionalInt(map['word_id'], 'Record.word_id');
    // 外键缺失时无法回查单词详情，必须暴露数据格式错误。
    if (wordId == null) {
      throw const FormatException('Record.word_id 不能为空');
    }

    // 其余数值字段使用公共解析器统一收窄，缺失的统计值按 0 处理。
    return Record(
      // 使用上方已确认非空的自增主键。
      id: id,
      // 当前只有 dictation；旧数据缺失模块时使用该业务默认值。
      module: map['module']?.toString() ?? 'dictation',
      // 使用上方已确认非空的单词外键。
      wordId: wordId,
      // 原生 SQLite 使用 0/1，测试或未来实现也允许直接返回 bool。
      isCorrect:
          map['is_correct'] == true ||
          (map['is_correct'] is num && (map['is_correct'] as num).toInt() == 1),
      // 可选统计字段缺失时按没有错误处理。
      wrongCount:
          readOptionalInt(map['wrong_count'], 'Record.wrong_count') ?? 0,
      // 可选统计字段缺失时按没有使用提示处理。
      hintCount: readOptionalInt(map['hint_count'], 'Record.hint_count') ?? 0,
      // 历史数据缺少难度快照时使用 0 保持页面可展示。
      difficultyBefore:
          readOptionalInt(
            map['difficulty_before'],
            'Record.difficulty_before',
          ) ??
          0,
      // 保存事务完成后的难度，供后续复盘难度变化。
      difficultyAfter:
          readOptionalInt(map['difficulty_after'], 'Record.difficulty_after') ??
          0,
      // 原生记录时间缺失时使用 0，调用方可明确识别无效时间。
      createdAt: readOptionalInt(map['created_at'], 'Record.created_at') ?? 0,
      // 日期文本用于按本地自然日查询，缺失时保持空字符串。
      createdDate: map['created_date']?.toString() ?? '',
    );
  }
}
