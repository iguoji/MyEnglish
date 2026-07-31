import 'model_value_parser.dart';

/// 单词下的一组词性与释义。
///
/// @property `int?` id SQLite 自增主键。
/// @property `int?` wordId 所属单词主键。
/// @property `int` index 展示排序值。
/// @property `String` pos 词性文本。
/// @property `List<String>` definitions 中文释义列表。
class Meaning {
  /// 创建一组词性与释义。
  ///
  /// @param `int?` id SQLite 自增主键。
  /// @param `int?` wordId 所属单词主键。
  /// @param `int` index 展示排序值，数值越大越靠前。
  /// @param `String` pos 词性文本。
  /// @param `List<String>` definitions 中文释义列表。
  /// @param `DateTime?` createdAt 创建时间。
  /// @param `DateTime?` updatedAt 更新时间。
  /// @param `DateTime?` deletedAt 软删除时间。
  const Meaning({
    this.id,
    this.wordId,
    required this.index,
    required this.pos,
    required this.definitions,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  /// SQLite 自增主键。
  ///
  /// @var `int?`
  final int? id;

  /// 所属单词主键，对应数据库外键 word_id。
  ///
  /// @var `int?`
  final int? wordId;

  /// 当前 Meaning 在一个 Word 中的排序值。
  ///
  /// @var `int`
  final int index;

  /// 词性字符串。
  ///
  /// @var `String`
  final String pos;

  /// 当前词性下的释义列表。
  ///
  /// @var `List<String>`
  final List<String> definitions;

  /// 展示用词性：全部小写，空词性返回 '*'。
  ///
  /// 原始 [pos] 保持原样存储（如 "N."、"VT."）；UI 展示时调用此 getter
  /// 得到 "n."、"vt."，保持数据层与展示层解耦。先去掉首尾空格，避免
  /// 旧数据只有空白字符时渲染出一个看不见但仍占位的词性。
  ///
  /// @return `String` 清理空格并统一小写后的展示词性。
  String get displayPos {
    // trim + toLowerCase 对应 PHP 的 strtolower(trim($pos))。
    final normalizedPos = pos.trim().toLowerCase();
    // 空词性使用星号占位，避免页面绘制不可见的空白标签。
    return normalizedPos.isEmpty ? '*' : normalizedPos;
  }

  /// 创建时间。
  ///
  /// @var `DateTime?`
  final DateTime? createdAt;

  /// 更新时间。
  ///
  /// @var `DateTime?`
  final DateTime? updatedAt;

  /// 软删除时间。
  ///
  /// @var `DateTime?`
  final DateTime? deletedAt;

  /// 把 JSON 或 MethodChannel 返回的 Map 转成 Meaning。
  ///
  /// @param `Map<Object?, Object?>` map 数据库行或导入文件中的释义对象。
  /// @param `int?` fallbackWordId 嵌套数据缺少外键时使用的单词主键。
  /// @return `Meaning` 完成字段校验且释义列表不可变的模型。
  factory Meaning.fromMap(Map<Object?, Object?> map, {int? fallbackWordId}) {
    // definitions 对应 JSON 数组，缺失时允许按空释义列表处理。
    final rawDefinitions = map['definitions'];
    // 字段存在时必须是数组，逻辑类似 Laravel 的 array 校验规则。
    if (rawDefinitions != null && rawDefinitions is! List) {
      throw const FormatException('Meaning.definitions 必须是数组');
    }

    // 将动态数组映射成字符串列表，并冻结结果避免页面直接修改模型。
    final definitions = List<String>.unmodifiable(
      // 缺失字段等价于 PHP 的 $definitions ?? []。
      (rawDefinitions as List? ?? const <Object?>[]).map((definition) {
        // null 不是有效释义，不能转换成误导用户的 "null" 文本。
        if (definition == null) {
          throw const FormatException('Meaning.definitions 不能包含 null');
        }
        // 原始字符串直接保留，其他 JSON 标量使用明确文本表示。
        return definition.toString();
      }),
    );

    // 公共解析器负责数字和日期类型校验，模型只处理字段业务语义。
    return Meaning(
      // 新建但未落库的释义允许没有自增主键。
      id: readOptionalInt(map['id'], 'Meaning.id'),
      // 嵌套 JSON 没有 word_id 时继承外层 Word 的主键。
      wordId:
          readOptionalInt(map['word_id'], 'Meaning.word_id') ?? fallbackWordId,
      // 缺失排序值时使用 0，仍能稳定排在高索引释义之后。
      index: readOptionalInt(map['index'], 'Meaning.index') ?? 0,
      // 缺失词性时保存空文本，displayPos 会统一显示星号。
      pos: map['pos']?.toString() ?? '',
      // 使用上方已经完成校验的不可变释义列表。
      definitions: definitions,
      // 时间字段兼容 SQLite 毫秒数和导入文件日期文本。
      createdAt: readOptionalDate(map['created_at'], 'Meaning.created_at'),
      updatedAt: readOptionalDate(map['updated_at'], 'Meaning.updated_at'),
      deletedAt: readOptionalDate(map['deleted_at'], 'Meaning.deleted_at'),
    );
  }

  /// 转成 MethodChannel 可传输 Map，供 SQLite 模式新增和编辑使用。
  ///
  /// @return `Map<String, Object?>` 原生 Meaning Store 接受的完整字段集合。
  Map<String, Object?> toMap() {
    // 返回结构类似 Laravel 模型的 toArray()，可直接通过 MethodChannel 传输。
    return <String, Object?>{
      // id 为空时由 SQLite 自动生成。
      'id': id,
      // word_id 维护释义到单词的外键关系。
      'word_id': wordId,
      // index 决定同一单词下多条释义的显示顺序。
      'index': index,
      // pos 保存原始词性，展示时再统一转换小写。
      'pos': pos,
      // MethodChannel 原生支持字符串列表，无需二次 JSON 编码。
      'definitions': definitions,
      // DateTime 统一转成 SQLite 使用的毫秒时间戳。
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  /// 转成导出文件使用的数据。
  ///
  /// 数据库主键、外键和时间字段不属于可迁移的业务内容，因此不会写出。
  ///
  /// @return `Map<String, Object?>` 可写入备份 JSON 的释义业务字段。
  Map<String, Object?> toExportMap() {
    // 导出结构只保留重新导入时真正需要的业务数据。
    return <String, Object?>{
      // 排序值保证导入后释义顺序不变。
      'index': index,
      // 词性保留原始值，由展示层统一小写。
      'pos': pos,
      // 创建新列表，避免导出调用方持有模型内部列表引用。
      'definitions': List<String>.from(definitions),
    };
  }
}
