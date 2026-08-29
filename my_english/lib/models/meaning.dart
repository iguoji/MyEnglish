///
/// 单词下的一条中文释义。
///
/// 新结构里「一行 = 一条释义」：`hello` 的 `int. 喂、你好` 与 `int. 嘿`
/// 是两条独立记录，而不是一条记录里塞一个数组。这样看义选词、词义连连
/// 这些「按单条释义出题」的玩法可以直接引用主键，不用再靠数组下标定位。
///
class Meaning {
  ///
  /// 创建一条释义。
  const Meaning({
    this.id,
    this.wordId,
    required this.pos,
    this.subPos,
    required this.definition,
    this.confusions = const <String>[],
    this.sort = 0,
  });

  ///
  /// SQLite 自增主键；尚未落库的新释义为空。
  final int? id;

  ///
  /// 所属单词主键，对应数据库外键 word_id。
  final int? wordId;

  ///
  /// 主词性，如 `n.` / `v.` / `adj.`；用户没选词性时是空字符串。
  final String pos;

  ///
  /// 子词性，如 `vt.` / `vi.` / `vlink.`；没有细分时为空。
  ///
  /// 生活化解释：`vt.`（及物动词）本质上还是动词，所以主词性统一记成 `v.`，
  /// 「及物 / 不及物」这一层降为子词性，便于按大类聚合统计。
  final String? subPos;

  ///
  /// 这一条中文释义本身，例如「招呼」。
  final String definition;

  ///
  /// 外形、字数相近的混淆含义；复习时实时生成，用户长按可重新生成。
  final List<String> confusions;

  ///
  /// 排序值，数字越大越靠前。
  final int sort;

  ///
  /// 展示用词性：优先显示更精确的子词性，全部小写，空词性显示 `*`。
  ///
  /// 举例：主词性 `v.` + 子词性 `vt.` → 显示 `vt.`；
  /// 主词性 `n.` 无子词性 → 显示 `n.`；两者都空 → 显示 `*`。
  String get displayPos {
    // 子词性更精确，有就优先用它。
    final preferred = (subPos ?? '').trim().isNotEmpty ? subPos!.trim() : pos.trim();
    // 统一小写，避免旧数据里的 "N." 和 "n." 显示成两种样子。
    final normalized = preferred.toLowerCase();
    // 空词性使用星号占位，避免页面绘制一个看不见但仍占位的标签。
    return normalized.isEmpty ? '*' : normalized;
  }

  ///
  /// 释义正文的字符数（按完整 Unicode 字符计，中文不会被拆成字节）。
  int get characterCount => definition.trim().runes.length;

  ///
  /// 把原生 MethodChannel 返回的一行数据转成 Meaning。
  factory Meaning.fromMap(Map<Object?, Object?> map, {int? fallbackWordId}) {
    // 释义正文是这条记录存在的意义，空的说明数据坏了。
    final definition = map['definition']?.toString();
    if (definition == null || definition.trim().isEmpty) {
      throw const FormatException('Meaning.definition 不能为空');
    }
    return Meaning(
      // 新建但未落库的释义允许没有主键。
      id: _readOptionalInt(map['id'], 'Meaning.id'),
      // 嵌套在单词里返回时没有 word_id，继承外层单词的主键。
      wordId: _readOptionalInt(map['word_id'], 'Meaning.word_id') ?? fallbackWordId,
      // 缺失词性时保存空文本，displayPos 会统一显示星号。
      pos: map['pos']?.toString() ?? '',
      // 子词性可空；空字符串一律归一成 null，避免出现两种「没有」。
      subPos: (map['sub_pos']?.toString().trim().isNotEmpty ?? false)
          ? map['sub_pos']!.toString().trim()
          : null,
      definition: definition,
      confusions: _readStringList(map['confusions'], 'Meaning.confusions'),
      // 缺失排序值时用 0，仍能稳定排在高排序值之后。
      sort: _readOptionalInt(map['sort'], 'Meaning.sort') ?? 0,
    );
  }

  ///
  /// 转成 MethodChannel 可传输的 Map，供新增和编辑使用。
  ///
  /// 不带 sort：排序值由原生按「传入顺序」自动发放，
  /// 上层只要按想显示的顺序传进来即可，不必自己算数字。
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'word_id': wordId,
    'pos': pos,
    'sub_pos': subPos,
    'definition': definition,
    'confusions': List<String>.from(confusions),
  };

  ///
  /// 返回替换了混淆含义的副本；模型不可变，改动一律通过复制表达。
  Meaning withConfusions(List<String> next) => Meaning(
    id: id,
    wordId: wordId,
    pos: pos,
    subPos: subPos,
    definition: definition,
    confusions: List<String>.unmodifiable(next),
    sort: sort,
  );

  ///
  /// 返回按表单结果编辑后的副本，供「修改单词」提交时使用。
  Meaning copyWith({String? pos, String? subPos, String? definition}) => Meaning(
    id: id,
    wordId: wordId,
    pos: pos ?? this.pos,
    // 子词性允许被清空，所以不能用 `??` —— 那样传 null 会变成「保持原值」。
    subPos: subPos,
    definition: definition ?? this.definition,
    confusions: confusions,
    sort: sort,
  );
}

