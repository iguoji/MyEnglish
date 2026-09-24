// dart:math 提供 Random 与 min：随机挑候选，以及在四个格子里找「答案放得最少」的那几格。
import 'dart:math';

import '../../../models/session_question.dart';
import '../../../models/word.dart';
import 'distractor_reserve.dart';

///
/// 一道选择题在挑混淆项时需要知道的全部信息。
///
/// 开局编卷时手上是试卷里的一行数据，旧局补题时手上是小题对象；两边都先换算成
/// 它，挑选规则只写一份。
class DistractorQuestion {
  const DistractorQuestion({
    required this.type,
    required this.contentType,
    required this.answerType,
    required this.content,
    required this.answers,
    required this.details,
  });

  /// 从开局编好的试卷行读取，字段名与原生建表时一致。
  factory DistractorQuestion.fromPaper(Map<String, Object?> raw) =>
      DistractorQuestion(
        type: raw['question_type'] as int? ?? 0,
        contentType: raw['content_type'] as int? ?? 1,
        answerType: raw['answer_type'] as int? ?? 0,
        content: <String>[
          for (final text in raw['content'] as List? ?? const <Object?>[])
            text.toString(),
        ].firstOrNull ?? '',
        answers: <String>[
          for (final text in raw['answers'] as List? ?? const <Object?>[])
            text.toString(),
        ],
        details: <({int wordId, int? meaningId})>[
          for (final detail in raw['details'] as List? ?? const <Object?>[])
            _detailOf(detail as Map),
        ],
      );

  /// 试卷行里的一条考察对象。
  static ({int wordId, int? meaningId}) _detailOf(Map raw) =>
      (wordId: raw['word_id'] as int, meaningId: raw['meaning_id'] as int?);

  /// 从已经存进会话的小题读取（旧局里还没生成混淆项的题）。
  factory DistractorQuestion.fromSubQuestion(SessionSubQuestion question) =>
      DistractorQuestion(
        type: question.type,
        contentType: question.contentType,
        answerType: question.answerType,
        content: question.content.firstOrNull ?? '',
        answers: question.answers,
        details: <({int wordId, int? meaningId})>[
          for (final detail in question.details)
            (wordId: detail.wordId, meaningId: detail.meaningId),
        ],
      );

  /// 题型：100 单选、200 双选；其余题型没有候选。
  final int type;

  /// 题目内容类型：1 是单词（听音题），2 是中文释义。
  final int contentType;

  /// 答案类型：1 选英文单词，2 选中文释义。
  final int answerType;

  /// 题目内容：看义选词就是屏幕上那句中文。
  final String content;

  /// 正确答案（双选题有两个）。
  final List<String> answers;

  /// 这道题考的是哪些单词、哪些含义。
  final List<({int wordId, int? meaningId})> details;

  /// 是不是需要四个候选的选择题。
  bool get isChoice => type == 100 || type == 200;

  /// 候选是英文单词还是中文释义。
  bool get english => answerType == 1;
}

/// 一道题挑好的结果：存进题目的干扰项，以及四个候选在屏幕上的排列顺序。
typedef PlannedOptions = ({List<String> distractors, List<String> options});

