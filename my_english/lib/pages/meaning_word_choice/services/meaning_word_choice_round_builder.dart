// dart:math 提供 Random，用于随机抽取干扰词。
import 'dart:math';

// 引入单词模型，候选词与含义都从会话单词中派生。
import '../../../models/word.dart';

///
/// 看义选词的一道题：一个「去重后」的中文含义。
///
/// 一个含义可能在多个单词、多个词性下出现（例如 eat 的 vi. 吃 与 feed 的
/// vt. 吃），去重时按释义文本合并：词性汇总成数组，匹配单词汇总成 id 集合。
/// 所以这道题的正确答案可能不止一个，全选出来才算这一轮完成。
///
class MeaningWordChoiceRound {
  ///
  /// 创建一道看义选词小题。
  const MeaningWordChoiceRound({
    required this.meaningId,
    required this.definition,
    required this.posGroup,
    required this.matchIds,
  });

  ///
  /// 这道题在数据列表里的代表含义主键。
  ///
  /// 同一句中文可能属于多个单词，数据列表里只存其中一个作为代表；
  /// 写会话记录时用它，回放记录还原现场时也靠它对上号。
  final int meaningId;

  ///
  /// 去重后的中文释义文本（已去除首尾空白）。
  final String definition;

  ///
  /// 出现该释义的全部词性（小写，如 `vi.` / `vt.`），气泡里合并展示。
  final List<String> posGroup;

  ///
  /// 拥有该释义的全部单词主键（已去重），也就是本轮的全部正确答案。
  final List<int> matchIds;
}

///
/// 一轮候选词中的一个选项。
///
class MeaningWordChoiceCandidate {
  ///
  /// 创建一个候选词选项。
  const MeaningWordChoiceCandidate({
    required this.wordId,
    required this.isMatch,
  });

  ///
  /// 候选单词主键；从会话单词列表反查拼写。
  final int wordId;

  ///
  /// 是否当前含义的匹配词（正确答案）。
  final bool isMatch;
}

///
/// 看义选词的数据构建服务：含义序列与候选词，都不依赖任何 UI 状态。
///
/// 只做两件事：
/// 1. [buildRoundsFromMeaningIds]：把会话的数据列表还原成答题序列；
/// 2. [buildCandidates]：为某一轮生成候选词（匹配词 + 会话内干扰词）。
///
abstract final class MeaningWordChoiceRoundBuilder {
  ///
  /// 候选词默认数量；匹配词超过它时突破上限。
  static const int defaultCandidateCount = 4;

  ///
  /// 按会话的数据列表还原答题序列。
  ///
  /// 数据列表是一串**含义主键**，在开局时就已经按释义文本去重并打乱、写进数据库。
  /// 这里做的只是：按主键找回释义文本，再把「会话里所有拥有这句中文的单词」
  /// 汇总成这一轮的正确答案集合。
  ///
  /// 因为顺序来自数据库而不是当场打乱，中途退出再进来时题序完全一致——
  /// 1.x 那份「把整个题序也存进快照」的做法可以退休了。
  static List<MeaningWordChoiceRound> buildRoundsFromMeaningIds(
    List<int> meaningIds,
    List<Word> words,
  ) {
    // 先把会话词表摊平成「释义文本 → 词性集合 / 单词集合」。
    final posByDefinition = <String, Set<String>>{};
    final wordsByDefinition = <String, Set<int>>{};
    // 含义主键 → 它的释义文本。
    final definitionByMeaningId = <int, String>{};

    for (final word in words) {
      // 没有主键的临时单词无法作为答案，直接跳过。
      final wordId = word.id;
      if (wordId == null) continue;
      for (final meaning in word.allMeanings) {
        // 释义去首尾空白，空字符串不能成为一道题。
        final definition = meaning.definition.trim();
        if (definition.isEmpty) continue;
        // displayPos 统一成小写词性，空词性显示为星号，合并时自然去重。
        (posByDefinition[definition] ??= <String>{}).add(meaning.displayPos);
        (wordsByDefinition[definition] ??= <int>{}).add(wordId);
        if (meaning.id != null) definitionByMeaningId[meaning.id!] = definition;
      }
    }

    final rounds = <MeaningWordChoiceRound>[];
    for (final meaningId in meaningIds) {
      // 含义被删掉或所属单词已不在会话里时跳过这一轮，不让整局崩掉。
      final definition = definitionByMeaningId[meaningId];
      if (definition == null) continue;
      rounds.add(
        MeaningWordChoiceRound(
          meaningId: meaningId,
          definition: definition,
          // 词性按字典序保证展示稳定。
          posGroup: List<String>.unmodifiable(
            posByDefinition[definition]!.toList()..sort(),
          ),
          matchIds: List<int>.unmodifiable(wordsByDefinition[definition]!),
        ),
      );
    }
    return List<MeaningWordChoiceRound>.unmodifiable(rounds);
  }

  ///
  /// 为某一轮生成候选词。
  ///
  /// 规则：
  /// - 匹配词永远全部上阵（这是「允许超过四个」的唯一场景）；
  /// - 不够 [defaultCandidateCount] 个时，从会话单词中抽取「不含当前含义」的
  ///   单词做干扰词；会话里凑不齐时就少几个，不引入会话外的保底词
  ///   （那些词没有主键，无法被会话记录引用）。
  ///
  /// 候选顺序按**字母升序**（对应《数据结构》文档「单词候选词按字母升序」）。
  /// 位置由拼写决定而不是随机，所以中途退出再进来时候选区排列完全一致，
  /// 不必再为它单独存一份快照。
  static List<MeaningWordChoiceCandidate> buildCandidates({
    required MeaningWordChoiceRound round,
    required List<Word> words,
    Random? random,
  }) {
    final randomImpl = random ?? Random();
    final matchSet = round.matchIds.toSet();
    final spellings = <int, String>{
      for (final word in words)
        if (word.id != null) word.id!: word.spelling,
    };

    final chosen = <int>{...round.matchIds};
    if (chosen.length < defaultCandidateCount) {
      // 干扰词候选池：会话中不含当前含义、且不是匹配词本身的单词。
      final pool = <int>[
        for (final word in words)
          if (word.id != null &&
              !matchSet.contains(word.id) &&
              !_hasDefinition(word, round.definition))
            word.id!,
      ]..shuffle(randomImpl);
      for (final wordId in pool) {
        if (chosen.length >= defaultCandidateCount) break;
        chosen.add(wordId);
      }
    }

    // 按字母升序排列；拼写相同的不同单词用主键兜底，顺序唯一确定。
    final ordered = chosen.toList()
      ..sort((first, second) {
        final bySpelling = (spellings[first] ?? '').toLowerCase().compareTo(
          (spellings[second] ?? '').toLowerCase(),
        );
        return bySpelling != 0 ? bySpelling : first.compareTo(second);
      });

    return List<MeaningWordChoiceCandidate>.unmodifiable(
      <MeaningWordChoiceCandidate>[
        for (final wordId in ordered)
          MeaningWordChoiceCandidate(
            wordId: wordId,
            isMatch: matchSet.contains(wordId),
          ),
      ],
    );
  }

  ///
  /// 判断一个单词是否拥有指定释义文本（任一含义、任一词性下）。
  static bool _hasDefinition(Word word, String definition) {
    for (final meaning in word.allMeanings) {
      if (meaning.definition.trim() == definition) return true;
    }
    return false;
  }
}
