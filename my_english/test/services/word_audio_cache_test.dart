// dart:async 提供可控的广播 StreamController，用来模拟原生 EventChannel。
import 'dart:async';

// services.dart 提供可注入的 MethodChannel 测试桩。
import 'package:flutter/services.dart';
// flutter_test 提供测试绑定和断言。
import 'package:flutter_test/flutter_test.dart';
// 引入待测试的离线缓存状态服务。
import 'package:my_english/services/word_audio_cache.dart';

///
/// 验证失败进度的真实百分比，以及清空后长期订阅仍可复用。
void main() {
  // MethodChannel 测试必须先初始化 Flutter 消息绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 测试使用独立通道，避免与全局单例和其他用例串场。
  const channel = MethodChannel('test/word_audio_cache');
  // 取得测试消息桥用于注册假原生实现。
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 每个用例后注销处理器。
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // 清空缓存只重置数据，不能取消进度订阅，否则第二批永远收不到事件。
  test(
    'keeps one progress subscription after clearing and restarting',
    () async {
      // 记录广播流实际被监听的次数。
      var listenCount = 0;
      // 广播控制器允许测试主动推送与 Kotlin 相同结构的 Map 事件。
      final events = StreamController<dynamic>.broadcast(
        onListen: () => listenCount += 1,
      );
      // 用例结束关闭控制器。
      addTearDown(events.close);
      // 假原生返回初始 0/2，并接受 precache 与 clearAudioCache。
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCacheProgress') {
          return <String, Object?>{'cached': 0, 'total': 2};
        }
        return null;
      });
      // 注入可控通道和事件流。
      final cache = WordAudioCache.forTesting(
        channel: channel,
        progressEvents: events.stream,
      );
      // 用例结束释放 ChangeNotifier 资源。
      addTearDown(cache.dispose);

      // 第一批开始时创建唯一长期订阅。
      await cache.setWordList(<String>['apple', 'banana']);
      cache.start();
      await Future<void>.delayed(Duration.zero);
      expect(listenCount, 1);

      // 两个单词只有一个已完整缓存，百分比必须是真实 50%，不能显示 100%。
      events.add(<String, Object?>{'cached': 1, 'total': 2, 'done': true});
      await Future<void>.delayed(Duration.zero);
      expect(cache.cached, 1);
      expect(cache.percent, 50);
      expect(cache.isCaching, isFalse);

      // 清空后重新装载词表并启动第二批。
      await cache.clearCacheFiles();
      await cache.setWordList(<String>['apple', 'banana']);
      cache.start();
      await Future<void>.delayed(Duration.zero);
      // 仍是同一个订阅；原生清空 EventSink 的旧实现会让这条路径断链。
      expect(listenCount, 1);

      // 原有订阅可以继续接收第二批事件；第二批只缓存了 1 个，百分比仍是 50%。
      events.add(<String, Object?>{'cached': 1, 'total': 2, 'done': false});
      await Future<void>.delayed(Duration.zero);
      expect(cache.cached, 1);
      expect(cache.percent, 50);
      expect(cache.isCaching, isTrue);
    },
  );

  // 验证较旧的原生查询即使最后返回，也不能覆盖较新的词库进度。
  test('ignores stale word list progress responses', () async {
    // 两个 Completer 分别控制旧词库和新词库查询的返回时机。
    final oldResult = Completer<Map<String, Object?>>();
    final newResult = Completer<Map<String, Object?>>();
    // 注册假原生实现，根据词表首项把请求交给对应的可控结果。
    messenger.setMockMethodCallHandler(channel, (call) {
      // 本用例只允许查询初始缓存进度。
      expect(call.method, 'getCacheProgress');
      // 读取 Dart 传给原生的词表参数。
      final arguments = call.arguments! as Map<Object?, Object?>;
      // 收窄出首个拼写，用它区分先后两次请求。
      final spellings = arguments['spellings']! as List<Object?>;
      // 返回尚未完成的 Future，让测试自行安排返回顺序。
      return spellings.first == 'old' ? oldResult.future : newResult.future;
    });
    // 本用例不需要进度事件，使用空广播流即可。
    final events = StreamController<dynamic>.broadcast();
    // 用例结束关闭流。
    addTearDown(events.close);
    // 注入可控通道创建独立服务实例。
    final cache = WordAudioCache.forTesting(
      channel: channel,
      progressEvents: events.stream,
    );
    // 用例结束释放 ChangeNotifier。
    addTearDown(cache.dispose);

    // 先发起包含两个单词的旧请求，但暂不等待它完成。
    final oldRequest = cache.setWordList(<String>['old', 'legacy']);
    // 紧接着发起只包含一个单词的新请求。
    final newRequest = cache.setWordList(<String>['new']);
    // 让新请求先返回 1/2 的真实进度。
    newResult.complete(<String, Object?>{'cached': 1, 'total': 2});
    // 等待新状态写入服务。
    await newRequest;
    // 当前展示必须采用最新词库的结果。
    expect(cache.cached, 1);
    expect(cache.total, 2);

    // 最后才让旧请求返回一个明显不同的 4/4 结果。
    oldResult.complete(<String, Object?>{'cached': 4, 'total': 4});
    // 等待旧 Future 正常结束。
    await oldRequest;
    // 旧响应已失效，不能反向覆盖最新词库进度。
    expect(cache.cached, 1);
    expect(cache.total, 2);
  });
}
