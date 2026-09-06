import 'dart:async';

import '../../../models/session.dart';
import '../../../models/session_record.dart';
import '../../../store/session.dart';

///
/// 一局答题的「进度出口」。
///
/// 页面只管组装自己的状态，落盘的顺序、串行化和结算规则都由它负责。
///
/// 1.x 时代这里要区分「长期练习」和「今日任务」两套存储，所以是个抽象接口；
/// 2.0 起所有模块的所有局都住在同一张会话表里，于是收敛成一个普通类。
///
/// **写入是串行的**：进度保存可能被高频触发（每答一题、每滴答一秒），
/// 并发写同一行会让后发的旧值覆盖先到的新值。这里用一条 Future 链把所有
/// 写入排成队，保证磁盘上的顺序和调用顺序一致。
///
class SessionProgress {
  ///
  /// 创建一个进度出口。
  SessionProgress({
    required this.store,
    required this.session,
    required this.records,
  });

  ///
  /// 底层会话 Store。
  final SessionStore store;

  ///
  /// 当前这一局。
  final Session session;

  ///
  /// 进入页面时已经存在的点击记录，用来还原现场。
  final List<SessionRecord> records;

  ///
  /// 串行写入队列；null 表示当前没有排队中的写入。
  Future<void> _queue = Future<void>.value();

  ///
  /// 已经结算过的单词，避免同一个词在一局里被重复结算。
  final Set<int> _settled = <int>{};

  ///
  /// 这一局是否已经收尾；收尾后所有写入一律忽略。
  bool _finished = false;

  ///
  /// 本局的模块。
  ReviewModule get module => session.module;

  ///
  /// 这一局答题时是否需要推进单词的复习时间。
  bool get updatesReviewedAt => session.updatesReviewedAt;

  ///
  /// 某个单词在本局的现场：做到哪了、点错过哪些候选。
  WordProgress progressOf(int wordId) =>
      WordProgress.fromRecords(_liveRecords, wordId);

  ///
  /// 本局已经产生的全部记录（含进入页面后新写的）。
  List<SessionRecord> get allRecords =>
      List<SessionRecord>.unmodifiable(_liveRecords);

  ///
  /// 记录列表的可变副本：新写的记录会追加进来，让现场查询立刻反映最新状态。
  late final List<SessionRecord> _liveRecords = List<SessionRecord>.of(records);

  ///
  /// 本局累计错误次数，由记录直接数出来。
  int get wrongCount =>
      _liveRecords.where((record) => !record.isCorrect).length;

  ///
  /// 保存进度：做到第几条、已经花了多少秒。
  Future<void> save({required int cursor, required int elapsed}) {
    // 已经收尾的局不再接受进度写入，避免结算后又被旧的定时器覆盖回去。
    if (_finished) return Future<void>.value();
    return _enqueue(
      () => store.updateProgress(
        sessionId: session.id,
        cursor: cursor,
        elapsed: elapsed,
      ),
    );
  }

  ///
  /// 记一次点击，不论对错。
  ///
  /// [meaningId] 为空表示这一步针对整个单词（听音辨义的「选拼写」）。
  /// [input] 是用户实际点的那个候选词，或者拼错的完整单词。
  ///
  /// 随身听没有对错可言，调用会被直接忽略——若也写记录，
  /// 首页的复习数字和打卡热力图会被「只是听了一遍」灌水。
  Future<void> record({
    required int wordId,
    int? meaningId,
    required String input,
    required bool isCorrect,
  }) {
    if (_finished || !module.writesRecords) return Future<void>.value();
    // 先在内存里补一条，让紧接着的现场查询立刻看到这次点击；
    // id 用负数占位，它只在内存里用于计数，不会写进数据库。
    _liveRecords.add(
      SessionRecord(
        id: -_liveRecords.length - 1,
        wordId: wordId,
        meaningId: meaningId,
        input: input,
        isCorrect: isCorrect,
      ),
    );
    return _enqueue(
      () => store.addRecord(
        sessionId: session.id,
        wordId: wordId,
        meaningId: meaningId,
        input: input,
        isCorrect: isCorrect,
      ),
    );
  }

  ///
  /// 一个单词在本局整个过完一遍后结算：更新难度，必要时推进复习时间。
  ///
  /// 同一个词在一局里只会结算一次，重复调用直接返回 null。
  Future<SettleResult?> settle(int wordId) async {
    if (_finished || !module.writesRecords) return null;
    // 已经算过的词不再重复计入连对次数。
    if (!_settled.add(wordId)) return null;
    SettleResult? result;
    await _enqueue(() async {
      result = await store.settleWord(
        sessionId: session.id,
        wordId: wordId,
        updateReviewedAt: updatesReviewedAt,
      );
    });
    return result;
  }

  ///
  /// 给这一局判成败并收尾。
  ///
  /// 判定口径（对应《复习模块》文档的「会话结果」）：
  /// - 完成：这一局的全部条目都操作完了一遍，且一次错都没有；
  /// - 失败：超时、中途退出，或者过程中错过。
  ///
  /// 「中断」不走这里——它只在用户改了每日复习数量时由设置面板批量触发。
  Future<void> finish({required bool perfect, int? cursor, int? elapsed}) {
    // 重复收尾会把已经判定的成败改掉，一律忽略。
    if (_finished) return Future<void>.value();
    _finished = true;
    return _enqueue(
      () => store.finishSession(
        sessionId: session.id,
        status: perfect ? SessionStatus.completed : SessionStatus.failed,
        cursor: cursor,
        elapsed: elapsed,
      ),
    );
  }

  ///
  /// 把一次写入排进串行队列。
  ///
  /// 队列里某一次写入失败不能卡住后面的：catchError 让链条继续往下走，
  /// 单次失败最多丢一次进度，下一次保存会把最新状态重新写上去。
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((Object _) {});
    _queue = next;
    return next;
  }
}
