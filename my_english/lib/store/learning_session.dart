import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/learning_session.dart';

///
/// 学习会话 Store 接口，正式环境写 SQLite，Widget 测试可注入内存实现。
///
abstract interface class LearningSessionStore {
  ///
  /// 一次读取随身听和听音辨义两种未完成会话。
  ///
  /// @return `Future<List<LearningSession>>` 本地仍可继续的会话列表。
  ///
  Future<List<LearningSession>> getAll();

  ///
  /// 新增或覆盖同类型会话。
  ///
  /// @param  LearningSession  session 需要保存的最新页面快照。
  /// @return `Future<void>` 原生写入完成后的异步结果。
  ///
  Future<void> save(LearningSession session);

  ///
  /// 删除一种已经完成或已经失效的会话。
  ///
  /// @param  LearningSessionType  type 需要删除的学习模式。
  /// @return `Future<void>` 原生删除完成后的异步结果。
  ///
  Future<void> delete(LearningSessionType type);
}

///
/// 通过项目现有 word_store 通道访问 Android SQLite 的正式实现。
///
class LocalLearningSessionStore implements LearningSessionStore {
  ///
  /// 允许测试注入独立通道；正式 App 使用默认 word_store 通道。
  ///
  /// @param  MethodChannel?  channel 测试专用通道；为空时使用正式通道。
  ///
  const LocalLearningSessionStore({MethodChannel? channel})
    // 构造器注入类似 Laravel 容器注入，测试可以替换真实原生依赖。
    : _channel = channel ?? _defaultChannel;

  ///
  /// 全局默认实例，首页和两个学习页共用同一份本地数据。
  ///
  /// @var LocalLearningSessionStore
  ///
  static const LocalLearningSessionStore instance = LocalLearningSessionStore();

  ///
  /// 通道名必须与 MainActivity 注册值完全一致。
  ///
  /// @var MethodChannel
  ///
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 实际执行原生调用的消息通道。
  ///
  /// @var MethodChannel
  ///
  final MethodChannel _channel;

  ///
  /// 从原生 SQLite 读取全部未完成会话。
  ///
  /// @return `Future<List<LearningSession>>` 完成模型转换的不可变列表。
  ///
  @override
  Future<List<LearningSession>> getAll() async {
    // invokeListMethod 类似调用 Laravel Repository，原生返回两种会话的数据行。
    final rows = await _channel.invokeListMethod<Object?>(
      'getLearningSessions',
    );
    // 原生返回 null 等价于查询结果为空，统一交给页面空列表。
    if (rows == null) return const <LearningSession>[];

    // 逐行校验 Map 结构并转换成强类型模型，最终冻结列表防止外部修改。
    return List<LearningSession>.unmodifiable(
      rows.map((row) {
        // MethodChannel 数据必须是一行键值对象，其他结构说明原生协议不一致。
        if (row is! Map) {
          throw const FormatException('学习会话记录必须是对象');
        }
        // Map.from 收窄动态类型后交由模型完成 JSON 字段解析。
        return LearningSession.fromMap(Map<Object?, Object?>.from(row));
      }),
    );
  }

  ///
  /// 保存并覆盖同类型学习会话。
  ///
  /// @param  LearningSession  session 需要写入 SQLite 的页面快照。
  /// @return `Future<void>` 原生保存完成后的异步结果。
  ///
  @override
  Future<void> save(LearningSession session) async {
    // 空单词列表无法恢复页面，等价于拒绝一条不满足业务规则的模型。
    if (session.wordIds.isEmpty) {
      throw ArgumentError.value(session.wordIds, 'wordIds', '学习会话单词列表不能为空');
    }
    // session_type 是 SQLite 主键，因此同类型保存会直接覆盖上一份快照。
    await _channel.invokeMethod<void>('saveLearningSession', session.toMap());
  }

  ///
  /// 删除指定类型的学习会话。
  ///
  /// @param  LearningSessionType  type 已完成或失效的学习模式。
  /// @return `Future<void>` 原生删除完成后的异步结果。
  ///
  @override
  Future<void> delete(LearningSessionType type) async {
    // 使用 Map 传参保持 MethodChannel 协议可扩展，并与原生参数读取方式一致。
    await _channel.invokeMethod<void>(
      'deleteLearningSession',
      <String, Object?>{'session_type': type.storageKey},
    );
  }
}

///
/// 管理单个学习页面的会话快照。
///
/// 页面只负责组装自己的状态字段；本类统一处理单词主键校验、异常隔离和
/// 同类型会话的保存或删除。缓存失败不会中断当前学习流程。
///
class LearningSessionPersistence {
  ///
  /// 创建某个学习页面专用的持久化门面。
  ///
  /// @param  LearningSessionStore  store 实际执行读写的 Store。
  /// @param  LearningSessionType  type 当前页面所属的学习模式。
  ///
  const LearningSessionPersistence({required this.store, required this.type});

