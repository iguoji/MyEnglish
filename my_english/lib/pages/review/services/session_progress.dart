import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../models/session.dart';
import '../../../models/session_question.dart';
import '../../../models/session_record.dart';
import '../../../models/settlement.dart';
import '../../../models/word.dart';
import '../../../store/session.dart';
import 'question_options.dart';

/// 四种答题页面共用的会话控制器：排队保存、当前遍次、题目用时与统一结算。
/// 随身听的清单和播放进度由 SettingsStore 独立保存。
class SessionProgress with WidgetsBindingObserver {
  SessionProgress({
    required this.store,
    required Session session,
    required this.records,
    List<Word>? corpusWords,
  }) : _session = session,
       _liveRecords = List<SessionRecord>.of(records),
       _options = QuestionOptions(
         session: session,
         store: store,
         corpusWords: corpusWords,
       ) {
    _elapsed = session.elapsed;
    _indexSession();
    WidgetsBinding.instance.addObserver(this);
  }

  final SessionStore store;
  Session _session;
  Session get session => _session;
  final List<SessionRecord> records;
  final List<SessionRecord> _liveRecords;
  final QuestionOptions _options;
  Future<void> _queue = Future<void>.value();
  final Map<int, SettlementDraft> _drafts = {};
  final Map<int, int> _usedSeconds = {};
  final Set<int> _dirtyTimes = {};
  final Map<int, SessionSubQuestion> _questionsById = {};
  final Map<int, SessionSubQuestion> _nextQuestions = {};
  final Map<(int, int?), SessionSubQuestion> _questionsByTarget = {};
  final Map<int, List<SessionRecord>> _recordsByQuestion = {};
  final Map<int, List<SessionRecord>> _recordsByWord = {};
  final Set<int> _recordIds = {};
  (int, int)? _lastQueuedProgress;

  /// 题号索引每次开局/重试只建一次，答题时不反复展开整张试卷。
  void _indexSession() {
    _questionsById.clear();
    _nextQuestions.clear();
    _questionsByTarget.clear();
    _usedSeconds.clear();
    _dirtyTimes.clear();
    _lastQueuedProgress = null;
    SessionSubQuestion? previous;
    for (final q in session.questions) {
      if (previous != null) _nextQuestions[previous.id] = q;
      previous = q;
      _questionsById[q.id] = q;
      if (q.usedSeconds > 0) _usedSeconds[q.id] = q.usedSeconds;
      for (final detail in q.details) {
        _questionsByTarget.putIfAbsent((
          detail.wordId,
          detail.meaningId,
        ), () => q);
      }
    }
    _recordsByQuestion.clear();
    _recordsByWord.clear();
    _recordIds.clear();
    for (final record in _liveRecords) {
      _indexRecord(record);
    }
  }

  void _indexRecord(SessionRecord record) {
    _recordIds.add(record.id);
    if (record.questionId != null) {
      (_recordsByQuestion[record.questionId!] ??= []).add(record);
    }
    for (final wordId in <int>{record.wordId, ...record.targetWordIds}) {
      (_recordsByWord[wordId] ??= []).add(record);
    }
  }

  final Stopwatch _questionClock = Stopwatch();
  int? _timedQuestion;
  int _elapsed = 0;
  bool _timingAllowed = false;
  bool _readyForSettlement = false;
  bool _committed = false;
  Future<void>? _pendingCommit;
  int _pendingAdjustments = 0;
  bool _detached = false;

  ReviewModule get module => session.module;
  bool get updatesReviewedAt => session.updatesReviewedAt;
  WordProgress progressOf(int wordId) =>
      WordProgress.fromRecords(_recordsByWord[wordId] ?? const [], wordId);
  List<SessionRecord> get allRecords =>
      List<SessionRecord>.unmodifiable(_liveRecords);
  List<SettlementDraft> get settlementDrafts =>
      List<SettlementDraft>.unmodifiable(_drafts.values);
  SettlementDraft? settlementFor(int wordId) => _drafts[wordId];
  int get wrongCount =>
      _liveRecords.where((record) => !record.isCorrect).length;

  SessionSubQuestion? questionFor({
    int? wordId,
    int? meaningId,
    int? questionId,
  }) {
    if (questionId != null) return _questionsById[questionId];
    return _questionsByTarget[(wordId, meaningId)];
  }