///
/// 「既及物又不及物」的合并词性。
///
/// 数据库里不存这个值——它只是展示层的说法。库里存的永远是原子事实：
/// 这条含义是 `vi.`、那条含义是 `vt.`；两边撞上同一句中文时，
/// 模型层才把它们并成一行显示。
const String kTransitiveAndIntransitive = 'vi. vt.';

///
/// 光杆动词：只说明「这是个动词」，没标注及物性。
const String kVerb = 'v.';

///
/// 不及物动词。
const String kIntransitive = 'vi.';

///
/// 及物动词。
const String kTransitive = 'vt.';

///
/// 系动词。
const String kLinkingVerb = 'vlink.';

///
/// 比光杆 `v.` 更精确的那几种动词词性。
const Set<String> kSpecificVerbPos = <String>{
  kIntransitive,
  kTransitive,
  kLinkingVerb,
  kTransitiveAndIntransitive,
};

///
/// 展示用的一组释义：同一个词性下的全部条目。
///
/// 数据库里一行只有一条释义，界面上习惯把同一词性的并成一行显示：
/// `n.  招呼；问候`。这个类只服务于展示，不参与任何持久化。
class MeaningGroup {
  ///
  /// 创建一组同词性的释义。
  const MeaningGroup({required this.pos, required this.meanings});

  ///
  /// 这一组共用的展示词性，如 `n.` / `vt.` / `vi. vt.` / `*`。
  final String pos;

  ///
  /// 组内的释义，顺序与数据库排序值一致。
  final List<Meaning> meanings;

  ///
  /// 用指定的全角标点把组内释义连成一句。
  String joinedDefinitions(String separator) =>
      meanings.map((meaning) => meaning.definition).join(separator);
}

///
/// 把数据库里一维的释义列表，整理成「按词性分组」的展示结构。
///
/// 这是**模型层唯一一处**做这件事的地方：页面、出题器、导出统统直接用
/// [Word.meanings] 拿整理好的结果，不再各自写一遍分组逻辑。
///
/// 依次做四件事：
///
/// 1. **按词性归组**，保留每个词性首次出现的先后顺序。
///    同一个词性即使在库里不连续（`n.` → `vi.` → `n.`）也会并进同一组。
///
/// 2. **组内按文本去重**。历史数据里存在同词性下同一句中文录了两遍的情况
///    （rub 的 `vt.` 里「擦 / 搓 / 揉」各有两条），显示两遍毫无意义。
///
/// 3. **`vi.` 与 `vt.` 的交集并成 `vi. vt.`**：
///    ```
///    vi.  你好；我好；他好          vi.      他好
///    vt.  你好；她好；我好；它好  →  vt.      她好；它好
///                                   vi. vt.  你好；我好
///    ```
///    合并出来的组排在 `vi.` / `vt.` 之后；某一边被掏空就整组消失。
///
/// 4. **光杆 `v.` 减去更精确的动词组**。`v.` 只表示「这是个动词」，
///    同一句中文既标 `v.` 又标 `vt.` 时，那条 `v.` 是没整理干净的残留，
///    更精确的那个赢。
Map<String, List<Meaning>> buildMeaningGroups(List<Meaning> meanings) {
  // ---- 1 + 2：按词性归组并在组内去重 ----------------------------------
  // LinkedHashMap（Dart 的默认 Map）保留插入顺序，所以词性先后由首次出现决定。
  final grouped = <String, List<Meaning>>{};
  final seenByPos = <String, Set<String>>{};
  for (final meaning in meanings) {
    final text = meaning.definition.trim();
    // 空释义不该出现在任何地方。
    if (text.isEmpty) continue;
    final pos = meaning.displayPos;
    // 同一词性下这句中文已经收过了，第二条直接跳过。
    if (!(seenByPos[pos] ??= <String>{}).add(text)) continue;
    (grouped[pos] ??= <Meaning>[]).add(meaning);
  }

  // ---- 3：vi. ∩ vt. → vi. vt. -----------------------------------------
  final intransitive = grouped[kIntransitive];
  final transitive = grouped[kTransitive];
  if (intransitive != null && transitive != null) {
    final transitiveTexts = <String>{
      for (final meaning in transitive) meaning.definition.trim(),
    };
    // 交集按 vi. 的原始顺序取，保证合并组内部顺序稳定。
    final shared = <Meaning>[
      for (final meaning in intransitive)
        if (transitiveTexts.contains(meaning.definition.trim())) meaning,
    ];
    if (shared.isNotEmpty) {
      final sharedTexts = <String>{
        for (final meaning in shared) meaning.definition.trim(),
      };
      // 两边都把交集摘出去；摘空了的组稍后会被删掉。
      grouped[kIntransitive] = <Meaning>[
        for (final meaning in intransitive)
          if (!sharedTexts.contains(meaning.definition.trim())) meaning,
      ];
      grouped[kTransitive] = <Meaning>[
        for (final meaning in transitive)
          if (!sharedTexts.contains(meaning.definition.trim())) meaning,
      ];
      grouped[kTransitiveAndIntransitive] = shared;
    }
  }

  // ---- 4：光杆 v. 减去更精确的动词组 -----------------------------------
  final plainVerb = grouped[kVerb];
  if (plainVerb != null) {
    final specificTexts = <String>{
      for (final pos in kSpecificVerbPos)
        for (final meaning in grouped[pos] ?? const <Meaning>[])
          meaning.definition.trim(),
    };
    if (specificTexts.isNotEmpty) {
      grouped[kVerb] = <Meaning>[
        for (final meaning in plainVerb)
          if (!specificTexts.contains(meaning.definition.trim())) meaning,
      ];
    }
  }

  // ---- 5：删空组，并把 vi. vt. 挪到 vi./vt. 之后 -----------------------
  return _orderGroups(grouped);
}

