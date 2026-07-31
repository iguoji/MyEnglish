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
///
/// @return void
///
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
      // 假原生返回初始 0/4，并接受 precache 与 clearAudioCache。
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCacheProgress') {
          return <String, Object?>{'cached': 0, 'total': 4};
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

      // 四个任务只成功一个但整批已结束，百分比必须是真实 25%，不能显示 100%。
      events.add(<String, Object?>{'cached': 1, 'total': 4, 'done': true});
      await Future<void>.delayed(Duration.zero);
      expect(cache.cached, 1);
      expect(cache.percent, 25);
      expect(cache.isCaching, isFalse);

      // 清空后重新装载词表并启动第二批。
      await cache.clearCacheFiles();
      await cache.setWordList(<String>['apple', 'banana']);
      cache.start();
      await Future<void>.delayed(Duration.zero);
      // 仍是同一个订阅；原生清空 EventSink 的旧实现会让这条路径断链。
      expect(listenCount, 1);

      // 原有订阅可以继续接收第二批事件。
      events.add(<String, Object?>{'cached': 2, 'total': 4, 'done': false});
      await Future<void>.delayed(Duration.zero);
      expect(cache.cached, 2);
      expect(cache.percent, 50);
      expect(cache.isCaching, isTrue);
    },
  );
}
