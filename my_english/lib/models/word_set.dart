///
/// 「今天要背的这一批词」。
///
/// 全部复习模块共用同一份，所以一天通常只有一条——只有当你改了
/// 「每日复习」的数量时才会新建一条，永远取当天最新的那条。
///
/// [tomorrowWordIds] 只服务于「今天的巩固局」：主线过关之后再进模块，
/// 抽的是「今天随机一半 + 明天一半」。第二天会重新按规则选词建库，
/// 不会复用昨天存下来的这份明日列表。
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
  });

  /// 自增主键。
  final int id;

  ///
  /// 创建这份词库时「每日复习」设置的数量。
  ///
  /// 用它和当前设置一比就知道要不要补词或截断，不必先解析整个数组。
  final int wordCount;

  /// 今日单词主键快照，顺序不可变。
  final List<int> todayWordIds;

  /// 明日单词主键快照，只给今天的巩固局用。
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
