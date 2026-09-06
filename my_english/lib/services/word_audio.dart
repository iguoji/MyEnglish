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
  Future<void> play(String spelling, PronunciationAccent accent);

  ///
  /// 主动停止当前播放，例如页面销毁或 App 进入后台。
  Future<void> stop();

  ///
  /// 用“智能轮转”方式朗读一个单词（渠道挑选与记账都在原生完成）。
  ///
  /// 默认实现退化为普通 [play]，这样测试替身和旧实现无需逐个补方法也能编译；
  /// 生产实现（[LocalWordAudioPlayer]）会请求原生在“本周期未读且有缓存”的网络渠道
  /// 间点名播放，缺缓存的渠道后台并发补齐，全部不可用才由系统 TTS 最后兜底。
  /// 三个复习模块统一走本方法，反复点按重听时就能轮流听到不同来源的发音。
  Future<void> playRandomChannel(
    String spelling,
    PronunciationAccent accent,
  ) async {
    // 测试替身与旧实现仍按「固定渠道」行为播放，避免破坏现有用例。
    await play(spelling, accent);
  }

  ///
  /// 读取并消费最近一次播放是否由本地 TTS 完成。
  ///
  /// 测试替身和旧播放器默认返回 false；Android 原生实现返回本次 play 的真实来源。
  /// 页面据此只在当前页面第一次使用 TTS 时显示提示。
  Future<bool> consumeLastPlaybackUsedTts() async => false;

  ///
  /// 读取并消费最近一次播放的详细来源信息。
  ///
  /// 返回是否由本地 TTS 完成，以及本次是否来自轮转渠道播放。轮转渠道模式下 TTS
  /// 可能是被故意按顺序选中（而不是网络不可用的兜底），页面据此决定要不要提示
  /// “当前网络音频不可用”。
  ///
  /// 默认实现按“非 TTS、非轮转渠道”处理，测试替身和旧实现无需覆盖。
  ({bool usedTts, bool isRandomChannel}) consumeLastPlayback() {
    return (usedTts: false, isRandomChannel: false);
  }

  ///
  /// 显示或刷新锁屏/通知栏的媒体控制（标题=拼写，副标题=首条释义）。
  ///
  /// 默认空实现：只有 LocalWordAudioPlayer 会真正驱动 Android MediaSession；
  /// 测试替身沿用空实现，不会破坏现有用例。
  Future<void> showMediaSession(
    String spelling,
    String subtitle,
    bool isPlaying,
  ) async {}

  ///
  /// 仅更新播放/暂停状态（切换通知栏图标与 ongoing 标记）。
  Future<void> setMediaPlaying(bool isPlaying) async {}

  ///
  /// 收起锁屏/通知栏媒体控制并停用媒体会话。
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
  const WordAudioPlaybackException(this.message);

  ///
  /// 用户可见的播放错误说明。
  final String message;

  ///
  /// 输出简洁说明，避免提示显示“Instance of ...”。
  @override
  String toString() => message;
}

///
/// 设备没有可用的离线英语 TTS 引擎或语音数据。
///
/// 网络音频已经失败时，页面可以据此显示“需要联网或安装英语语音包”的提示。
///
class WordAudioTtsUnavailableException implements Exception {
  ///
  /// 保存原生层返回的用户可读原因。
  const WordAudioTtsUnavailableException(this.message);

  ///
  /// 用户可见的 TTS 不可用说明。
  final String message;

  ///
  /// 输出可直接展示的中文提示。
  @override
  String toString() => message;
}

///
/// 设备 TTS 引擎存在，但拒绝朗读当前单词。
///
class WordAudioTtsException implements Exception {
  ///
  /// 保存原生返回的用户可读原因。
  const WordAudioTtsException(this.message);

  ///
  /// 用户可见的 TTS 错误说明。
  final String message;

  ///
  /// 输出可直接展示的中文提示。
  @override
  String toString() => message;
}

///
/// 真正调用 Android MediaPlayer 的生产实现。
///
class LocalWordAudioPlayer implements WordAudioPlayer {
  ///
  /// 默认构造器使用与 MainActivity 一致的通道名。
  LocalWordAudioPlayer([
    this._channel = const MethodChannel('my_english/word_audio'),
  ]);

  ///
  /// 保存可注入通道，Widget/单元测试可以替换原生实现。
  final MethodChannel _channel;

  ///
  /// 最近一次已经完成的播放是否使用了本地 TTS。
  bool? _lastPlaybackUsedTts;

  /// 最近一次播放是否来自“智能轮转”请求（供页面判断 TTS 是网络兜底还是普通路径）。
  bool _playbackWasRandomChannel = false;

  ///
  /// 把拼写和口音发送给 Android；原生 Future 会持续到音频播放结束。
  ///
  /// 原生智能轮转会先挑“本周期未读且有本地缓存”的网络渠道播放；没有缓存就并发
  /// 后台补齐并等一个短暂窗口；全部不可用才走系统 TTS 兜底，渠道挑选不再由 Dart 完成。
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {
    // trim 防止数据源首尾空格进入 URL 和缓存文件名。
    await _invokePlay('playSmart', <String, Object?>{
      'spelling': spelling.trim(),
      // 使用稳定英文值区分美式与英式缓存目录。
      'accent': accent.storageValue,
    }, randomChannel: false);
  }

