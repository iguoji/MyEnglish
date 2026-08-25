import 'dart:math';

///
/// 候选区里的一个片段按钮。
///
/// 生活化解释：拼写巩固的片段模式会把一个单词切成几块（比如 tradition →
/// tra / di / tion），然后把这几块和一堆「长得很像但不对」的块混在一起打乱，
/// 让用户按顺序挑出正确的那几块。这个类就表示其中一个块。
///
class SpellingChunk {
  ///
  /// 创建一个候选片段。
  const SpellingChunk({required this.text, required this.isCorrect});

  ///
  /// 按钮上显示的字母组合。
  final String text;

  ///
  /// 是否属于当前单词的正确切分结果。
  ///
  /// 只用于生成阶段的统计与测试断言；页面判对错时比较的是「这一格该填什么」，
  /// 不是这个字段——因为顺序错了同样算错。
  final bool isCorrect;
}

///
/// 拼写巩固「片段模式」的候选片段生成器。
///
/// 这个类不依赖 Widget 或页面状态，因此可以独立测试「干扰项数量」与
/// 「干扰项不会和正确片段撞车」这两条约定。
///
/// 为什么需要它：`ui/拼写巩固.html` 原型给每个单词手写了一份 `confusables`
/// 干扰项表。真实词库有成千上万个词，不可能逐个手写，所以这里改成按拼写规律
/// 现场生成：元音互换、相近辅音互换、相邻字母对调、双写字母增减。
/// 生成策略与听音辨义的候选项生成器同源，保证两个模块的干扰项「像」得一致。
///
abstract final class SpellingChunkGenerator {
  ///
  /// 英文元音集合；替换元音时只在同类字母中挑选。
  static const Set<String> _vowels = <String>{'a', 'e', 'i', 'o', 'u', 'y'};

  ///
  /// 常见辅音的相近或易混淆替换表，生成结果比随机字母更像英文拼写。
  ///
  /// 与 `ListeningMeaningOptionGenerator._consonantReplacements` 保持同一份口径。
  static const Map<String, List<String>> _consonantReplacements =
      <String, List<String>>{
        'b': <String>['p', 'd'],
        'c': <String>['s', 'k'],
        'd': <String>['t', 'b'],
        'f': <String>['v', 'p'],
        'g': <String>['j', 'k'],
        'h': <String>['w', 'g'],
        'j': <String>['g', 'y'],
        'k': <String>['c', 'g'],
        'l': <String>['r', 'n'],
        'm': <String>['n', 'w'],
        'n': <String>['m', 'l'],
        'p': <String>['b', 'f'],
        'q': <String>['c', 'g'],
        'r': <String>['l', 'n'],
        's': <String>['c', 'z'],
        't': <String>['d', 'p'],
        'v': <String>['f', 'w'],
        'w': <String>['v', 'h'],
        'x': <String>['s', 'c'],
        'z': <String>['s', 'c'],
      };

  ///
  /// 每个正确片段默认配几个干扰项。
  ///
  /// 定成 2 是在「太少 → 一眼就能挑出正确的」和「太多 → 满屏按钮、找起来累」
  /// 之间取的平衡：3 个片段的词会得到 3 + 6 = 9 个按钮。
  static const int defaultDistractorsPerChunk = 2;

  ///
  /// 候选区最多显示多少个按钮。
  ///
  /// 手动拆分允许把长单词切得很碎，若不设上限，10 个片段会生成 30 个按钮，
  /// candidate 区会挤成一团。超过上限时优先保证正确片段全部在场。
  static const int maxPoolSize = 12;

  ///
  /// 为一份切分结果生成打乱后的候选池。
  ///
  /// [parts] 是这个单词当前的切分结果（顺序即正确答案顺序）；
  /// [random] 由调用方传入固定种子，保证「退出再进来」时候选顺序完全一致。
  ///
  /// 返回的列表里必定包含 [parts] 的每一项（含重复项，比如 ["tar","tar"]），
  /// 其余是长得像但不正确的干扰项。
  static List<SpellingChunk> buildPool({
    required List<String> parts,
    required Random random,
    int distractorsPerChunk = defaultDistractorsPerChunk,
  }) {
    // 没有切分结果就没有候选区可言（这种词会走键盘模式）。
    if (parts.isEmpty) return const <SpellingChunk>[];

    // 正确片段先全部入池：即使后面干扰项被上限截断，正确答案也一定在场，
    // 否则这一题会变成死局。
    final pool = <SpellingChunk>[
      for (final part in parts) SpellingChunk(text: part, isCorrect: true),
    ];

    // 判重集合：干扰项既不能和任何正确片段相同（否则点它会被判错，很冤），
    // 也不能和已经生成的其他干扰项相同。统一按小写比较。
    final taken = <String>{for (final part in parts) part.toLowerCase()};

    // 还能放几个干扰项。
    final budget = maxPoolSize - pool.length;
    // 正确片段已经占满上限（手动拆得极碎时会发生），直接打乱返回。
    if (budget <= 0) return _shuffled(pool, random);

    // 每个正确片段轮流贡献干扰项，这样各片段的干扰项数量是均匀的，
    // 不会出现「第一块有 5 个假货、最后一块一个都没有」的偏斜。
    final distractors = <String>[];
    for (var round = 0; round < distractorsPerChunk; round += 1) {
      for (final part in parts) {
        if (distractors.length >= budget) break;
        // 取这一片段还没被用掉的第一个变体。
        final variant = _nextVariant(part, taken);
        if (variant == null) continue;
        taken.add(variant.toLowerCase());
        distractors.add(variant);
      }
      if (distractors.length >= budget) break;
    }

    pool.addAll(
      distractors.map(
        (text) => SpellingChunk(text: text, isCorrect: false),
      ),
    );
    return _shuffled(pool, random);
  }

