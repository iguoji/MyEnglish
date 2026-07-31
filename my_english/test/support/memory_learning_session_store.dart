import 'package:my_english/models/learning_session.dart';
import 'package:my_english/store/learning_session.dart';

/// 学习会话的内存测试实现。
///
/// 保存行为与 SQLite 的同类型覆盖规则一致，测试可直接检查 [sessions]。
class MemoryLearningSessionStore implements LearningSessionStore {
  MemoryLearningSessionStore([List<LearningSession> initial = const []])
    : sessions = List<LearningSession>.of(initial);

  final List<LearningSession> sessions;

  @override
  Future<List<LearningSession>> getAll() async {
    return List<LearningSession>.unmodifiable(sessions);
  }

  @override
  Future<void> save(LearningSession session) async {
    sessions.removeWhere((item) => item.type == session.type);
    sessions.add(session);
  }

  @override
  Future<void> delete(LearningSessionType type) async {
    sessions.removeWhere((item) => item.type == type);
  }
}
