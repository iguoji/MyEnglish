// Meaning 是全应用共享的数据模型，不依赖任何具体页面。

/// 一个单词下的一条词性与释义，对应 PHP 项目中的 Meaning 实体类。
class Meaning {
  /// 创建 Meaning；数据库生成的字段允许为空，业务字段必须明确传入。
  const Meaning({
    // 新增但尚未写入数据库时没有自增主键。
    this.id,
    // JSON 把 Meaning 嵌套在 Word 中，所以其中可能暂时没有 word_id。
    this.wordId,
    // index 越大，显示顺序越靠前。
    required this.index,
    // pos 保存词性，例如 n.、vt.、adj.。
    required this.pos,
    // definitions 保存当前词性下的中文释义。
    required this.definitions,
    // 时间字段在 JSON 或新建对象中都可能为空。
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  /// SQLite 自增主键，对应 PHP 模型中的 `$meaning->id`。
  final int? id;

  /// 所属单词主键，对应数据库外键 word_id。
  final int? wordId;

  /// 当前 Meaning 在一个 Word 中的排序值。
  final int index;

  /// 词性字符串。
  final String pos;

  /// 不可变释义列表，类型相当于 PHPDoc 的 `string[]`。
  final List<String> definitions;

  /// 展示用词性：全部大写，空词性返回 '*'。
  ///
  /// 原始 [pos] 保持原样存储（如 "n."、"vt."）；UI 展示时调用此 getter
  /// 得到 "N."、"VT."，保持数据层与展示层解耦。
  String get displayPos => pos.isEmpty ? '*' : pos.toUpperCase();

  /// 创建、更新和软删除时间。
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// 把 JSON 或 MethodChannel 返回的 Map 转成 Meaning。
  factory Meaning.fromMap(Map<Object?, Object?> map, {int? fallbackWordId}) {
    // definitions 缺失时使用空数组，存在但类型错误时主动报告数据问题。
    final rawDefinitions = map['definitions'];
    // JSON 约定 definitions 必须是数组。
    if (rawDefinitions != null && rawDefinitions is! List) {
      // FormatException 会一路显示到首页错误区域，便于定位坏数据。
      throw const FormatException('Meaning.definitions 必须是数组');
    }

    // 把动态数组逐项转换成字符串，并禁止页面意外修改。
    final definitions = List<String>.unmodifiable(
      // `as List?` 对应 PHP 中先确认 is_array 后再 array_map。
      (rawDefinitions as List? ?? const <Object?>[]).map((definition) {
        // null 不是有效释义，避免界面显示字符串 "null"。
        if (definition == null) {
          throw const FormatException('Meaning.definitions 不能包含 null');
        }
        // 普通字符串原样保留；其他 JSON 标量也使用明确文本表示。
        return definition.toString();
      }),
    );

    // 返回完成类型转换的数据对象。
    return Meaning(
      // 可空数字统一转换成 Dart int。
      id: _readInt(map['id'], 'Meaning.id'),
      // JSON 没有 word_id 时使用所属 Word 传入的主键。
      wordId: _readInt(map['word_id'], 'Meaning.word_id') ?? fallbackWordId,
      // 未设置 index 时使用 0，仍然可以稳定排在其他 Meaning 后面。
      index: _readInt(map['index'], 'Meaning.index') ?? 0,
      // 未设置 pos 时显示空词性，不妨碍释义本身展示。
      pos: map['pos']?.toString() ?? '',
      // 保存刚才生成的只读数组。
      definitions: definitions,
      // 日期同时兼容 SQLite 毫秒数和 JSON 的 yyyy-MM-dd 字符串。
      createdAt: _readDate(map['created_at'], 'Meaning.created_at'),
      updatedAt: _readDate(map['updated_at'], 'Meaning.updated_at'),
      deletedAt: _readDate(map['deleted_at'], 'Meaning.deleted_at'),
    );
  }

  /// 转成 MethodChannel 可传输 Map，供 SQLite 模式新增和编辑使用。
  Map<String, Object?> toMap() {
    // Map 对应 PHP 关联数组，也对应小程序提交接口时的普通对象。
    return <String, Object?>{
      // id 为空时由 SQLite 自动生成。
      'id': id,
      // 保存所属 Word 主键。
      'word_id': wordId,
      // 保存排序值。
      'index': index,
      // 保存词性。
      'pos': pos,
      // MethodChannel 原生支持 List<String>，无需再次 JSON 编码。
      'definitions': definitions,
      // SQLite 统一保存毫秒时间戳。
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  /// 转成导出 JSON 用的普通 Map，字段与 words.json 完全一致（index/pos/definitions）。
  ///
  /// 与 [toMap] 的区别：导出只保留业务可见字段，不写入数据库内部的 word_id 与时间戳，
  /// 这样导出的文件既干净又能直接被「导入」流程的 [Meaning.fromMap] 重新解析。
  Map<String, Object?> toExportMap() {
    // 结构等价于 PHP 中 json_encode 一个只含公开字段的关联数组。
    return <String, Object?>{
      // 同一条释义在当前 Word 中的排序值，index 越大越靠前。
      'index': index,
      // 词性，例如 n.、vt.、adj.。
      'pos': pos,
      // 当前词性下的中文释义数组。
      'definitions': List<String>.from(definitions),
    };
  }
}

/// 读取可空整数，并在字段类型错误时输出明确字段名。
int? _readInt(Object? value, String fieldName) {
  // null 表示该字段确实没有值。
  if (value == null) return null;
  // JSON 和 MethodChannel 的整数都属于 num。
  if (value is num) return value.toInt();
  // 其他类型说明数据源格式不符合约定。
  throw FormatException('$fieldName 必须是数字，实际值为：$value');
}

/// 日期兼容 SQLite 毫秒数、纯数字文本和 ISO 日期文本。
DateTime? _readDate(Object? value, String fieldName) {
  // null 继续保持为空。
  if (value == null) return null;
  // 原生 SQLite 返回毫秒数。
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  // JSON 当前使用 yyyy-MM-dd 字符串。
  if (value is String) {
    // 去掉意外的首尾空格。
    final normalizedValue = value.trim();
    // 数字字符串也按毫秒时间戳兼容处理。
    final milliseconds = int.tryParse(normalizedValue);
    // 能转换成整数就直接创建 DateTime。
    if (milliseconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    // DateTime.tryParse 支持 yyyy-MM-dd 和完整 ISO 8601。
    final parsedDate = DateTime.tryParse(normalizedValue);
    // 合法日期直接返回。
    if (parsedDate != null) return parsedDate;
  }
  // 不悄悄吞掉错误，否则首页只会出现错误日期而不知道数据坏在哪里。
  throw FormatException('$fieldName 不是有效日期，实际值为：$value');
}