///
/// 一局练习的混淆项规划：每局从全局词库重新挑，整局统一记账。
///
/// 规则分三层，每一层都不放过上一层：
///
/// 一、必须满足（任何情况下都不放宽）
///   - 混淆项绝不是、也不能长得像当前单词的任何一个含义（中文候选）；
///   - 看义选词里，混淆单词的任何一个中文意思都不能和题目那句中文长得像，
///     否则会出现「两个选项都对」；
///   - 与正确答案、以及同一道题里的其它混淆项都要「长得不一样」，
///     避免眼疾手快时看错、点错（规则见 [_englishAlike] / [_chineseAlike]）；
///   - 听音选单词题避开同音词（right / write），否则听起来两个都对；
///   - 只用真实存在的单词和释义，不现场拼造假词；英文候选必须是正常的拼写形态。
///
/// 二、尽量满足
///   - 本局还没用过的优先，整局尽量不重复；
///   - 长短接近（别让正确答案因为特别短或特别长被一眼认出来）；
///   - 词性相同的优先。
///
/// 三、兜底顺序
///   词库里本局没用过的 → 词库里本局用过的（挑用得最少、上次出现离现在最远的）
///   → 内置备用词表（见 [kReserveWords]）。
///
/// 正确答案放在哪一格用「洗牌发牌」：每次都在「答案放得最少」的格子里随机挑。
/// 整局四个位置的次数最多差 1；全是单选题时，每四道题 A、B、C、D 正好各一次，
/// 同一个位置最多连着出现两次。
class DistractorPlanner {
  DistractorPlanner({
    required List<Word> sessionWords,
    required List<Word> corpus,
    required Random random,
  }) : _random = random {
    // 查考察对象时，以开局那一刻的会话快照为准，再退到全局词库。
    for (final word in <Word>[...sessionWords, ...corpus]) {
      final id = word.id;
      if (id != null) _words.putIfAbsent(id, () => word);
    }
    // 词库在前、备用词表在后：同一个拼写、同一句中文只收第一次出现的那条。
    for (final word in <Word>[...corpus, ...sessionWords]) {
      _addLibraryWord(word);
    }
    for (final entry in kReserveWords) {
      _addReserveWord(entry);
    }
    // 每局打乱一次候选的先后：同样满足条件的候选里随机挑，每局都不一样。
    _english = _englishByKey.values.toList()..shuffle(random);
    _chinese = _chineseByKey.values.toList()..shuffle(random);
    for (var index = 0; index < _english.length; index++) {
      _english[index].order = index;
    }
    for (var index = 0; index < _chinese.length; index++) {
      _chinese[index].order = index;
    }
  }

  /// 开局编卷：给整张试卷的全部选择题一次定好混淆项和四个候选的顺序。
  ///
  /// 返回新的试卷；选择题多出 `distractors`（干扰项）与 `options`（排列顺序）
  /// 两个字段，其余题型原样保留。
  static List<Map<String, Object?>> planPaper(
    List<Map<String, Object?>> groups, {
    required List<Word> words,
    required List<Word> corpus,
    required Random random,
  }) {
    final planner = DistractorPlanner(
      sessionWords: words,
      corpus: corpus,
      random: random,
    );
    return <Map<String, Object?>>[
      for (final group in groups)
        <String, Object?>{
          ...group,
          'questions': <Map<String, Object?>>[
            for (final raw in group['questions']! as List)
              planner._planRow(Map<String, Object?>.from(raw as Map)),
          ],
        },
    ];
  }

  final Random _random;

  /// 按编号查考察对象（会话快照优先）。
  final Map<int, Word> _words = <int, Word>{};

  /// 英文候选（按小写拼写去重）。
  final Map<String, _Candidate> _englishByKey = <String, _Candidate>{};

  /// 中文候选（按释义原文去重）。
  final Map<String, _Candidate> _chineseByKey = <String, _Candidate>{};

  /// 本局打乱后的英文候选。
  late final List<_Candidate> _english;

  /// 本局打乱后的中文候选。
  late final List<_Candidate> _chinese;

  /// A、B、C、D 四格各放过几次正确答案。
  final List<int> _slotCounts = List<int>.filled(4, 0);

  /// 已经记过账的题数：用来记录每个混淆项「上次出现在第几题」。
  int _asked = 0;

  /// 同音词索引：拼写 → 与它同音的其它拼写。
  static final Map<String, Set<String>> _homophones = () {
    final index = <String, Set<String>>{};
    for (final group in kHomophoneGroups) {
      for (final spelling in group) {
        (index[spelling] ??= <String>{}).addAll(
          group.where((other) => other != spelling),
        );
      }
    }
    return index;
  }();

  /// 放宽顺序：前一步凑不齐三个，才进入下一步。
  static const List<_Stage> _stages = <_Stage>[
    _Stage(reserve: false, fresh: true, lengthTolerance: 2, samePos: true),
    _Stage(reserve: false, fresh: true, lengthTolerance: 2),
    _Stage(reserve: false, fresh: true, lengthTolerance: 4),
    _Stage(reserve: false, fresh: true),
    _Stage(reserve: false, fresh: false),
    _Stage(reserve: true, fresh: true, lengthTolerance: 2, samePos: true),
    _Stage(reserve: true, fresh: true, lengthTolerance: 2),
    _Stage(reserve: true, fresh: true),
    _Stage(reserve: true, fresh: false),
  ];

