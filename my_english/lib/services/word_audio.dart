// services.dart 提供 MethodChannel 与 PlatformException，用于调用 Android 原生播放器。
import 'package:flutter/services.dart';

// 口音枚举属于全局设置模型，音频服务和任何页面都可以共同使用。
import '../store/settings.dart';

///
/// 页面依赖的音频接口；未来循环播放页和测试替身都可以复用这份约定。
///
/// 改为普通 abstract class（而非 abstract interface class），是为了给锁屏/通知栏
/// 媒体控制提供“空默认实现”：老测试替身只实现 play/stop 即可，无需逐个补方法。
///
abstract class WordAudioPlayer {
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

  ///
  /// 显示或刷新锁屏/通知栏的媒体控制（标题=拼写，副标题=首条释义）。
  ///
  /// 默认空实现：只有 NativeWordAudioPlayer 会真正驱动 Android MediaSession；
  /// 测试替身沿用空实现，不会破坏现有用例。
  ///
  /// @param  String  spelling 当前单词拼写。
  /// @param  String  subtitle 副标题（通常为第一条释义）。
  /// @param  bool  isPlaying 当前是否处于播放状态。
  /// @return `Future<void>`
  ///
  Future<void> showMediaSession(
    String spelling,
    String subtitle,
    bool isPlaying,
  ) async {}

  ///
  /// 仅更新播放/暂停状态（切换通知栏图标与 ongoing 标记）。
  ///
  /// @param  bool  isPlaying 当前是否处于播放状态。
  /// @return `Future<void>`
  ///
  Future<void> setMediaPlaying(bool isPlaying) async {}

  ///
  /// 收起锁屏/通知栏媒体控制并停用媒体会话。
  ///
  /// @return `Future<void>`
  ///
  Future<void> releaseMediaSession() async {}
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
/// 音频缓存解码失败时使用的可重试异常。
///
/// 原生层已经删除损坏缓存；页面收到后可以再次调用 play，让播放器重新下载。
///
class WordAudioPlaybackException implements Exception {
  ///
  /// 保存原生返回的可读错误。
  ///
  /// @param  String  message 原生播放错误说明。
  ///
  const WordAudioPlaybackException(this.message);

  ///
  /// 用户可见的播放错误说明。
  ///
  /// @var String
  ///
  final String message;

  ///
  /// 输出简洁说明，避免提示显示“Instance of ...”。
  ///
  /// @return String
  ///
  @override
  String toString() => message;
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
      // 原生已删除坏缓存，转换成专用异常供页面执行一次自动重新下载。
      if (error.code == 'AUDIO_PLAYBACK_FAILED') {
        throw WordAudioPlaybackException(error.message ?? '音频文件无法播放');
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

  ///
  /// 显示/刷新锁屏与通知栏的媒体控制；原生据此创建 Android MediaSession 与通知。
  ///
  /// @param  String  spelling 当前单词拼写（通知标题）。
  /// @param  String  subtitle 首条释义（通知副标题）。
  /// @param  bool  isPlaying 当前是否正在播放。
  /// @return `Future<void>`
  ///
  @override
  Future<void> showMediaSession(
    String spelling,
    String subtitle,
    bool isPlaying,
  ) async {
    // Map 类似小程序调用插件时传入的 options 对象。
    await _channel.invokeMethod<void>('mediaSessionShow', <String, Object?>{
      'spelling': spelling,
      'subtitle': subtitle,
      'isPlaying': isPlaying,
    });
  }

  ///
  /// 仅把播放/暂停状态同步给原生，用于切换通知栏图标。
  ///
  /// @param  bool  isPlaying 当前是否正在播放。
  /// @return `Future<void>`
  ///
  @override
  Future<void> setMediaPlaying(bool isPlaying) async {
    await _channel.invokeMethod<void>(
      'mediaSessionSetPlaying',
      <String, Object?>{'isPlaying': isPlaying},
    );
  }

  ///
  /// 收起媒体控制；原生停用 MediaSession 并移除通知。
  ///
  /// @return `Future<void>`
  ///
  @override
  Future<void> releaseMediaSession() async {
    await _channel.invokeMethod<void>('mediaSessionRelease');
  }

  ///
  /// 注册“原生→Dart”的媒体控制回调。
  ///
  /// 锁屏、通知栏按钮或蓝牙耳机上的播放/暂停/上一首/下一首，最终都会由原生
  /// MediaSession 通过本通道回传一个字符串动作（play/pause/next/previous/stop），
  /// Dart 侧（随身听页）据此控制播放。传 null 可注销回调（页面销毁时调用）。
  ///
  /// 复用音频通道名，但方向相反：这里接收原生发来的事件。
  ///
  /// @param  `Future<dynamic>? Function(String action)?`  handler 动作回调。
  /// @return void
  ///
  static void setMediaControlHandler(
    Future<dynamic>? Function(String action)? handler,
  ) {
    // 同一通道同一名字，Dart 侧这里只接收原生主动发来的调用。
    const MethodChannel('my_english/word_audio').setMethodCallHandler((
      call,
    ) async {
      // 只处理媒体控制事件；其他方法调用（若有）忽略。
      if (call.method != 'mediaControl') return;
      // 取出动作字符串；缺失时按空串处理，避免崩溃。
      final action =
          (call.arguments as Map<dynamic, dynamic>?)?['action'] as String? ??
          '';
      // 回调可能为空（已注销），为空时直接忽略原生事件。
      await handler?.call(action);
    });
  }
}