  ///
  /// 每个 Store 实例下各学习模式最后一项写任务。
  ///
  /// 页面 getter 会重复创建本门面，因此队列必须按 Store 身份共享，不能放在单个
  /// 门面实例里。这样先触发的旧快照一定先完成，后触发的新快照才会最终留在数据库。
  ///
  /// @var `Expando<Map<LearningSessionType, Future<void>>>`
  ///
  static final Expando<Map<LearningSessionType, Future<void>>> _writeQueues =
      Expando<Map<LearningSessionType, Future<void>>>('learningSessionWrites');

  ///
  /// 实际读写会话的 Store。
  ///
  /// @var LearningSessionStore
  ///
  final LearningSessionStore store;

  ///
  /// 当前页面维护的会话类型。
  ///
  /// @var LearningSessionType
  ///
  final LearningSessionType type;

  ///
  /// 把一次读写追加到当前 Store 与学习模式的队尾。
  ///
  /// 前一项即使失败也会被吞掉后继续执行下一项，避免一次辅助缓存故障让整条队列停摆。
  ///
  /// @param  `Future<void> Function()`  operation 实际要执行的保存或删除动作。
  /// @return `Future<void>` 当前动作结束后的异步结果；异常已转换为调试日志。
  ///
  Future<void> _enqueue(Future<void> Function() operation) {
    // 每个 Store 建立自己的模式队列表，测试 Store 与正式 Store 不会互相等待。
    final queues = _writeQueues[store] ??=
        <LearningSessionType, Future<void>>{};
    // 无论前一项成功还是失败，都从同一个队尾继续本次动作。
    final queued = (queues[type] ?? Future<void>.value()).then((_) async {
      try {
        // 真正的原生写入只会在上一项完成后开始。
        await operation();
      } catch (error) {
        // 学习进度属于辅助缓存，失败只记录诊断信息，不打断学习页面。
        debugPrint('${type.label}进度持久化失败：$error');
      }
    });
    // 保存新队尾，之后创建的门面也能通过同一 Store 身份找到它。
    queues[type] = queued;
    return queued;
  }

  ///
  /// 保存最新快照。
  ///
  /// [enabled] 为 false 或任一单词尚无数据库主键时不创建无法恢复的记录。
  ///
  /// @param  `Iterable<int?>`  wordIds 页面当前学习列表的单词主键。
  /// @param  `Map<String, Object?>`  state 页面自行组装的进度数据。
  /// @param  bool  enabled 是否允许本次保存。
  /// @return `Future<void>` 保存结束后的异步结果；缓存异常会在内部消化。
  ///
  Future<void> save({
    required Iterable<int?> wordIds,
    required Map<String, Object?> state,
    bool enabled = true,
  }) async {
    // 已完成页面传入 false，避免 dispose 时重新创建已经删除的会话。
    if (!enabled) return;

    // Iterable 先落成固定列表，相当于 PHP collect($ids)->all() 后再统一校验。
    final nullableIds = wordIds.toList(growable: false);
    // 空列表或缺失主键都无法从数据库重新组装 Word，因此不写无效快照。
    if (nullableIds.isEmpty || nullableIds.any((id) => id == null)) return;

    // 入队前冻结本次页面快照，避免调用方随后修改 Map 影响尚未执行的任务。
    final session = LearningSession(
      type: type,
      wordIds: List<int>.unmodifiable(nullableIds.cast<int>()),
      state: Map<String, Object?>.unmodifiable(state),
    );
    // 串行追加保存，杜绝旧请求比新请求更晚完成后反向覆盖数据库。
    await _enqueue(() => store.save(session));
  }

  ///
  /// 删除已完成或失效的快照。
  ///
  /// @return `Future<void>` 删除结束后的异步结果；缓存异常会在内部消化。
  ///
  Future<void> delete() async {
    // 删除也进入同一队列，防止它越过尚未完成的保存后又被旧快照重新覆盖。
    await _enqueue(() => store.delete(type));
  }
}

///
/// 为学习会话类型补充当前文件内部使用的中文日志名称。
///
extension on LearningSessionType {
  ///
  /// 返回日志中使用的中文学习模式名称。
  ///
  /// @return String 面向调试信息的模式名称。
  ///
  String get label => switch (this) {
    // 随身听会话使用用户界面中的正式名称。
    LearningSessionType.listening => '随身听',
    LearningSessionType.listeningMeaning => '听音辨义',
    LearningSessionType.listeningMeaningReview => '听音辨义（复习）',
    LearningSessionType.meaningMatch => '词义连连',
    LearningSessionType.spellingReinforcement => '拼写巩固',
    LearningSessionType.meaningWordChoice => '看义选词',
  };
}