  /// 旧局补题前，把本局已经出过的题记上账：用过哪些干扰项、答案占过哪几格。
  ///
  /// [options] 为空说明这道题还没排过顺序，只记干扰项。
  void remember({
    required bool english,
    required List<String> answers,
    required List<String> distractors,
    List<String>? options,
  }) {
    final index = _asked++;
    final pool = english ? _englishByKey : _chineseByKey;
    for (final text in distractors) {
      final candidate = pool[_keyOf(text, english)];
      if (candidate == null) continue;
      candidate.uses++;
      candidate.lastUsed = index;
    }
    if (options == null || options.length != 4) return;
    for (final answer in answers) {
      final slot = options.indexOf(answer);
      if (slot >= 0) _slotCounts[slot]++;
    }
  }

  /// 为一道选择题挑混淆项，并排好四个候选；凑不齐四个不同候选时返回 null。
  PlannedOptions? plan(DistractorQuestion question) {
    if (!question.isChoice) return null;
    // 原生保存答案时会去掉首尾空格，这里用同一份文本，页面才认得出哪个是答案。
    final answers = <String>[
      for (final answer in question.answers)
        if (answer.trim().isNotEmpty) answer.trim(),
    ];
    final needed = 4 - answers.length;
    if (answers.isEmpty || needed <= 0) return null;
    final rule = _Rule.of(question, answers, _words);
    final pool = question.english ? _english : _chinese;
    final chosen = <_Candidate>[];
    for (final stage in _stages) {
      if (chosen.length >= needed) break;
      // 不知道目标词性（用户没填）时，「同词性优先」这一步直接跳过。
      if (stage.samePos && rule.pos.isEmpty) continue;
      _collect(pool, stage, rule, chosen, needed);
    }
    if (chosen.length < needed) return null;
    final index = _asked++;
    for (final candidate in chosen) {
      candidate.uses++;
      candidate.lastUsed = index;
    }
    final distractors = <String>[
      for (final candidate in chosen) candidate.text,
    ];
    return (
      distractors: List<String>.unmodifiable(distractors),
      options: List<String>.unmodifiable(_arrange(answers, distractors)),
    );
  }

  /// 开局编卷时处理试卷里的一行：只给还没有混淆项的选择题补上。
  Map<String, Object?> _planRow(Map<String, Object?> raw) {
    final question = DistractorQuestion.fromPaper(raw);
    if (!question.isChoice || raw['distractors'] != null) return raw;
    final planned = plan(question);
    // 词库和备用词表都凑不齐时先不定，答题时再按同一套规则补。
    if (planned == null) return raw;
    return <String, Object?>{
      ...raw,
      'distractors': planned.distractors,
      'options': planned.options,
    };
  }

  /// 按某一步的条件，从 [pool] 里往 [chosen] 补候选，直到够 [needed] 个。
  void _collect(
    List<_Candidate> pool,
    _Stage stage,
    _Rule rule,
    List<_Candidate> chosen,
    int needed,
  ) {
    Iterable<_Candidate> source = pool.where(
      (candidate) =>
          candidate.reserve == stage.reserve &&
          (candidate.uses == 0) == stage.fresh,
    );
    if (!stage.fresh) {
      // 本局用过的：先挑用得最少的，再挑上次出现离现在最远的，让重复尽量隔得远。
      source = source.toList()
        ..sort((first, second) {
          final byUses = first.uses.compareTo(second.uses);
          if (byUses != 0) return byUses;
          final byRecent = first.lastUsed.compareTo(second.lastUsed);
          if (byRecent != 0) return byRecent;
          final byLength = (first.length - rule.length).abs().compareTo(
            (second.length - rule.length).abs(),
          );
          return byLength != 0
              ? byLength
              : first.order.compareTo(second.order);
        });
    }
    final tolerance = stage.lengthTolerance;
    for (final candidate in source) {
      if (chosen.length >= needed) return;
      if (tolerance != null &&
          (candidate.length - rule.length).abs() > tolerance) {
        continue;
      }
      if (stage.samePos && !candidate.pos.any(rule.pos.contains)) continue;
      if (chosen.contains(candidate) || !rule.allows(candidate, chosen)) {
        continue;
      }
      chosen.add(candidate);
    }
  }

