// services.dart 提供 MethodChannel、MethodCall 与 PlatformException。
import 'package:flutter/services.dart';
// flutter_test 提供测试消息通道和断言。
import 'package:flutter_test/flutter_test.dart';
// 引入 Dart 音频桥接实现。
import 'package:my_english/services/word_audio.dart';
// 引入口音枚举。
import 'package:my_english/store/settings.dart';

///
/// 验证页面参数正确发送给 Android 音频服务。
///
/// @return void
///
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
    final player = NativeWordAudioPlayer(channel);
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

  // Android 返回 true 时，Dart 必须识别本次由 TTS 完成，且读取一次后立即消费。
  test('consumes the latest TTS playback source once', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    final player = NativeWordAudioPlayer(channel);

    await player.play('ability', PronunciationAccent.american);

    expect(await player.consumeLastPlaybackUsedTts(), isTrue);
    expect(await player.consumeLastPlaybackUsedTts(), isFalse);
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
    final player = NativeWordAudioPlayer(channel);
    // Dart 层转换成专用可忽略异常。
    await expectLater(
      player.play('ability', PronunciationAccent.american),
      throwsA(isA<WordAudioInterruptedException>()),
    );
  });

  // 原生发现坏缓存并删除后，Dart 必须把它标记成可重试的播放异常。
  test('native playback failure becomes a retryable exception', () async {
    // 假原生返回与 MediaPlayer onError 一致的协议码和可读说明。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'AUDIO_PLAYBACK_FAILED',
            message: '音频文件无法解码，已清除缓存',
          );
        });
    // 创建使用测试通道的播放器。
    final player = NativeWordAudioPlayer(channel);
    // 页面应收到专用异常，且字符串就是可直接展示的中文原因。
    await expectLater(
      player.play('forest', PronunciationAccent.american),
      throwsA(
        isA<WordAudioPlaybackException>().having(
          (error) => error.toString(),
          'message',
          contains('已清除缓存'),
        ),
      ),
    );
  });

  // 没有本地英语 TTS 时，页面必须收到可直接展示的中文提示。
  test('native unavailable TTS becomes a user-readable exception', () async {
    // 假原生返回 TTS 能力不可用协议码。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'AUDIO_TTS_UNAVAILABLE',
            message: '当前设备没有可用的离线英语 TTS 引擎',
          );
        });
    // 创建播放器。
    final player = NativeWordAudioPlayer(channel);
    // Dart 层转换成专用异常，页面可以显示联网或安装语音包提示。
    await expectLater(
      player.play('forest', PronunciationAccent.american),
      throwsA(
        isA<WordAudioTtsUnavailableException>().having(
          (error) => error.toString(),
          'message',
          contains('离线英语 TTS'),
        ),
      ),
    );
  });

  // TTS 引擎拒绝朗读时，Dart 层不能把它误报成网络下载失败。
  test('native TTS failure becomes a dedicated exception', () async {
    // 假原生返回 TTS 播放失败协议码。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'AUDIO_TTS_FAILED',
            message: '设备 TTS 引擎无法朗读当前单词',
          );
        });
    // 创建播放器。
    final player = NativeWordAudioPlayer(channel);
    // Dart 层转换成专用异常，便于页面按 TTS 失败处理。
    await expectLater(
      player.play('forest', PronunciationAccent.american),
      throwsA(
        isA<WordAudioTtsException>().having(
          (error) => error.toString(),
          'message',
          contains('TTS 引擎'),
        ),
      ),
    );
  });
}