  /// 候选成功保存后才启用答题；数据加载时间不计入小题答题用时。
  Future<List<String>> optionsFor(SessionSubQuestion question) async {
    final result = await _options.load(question);
    activateQuestion(question.id);
    final next = _nextQuestions[question.id];
    if (next != null && (next.type == 100 || next.type == 200)) {
      unawaited(
        Future<void>.delayed(Duration.zero, () async {
          if (_detached) return;
          try {
            await _options.load(next);
          } catch (_) {
            /* 真正进入这题时仍可重试并说明错误。 */
          }
        }),
      );
    }
    return result;
  }

  List<String>? cachedOptionsFor(SessionSubQuestion question) =>
      _options.cached(question);

  void activateQuestion(int questionId) {
    if (_timedQuestion == questionId && _timingAllowed) return;
    _captureTime();
    _timedQuestion = questionId;
    _timingAllowed = true;
    _questionClock
      ..reset()
      ..start();
  }

  void pauseQuestion() {
    _captureTime();
    _timingAllowed = false;
    _questionClock.stop();
  }

  void _captureTime() {
    final id = _timedQuestion;
    if (id == null) return;
    final wholeSeconds = _questionClock.elapsed.inSeconds;
    if (wholeSeconds > 0) {
      _usedSeconds[id] = (_usedSeconds[id] ?? 0) + wholeSeconds;
      _dirtyTimes.add(id);
      final running = _questionClock.isRunning;
      _questionClock.reset();
      if (running) _questionClock.start();
    }
  }

  Future<void> save({required int cursor, required int elapsed}) {
    if (_committed) return Future<void>.value();
    _elapsed = elapsed;
    _captureTime();
    final sessionId = session.id;
    final marker = (cursor, elapsed);
    if (_dirtyTimes.isEmpty && _lastQueuedProgress == marker) {
      return Future<void>.value();
    }
    final times = <int, int>{
      for (final id in _dirtyTimes) id: _usedSeconds[id]!,
    };
    _dirtyTimes.removeAll(times.keys);
    _lastQueuedProgress = marker;
    return _enqueue(() async {
      try {
        await store.updateProgress(
          sessionId: sessionId,
          cursor: cursor,
          elapsed: elapsed,
          questionTimes: times,
        );
      } catch (_) {
        _dirtyTimes.addAll(times.keys);
        if (_lastQueuedProgress == marker) _lastQueuedProgress = null;
        rethrow;
      }
    });
  }

  Future<void> record({
    required int wordId,
    int? meaningId,
    int? questionId,
    required String input,
    required bool isCorrect,
    int? elapsed,
  }) {
    if (_committed || !module.writesRecords) return Future<void>.value();
    final question = questionFor(
      wordId: wordId,
      meaningId: meaningId,
      questionId: questionId,
    );
    if (question == null) return Future<void>.error(StateError('没有找到本次作答的小题'));
    if (elapsed != null && elapsed > _elapsed) _elapsed = elapsed;
    _captureTime();
    final used = _usedSeconds[question.id] ?? question.usedSeconds;
    final selected = <String>{
      for (final record
          in _recordsByQuestion[question.id] ?? const <SessionRecord>[])
        if (record.isCorrect)
          ...record.answers.map((text) => text.trim().toLowerCase()),
      if (isCorrect) input.trim().toLowerCase(),
    };
    final complete =
        isCorrect &&
        (question.type != 200 ||
            question.answers.every(
              (text) => selected.contains(text.trim().toLowerCase()),
            ));
    if (complete) {
      _timingAllowed = false;
      _questionClock.stop();
    }
    return _enqueue(() async {
      final record = await store.submitAnswer(
        sessionId: session.id,
        questionId: question.id,
        answers: <String>[input],
        elapsed: _elapsed,
        usedSeconds: used,
      );
      if (record.isCorrect != isCorrect) {
        throw StateError('题目答案与页面判断不一致，请重新进入本局');
      }
      if (!_recordIds.contains(record.id)) {
        _liveRecords.add(record);
        _indexRecord(record);
      }
      if (_usedSeconds[question.id] == used) _dirtyTimes.remove(question.id);
      for (final id in question.wordIds) {
        _drafts.remove(id);
      }
    });
  }

