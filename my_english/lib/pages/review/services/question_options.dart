import '../../../models/meaning.dart';
import '../../../models/session.dart';
import '../../../models/session_question.dart';
import '../../../models/word.dart';
import '../../../store/session.dart';
import '../../../store/word.dart';
import '../../../services/study_open_timing.dart';
import '../../listening_meaning/services/listening_meaning_option_generator.dart';

/// 所有选择题使用同一份“来源混淆字段 → 题目混淆选项 → 固定排序”规则。
class QuestionOptions {
  QuestionOptions({
    required this.session,
    required this.store,
    WordStore? wordStore,
    List<Word>? corpusWords,
  }) : _corpus = corpusWords,
       wordStore = wordStore ?? LocalWordStore.instance,
       _words = <int, Word>{
         for (final word in session.snapshotWords) word.id!: word,
       };
  final Session session;
  final SessionStore store;
  final WordStore wordStore;
  final Map<int, Word> _words;
  final Map<int, List<String>> _cache = {};
  final Map<int, Future<List<String>>> _inflight = {};

  List<String>? cached(SessionSubQuestion question) =>
      _cache[question.id] ??
      (question.distractors != null && question.options.length == 4
          ? question.options
          : null);

  /// 预取和当前题共用同一个请求，避免同一题生成两版候选、重复写库。
  Future<List<String>> load(
    SessionSubQuestion question, {
    bool refresh = false,
  }) {
    if (!refresh) {
      final ready = cached(question);
      if (ready != null) return Future.value(ready);
      final pending = _inflight[question.id];
      if (pending != null) return pending;
    }
    final request = _load(question, refresh: refresh);
    if (!refresh) {
      _inflight[question.id] = request;
      void clear() {
        if (identical(_inflight[question.id], request)) {
          _inflight.remove(question.id);
        }
      }

      request.then<void>(
        (_) => clear(),
        onError: (Object _, StackTrace _) => clear(),
      );
    }
    return request;
  }

  List<Word>? _corpus;