  ///
  /// 智能轮转请求朗读单词（轮转记账在原生，本方法只负责标记来源语义）。
  ///
  /// 三个复习模块反复重听时，原生按“不背单词 -> 百度翻译 -> 有道”的本周期已读
  /// 账本轮流点名，且始终限定在用户设置的口音之内，不擅自切换美式/英式。
  @override
  Future<void> playRandomChannel(
    String spelling,
    PronunciationAccent accent,
  ) async {
    // 与 [play] 同走原生智能轮转；randomChannel 标记让页面能区分 TTS 兜底场景。
    await _invokePlay('playSmart', <String, Object?>{
      // trim 防止数据源首尾空格进入 URL 和缓存文件名。
      'spelling': spelling.trim(),
      // 使用稳定英文值区分美式与英式缓存目录。
      'accent': accent.storageValue,
    }, randomChannel: true);
  }

  ///
  /// 通用播放调用：负责发送通道请求并统一转换原生错误。
  ///
  /// [method] 目前恒为 playSmart（渠道挑选已下沉原生）；[randomChannel] 标记本次
  /// 是否属于轮转请求，供消费播放来源时区分“TTS 是网络兜底还是故意点名”。
  Future<void> _invokePlay(
    String method,
    Map<String, Object?> args, {
    required bool randomChannel,
  }) async {
    // 新请求开始时丢弃上一条尚未消费的来源，避免异常流程遗留旧状态。
    _lastPlaybackUsedTts = null;
    try {
      // Map 是这次原生调用需要传递的参数集合。
      final usedTts = await _channel.invokeMethod<bool>(method, args);
      // Android 返回 true 表示本次由离线 TTS 完成，null 按网络 MP3 兼容处理。
      _lastPlaybackUsedTts = usedTts ?? false;
      // 记录本次调用方是否属于智能轮转请求，供页面判断 TTS 的出现语义。
      _playbackWasRandomChannel = randomChannel;
    } on PlatformException catch (error) {
      // 新单词替换旧播放不是用户可见错误，转换成专用异常供页面忽略。
      if (error.code == 'AUDIO_INTERRUPTED' || error.code == 'AUDIO_STOPPED') {
        throw const WordAudioInterruptedException();
      }
      // 原生已删除坏缓存，转换成专用异常供页面执行一次自动重新下载。
      if (error.code == 'AUDIO_PLAYBACK_FAILED') {
        throw WordAudioPlaybackException(error.message ?? '音频文件无法播放');
      }
      // 没有本地英语 TTS 时，提示用户联网播放或安装英语语音包。
      if (error.code == 'AUDIO_TTS_UNAVAILABLE') {
        throw WordAudioTtsUnavailableException(
          error.message ?? '当前设备没有可用的离线英语 TTS 引擎，请联网播放单词或安装英语语音包',
        );
      }
      // TTS 引擎拒绝朗读时，保留原生返回的可读错误。
      if (error.code == 'AUDIO_TTS_FAILED') {
        throw WordAudioTtsException(error.message ?? '设备 TTS 引擎无法朗读当前单词');
      }
      // 下载或播放失败保留原生具体信息，首页会转成 SnackBar。
      rethrow;
    }
  }

  ///
  /// Android 原生在 play Future 结束时把播放来源保存于通道结果；本方法读取该结果。
  @override
  Future<bool> consumeLastPlaybackUsedTts() async =>
      consumeLastPlayback().usedTts;

  ///
  /// 读取并消费最近一次播放的完整来源信息。
  ///
  /// [usedTts] 表示本次是否由本地 TTS 完成；[isRandomChannel] 表示是否来自轮转
  /// 渠道播放。读取一次后立即清空，避免下一次播放误继承上一次的状态。
  @override
  ({bool usedTts, bool isRandomChannel}) consumeLastPlayback() {
    final info = (
      usedTts: _lastPlaybackUsedTts ?? false,
      isRandomChannel: _playbackWasRandomChannel,
    );
    // 清空两个状态，保证只被消费一次。
    _lastPlaybackUsedTts = null;
    _playbackWasRandomChannel = false;
    return info;
  }

  ///
  /// 通知原生释放当前 MediaPlayer；没有播放时该操作也是安全的。
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
  @override
  Future<void> showMediaSession(
    String spelling,
    String subtitle,
    bool isPlaying,
  ) async {
    // Map 是这次原生调用需要传递的参数集合。
    await _channel.invokeMethod<void>('mediaSessionShow', <String, Object?>{
      'spelling': spelling,
      'subtitle': subtitle,
      'isPlaying': isPlaying,
    });
  }

  ///
  /// 仅把播放/暂停状态同步给原生，用于切换通知栏图标。
  @override
  Future<void> setMediaPlaying(bool isPlaying) async {
    await _channel.invokeMethod<void>(
      'mediaSessionSetPlaying',
      <String, Object?>{'isPlaying': isPlaying},
    );
  }

  ///
  /// 收起媒体控制；原生停用 MediaSession 并移除通知。
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
