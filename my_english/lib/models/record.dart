// 引入 dart:convert 仅作占位说明，本模型不依赖 JSON 编解码。
// 这里直接用原生 MethodChannel 返回的 Map 构造，类似 PHP 里把数据库一行
// 转成关联数组后再 new 一个对象。

/// 单词默写记录模型，字段与 README 的 record 表一一对应。
///
/// 设计要点：每个单词"每天只产生一条"记录（首条为准），所以本模型主要
/// 用于「今日复习」展示——把今天写进数据库的那些记录读出来用。
class Record {
  /// 创建一条记录对象，所有字段都来自原生 SQLite 的一行。
  const Record({
    // 自增主键，原生返回 Long，Dart 用 int 接收。
    required this.id,
    // 来源模块，目前固定是 "dictation"（单词默写）。
    required this.module,
    // 所属单词主键，相当于 PHP 里的 word_id 外键。
    required this.wordId,
    // 最终是否全对：选对即 true（默写只能以"全对"结束，错选只会延迟完成）。
    required this.isCorrect,
    // 本次具体错误次数（候选词选错几次）。
    required this.wrongCount,
    // 本次使用提示次数（点了几下提示）。
    required this.hintCount,
    // 变动前难度，方便回看这次默写对难度的影响。
    required this.difficultyBefore,
    // 变动后难度。
    required this.difficultyAfter,
    // 记录写入时间（毫秒时间戳），用于排序与展示。
    required this.createdAt,
    // 本地日期 'YYYY-MM-DD'，相当于 PHP date('Y-m-d')。
    required this.createdDate,
  });

  /// 自增主键。
  final int id;

  /// 来源模块，目前只有单词默写。
  final String module;

  /// 所属单词主键。
  final int wordId;

  /// 最终是否全对。
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

  /// 把原生返回的一行 Map 转成 Record 对象。
  ///
  /// 原生 getTodayReviewWords 已经拼好字段名，这里只是逐个取出并确认类型，
  /// 类似 PHP 里 `new Record($row['id'], $row['word_id'], ...)`。
  factory Record.fromMap(Map<Object?, Object?> map) {
    // id 必填，缺失直接报错便于定位。
    final id = map['id'];
    if (id is! num) throw const FormatException('Record.id 必须是数字');
    // word_id 同理必填。
    final wordId = map['word_id'];
    if (wordId is! num) throw const FormatException('Record.word_id 必须是数字');
    // 读取难度前后值，缺失时用 0 兜底。
    final before = map['difficulty_before'];
    final after = map['difficulty_after'];
    // 读取错误/提示次数，缺失时按 0 处理。
    final wrong = map['wrong_count'];
    final hint = map['hint_count'];
    // 读取时间戳，缺失按 0 兜底。
    final createdAt = map['created_at'];

    // 返回完整 Record 对象。
    return Record(
      id: id.toInt(),
      module: map['module']?.toString() ?? 'dictation',
      wordId: wordId.toInt(),
      // 原生用 0/1 存布尔，这里转回 Dart bool。
      isCorrect:
          map['is_correct'] == true ||
          (map['is_correct'] is num && (map['is_correct'] as num).toInt() == 1),
      wrongCount: wrong is num ? wrong.toInt() : 0,
      hintCount: hint is num ? hint.toInt() : 0,
      difficultyBefore: before is num ? before.toInt() : 0,
      difficultyAfter: after is num ? after.toInt() : 0,
      createdAt: createdAt is num ? createdAt.toInt() : 0,
      // 日期字符串缺失时回退空串，由调用方决定如何处理。
      createdDate: map['created_date']?.toString() ?? '',
    );
  }
}
