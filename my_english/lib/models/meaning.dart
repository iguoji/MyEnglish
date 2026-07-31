import 'model_value_parser.dart';

/// 单词下的一组词性与释义。
class Meaning {
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
  final int? id;

  /// 所属单词主键，对应数据库外键 word_id。
  final int? wordId;

  /// 当前 Meaning 在一个 Word 中的排序值。
  final int index;

  /// 词性字符串。
  final String pos;

  /// 当前词性下的释义列表。
  final List<String> definitions;

  /// 展示用词性：全部小写，空词性返回 '*'。
  ///
  /// 原始 [pos] 保持原样存储（如 "N."、"VT."）；UI 展示时调用此 getter
  /// 得到 "n."、"vt."，保持数据层与展示层解耦。先去掉首尾空格，避免
  /// 旧数据只有空白字符时渲染出一个看不见但仍占位的词性。
  String get displayPos {
    final normalizedPos = pos.trim().toLowerCase();
    return normalizedPos.isEmpty ? '*' : normalizedPos;
  }

  /// 创建、更新和软删除时间。
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// 把 JSON 或 MethodChannel 返回的 Map 转成 Meaning。
  factory Meaning.fromMap(Map<Object?, Object?> map, {int? fallbackWordId}) {
    final rawDefinitions = map['definitions'];
    if (rawDefinitions != null && rawDefinitions is! List) {
      throw const FormatException('Meaning.definitions 必须是数组');
    }

    final definitions = List<String>.unmodifiable(
      (rawDefinitions as List? ?? const <Object?>[]).map((definition) {
        if (definition == null) {
          throw const FormatException('Meaning.definitions 不能包含 null');
        }
        return definition.toString();
      }),
    );

    return Meaning(
      id: readOptionalInt(map['id'], 'Meaning.id'),
      wordId:
          readOptionalInt(map['word_id'], 'Meaning.word_id') ?? fallbackWordId,
      index: readOptionalInt(map['index'], 'Meaning.index') ?? 0,
      pos: map['pos']?.toString() ?? '',
      definitions: definitions,
      createdAt: readOptionalDate(map['created_at'], 'Meaning.created_at'),
      updatedAt: readOptionalDate(map['updated_at'], 'Meaning.updated_at'),
      deletedAt: readOptionalDate(map['deleted_at'], 'Meaning.deleted_at'),
    );
  }

  /// 转成 MethodChannel 可传输 Map，供 SQLite 模式新增和编辑使用。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'word_id': wordId,
      'index': index,
      'pos': pos,
      'definitions': definitions,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  /// 转成导出文件使用的数据。
  ///
  /// 数据库主键、外键和时间字段不属于可迁移的业务内容，因此不会写出。
  Map<String, Object?> toExportMap() {
    return <String, Object?>{
      'index': index,
      'pos': pos,
      'definitions': List<String>.from(definitions),
    };
  }
}