  ///
  /// 取某个片段的下一个可用变体；全部变体都被占用时返回 null。
  static String? _nextVariant(String part, Set<String> taken) {
    for (final variant in variantsOf(part)) {
      if (!taken.contains(variant.toLowerCase())) return variant;
    }
    return null;
  }

  ///
  /// 按「元音互换 → 相近辅音互换 → 相邻字母对调 → 双写增减」生成一个片段的全部变体。
  ///
  /// 四种策略交错输出，避免同一个片段的两个干扰项都是同一类错误
  /// （比如 tra 的两个干扰项都只换元音，用户会觉得选项很单调）。
  /// 非纯英文字母的片段（理论上不会出现）返回空列表。
  static List<String> variantsOf(String part) {
    // 空片段或含空格、连字符的片段不做人工改字母：这类词整体走键盘模式。
    if (part.isEmpty || !RegExp(r'^[A-Za-z]+$').hasMatch(part)) {
      return const <String>[];
    }
    final letters = part.split('');
    final vowelChanged = <String>[];
    final consonantChanged = <String>[];
    final transposed = <String>[];
    final doubled = <String>[];

    // 元音只替换成另一个元音，保留基本的英文音节形状。
    for (var index = 0; index < letters.length; index += 1) {
      final original = letters[index].toLowerCase();
      if (!_vowels.contains(original)) continue;
      for (final replacement in _vowels) {
        if (replacement == original) continue;
        final changed = <String>[...letters];
        changed[index] = _matchCase(replacement, letters[index]);
        vowelChanged.add(changed.join());
      }
    }

    // 辅音只在易混淆表内替换，避免生成明显不像英文的串。
    for (var index = 0; index < letters.length; index += 1) {
      final original = letters[index].toLowerCase();
      final replacements = _consonantReplacements[original];
      if (replacements == null) continue;
      for (final replacement in replacements) {
        final changed = <String>[...letters];
        changed[index] = _matchCase(replacement, letters[index]);
        consonantChanged.add(changed.join());
      }
    }

    // 相邻字母对调：长度不变，形态与原片段高度相似（tion → tino）。
    for (var index = 0; index < letters.length - 1; index += 1) {
      // 两个字母一样时对调等于没变。
      if (letters[index].toLowerCase() == letters[index + 1].toLowerCase()) {
        continue;
      }
      final swapped = <String>[...letters];
      final first = swapped[index];
      swapped[index] = swapped[index + 1];
      swapped[index + 1] = first;
      transposed.add(swapped.join());
    }

    // 双写增减：ful → full、ll → l 这类最常见的拼写失误。
    for (var index = 0; index < letters.length; index += 1) {
      final current = letters[index];
      // 已经是双写就减一个，否则增一个。
      if (index + 1 < letters.length &&
          current.toLowerCase() == letters[index + 1].toLowerCase()) {
        final reduced = <String>[...letters]..removeAt(index + 1);
        doubled.add(reduced.join());
        continue;
      }
      final expanded = <String>[...letters]..insert(index + 1, current);
      doubled.add(expanded.join());
    }

    // 先各取一个不同策略的结果，再附加其余项作为数量回退。
    return <String>[
      if (vowelChanged.isNotEmpty) vowelChanged.first,
      if (consonantChanged.isNotEmpty) consonantChanged.first,
      if (transposed.isNotEmpty) transposed.first,
      if (doubled.isNotEmpty) doubled.first,
      ...vowelChanged.skip(1),
      ...consonantChanged.skip(1),
      ...transposed.skip(1),
      ...doubled.skip(1),
    ];
  }

  ///
  /// 把候选池就地打乱后冻结返回。
  static List<SpellingChunk> _shuffled(
    List<SpellingChunk> pool,
    Random random,
  ) {
    final shuffled = List<SpellingChunk>.of(pool)..shuffle(random);
    return List<SpellingChunk>.unmodifiable(shuffled);
  }

  ///
  /// 让替换字母沿用原字母的大小写。
  ///
  /// 词库里的词可能首字母大写（如 Tradition），替换后不该突然变成小写。
  static String _matchCase(String replacement, String original) =>
      original == original.toUpperCase()
      ? replacement.toUpperCase()
      : replacement;
}