  /// 按「洗牌发牌」决定正确答案放哪几格，其余格子随机填干扰项。
  List<String> _arrange(List<String> answers, List<String> distractors) {
    final slots = <int>[];
    for (var i = 0; i < answers.length; i++) {
      final free = <int>[
        for (var slot = 0; slot < 4; slot++)
          if (!slots.contains(slot)) slot,
      ];
      final fewest = free.map((slot) => _slotCounts[slot]).reduce(min);
      final lightest = <int>[
        for (final slot in free)
          if (_slotCounts[slot] == fewest) slot,
      ];
      final slot = lightest[_random.nextInt(lightest.length)];
      slots.add(slot);
      _slotCounts[slot]++;
    }
    final rest = List<String>.of(distractors)..shuffle(_random);
    final options = List<String?>.filled(4, null);
    for (var i = 0; i < answers.length; i++) {
      options[slots[i]] = answers[i];
    }
    var next = 0;
    for (var slot = 0; slot < 4; slot++) {
      options[slot] ??= rest[next++];
    }
    return <String>[for (final option in options) option!];
  }

  /// 把词库里的一个单词加进英文、中文两个候选池。
  void _addLibraryWord(Word word) {
    final spelling = word.spelling.trim();
    final meanings = word.rawMeanings;
    if (_looksLikeEnglishWord(spelling)) {
      final key = _keyOf(spelling, true);
      final candidate = _englishByKey.putIfAbsent(
        key,
        () => _Candidate(text: spelling, key: key, reserve: false),
      );
      // 同一个拼写在词库里出现多次时，意思和词性都并在一起核对。
      for (final meaning in meanings) {
        final definition = meaning.definition.trim();
        if (definition.isNotEmpty) candidate.senses.add(definition);
        final pos = _normalizePos(meaning.pos);
        if (pos != null) candidate.pos.add(pos);
      }
    }
    for (final meaning in meanings) {
      final definition = meaning.definition.trim();
      if (definition.isEmpty) continue;
      final candidate = _chineseByKey.putIfAbsent(
        definition,
        () => _Candidate(text: definition, key: definition, reserve: false),
      );
      final pos = _normalizePos(meaning.pos);
      if (pos != null) candidate.pos.add(pos);
    }
  }

  /// 把备用词表里的一个词加进候选池；词库里已经有的拼写或释义不重复收。
  void _addReserveWord(ReserveWord entry) {
    final pos = _normalizePos(entry.pos);
    final key = _keyOf(entry.spelling, true);
    if (!_englishByKey.containsKey(key)) {
      final candidate = _Candidate(
        text: entry.spelling,
        key: key,
        reserve: true,
      )..senses.add(entry.definition);
      if (pos != null) candidate.pos.add(pos);
      _englishByKey[key] = candidate;
    }
    if (!_chineseByKey.containsKey(entry.definition)) {
      final candidate = _Candidate(
        text: entry.definition,
        key: entry.definition,
        reserve: true,
      );
      if (pos != null) candidate.pos.add(pos);
      _chineseByKey[entry.definition] = candidate;
    }
  }

  /// 比较用的文本：英文忽略大小写，中文只去首尾空格。
  static String _keyOf(String text, bool english) =>
      english ? text.trim().toLowerCase() : text.trim();

  /// 词性统一成小写；没填词性返回 null。及物、不及物动词都算动词。
  static String? _normalizePos(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == '*') return null;
    if (value == 'vt.' || value == 'vi.') return 'v.';
    return value;
  }

  /// 检查字符串是否符合基本英文拼写形态。
  ///
  /// 允许纯字母，以及 can't / well-known 这类中间带撇号或连字符的形态；
  /// 三个相同字母连在一起的通常是录入错误，也不拿来当候选。
  static bool _looksLikeEnglishWord(String value) {
    if (!RegExp(r"^[A-Za-z]+(?:['-][A-Za-z]+)*$").hasMatch(value)) {
      return false;
    }
    return !RegExp(r'([A-Za-z])\1\1', caseSensitive: false).hasMatch(value);
  }
}

///
/// 一步放宽条件。
class _Stage {
  const _Stage({
    required this.reserve,
    required this.fresh,
    this.lengthTolerance,
    this.samePos = false,
  });

  /// 这一步从备用词表里挑（false 表示从词库里挑）。
  final bool reserve;

