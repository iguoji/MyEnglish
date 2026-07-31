// services.dart 提供 MethodChannel 与 MethodCall，用来模拟 Android SQLite 桥接。
import 'package:flutter/services.dart';
// flutter_test 提供测试绑定、断言和 mock 消息桥。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的默写候选缓存 Store。
import 'package:my_english/store/dictation_option_cache.dart';

/// 验证候选缓存 Store 的方法名、参数结构与返回值清洗。
void main() {
  // MethodChannel 测试必须先初始化 Flutter binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 使用独立通道名，避免与其他 Store 测试相互影响。
  const channel = MethodChannel('test/dictation_option_cache_store');
  // 获取测试环境的默认消息桥。
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 每个测试结束后注销原生处理器。
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads cleaned distractors and saves a complete cache row', () async {
    // 记录发给原生的完整调用顺序。
    final nativeCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      // 模拟历史缓存中混入空格、重复项、空文本和错误类型。
      if (call.method == 'getDictationOptionCache') {
        return <Object?>[' first ', 'second', 'first', '', 7];
      }
      // 保存调用返回 null，对应 Future<void>。
      if (call.method == 'saveDictationOptionCache') return null;
      throw StateError('unexpected method: ${call.method}');
    });
    // 用测试通道创建 Store。
    const store = DictationOptionCacheStore(channel: channel);

    // 读取结果应只保留去空格后的两个唯一合法字符串。
    final loaded = await store.getDistractors('word:1');
    expect(loaded, <String>['first', 'second']);
    // 保存新的标准三项缓存。
    await store.saveDistractors(
      cacheKey: 'word:1',
      wordId: 1,
      distractors: const <String>['one', 'two', 'three'],
    );

    // 首次调用按 key 查询。
    expect(
      nativeCalls.first,
      isMethodCall(
        'getDictationOptionCache',
        arguments: <String, Object?>{'cacheKey': 'word:1'},
      ),
    );
    // 第二次调用把 key、Word 外键和三个文本整体交给原生覆盖。
    expect(
      nativeCalls.last,
      isMethodCall(
        'saveDictationOptionCache',
        arguments: <String, Object?>{
          'cacheKey': 'word:1',
          'wordId': 1,
          'distractors': <String>['one', 'two', 'three'],
        },
      ),
    );
  });
}
