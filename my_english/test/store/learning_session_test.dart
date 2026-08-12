// dart:async 提供 Completer，用于精确控制两次异步保存的完成顺序。
import 'dart:async';

// services.dart 提供 MethodChannel 与 MethodCall，用来模拟 Android SQLite 桥接。
import 'package:flutter/services.dart';
// flutter_test 提供测试绑定、断言和 mock 消息桥。
import 'package:flutter_test/flutter_test.dart';
// 引入学习会话模型与正式 Store。
import 'package:my_english/models/learning_session.dart';
import 'package:my_english/store/learning_session.dart';

import '../support/memory_learning_session_store.dart';

///
/// 验证学习会话的 JSON 解析、通道方法名和覆盖写入参数。
///
/// @return void
///
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

  test('persistence serializes snapshots across recreated facades', () async {
    // 可控 Store 会暂停第一项保存，用来观察第二项是否被正确排队。
    final store = _ControlledLearningSessionStore();
    // 模拟页面 getter 第一次创建持久化门面并触发旧快照保存。
    final firstPersistence = LearningSessionPersistence(
      store: store,
      type: LearningSessionType.dictation,
    );
    // 启动第一项保存但不等待，因为它会被测试 Store 主动挂起。
    final firstSave = firstPersistence.save(
      wordIds: <int?>[1],
      state: <String, Object?>{'wordIndex': 0},
    );
    // 让 Future 队列有机会真正进入 Store.save。
    await Future<void>.delayed(Duration.zero);
    // 第一项已经开始执行。
    expect(store.startedWordIndexes, <int>[0]);

    // 模拟页面 getter 再次创建新门面并触发更新后的快照。
    final secondSave = LearningSessionPersistence(
      store: store,
      type: LearningSessionType.dictation,
    ).save(wordIds: <int?>[1], state: <String, Object?>{'wordIndex': 1});
    // 再让微任务运行；若没有共享队列，第二项此时也会进入 Store。
    await Future<void>.delayed(Duration.zero);
    // 新快照必须仍在队尾等待，不能与旧快照并发写入。
    expect(store.startedWordIndexes, <int>[0]);

    // 放行第一项保存。
    store.firstSave.complete();
    // 等待两个调用都结束。
    await Future.wait(<Future<void>>[firstSave, secondSave]);
    // 第二项只会在第一项完成后开始，因此数据库最终状态必然是最新下标 1。
    expect(store.startedWordIndexes, <int>[0, 1]);
    expect(store.persistedWordIndex, 1);
  });
}

///
/// 可暂停首次保存的测试 Store，用于验证持久化队列不会乱序写入。
///
class _ControlledLearningSessionStore implements LearningSessionStore {
  ///
  /// 第一项保存的手动放行开关。
  ///
  /// @var `Completer<void>`
  ///
  final Completer<void> firstSave = Completer<void>();

  ///
  /// 每次真正进入 Store.save 时记录的单词下标。
  ///
  /// @var `List<int>`
  ///
  final List<int> startedWordIndexes = <int>[];

  ///
  /// 最后成功落库的单词下标。
  ///
  /// @var int?
  ///
  int? persistedWordIndex;

  ///
  /// 本用例不读取已有会话。
  ///
  /// @return `Future<List<LearningSession>>` 空列表。
  ///
  @override
  Future<List<LearningSession>> getAll() async => const <LearningSession>[];

  ///
  /// 暂停第一项保存，第二项保存正常完成。
  ///
  /// @param  LearningSession  session 本次页面快照。
  /// @return `Future<void>` 对应保存完成时机。
  ///
  @override
  Future<void> save(LearningSession session) async {
    // 取出测试状态里的单词下标。
    final wordIndex = session.state['wordIndex']! as int;
    // 记录真正开始执行的顺序。
    startedWordIndexes.add(wordIndex);
    // 第一项必须等待测试主动放行。
    if (wordIndex == 0) await firstSave.future;
    // 模拟 SQLite 覆盖同类型记录，最后一次完成者成为持久化结果。
    persistedWordIndex = wordIndex;
  }

  ///
  /// 本用例不执行删除。
  ///
  /// @param  LearningSessionType  type 待删除模式。
  /// @return `Future<void>` 立即完成。
  ///
  @override
  Future<void> delete(LearningSessionType type) async {}
}

///
/// 主动抛错的测试 Store，用于验证辅助缓存异常不会中断页面流程。
///
class _FailingLearningSessionStore implements LearningSessionStore {
  ///
  /// 返回空会话列表。
  ///
  /// @return `Future<List<LearningSession>>` 空列表。
  ///
  @override
  Future<List<LearningSession>> getAll() async => const <LearningSession>[];

  ///
  /// 模拟保存失败。
  ///
  /// @param  LearningSession  session 本次尝试保存的会话。
  /// @return `Future<void>` 始终以 StateError 结束。
  ///
  @override
  Future<void> save(LearningSession session) async {
    throw StateError('save failed');
  }

  ///
  /// 模拟删除失败。
  ///
  /// @param  LearningSessionType  type 本次尝试删除的会话类型。
  /// @return `Future<void>` 始终以 StateError 结束。
  ///
  @override
  Future<void> delete(LearningSessionType type) async {
    throw StateError('delete failed');
  }
}
