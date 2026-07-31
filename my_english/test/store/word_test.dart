// services.dart 提供 MethodChannel 和 MethodCall。
import 'package:flutter/services.dart';
// flutter_test 提供单元测试与测试消息通道。
import 'package:flutter_test/flutter_test.dart';
// 引入全局 Word 模型。
import 'package:my_english/models/word.dart';
// 引入被测试的纯 SQLite Word Store 与导入解析器。
import 'package:my_english/store/word.dart';

/// 注册原生通道桩，验证纯 SQLite Store 的路由与导入解析。
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

  // 验证全部 CRUD 与导入/清空都正确路由到原生通道。
  test(
    'SQLite store routes CRUD, import and clear through the channel',
    () async {
      // 按实际发生顺序记录完整调用，既检查方法名也检查事务参数。
      final nativeCalls = <MethodCall>[];
      // 模拟 Android MainActivity 的返回值。
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        // 保存调用顺序。
        nativeCalls.add(call);
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
          // 更新、删除、导入和清空均返回 Future<void>，对应 null。
          case 'updateWord':
          case 'deleteWord':
          case 'importWords':
          case 'importData':
          case 'clearAllWords':
            return null;
        }
        // 未登记方法说明测试或接口出现错误。
        throw StateError('unexpected method: ${call.method}');
      });

      // 创建只使用原生通道的 Store。
      final store = LocalWordStore(channel: channel);

      // 创建时把分组一并放进同一个原生事务，并返回主键。
      final createdId = await store.create(
        const Word(spelling: 'persisted', groupIds: <int>[3]),
      );
      expect(createdId, 7);
      // 查询从原生获取模型。
      final words = await store.getAll();
      expect(words.single.spelling, 'persisted');
      // 更新同样用一次调用整体替换主体、释义和分组。
      await store.update(
        const Word(id: 7, spelling: 'persisted', groupIds: <int>[4]),
      );
      // 删除进入原生软删除。
      await store.delete(7);
      // 导入批量写入（整库替换）。
      await store.importWords(const [Word(spelling: 'a'), Word(spelling: 'b')]);
      // 清空两张表。
      await store.clearAll();
      // 方法顺序证明核心操作都经过 SQLite，并且创建、更新各只需要一次通道调用。
      expect(nativeCalls.map((call) => call.method), <String>[
        'createWord',
        'getAllWords',
        'updateWord',
        'deleteWord',
        'importWords',
        'clearAllWords',
      ]);
      // 创建参数已经包含分组 id，不再另发 addGroupMember。
      expect(
        (nativeCalls[0].arguments as Map<Object?, Object?>)['group_ids'],
        <int>[3],
      );
      // 更新参数同样包含完整新分组，不再另发 setWordGroups。
      expect(
        (nativeCalls[2].arguments as Map<Object?, Object?>)['group_ids'],
        <int>[4],
      );
    },
  );

  // 验证导入解析兼容「数组」与「{words:[...]}」两种形态。
  test('parseWordsFromJsonText handles array and object shapes', () {
    // 形态一：顶层数组，对应原始 words.json。
    final fromArray = parseWordsFromJsonText('''
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
        }
      ]
    ''');
    expect(fromArray, hasLength(1));
    expect(fromArray.single.spelling, 'able');
    expect(fromArray.single.meanings.single.pos, 'adj.');

    // 形态二：顶层对象含 words 数组，对应本 App 导出的备份。
    final fromObject = parseWordsFromJsonText('''
      {
        "words": [
          {
            "spelling": "book",
            "meanings": [{"index": 1, "pos": "n.", "definitions": ["书"]}]
          }
        ]
      }
    ''');
    expect(fromObject, hasLength(1));
    expect(fromObject.single.spelling, 'book');
  });

  // 验证顶层既不是数组也不是含 words 的对象时明确报错。
  test('parseWordsFromJsonText rejects unsupported top-level shape', () {
    // 普通对象没有 words 字段，应抛 FormatException。
    expect(
      () => parseWordsFromJsonText('{"foo": "bar"}'),
      throwsA(isA<FormatException>()),
    );
  });
}
