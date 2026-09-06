// services.dart 提供 MethodChannel 和 MethodCall。
import 'package:flutter/services.dart';
// flutter_test 提供单元测试与测试消息通道。
import 'package:flutter_test/flutter_test.dart';
// 引入全局 Word 模型与释义模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入被测试的纯 SQLite Word Store 与导入解析器。
import 'package:my_english/store/word.dart';

///
/// 注册原生通道桩，验证纯 SQLite Store 的路由与导入解析（v2.0 结构）。
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
          case 'getWordsByIds':
          case 'getWordsByMeaningIds':
            return <Object?>[
              <Object?, Object?>{
                'id': 7,
                'spelling': 'persisted',
                'meanings': <Object?>[
                  <Object?, Object?>{
                    'id': 10,
                    'word_id': 7,
                    'pos': 'n.',
                    'definition': '持久化的',
                  },
                ],
                'created_at': DateTime(2026, 7, 26).millisecondsSinceEpoch,
              },
            ];
          // 按条件选词返回主键数组。
          case 'pickWords':
            return <int>[7];
          case 'exportData':
            return <String, Object?>{
              'words': <Object?>[
                <String, Object?>{'id': 7, 'spelling': 'persisted'},
              ],
            };
          // 更新、删除、导入和清空均返回 Future<void>，对应 null。
          case 'updateWord':
          case 'deleteWord':
          case 'importData':
          case 'clearAll':
          case 'saveWordConfusions':
          case 'saveMeaningConfusions':
          case 'saveWordSyllables':
            return null;
        }
        // 未登记方法说明测试或接口出现错误。
        throw StateError('unexpected method: ${call.method}');
      });

      // 创建只使用原生通道的 Store。
      final store = LocalWordStore(channel: channel);

      // 创建返回主键。
      final createdId = await store.create(
        Word(
          spelling: 'persisted',
          meanings: const <Meaning>[Meaning(pos: 'n.', definition: '持久化的')],
        ),
      );
      expect(createdId, 7);
      // 查询从原生获取模型。
      final words = await store.getAll();
      expect(words.single.spelling, 'persisted');
      expect(words.single.allMeanings.single.definition, '持久化的');
      // 按主键与含义主键查询同样路由到对应方法。
      expect((await store.getByIds(<int>[7])).single.spelling, 'persisted');
      expect(
        (await store.getByMeaningIds(<int>[10])).single.spelling,
        'persisted',
      );
      // 按条件选词返回主键数组。
      expect(await store.pickWords(limit: 1, exclude: const <int>[]), <int>[7]);
      // 更新用一次调用整体替换主体与释义。
      await store.update(Word(id: 7, spelling: 'persisted'));
      // 保存混淆词与音节分别路由到各自的通道方法。
      await store.saveWordConfusions(7, const <String>['persisted2']);
      await store.saveMeaningConfusions(10, const <String>['能持久']);
      await store.saveWordSyllables(7, const <String>['per', 'sist']);
      // 删除进入原生软删除。
      await store.delete(7);
      // 导入批量写入（整库替换）。
      await store.importData(<String, Object?>{
        'words': <Object?>[
          <String, Object?>{'id': 1, 'spelling': 'a'},
        ],
      });
      // 导出直接使用 SQLite 表结构生成的对象。
      final exported = await store.exportData();
      expect(exported['words'], hasLength(1));
      // 清空两张表。
      await store.clearAll();
      // 方法顺序证明核心操作都经过 SQLite，并且创建、更新各只需要一次通道调用。
      expect(nativeCalls.map((call) => call.method), <String>[
        'createWord',
        'getAllWords',
        'getWordsByIds',
        'getWordsByMeaningIds',
        'pickWords',
        'updateWord',
        'saveWordConfusions',
        'saveMeaningConfusions',
        'saveWordSyllables',
        'deleteWord',
        'importData',
        'exportData',
        'clearAll',
      ]);
      // 删除参数携带主键。
      expect((nativeCalls[9].arguments as Map<Object?, Object?>)['id'], 7);
    },
  );

  // 验证导入解析：只认「顶层对象 + words 数组」的 2.0 备份结构。
  test('parseBackupJson accepts object shape with words array', () {
    final backup = parseBackupJson('''
      {
        "words": [
          {
            "id": 1,
            "spelling": "able",
            "meanings": [
              {"id": 10, "word_id": 1, "pos": "adj.", "definition": "能做……的"}
            ]
          }
        ]
      }
    ''');
    // 原样保留顶层结构与 words 数组。
    expect(backup['words'], isA<List<Object?>>());
  });

  // 顶层是数组或缺少 words 数组时，必须给出明确的中文错误提示。
  test('parseBackupJson rejects unsupported top-level shapes', () {
    // 顶层数组属于 1.x 旧结构，应被拒绝并提示走迁移脚本。
    expect(
      () => parseBackupJson('[{"spelling": "able"}]'),
      throwsA(isA<FormatException>()),
    );
    // 普通对象没有 words 字段同样拒绝。
    expect(
      () => parseBackupJson('{"foo": "bar"}'),
      throwsA(isA<FormatException>()),
    );
  });

  // parseWordMaps 逐条转换并保留顺序，坏记录带位置信息报错。
  test('parseWordMaps converts maps and wraps errors with position', () {
    final words = parseWordMaps(<dynamic>[
      <Object?, Object?>{
        'id': 1,
        'spelling': 'able',
        'meanings': <Object?>[
          <Object?, Object?>{
            'id': 10,
            'word_id': 1,
            'pos': 'adj.',
            'definition': '能做……的',
          },
        ],
      },
      <Object?, Object?>{
        'id': 2,
        'spelling': 'book',
        'meanings': <Object?>[
          <Object?, Object?>{
            'id': 11,
            'word_id': 2,
            'pos': 'n.',
            'definition': '书',
          },
        ],
      },
    ], sourceLabel: '导入文件');

    // 数量与顺序原样保留。
    expect(words.map((word) => word.spelling).toList(), <String>[
      'able',
      'book',
    ]);

    // 第二条记录缺拼写，错误信息应指明是第几条。
    expect(
      () => parseWordMaps(<dynamic>[
        <Object?, Object?>{'spelling': 'ok'},
        <Object?, Object?>{'id': 3},
      ], sourceLabel: '导入文件'),
      throwsA(
        predicate(
          (error) =>
              error is FormatException &&
              error.message.contains('导入文件 第 2 个单词'),
        ),
      ),
    );
  });
}
