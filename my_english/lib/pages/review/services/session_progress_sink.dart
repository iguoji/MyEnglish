import '../../../models/learning_session.dart';
import '../../../models/model_value_parser.dart';
import '../../../models/review_session.dart';
import '../../../store/learning_session.dart';
import '../../../store/review_session.dart';

///
/// 一局答题的「进度出口」。
///
/// 听音辨义和词义连连都有两种进入方式，进度该存到哪张表并不一样：
/// - 从词库底部进入的普通练习 → 存 `learning_sessions`，长期有效、随时接着练；
/// - 从首页复习模块进入 → 存 `review_sessions`，属于今天的任务，有明确的成败。
///
/// 页面本身不该关心这个差别。它只管组装自己的进度字段，交给这个出口去落盘；
/// 到底是「覆盖一条长期快照」还是「给今天这一局判个成败」，由具体实现决定。
///
abstract interface class SessionProgressSink {
  ///
  /// 进入页面时需要恢复的进度快照；全新一局时是空 Map。
  Map<String, Object?> get initialState;

  ///
  /// 这一局此前已经累计的错误数。
  ///
  /// 中途退出再进来时，错误数必须接着数，不能归零——否则错完退出再进来
  /// 就能刷出一局「全对」。
  int get initialWrongTotal;

  ///
  /// 保存最新进度快照。
  Future<void> save({
    required Map<String, Object?> state,
    required int wrongTotal,
    bool enabled,
  });

  ///
  /// 结算这一局。
  Future<void> finish({
    required bool perfect,
    Map<String, Object?>? state,
    int? wrongTotal,
  });
}

///
/// 普通练习入口的进度出口：进度存进长期学习会话。
///
/// 这类练习没有「今天的任务」概念，也就没有成败之分：整轮做完就把快照删掉，
/// 首页的「继续」按钮随之消失。
///
class LearningSessionProgressSink implements SessionProgressSink {
  ///
  /// 创建一个长期会话进度出口。
  LearningSessionProgressSink({
    required LearningSessionStore store,
    required LearningSessionType type,
    required this.wordIds,
    LearningSession? session,
  }) : _persistence = LearningSessionPersistence(store: store, type: type),
       // 类型对不上的历史快照不能拿来恢复，直接当作全新一局。
       _session = session != null && session.type == type ? session : null;

  ///
  /// 实际执行串行写入的持久化门面。
  final LearningSessionPersistence _persistence;

  ///
  /// 本轮固定的单词主键顺序，保存快照时一并写入。
  final Iterable<int?> wordIds;

  ///
  /// 需要恢复的历史会话；全新一局时为 null。
  final LearningSession? _session;

  @override
  Map<String, Object?> get initialState =>
      _session?.state ?? const <String, Object?>{};

  ///
  /// 长期练习不判成败，累计错误数只从快照里读出来接着数。
  @override
  int get initialWrongTotal =>
      readIntOrFallback(_session?.state['errors'], fallback: 0);

  @override
  Future<void> save({
    required Map<String, Object?> state,
    required int wrongTotal,
    bool enabled = true,
  }) => _persistence.save(wordIds: wordIds, state: state, enabled: enabled);

  ///
  /// 整轮做完就删掉快照，不区分对错。
  @override
  Future<void> finish({
    required bool perfect,
    Map<String, Object?>? state,
    int? wrongTotal,
  }) => _persistence.delete();
}

///
/// 首页复习模块的进度出口：进度存进今天这一局复习会话。
///
/// 这类会话有明确的成败：把这一局的单词/卡片全部操作完一遍才算「完成」，
/// 中途答错不影响这个判定；倒计时耗尽或中途退出导致没走完全部单词/卡片
/// 才算「失败」。
///
class ReviewSessionProgressSink implements SessionProgressSink {
  ///
  /// 创建一个复习会话进度出口。
  ReviewSessionProgressSink({
    required ReviewSessionStore store,
    required ReviewSession session,
  }) : _persistence = ReviewSessionPersistence(
         store: store,
         sessionId: session.id,
       ),
       _session = session;

  ///
  /// 实际执行串行写入的持久化门面。
  final ReviewSessionPersistence _persistence;

  ///
  /// 当前这一局。
  final ReviewSession _session;

  @override
  Map<String, Object?> get initialState => _session.state;

  @override
  int get initialWrongTotal => _session.wrongTotal;

  @override
  Future<void> save({
    required Map<String, Object?> state,
    required int wrongTotal,
    bool enabled = true,
  }) => _persistence.save(
    state: state,
    wrongTotal: wrongTotal,
    enabled: enabled,
  );

  ///
  /// 按「操作完一遍即算完成」的规则给这一局判成败。
  @override
  Future<void> finish({
    required bool perfect,
    Map<String, Object?>? state,
    int? wrongTotal,
  }) => _persistence.finish(
    status: perfect
        ? ReviewSessionStatus.completed
        : ReviewSessionStatus.failed,
    state: state,
    wrongTotal: wrongTotal,
  );
}