  /// 这一步只挑本局还没用过的（false 表示只挑用过的）。
  final bool fresh;

  /// 与正确答案的长度差上限（英文按字母数，中文按字数）；null 表示不限。
  final int? lengthTolerance;

  /// 是否要求与目标词性相同。
  final bool samePos;
}

///
/// 一个候选（英文单词或中文释义）以及它在本局的使用记录。
class _Candidate {
  _Candidate({required this.text, required this.key, required this.reserve});

  /// 显示在候选卡上的文本。
  final String text;

  /// 比较用的文本（英文已转小写）。
  final String key;

  /// 是否来自内置备用词表。
  final bool reserve;

  /// 词性（小写，如 `n.`、`v.`）。
  final Set<String> pos = <String>{};

  /// 英文候选的全部中文意思：看义选词用它排除「两个选项都对」。
  final Set<String> senses = <String>{};

  /// 本局打乱后的先后次序。
  int order = 0;

  /// 本局已经当过几次干扰项。
  int uses = 0;

  /// 最近一次出现在第几道题（从 0 数）；没出现过为 -1。
  int lastUsed = -1;

  /// 长度：英文按字母数，中文按字数。
  int get length => key.runes.length;
}

///
/// 一道题的挑选条件：答案、目标词性、不能撞车的意思、同音词。
class _Rule {
  const _Rule._({
    required this.english,
    required this.length,
    required this.pos,
    required this.answerKeys,
    required this.ownDefinitions,
    required this.prompt,
    required this.homophones,
  });

  factory _Rule.of(
    DistractorQuestion question,
    List<String> answers,
    Map<int, Word> words,
  ) {
    final english = question.english;
    final targetIds = <int>{
      for (final detail in question.details) detail.wordId,
    };
    final targets = <Word>[
      for (final id in targetIds)
        if (words[id] != null) words[id]!,
    ];
    final meaningIds = <int>{
      for (final detail in question.details)
        if (detail.meaningId != null) detail.meaningId!,
    };
    // 目标词性：选中文题看考的那条含义；看义选词看题目那句中文所属的含义。
    // 听音选单词题不看词性，只要求长得不一样、读音不一样。
    final pos = <String>{};
    for (final word in targets) {
      for (final meaning in word.rawMeanings) {
        if (!meaningIds.contains(meaning.id)) continue;
        final value = DistractorPlanner._normalizePos(meaning.pos);
        if (value != null) pos.add(value);
      }
    }
    final answerKeys = <String>{
      for (final answer in answers) DistractorPlanner._keyOf(answer, english),
    };
    // 当前单词的全部含义（含答案本身）：中文混淆项不能是其中任何一条，
    // 也不能和其中任何一条长得像。
    final ownDefinitions = <String>{
      if (!english) ...answerKeys,
      for (final word in targets)
        for (final meaning in word.rawMeanings)
          if (meaning.definition.trim().isNotEmpty) meaning.definition.trim(),
    };
    final listening = english && question.contentType == 1;
    final prompt = question.content.trim();
    return _Rule._(
      english: english,
      length: answers.first.runes.length,
      pos: pos,
      answerKeys: answerKeys,
      ownDefinitions: ownDefinitions,
      prompt: english && question.contentType == 2 && prompt.isNotEmpty
          ? prompt
          : null,
      homophones: <String>{
        if (listening)
          for (final key in answerKeys)
            ...?DistractorPlanner._homophones[key],
      },
    );
  }

  /// 候选是英文还是中文。
  final bool english;

  /// 正确答案的长度（英文按字母数，中文按字数）。
  final int length;

  /// 目标词性；为空表示不知道。
  final Set<String> pos;

  /// 正确答案（比较用文本）。
  final Set<String> answerKeys;

  /// 当前单词的全部含义（仅中文候选用）。
  final Set<String> ownDefinitions;

  /// 看义选词题目那句中文；其它题型为 null。
  final String? prompt;

  /// 与答案同音的拼写（仅听音选单词题）。
  final Set<String> homophones;

