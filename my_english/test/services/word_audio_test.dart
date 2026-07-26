// services.dart 提供 MethodChannel、MethodCall 与 PlatformException。
import 'package:flutter/services.dart';
// flutter_test 提供测试消息通道和断言。
import 'package:flutter_test/flutter_test.dart';
// 引入 Dart 音频桥接实现。
import 'package:my_english/services/word_audio.dart';
// 引入口音枚举。
import 'package:my_english/store/settings.dart';

/// 验证页面参数正确发送给 Android 音频服务。
void main() {
  // 初始化测试二进制消息环境。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 使用测试专属通道。
  const channel = MethodChannel('test/word_audio');

  // 每项完成后移除 handler。
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 拼写会清理首尾空格，口音使用稳定原生值。
  test('play sends normalized spelling and selected accent', () async {
    // 保存原生收到的最后一次调用。
    MethodCall? receivedCall;
    // 假原生立即完成播放。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // 记录调用。
          receivedCall = call;
          // null 表示播放成功完成。
          return null;
        });
    // 通过可注入的测试通道创建播放器。
    const player = NativeWordAudioPlayer(channel);
    // 播放英式单词。
    await player.play('  ability  ', PronunciationAccent.british);
    // 方法名必须是 play。
    expect(receivedCall?.method, 'play');
    // 参数对应原生 Map。
    expect(receivedCall?.arguments, <String, Object?>{
      'spelling': 'ability',
      'accent': 'british',
    });
  });

  // 新请求中断旧播放不应被首页当作音源失败。
  test('native interruption becomes a dedicated exception', () async {
    // 假原生返回约定中断码。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // 与 Android WordAudioPlayer.interruptCurrent 保持一致。
          throw PlatformException(code: 'AUDIO_INTERRUPTED');
        });
    // 创建播放器。
    const player = NativeWordAudioPlayer(channel);
    // Dart 层转换成专用可忽略异常。
    await expectLater(
      player.play('ability', PronunciationAccent.american),
      throwsA(isA<WordAudioInterruptedException>()),
    );
  });
}
