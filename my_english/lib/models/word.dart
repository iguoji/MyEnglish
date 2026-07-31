import 'meaning.dart';
import 'model_value_parser.dart';

/// 单词及其释义、分组和复习信息。
///
/// @property `int?` id SQLite 自增主键。
/// @property `String` spelling 英文拼写。
/// @property `List<Meaning>` meanings 词性与释义列表。
/// @property `int?` difficulty 当前学习难度。
/// @property `List<int>` groupIds 所属分组主键。
class Word {
  /// 创建 Word；id 和时间在写入数据库前可以为空。
  ///
  /// @param `int?` id SQLite 自增主键。
  /// @param `String` spelling 英文拼写。
  /// @param `List<Meaning>` meanings 词性与释义列表。
  /// @param `int?` difficulty 当前学习难度。
  /// @param `List<int>` groupIds 所属分组主键。
  /// @param `DateTime?` reviewedAt 最近复习时间。
  /// @param `DateTime?` createdAt 创建时间。
  /// @param `DateTime?` updatedAt 更新时间。
  /// @param `DateTime?` deletedAt 软删除时间。
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
  ///
  /// @var `int?`
  final int? id;

  /// 英文拼写；允许多个 Word 使用相同 spelling，记录身份由 id 决定。
  ///
  /// @var `String`
  final String spelling;

  /// 当前单词的全部 Meaning。
  ///
  /// @var `List<Meaning>`
  final List<Meaning> meanings;

  /// 可空难度，最小值为 0 且没有最大值。
  ///
  /// @var `int?`
  final int? difficulty;

  /// 所属分组主键；空列表表示未分组，复制操作可使单词属于多个分组。
  ///
  /// @var `List<int>`
  final List<int> groupIds;

  /// 最近复习时间。
  ///
  /// @var `DateTime?`
  final DateTime? reviewedAt;

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

  /// 首页更新时间分组使用的日期。
  ///
  /// @return `DateTime?` 更新时间；缺失时回退创建时间。
  DateTime? get effectiveDate => updatedAt ?? createdAt;

  /// 未指定分组模式时使用的列表日期。
  ///
  /// 依次回退到最近复习、创建和更新时间；三者均为空时返回 null。
  ///
  /// @return `DateTime?` 当前最适合展示的业务日期。
  DateTime? get displayDate => reviewedAt ?? createdAt ?? updatedAt;

  /// 把 JSON 或 MethodChannel 返回的 Map 转换成 Word。
  ///
  /// @param `Map<Object?, Object?>` map 数据库行或导入文件中的单词对象。
  /// @return `Word` 完成字段校验、释义排序和列表冻结后的单词模型。
  factory Word.fromMap(Map<Object?, Object?> map) {
    // 先读取必填拼写，逻辑类似 Laravel FormRequest 的 required 校验。
    final spelling = map['spelling']?.toString();
    // null、空字符串和纯空格都不能构成可学习的单词。
    if (spelling == null || spelling.trim().isEmpty) {
      throw const FormatException('Word.spelling 不能为空');
    }

    // 单词 id 作为嵌套释义缺少 word_id 时的外键回退值。
    final id = readOptionalInt(map['id'], 'Word.id');
    // meanings 对应一对多关联，缺失时允许使用空列表。
    final rawMeanings = map['meanings'];
    // 存在 meanings 字段时必须是数组，避免后续 foreach 处理错误结构。
    if (rawMeanings != null && rawMeanings is! List) {
      throw const FormatException('Word.meanings 必须是数组');
    }

    // 创建可变数组，按顺序接收已经完成类型转换的 Meaning 模型。
    final parsedMeanings = <Meaning>[];
    // 缺失 meanings 时使用 const 空数组，效果类似 PHP 的 $items ?? []。
    final meaningItems = rawMeanings as List? ?? const <Object?>[];
    // 使用带下标的循环，让异常可以指出导入文件中的具体释义位置。
    for (var index = 0; index < meaningItems.length; index += 1) {
      // 读取当前动态元素，尚未假设它一定是 Map。
      final rawMeaning = meaningItems[index];
      // 每条释义必须是键值对象，普通文本不能构造 Meaning。
      if (rawMeaning is! Map) {
        throw FormatException('Word.meanings 第 ${index + 1} 项必须是对象');
      }
      // 为嵌套模型补充上下文，同时保留它自己的详细格式异常。
      try {
        // Map.from 将动态 Map 收窄成 Meaning.fromMap 接受的键值类型。
        final meaningMap = Map<Object?, Object?>.from(rawMeaning);
        // 嵌套数据缺失 word_id 时使用当前单词 id 作为外键。
        parsedMeanings.add(Meaning.fromMap(meaningMap, fallbackWordId: id));
      } on FormatException catch (error) {
        // 在原始异常前补充数组位置，方便定位具体坏数据。
        throw FormatException(
          'Word.meanings 第 ${index + 1} 项错误：${error.message}',
        );
      }
    }

    // 释义索引越大，展示顺序越靠前。
    parsedMeanings.sort((first, second) => second.index.compareTo(first.index));

    // 统一调用公共解析器组装完整模型，字段错误不会被静默吞掉。
    return Word(
      // 主键可以为空，新建单词会由 SQLite 自动生成。
      id: id,
      // 拼写保留数据源原始大小写，展示层再决定格式。
      spelling: spelling,
      // 冻结释义数组，防止页面直接改坏模型内部数据。
      meanings: List<Meaning>.unmodifiable(parsedMeanings),
      // 难度为空表示尚未设置，数字则完整保留。
      difficulty: readOptionalInt(map['difficulty'], 'Word.difficulty'),
      // 空分组数组表示未分组，多项表示复制到多个分组。
      groupIds: readIntList(map['group_ids'], 'Word.group_ids'),
      // 时间字段兼容原生毫秒时间戳和导入文件的日期文本。
      reviewedAt: readOptionalDate(map['reviewed_at'], 'Word.reviewed_at'),
      createdAt: readOptionalDate(map['created_at'], 'Word.created_at'),
      updatedAt: readOptionalDate(map['updated_at'], 'Word.updated_at'),
      deletedAt: readOptionalDate(map['deleted_at'], 'Word.deleted_at'),
    );
  }

