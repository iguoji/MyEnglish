import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/learning_session.dart';

/// 学习会话 Store 接口，正式环境写 SQLite，Widget 测试可注入内存实现。
abstract interface class LearningSessionStore {
  /// 一次读取随身听和默写两种未完成会话。
  Future<List<LearningSession>> getAll();

  /// 新增或覆盖同类型会话。
  Future<void> save(LearningSession session);

  /// 删除一种已经完成或已经失效的会话。
  Future<void> delete(LearningSessionType type);
}

/// 通过项目现有 word_store 通道访问 Android SQLite 的正式实现。
class LocalLearningSessionStore implements LearningSessionStore {
  /// 允许测试注入独立通道；正式 App 使用默认 word_store 通道。
  const LocalLearningSessionStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  /// 全局默认实例，首页和两个学习页共用同一份本地数据。
  static const LocalLearningSessionStore instance = LocalLearningSessionStore();

  /// 通道名必须与 MainActivity 注册值完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  /// 实际执行原生调用的消息通道。
  final MethodChannel _channel;

  @override
  Future<List<LearningSession>> getAll() async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getLearningSessions',
    );
    if (rows == null) return const <LearningSession>[];

    return List<LearningSession>.unmodifiable(
      rows.map((row) {
        if (row is! Map) {
          throw const FormatException('学习会话记录必须是对象');
        }
        return LearningSession.fromMap(Map<Object?, Object?>.from(row));
      }),
    );
  }

  @override
  Future<void> save(LearningSession session) async {
    if (session.wordIds.isEmpty) {
      throw ArgumentError.value(session.wordIds, 'wordIds', '学习会话单词列表不能为空');
    }
    await _channel.invokeMethod<void>('saveLearningSession', session.toMap());
  }

  @override
  Future<void> delete(LearningSessionType type) async {
    await _channel.invokeMethod<void>(
      'deleteLearningSession',
      <String, Object?>{'session_type': type.storageKey},
    );
  }
}

/// 管理单个学习页面的会话快照。
///
/// 页面只负责组装自己的状态字段；本类统一处理单词主键校验、异常隔离和
/// 同类型会话的保存或删除。缓存失败不会中断当前学习流程。
class LearningSessionPersistence {
  const LearningSessionPersistence({required this.store, required this.type});

  /// 实际读写会话的 Store。
  final LearningSessionStore store;

  /// 当前页面维护的会话类型。
  final LearningSessionType type;

  /// 保存最新快照。
  ///
  /// [enabled] 为 false 或任一单词尚无数据库主键时不创建无法恢复的记录。
  Future<void> save({
    required Iterable<int?> wordIds,
    required Map<String, Object?> state,
    bool enabled = true,
  }) async {
    if (!enabled) return;

    final nullableIds = wordIds.toList(growable: false);
    if (nullableIds.isEmpty || nullableIds.any((id) => id == null)) return;

    try {
      await store.save(
        LearningSession(
          type: type,
          wordIds: nullableIds.cast<int>(),
          state: state,
        ),
      );
    } catch (error) {
      debugPrint('保存${type.label}进度失败：$error');
    }
  }

  /// 删除已完成或失效的快照。
  Future<void> delete() async {
    try {
      await store.delete(type);
    } catch (error) {
      debugPrint('删除${type.label}进度失败：$error');
    }
  }
}

extension on LearningSessionType {
  String get label => switch (this) {
    LearningSessionType.listening => '随身听',
    LearningSessionType.dictation => '默写',
  };
}
