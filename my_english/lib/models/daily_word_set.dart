///
/// 「今天要背的这一批词」。
///
/// 四个复习模块共用同一份，所以一天只有一条。[wordIds] 的顺序就是四个模块
/// 当天共同使用的答题顺序；[wordCount] 冗余保存列表长度，让首页判断
/// 「数量还等不等于设置里的每日复习」时不必先解析整个数组。
///
/// @property int id SQLite 自增主键，会话表用它做来源外键。
/// @property String setDate 设备本地日期，格式固定为 yyyy-MM-dd。
/// @property int wordCount 单词数量，恒等于 [wordIds] 的长度。
/// @property `List<int>` wordIds 固定顺序的单词主键。
///
class DailyWordSet {
  ///
  /// 创建一份每日词库。
  ///
  /// @param  int  id SQLite 自增主键。
  /// @param  String  setDate 设备本地日期，yyyy-MM-dd。
  /// @param  int  wordCount 单词数量。
  /// @param  `List<int>`  wordIds 固定顺序的单词主键。
  /// @param  DateTime?  createdAt 今天第一次建库的时间。
  /// @param  DateTime?  updatedAt 最后一次调整数量的时间。
  ///
  const DailyWordSet({
    required this.id,
    required this.setDate,
    required this.wordCount,
    required this.wordIds,
    this.createdAt,
    this.updatedAt,
  });

  /// SQLite 自增主键。
  final int id;

  /// 设备本地日期，格式固定为 yyyy-MM-dd。
  final String setDate;

  /// 单词数量，恒等于 [wordIds] 的长度。
  final int wordCount;

  /// 当天共用的单词主键快照，顺序不可变。
  final List<int> wordIds;

  /// 今天第一次建库的时间。
  final DateTime? createdAt;

  /// 最后一次因设置变化调整数量的时间。
  final DateTime? updatedAt;

  ///
  /// 把原生 MethodChannel 返回的数据转换成强类型模型。
  ///
  /// @param  `Map<Object?, Object?>`  map 原生词库数据。
  /// @return DailyWordSet 完成校验的每日词库。
  ///
  factory DailyWordSet.fromMap(Map<Object?, Object?> map) {
    // 主键缺失时会话无法把自己关联回来源词库，属于协议错误。
    final rawId = map['id'];
    if (rawId is! num) throw const FormatException('每日词库缺少有效 id');

    // 日期是这张表的业务唯一键，空值说明数据损坏。
    final setDate = map['set_date']?.toString() ?? '';
    if (setDate.isEmpty) throw const FormatException('每日词库缺少 set_date');

    // 单词主键由原生直接以数字列表传回，逐项收窄成 Dart int。
    final rawIds = map['word_ids'];
    if (rawIds is! List) throw const FormatException('每日词库 word_ids 必须是数组');
    final ids = <int>[
      for (final value in rawIds)
        if (value is num)
          value.toInt()
        else
          throw const FormatException('每日词库单词 id 必须是数字'),
    ];

    return DailyWordSet(
      id: rawId.toInt(),
      setDate: setDate,
      // 数量以实际数组长度为准，避免冗余列与数组对不上时误判。
      wordCount: ids.length,
      wordIds: List<int>.unmodifiable(ids),
      createdAt: _readTime(map['created_at']),
      updatedAt: _readTime(map['updated_at']),
    );
  }

  ///
  /// 把原生毫秒时间戳转成 DateTime；缺失或为 0 时返回 null。
  ///
  /// @param  Object?  value 原生返回的时间戳。
  /// @return DateTime? 可用于诊断展示的本地时间。
  ///
  static DateTime? _readTime(Object? value) {
    if (value is! num || value.toInt() == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
}
