// dart:math 提供 Random，用于打乱含义顺序与候选词位置。
import 'dart:math';

// 引入单词模型，候选词与含义都从会话单词中派生。
import '../../../models/word.dart';

///
/// 看义选词的一道题：一个「去重后」的中文含义。
///
/// 一个含义可能在多个单词、多个词性下出现（例如 eat 的 vi. 吃 与 feed 的
/// vt. 吃），去重时按释义文本合并：词性汇总成数组，匹配单词汇总成 id 集合。
///
class MeaningWordChoiceRound {
  ///
  /// 创建一道看义选词小题。
  const MeaningWordChoiceRound({
    required this.definition,
    required this.posGroup,
    required this.matchIds,
  });

  ///
  /// 去重后的中文释义文本（已去除首尾空白）。
  final String definition;

  ///
  /// 出现该释义的全部词性（小写，如 `vi.` / `vt.`），气泡里合并展示。
  final List<String> posGroup;

  ///
  /// 拥有该释义的全部单词主键（已去重），也就是本轮的全部正确答案。
  final List<int> matchIds;

  ///
  /// 转成会话快照可保存的 Map。
  Map<String, Object?> toJson() => <String, Object?>{
    'def': definition,
    'pos': posGroup,
    'matchIds': matchIds,
  };

  ///
  /// 从会话快照 Map 恢复；损坏字段一律跳过，保证续玩不崩。
  factory MeaningWordChoiceRound.fromJson(Map<Object?, Object?> map) {
    final definition = map['def']?.toString() ?? '';
    final posGroup = <String>[
      if (map['pos'] is List)
        for (final item in map['pos']! as List)
          if (item is String && item.isNotEmpty) item,
    ];
    final matchIds = <int>[
      if (map['matchIds'] is List)
        for (final item in map['matchIds']! as List)
          if (item is num) item.toInt(),
    ];
    return MeaningWordChoiceRound(
      definition: definition,
      posGroup: List<String>.unmodifiable(posGroup),
      matchIds: List<int>.unmodifiable(matchIds),
    );
  }
}

///
/// 一轮候选词中的一个选项。
///
/// [isMatch] 表示它是否包含当前含义（正确答案）；恢复快照时同样需要，
/// 因此一并持久化。
///
class MeaningWordChoiceCandidate {
  ///
  /// 创建一个候选词选项。
  const MeaningWordChoiceCandidate({required this.wordId, required this.isMatch});

  ///
  /// 候选单词主键；从会话单词列表反查拼写。
  final int wordId;

  ///
  /// 是否当前含义的匹配词。
  final bool isMatch;

  ///
  /// 转成会话快照可保存的 Map。
  Map<String, Object?> toJson() => <String, Object?>{
    'wordId': wordId,
    'isMatch': isMatch,
  };

  ///
  /// 从会话快照 Map 恢复；无法识别时返回 null 由调用方丢弃。
  static MeaningWordChoiceCandidate? fromJson(Map<Object?, Object?> map) {
    final rawId = map['wordId'];
    if (rawId is! num) return null;
    return MeaningWordChoiceCandidate(
      wordId: rawId.toInt(),
      isMatch: map['isMatch'] == true,
    );
  }
}

///
/// 看义选词的数据构建服务：含义序列与候选词，都不依赖任何 UI 状态。
///
/// 只做两件事：
/// 1. [buildRounds]：把会话单词的全部含义去重、合并词性、全局打乱，得到答题序列；
/// 2. [buildCandidates]：为某一轮生成候选词（匹配词 + 会话内干扰词）。
///
abstract final class MeaningWordChoiceRoundBuilder {
  ///
  /// 候选词默认数量；匹配词超过它时突破上限。
  static const int defaultCandidateCount = 4;

