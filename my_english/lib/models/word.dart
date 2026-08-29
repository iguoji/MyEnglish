import 'meaning.dart';
import 'model_value_parser.dart';

///
/// 一个单词，以及它的全部中文释义。
///
/// 音标、词形（复数/时态等）和分组在 2.0 结构里已经去掉——它们从来没被界面
/// 用到过，留着只会让每张表和每次解析都背一份没人读的字段。
///
class Word {
  ///
  /// 创建一个单词；id 与时间在写入数据库前可以为空。
  ///
  /// 传进来的是数据库那样的**一维释义列表**，构造时立刻整理成按词性分组的
  /// [meanings]：归组、组内去重、`vi.`∩`vt.` 合并、光杆 `v.` 去冗余。
  /// 所以外部拿到的 Word 永远是整理好的，谁都不用再自己分一遍组。
  Word({
    this.id,
    required this.spelling,
    List<Meaning> meanings = const <Meaning>[],
    this.difficulty = 0,
    this.confusions = const <String>[],
    this.syllables = const <String>[],
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
  }) : meanings = buildMeaningGroups(meanings);

  ///
  /// SQLite 自增主键。
  final int? id;

  ///
  /// 英文拼写；允许多个单词使用相同拼写，记录身份由 id 决定。
  final String spelling;

  ///
  /// 按展示词性分组的全部释义，键是 `n.` / `vt.` / `vi. vt.` / `*` 这样的词性。
  ///
  /// 举个例子，`hello` 拿到手是这样：
  /// ```
  /// {
  ///   '*'  : [未整理的含义],
  ///   'n.' : [你好, 你好1],
  ///   'v.' : [你好3, 你好4],
  ///   'vt.': [你好5, 你好6],
  ///   'vi. vt.': [既及物又不及物的那些],
  /// }
  /// ```
  /// 词性的先后是「在数据库里首次出现的顺序」，组内顺序是排序值从大到小。
  /// 整理规则见 [buildMeaningGroups]。
  final Map<String, List<Meaning>> meanings;

  ///
  /// 难度，最小 0 且没有上限；答错 +1，连对满 5 的倍数 -1。
  final int difficulty;

  ///
  /// 外形、发音、字数相近的混淆单词。
  ///
  /// 按「用到才生成」的策略：某个模块第一次遇到这个词时算一批存进来，
  /// 之后所有模块直接复用；用户长按某个混淆词可以重算并覆盖。
  final List<String> confusions;

  ///
  /// 按音节拆分后的数组，如 `[tra, di, tion]`；拼写巩固用它出题。
  final List<String> syllables;

  ///
  /// 最近复习时间；`null` 代表从来没复习过，选词时排在最前面。
  final DateTime? reviewedAt;

  ///
  /// 创建时间。
  final DateTime? createdAt;

  ///
  /// 更新时间。
  final DateTime? updatedAt;

  ///
  /// 取某个词性下的全部释义；没有这个词性时返回空列表。
  ///
  /// `pos` 用展示形式（`vt.` / `vi. vt.` / `*`），不是数据库里的主/子词性。
  List<Meaning> getPosMeanings(String pos) =>
      meanings[pos] ?? const <Meaning>[];

  ///
  /// 摊平成一维的全部释义，顺序 = 词性分组顺序 + 组内顺序。
  ///
  /// 出题、统计、找混淆项这类「不关心词性、只要全部含义」的地方用它。
  List<Meaning> get allMeanings => <Meaning>[
    for (final group in meanings.values) ...group,
  ];

  ///
  /// 按词性分好的展示分组，界面照着一组画一行。
  List<MeaningGroup> get meaningGroups => <MeaningGroup>[
    for (final entry in meanings.entries)
      MeaningGroup(pos: entry.key, meanings: entry.value),
  ];

  ///
  /// 词库列表按日期分段时使用的时间。
  ///
  /// 依次回退到最近复习、创建和更新时间；三者均为空时返回 null。
  DateTime? get displayDate => reviewedAt ?? createdAt ?? updatedAt;

  ///
  /// 排序用的「含义数」：这个单词一共有几条中文释义。
  ///
  /// 生活化解释：含义少的单词更好记，所以复习时先安排它们。
  /// 新结构里一行就是一条释义，所以直接就是列表长度。
  int get meaningCount => allMeanings.length;

  ///
  /// 排序用的「释义总字符数」：全部中文释义去掉首尾空白后的字符数量之和。
  ///
  /// [meaningCount] 只能区分释义有几条；当两个单词都只有一条释义时，
  /// 本字段继续区分「能力」和「进行某项工作的能力」这类复杂度差异。
  int get meaningCharacterCount =>
      allMeanings.fold(0, (sum, meaning) => sum + meaning.characterCount);

  ///
  /// 按统一业务规则比较两个单词的含义复杂度。
  ///
  /// 所有让「含义」参与单词排序的地方都必须调用本方法：第一层先比较释义条数，
  /// 只有条数相同时才比较释义正文的字符总数。这里不处理升降序，
  /// 调用方只需在最终结果上应用自己的方向，便不会让两层方向分裂。
  int compareMeaningComplexityTo(Word other) {
    // 第一层固定比较释义数量，这是所有含义排序不可跳过的首要条件。
    final byCount = meaningCount.compareTo(other.meaningCount);
    if (byCount != 0) return byCount;
    // 数量完全相同后，才用释义正文字符总数继续区分复杂度。
    return meaningCharacterCount.compareTo(other.meaningCharacterCount);
  }

