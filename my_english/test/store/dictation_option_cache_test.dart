// services.dart 提供 MethodChannel 与 MethodCall，用来模拟 Android SQLite 桥接。
import 'package:flutter/services.dart';
// flutter_test 提供测试绑定、断言和 mock 消息桥。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的默写候选缓存 Store。
import 'package:my_english/store/dictation_option_cache.dart';

///
/// 验证候选缓存 Store 的方法名、参数结构与返回值清洗。
///
/// @return void
///
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

  test('reads cleaned options and saves names with correct position', () async {
    // 记录发给原生的完整调用顺序。
    final nativeCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      // 模拟缓存中混入空格、大小写重复项、空文本和错误类型。
      if (call.method == 'getDictationOptionCache') {
        return <String, Object?>{
          'distractors': <Object?>[' First ', 'second', 'first', '', 7],
          'correctIndex': 2,
        };
      }
      // 保存调用返回 null，对应 Future<void>。
      if (call.method == 'saveDictationOptionCache') return null;
      throw StateError('unexpected method: ${call.method}');
    });
    // 用测试通道创建 Store。
    const store = DictationOptionCacheStore(channel: channel);

    // 读取结果应保留原顺序、清除重复文本，并还原正确答案位置。
    final loaded = await store.getOptions('word:1');
    expect(loaded?.distractors, <String>['First', 'second']);
    expect(loaded?.correctIndex, 2);
    // 保存新的标准三项缓存和正确答案下标。
    await store.saveOptions(
      cacheKey: 'word:1',
      wordId: 1,
      distractors: const <String>['one', 'two', 'three'],
      correctIndex: 1,
    );

    // 首次调用按 key 查询。
    expect(
      nativeCalls.first,
      isMethodCall(
        'getDictationOptionCache',
        arguments: <String, Object?>{'cacheKey': 'word:1'},
      ),
    );
    // 第二次调用把 key、Word 外键、三个文本和正确答案位置整体交给原生覆盖。
    expect(
      nativeCalls.last,
      isMethodCall(
        'saveDictationOptionCache',
        arguments: <String, Object?>{
          'cacheKey': 'word:1',
          'wordId': 1,
          'distractors': <String>['one', 'two', 'three'],
          'correctIndex': 1,
        },
      ),
    );
  });

  test('keeps missing correct position as a legacy cache marker', () async {
    // 旧版本原生缓存只有三个干扰项，升级后的 correctIndex 会暂时返回 null。
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDictationOptionCache') {
        return <String, Object?>{
          'distractors': <String>['one', 'two', 'three'],
          'correctIndex': null,
        };
      }
      throw StateError('unexpected method: ${call.method}');
    });
    const store = DictationOptionCacheStore(channel: channel);

    // null 不是损坏，而是通知页面沿用当前显示位置并补存一次。
    final loaded = await store.getOptions('legacy:word:1');
    expect(loaded?.distractors, <String>['one', 'two', 'three']);
    expect(loaded?.correctIndex, isNull);
  });

  test('rejects duplicate distractors before writing native cache', () async {
    // 即使未来页面误传 Ability/ability，Store 也不能把重复候选交给 SQLite。
    const store = DictationOptionCacheStore(channel: channel);
    await expectLater(
      store.saveOptions(
        cacheKey: 'word:duplicate',
        wordId: 1,
        distractors: const <String>['Ability', 'ability', 'other'],
        correctIndex: 0,
      ),
      throwsArgumentError,
    );
  });
}