  ///
  /// 构建答题序列：遍历 → 文本去重 → 词性合并 → 全局打乱。
  ///
  /// 用 [random] 打乱，便于测试注入固定随机源。
  static List<MeaningWordChoiceRound> buildRounds(
    List<Word> words, {
    Random? random,
  }) {
    final randomImpl = random ?? Random();
    // 释义文本 → 出现它的词性集合。
    final posByDefinition = <String, Set<String>>{};
    // 释义文本 → 拥有它的单词主键集合。
    final wordsByDefinition = <String, Set<int>>{};

    // 第一遍遍历：把全部含义摊平成「文本 → 词性集合 / 单词集合」。
    for (final word in words) {
      // 没有主键的临时单词无法被快照引用，直接跳过。
      final wordId = word.id;
      if (wordId == null) continue;
      for (final meaning in word.meanings) {
        // displayPos 统一成小写词性，空词性显示为星号，合并时自然去重。
        final pos = meaning.displayPos;
        for (final rawDefinition in meaning.definitions) {
          // 释义去首尾空白，空字符串不能成为一道题。
          final definition = rawDefinition.trim();
          if (definition.isEmpty) continue;
          (posByDefinition[definition] ??= <String>{}).add(pos);
          (wordsByDefinition[definition] ??= <int>{}).add(wordId);
        }
      }
    }

    // 第二遍：把合并结果转成有序的小题列表，词性按字典序保证展示稳定。
    final rounds = <MeaningWordChoiceRound>[
      for (final entry in wordsByDefinition.entries)
        MeaningWordChoiceRound(
          definition: entry.key,
          posGroup: List<String>.unmodifiable(
            posByDefinition[entry.key]!.toList()..sort(),
          ),
          matchIds: List<int>.unmodifiable(entry.value),
        ),
    ];

    // 全局打乱：同一个多义词的多个含义被拆散到全程，避免连续考同一个词。
    rounds.shuffle(randomImpl);
    return List<MeaningWordChoiceRound>.unmodifiable(rounds);
  }

  ///
  /// 为某一轮生成候选词。
  ///
  /// 规则：
  /// - 匹配词数量 ≥ 默认候选数时，候选词 = 全部匹配词（突破 4 个上限）；
  /// - 否则从会话单词中随机抽取「不含当前含义」的单词做干扰词，
  ///   凑到 [defaultCandidateCount] 个；会话里凑不齐时就少几个，
  ///   不引入会话外的保底词（保底词没有主键，无法被快照恢复引用）。
  ///
  static List<MeaningWordChoiceCandidate> buildCandidates({
    required MeaningWordChoiceRound round,
    required List<Word> words,
    Random? random,
  }) {
    final randomImpl = random ?? Random();
    // 匹配词先拷贝出来再打乱，保证候选区内位置随机。
    final matches = <int>[...round.matchIds]..shuffle(randomImpl);

    // 匹配词足够多时直接全部上阵，这是「允许超过四个」的唯一场景。
    if (matches.length >= defaultCandidateCount) {
      return List<MeaningWordChoiceCandidate>.unmodifiable(<
        MeaningWordChoiceCandidate
      >[
        for (final wordId in matches)
          MeaningWordChoiceCandidate(wordId: wordId, isMatch: true),
      ]);
    }

    // 干扰词候选池：会话中不含当前含义、且不是匹配词本身的单词。
    final matchSet = round.matchIds.toSet();
    final distractorPool = <int>[
      for (final word in words)
        if (word.id != null &&
            !matchSet.contains(word.id) &&
            !_hasDefinition(word, round.definition))
          word.id!,
    ]..shuffle(randomImpl);

    // 需要补的干扰词数量，取「目标数量减匹配词数」与池子大小的较小值。
    final needed = defaultCandidateCount - matches.length;
    final distractors = distractorPool.take(needed).toList();

    // 匹配词与干扰词合并后整体打乱，正确答案位置不固定。
    final candidates = <MeaningWordChoiceCandidate>[
      for (final wordId in matches)
        MeaningWordChoiceCandidate(wordId: wordId, isMatch: true),
      for (final wordId in distractors)
        MeaningWordChoiceCandidate(wordId: wordId, isMatch: false),
    ]..shuffle(randomImpl);

    return List<MeaningWordChoiceCandidate>.unmodifiable(candidates);
  }

  ///
  /// 判断一个单词是否拥有指定释义文本（任一含义、任一词性下）。
  static bool _hasDefinition(Word word, String definition) {
    for (final meaning in word.meanings) {
      for (final rawDefinition in meaning.definitions) {
        if (rawDefinition.trim() == definition) return true;
      }
    }
    return false;
  }
}
