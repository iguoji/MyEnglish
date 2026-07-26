// 引入同属全局 models 目录的 Meaning 模型。
import 'meaning.dart';

/// 单词数据模型，可被首页、循环播放页和未来任意业务页面共同使用。
class Word {
  /// 创建 Word；id 和时间在写入数据库前可以为空。
  const Word({
    // SQLite 会为新数据生成自增主键。
    this.id,
    // spelling 是业务必填字段。
    required this.spelling,
    // 一个 Word 可以包含多条 Meaning。
    this.meanings = const <Meaning>[],
    // null 表示没有难度，任何非空非负数都是有效难度。
    this.difficulty,
    // 最近复习时间供未来复习模块使用。
    this.reviewedAt,
    // 创建、更新和软删除时间。
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  /// SQLite 自增主键。
  final int? id;

  /// 英文拼写；允许多个 Word 使用相同 spelling，记录身份由 id 决定。
  final String spelling;

  /// 当前单词的全部 Meaning。
  final List<Meaning> meanings;

  /// 可空难度，最小值为 0 且没有最大值。
  final int? difficulty;

  /// 最近复习时间。
  final DateTime? reviewedAt;

  /// 创建、更新和软删除时间。
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// 列表显示和日期排序共同使用的业务日期：优先更新时间，没有时使用加入时间。
  DateTime? get effectiveDate => updatedAt ?? createdAt;

  /// 把 JSON 或 MethodChannel 返回的 Map 转换成 Word。
  factory Word.fromMap(Map<Object?, Object?> map) {
    // spelling 不允许缺失或只有空格。
    final spelling = map['spelling']?.toString();
    // 拼写字段为空时立即报告具体格式错误。
    if (spelling == null || spelling.trim().isEmpty) {
      throw const FormatException('Word.spelling 不能为空');
    }

    // 先读取 Word id，供嵌套 Meaning 缄失 word_id 时使用。
    final id = _readInt(map['id'], 'Word.id');
    // meanings 缺失时使用空数组，类型错误时不能静默忽略。
    final rawMeanings = map['meanings'];
    // JSON 约定 meanings 必须为数组。
    if (rawMeanings != null && rawMeanings is! List) {
      throw const FormatException('Word.meanings 必须是数组');
    }

    // 逐条把普通 Map 转成 Meaning。
    final parsedMeanings = <Meaning>[];
    // as List? 类似 PHP 中已经通过 is_array 后再 foreach。
    final meaningItems = rawMeanings as List? ?? const <Object?>[];
    // 使用带 index 的循环，错误信息可以指出坏的是第几条 Meaning。
    for (var index = 0; index < meaningItems.length; index += 1) {
      // 读取当前动态项。
      final rawMeaning = meaningItems[index];
      // 每项必须是 JSON 对象或 MethodChannel Map。
      if (rawMeaning is! Map) {
        throw FormatException('Word.meanings 第 ${index + 1} 项必须是对象');
      }
      try {
        // Map.from 把动态 Map 收窄成模型构造器需要的类型。
        final meaningMap = Map<Object?, Object?>.from(rawMeaning);
        // 当前 Word id 作为 Meaning 外键回退值。
        parsedMeanings.add(Meaning.fromMap(meaningMap, fallbackWordId: id));
      } on FormatException catch (error) {
        // 补充 Meaning 在 Word 中的位置后继续向上抛出。
        throw FormatException(
          'Word.meanings 第 ${index + 1} 项错误：${error.message}',
        );
      }
    }

    // README 规定 index 越大越靠前，数据库和 JSON 在模型层统一排序。
    parsedMeanings.sort((first, second) => second.index.compareTo(first.index));

    // 返回完整 Word。
    return Word(
      // 使用已转换的可空 id。
      id: id,
      // spelling 保留原始大小写。
      spelling: spelling,
      // 冻结 Meaning 列表，避免页面直接篡改模型。
      meanings: List<Meaning>.unmodifiable(parsedMeanings),
      // difficulty 类型错误时主动报错。
      difficulty: _readInt(map['difficulty'], 'Word.difficulty'),
      // 日期同时支持 SQLite 毫秒数和 JSON 字符串。
      reviewedAt: _readDate(map['reviewed_at'], 'Word.reviewed_at'),
      createdAt: _readDate(map['created_at'], 'Word.created_at'),
      updatedAt: _readDate(map['updated_at'], 'Word.updated_at'),
      deletedAt: _readDate(map['deleted_at'], 'Word.deleted_at'),
    );
  }

  /// 转成 MethodChannel 可传输 Map，供 SQLite 模式 CRUD 使用。
  Map<String, Object?> toMap() {
    // 返回结构相当于 PHP Controller 交给 Store 的关联数组。
    return <String, Object?>{
      // id 为空时由 SQLite 自增生成。
      'id': id,
      // 保存英文拼写。
      'spelling': spelling,
      // 把 Meaning 逐条转换成 Map。
      'meanings': meanings.map((meaning) => meaning.toMap()).toList(),
      // null 会原样传给 SQLite。
      'difficulty': difficulty,
      // 时间统一传毫秒时间戳。
      'reviewed_at': reviewedAt?.millisecondsSinceEpoch,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }
}

/// 读取可空整数并保留清晰字段错误。
int? _readInt(Object? value, String fieldName) {
  // null 表示字段确实没有值。
  if (value == null) return null;
  // JSON 数字和 MethodChannel Long 都实现 num。
  if (value is num) return value.toInt();
  // 不接受难以发现的隐式字符串转数字。
  throw FormatException('$fieldName 必须是数字，实际值为：$value');
}

/// 日期兼容 SQLite 毫秒数、纯数字文本和 ISO 日期文本。
DateTime? _readDate(Object? value, String fieldName) {
  // null 继续保持为空。
  if (value == null) return null;
  // SQLite 返回整数毫秒数。
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  // JSON 使用字符串日期。
  if (value is String) {
    // 清理首尾空格。
    final normalizedValue = value.trim();
    // 兼容字符串形式的毫秒数。
    final milliseconds = int.tryParse(normalizedValue);
    // 数字文本按时间戳读取。
    if (milliseconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    // 兼容 yyyy-MM-dd 和完整 ISO 8601。
    final parsedDate = DateTime.tryParse(normalizedValue);
    // 合法日期直接返回。
    if (parsedDate != null) return parsedDate;
  }
  // 错误值交给首页实际展示，便于修正 JSON。
  throw FormatException('$fieldName 不是有效日期，实际值为：$value');
}
