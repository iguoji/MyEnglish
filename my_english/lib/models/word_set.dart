/// 按日期唯一的计划视图；成员实际保存在计划单词表中。
/// 每次获取按最新每日目标补缺，今日和明日列表来自各自的计划。
class WordSet {
  ///
  /// 创建一份复习词库。
  const WordSet({
    required this.id,
    required this.wordCount,
    required this.todayWordIds,
    required this.tomorrowWordIds,
    required this.date,
    this.createdAt,
    this.updatedAt,
    this.hardWordIds = const <int>[],
  });

  /// 成员的难词身份由计划单词表固定保存，补词后不靠数组位置猜分类。
  final List<int> hardWordIds;

  /// 自增主键。
  final int id;

  ///
  /// 当前计划中的实际单词数量，目标数量始终读取全局设置。
  final int wordCount;

  /// 今日单词主键快照，顺序不可变。
  final List<int> todayWordIds;

  /// 已预建的明日计划成员；第二天继续使用同一份计划。
  final List<int> tomorrowWordIds;

  /// 设备本地日期，格式固定为 yyyy-MM-dd。
  final String date;

  /// 今天第一次建库的时间。
  final DateTime? createdAt;

  /// 最后一次因设置变化调整数量的时间。
  final DateTime? updatedAt;

  ///
  /// 把原生 MethodChannel 返回的数据转换成强类型模型。
  factory WordSet.fromMap(Map<Object?, Object?> map) {
    // 主键缺失时会话无法把自己关联回来源词库，属于协议错误。
    final rawId = map['id'];
    if (rawId is! num) throw const FormatException('复习词库缺少有效 id');

    // 日期是这张表的业务键，空值说明数据损坏。
    final date = map['date']?.toString() ?? '';
    if (date.isEmpty) throw const FormatException('复习词库缺少 date');

    final today = _readIds(map['today_word_ids'], '今日单词列表');
    return WordSet(
      id: rawId.toInt(),
      // 数量以实际数组长度为准，避免冗余列与数组对不上时误判。
      wordCount: today.length,
      todayWordIds: List<int>.unmodifiable(today),
      tomorrowWordIds: List<int>.unmodifiable(
        _readIds(map['tomorrow_word_ids'], '明日单词列表'),
      ),
      date: date,
      createdAt: _readTime(map['created_at']),
      updatedAt: _readTime(map['updated_at']),
      hardWordIds: _readIds(
        map['hard_word_ids'] ?? const <int>[],
        'hard_word_ids',
      ),
    );
  }

  ///
  /// 把原生返回的动态数组收窄成单词主键列表。
  static List<int> _readIds(Object? value, String fieldName) {
    // 缺失字段按空列表处理：明日列表在主线场景下本来就是空的。
    if (value == null) return const <int>[];
    if (value is! List) throw FormatException('复习词库的$fieldName必须是数组');
    return <int>[
      for (final item in value)
        if (item is num)
          item.toInt()
        else
          throw FormatException('复习词库的$fieldName元素必须是数字，实际为：$item'),
    ];
  }

  ///
  /// 把原生毫秒时间戳转成 DateTime；缺失或为 0 时返回 null。
  static DateTime? _readTime(Object? value) {
    if (value is! num || value.toInt() == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
}
