import 'meaning.dart';
import 'model_value_parser.dart';

/// 单词及其释义、分组和复习信息。
class Word {
  /// 创建 Word；id 和时间在写入数据库前可以为空。
  const Word({
    this.id,
    required this.spelling,
    this.meanings = const <Meaning>[],
    this.difficulty,
    this.groupIds = const <int>[],
    this.reviewedAt,
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

  /// 所属分组主键；空列表表示未分组，复制操作可使单词属于多个分组。
  final List<int> groupIds;

  /// 最近复习时间。
  final DateTime? reviewedAt;

  /// 创建、更新和软删除时间。
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// 首页更新时间分组使用的日期。
  DateTime? get effectiveDate => updatedAt ?? createdAt;

  /// 未指定分组模式时使用的列表日期。
  ///
  /// 依次回退到最近复习、创建和更新时间；三者均为空时返回 null。
  DateTime? get displayDate => reviewedAt ?? createdAt ?? updatedAt;

  /// 把 JSON 或 MethodChannel 返回的 Map 转换成 Word。
  factory Word.fromMap(Map<Object?, Object?> map) {
    final spelling = map['spelling']?.toString();
    if (spelling == null || spelling.trim().isEmpty) {
      throw const FormatException('Word.spelling 不能为空');
    }

    // 单词 id 作为嵌套释义缺少 word_id 时的外键回退值。
    final id = readOptionalInt(map['id'], 'Word.id');
    final rawMeanings = map['meanings'];
    if (rawMeanings != null && rawMeanings is! List) {
      throw const FormatException('Word.meanings 必须是数组');
    }

    final parsedMeanings = <Meaning>[];
    final meaningItems = rawMeanings as List? ?? const <Object?>[];
    for (var index = 0; index < meaningItems.length; index += 1) {
      final rawMeaning = meaningItems[index];
      if (rawMeaning is! Map) {
        throw FormatException('Word.meanings 第 ${index + 1} 项必须是对象');
      }
      try {
        final meaningMap = Map<Object?, Object?>.from(rawMeaning);
        parsedMeanings.add(Meaning.fromMap(meaningMap, fallbackWordId: id));
      } on FormatException catch (error) {
        throw FormatException(
          'Word.meanings 第 ${index + 1} 项错误：${error.message}',
        );
      }
    }

    // 释义索引越大，展示顺序越靠前。
    parsedMeanings.sort((first, second) => second.index.compareTo(first.index));

    return Word(
      id: id,
      spelling: spelling,
      meanings: List<Meaning>.unmodifiable(parsedMeanings),
      difficulty: readOptionalInt(map['difficulty'], 'Word.difficulty'),
      groupIds: readIntList(map['group_ids'], 'Word.group_ids'),
      reviewedAt: readOptionalDate(map['reviewed_at'], 'Word.reviewed_at'),
      createdAt: readOptionalDate(map['created_at'], 'Word.created_at'),
      updatedAt: readOptionalDate(map['updated_at'], 'Word.updated_at'),
      deletedAt: readOptionalDate(map['deleted_at'], 'Word.deleted_at'),
    );
  }

  /// 转成 MethodChannel 可传输 Map，供 SQLite 模式 CRUD 使用。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'spelling': spelling,
      'meanings': meanings.map((meaning) => meaning.toMap()).toList(),
      'group_ids': groupIds,
      'difficulty': difficulty,
      'reviewed_at': reviewedAt?.millisecondsSinceEpoch,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  /// 转成导出文件使用的数据。
  ///
  /// 日期统一使用 yyyy-MM-dd；分组关系使用导入流程识别的 groups 字段。
  Map<String, Object?> toExportMap() {
    final map = <String, Object?>{
      'id': id,
      'spelling': spelling,
      'meanings': meanings.map((meaning) => meaning.toExportMap()).toList(),
      'difficulty': difficulty,
      'groups': groupIds,
      'created_at': _exportDate(createdAt),
      'updated_at': _exportDate(updatedAt),
    };
    if (reviewedAt != null) map['reviewed_at'] = _exportDate(reviewedAt);
    return map;
  }

  /// 返回移动到指定分组后的新 Word；null 表示移回"未分组"。
  ///
  /// 移动会替换全部分组关系；只有复制操作保留多个分组。
  Word withGroup(int? newGroupId) {
    return Word(
      id: id,
      spelling: spelling,
      meanings: meanings,
      difficulty: difficulty,
      groupIds: newGroupId == null ? const <int>[] : <int>[newGroupId],
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt,
    );
  }

  /// 返回加入指定分组后的新 Word（复制语义）。
  ///
  /// 保留当前分组并追加 [groupId]。
  Word withAddedGroup(int groupId) {
    return Word(
      id: id,
      spelling: spelling,
      meanings: meanings,
      difficulty: difficulty,
      groupIds: <int>[...groupIds, groupId],
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt,
    );
  }

  /// 返回按表单结果编辑后的新 Word，供"修改单词"提交时使用。
  Word edited({
    required String spelling,
    required List<Meaning> meanings,
    required int? groupId,
  }) {
    // 编辑会刷新 updatedAt；创建时间与主键保持不变。
    // 表单只选单个分组，转成单元素列表；null 表示未分组。
    return Word(
      id: id,
      spelling: spelling,
      meanings: meanings,
      difficulty: difficulty,
      groupIds: groupId == null ? const <int>[] : <int>[groupId],
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt,
    );
  }
}

/// 把日期格式化为导出文件使用的 yyyy-MM-dd 文本；null 直接返回 null。
///
/// 不引入 intl 依赖，用 ISO 字符串前 10 位即可得到稳定的年月日，
/// 与 [Word.fromMap] 支持的 yyyy-MM-dd 解析格式完全对称。
String? _exportDate(DateTime? value) {
  // 空日期保持为 null，导出时整字段省略或写为 null。
  if (value == null) return null;
  // toIso8601String 形如 2026-03-18T00:00:00.000，截前 10 位即 yyyy-MM-dd。
  return value.toIso8601String().substring(0, 10);
}
