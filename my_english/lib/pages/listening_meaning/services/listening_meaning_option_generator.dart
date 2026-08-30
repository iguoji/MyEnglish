// 引入全局 Word 模型，候选项需要从首页传入的词库中读取拼写和释义。
import 'dart:math';

import '../../../models/word.dart';

///
/// 听音辨义候选项生成器：只负责候选数据的生成规则，不依赖任何 UI 状态。
///
/// 这个类不依赖 Widget 或页面状态，因此可以独立测试“始终三个干扰项”和相似度排序。
///
abstract final class ListeningMeaningOptionGenerator {
  ///
  /// 英文元音集合，替换元音时只在同类字母中选择。
  static const Set<String> _vowels = <String>{'a', 'e', 'i', 'o', 'u', 'y'};

  ///
  /// 常见辅音的相近或易混淆替换表，生成结果比随机字符更像英文拼写。
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
  /// 当首页词库过小或数据异常时，使用真实常见英文词作为最后一层保底。
  static const List<String> _wordFallbackBank = <String>[
    'answer',
    'choice',
    'change',
    'learn',
    'study',
    'word',
    'sound',
    'meaning',
  ];

  ///
  /// 为英文拼写生成固定数量的不重复干扰项。
  static List<String> buildWordDistractors({
    required String correct,
    required List<Word> sourceWords,
    int count = 3,
  }) {
    // count 为 0 时没有干扰项需要生成。
    if (count <= 0) return const <String>[];
    // 清理首尾空格，但不改变单词的原始大小写。
    final normalizedCorrect = correct.trim();
    // LinkedHashSet 的默认实现会保留插入顺序，方便按规则优先级取值。
    final distractors = <String>{};

    // 第一层先用同长度的换位和替换生成外观相似的英文拼写。
    for (final variant in _syntheticWordVariants(normalizedCorrect)) {
      // 候选值必须通过英文形态检查并且不能与正确答案重复。
      _addUniqueWordCandidate(distractors, variant, normalizedCorrect);
      // 已经满足数量时立即停止，避免生成无用数据。
      if (distractors.length >= count) break;
    }

    // 人工变体不足时，按长度和编辑距离从首页传入的词库中挑选。
    if (distractors.length < count) {
      // 只提取非空拼写，排序方法会让同字母数的真实单词靠前。
      final sourceSpellings = sourceWords
          .map((word) => word.spelling.trim())
          .where((spelling) => spelling.isNotEmpty);
      // 依次把最相似的真实单词补入结果。
      for (final spelling in _rankBySimilarity(
        normalizedCorrect,
        sourceSpellings,
      )) {
        _addUniqueWordCandidate(distractors, spelling, normalizedCorrect);
        if (distractors.length >= count) break;
      }
    }

    // 极端情况下活动词库可能只有一个单词，最后用常见英文词保证交互始终是四选一。
    if (distractors.length < count) {
      for (final spelling in _rankBySimilarity(
        normalizedCorrect,
        _wordFallbackBank,
      )) {
        _addUniqueWordCandidate(distractors, spelling, normalizedCorrect);
        if (distractors.length >= count) break;
      }
    }

    // 转为不可修改列表，防止 UI 层意外破坏候选生成结果。
    return List<String>.unmodifiable(distractors.take(count));
  }

