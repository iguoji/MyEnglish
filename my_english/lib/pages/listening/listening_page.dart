// dart:async 提供 Future、Timer 与 unawaited，负责播放循环和倒计时。
import 'dart:async';

// material.dart 提供页面、列表、底部面板和动画等基础组件。
import 'package:flutter/material.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局设计令牌。
import '../../common/theme.dart';
// 引入全局 Toast 工具，层级高于 BottomSheet。
import '../../common/toast.dart';
// 引入单词数据模型。
import '../../models/word.dart';
// 引入可替换的单词发音服务。
import '../../services/word_audio.dart';
// 引入口音设置。
import '../../store/settings.dart';
// 引入答案卡正文组件。
import 'widgets/listening_answer_content.dart';
// 引入搜索框、图标按钮、设置行和播放控制按钮。
import 'widgets/listening_controls.dart';
// 引入集中管理的页面布局尺寸。
import 'widgets/listening_layout.dart';

/// 随身听全屏页面。
///
/// 页面结构为：顶部进度、可搜索跳转的播放列表、隐藏答案卡、
/// 上一个/播放/下一个控制，以及播放次数、间隔和循环设置面板。
class ListeningPage extends StatefulWidget {
  /// 创建随身听页面；首页必须提供至少一个单词以及可替换的播放器。
  const ListeningPage({
    required this.words,
    required this.audioPlayer,
    required this.accent,
    this.definitionSeparator = '、',
    super.key,
  }) : assert(words.length > 0, '随身听至少需要一个单词');

  /// 首页按“已勾选优先，否则当前可见”规则传入的学习列表。
  final List<Word> words;

  /// 与首页共用音频服务，测试时可以注入内存替身。
  final WordAudioPlayer audioPlayer;

  /// 当前设置中的美式或英式口音。
  final PronunciationAccent accent;

  /// 同一词性下多条中文释义之间使用的全角分隔符。
  final String definitionSeparator;

  /// StatefulWidget 把会变化的数据交给独立 State，类似小程序 Page 的 data 与方法集合。
  @override
  State<ListeningPage> createState() => _ListeningPageState();
}

/// 随身听页面状态，集中管理播放流程、搜索条件和所有用户交互。
class _ListeningPageState extends State<ListeningPage> {
  // 播放列表滚动控制器，用于把当前单词自动滚动到中间。
  final ScrollController _listController = ScrollController();
  // 搜索框控制器保存用户输入。
  final TextEditingController _queryController = TextEditingController();

  // 当前播放下标。
  int _index = 0;
  // 当前单词已经完成的播放轮数。
  int _completedRepeats = 0;
  // 两次播放之间剩余秒数。
  int _remainingSeconds = 2;
  // 默认自动播放。
  bool _isPlaying = true;
  // 非循环模式走到末尾后显示“已播完”。
  bool _isFinished = false;
  // 是否永久显示答案。
  bool _revealAll = false;
  // 是否正在按住答案卡临时查看。
  bool _isPeeking = false;
  // 播放次数边界与原型一致，为 1 到 9。
  int _repeat = 2;
  // 播放间隔边界与原型一致，为 1 到 10 秒。
  int _interval = 2;
  // 默认循环整个列表。
  bool _loop = true;
  // 搜索文本只用于过滤上方列表，不改变真实播放顺序。
  String _query = '';
  // 每次暂停、跳转或退出都会增加序号，使旧异步循环自动失效。
  int _playSerial = 0;
  // 可取消的一秒计时器；相比 Future.delayed，页面销毁时不会遗留测试计时器。
  Timer? _countdownTimer;
  // 当前一秒等待的完成器，取消时主动完成以唤醒旧循环。
  Completer<void>? _countdownCompleter;

  /// 根据当前下标读取正在播放的单词，类似 PHP 数组 `$words[$index]`。
  Word get _currentWord => widget.words[_index];

