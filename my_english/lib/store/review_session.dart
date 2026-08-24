import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/review_session.dart';

///
/// 模块会话 Store 接口；正式环境写 SQLite，Widget 测试可注入内存实现。
///
abstract interface class ReviewSessionStore {
  ///
  /// 读取某个模块今天最新的一条会话（不论状态）。
  Future<ReviewSession?> getLatest(ReviewModule module);

  ///
  /// 读取某个模块今天已完成的主线会话。
  ///
  /// 有这条记录才说明今天的主线任务已经过关，接下来该开巩固局。
  Future<ReviewSession?> getCompletedDaily(ReviewModule module);

  ///
  /// 读取今天四个模块各自的进度，供首页卡片显示三态。
  Future<Map<ReviewModule, ReviewModuleState>> getTodayStates();

  ///
  /// 新建一局会话。
  Future<ReviewSession> create({
    required ReviewModule module,
    required ReviewSessionKind kind,
    required int? wordSetId,
    required List<int> wordIds,
    Map<String, Object?> state = const <String, Object?>{},
  });

  ///
  /// 更新一局进行中会话的页面进度与累计错误数。
  Future<void> saveProgress({
    required int sessionId,
    required Map<String, Object?> state,
    required int wrongTotal,
  });

  ///
  /// 给一局会话结算。
  Future<ReviewSession> finish({
    required int sessionId,
    required ReviewSessionStatus status,
    Map<String, Object?>? state,
    int? wrongTotal,
  });

  ///
  /// 把「进行中」的会话统一改成「中断」。
  Future<int> abortActive({bool onlyStale = false});
}

///
/// 通过项目现有 word_store 通道访问 Android SQLite 的正式实现。
///
class LocalReviewSessionStore implements ReviewSessionStore {
  ///
  /// 允许测试注入独立通道；正式 App 使用默认 word_store 通道。
  const LocalReviewSessionStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用实例，首页和四个模块页共用同一份本地数据。
  static const LocalReviewSessionStore instance = LocalReviewSessionStore();

  ///
  /// 通道名必须与 MainActivity 注册值完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 实际执行原生调用的消息通道。
  final MethodChannel _channel;

  @override
  Future<ReviewSession?> getLatest(ReviewModule module) =>
      _readSession('getLatestReviewSession', <String, Object?>{
        'module': module.storageKey,
      });

  @override
  Future<ReviewSession?> getCompletedDaily(ReviewModule module) =>
      _readSession('getCompletedDailyReviewSession', <String, Object?>{
        'module': module.storageKey,
      });

  @override
  Future<Map<ReviewModule, ReviewModuleState>> getTodayStates() async {
    // 原生返回 [{module, kind, status, daily_completed}]；null 按空列表处理。
    final rows = await _channel.invokeListMethod<Object?>(
      'getTodayReviewSessionStates',
    );
    if (rows == null) return const <ReviewModule, ReviewModuleState>{};
    final states = <ReviewModule, ReviewModuleState>{};
    for (final row in rows) {
      // 类型异常的行直接跳过，不让一条坏数据毁掉整个首页。
      if (row is! Map) continue;
      final map = Map<Object?, Object?>.from(row);
      final module = ReviewModule.tryFromStorageKey(map['module']?.toString());
      // 历史遗留或未来新增的模块键当前版本无法展示，安全跳过。
      if (module == null) continue;
      states[module] = ReviewModuleState.fromMap(map);
    }
    return Map<ReviewModule, ReviewModuleState>.unmodifiable(states);
  }

  @override
  Future<ReviewSession> create({
    required ReviewModule module,
    required ReviewSessionKind kind,
    required int? wordSetId,
    required List<int> wordIds,
    Map<String, Object?> state = const <String, Object?>{},
  }) async {
    // 空列表无法开局，在 Dart 层就拒绝，避免原生抛出更难读的错误。
    if (wordIds.isEmpty) {
      throw ArgumentError.value(wordIds, 'wordIds', '复习会话单词列表不能为空');
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'createReviewSession',
      <String, Object?>{
        'module': module.storageKey,
        'kind': kind.code,
        'wordSetId': wordSetId,
        'wordIds': List<int>.unmodifiable(wordIds),
        // 页面进度统一编码成 JSON 文本，由 SQLite 作为 TEXT 保存。
        'stateJson': jsonEncode(state),
      },
    );
    if (raw == null) throw const FormatException('原生没有返回新建的复习会话');
    return ReviewSession.fromMap(Map<Object?, Object?>.from(raw));
  }

  @override
  Future<void> saveProgress({
    required int sessionId,
    required Map<String, Object?> state,
    required int wrongTotal,
  }) async {
    await _channel.invokeMethod<void>(
      'updateReviewSessionProgress',
      <String, Object?>{
        'sessionId': sessionId,
        'stateJson': jsonEncode(state),
        'wrongTotal': wrongTotal < 0 ? 0 : wrongTotal,
      },
    );
  }