  ///
  /// 按《含义混淆词.md》的「共享汉字」算法生成中文释义干扰项。
  ///
  /// 核心思想（不用 AI）：中文是表意文字，共享汉字通常意味着共享语义场。所以
  /// 不再像旧版那样对候选纯随机洗牌，而是分优先级去词库里找「和正确答案共享
  /// 某个汉字 / 相同前缀 / 相同后缀」的释义，语义上更接近、也更像“该混淆”。
  ///
  /// 候选来源 [sourceWords]：页面会传入**整个词库**（而不是本轮学习列表），这样才能
  /// 有几千条中文释义做候选池，共享汉字才找得到对应的同类词。
  ///
  /// 递进式优先级（只要某个层级凑够 [count] 就停下）：
  /// 1. 相同前缀 / 后缀（长度 ≥ 2 且字数相同，最精准）；
  /// 2. 共享任意单字（字数差 ≤ 1，泛关联）；
  /// 3. 同字数纯随机（拿到找得到共享字的魑魅、饕餮这类词）；
  /// 4. 整个语料纯随机（极小概率的绝对兜底）。
  ///
  /// 严格的互斥：绝不使用当前词的其他含义（[excludeDefinitions]），也排除与正确答案
  /// 互为子串 / 包含的歧义词。
  ///
  /// [excludeDefinitions] 是本条正确答案所在单词自身的全部释义集合：同一个单词往往有
  /// 多个含义（例如能力 / 才能），它们绝不能互相充当干扰项。
  ///
  /// 词库极小（例如用户只录入了 1 个单词）时候选池可能为空，此时返回空列表，绝不强行
  /// 凑够 [count] 个——没有混淆项就不硬造。
  static List<String> buildDefinitionDistractors({
    required String correct,
    required List<Word> sourceWords,
    int count = 3,
    Set<String> excludeDefinitions = const <String>{},
  }) {
    if (count <= 0) return const <String>[];
    // 中文释义统一清理首尾空格。
    final normalizedCorrect = correct.trim();
    final normalizedExcluded = excludeDefinitions
        .map((definition) => definition.trim())
        .where((definition) => definition.isNotEmpty)
        .toSet();
    // 把传入词库的全部释义拉平成“常驻候选池”，供后续各优先级筛选。
    final corpus = <String>{
      for (final word in sourceWords)
        for (final meaning in word.allMeanings)
          if (meaning.definition.trim().isNotEmpty) meaning.definition.trim(),
    };

    final targetLen = normalizedCorrect.length;
    final blacklist = <String>{...normalizedExcluded, normalizedCorrect};

    // 互斥判断：命中当前词的其他含义，或与正确答案互为子串，都不可作候选。
    bool isInvalid(String candidate) {
      if (blacklist.contains(candidate)) return true;
      if (candidate.contains(normalizedCorrect) ||
          normalizedCorrect.contains(candidate)) {
        return true;
      }
      return false;
    }

    // 用集合收拢候选，天然去重。
    final pool = <String>{};

    // ----- 优先级 1：相同前缀 / 后缀（最精准的同类词）-----
    if (targetLen >= 2) {
      final prefix = normalizedCorrect.substring(0, targetLen - 1);
      final suffix = normalizedCorrect.substring(1);
      for (final w in corpus) {
        if (w.length != targetLen || isInvalid(w)) continue;
        if (w.startsWith(prefix) || w.endsWith(suffix)) pool.add(w);
      }
    }

    // ----- 优先级 2：字级共享（泛关联）-----
    if (pool.length < count) {
      for (final w in corpus) {
        if (isInvalid(w)) continue;
        if ((w.length - targetLen).abs() > 1) continue;
        final chars = normalizedCorrect.split('');
        for (final ch in chars) {
          if (w.contains(ch)) {
            pool.add(w);
            break;
          }
        }
      }
    }

    // ----- 优先级 3：同字数纯随机（兜底，魑魅饕餮这类共享字极少的词）-----
    if (pool.length < count) {
      for (final w in corpus) {
        if (w.length == targetLen && !isInvalid(w)) pool.add(w);
      }
    }

    // ----- 优先级 4：绝对兜底，整个语料随便拿 -----
    if (pool.length < count) {
      for (final w in corpus) {
        if (!isInvalid(w)) pool.add(w);
      }
    }

    // 池内随机打乱，取前 count 个；不足 count 时有多少给多少（不强凑）。
    final list = pool.toList(growable: false)..shuffle(Random());
    return List<String>.unmodifiable(list.take(count));
  }

  ///
  /// 为长按刷新寻找一个尚未出现在当前四选一中的新英文干扰项。
  static String? findReplacementWordDistractor({
    required String correct,
    required List<Word> sourceWords,
    required Iterable<String> excluded,
  }) {
    // 英文比较忽略大小写，避免用 Ability 替换 ability 形成视觉重复。
    final normalizedExcluded = excluded
        .map((value) => value.trim().toLowerCase())
        .toSet();
    // 请求较大的候选池；生成器仍按相似度顺序返回，因此替换项不会突然变得离谱。
    final candidates = buildWordDistractors(
      correct: correct,
      sourceWords: sourceWords,
      count: 64,
    );
    // 返回第一个未在当前选项中的候选；候选池耗尽时返回 null 交给 UI 提示。
    for (final candidate in candidates) {
      if (!normalizedExcluded.contains(candidate.trim().toLowerCase())) {
        return candidate;
      }
    }
    return null;
  }

