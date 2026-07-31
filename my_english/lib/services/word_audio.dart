// services.dart 提供 MethodChannel 与 PlatformException，用于调用 Android 原生播放器。
import 'package:flutter/services.dart';

// 口音枚举属于全局设置模型，音频服务和任何页面都可以共同使用。
import '../store/settings.dart';

///
/// 页面依赖的音频接口；未来循环播放页和测试替身都可以复用这份约定。
///
abstract interface class WordAudioPlayer {
  ///
  /// 播放一个单词，并在音频完成、失败或被新播放替换时结束 Future。
  ///
  /// @param  String  spelling
  /// @param  PronunciationAccent  accent
  /// @return `Future<void>`
  ///
  Future<void> play(String spelling, PronunciationAccent accent);

  ///
  /// 主动停止当前播放，例如页面销毁或 App 进入后台。
  ///
  /// @return `Future<void>`
  ///
  Future<void> stop();
}

///
/// 新播放请求替换旧请求时使用的内部异常，页面无需向用户提示。
///
class WordAudioInterruptedException implements Exception {
  ///
  /// const 异常没有额外状态，可以被重复使用。
  ///
  const WordAudioInterruptedException();
}

///
/// 真正调用 Android MediaPlayer 的生产实现。
///
class NativeWordAudioPlayer implements WordAudioPlayer {
  ///
  /// 默认构造器使用与 MainActivity 一致的通道名。
  ///
  /// @param  MethodChannel  _channel
  ///
  const NativeWordAudioPlayer([
    this._channel = const MethodChannel('my_english/word_audio'),
  ]);

  ///
  /// 保存可注入通道，Widget/单元测试可以替换原生实现。
  ///
  /// @var MethodChannel
  ///
  final MethodChannel _channel;

  ///
  /// 把拼写和口音发送给 Android；原生 Future 会持续到音频播放结束。
  ///
  /// @param  String  spelling
  /// @param  PronunciationAccent  accent
  /// @return `Future<void>`
  ///
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {
    try {
      // Map 类似小程序调用插件时传入的 options 对象。
      await _channel.invokeMethod<void>('play', <String, Object?>{
        // trim 防止数据源首尾空格进入 URL 和缓存文件名。
        'spelling': spelling.trim(),
        // 使用稳定英文值区分美式与英式缓存目录。
        'accent': accent.storageValue,
      });
    } on PlatformException catch (error) {
      // 新单词替换旧播放不是用户可见错误，转换成专用异常供页面忽略。
      if (error.code == 'AUDIO_INTERRUPTED' || error.code == 'AUDIO_STOPPED') {
        throw const WordAudioInterruptedException();
      }
      // 下载或播放失败保留原生具体信息，首页会转成 SnackBar。
      rethrow;
    }
  }

  ///
  /// 通知原生释放当前 MediaPlayer；没有播放时该操作也是安全的。
  ///
  /// @return `Future<void>`
  ///
  @override
  Future<void> stop() async {
    try {
      // stop 不需要参数。
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      // 页面正在退出时，停止已结束的播放不应制造额外未处理异常。
      if (error.code != 'AUDIO_STOPPED') rethrow;
    }
  }
}