  @override
  Future<ReviewSession> finish({
    required int sessionId,
    required ReviewSessionStatus status,
    Map<String, Object?>? state,
    int? wrongTotal,
  }) async {
    // 「进行中」不是一个可结算的状态，误传时立刻暴露调用方的逻辑错误。
    if (status == ReviewSessionStatus.active) {
      throw ArgumentError.value(status, 'status', '结算状态不能是进行中');
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'finishReviewSession',
      <String, Object?>{
        'sessionId': sessionId,
        'status': status.code,
        // 两个可空参数表示「保持数据库现值」，页面可以只改状态。
        'stateJson': state == null ? null : jsonEncode(state),
        'wrongTotal': wrongTotal,
      },
    );
    if (raw == null) throw const FormatException('原生没有返回已结算的复习会话');
    return ReviewSession.fromMap(Map<Object?, Object?>.from(raw));
  }

  @override
  Future<int> abortActive({bool onlyStale = false}) async {
    final count = await _channel.invokeMethod<int>(
      'abortActiveReviewSessions',
      <String, Object?>{'onlyStale': onlyStale},
    );
    return count ?? 0;
  }

  ///
  /// 调用一个返回单条会话的原生方法，并转换成模型。
  Future<ReviewSession?> _readSession(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (raw == null) return null;
    return ReviewSession.fromMap(Map<Object?, Object?>.from(raw));
  }
}

///
/// 管理单个模块页面的会话进度落盘。
///
/// 页面只负责组装自己的状态字段；本类统一处理串行写入、异常隔离和结算。
/// 进度保存属于辅助能力，失败只写日志，绝不打断正在进行的答题。
///
class ReviewSessionPersistence {
  ///
  /// 创建某一局会话专用的持久化门面。
  const ReviewSessionPersistence({required this.store, required this.sessionId});

  ///
  /// 每个 Store 实例下各会话的最后一项写任务。
  ///
  /// 页面 getter 会重复创建本门面，因此队列必须按 Store 身份共享，不能放在
  /// 单个门面实例里。这样先触发的旧快照一定先完成，后触发的新快照才会最终
  /// 留在数据库，不会出现「旧进度反向覆盖新进度」。
  static final Expando<Map<int, Future<void>>> _writeQueues =
      Expando<Map<int, Future<void>>>('reviewSessionWrites');

  ///
  /// 实际读写会话的 Store。
  final ReviewSessionStore store;

  ///
  /// 当前页面正在进行的这一局。
  final int sessionId;

  ///
  /// 把一次写入追加到当前 Store 与会话的队尾。
  ///
  /// 前一项即使失败也会被吞掉后继续执行下一项，避免一次缓存故障让整条队列停摆。
  Future<void> _enqueue(Future<void> Function() operation) {
    // 每个 Store 建立自己的会话队列表，测试 Store 与正式 Store 不会互相等待。
    final queues = _writeQueues[store] ??= <int, Future<void>>{};
    // 无论前一项成功还是失败，都从同一个队尾继续本次动作。
    final queued = (queues[sessionId] ?? Future<void>.value()).then((_) async {
      try {
        await operation();
      } catch (error) {
        // 学习进度属于辅助缓存，失败只记录诊断信息，不打断答题页面。
        debugPrint('复习会话 $sessionId 进度持久化失败：$error');
      }
    });
    queues[sessionId] = queued;
    return queued;
  }

  ///
  /// 保存最新进度快照。
  Future<void> save({
    required Map<String, Object?> state,
    required int wrongTotal,
    bool enabled = true,
  }) async {
    // 已结算页面传 false，避免 dispose 时又把状态写回「进行中」的进度。
    if (!enabled) return;
    // 入队前冻结本次页面快照，避免调用方随后修改 Map 影响尚未执行的任务。
    final frozen = Map<String, Object?>.unmodifiable(state);
    await _enqueue(
      () => store.saveProgress(
        sessionId: sessionId,
        state: frozen,
        wrongTotal: wrongTotal,
      ),
    );
  }

  ///
  /// 结算这一局。
  ///
  /// 结算同样进入写队列，保证它一定排在此前所有进度保存之后执行，
  /// 不会被一条迟到的旧快照把状态改回去。
  Future<void> finish({
    required ReviewSessionStatus status,
    Map<String, Object?>? state,
    int? wrongTotal,
  }) async {
    final frozen = state == null
        ? null
        : Map<String, Object?>.unmodifiable(state);
    await _enqueue(
      () => store.finish(
        sessionId: sessionId,
        status: status,
        state: frozen,
        wrongTotal: wrongTotal,
      ),
    );
  }
}
