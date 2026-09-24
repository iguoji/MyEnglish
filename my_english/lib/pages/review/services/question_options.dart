import 'dart:math';

import '../../../models/session.dart';
import '../../../models/session_question.dart';
import '../../../models/word.dart';
import '../../../store/session.dart';
import '../../../store/word.dart';
import '../../../services/study_open_timing.dart';
import 'distractor_planner.dart';

/// 选择题的四个候选：直接读开局时定好的内容和顺序，缺了才按同一套规则补。
///
/// 新开的局在开局时就给每道选择题挑好了混淆项、排好了顺序并存进会话
/// （见 [DistractorPlanner.planPaper]），这里原样读出，恢复会话时一模一样。
/// 旧版本开的、还没出到的题没有混淆项，才在第一次出现时补上并保存。
///
/// 混淆项只属于这一局：不写回单词和含义，下一局重新挑；也不提供刷新替换。
class QuestionOptions {
  QuestionOptions({
    required this.session,
    required this.store,
    WordStore? wordStore,
    List<Word>? corpusWords,
  }) : _corpus = corpusWords,
       wordStore = wordStore ?? LocalWordStore.instance;
  final Session session;
  final SessionStore store;
  final WordStore wordStore;
  final Map<int, List<String>> _cache = {};
  final Map<int, Future<List<String>>> _inflight = {};

  /// 已经挑好、但可能还没保存成功的结果；保存失败重试时沿用同一份，不重复记账。
  final Map<int, PlannedOptions> _planned = {};
  List<Word>? _corpus;
  Future<DistractorPlanner>? _planner;

  /// 已经定好的候选；还没有时返回 null，由 [load] 补上。
  List<String>? cached(SessionSubQuestion question) =>
      _cache[question.id] ?? question.presetOptions;

  /// 预取和当前题共用同一个请求，避免同一题生成两版候选、重复写库。
  Future<List<String>> load(SessionSubQuestion question) {
    final ready = cached(question);
    if (ready != null) return Future.value(ready);
    final pending = _inflight[question.id];
    if (pending != null) return pending;
    final request = _create(question);
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
    return request;
  }

  /// 给还没有混淆项的题挑选、排序并保存。
  Future<List<String>> _create(SessionSubQuestion question) async {
    final candidateTiming = StudyOpenTiming.of(session);
    final timing = candidateTiming?.tracksQuestion(question.id) == true
        ? candidateTiming
        : null;
    timing?.mark('options_prepare_started');
    final planner = await (_planner ??= _createPlanner());
    final planned =
        _planned[question.id] ??
        planner.plan(DistractorQuestion.fromSubQuestion(question));
    if (planned == null) {
      throw StateError('无法生成四个不同的候选，请检查这个词的混淆内容');
    }
    _planned[question.id] = planned;
    timing?.mark('options_generated');
    Future<void> save() => store.saveQuestionDistractors(
      sessionId: session.id,
      questionId: question.id,
      distractors: planned.distractors,
      options: planned.options,
    );
    await (timing == null ? save() : timing.run(save));
    timing?.mark('options_saved');
    // 写入成功后再放进缓存；写入失败不会被误当成已经定好的候选。
    return _cache[question.id] = planned.options;
  }

  /// 按本局已经出过的题记好账，保证补出来的题同样不重复、位置同样均匀。
  Future<DistractorPlanner> _createPlanner() async {
    final corpus = _corpus ??= await _loadCorpus();
    final planner = DistractorPlanner(
      sessionWords: session.snapshotWords,
      corpus: corpus,
      // 同一局每次补出来的结果一致，方便排查。
      random: Random(session.id),
    );
    for (final question in session.questions) {
      if (question.type != 100 && question.type != 200) continue;
      final distractors = question.distractors;
      if (distractors == null) continue;
      planner.remember(
        english: question.answerType == 1,
        answers: question.answers,
        distractors: distractors,
        options: question.presetOptions,
      );
    }
    return planner;
  }

  /// 全局词库只用来挑混淆项，不会替换已开局的单词或含义；读不到时退回本局单词。
  Future<List<Word>> _loadCorpus() async {
    try {
      return await wordStore.getAll();
    } catch (_) {
      return session.snapshotWords;
    }
  }
}