  /// 转成 MethodChannel 可传输 Map，供 SQLite 模式 CRUD 使用。
  ///
  /// @return `Map<String, Object?>` 原生 Word Store 接受的字段集合。
  Map<String, Object?> toMap() {
    // 返回 Map 类似 Laravel 模型的 toArray()，MethodChannel 可直接传输。
    return <String, Object?>{
      // id 为空时交给 SQLite 自增生成。
      'id': id,
      // 保存单词原始拼写。
      'spelling': spelling,
      // 一对多释义逐条转换成原生可识别的 Map。
      'meanings': meanings.map((meaning) => meaning.toMap()).toList(),
      // 分组关系列表与单词主体在原生事务中一起保存。
      'group_ids': groupIds,
      // null 难度原样交给数据库处理。
      'difficulty': difficulty,
      // DateTime 统一转换成 SQLite 使用的毫秒时间戳。
      'reviewed_at': reviewedAt?.millisecondsSinceEpoch,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  /// 转成导出文件使用的数据。
  ///
  /// 日期统一使用 yyyy-MM-dd；分组关系使用导入流程识别的 groups 字段。
  ///
  /// @return `Map<String, Object?>` 可写入备份 JSON 的业务字段集合。
  Map<String, Object?> toExportMap() {
    // 导出结构只使用 JSON 支持的字符串、数字、数组和对象。
    final map = <String, Object?>{
      // 主键用于备份时识别原记录。
      'id': id,
      // 拼写作为单词核心业务字段直接写出。
      'spelling': spelling,
      // 释义使用精简的导出结构，不携带数据库外键。
      'meanings': meanings.map((meaning) => meaning.toExportMap()).toList(),
      // 难度为空时 JSON 会保留 null，导入后语义不变。
      'difficulty': difficulty,
      // 导入流程通过 groups 字段重建多对多关系。
      'groups': groupIds,
      // 日期格式固定为 yyyy-MM-dd，方便人工阅读和编辑。
      'created_at': _exportDate(createdAt),
      'updated_at': _exportDate(updatedAt),
    };
    // 最近复习时间是可选字段，只有真实存在时才写入备份。
    if (reviewedAt != null) map['reviewed_at'] = _exportDate(reviewedAt);
    // 返回完整导出对象，交由上层统一执行 jsonEncode。
    return map;
  }

  /// 返回移动到指定分组后的新 Word；null 表示移回"未分组"。
  ///
  /// 移动会替换全部分组关系；只有复制操作保留多个分组。
  ///
  /// @param `int?` newGroupId 目标分组主键；null 表示未分组。
  /// @return `Word` 更新分组和更新时间后的新模型。
  Word withGroup(int? newGroupId) {
    // 模型保持不可变，移动操作通过创建副本表达状态变化。
    return Word(
      id: id,
      spelling: spelling,
      meanings: meanings,
      difficulty: difficulty,
      // 移动是单归属语义，目标为空时清空全部分组。
      groupIds: newGroupId == null ? const <int>[] : <int>[newGroupId],
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      // 分组关系变化属于一次业务更新，需要刷新 updatedAt。
      updatedAt: DateTime.now(),
      deletedAt: deletedAt,
    );
  }

  /// 返回加入指定分组后的新 Word（复制语义）。
  ///
  /// 保留当前分组并追加 [groupId]。
  ///
  /// @param `int` groupId 需要追加的目标分组主键。
  /// @return `Word` 同时属于原分组和目标分组的新模型。
  Word withAddedGroup(int groupId) {
    // 扩展运算符对应 PHP 的数组展开，保留旧分组后追加目标分组。
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
  ///
  /// @param `String` spelling 表单提交的新拼写。
  /// @param `List<Meaning>` meanings 表单提交的新释义列表。
  /// @param `int?` groupId 表单选择的单一分组；null 表示未分组。
  /// @return `Word` 保留主键和创建时间、刷新业务字段后的新模型。
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
///
/// @param `DateTime?` value 待导出的可空日期。
/// @return `String?` yyyy-MM-dd 文本；输入为空时返回 null。
String? _exportDate(DateTime? value) {
  // 空日期保持为 null，导出时整字段省略或写为 null。
  if (value == null) return null;
  // toIso8601String 形如 2026-03-18T00:00:00.000，截前 10 位即 yyyy-MM-dd。
  return value.toIso8601String().substring(0, 10);
}