  ///
  /// 把原生 MethodChannel 返回的一行数据转换成 Word。
  factory Word.fromMap(Map<Object?, Object?> map) {
    // 先读取必填拼写，逻辑类似 Laravel FormRequest 的 required 校验。
    final spelling = map['spelling']?.toString();
    // null、空字符串和纯空格都不能构成一个可学习的单词。
    if (spelling == null || spelling.trim().isEmpty) {
      throw const FormatException('Word.spelling 不能为空');
    }

    // 单词 id 作为嵌套释义缺少 word_id 时的外键回退值。
    final id = readOptionalInt(map['id'], 'Word.id');
    final rawMeanings = map['meanings'];
    // 存在 meanings 字段时必须是数组，避免后续遍历处理错误结构。
    if (rawMeanings != null && rawMeanings is! List) {
      throw const FormatException('Word.meanings 必须是数组');
    }

    final parsedMeanings = <Meaning>[];
    final meaningItems = rawMeanings as List? ?? const <Object?>[];
    // 带下标循环，让异常能指出具体是第几条释义出了问题。
    for (var index = 0; index < meaningItems.length; index += 1) {
      final rawMeaning = meaningItems[index];
      if (rawMeaning is! Map) {
        throw FormatException('Word.meanings 第 ${index + 1} 项必须是对象');
      }
      try {
        parsedMeanings.add(
          Meaning.fromMap(
            Map<Object?, Object?>.from(rawMeaning),
            fallbackWordId: id,
          ),
        );
      } on FormatException catch (error) {
        // 在原始异常前补充数组位置，方便定位具体坏数据。
        throw FormatException('Word.meanings 第 ${index + 1} 项错误：${error.message}');
      }
    }
    // 排序值越大越靠前；原生已经按这个顺序返回，这里再兜底一次，
    // 保证从任何来源（含测试构造）拿到的模型都是同一个顺序。
    parsedMeanings.sort((first, second) {
      final bySort = second.sort.compareTo(first.sort);
      if (bySort != 0) return bySort;
      return (first.id ?? 0).compareTo(second.id ?? 0);
    });

    return Word(
      id: id,
      // 拼写保留数据源原始大小写，展示层再决定格式。
      spelling: spelling,
      // 冻结释义数组，防止页面直接改坏模型内部数据。
      meanings: List<Meaning>.unmodifiable(parsedMeanings),
      difficulty: readOptionalInt(map['difficulty'], 'Word.difficulty') ?? 0,
      confusions: readStringList(map['confusions'], 'Word.confusions'),
      syllables: readStringList(map['syllables'], 'Word.syllables'),
      // 复习时间可空：null 代表这个词还没复习过。
      reviewedAt: readOptionalDate(map['reviewed_at'], 'Word.reviewed_at'),
      createdAt: readOptionalDate(map['created_at'], 'Word.created_at'),
      updatedAt: readOptionalDate(map['updated_at'], 'Word.updated_at'),
    );
  }

  ///
  /// 转成 MethodChannel 可传输的 Map，供新增和编辑使用。
  ///
  /// 释义在这里**摊平回一维**：数据库就是一行一条，
  /// 分组只是模型层给界面看的样子。
  Map<String, Object?> toMap() => <String, Object?>{
    // id 为空时交给 SQLite 自增生成。
    'id': id,
    'spelling': spelling,
    // 释义按当前顺序传出，排序值由原生自动发放。
    'meanings': allMeanings.map((meaning) => meaning.toMap()).toList(),
    'difficulty': difficulty,
    'confusions': List<String>.from(confusions),
    'syllables': List<String>.from(syllables),
    // DateTime 统一转换成 SQLite 使用的毫秒时间戳。
    'reviewed_at': reviewedAt?.millisecondsSinceEpoch,
    'created_at': createdAt?.millisecondsSinceEpoch,
  };

  ///
  /// 返回替换了混淆单词的副本；模型不可变，改动一律通过复制表达。
  Word withConfusions(List<String> next) => copyWith(confusions: next);

  ///
  /// 返回替换了音节拆分的副本。
  Word withSyllables(List<String> next) => copyWith(syllables: next);

  ///
  /// 返回按表单结果编辑后的副本，供「修改单词」提交时使用。
  Word edited({required String spelling, required List<Meaning> meanings}) =>
      copyWith(spelling: spelling, meanings: meanings, updatedAt: DateTime.now());

  ///
  /// 转成纯数据结构（嵌套 Map / List），给导出和排查问题用。
  ///
  /// 与 [toMap] 的区别：这里保留**按词性分组**的样子，一眼能看清
  /// 这个词有哪几种词性、每种下面有哪些含义；[toMap] 则是摊平的数据库形态。
  Map<String, Object?> toArray() => <String, Object?>{
    'id': id,
    'spelling': spelling,
    'difficulty': difficulty,
    'confusions': List<String>.from(confusions),
    'syllables': List<String>.from(syllables),
    'reviewed_at': reviewedAt?.millisecondsSinceEpoch,
    'meanings': <String, Object?>{
      for (final entry in meanings.entries)
        entry.key: <Map<String, Object?>>[
          for (final meaning in entry.value)
            <String, Object?>{
              'id': meaning.id,
              'mean': meaning.definition,
              'confusions': List<String>.from(meaning.confusions),
            },
        ],
    },
  };

  ///
  /// 复制并替换部分字段；没传的字段保持原值。
  Word copyWith({
    String? spelling,
    List<Meaning>? meanings,
    int? difficulty,
    List<String>? confusions,
    List<String>? syllables,
    DateTime? reviewedAt,
    DateTime? updatedAt,
  }) => Word(
    id: id,
    spelling: spelling ?? this.spelling,
    meanings: meanings ?? allMeanings,
    difficulty: difficulty ?? this.difficulty,
    confusions: confusions ?? this.confusions,
    syllables: syllables ?? this.syllables,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