  ///
  /// 为长按刷新寻找一个尚未出现在当前四选一中的新中文释义干扰项。
  ///
  /// [excludeDefinitions] 语义同 [buildDefinitionDistractors]：刷新后的新候选
  /// 也必须避开当前单词自身的全部含义，避免“换一道”却还看到同词的其他释义。
  static String? findReplacementDefinitionDistractor({
    required String correct,
    required List<Word> sourceWords,
    required Iterable<String> excluded,
    Set<String> excludeDefinitions = const <String>{},
  }) {
    // 中文释义按去除首尾空格后的完整文本判重。
    final normalizedExcluded = excluded.map((value) => value.trim()).toSet();
    // 与初次生成共用相似度规则，只扩大候选池以便找到第四个以后的备选项。
    final candidates = buildDefinitionDistractors(
      correct: correct,
      sourceWords: sourceWords,
      count: 64,
      excludeDefinitions: excludeDefinitions,
    );
    // 找到第一条未显示的释义就返回。
    for (final candidate in candidates) {
      if (!normalizedExcluded.contains(candidate.trim())) return candidate;
    }
    return null;
  }

  ///
  /// 按“中心交换、元音替换、相近辅音替换”生成同长度英文变体。
  static List<String> _syntheticWordVariants(String word) {
    // 非纯英文单词不做人工改字母，会直接进入真实词库回退。
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(word)) return const <String>[];
    // 把单词拆成字符列表，逐个位置执行替换。
    final letters = word.split('');
    // 三种策略分开收集，最后交错取值，避免三个选项都是同一类错误。
    final transposed = <String>[];
    final vowelChanged = <String>[];
    final consonantChanged = <String>[];
    // 从单词中心向两侧的顺序更容易生成肉眼难以立即识别的相似项。
    final positions = _centerFirstPositions(letters.length);
    // 交换策略先从约三分之一位置开始，ability 这类单词会产生常见的 abliity 形态。
    final preferredSwapPosition = letters.length > 1
        ? (letters.length ~/ 3).clamp(0, letters.length - 2)
        : 0;
    // 优先位置之后再依中心距离补入其他位置，且不重复。
    final swapPositions = <int>[
      if (letters.length > 1) preferredSwapPosition,
      for (final position in positions)
        if (position != preferredSwapPosition) position,
    ];

    // 交换相邻字母，长度不变且形态与原词高度相似。
    for (final position in swapPositions) {
      // 最后一个字母没有右侧相邻项，因此需要跳过。
      if (position >= letters.length - 1) continue;
      // 相同字母交换后没有变化，不能作为干扰项。
      if (letters[position].toLowerCase() ==
          letters[position + 1].toLowerCase()) {
        continue;
      }
      // 复制列表后再交换，不修改原始 word。
      final swapped = <String>[...letters];
      // 临时保存左侧字母。
      final first = swapped[position];
      // 把右侧字母放到左侧。
      swapped[position] = swapped[position + 1];
      // 把临时保存的字母放到右侧。
      swapped[position + 1] = first;
      // 重新拼成字符串。
      transposed.add(swapped.join());
    }

    // 元音只替换为另一个元音，保留基本英文音节结构。
    for (final position in positions) {
      // 读取当前字母的小写形态。
      final original = letters[position].toLowerCase();
      // 非元音交给后面的辅音规则。
      if (!_vowels.contains(original)) continue;
      // 依次尝试其他常见元音。
      for (final replacement in _vowels) {
        // 不把字母替换为它自己。
        if (replacement == original) continue;
        // 复制原字母列表。
        final changed = <String>[...letters];
        // 按原字母大小写套用新元音。
        changed[position] = _matchCase(replacement, letters[position]);
        // 保存同长度结果。
        vowelChanged.add(changed.join());
      }
    }

    // 辅音替换只使用易混淆字母表，避免生成明显不像英文的串。
    for (final position in positions) {
      // 读取小写原字母。
      final original = letters[position].toLowerCase();
      // 没有专用替换组的字母不强行变更。
      final replacements = _consonantReplacements[original];
      // null 表示不需要生成该位置的辅音变体。
      if (replacements == null) continue;
      // 一个字母可以有多个相近替换。
      for (final replacement in replacements) {
        // 复制列表以保留原单词。
        final changed = <String>[...letters];
        // 替换当前辅音并保留原大小写。
        changed[position] = _matchCase(replacement, letters[position]);
        // 保存结果。
        consonantChanged.add(changed.join());
      }
    }

