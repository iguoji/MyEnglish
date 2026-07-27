// dart:async 提供 Future、Timer 与 unawaited，负责播放循环和倒计时。
import 'dart:async';

// material.dart 提供页面、列表、底部面板和动画等基础组件。
import 'package:flutter/material.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局设计令牌。
import '../../common/theme.dart';
// 引入单词数据模型。
import '../../models/word.dart';
// 引入可替换的单词发音服务。
import '../../services/word_audio.dart';
// 引入口音设置。
import '../../store/settings.dart';

/// 随身听全屏页面。
///
/// 页面结构与新版原型一致：顶部进度、可搜索跳转的播放列表、隐藏答案卡、
/// 上一个/播放/下一个控制，以及播放次数、间隔和循环设置面板。
class ListeningPage extends StatefulWidget {
  const ListeningPage({
    required this.words,
    required this.audioPlayer,
    required this.accent,
    super.key,
  });

  /// 首页按“已勾选优先，否则当前可见”规则传入的学习列表。
  final List<Word> words;

  /// 与首页共用音频服务，测试时可以注入内存替身。
  final WordAudioPlayer audioPlayer;

  /// 当前设置中的美式或英式口音。
  final PronunciationAccent accent;

  @override
  State<ListeningPage> createState() => _ListeningPageState();
}

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

  Word get _currentWord => widget.words[_index];

  @override
  void initState() {
    super.initState();
    // 第一帧完成后再开始播放，避免初始化阶段直接调用原生通道。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startPlaybackLoop();
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
    while (mounted && serial == _playSerial && _isPlaying) {
      try {
        // 播放当前拼写；Future 在原生音频结束后完成。
        await widget.audioPlayer.play(_currentWord.spelling, widget.accent);
      } on WordAudioInterruptedException {
        // 用户暂停或跳转时 stop 会中断音频，这是正常控制流程。
      } catch (error) {
        // 网络或原生播放器失败时暂停，并保留具体错误给用户。
        if (!mounted || serial != _playSerial) return;
        setState(() => _isPlaying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播放失败：$error')));
        return;
      }
      // 音频期间发生暂停、跳转或退出时，旧循环直接结束。
      if (!mounted || serial != _playSerial || !_isPlaying) return;

      // 每次发音结束后执行可见倒计时。
      for (var second = _interval; second > 0; second--) {
        if (!mounted || serial != _playSerial || !_isPlaying) return;
        setState(() => _remainingSeconds = second);
        await _waitOneSecond();
      }
      if (!mounted || serial != _playSerial || !_isPlaying) return;

      // 当前单词完成一次播放。
      _completedRepeats++;
      if (_completedRepeats >= _repeat) {
        // 播放次数达标后切到下一个单词。
        _completedRepeats = 0;
        if (_index + 1 < widget.words.length) {
          setState(() {
            _index++;
            _remainingSeconds = _interval;
          });
          _centerCurrentWord();
        } else if (_loop) {
          // 循环模式从头开始。
          setState(() {
            _index = 0;
            _remainingSeconds = _interval;
          });
          _centerCurrentWord();
        } else {
          // 非循环模式停在最后一个单词。
          setState(() {
            _isPlaying = false;
            _isFinished = true;
            _remainingSeconds = 0;
          });
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
    _cancelCountdown();
    final completer = Completer<void>();
    _countdownCompleter = completer;
    _countdownTimer = Timer(const Duration(seconds: 1), () {
      if (!completer.isCompleted) completer.complete();
      if (identical(_countdownCompleter, completer)) {
        _countdownCompleter = null;
        _countdownTimer = null;
      }
    });
    return completer.future;
  }

  /// 取消尚未结束的倒计时，并让等待它的旧循环立刻继续到序号检查处。
  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final completer = _countdownCompleter;
    _countdownCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// 暂停当前音频并使旧循环失效。
  Future<void> _pausePlayback() async {
    ++_playSerial;
    _cancelCountdown();
    setState(() => _isPlaying = false);
    try {
      await widget.audioPlayer.stop();
    } catch (error) {
      // 控制动作失败不阻塞页面，只在调试控制台保留诊断。
      debugPrint('暂停随身听失败：$error');
    }
  }

  /// 播放/暂停主按钮。
  void _togglePlayback() {
    if (_isFinished) {
      setState(() {
        _index = 0;
        _completedRepeats = 0;
        _remainingSeconds = _interval;
        _isFinished = false;
        _isPlaying = true;
      });
      _centerCurrentWord(force: true);
      _startPlaybackLoop();
      return;
    }
    if (_isPlaying) {
      unawaited(_pausePlayback());
    } else {
      setState(() => _isPlaying = true);
      _startPlaybackLoop();
    }
  }

  /// 跳到指定位置并从该词第一轮重新开始。
  void _jumpTo(int index) {
    ++_playSerial;
    _cancelCountdown();
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    setState(() {
      _index = index.clamp(0, widget.words.length - 1);
      _completedRepeats = 0;
      _remainingSeconds = _interval;
      _isFinished = false;
      _query = '';
      _queryController.clear();
    });
    _centerCurrentWord(force: true);
    if (_isPlaying) _startPlaybackLoop();
  }

  /// 自动把当前项滚动到列表中部。
  void _centerCurrentWord({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listController.hasClients) return;
      final target =
          (_index * 32.0 - _listController.position.viewportDimension / 2 + 16)
              .clamp(0.0, _listController.position.maxScrollExtent);
      _listController.animateTo(
        target,
        duration: Duration(milliseconds: force ? 180 : 260),
        curve: Curves.easeOut,
      );
    });
  }

  /// 打开与原型一致的底部播放设置。
  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final tokens = AppTokens.of(sheetContext);
          // 同时刷新面板和背后的播放页。
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          return Container(
            padding: EdgeInsets.fromLTRB(
              0,
              16,
              0,
              20 + MediaQuery.paddingOf(sheetContext).bottom,
            ),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Row(
                    children: [
                      Text(
                        '设置',
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                _SettingRow(
                  label: '播放次数',
                  value: _repeat,
                  onMinus: _repeat > 1 ? () => update(() => _repeat--) : null,
                  onPlus: _repeat < 9 ? () => update(() => _repeat++) : null,
                ),
                _SettingRow(
                  label: '播放间隔(秒)',
                  value: _interval,
                  onMinus: _interval > 1
                      ? () => update(() {
                          _interval--;
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
                SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          '列表循环',
                          style: TextStyle(color: tokens.text, fontSize: 14.5),
                        ),
                        const Spacer(),
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

  @override
  void dispose() {
    // 结束所有旧循环并停止仍在播放的原生音频。
    ++_playSerial;
    _cancelCountdown();
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    _listController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final progress = (_index + 1) / widget.words.length;
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = <({int index, Word word})>[
      for (var index = 0; index < widget.words.length; index++)
        if (normalizedQuery.isEmpty ||
            widget.words[index].spelling.toLowerCase().contains(
              normalizedQuery,
            ))
          (index: index, word: widget.words[index]),
    ];
    final showAnswer = _revealAll || _isPeeking;

    return Scaffold(
      backgroundColor: tokens.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  _IconTap(
                    key: const Key('close-listening'),
                    icon: TablerIcons.chevronLeft,
                    onTap: () => Navigator.pop(context),
                  ),
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
                  _IconTap(
                    key: const Key('open-listening-settings'),
                    icon: TablerIcons.settings,
                    onTap: _openSettings,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: tokens.sub,
                  color: AppTokens.accent,
                ),
              ),
            ),
            Container(
              height: 180,
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              decoration: BoxDecoration(
                color: tokens.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            // 原型搜索框和两侧跳转按钮均为 26 像素高。
                            height: 26,
                            child: TextField(
                              key: const Key('listening-search'),
                              controller: _queryController,
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              style: TextStyle(
                                color: tokens.text,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '搜索',
                                hintStyle: TextStyle(
                                  color: tokens.muted,
                                  fontSize: 12,
                                ),
                                prefixIcon: Icon(
                                  TablerIcons.search,
                                  size: 14,
                                  color: tokens.muted,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 30,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: tokens.inputBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: AppTokens.accent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SmallIconButton(
                          icon: TablerIcons.arrowUp,
                          onTap: () => _listController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SmallIconButton(
                          icon: TablerIcons.arrowDown,
                          onTap: () => _listController.animateTo(
                            _listController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.rowBorder),
                  Expanded(
                    child: ListView.builder(
                      controller: _listController,
                      itemExtent: 32,
                      itemCount: filtered.length,
                      itemBuilder: (context, visibleIndex) {
                        final entry = filtered[visibleIndex];
                        final current = entry.index == _index;
                        final spelling = _revealAll
                            ? entry.word.spelling
                            : _maskSpelling(entry.word.spelling);
                        final status = current
                            ? _isFinished
                                  ? '已播完'
                                  : _isPlaying
                                  ? '${_completedRepeats + 1}/$_repeat · ${_remainingSeconds}s'
                                  : '已暂停'
                            : '';
                        return InkWell(
                          onTap: () => _jumpTo(entry.index),
                          child: Container(
                            color: current
                                ? AppTokens.accent.withValues(alpha: 0.08)
                                : null,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    spelling,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: current
                                          ? AppTokens.accent
                                          : tokens.text,
                                      fontSize: 13.5,
                                      fontWeight: current
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                if (current) ...[
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: tokens.muted,
                                      fontSize: 11,
                                    ),
                                  ),
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
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Listener(
                onPointerDown: (_) => setState(() => _isPeeking = true),
                onPointerUp: (_) => setState(() => _isPeeking = false),
                onPointerCancel: (_) => setState(() => _isPeeking = false),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  padding: const EdgeInsets.fromLTRB(16, 16, 44, 16),
                  decoration: BoxDecoration(
                    color: tokens.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        child: showAnswer
                            ? _AnswerContent(word: _currentWord, tokens: tokens)
                            : _HiddenAnswer(word: _currentWord, tokens: tokens),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: _IconTap(
                          key: const Key('toggle-listening-answer'),
                          icon: _revealAll
                              ? TablerIcons.eye
                              : TablerIcons.eyeOff,
                          color: tokens.muted,
                          onTap: () => setState(() => _revealAll = !_revealAll),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PlayerMoveButton(
                    icon: TablerIcons.playerTrackPrev,
                    label: '上一个',
                    onTap: () => _jumpTo(_index - 1),
                  ),
                  const SizedBox(width: 24),
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
                          _isPlaying
                              ? TablerIcons.playerPause
                              : TablerIcons.playerPlay,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  _PlayerMoveButton(
                    icon: TablerIcons.playerTrackNext,
                    label: '下一个',
                    onTap: () => _jumpTo(_index + 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  String _maskSpelling(String spelling) {
    if (spelling.isEmpty) return '';
    return '${spelling[0]}${List.filled((spelling.length - 1).clamp(2, 32), '•').join()}';
  }
}

class _AnswerContent extends StatelessWidget {
  const _AnswerContent({required this.word, required this.tokens});

  final Word word;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          word.spelling,
          style: TextStyle(
            color: tokens.text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final meaning in word.meanings) ...[
          Text(
            meaning.pos,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 7),
          for (final definition in meaning.definitions)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                definition,
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _HiddenAnswer extends StatelessWidget {
  const _HiddenAnswer({required this.word, required this.tokens});

  final Word word;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          // 原型按“40 + 字母数 × 12”计算拼写骨架，最长限制为 260。
          width: (40 + word.spelling.length * 12).clamp(0, 260).toDouble(),
          height: 26,
          decoration: BoxDecoration(
            color: tokens.sub,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 12),
        // 词性在隐藏答案时仍然可见；仅把每条中文释义替换成对应宽度的骨架。
        for (final meaning in word.meanings) ...[
          Text(
            meaning.pos,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 7),
          for (final definition in meaning.definitions) ...[
            Container(
              // 原型按“20 + 字符数 × 14”计算释义骨架，最长限制为 300。
              width: (20 + definition.length * 14).clamp(0, 300).toDouble(),
              height: 15,
              decoration: BoxDecoration(
                color: tokens.sub,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: 7),
          ],
          const SizedBox(height: 5),
        ],
        Text(
          '按住卡片临时查看，点右上角眼睛常显',
          style: TextStyle(color: tokens.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.rowBorder)),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: tokens.text, fontSize: 14.5)),
          const Spacer(),
          _StepButton(icon: TablerIcons.minus, onTap: onMinus),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StepButton(icon: TablerIcons.plus, onTap: onPlus),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: tokens.card,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 15,
              color: onTap == null ? tokens.muted : tokens.textMedium,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.onTap,
    this.color,
    super.key,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: 34,
      height: 34,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Icon(icon, size: 21, color: color ?? tokens.textMedium),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: 28,
      height: 28,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.inputBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: tokens.textMedium),
        ),
      ),
    );
  }
}

class _PlayerMoveButton extends StatelessWidget {
  const _PlayerMoveButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: tokens.textMedium,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}