///
/// 丢掉空组，并把合并出来的 `vi. vt.` 放到 `vi.` / `vt.` 的后面。
///
/// 位置规则：跟在仍然活着的 `vi.` / `vt.` 里靠后的那个之后；
/// 两个都被掏空时，就占用它们原来靠前的那个位置。
Map<String, List<Meaning>> _orderGroups(Map<String, List<Meaning>> grouped) {
  final merged = grouped[kTransitiveAndIntransitive];
  final hasMerged = merged != null && merged.isNotEmpty;
  final ordered = <String, List<Meaning>>{};

  for (final entry in grouped.entries) {
    // 合并组自己不按原位置走，下面单独插。
    if (entry.key == kTransitiveAndIntransitive) continue;
    if (entry.value.isNotEmpty) ordered[entry.key] = entry.value;
    // 每经过一个 vi./vt.（不论它是否被掏空）就把合并组挪到当前末尾，
    // 于是它最终停在两者中靠后的那个之后。
    if (hasMerged &&
        (entry.key == kIntransitive || entry.key == kTransitive)) {
      ordered.remove(kTransitiveAndIntransitive);
      ordered[kTransitiveAndIntransitive] = merged;
    }
  }
  // 兜底：原始分组里没有 vi./vt. 时（理论上不会发生）也别把合并组弄丢。
  if (hasMerged && !ordered.containsKey(kTransitiveAndIntransitive)) {
    ordered[kTransitiveAndIntransitive] = merged;
  }

  return Map<String, List<Meaning>>.unmodifiable(<String, List<Meaning>>{
    for (final entry in ordered.entries)
      entry.key: List<Meaning>.unmodifiable(entry.value),
  });
}

///
/// 把展示用的一个词性，拆回数据库要存的「主词性 + 子词性」若干条。
///
/// 界面上用户看到和填写的是一个词性（`vt.`、`vi. vt.`、`n.`），
/// 但库里分两级存，而且 `vi. vt.` 根本不是一个真实取值——它是模型层
/// 把 `vi.` 和 `vt.` 并起来的说法，写回去时要还原成两条。
///
/// 规则与 `tools/migrate_v2.py` 完全一致，保证手动录入和批量迁移结果相同。
List<({String pos, String? subPos})> splitPos(String input) {
  final value = input.trim().toLowerCase();
  return switch (value) {
    // 未选词性：主词性存空串，界面照旧显示成 '*'。
    '' || '*' => const <({String pos, String? subPos})>[
      (pos: '', subPos: null),
    ],
    // 动词的三种子类：主词性统一记成 v.，细分降为子词性。
    kIntransitive => const <({String pos, String? subPos})>[
      (pos: kVerb, subPos: kIntransitive),
    ],
    kTransitive => const <({String pos, String? subPos})>[
      (pos: kVerb, subPos: kTransitive),
    ],
    kLinkingVerb => const <({String pos, String? subPos})>[
      (pos: kVerb, subPos: kLinkingVerb),
    ],
    // 「既及物又不及物」拆回两条真实记录。
    kTransitiveAndIntransitive => const <({String pos, String? subPos})>[
      (pos: kVerb, subPos: kIntransitive),
      (pos: kVerb, subPos: kTransitive),
    ],
    // 其余（n. / adj. / adv. / num. / prep. / conj. / int.）本身就是主词性。
    _ => <({String pos, String? subPos})>[(pos: value, subPos: null)],
  };
}

///
/// 读取可空整数；不接受字符串数字，避免上游格式错误被静默掩盖。
int? _readOptionalInt(Object? value, String fieldName) {
  if (value == null) return null;
  // JSON 数字和原生 Long 都属于 num，统一收窄为 Dart int。
  if (value is num) return value.toInt();
  throw FormatException('$fieldName 必须是数字，实际值为：$value');
}

///
/// 把动态值收窄成字符串数组；缺失时返回空数组。
List<String> _readStringList(Object? value, String fieldName) {
  if (value == null) return const <String>[];
  if (value is! List) throw FormatException('$fieldName 必须是数组');
  return List<String>.unmodifiable(
    value.map((item) {
      if (item == null) throw FormatException('$fieldName 不能包含 null');
      return item.toString();
    }),
  );
}