    // 先各取一个不同策略的结果，再附加其余项作为数量回退。
    return <String>[
      if (transposed.isNotEmpty) transposed.first,
      if (vowelChanged.isNotEmpty) vowelChanged.first,
      if (consonantChanged.isNotEmpty) consonantChanged.first,
      ...transposed.skip(1),
      ...vowelChanged.skip(1),
      ...consonantChanged.skip(1),
    ];
  }

  ///
  /// 按长度、编辑距离、公共前缀和原始顺序稳定排列字符串。
  static List<String> _rankBySimilarity(
    String target,
    Iterable<String> values,
  ) {
    // 先去除空值和大小写意义上的重复值。
    final uniqueValues = <String>[];
    // 用小写集合判断英文重复，中文转小写后保持不变。
    final normalizedValues = <String>{};
    // 依次读取输入源。
    for (final rawValue in values) {
      // 清理外部数据的首尾空格。
      final value = rawValue.trim();
      // 空值不可作为可点击候选项。
      if (value.isEmpty) continue;
      // 归一化大小写。
      final normalized = value.toLowerCase();
      // Set.add 返回 false 表示已经收集过同文本。
      if (!normalizedValues.add(normalized)) continue;
      // 保留第一次出现的原始文本。
      uniqueValues.add(value);
    }
    // 把每个字符串连同排序分数一起保存。
    final scored =
        <
          ({
            String value,
            int sourceIndex,
            int lengthDifference,
            int editDistance,
            int commonPrefix,
          })
        >[];
    // 目标长度使用 Unicode 码点数，中文汉字会按一个字计算。
    final targetLength = target.runes.length;
    // 为每个唯一候选计算分数。
    for (var index = 0; index < uniqueValues.length; index++) {
      // 读取当前文本。
      final value = uniqueValues[index];
      // 保存各项可比较数据。
      scored.add((
        value: value,
        sourceIndex: index,
        lengthDifference: (value.runes.length - targetLength).abs(),
        editDistance: _levenshteinDistance(target, value),
        commonPrefix: _commonPrefixLength(target, value),
      ));
    }
    // sort 依次应用用户要求的优先级。
    scored.sort((first, second) {
      // 字数差为 0 的候选最优先，其他则差值越小越靠前。
      final byLength = first.lengthDifference.compareTo(
        second.lengthDifference,
      );
      // 长度差不同时已经可以确定顺序。
      if (byLength != 0) return byLength;
      // 同长度下编辑次数越少，外观越接近。
      final byDistance = first.editDistance.compareTo(second.editDistance);
      // 编辑距离不同时返回结果。
      if (byDistance != 0) return byDistance;
      // 公共开头越长越靠前，因此这里使用降序。
      final byPrefix = second.commonPrefix.compareTo(first.commonPrefix);
      // 公共前缀不同时返回结果。
      if (byPrefix != 0) return byPrefix;
      // 所有相似度都一样时保留首页词库原始顺序。
      return first.sourceIndex.compareTo(second.sourceIndex);
    });
    // 只返回排序后的文本值。
    return scored.map((item) => item.value).toList(growable: false);
  }

  ///
  /// 把英文候选项加入集合，同时执行去重和拼写形态校验。
  static void _addUniqueWordCandidate(
    Set<String> output,
    String candidate,
    String correct,
  ) {
    // 清理数据源可能带入的空格。
    final value = candidate.trim();
    // 空文本不可显示。
    if (value.isEmpty) return;
    // 正确答案不能以不同大小写再出现一次。
    if (value.toLowerCase() == correct.toLowerCase()) return;
    // 人工变体和词库单词都必须是可读的英文拼写形态。
    if (!_looksLikeEnglishWord(value)) return;
    // 大小写意义上重复的候选也必须排除。
    if (output.any((item) => item.toLowerCase() == value.toLowerCase())) return;
    // 通过全部检查后加入结果。
    output.add(value);
  }

  ///
  /// 检查字符串是否符合基本英文拼写形态。
  static bool _looksLikeEnglishWord(String value) {
    // 允许纯字母，以及 can't / well-known 这类中间带撗号或连字符的形态。
    final validCharacters = RegExp(
      r"^[A-Za-z]+(?:['-][A-Za-z]+)*$",
    ).hasMatch(value);
    // 包含其他符号、数字或连续分隔符时直接拒绝。
    if (!validCharacters) return false;
    // 三个完全相同字母连续出现通常是随机替换产生的无效形态。
    if (RegExp(r'([A-Za-z])\1\1', caseSensitive: false).hasMatch(value)) {
      return false;
    }
    // 通过基本形态检查。
    return true;
  }

  ///
  /// 返回从字符串中心逐渐扩展到两侧的下标顺序。
  static List<int> _centerFirstPositions(int length) {
    // 生成 0..length-1 的所有位置。
    final positions = List<int>.generate(length, (index) => index);
    // 中心使用小数，偶数长度时两个中间位置会等距。
    final center = (length - 1) / 2;
    // 按距离中心的绝对值升序。
    positions.sort((first, second) {
      // 计算第一个位置到中心的距离。
      final firstDistance = (first - center).abs();
      // 计算第二个位置到中心的距离。
      final secondDistance = (second - center).abs();
      // 距离不同时近的靠前。
      final byDistance = firstDistance.compareTo(secondDistance);
      // 距离相等时保持左侧先于右侧的稳定顺序。
      return byDistance != 0 ? byDistance : first.compareTo(second);
    });
    // 返回排好序的位置列表。
    return positions;
  }

  ///
  /// 按原字母的大小写形态返回替换字母。
  static String _matchCase(String replacement, String original) {
    // 原字母是大写时也把替换值转为大写。
    if (original == original.toUpperCase()) return replacement.toUpperCase();
    // 其他情况保持小写。
    return replacement.toLowerCase();
  }

  ///
  /// 计算两个字符串的 Levenshtein 编辑距离。
  static int _levenshteinDistance(String first, String second) {
    // 转为 Unicode 码点列表，中英文和扩展字符共用同一算法。
    final firstRunes = first.toLowerCase().runes.toList(growable: false);
    // 转换第二个文本。
    final secondRunes = second.toLowerCase().runes.toList(growable: false);
    // 上一行初始值表示把空字符串变成 second 前缀需要的插入次数。
    var previous = List<int>.generate(secondRunes.length + 1, (index) => index);
    // 逐个处理 first 的字符。
    for (var firstIndex = 0; firstIndex < firstRunes.length; firstIndex++) {
      // 当前行第一列表示删除 first 前缀的次数。
      final current = <int>[firstIndex + 1];
      // 逐个与 second 字符比较。
      for (
        var secondIndex = 0;
        secondIndex < secondRunes.length;
        secondIndex++
      ) {
        // 字符相同时替换成本为 0，不同时为 1。
        final replacementCost =
            firstRunes[firstIndex] == secondRunes[secondIndex] ? 0 : 1;
        // 从左侧格加一表示插入。
        final insertion = current[secondIndex] + 1;
        // 从上方格加一表示删除。
        final deletion = previous[secondIndex + 1] + 1;
        // 从左上格加成本表示保留或替换。
        final replacement = previous[secondIndex] + replacementCost;
        // 保存三种操作中的最小成本。
        current.add(
          insertion < deletion
              ? (insertion < replacement ? insertion : replacement)
              : (deletion < replacement ? deletion : replacement),
        );
      }
      // 当前行成为下一轮的上一行。
      previous = current;
    }
    // 右下角值就是两个完整字符串的最小编辑次数。
    return previous.last;
  }

  ///
  /// 计算两个文本从开头连续相同的 Unicode 字符数。
  static int _commonPrefixLength(String first, String second) {
    // 统一转小写后比较英文，中文不受影响。
    final firstRunes = first.toLowerCase().runes.toList(growable: false);
    // 转换第二个文本。
    final secondRunes = second.toLowerCase().runes.toList(growable: false);
    // 只需比较到较短文本的末尾。
    final limit = firstRunes.length < secondRunes.length
        ? firstRunes.length
        : secondRunes.length;
    // 从第一个字符开始逐个比较。
    for (var index = 0; index < limit; index++) {
      // 第一个不同位置的下标就是公共前缀长度。
      if (firstRunes[index] != secondRunes[index]) return index;
    }
    // 较短文本完全是公共前缀时返回 limit。
    return limit;
  }
}