  Future<void> retryWord(int wordId) => _enqueue(() async {
    final group = session.groups.firstWhere(
      (group) => group.questions.any((q) => q.wordIds.contains(wordId)),
    );
    _session = await store.retryGroup(session.id, group.id);
    _liveRecords
      ..clear()
      ..addAll(_session.records);
    _indexSession();
    _drafts.remove(wordId);
    _timedQuestion = null;
    _timingAllowed = false;
    _questionClock
      ..stop()
      ..reset();
  });

  /// 单词结果和实际用时统一从已保存的小题读取，不使用页面停留的墙上时间。
  Future<SettleResult?> settle(int wordId) async {
    if (_committed || !module.writesRecords) return null;
    SettleResult? result;
    await _enqueue(() async {
      result = await store.prepareSettlement(
        sessionId: session.id,
        wordId: wordId,
      );
      final prepared = result!;
      _drafts[wordId] = SettlementDraft(
        sessionId: session.id,
        wordId: wordId,
        isCorrect: prepared.isCorrect,
        streak: prepared.streak,
        difficultyBefore: prepared.difficultyBefore,
        suggestedAdjustment:
            prepared.suggestedAdjustment ?? prepared.difficultyDelta,
        adjustment: prepared.adjustment ?? prepared.difficultyDelta,
        manual: prepared.manual,
        usedTimeSeconds: prepared.usedTimeSeconds,
        recentResults: prepared.recentResults,
      );
    });
    return result;
  }

  /// 调整成功后才更新草稿；保存期间禁止离开，避免把未确认的旧值落实。
  Future<void> adjustSettlement(int wordId, DifficultyAdjust adjust) {
    if (_committed || _pendingCommit != null) {
      return Future<void>.error(StateError('结算正在提交或已经提交，不能再调整'));
    }
    _pendingAdjustments++;
    return _enqueue(() async {
      final current = _drafts[wordId];
      if (current == null) throw StateError('没有找到这个单词的结算草稿');
      final next = current.copyWithAdjust(adjust);
      await store.updateSettlementDraft(
        sessionId: session.id,
        wordId: wordId,
        difficultyAfter: next.difficultyAfter,
        adjustment: next.adjustment,
        operation: 2,
      );
      _drafts[wordId] = next;
    }).whenComplete(() {
      _pendingAdjustments--;
    });
  }

  /// 完成整张试卷即为完成；是否全对只影响逐词结算，不能把整局记成失败。
  Future<void> finish({int? cursor, int? elapsed}) => _enqueue(() async {
    if (_readyForSettlement || _committed) return;
    _captureTime();
    _questionClock.stop();
    _timingAllowed = false;
    await store.finishSession(
      sessionId: session.id,
      status: SessionStatus.completed,
      cursor: cursor,
      elapsed: elapsed,
      pendingSettlement: module.writesRecords,
    );
    if (module.writesRecords) {
      final drafts = await store.getSettlementDrafts(session.id);
      _drafts
        ..clear()
        ..addEntries(drafts.map((draft) => MapEntry(draft.wordId, draft)));
    }
    _readyForSettlement = true;
  });

  Future<void> commitSettlement() {
    if (_committed || !module.writesRecords) return Future<void>.value();
    if (_pendingAdjustments > 0) {
      return Future<void>.error(StateError('难度调整正在保存，请稍候'));
    }
    // 连续点击必须共享真正的提交结果，不能返回会吞掉错误的队列尾部。
    final pending = _pendingCommit;
    if (pending != null) return pending;
    final commit =
        _enqueue(() async {
          if (!_readyForSettlement) throw StateError('本局尚未完成保存，请重试');
          await store.finalizeSessionSettlement(session.id);
          _committed = true;
        }).whenComplete(() {
          _pendingCommit = null;
        });
    _pendingCommit = commit;
    return commit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _timingAllowed && !_detached) {
      _questionClock.start();
    } else {
      _captureTime();
      _questionClock.stop();
    }
  }

  /// 页面销毁时解绑，不让已经关闭的一局继续监听前后台变化。
  void detach() {
    if (_detached) return;
    _detached = true;
    _captureTime();
    _questionClock.stop();
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }
}
