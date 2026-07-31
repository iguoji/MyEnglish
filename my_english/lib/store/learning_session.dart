// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SQLite。
import 'package:flutter/services.dart';

// 引入学习会话模型及类型枚举。
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
    // 原生返回两行以内的 Map 列表；测试空实现返回 null 时按无历史处理。
    final rows = await _channel.invokeListMethod<Object?>(
      'getLearningSessions',
    );
    if (rows == null) return const <LearningSession>[];

    // 每一行都必须是 Map，格式异常应被首页捕获并清空继续入口。
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
    // 空列表无法恢复页面，禁止写入一条永远不可用的“继续”记录。
    if (session.wordIds.isEmpty) {
      throw ArgumentError.value(session.wordIds, 'wordIds', '学习会话单词列表不能为空');
    }
    // 原生使用 session_type 主键执行覆盖写入。
    await _channel.invokeMethod<void>('saveLearningSession', session.toMap());
  }

  @override
  Future<void> delete(LearningSessionType type) async {
    // 删除参数保留 Map 结构，便于以后附加原因或时间字段。
    await _channel.invokeMethod<void>(
      'deleteLearningSession',
      <String, Object?>{'session_type': type.storageKey},
    );
  }
}
