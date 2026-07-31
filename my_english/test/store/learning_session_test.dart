// services.dart 提供 MethodChannel 与 MethodCall，用来模拟 Android SQLite 桥接。
import 'package:flutter/services.dart';
// flutter_test 提供测试绑定、断言和 mock 消息桥。
import 'package:flutter_test/flutter_test.dart';
// 引入学习会话模型与正式 Store。
import 'package:my_english/models/learning_session.dart';
import 'package:my_english/store/learning_session.dart';

import '../support/memory_learning_session_store.dart';

/// 验证学习会话的 JSON 解析、通道方法名和覆盖写入参数。
///
/// @return `void`
void main() {
  // MethodChannel 测试必须先初始化 Flutter binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 独立通道避免与其他 Store 测试互相覆盖处理器。
  const channel = MethodChannel('test/learning_session_store');
  // 获取测试环境消息桥。
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 每个用例后注销处理器，防止状态泄漏。
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads, saves and deletes structured learning sessions', () async {
    // 保存 Dart 发往原生的完整调用顺序。
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getLearningSessions') {
        // 模拟 SQLite 返回 JSON 文本列。
        return <Map<String, Object?>>[
          <String, Object?>{
            'session_type': 'listening',
            'word_ids_json': '[9,3,7]',
            'state_json': '{"index":1,"isPlaying":false}',
            'updated_at': 1234,
          },
        ];
      }
      // save/delete 对应 Future<void>，原生成功时返回 null。
      if (call.method == 'saveLearningSession' ||
          call.method == 'deleteLearningSession') {
        return null;
      }
      throw StateError('unexpected method: ${call.method}');
    });
    // 使用测试通道创建正式实现。
    const store = LocalLearningSessionStore(channel: channel);

    // 读取后应还原类型、顺序、状态与毫秒时间戳。
    final sessions = await store.getAll();
    expect(sessions, hasLength(1));
    expect(sessions.single.type, LearningSessionType.listening);
    expect(sessions.single.wordIds, <int>[9, 3, 7]);
    expect(sessions.single.state['index'], 1);
    expect(sessions.single.state['isPlaying'], isFalse);
    expect(sessions.single.updatedAt?.millisecondsSinceEpoch, 1234);

    // 保存默写状态，确认复杂字段仍以 JSON 字符串传输。
    await store.save(
      const LearningSession(
        type: LearningSessionType.dictation,
        wordIds: <int>[3, 9],
        state: <String, Object?>{'wordIndex': 1, 'stage': 'definition'},
      ),
    );
    await store.delete(LearningSessionType.dictation);

    expect(calls.first, isMethodCall('getLearningSessions', arguments: null));
    expect(
      calls[1],
      isMethodCall(
        'saveLearningSession',
        arguments: <String, Object?>{
          'session_type': 'dictation',
          'word_ids_json': '[3,9]',
          'state_json': '{"wordIndex":1,"stage":"definition"}',
        },
      ),
    );
    expect(
      calls.last,
      isMethodCall(
        'deleteLearningSession',
        arguments: <String, Object?>{'session_type': 'dictation'},
      ),
    );
  });

  test(
    'persistence saves valid snapshots and skips invalid word ids',
    () async {
      final store = MemoryLearningSessionStore();
      final persistence = LearningSessionPersistence(
        store: store,
        type: LearningSessionType.dictation,
      );

      await persistence.save(
        wordIds: <int?>[2, 5],
        state: <String, Object?>{'wordIndex': 1},
      );
      await persistence.save(
        wordIds: <int?>[2, null],
        state: <String, Object?>{'wordIndex': 0},
      );
      await persistence.save(
        wordIds: <int?>[2, 5],
        state: <String, Object?>{'wordIndex': 0},
        enabled: false,
      );

      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.wordIds, <int>[2, 5]);
      expect(store.sessions.single.state, <String, Object?>{'wordIndex': 1});
    },
  );

  test('persistence isolates optional cache failures', () async {
    final persistence = LearningSessionPersistence(
      store: _FailingLearningSessionStore(),
      type: LearningSessionType.listening,
    );

    await expectLater(
      persistence.save(wordIds: <int?>[1], state: const <String, Object?>{}),
      completes,
    );
    await expectLater(persistence.delete(), completes);
  });
}

/// 主动抛错的测试 Store，用于验证辅助缓存异常不会中断页面流程。
class _FailingLearningSessionStore implements LearningSessionStore {
  /// 返回空会话列表。
  ///
  /// @return `Future<List<LearningSession>>` 空列表。
  @override
  Future<List<LearningSession>> getAll() async => const <LearningSession>[];

  /// 模拟保存失败。
  ///
  /// @param `LearningSession` session 本次尝试保存的会话。
  /// @return `Future<void>` 始终以 StateError 结束。
  @override
  Future<void> save(LearningSession session) async {
    throw StateError('save failed');
  }

  /// 模拟删除失败。
  ///
  /// @param `LearningSessionType` type 本次尝试删除的会话类型。
  /// @return `Future<void>` 始终以 StateError 结束。
  @override
  Future<void> delete(LearningSessionType type) async {
    throw StateError('delete failed');
  }
}
