// dart:async 提供 Future 与订阅所需的 StreamSubscription，支撑异步上报与后台监听。
import 'dart:async';

// material.dart 提供 ChangeNotifier，让抽屉的离线语音入口实时刷新百分比。
import 'package:flutter/material.dart';
// services.dart 提供 MethodChannel 与 EventChannel，分别用于触发预缓存和接收进度。
import 'package:flutter/services.dart';

///
/// 离线语音缓存进度服务（单例）。
///
/// 它只依赖 Android 原生层与独立的后台线程池，**不持有任何 Flutter Widget**，
/// 因此用户关闭抽屉、返回首页甚至切到其它页面后，批量缓存仍能在后台继续推进，
/// 百分比通过事件通道实时回传，重新打开抽屉即可看到最新进度。
///
/// 百分比口径与需求一致：总数 = 词库单词数；已缓存 = 至少有一个网络渠道同时
/// 拥有美式和英式有效 MP3 的单词数。
///
class WordAudioCache extends ChangeNotifier {
  ///
  /// 私有构造器；外部统一通过 [instance] 访问同一份缓存状态。
  WordAudioCache._(this._channel, this._progressEvents);

  ///
  /// 测试专用构造器：注入方法通道和进度流，不依赖 Android 插件。
  @visibleForTesting
  WordAudioCache.forTesting({
    required MethodChannel channel,
    required Stream<dynamic> progressEvents,
  }) : this._(channel, progressEvents);

  ///
  /// 与方法通道对应的事件通道名；必须与 MainActivity 注册值完全一致。
  static const String _eventChannelName = 'my_english/audio_cache';

  ///
  /// 音频方法通道名；与 MainActivity 注册值一致。
  static const String _methodChannelName = 'my_english/word_audio';

  ///
  /// App 级唯一实例；首页、抽屉与后台缓存任务共享同一份进度。
  static final WordAudioCache instance = WordAudioCache._(
    const MethodChannel(_methodChannelName),
    const EventChannel(_eventChannelName).receiveBroadcastStream(),
  );

  ///
  /// 缓存控制方法通道。
  final MethodChannel _channel;

  ///
  /// 进度事件流：生产环境来自 EventChannel，测试可注入可控 Stream。
  final Stream<dynamic> _progressEvents;

  ///
  /// 是否已订阅原生进度流；只订阅一次，避免重复监听导致重复计数。
  bool _subscribed = false;

  ///
  /// 已缓存单词数：该单词只要有一家渠道同时缓存了美式和英式，就计为 1。
  int _cached = 0;

  ///
  /// 需要统计的词库单词总数。
  int _total = 0;

  ///
  /// 是否正在后台预缓存（用于决定是否显示进度条）。
  bool _isCaching = false;

  ///
  /// 当前参与缓存的单词拼写列表（来自首页词库）。
  List<String> _spellings = const <String>[];

  ///
  /// 词库刷新请求代次；只有最后发起的一次原生查询可以更新当前进度。
  int _wordListGeneration = 0;

  ///
  /// 只读：已缓存数量。
  int get cached => _cached;

  ///
  /// 只读：需要缓存的总数。
  int get total => _total;

  ///
  /// 只读：是否正在后台预缓存。
  bool get isCaching => _isCaching;

  ///
  /// 缓存完成比例（0.0~1.0）；总数为 0 时返回 0 避免除零。
  double get ratio => _total == 0 ? 0.0 : _cached / _total;

  ///
  /// 已缓存百分比整数（0~100），供抽屉右侧展示。
  int get percent => (ratio * 100).round();