  Future<List<String>> _load(
    SessionSubQuestion question, {
    bool refresh = false,
  }) async {
    final candidateTiming = StudyOpenTiming.of(session);
    final timing = candidateTiming?.tracksQuestion(question.id) == true
        ? candidateTiming
        : null;
    timing?.mark('options_prepare_started');
    final english = question.answerType == 1;
    if (!refresh && _cache[question.id] != null) return _cache[question.id]!;
    if (!refresh &&
        question.distractors != null &&
        question.options.length == 4) {
      return _cache[question.id] = question.options;
    }
    if (_corpus == null) {
      // 题目快照始终可用；全词库只用于寻找干扰，不会替换已开局的单词或含义。
      try {
        _corpus = await wordStore.getAll();
      } catch (_) {
        _corpus = _words.values.toList();
      }
    }
    final correct = question.answers;
    String key(String text) =>
        english ? text.trim().toLowerCase() : text.trim();
    final forbidden = correct.map(key).toSet();
    final current = _cache[question.id] ?? question.options;
    final refreshExcluded = refresh
        ? current
              .where((text) => !forbidden.contains(key(text)))
              .map(key)
              .toSet()
        : <String>{};
    final targetWords = question.wordIds.map((id) => _words[id]!).toList();
    if (english && question.contentType == 2) {
      // 别的批次、别的词库中同样具有这个含义的词，都不能变成错误选项。
      for (final word in <Word>[..._corpus!, ..._words.values]) {
        if (word.rawMeanings.any(
          (meaning) =>
              meaning.definition.trim() == question.content.first.trim(),
        )) {
          forbidden.add(key(word.spelling));
        }
      }
    }
    final ownDefinitions = <String>{
      for (final word in targetWords)
        for (final meaning in word.rawMeanings) meaning.definition.trim(),
    };
    bool allowed(String text) {
      final value = key(text);
      if (value.isEmpty ||
          forbidden.contains(value) ||
          refreshExcluded.contains(value)) {
        return false;
      }
      if (!english) {
        if (ownDefinitions.contains(value)) return false;
        if (correct.any(
          (answer) => answer.contains(value) || value.contains(answer),
        )) {
          return false;
        }
      }
      return true;
    }

    final needed = 4 - correct.length;
    final pool = <String, String>{};
    final sources = <Map<String, Object?>>[];
    for (final word in targetWords) {
      if (english) {
        final live = _corpus!
            .where(
              (entry) => entry.id == word.id && entry.spelling == word.spelling,
            )
            .firstOrNull;
        final cached = word.confusions.isNotEmpty
            ? word.confusions
            : live?.confusions ?? const <String>[];
        final source = <String>{...cached.where(allowed)};
        if (source.length < needed || refresh) {
          source.addAll(
            ListeningMeaningOptionGenerator.buildWordDistractors(
              correct: word.spelling,
              sourceWords: _corpus!,
              count: 64,
            ).where(allowed),
          );
        }
        final values = sortQuestionOptions(
          source,
          english: true,
        ).take(needed > 3 ? needed : 3).toList();
        for (final value in values) {
          pool.putIfAbsent(key(value), () => value);
        }
        sources.add({
          'word_id': word.id,
          'meaning_id': null,
          'confusions': values,
        });
      } else {
        final meanings = word.rawMeanings.where(
          (meaning) =>
              question.details.any((detail) => detail.meaningId == meaning.id),
        );
        for (final meaning in meanings) {
          final live = _corpus!
              .where(
                (entry) =>
                    entry.id == word.id && entry.spelling == word.spelling,
              )
              .firstOrNull;
          final liveMeaning = live?.rawMeanings
              .where(
                (entry) =>
                    entry.id == meaning.id &&
                    entry.definition == meaning.definition,
              )
              .firstOrNull;
          final cached = meaning.confusions.isNotEmpty
              ? meaning.confusions
              : liveMeaning?.confusions ?? const <String>[];
          final source = <String>{...cached.where(allowed)};
          if (source.length < needed || refresh) {
            source.addAll(
              ListeningMeaningOptionGenerator.buildDefinitionDistractors(
                correct: meaning.definition,
                sourceWords: _corpus!,
                count: 3,
                excludeDefinitions: ownDefinitions,
              ).where(allowed),
            );
          }
          // 新词库也保持四个按钮；备用释义同样写入来源字段，之后直接复用。
          if (source.length < needed) {
            source.addAll(_definitionFallback.where(allowed));
          }
          final values = source.take(3).toList();
          for (final value in values) {
            pool.putIfAbsent(key(value), () => value);
          }
          sources.add({
            'word_id': word.id,
            'meaning_id': meaning.id,
            'confusions': values,
          });
        }
      }
    }
    final distractors = pool.values.take(needed).toList();
    if (distractors.length != needed) {
      throw StateError('无法生成四个不同的候选，请检查这个词的混淆内容');
    }
    timing?.mark('options_generated');
    Future<void> save() => store.saveQuestionDistractors(
      sessionId: session.id,
      questionId: question.id,
      distractors: distractors,
      sources: sources,
    );
    await (timing == null ? save() : timing.run(save));
    timing?.mark('options_saved');
    // 写入成功后再更新内存；写入失败不会被误当成永久缓存。
    for (final source in sources) {
      final wordId = source['word_id']! as int;
      final word = _words[wordId]!;
      final meaningId = source['meaning_id'] as int?;
      final values = source['confusions']! as List<String>;
      _words[wordId] = meaningId == null
          ? word.withConfusions(values)
          : word.copyWith(
              meanings: <Meaning>[
                for (final meaning in word.rawMeanings)
                  if (meaning.id != meaningId)
                    meaning
                  else
                    Meaning(
                      id: meaning.id,
                      wordId: meaning.wordId,
                      pos: meaning.pos,
                      subPos: meaning.subPos,
                      definition: meaning.definition,
                      confusions: values,
                      sort: meaning.sort,
                    ),
              ],
            );
    }
    return _cache[question.id] = sortQuestionOptions(<String>[
      ...correct,
      ...distractors,
    ], english: english);
  }

  static const _definitionFallback = <String>[
    '旅行',
    '机器',
    '颜色',
    '条件',
    '价格',
    '方向',
    '昨天',
    '音乐',
    '速度',
    '结果',
    '空气',
    '街道',
    '季节',
    '数字',
    '声音',
    '变化',
    '方法',
    '关系',
    '温度',
    '位置',
    '尺寸',
    '时间',
    '距离',
    '河流',
    '材料',
    '故事',
    '问题',
    '花园',
    '食物',
    '衣服',
    '窗户',
    '天气',
    '朋友',
    '山峰',
    '灯光',
    '交通',
  ];
}