  /// 页面状态第一次创建时执行一次初始化。
  @override
  void initState() {
    // 先让 Flutter 完成 State 基础初始化。
    super.initState();
    // 第一帧完成后再开始播放，避免初始化阶段直接调用原生通道。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 页面可能在第一帧回调前已退出，mounted=false 时不能再更新界面。
      if (!mounted) return;
      // 启动第一个单词的播放循环。
      _startPlaybackLoop();
      // 首次进入不等待普通滚动动画，较快地把当前行移到列表中间。
      _centerCurrentWord(force: true);
    });
  }

  /// 启动一个新的异步播放循环。
  void _startPlaybackLoop() {
    // 新序号会让旧循环在下一次检查时退出。
    final serial = ++_playSerial;
    // 不阻塞界面线程，异步执行“发音 → 间隔 → 推进”流程。
    unawaited(_runPlayback(serial));
  }

  /// 按真实音频完成时间执行循环，避免固定 Timer 截断较长发音。
  Future<void> _runPlayback(int serial) async {
    // while 对应 PHP 中持续执行的任务循环；三项条件任一失效就停止。
    while (mounted && serial == _playSerial && _isPlaying) {
      // 音频调用可能被用户中断或因网络失败抛出异常。
      try {
        // 播放当前拼写；Future 在原生音频结束后完成。
        await widget.audioPlayer.play(_currentWord.spelling, widget.accent);
      } on WordAudioInterruptedException {
        // 用户暂停或跳转时 stop 会中断音频，这是正常控制流程。
      } catch (error) {
        // 网络或原生播放器失败时暂停，并保留具体错误给用户。
        if (!mounted || serial != _playSerial) return;
        // setState 类似小程序 setData，修改后会重绘播放按钮和状态文字。
        setState(() => _isPlaying = false);
        // Toast 以非阻塞方式显示具体失败原因，层级高于 BottomSheet。
        Toast.show(context, '播放失败：$error');
        // 当前循环已经失败，不能继续倒计时或推进单词。
        return;
      }
      // 音频期间发生暂停、跳转或退出时，旧循环直接结束。
      if (!mounted || serial != _playSerial || !_isPlaying) return;

      // 每次发音结束后执行可见倒计时。
      for (var second = _interval; second > 0; second--) {
        // 每一秒开始前再次确认任务没有被新操作取消。
        if (!mounted || serial != _playSerial || !_isPlaying) return;
        // 把当前剩余秒数同步到播放列表状态文字。
        setState(() => _remainingSeconds = second);
        // 等待一秒；暂停操作可以主动提前结束这次等待。
        await _waitOneSecond();
      }
      // 倒计时结束后仍需确认当前循环没有过期。
      if (!mounted || serial != _playSerial || !_isPlaying) return;

      // 当前单词完成一次播放。
      _completedRepeats++;
      // 达到用户设置的次数后才推进到下一个单词。
      if (_completedRepeats >= _repeat) {
        // 播放次数达标后切到下一个单词。
        _completedRepeats = 0;
        // 普通情况直接进入列表中的下一项。
        if (_index + 1 < widget.words.length) {
          // 一次 setState 同时更新下标和倒计时，避免中间状态被绘制出来。
          setState(() {
            _index++;
            _remainingSeconds = _interval;
          });
          // 新单词出现后把它滚动到播放列表中部。
          _centerCurrentWord();
        } else if (_loop) {
          // 循环模式从头开始。
          setState(() {
            _index = 0;
            _remainingSeconds = _interval;
          });
          // 回到首词后同步滚动列表。
          _centerCurrentWord();
        } else {
          // 非循环模式停在最后一个单词。
          setState(() {
            _isPlaying = false;
            _isFinished = true;
            _remainingSeconds = 0;
          });
          // 已播完且不循环，结束异步任务。
          return;
        }
      } else {
        // 同一个词继续下一轮播放。
        setState(() => _remainingSeconds = _interval);
      }
    }
  }

  /// 等待一秒，但允许暂停、跳转和 dispose 立即取消。
  Future<void> _waitOneSecond() {
    // 创建新等待前先清理旧 Timer，确保任意时刻最多只有一个计时器。
    _cancelCountdown();
    // Completer 类似手动控制完成时机的 Promise。
    final completer = Completer<void>();
    // 保存引用后，暂停方法可以提前完成这个 Promise。
    _countdownCompleter = completer;
    // Timer 到一秒后完成 Promise，让播放循环继续。
    _countdownTimer = Timer(const Duration(seconds: 1), () {
      // 已被暂停操作完成过时不能重复 complete。
      if (!completer.isCompleted) completer.complete();
      // 只有当前保存的仍是本次任务时才清空字段，避免覆盖更新的 Timer。
      if (identical(_countdownCompleter, completer)) {
        _countdownCompleter = null;
        _countdownTimer = null;
      }
    });
    // 把可等待的 Future 返回给播放循环。
    return completer.future;
  }

  /// 取消尚未结束的倒计时，并让等待它的旧循环立刻继续到序号检查处。
  void _cancelCountdown() {
    // 停止系统 Timer，防止稍后重复触发回调。
    _countdownTimer?.cancel();
    // 清空字段表示当前没有活动计时器。
    _countdownTimer = null;
    // 临时保存 Completer，因为字段随后要先清空。
    final completer = _countdownCompleter;
    // 先断开全局引用，避免完成回调误认为它仍是当前任务。
    _countdownCompleter = null;
    // 主动完成等待，使旧播放循环立即进入序号检查并退出。
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// 暂停当前音频并使旧循环失效。
  Future<void> _pausePlayback() async {
    // 序号递增后，旧 _runPlayback 会在下一处检查直接返回。
    ++_playSerial;
    // 同时结束仍在进行的一秒倒计时。
    _cancelCountdown();
    // 先更新按钮和状态文字，让用户立即看到暂停结果。
    setState(() => _isPlaying = false);
    // 原生 stop 可能失败，因此使用 try/catch 隔离底层异常。
    try {
      // 等待原生播放器真正停止。
      await widget.audioPlayer.stop();
    } catch (error) {
      // 控制动作失败不阻塞页面，只在调试控制台保留诊断。
      debugPrint('暂停随身听失败：$error');
    }
  }

  /// 播放/暂停主按钮。
  void _togglePlayback() {
    // “已播完”状态再次点击时从第一个单词重新开始。
    if (_isFinished) {
      // 一次性恢复全部播放状态。
      setState(() {
        _index = 0;
        _completedRepeats = 0;
        _remainingSeconds = _interval;
        _isFinished = false;
        _isPlaying = true;
      });
      // 把首词滚到中间。
      _centerCurrentWord(force: true);
      // 创建新的异步播放任务。
      _startPlaybackLoop();
      // 重播分支结束，避免继续执行普通暂停/播放判断。
      return;
    }
    // 正在播放时执行异步暂停。
    if (_isPlaying) {
      unawaited(_pausePlayback());
    } else {
      // 暂停状态点击后先切回播放图标状态。
      setState(() => _isPlaying = true);
      // 再启动新的播放循环。
      _startPlaybackLoop();
    }
  }

  /// 跳到指定位置并从该词第一轮重新开始。
  void _jumpTo(int index) {
    // 让旧播放循环失效。
    ++_playSerial;
    // 立即取消旧倒计时。
    _cancelCountdown();
    // 停止旧音频；控制动作失败不影响跳词界面。
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    // 更新当前单词及其关联状态。
    setState(() {
      // clamp 类似 PHP min/max 组合，保证下标永远位于列表范围内。
      _index = index.clamp(0, widget.words.length - 1);
      // 新单词从第 1 次播放重新计数。
      _completedRepeats = 0;
      // 重置间隔倒计时。
      _remainingSeconds = _interval;
      // 清除上一轮的结束标记。
      _isFinished = false;
      // 跳词后退出搜索结果，恢复完整播放列表。
      _query = '';
      // 同步清空 TextField 中实际显示的文字。
      _queryController.clear();
    });
    // 把新单词滚动到列表中部。
    _centerCurrentWord(force: true);
    // 原本处于播放状态时才自动续播，暂停状态保持暂停。
    if (_isPlaying) _startPlaybackLoop();
  }

  /// 自动把当前项滚动到列表中部。
  void _centerCurrentWord({bool force = false}) {
    // 等当前帧完成列表布局后，ScrollController 才能读取准确尺寸。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 页面已退出或列表尚未绑定时不执行滚动。
      if (!mounted || !_listController.hasClients) return;
      // 当前行中心 = 行起点 + 半个统一行高，不再复制写死的 32 和 16。
      final currentRowCenter =
          _index * ListeningLayout.playlistRowHeight +
          ListeningLayout.playlistRowHeight / 2;
      // 目标滚动距离让当前行中心对齐可视区域中心，并限制在合法范围。
      final target =
          (currentRowCenter - _listController.position.viewportDimension / 2)
              .clamp(0.0, _listController.position.maxScrollExtent);
      // 使用平滑动画移动到计算后的目标位置。
      _listController.animateTo(
        target,
        // 首次或主动跳词使用较快动画，自动播放推进使用普通动画。
        duration: Duration(milliseconds: force ? 180 : 260),
        // easeOut 让滚动在接近目标时自然减速。
        curve: Curves.easeOut,
      );
    });
  }

  /// 打开与原型一致的底部播放设置。
  Future<void> _openSettings() async {
    // showModalBottomSheet 类似小程序从底部弹出的自定义 action-sheet。
    await showModalBottomSheet<void>(
      // 使用当前页面 Navigator 管理弹出与关闭。
      context: context,
      // 外层设为透明，真正背景和圆角由内部容器绘制。
      backgroundColor: Colors.transparent,
      // 允许面板根据内容和安全区决定高度。
      isScrollControlled: true,
      // builder 在独立路由中创建设置面板。
      builder: (sheetContext) => StatefulBuilder(
        // StatefulBuilder 提供面板自己的 setSheetState，类似局部 setData。
        builder: (sheetContext, setSheetState) {
          // 设置面板也必须读取当前亮色或深色主题。
          final tokens = AppTokens.of(sheetContext);
          // 同时刷新面板和背后的播放页。
          void update(VoidCallback change) {
            // 更新页面长期保存的播放设置。
            setState(change);
            // 再通知当前弹层路由立即重绘控件值。
            setSheetState(() {});
          }

          // Container 绘制底部面板背景、圆角和安全区留白。
          return Container(
            // Key 类似小程序容器的 id，让测试能以面板自身边界核对右对齐。
            key: const Key('listening-settings-sheet'),
            // 底部额外叠加系统安全区，避免开关被手势条遮挡。
            padding: EdgeInsets.fromLTRB(
              0,
              16,
              0,
              20 + MediaQuery.paddingOf(sheetContext).bottom,
            ),
            // BoxDecoration 对应 WXSS 中的 background 与 border-radius。
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            // Column 依次放置标题、播放次数、间隔和循环设置。
            child: Column(
              // 面板高度只包住实际内容。
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题行使用与页面一致的 20 像素左右边距。
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  // Row 让“设置”和“完成”分列左右两端。
                  child: Row(
                    children: [
                      // 左侧面板标题。
                      Text(
                        '设置',
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Spacer 占满中间空间，把完成按钮推到右侧。
                      const Spacer(),
                      // InkWell 只包住可见文字，不像 TextButton 默认在文字左右添加内边距。
                      InkWell(
                        // Key 类似小程序节点的 id，供测试准确读取“完成”的位置。
                        key: const Key('listening-settings-done'),
                        // 点击“完成”后关闭当前底部设置面板。
                        onTap: () => Navigator.pop(sheetContext),
                        // 纯文字操作不显示 Material 默认的按压底色。
                        overlayColor: const WidgetStatePropertyAll<Color>(
                          Colors.transparent,
                        ),
                        // 关闭水波纹，让交互样式与首页设置面板保持一致。
                        splashFactory: NoSplash.splashFactory,
                        // 文字右边缘会直接落在标题行的 20 像素右边距上。
                        child: const Text(
                          '完成',
                          style: TextStyle(
                            color: AppTokens.accent,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 第一行控制每个单词重复播放次数。
                ListeningSettingRow(
                  label: '播放次数',
                  value: _repeat,
                  // 已到最小值时传 null，按钮会自动进入禁用色。
                  onMinus: _repeat > 1 ? () => update(() => _repeat--) : null,
                  // 已到最大值时同样禁止继续增加。
                  onPlus: _repeat < 9 ? () => update(() => _repeat++) : null,
                ),
                // 第二行控制两次发音之间的秒数。
                ListeningSettingRow(
                  label: '播放间隔(秒)',
                  value: _interval,
                  onMinus: _interval > 1
                      ? () => update(() {
                          // 先减少用户配置的间隔。
                          _interval--;
                          // 正在显示的剩余秒数不能大于新的间隔。
                          _remainingSeconds = _remainingSeconds.clamp(
                            0,
                            _interval,
                          );
                        })
                      : null,
                  onPlus: _interval < 10
                      ? () => update(() => _interval++)
                      : null,
                ),
                // 第三行是简单的开关，因此直接使用固定高容器。
                SizedBox(
                  height: ListeningLayout.settingsRowHeight,
                  // 左右留白与上面两行一致。
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    // Row 将标签和 Switch 放在两侧。
                    child: Row(
                      children: [
                        // 开关标签。
                        Text(
                          '列表循环',
                          style: TextStyle(color: tokens.text, fontSize: 14.5),
                        ),
                        // 占满中间区域。
                        const Spacer(),
                        // Switch 对应小程序 switch，变化后更新页面和面板两处状态。
                        Switch(
                          key: const Key('listening-loop-switch'),
                          value: _loop,
                          onChanged: (value) => update(() => _loop = value),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 页面退出时释放所有计时器、原生播放任务和输入控制器。
  @override
  void dispose() {
    // 结束所有旧循环并停止仍在播放的原生音频。
    ++_playSerial;
    // 取消当前一秒等待。
    _cancelCountdown();
    // 通知原生播放器停止；dispose 不能 await，因此忽略返回 Future。
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    // 释放列表滚动控制器。
    _listController.dispose();
    // 释放搜索输入控制器。
    _queryController.dispose();
    // 最后交给父类完成 Flutter 自身资源清理。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // tokens 相当于小程序从全局主题 Store 读取当前页面颜色变量。
    final tokens = AppTokens.of(context);
    // 当前下标从 0 开始，因此加 1 后再除以总数得到进度条需要的 0～1 比例。
    final progress = (_index + 1) / widget.words.length;
    // 搜索统一忽略首尾空格和英文大小写。
    final normalizedQuery = _query.trim().toLowerCase();
    // record 同时保存原列表下标和单词，过滤后点击仍能跳回真实播放位置。
    final filtered = <({int index, Word word})>[
      // 遍历父页面传入的完整播放列表。
      for (var index = 0; index < widget.words.length; index++)
        // 没有关键词时全部保留，否则只保留拼写中包含关键词的单词。
        if (normalizedQuery.isEmpty ||
            widget.words[index].spelling.toLowerCase().contains(
              normalizedQuery,
            ))
          // 把真实下标和当前单词一起放进过滤结果。
          (index: index, word: widget.words[index]),
    ];
    // “常显”或“手指正在按住”任一条件成立时都展示真实答案。
    final showAnswer = _revealAll || _isPeeking;

    // Scaffold 对应小程序页面最外层容器，负责整页背景。
    return Scaffold(
      // 页面背景跟随亮色或深色主题。
      backgroundColor: tokens.page,
      // SafeArea 自动避开刘海、状态栏和系统手势区。
      body: SafeArea(
        // 页面从上到下依次排列顶栏、播放列表、答案卡和播放控制区。
        child: Column(
          children: [
            // 顶栏和进度条属于同一信息区，由独立方法维护其布局约束。
            _buildHeader(tokens, progress),
            // 播放列表卡片负责搜索、快速滚动和单词跳转。
            _buildPlaylistCard(tokens, filtered),
            // Expanded 让答案卡占用除固定区域外的剩余高度。
            Expanded(child: _buildAnswerCard(tokens, showAnswer)),
            // 底部控制区负责上一个、播放暂停和下一个。
            _buildPlaybackControls(tokens),
            // 给系统底部手势区域上方保留固定呼吸空间。
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  /// 构建顶栏和播放进度，类似小程序页面中的 navigation 区域。
  Widget _buildHeader(AppTokens tokens, double progress) {
    // Column 让按钮标题行与进度条垂直排列。
    return Column(
      // mainAxisSize.min 表示只占自身内容高度，不抢答案卡的剩余空间。
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶栏左右边距由统一布局常量控制。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ListeningLayout.pageInset,
            ListeningLayout.headerTop,
            ListeningLayout.pageInset,
            0,
          ),
          // Row 对应小程序 flex 横向布局。
          child: Row(
            children: [
              // 返回按钮的点击画布直接贴在 20 像素页面边界，不做任何负偏移。
              ListeningIconButton(
                key: const Key('close-listening'),
                icon: TablerIcons.chevronLeft,
                alignment: Alignment.centerLeft,
                onTap: () => Navigator.pop(context),
              ),
              // Expanded 吃掉中间空间，让标题相对两个等宽按钮保持绝对居中。
              Expanded(
                child: Text(
                  '${_index + 1} / ${widget.words.length}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // 设置按钮使用与返回按钮相同画布，并把图标画布对齐右边界。
              ListeningIconButton(
                key: const Key('open-listening-settings'),
                icon: TablerIcons.settings,
                alignment: Alignment.centerRight,
                onTap: _openSettings,
              ),
            ],
          ),
        ),
        // 进度条与顶栏共享相同左右边界。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ListeningLayout.pageInset,
            ListeningLayout.progressTop,
            ListeningLayout.pageInset,
            0,
          ),
          // ClipRRect 只负责把进度条两端裁成轻微圆角。
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: ListeningLayout.progressHeight,
              backgroundColor: tokens.sub,
              color: AppTokens.accent,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建搜索与播放列表卡片，对应小程序页面中的独立 list-card 组件。
  Widget _buildPlaylistCard(
    AppTokens tokens,
    List<({int index, Word word})> filtered,
  ) {
    // Container 同时确定卡片尺寸、外边距和边框。
    return Container(
      key: const Key('listening-playlist-card'),
      height: ListeningLayout.playlistHeight,
      margin: const EdgeInsets.fromLTRB(
        ListeningLayout.pageInset,
        ListeningLayout.sectionGap,
        ListeningLayout.pageInset,
        0,
      ),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(ListeningLayout.cardRadius),
        border: Border.all(color: tokens.border),
      ),
      // 裁掉列表行背景可能越过圆角的部分。
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 工具栏四边使用相同正数内边距。
          Padding(
            padding: const EdgeInsets.all(ListeningLayout.playlistToolbarInset),
            child: Row(
              children: [
                // 搜索框占用两个跳转按钮以外的全部宽度。
                Expanded(
                  child: ListeningPlaylistSearchField(
                    key: const Key('listening-search'),
                    controller: _queryController,
                    tokens: tokens,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                // 统一使用 8 像素控件间距。
                const SizedBox(width: 8),
                // 上按钮滚动到列表起点。
                ListeningSmallIconButton(
                  key: const Key('listening-scroll-top'),
                  icon: TablerIcons.arrowUp,
                  onTap: () => _scrollPlaylistTo(0),
                ),
                // 两个按钮之间继续保持相同间距。
                const SizedBox(width: 8),
                // 下按钮滚动到当前列表的最大可滚动位置。
                ListeningSmallIconButton(
                  key: const Key('listening-scroll-bottom'),
                  icon: TablerIcons.arrowDown,
                  onTap: () {
                    // 未挂载列表时最大滚动距离不存在，因此先检查控制器状态。
                    if (!_listController.hasClients) return;
                    // 读取 Flutter 已经计算完成的列表底部位置。
                    _scrollPlaylistTo(_listController.position.maxScrollExtent);
                  },
                ),
              ],
            ),
          ),
          // 分隔线把搜索工具栏和单词列表明确分区。
          Divider(height: 1, color: tokens.rowBorder),
          // Expanded 让列表只使用卡片工具栏以下的剩余高度。
          Expanded(
            child: ListView.builder(
              controller: _listController,
              itemExtent: ListeningLayout.playlistRowHeight,
              itemCount: filtered.length,
              itemBuilder: (context, visibleIndex) {
                // visibleIndex 是过滤结果下标，不等于真实播放列表下标。
                final entry = filtered[visibleIndex];
                // 每一行交给单独方法输出，避免列表 builder 内继续深层嵌套。
                return _buildPlaylistRow(tokens, entry);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 把播放列表平滑滚动到目标位置。
  void _scrollPlaylistTo(double target) {
    // 页面刚创建或已经销毁时控制器可能没有绑定 ListView，此时直接忽略点击。
    if (!_listController.hasClients) return;
    // animateTo 对应小程序 scroll-view 设置 scrollTop 并启用动画。
    _listController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// 构建播放列表中的单个固定高度行。
  Widget _buildPlaylistRow(AppTokens tokens, ({int index, Word word}) entry) {
    // 真实下标相同表示这一行是当前正在播放的单词。
    final current = entry.index == _index;
    // 只有常显模式会同步公开上方列表拼写，临时按住只影响答案卡。
    final spelling = _revealAll
        ? entry.word.spelling
        : _maskSpelling(entry.word.spelling);
    // 非当前行不显示状态，避免每行右侧出现无意义占位。
    final status = !current
        ? ''
        : _isFinished
        ? '已播完'
        : _isPlaying
        ? '${_completedRepeats + 1}/$_repeat · ${_remainingSeconds}s'
        : '已暂停';
    // InkWell 提供整行点击反馈和跳转操作。
    return InkWell(
      onTap: () => _jumpTo(entry.index),
      child: Container(
        // 当前行使用浅强调色，其他行沿用卡片背景。
        color: current ? AppTokens.accent.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // 单词区域占满右侧状态之外的剩余宽度。
            Expanded(
              child: Text(
                spelling,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: current ? AppTokens.accent : tokens.text,
                  fontSize: 13.5,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // 右侧播放信息只属于当前行。
            if (current) ...[
              Text(status, style: TextStyle(color: tokens.muted, fontSize: 11)),
              // 播放中额外显示音量图标，暂停和结束状态不显示。
              if (_isPlaying) ...[
                const SizedBox(width: 6),
                const Icon(
                  TablerIcons.volume2,
                  size: 14,
                  color: AppTokens.accent,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 构建答案卡；按钮相对卡片外框使用正数边距定位。
  Widget _buildAnswerCard(AppTokens tokens, bool showAnswer) {
    // Padding 放在卡片外部，因此 key 读取到的是实际白色卡片边界而不是含 margin 的虚拟尺寸。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ListeningLayout.pageInset,
        ListeningLayout.sectionGap,
        ListeningLayout.pageInset,
        0,
      ),
      // Listener 对应小程序 bindtouchstart/bindtouchend，支持按住临时查看答案。
      child: Listener(
        key: const Key('listening-answer-card'),
        onPointerDown: (_) => setState(() => _isPeeking = true),
        onPointerUp: (_) => setState(() => _isPeeking = false),
        onPointerCancel: (_) => setState(() => _isPeeking = false),
        // Material 同时绘制背景、圆角和边框，避免两层组件的轮廓出现像素误差。
        child: Material(
          // Key 类似小程序节点的 id，回归测试用它读取真正绘制边框的组件。
          key: const Key('listening-answer-surface'),
          // 卡片背景色交由 Material 统一绘制。
          color: tokens.card,
          // RoundedRectangleBorder 将圆角和边框绑定为同一条轮廓。
          shape: RoundedRectangleBorder(
            // 四个角共用布局尺寸表中的统一圆角。
            borderRadius: BorderRadius.circular(ListeningLayout.cardRadius),
            // side 就像 WXSS 的 border，默认使用 1 像素宽度。
            side: BorderSide(color: tokens.border),
          ),
          // 内容按同一个圆角轮廓裁剪，抗锯齿保证圆角边缘平滑完整。
          clipBehavior: Clip.antiAlias,
          // Stack 让正文滚动区和右上角眼睛按钮共用卡片坐标系。
          child: Stack(
            children: [
              // Positioned.fill 让正文滚动区严格使用卡片完整尺寸。
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ListeningLayout.answerContentInset,
                    ListeningLayout.answerContentInset,
                    ListeningLayout.answerContentRightInset,
                    ListeningLayout.answerContentInset,
                  ),
                  // 内容超出卡片高度时可以纵向滚动。
                  child: SingleChildScrollView(
                    // 隐藏和显示共用同一棵布局树，只替换槽位内部内容。
                    child: ListeningAnswerContent(
                      word: _currentWord,
                      tokens: tokens,
                      definitionSeparator: widget.definitionSeparator,
                      revealed: showAnswer,
                    ),
                  ),
                ),
              ),
              // 眼睛按钮相对卡片真实外框使用 8 像素正数边距定位。
              Positioned(
                top: ListeningLayout.answerActionInset,
                right: ListeningLayout.answerActionInset,
                child: ListeningIconButton(
                  key: const Key('toggle-listening-answer'),
                  icon: _revealAll ? TablerIcons.eye : TablerIcons.eyeOff,
                  color: tokens.muted,
                  // 图标画布在按钮内部贴右上角，不再依赖任何负数偏移。
                  alignment: Alignment.topRight,
                  onTap: () => setState(() => _revealAll = !_revealAll),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建页面底部的三个播放控制按钮。
  Widget _buildPlaybackControls(AppTokens tokens) {
    // Padding 提供控制区与答案卡、屏幕边缘之间的固定距离。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ListeningLayout.pageInset,
        14,
        ListeningLayout.pageInset,
        2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一个按钮会在第一页自动通过 _jumpTo 的 clamp 保持下标为 0。
          ListeningPlayerMoveButton(
            icon: TablerIcons.playerTrackPrev,
            label: '上一个',
            onTap: () => _jumpTo(_index - 1),
          ),
          const SizedBox(width: 24),
          // Material 提供圆形背景和真实阴影。
          Material(
            color: AppTokens.accent,
            shape: const CircleBorder(),
            elevation: 7,
            child: InkWell(
              key: const Key('toggle-listening-playback'),
              onTap: _togglePlayback,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 54,
                height: 54,
                child: Icon(
                  _isPlaying ? TablerIcons.playerPause : TablerIcons.playerPlay,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // 下一个按钮把图标放在文字右侧，末页同样由 _jumpTo 限制范围。
          ListeningPlayerMoveButton(
            icon: TablerIcons.playerTrackNext,
            label: '下一个',
            iconAfterLabel: true,
            onTap: () => _jumpTo(_index + 1),
          ),
        ],
      ),
    );
  }

  /// 隐藏播放列表拼写，只保留首字母并用圆点代替其余字符。
  String _maskSpelling(String spelling) {
    // 空字符串没有首字母，直接返回可避免访问 spelling[0] 越界。
    if (spelling.isEmpty) return '';
    // 圆点至少两个、最多 32 个，避免极短和极长单词造成视觉异常。
    return '${spelling[0]}${List.filled((spelling.length - 1).clamp(2, 32), '•').join()}';
  }
}
