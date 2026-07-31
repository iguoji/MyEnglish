import 'package:my_english/models/learning_session.dart';
import 'package:my_english/store/learning_session.dart';

/// 学习会话的内存测试实现。
///
/// 保存行为与 SQLite 的同类型覆盖规则一致，测试可直接检查 [sessions]。
class MemoryLearningSessionStore implements LearningSessionStore {
  /// 创建测试使用的内存会话 Store。
  ///
  /// @param `List<LearningSession>` initial 测试开始前预置的会话列表。
  MemoryLearningSessionStore([List<LearningSession> initial = const []])
    // 复制输入数组，避免测试过程修改调用方持有的 fixture。
    : sessions = List<LearningSession>.of(initial);

  /// 当前内存中的学习会话。
  ///
  /// @var `List<LearningSession>`
  final List<LearningSession> sessions;

  /// 读取全部内存会话。
  ///
  /// @return `Future<List<LearningSession>>` 不可变的会话列表。
  @override
  Future<List<LearningSession>> getAll() async {
    // 冻结返回值，模拟正式 Store 不允许页面直接修改结果的规则。
    return List<LearningSession>.unmodifiable(sessions);
  }

  /// 按类型覆盖保存最新会话。
  ///
  /// @param `LearningSession` session 需要保存的页面快照。
  /// @return `Future<void>` 内存更新完成后的异步结果。
  @override
  Future<void> save(LearningSession session) async {
    // SQLite 使用 session_type 主键，内存实现先移除同类型旧记录。
    sessions.removeWhere((item) => item.type == session.type);
    // 再追加最新快照，保证每种学习模式最多保留一条。
    sessions.add(session);
  }

  /// 删除指定类型的内存会话。
  ///
  /// @param `LearningSessionType` type 需要删除的学习模式。
  /// @return `Future<void>` 内存删除完成后的异步结果。
  @override
  Future<void> delete(LearningSessionType type) async {
    // 精确删除目标模式，不影响另一种学习记录。
    sessions.removeWhere((item) => item.type == type);
  }
}