  ///
  /// 词库变化时（导入 / 新增 / 删除）刷新总数与已缓存数量。
  ///
  /// 向原生查询当前已缓存数；通道不可用（单元测试或异常环境）时安全回退为 0，
  /// 不让首页渲染因缓存探测失败而崩溃。
  Future<void> setWordList(List<String> spellings) async {
    // 复制调用方数组，避免外部后续原地修改影响正在运行的缓存任务。
    final snapshot = List<String>.unmodifiable(spellings);
    // 领取本次请求代次；后发请求会让此前仍在等待的请求自动失效。
    final generation = ++_wordListGeneration;
    // 记录参与缓存的单词，供 start() 触发预缓存使用。
    _spellings = snapshot;
    // 总数按“单词数”计算；一个单词不是拆成美式、英式两笔。
    _total = spellings.length;
    // 询问原生当前已缓存数量，得到真实的初始百分比。
    try {
      // 注意：原生 getCacheProgress 期望参数是一个 Map（键为 'spellings'），
      // 必须包装成 Map 而非直接传裸 List，否则 Kotlin 端 call.arguments as? Map
      // 会得到 null，把词表当成空、返回 {cached:0,total:0}，入口永远显示 0%。
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getCacheProgress',
        <String, Object?>{'spellings': snapshot},
      );
      // 等待期间词库已再次刷新时，旧结果不能覆盖新词库的进度。
      if (generation != _wordListGeneration) return;
      // 原生返回 {cached,total}，total 以原生实际计算为准（理论上等于单词数）。
      _cached = (result?['cached'] as num?)?.toInt() ?? 0;
      _total = (result?['total'] as num?)?.toInt() ?? _total;
    } on PlatformException {
      // 旧请求的异常同样不能把新请求已经得到的进度清零。
      if (generation != _wordListGeneration) return;
      // 通道异常（如真机尚未编译原生代码）时保守回退 0，不影响界面。
      _cached = 0;
    } on MissingPluginException {
      // 只处理当前仍有效的请求。
      if (generation != _wordListGeneration) return;
      // 单元测试无原生实现时同样回退 0。
      _cached = 0;
    }
    // 通知抽屉刷新百分比显示。
    notifyListeners();
  }

  ///
  /// 启动后台批量预缓存；已在进行中或词库为空时忽略重复点击。
  ///
  /// 已 100% 缓存完毕时也会直接返回，由调用方（抽屉入口）判断并提示用户，
  /// 避免进度条一闪而过造成"点了没反应"的错觉。
  void start() {
    // 已经在缓存则不再重复触发，避免重复创建任务。
    if (_isCaching) return;
    // 没有单词无需缓存。
    if (_spellings.isEmpty) return;
    // 已经全部缓存完毕（已缓存数达到总数）则无需再下载，直接跳过。
    if (_total > 0 && _cached >= _total) return;
    // 订阅原生进度流（全局只订阅一次）。
    _ensureSubscribed();
    // 立即进入缓存状态，抽屉下方出现进度条。
    _isCaching = true;
    // 通知界面显示进度条并锁定状态。
    notifyListeners();
    // 异步启动原生批量缓存；失败不影响界面，下次仍可在抽屉再次点击重试。
    unawaited(
      _channel
          .invokeMethod<void>('precache', <String, Object?>{
            'spellings': _spellings,
          })
          .catchError((Object error) {
            // 通道异常时结束缓存状态，避免进度条永远卡在"进行中"。
            _isCaching = false;
            // 把状态变化告知界面。
            notifyListeners();
          }),
    );
  }

  ///
  /// 清空全部离线语音缓存文件，并重置本地进度为 0。
  ///
  /// 由"清空数据"流程调用，确保删除本地单词时一并移除已下载的音频；
  /// 调用成功后抽屉入口百分比会回到 0%。通道不可用（测试/异常）时只重置本地状态。
  Future<void> clearCacheFiles() async {
    try {
      // 通知原生删除 word_audio 目录下的全部 mp3。
      final result = await _channel.invokeMethod<bool>('clearAudioCache');
      // 原生返回 false 时视为清空失败，不能把未删除的缓存显示成 0%。
      if (result == false) throw StateError('原生未确认离线语音缓存已清空');
    } on MissingPluginException {
      // 单元测试无原生实现时仍允许只重置测试内存状态。
    }
    // 重置本地进度显示，避免抽屉仍显示旧的百分比。
    _cached = 0;
    _total = 0;
    _isCaching = false;
    _spellings = const <String>[];
    // 通知界面刷新。
    notifyListeners();
  }

  ///
  /// 确保只订阅一次原生进度流。
  void _ensureSubscribed() {
    // 已经订阅过则直接返回，复用已有订阅。
    if (_subscribed) return;
    // 标记为已订阅，避免并发或重复点击时重复 listen。
    _subscribed = true;
    // 广播流在首次订阅后由原生 onListen 推送进度；由于本服务在 App 进程内长期
    // 持有该订阅、不会取消，所以即使用户关闭抽屉，后台进度仍持续回流。
    _progressEvents.listen(
      (dynamic event) {
        // event 是 Kotlin 推送的 Map：{cached,total,done}。
        if (event is! Map) return;
        // 取出原生上报的三个字段；缺省时沿用本地已有值，避免跳变。
        final cached = (event['cached'] as num?)?.toInt() ?? _cached;
        final total = (event['total'] as num?)?.toInt() ?? _total;
        final done = (event['done'] as bool?) ?? false;
        // 更新进度；只有"未完成且仍有差距"才保持在缓存中，否则收起进度条。
        _cached = cached;
        _total = total;
        _isCaching = !done && _cached < _total;
        // 通知抽屉刷新百分比与进度条。
        notifyListeners();
      },
      // 进度流异常时结束缓存状态，不让进度条卡住。
      onError: (Object error) {
        _isCaching = false;
        // 把状态变化告知界面。
        notifyListeners();
      },
    );
  }
}