  /// [candidate] 能不能和已经选中的 [chosen] 一起出现在这道题里。
  bool allows(_Candidate candidate, List<_Candidate> chosen) {
    if (answerKeys.contains(candidate.key)) return false;
    if (english) {
      for (final key in answerKeys) {
        if (_englishAlike(key, candidate.key)) return false;
      }
      for (final other in chosen) {
        if (_englishAlike(other.key, candidate.key)) return false;
      }
      if (homophones.contains(candidate.key)) return false;
      final prompt = this.prompt;
      if (prompt != null &&
          candidate.senses.any((sense) => _chineseAlike(sense, prompt))) {
        return false;
      }
      return true;
    }
    for (final definition in ownDefinitions) {
      if (_chineseAlike(definition, candidate.key)) return false;
    }
    for (final other in chosen) {
      if (_chineseAlike(other.key, candidate.key)) return false;
    }
    return true;
  }
}

/// 两个英文单词（已转小写）是否「长得像」，满足任意一条就算像：
/// - 开头有 2 个及以上字母相同（price / prize）；
/// - 最后 3 个字母相同（nation / station）；
/// - 一个包含另一个（act / action，只看 3 个字母以上的）；
/// - 不同的字母不到一半（按编辑距离算，place / price）。
///
/// 不要求首字母也必须不同：那样听音题只要听清第一个音就能选对，太简单了。
bool _englishAlike(String first, String second) {
  if (first == second) return true;
  final shorter = first.length <= second.length ? first : second;
  final longer = first.length <= second.length ? second : first;
  if (shorter.length >= 3 && longer.contains(shorter)) return true;
  if (_commonPrefixLength(first, second) >= 2) return true;
  if (first.length >= 3 &&
      second.length >= 3 &&
      first.substring(first.length - 3) ==
          second.substring(second.length - 3)) {
    return true;
  }
  return _levenshteinDistance(first, second) * 2 < longer.length;
}

/// 两句中文是否「长得像」，满足任意一条就算像：
/// - 第一个字相同（价格 / 价值，(使)疼痛 / (一次)经历）；
/// - 去掉「的、地、使、括号、省略号」这类常见虚字和符号后，第一个字相同，
///   或一个包含另一个（快的 / 愉快的，惊奇 / 使惊奇）；
/// - 去掉虚字后，共用的字达到较短那句的一半（动物 / 植物）。
///
/// 虚字不算进「共用的字」：否则「快乐的」和「美丽的」只因为都以「的」结尾就
/// 被当成长得像，形容词题的干扰项就只能挑名词、动词，答案反而一眼被认出来。
bool _chineseAlike(String first, String second) {
  if (first == second) return true;
  if (first.isEmpty || second.isEmpty) return true;
  if (first.runes.first == second.runes.first) return true;
  var a = _chineseCore(first);
  var b = _chineseCore(second);
  // 整句都是虚字的释义（「使得」「地」）去掉虚字就空了，这时两边都按原文比较。
  if (a.isEmpty || b.isEmpty) {
    a = first;
    b = second;
  }
  if (a.runes.first == b.runes.first) return true;
  if (a.contains(b) || b.contains(a)) return true;
  final aRunes = a.runes.toSet();
  final bRunes = b.runes.toSet();
  final shared = aRunes.intersection(bRunes).length;
  return shared * 2 >= min(a.runes.length, b.runes.length);
}

/// 比较中文长相时忽略的虚字和符号。
final Set<int> _chineseFiller = '的地得使()（）…,，;；、.·/ '.runes.toSet();

/// 去掉虚字和符号后剩下的「实词部分」。
String _chineseCore(String text) => String.fromCharCodes(
  text.runes.where((rune) => !_chineseFiller.contains(rune)),
);

/// 两个文本从开头连续相同的字符数。
int _commonPrefixLength(String first, String second) {
  final limit = min(first.length, second.length);
  for (var index = 0; index < limit; index++) {
    if (first.codeUnitAt(index) != second.codeUnitAt(index)) return index;
  }
  return limit;
}

/// 两个文本的编辑距离：最少改几个字符能把一个变成另一个。
int _levenshteinDistance(String first, String second) {
  final a = first.runes.toList(growable: false);
  final b = second.runes.toList(growable: false);
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final replace = previous[j] + (a[i] == b[j] ? 0 : 1);
      final insert = current[j] + 1;
      final delete = previous[j + 1] + 1;
      current[j + 1] = min(replace, min(insert, delete));
    }
    previous = current;
  }
  return previous.last;
}
