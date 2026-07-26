// services.dart 提供 MethodChannel 和 MethodCall。
import 'package:flutter/services.dart';
// flutter_test 提供单元测试与测试消息通道。
import 'package:flutter_test/flutter_test.dart';
// 引入全局 Meaning 与 Word 模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入被测试的双模式 Word Store。
import 'package:my_english/store/word.dart';

/// 注册 JSON 内存模式、重复 spelling 保留和 SQLite 回退测试。
void main() {
  // MethodChannel 测试需要先初始化 Flutter binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 使用独立通道名，避免与其他测试互相影响。
  const channel = MethodChannel('my_english/word_store_test');
  // 获取测试环境的消息桥。
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 每个测试结束后移除 mock handler。
  tearDown(() {
    // null 表示注销当前通道处理器。
    messenger.setMockMethodCallHandler(channel, null);
  });

  // 验证 JSON 存在时保留重复 spelling，所有 CRUD 都不触碰 MethodChannel。
  test(
    'JSON source preserves duplicate spelling and keeps CRUD in memory',
    () async {
      // 记录任何意外原生调用。
      final nativeCalls = <String>[];
      // 注册一个只负责记录的 handler。
      messenger.setMockMethodCallHandler(channel, (call) async {
        // 任何调用都会被最终断言发现。
        nativeCalls.add(call.method);
        // 本测试不期望真正返回数据。
        return null;
      });
      // 创建带两条重复 spelling 的 JSON Store。
      final store = LocalWordStore(
        channel: channel,
        jsonLoader: () async => '''
        [
          {
            "id": 1,
            "spelling": "able",
            "difficulty": 1,
            "created_at": "2026-03-18",
            "updated_at": "2026-04-01",
            "meanings": [
              {"index": 1, "pos": "adj.", "definitions": ["能做的"]}
            ]
          },
          {
            "id": 99,
            "spelling": "able",
            "difficulty": 4,
            "created_at": "2026-03-10",
            "updated_at": "2026-06-13",
            "meanings": [
              {"index": 3, "pos": "adj.", "definitions": ["能做的"]},
              {"index": 2, "pos": "adj.", "definitions": ["有才干的"]}
            ]
          }
        ]
      ''',
      );

      // 首次加载会选择 JSON，并按原始顺序保留全部 Word。
      final loadedWords = await store.getAll();
      // 两个同 spelling 都必须存在。
      expect(loadedWords, hasLength(2));
      // 每条记录保留自己的独立主键。
      expect(loadedWords.map((word) => word.id), <int?>[1, 99]);
      // 每条记录也保留自己的难度，不再聚合。
      expect(loadedWords.map((word) => word.difficulty), <int?>[1, 4]);
      // Meaning 分别属于各自 Word，不跨 Word 去重或合并。
      expect(loadedWords[0].meanings, hasLength(1));
      expect(loadedWords[1].meanings, hasLength(2));
      // 两条记录分别保留各自创建时间。
      expect(loadedWords[0].createdAt, DateTime(2026, 3, 18));
      expect(loadedWords[1].createdAt, DateTime(2026, 3, 10));
      // Store 已经锁定 JSON 内存模式。
      expect(store.activeSource, WordDataSource.jsonMemory);

      // 再新增一个相同拼写，验证 create 同样允许重复。
      final newId = await store.create(
        const Word(
          spelling: 'able',
          meanings: <Meaning>[
            Meaning(index: 1, pos: 'v.', definitions: <String>['能够']),
          ],
        ),
      );
      // 当前最大 id 是 99，所以新 id 为 100。
      expect(newId, 100);
      // 更新刚创建的内存 Word。
      await store.update(Word(id: newId, spelling: 'able', difficulty: 7));
      // 更新结果留在当前进程内。
      expect(
        (await store.getAll())
            .firstWhere((word) => word.id == newId)
            .difficulty,
        7,
      );
      // 删除同样只过滤内存数组。
      await store.delete(newId);
      // 删除后仍保留 JSON 原有的两条同拼写 Word。
      expect(await store.getAll(), hasLength(2));
      // 整个流程绝不能调用 SQLite 通道。
      expect(nativeCalls, isEmpty);
    },
  );

  // 验证资源不存在时，首次 CRUD 也会正确锁定 SQLite 并持久化。
  test('missing JSON makes all operations use SQLite', () async {
    // 按实际发生顺序记录方法名。
    final nativeCalls = <String>[];
    // 模拟 Android MainActivity 的返回值。
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      // 保存调用顺序。
      nativeCalls.add(call.method);
      // 根据方法名返回对应原生结果。
      switch (call.method) {
        // 创建返回 SQLite 自增主键。
        case 'createWord':
          return 7;
        // 查询返回普通 Map 数组。
        case 'getAllWords':
          return <Object?>[
            <Object?, Object?>{
              'id': 7,
              'spelling': 'persisted',
              'meanings': <Object?>[],
              'created_at': DateTime(2026, 7, 26).millisecondsSinceEpoch,
            },
          ];
        // update/delete 的 Future<void> 对应 null。
        case 'updateWord':
        case 'deleteWord':
          return null;
      }
      // 未登记方法说明测试或接口出现错误。
      throw StateError('unexpected method: ${call.method}');
    });
    // loader 抛专用缺失异常，模拟 AssetManifest 中没有 words.json。
    final store = LocalWordStore(
      channel: channel,
      jsonLoader: () async => throw const WordJsonAssetNotFoundException(),
    );

    // 故意在 getAll 之前调用 create，验证不会误判内存状态。
    final createdId = await store.create(const Word(spelling: 'persisted'));
    // 使用原生返回主键。
    expect(createdId, 7);
    // 数据源被永久锁定为 SQLite。
    expect(store.activeSource, WordDataSource.sqlite);
    // 查询从原生获取模型。
    final words = await store.getAll();
    // 原生结果转换正确。
    expect(words.single.spelling, 'persisted');
    // 更新进入原生事务。
    await store.update(const Word(id: 7, spelling: 'persisted'));
    // 删除进入原生软删除。
    await store.delete(7);
    // 方法顺序证明四个操作都经过 SQLite。
    expect(nativeCalls, <String>[
      'createWord',
      'getAllWords',
      'updateWord',
      'deleteWord',
    ]);
  });

  // 验证 JSON 已经存在但格式损坏时不能偷偷读取 SQLite。
  test('malformed JSON reports the error instead of falling back', () async {
    // 记录是否发生了错误回退。
    final nativeCalls = <String>[];
    // 注册通道处理器。
    messenger.setMockMethodCallHandler(channel, (call) async {
      // 如果这里被调用，断言会失败。
      nativeCalls.add(call.method);
      return <Object?>[];
    });
    // loader 成功返回文本，但文本不是合法 JSON。
    final store = LocalWordStore(
      channel: channel,
      jsonLoader: () async => '{broken json',
    );

    // 解析异常必须原样交给调用方。
    await expectLater(store.getAll(), throwsA(isA<FormatException>()));
    // 失败时没有锁定错误的数据源，允许点击重新加载。
    expect(store.activeSource, isNull);
    // 绝不能用旧 SQLite 数据掩盖 JSON 错误。
    expect(nativeCalls, isEmpty);
  });
}
