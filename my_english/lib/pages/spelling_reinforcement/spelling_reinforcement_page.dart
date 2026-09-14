import '../../widgets/audio_playback_capsule.dart';
// dart:async 提供计时器、自动发音延迟与 unawaited（落盘不阻塞交互）。
import 'dart:async';
// material.dart 提供全屏页面、进度条与按钮。
import 'package:flutter/material.dart';
// services.dart 提供 HapticFeedback，答错时给一次轻微震动。
import 'package:flutter/services.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。

// 引入全局设计令牌（颜色变量，随亮色/深色主题自动切换）。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角时间超过一小时改用 hh:mm:ss，不足用 mm:ss。
import '../../common/date.dart';
// 引入全局 Toast 工具，播放失败时提示用户。
import '../../common/toast.dart';
// 引入单词数据模型，首页会把当天固定词单传进来。
import '../../models/word.dart';
import '../../models/settlement.dart';
// 引入音频播放接口，与首页、随身听共用同一个实现。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入统一的进度出口，屏蔽「长期会话」与「复习会话」的差别。
import '../review/services/session_progress.dart';
// 引入集中管理的页面布局尺寸。
import 'widgets/spelling_layout.dart';
// 引入通用 26 键键盘，作为本页面唯一的输入方式。
import '../../widgets/qwerty_keyboard.dart';
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
import '../../widgets/settlement_summary.dart';
// 复用听音辨义模块的公共扬声器按钮，避免多个页面各自维护一套样式。
// 引入公共「词性及含义」面板，与听音辨义共用同一套版式。
import '../../widgets/letter_slot.dart';
import '../../widgets/pos_meaning_panel.dart';

/// 拼写题中允许用户从 26 键键盘输入的字符范围。
///
/// 只把英文字母交给用户输入；空格、撇号、连字符以及其他非字母字符
/// 都属于单词本身的一部分，由页面直接展示并自动跳过。
final RegExp _englishLetterPattern = RegExp(r'^[A-Za-z]$');

/// 答错时只记录错误并短暂锁定键盘，让用户看清反馈后继续作答。
///
/// 生活化解释：错误不会把整题卡死，也不会自动替用户填答案；红色抖动结束后，
/// 用户可以继续用键盘重新输入当前字母。

///
/// 一个单词这一局的最终结果，供结算页判断「这一组是否全对」。
///
class SpellingWordOutcome {
  ///
  /// 创建一条单词结果。
  const SpellingWordOutcome({required this.spelling, required this.wrongCount});

  ///
  /// 单词拼写。
  final String spelling;

  ///
  /// 这个词累计答错几次。
  final int wrongCount;

  ///
  /// 是否一次就拼对（全程没错）。
  bool get isPerfect => wrongCount == 0;
}

/// 播放状态声纹中的单根圆角竖条。

///
/// 拼写巩固页面。
///
/// 玩法：听发音、看中文释义，用 26 键键盘把单词逐字母拼出来。
///
/// 单词模型中的片段字段暂时保留，但本页面不再读取、计算、修改或展示片段；
/// 所有输入固定放在底部键盘，正文呈现答案占位格、播放状态、Meaning 标题和中文释义卡片。
///
/// 界面由上、中、下三部分组成：顶部是返回图标、进度、时间和进度条；中间是
/// 正文区域；底部是贴住可用屏幕边缘的 26 键键盘。
///
class SpellingReinforcementPage extends StatefulWidget {
  ///
  /// 创建拼写巩固页面。
  const SpellingReinforcementPage({
    required this.words,
    required this.title,
    required this.progress,
    required this.audioPlayer,
    required this.accent,
    // 首页把全局设置中的实际中文分隔符传进来，页面不写死任何一种标点。
    this.definitionSeparator = '；',
    super.key,
  }) : assert(words.length > 0, '拼写巩固至少需要一个单词');

  ///
  /// 首页按会话顺序传入的本局单词。
  final List<Word> words;

  ///
  /// 当前复习模块名称；顶栏中央显示数字进度，此处仅作语义标识与埋点。
  final String title;

  ///
  /// 本局的进度出口，由首页的 ReviewFlow 判定后传入。
  ///
  /// 它同时决定三件事：进度存到哪一局、每次点击记到哪一局，
  /// 以及答题要不要推进单词的复习时间（巩固局不推进）。
  final SessionProgress progress;

  ///
  /// 与首页、随身听共用的发音服务。
  final WordAudioPlayer audioPlayer;

  ///
  /// 当前发音口音。
  final PronunciationAccent accent;

  /// 同一词性下多条中文含义之间使用的全局设置分隔符。
  ///
  /// 默认值与首次安装时的全局设置一致；正式入口由首页传入用户当前选择的符号。
  final String definitionSeparator;

  ///
  /// 创建拼写巩固页面状态。
  @override
  State<SpellingReinforcementPage> createState() =>
      _SpellingReinforcementPageState();
}

///
/// 管理拼写巩固的当前单词、键盘输入进度与结算。
///
/// 这里同时驱动三条动画：作答区淡入、答错抖动、填对弹入，
/// 因此使用可挂多个 Ticker 的 TickerProviderStateMixin（复数版）。
///
class _SpellingReinforcementPageState extends State<SpellingReinforcementPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  ///
  /// 当前单词在本局固定词单中的下标。
  int _wordIndex = 0;

  ///
  /// 键盘模式下已经拼出的字符（含自动补上的空格与连字符）。
  final List<String> _typedLetters = <String>[];

  /// 每个用户输入的字母都有一个只使用一次的编号；自动补上的空格、连字符
  /// 等非字母字符用 null 占位，保证这个列表与 [_typedLetters] 一一对应。
  ///
  /// 生活化解释：字母格不仅要知道“现在是什么字母”，还要知道“这次是不是
  /// 新按出来的”。这样答错清空后再次输入时，会创建一枚全新的字母动画，
  /// 不会沿用上一次已经播放完的动画状态。
  final List<int?> _typedEntryTokens = <int?>[];

  /// 下一个字母入场动画的唯一编号。
  int _nextLetterEntryToken = 0;

  ///
  /// 当前单词已经答错的次数；整词完成时写进 [SpellingWordOutcome.wrongCount]。
  int _currentWrong = 0;

  ///
  /// 本局每个已完成单词的结果，供结算页判断「这一组是否全对」。
  final List<SpellingWordOutcome> _outcomes = <SpellingWordOutcome>[];

  ///
  ///
  /// 本局已经过去的毫秒数；只在页面处于前台且未结算时累加。
  int _elapsedMs = 0;

  ///
  /// 当前这个单词是「几点几分几秒」开始答题的。
  ///
  /// 生活化解释：右上角那个计时器是**整局**的，退后台会停、切页面也会停；
  /// 这一块是另一只独立的手表，专门掐「这个单词我盯着看了多久」。
  /// 结算页每行右边那个用时就是拿「现在」减它算出来的。
  DateTime _wordStartedAt = DateTime.now();

  ///
  /// 本局是否已经把全部单词走完一遍。
  bool _completed = false;

  /// 结算草稿正在提交时锁住两个离开入口，避免重复应用难度。
  bool _isCommittingSummary = false;

  ///
  /// 是否正在准备当前单词。
  ///
  /// 这段时间键盘暂不响应，避免切换单词时误触输入。
  bool _preparing = true;

  ///
  /// 答错反馈或切换单词停顿期间的输入锁。
  ///
  /// 生活化解释：答错后按钮要红着脸抖 0.35 秒，随后红色提示停留 1 秒；
  /// 拼对后最后一格也要绿着停留 1 秒。
  /// 这两段时间如果还能继续点，反馈会被下一次点击立刻打断，用户根本看不清
  /// 自己错在哪、或者错误会被记到下一个单词头上。
  bool _inputLocked = false;

  ///
  /// 是否正在显示整词答错反馈；新输入规则不会在中途逐字拦截。
  bool _showWrongFeedback = false;

  /// 是否正在显示整词答对反馈，用于把全部下划线短暂染成成功色。
  bool _showCorrectFeedback = false;

  ///
  /// 当前单词的发音是否仍在播放。
  bool _isPlaying = false;

  ///
  /// 当前音频请求代次，只允许最新请求更新播放状态。
  int _playGeneration = 0;

  ///
  /// 已经写过复习记录的单词下标，防止恢复进度后重复写入。
  final Set<int> _recordedIndexes = <int>{};

  ///
  /// 答错抖动的解锁定时器；页面销毁时必须取消，避免定时器泄漏。
  Timer? _unlockTimer;

  ///
  /// 切换到下一个单词的定时器。
  Timer? _advanceTimer;

  ///
  /// 每秒累加用时的定时器。
  Timer? _elapsedTimer;

  ///
  /// 进入单词后自动发音的定时器。
  Timer? _autoSpeakTimer;

  ///
  /// 答错抖动控制器：同一时刻只会有一个元素在抖，因此共用一个控制器。
  late final AnimationController _shakeController;

  /// 播放状态声纹的当前相位。
  ///
  /// 不使用逐帧 AnimationController：声纹是装饰性反馈，每秒更新约 12 次
  /// 已足够流畅，却能明显减少模拟器持续重绘造成的 CPU 占用。

  /// 声纹低频刷新定时器；只有真实播放时才运行。

  ///
  /// 本局进度的落盘出口，在 initState 里创建一次。
  SessionProgress get _progress => widget.progress;

  ///
  /// 当前正在拼写的单词。
  Word get _currentWord => widget.words[_wordIndex];

  /// 当前题目实际使用的拼写。
  ///
  /// 这里刻意不调用 `trim()`：单词内部的空格当然要保留，若数据里存在
  /// 首尾空格，也应该把它当作无需输入的特殊字符，而不是悄悄删掉。
  String get _targetSpelling => _currentWord.spelling;

  ///
  /// 本局总词量。
  int get _total => widget.words.length;

  ///
  /// 是否展示结算页。
  bool get _showSummary => _completed;

  ///
  /// 顶栏中间显示的「第几个」：结算时显示总数，答题时显示当前序号。
  int get _displayIndex => _showSummary ? _total : _wordIndex + 1;

  ///
  /// 进度条填充比例：已经完成的单词数占总数的比例。
  double get _progressRatio =>
      _total > 0 ? (_outcomes.length / _total).clamp(0.0, 1.0) : 0.0;

  // ===== 以下为生命周期 =====

  ///
  /// 初始化页面：建好动画与进度出口，恢复历史进度，再准备第一个单词。
  @override
  void initState() {
    super.initState();
    // 监听前后台变化：退到后台停表并停止发音，回到前台再继续。
    WidgetsBinding.instance.addObserver(this);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: SpellingLayout.shakeDurationMs),
    );
    // 先恢复历史进度（可能直接恢复到已结算状态），再准备当前单词。
    _restoreProgress();
    if (!_showSummary && _outcomes.length < _total) {
      unawaited(_prepareCurrentWord(autoSpeak: true, keepProgress: true));
      _startElapsedTimer();
    } else {
      _preparing = !_completed;
    }
  }

  ///
  /// 从会话与点击记录恢复本局进度。
  ///
  /// 2.0 起不再存页面快照：做到第几个来自会话的「当前进度」，用时来自
  /// 「所用时间」，每个词答对没有、错了几次全部回放点击记录得出。
  ///
  /// 唯一恢复不了的是「当前这个词已经拼了一半」——重进会从这个词的开头
  /// 重来。这是刻意的取舍：为了半个单词而维护一份快照并不划算。
  void _restoreProgress() {
    _elapsedMs = _progress.session.elapsed * 1000;
    _wordStartedAt = DateTime.now();
    var next = 0;
    for (final word in widget.words) {
      if (!_progress.progressOf(word.id!).spellingDone) break;
      _outcomes.add(
        SpellingWordOutcome(
          spelling: word.spelling,
          wrongCount: _progress.allRecords
              .where((record) => record.wordId == word.id && !record.isCorrect)
              .length,
        ),
      );
      _recordedIndexes.add(next++);
    }
    _wordIndex = next.clamp(0, _total - 1);
    _currentWrong = _progress.allRecords
        .where(
          (record) => record.wordId == _currentWord.id && !record.isCorrect,
        )
        .length;
    if (next >= _total) {
      _preparing = true;
      unawaited(_finishRecoveredSession());
    }
  }

  Future<void> _finishRecoveredSession() async {
    try {
      await _finishSession();
      if (mounted) {
        setState(() {
          _completed = true;
          _preparing = false;
        });
      }
    } catch (error) {
      if (mounted) Toast.show(context, '结算保存失败，重新进入可继续：$error');
    }
  }

  ///
  /// 准备当前单词。
  ///
  /// 拼写巩固现在始终使用 26 键键盘，因此这里不再读取、计算或回写
  /// 单词的片段字段；片段数据仍由模型保留，供以后恢复相关功能时使用。
  Future<void> _prepareCurrentWord({
    bool autoSpeak = false,
    bool keepProgress = false,
  }) async {
    if (!mounted) return;
    setState(() {
      // 续玩只恢复到当前单词，不恢复半个单词的输入现场。
      if (!keepProgress) {
        _typedLetters.clear();
        _typedEntryTokens.clear();
      }
      _preparing = false;
      _autoFillNonLetters();
    });
    final question = _progress.questionFor(wordId: _currentWord.id);
    if (question != null) _progress.activateQuestion(question.id);
    if (autoSpeak) _scheduleAutoSpeak();
  }

  ///
  /// 键盘模式下自动补齐当前位置之后的非字母字符。
  ///
  /// 生活化解释：ice cream 中间那个空格、T-shirt 中间那个连字符、o'clock
  /// 中间的撇号，用户在 26 键键盘上都不需要也无法输入。所以开题时先处理
  /// 开头的特殊字符；每拼完一个字母，再顺手处理后面紧跟的所有特殊字符，
  /// 光标就会停在下一个真正要输入的字母上。
  void _autoFillNonLetters() {
    final target = _targetSpelling;
    while (_typedLetters.length < target.length) {
      final next = target[_typedLetters.length];
      if (_englishLetterPattern.hasMatch(next)) break;
      _typedLetters.add(next);
      _typedEntryTokens.add(null);
    }
  }

  ///
  /// 启动每秒累加用时的定时器。
  void _startElapsedTimer() {
    if (_elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // 已结算就不再计时；用时不影响画面布局，但要让结算页数字跟着走。
      if (!mounted || _showSummary) return;
      setState(() => _elapsedMs += 1000);
    });
  }

  /// 停止并清空计时器引用，保证回到前台时可以重新启动。
  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  ///
  /// 安排进入单词后的自动发音。
  ///
  /// 延迟一小会儿再发声（原型 350 毫秒），让页面先画完再出声，
  /// 避免转场动画和音频同时启动造成的卡顿感。
  void _scheduleAutoSpeak() {
    _autoSpeakTimer?.cancel();
    _autoSpeakTimer = Timer(
      const Duration(milliseconds: SpellingLayout.autoSpeakDelayMs),
      () {
        if (!mounted || _showSummary) return;
        unawaited(_playAudio(interrupt: true));
      },
    );
  }

  ///
  /// 调用真实发音服务，并在播放期间把喇叭图标换成音量图标。
  ///
  /// [interrupt] 为 false 时忽略播放中的重复点击；为 true 时允许自动播放
  /// 打断旧音频，确保切换单词后立即播放新单词。
  Future<void> _playAudio({bool interrupt = false}) async {
    if (_showSummary) return;
    // 手动点击且正在播放中：保持防连点体验，直接忽略。
    if (_isPlaying && !interrupt) return;
    // 领取本次播放的代次号（前置 ++ 先自增再取值，保证全局唯一且递增）。
    final generation = ++_playGeneration;
    _setPlaybackState(true);
    try {
      // await 会一直等到原生音频播放完毕（或被新播放打断而抛异常）。
      await widget.audioPlayer.playRandomChannel(
        _currentWord.spelling,
        widget.accent,
      );
      // 播音不附带任何提示：TTS 现在也是轮转队列的正常一员，轮到它出声并不代表
      // 网络坏了；只有 TTS 引擎本身不可用（下方专用异常）时才需要向用户说明。
    } on WordAudioTtsUnavailableException catch (error) {
      // 设备没有可用的离线英语 TTS（且网络发音未能成功兜住）时给出明确提示，
      // 不带“播放失败”前缀，直接展示原因，方便用户去装语音包或联网。
      if (mounted && generation == _playGeneration) {
        Toast.show(context, error.toString());
      }
    } on WordAudioInterruptedException {
      // 页面关闭或新播放替换旧播放时无需弹出错误。
    } catch (error) {
      // 只有仍是「最新一次播放」时才提示失败，过期的旧请求不打扰用户。
      if (mounted && generation == _playGeneration) {
        Toast.show(context, '播放失败：$error');
      }
    } finally {
      // 号码牌过期说明已有更新的播放在跑，绝不能由旧请求清掉播放中状态。
      if (mounted && generation == _playGeneration) {
        _setPlaybackState(false);
      }
    }
  }

  /// 同步更新播放状态和声纹动画。
  ///
  /// 生活化解释：左边圆形按钮和右边声纹必须像同一个播放器一样同时变化，
  /// 不能出现“图标已经停了、声纹还在跳”这种状态错位。
  void _setPlaybackState(bool isPlaying) {
    if (isPlaying) {
    } else {}
    if (mounted) setState(() => _isPlaying = isPlaying);
  }

  // ===== 以下为作答交互 =====

  ///
  /// 点击键盘上的一个字母：先照常填入，等整词完成后统一自检。
  void _onKeyTap(String letter) {
    if (_showSummary || _inputLocked || _preparing) return;
    final target = _targetSpelling;
    // 已经拼满就不再接受输入（切换单词停顿期间的保险）。
    if (_typedLetters.length >= target.length) return;
    // 这里不比较答案，用户按下什么就先显示什么；整词填完后才一次性检查。
    setState(() {
      _typedLetters.add(letter);
      _typedEntryTokens.add(_nextLetterEntryToken++);
      // 紧跟其后的空格、连字符自动补上，光标落到下一个真正要输入的字母。
      _autoFillNonLetters();
    });
    unawaited(_persist());
    if (_typedLetters.length >= target.length) _evaluateCurrentWord();
  }

  /// 整个单词填完后统一比较，不在输入过程中逐个弹出错误提示。
  void _evaluateCurrentWord() {
    final target = _targetSpelling;
    final typed = _typedLetters.join();
    if (typed.toLowerCase() == target.toLowerCase()) {
      _onWordSolved();
      return;
    }
    _onWrongAnswer(input: typed);
  }

  ///
  /// 点击退格：删掉最后一个用户输入的字母。
  ///
  /// 自动补上的空格、连字符、撇号等非字母字符会一并退掉——它们不是用户输入的，
  /// 留在那里会让用户以为退格失灵了。
  void _onBackspace() {
    if (_showSummary || _inputLocked || _preparing) return;
    if (_typedLetters.isEmpty) return;
    setState(() {
      // 先退掉末尾那些自动补的非字母字符。
      while (_typedLetters.isNotEmpty &&
          !_englishLetterPattern.hasMatch(_typedLetters.last)) {
        _typedLetters.removeLast();
        _typedEntryTokens.removeLast();
      }
      // 再退掉一个真正的字母。
      if (_typedLetters.isNotEmpty) {
        _typedLetters.removeLast();
        _typedEntryTokens.removeLast();
      }
    });
    unawaited(_persist());
  }

  ///
  /// 处理一次整词答错：累计错误、整行抖动、保留红色提示后清空重试。
  ///
  /// 反馈不会在抖动结束时立刻消失，而是总计保留 1 秒，让用户看清错误信息。
  Future<void> _onWrongAnswer({required String input}) async {
    _inputLocked = true;
    try {
      await _recordAttempt(input: input, isCorrect: false);
    } catch (error) {
      if (mounted) {
        setState(() => _inputLocked = false);
        Toast.show(context, '答案保存失败：$error');
      }
      return;
    }
    if (!mounted) return;
    _progress.pauseQuestion();
    setState(() {
      _currentWrong += 1;
      _showWrongFeedback = true;
      _showCorrectFeedback = false;
      _inputLocked = true;
    });
    _shakeController.forward(from: 0);
    // 轻微震动：整词检查失败时给一次反馈，而不是每个错误字母都震动。
    unawaited(HapticFeedback.selectionClick());

    unawaited(_persist());
    _unlockTimer?.cancel();
    _unlockTimer = Timer(
      const Duration(milliseconds: SpellingLayout.wrongFeedbackDurationMs),
      () {
        if (!mounted) return;
        setState(() {
          _typedLetters.clear();
          _typedEntryTokens.clear();
          _autoFillNonLetters();
          _showWrongFeedback = false;
          _inputLocked = false;
        });
        final question = _progress.questionFor(wordId: _currentWord.id);
        if (question != null) _progress.activateQuestion(question.id);
      },
    );
  }

  ///
  /// 当前单词拼对：记一条、锁住输入、保留 1 秒成功反馈再进下一个词。
  Future<void> _onWordSolved() async {
    _inputLocked = true;
    try {
      await _recordAttempt(input: _typedLetters.join(), isCorrect: true);
    } catch (error) {
      if (mounted) {
        setState(() => _inputLocked = false);
        Toast.show(context, '答案保存失败：$error');
      }
      return;
    }
    if (!mounted) return;
    // 拼对也留痕：没有这一条，本局这个词在数据库里就等于「没练过」，
    // 首页的今日复习数与打卡热力图都统计不到它。

    setState(() {
      _showCorrectFeedback = true;
      _showWrongFeedback = false;
      _inputLocked = true;
    });
    _advanceTimer?.cancel();
    _advanceTimer = Timer(
      const Duration(milliseconds: SpellingLayout.wordAdvanceDelayMs),
      _goToNextWord,
    );
  }

  ///
  /// 结束当前单词并推进：写记录、清状态，还有词就准备下一个，否则结算。
  Future<void> _goToNextWord() async {
    if (!mounted) return;
    // 先把这个词的结果定格下来（结算页统计与「需加强」名单都靠它）。
    final outcome = SpellingWordOutcome(
      spelling: _currentWord.spelling,
      wrongCount: _currentWrong,
    );
    // 这个词尘埃落定，先把结算草稿真正写入队列，再切换题目或显示结算页。
    // 这样 finishSession 写入待结算标记时不会撞在尚未生成草稿的时间窗口里。
    await _recordCurrentWord(outcome);
    if (!mounted) return;

    final isLast = _wordIndex + 1 >= _total;
    setState(() {
      _outcomes.add(outcome);
      _currentWrong = 0;
      _showCorrectFeedback = false;
      _showWrongFeedback = false;
      _inputLocked = false;
      if (isLast) {
        _inputLocked = true;
      } else {
        _wordIndex += 1;
        // 换到新单词，手表重新掐表。
        _wordStartedAt = DateTime.now();
        // 进入新词前先清空输入，避免旧单词的字母闪现一帧。
        _typedLetters.clear();
        _typedEntryTokens.clear();
        _preparing = true;
      }
    });
    if (isLast) {
      // 整局已经结束，彻底停表，避免结算页期间定时器继续空转。
      _stopElapsedTimer();
      await _finishRecoveredSession();
      return;
    }
    unawaited(_prepareCurrentWord(autoSpeak: true));
  }

  ///
  /// 一个单词拼完后写一条复习记录。
  ///
  /// 时机：这个词已经拼对或被揭示答案，用户对它的掌握程度已经尘埃落定。
  /// 把累计答错次数交给原生，由它在一个事务里更新连对次数、难度和复习时间。
  ///
  ///
  /// 记一次输入尝试，不论对错。
  ///
  /// 拼写巩固没有「一条释义一小题」的概念，所以记录不带含义主键，
  /// 只挂在单词上。
  Future<void> _recordAttempt({
    required String input,
    required bool isCorrect,
  }) async {
    final wordId = _currentWord.id;
    // 没有主键无法落库；它通常只会出现在尚未保存的测试数据中。
    if (wordId == null) return;
    await _progress.record(
      wordId: wordId,
      input: input,
      isCorrect: isCorrect,
      elapsed: _elapsedSeconds,
    );
  }

  ///
  /// 这个词尘埃落定后结算它：更新难度，必要时推进复习时间。
  ///
  /// 「对 / 错」在每次点击的当下就已经逐次写进了会话记录，这里只负责结算。
  /// 结算会看「本局这个词有没有点错过」，一次都没错才算这一轮答对。
  Future<void> _recordCurrentWord(SpellingWordOutcome outcome) async {
    // 恢复进度后重复走到同一个词不该再算一次，用集合挡住。
    if (!_recordedIndexes.add(_wordIndex)) return;
    final wordId = _currentWord.id;
    // 没有主键的临时数据跳过。
    if (wordId == null) return;
    try {
      await _progress.settle(
        wordId,
        // 本词用时 = 现在 − 这个单词开始答题的那一刻。
        usedTime: DateTime.now().difference(_wordStartedAt),
      );
    } catch (error) {
      // 结算失败不该打断正在进行的一局；集合里放回去，后面还有机会补算。
      _recordedIndexes.remove(_wordIndex);
      debugPrint('拼写巩固结算单词失败：$error');
    }
  }

  // ===== 以下为持久化与生命周期收尾 =====

  ///
  /// 把当前进度写入 SQLite；页面交互先完成，持久化失败不阻断游戏。
  ///
  /// 2.0 起只写两个数：做到第几个词、已经花了多少秒。剩下的现场
  /// （每个词答没答对、错了几次）全部由这一局的点击记录反查得出。
  Future<void> _persist() async {
    // 已结算的局不能再被 dispose 时的延迟保存写回「进行中」。
    if (_showSummary) return;
    await _progress.save(cursor: _wordIndex, elapsed: _elapsedSeconds);
  }

  ///
  /// 本局已用秒数。
  int get _elapsedSeconds => (_elapsedMs ~/ 1000).clamp(0, 1 << 30);

  ///
  /// 给这一局结算。
  ///
  /// 判定规则和另两个模块一致：只要把这一局的单词全部走完一遍（[_completed]
  /// 为 true）就算「完成」，中途答错只影响结算页展示和单词个体难度，
  /// 不再影响整局成败。中途退出没走完才算「失败」。
  Future<void> _finishSession() => _progress.finish(
    perfect: _completed,
    cursor: _outcomes.length,
    elapsed: _elapsedSeconds,
  );

  ///
  /// App 前后台切换：退后台停表停声并保存，回前台再继续。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_showSummary) _startElapsedTimer();
      return;
    }
    _stopElapsedTimer();
    _autoSpeakTimer?.cancel();
    // 退后台时作废正在进行的播放请求。
    ++_playGeneration;
    if (mounted) _setPlaybackState(false);
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    if (!_showSummary) unawaited(_persist());
  }

  ///
  /// 页面被移出导航栈（返回/退出）时立即停表。
  @override
  void deactivate() {
    // 转场一开始就把计时器停掉，把主线程让给返回动画，避免卡顿。
    _stopElapsedTimer();
    // deactivate 发生在导航转场的构建阶段，只取消定时器，避免通知
    // 仍挂在树上的 ValueListenableBuilder 立即重建。
    super.deactivate();
  }

  /// 页面被重新挂回树时恢复计时，兼容返回手势取消等临时离场场景。
  @override
  void activate() {
    super.activate();
    if (!_showSummary) {
      _startElapsedTimer();
    }
  }

  @override
  void dispose() {
    _progress.detach();
    // 注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    _stopElapsedTimer();
    _advanceTimer?.cancel();
    _unlockTimer?.cancel();
    _autoSpeakTimer?.cancel();
    _shakeController.dispose();
    // dispose 也可能发生在导航层构建期间，不能在这里修改监听值。
    // 离场即停声，避免退回首页后还在念这个单词。
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    // 停表并保存当前进度；completed 也会在此落盘（首页据此显示状态）。
    unawaited(_persist());
    super.dispose();
  }

  // ===== 以下为界面构建 =====

  ///
  /// 构建拼写巩固页面。
  ///
  /// 骨架整块交给模块模板 [ModuleScaffold]：上段顶栏、中段正文、下段键盘。
  /// 本页只负责三件本模块特有的事——键盘那块灰蓝底色要连系统手势区一起染，
  /// 结算时下段整块撤掉，以及把系统导航栏的颜色跟着切换。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Android 的手势导航区域属于系统窗口，不是普通 Flutter 子组件；
    // 这里把它的背景色同步成键盘面板色，消除键盘下方的白色断层。
    final keyboardPanelColor = QwertyKeyboard.panelColor(context);
    // 结算页没有键盘，系统导航区应继续使用页面底色，避免离开答题页后
    // 底部仍残留一条灰蓝色区域。
    final navigationBarColor = _showSummary ? tokens.page : keyboardPanelColor;
    final systemUiStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: navigationBarColor,
      systemNavigationBarDividerColor: navigationBarColor,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      // 关闭系统可能自动添加的对比度遮罩，保证导航区与键盘颜色一致。
      systemNavigationBarContrastEnforced: false,
    );

    return ModuleScaffold(
      canPop: !_showSummary,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showSummary) unawaited(_leaveSummary());
      },
      header: ModuleHeader(
        leading: ModuleIconButton(
          key: const Key('close-spelling'),
          icon: AppGlyph.back,
          alignment: Alignment.centerLeft,
          onTap: _leaveSummary,
        ),
        title: ModuleProgressLabel(
          textKey: const Key('spelling-progress-label'),
          current: _displayIndex,
          total: _total,
        ),
        trailing: ModuleTimeLabel(
          textKey: const Key('spelling-elapsed'),
          text: _formatElapsed(),
        ),
        progress: _progressRatio,
        progressBarKey: const Key('spelling-progress'),
      ),
      body: _showSummary ? _buildSummary(tokens) : _buildGame(tokens),
      // 结算页不需要键盘，下段整块不传；答题时下段自带灰蓝底色，
      // 由模板负责一直铺到屏幕最底边。
      footer: _showSummary ? null : _buildKeyboard(),
      footerColor: _showSummary ? null : keyboardPanelColor,
      // 对应 ui/听音拼写1.html 的 border-t border-black/[0.06]。
      footerBorderColor: _showSummary ? null : AppTokens.keyPanelBorder,
      systemUiOverlayStyle: systemUiStyle,
    );
  }

  // 顶部信息区（返回键、进度数字、已用时间、进度条）已经整块交给模块模板的
  // ModuleHeader，本页不再自己拼一遍。原来这里是一段 90 行的 Stack：五个模块
  // 各抄了一份，改一处必然漏另外四处，真机上就表现为切换模块时顶部跳一下。

  ///
  /// 构建中间正文区域。
  ///
  /// 正文只负责展示当前单词的占位格、播放状态和释义；所有输入都固定放在
  /// 页面底部的 26 键键盘中，避免正文与操作区互相挤压。
  ///
  /// 页面底色统一成首页底色之后，正文整块躺在一张白卡上——卡片规格
  /// （8 圆角 + 1 像素细描边 + 一层极轻投影）与听音辨义的题目卡完全相同，
  /// 所以胶囊、词性含义卡这些内部元素一个都不用改，仍然是「浅灰躺在白底上」。
  Widget _buildGame(AppTokens tokens) {
    return GestureDetector(
      key: const Key('spelling-blank-replay'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_playAudio()),
      child: Padding(
        // 卡片四周留出与听音辨义一致的呼吸空间；底部同样留 12，
        // 卡片不会直接贴到键盘面板上。
        padding: const EdgeInsets.fromLTRB(
          SpellingLayout.pageInset,
          SpellingLayout.bodyVerticalInset,
          SpellingLayout.pageInset,
          SpellingLayout.bodyVerticalInset,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              // 空间够时卡片撑满正文区，内容较多时卡片自然增高并允许滚动。
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Container(
                key: const Key('spelling-body-card'),
                padding: const EdgeInsets.symmetric(
                  horizontal: SpellingLayout.bodyCardPaddingHorizontal,
                  vertical: SpellingLayout.bodyCardPaddingVertical,
                ),
                decoration: BoxDecoration(
                  color: tokens.card,
                  // 与候选词、描边按钮、输入框同一档控件描边；白卡只靠这一圈线
                  // 立在灰底上，不再叠投影。
                  border: Border.all(
                    color: tokens.rowBorder,
                    width: AppStroke.thin,
                  ),
                  borderRadius: BorderRadius.circular(
                    SpellingLayout.bodyCardRadius,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSpellingInput(tokens),
                      _buildPlaybackStatus(tokens),
                      _buildMeanings(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建听音拼写原型中的胶囊式播放状态组件。
  ///
  /// 原型右侧上方是音标；应用的单词模型没有音标字段，因此这里改成长条状
  /// 声纹。播放时声纹从左到右错开起伏，未播放时保留低矮静态形态，且上下
  /// 两行共用固定宽度，避免状态文字变化时胶囊发生横向跳动。
  Widget _buildPlaybackStatus(AppTokens tokens) => Padding(
    padding: const EdgeInsets.only(
      top: SpellingLayout.playbackSectionTop,
      bottom: SpellingLayout.playbackSectionBottom,
    ),
    child: AudioPlaybackCapsule(
      key: const Key('spelling-playback-status'),
      isPlaying: _isPlaying,
      onTap: () => unawaited(_playAudio()),
      accentLabel: widget.accent.label,
    ),
  );

  ///
  /// 构建 `听音拼写2.html` 中从 Meaning 标题开始的完整含义区域。
  ///
  /// 标题、卡片和含义排版本身已经抽成公共组件
  /// `lib/widgets/pos_meaning_panel.dart`，听音辨义用的是同一个组件的
  /// 「揭示模式」，所以两个模块的词性含义永远长一个模样。这里只负责决定
  /// 这块内容摆在页面的什么位置。
  Widget _buildMeanings() {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        // 原型在手机上铺满内容区，平板上限制最大宽度，避免卡片过宽。
        constraints: const BoxConstraints(
          maxWidth: SpellingLayout.meaningPanelMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            top: SpellingLayout.meaningSectionTop,
            bottom: SpellingLayout.meaningSectionBottom,
          ),
          child: PosMeaningPanel(
            // 模型层已经把相同词性的释义整理成分组，这里直接转成面板要的行。
            rows: PosMeaningRow.fromGroups(_currentWord.meaningGroups),
            separator: widget.definitionSeparator,
            keyPrefix: 'spelling',
          ),
        ),
      ),
    );
  }

  /// 构建 HTML 原型中的完整拼写输入区。
  ///
  /// 输入区由带细边框的下划线字母位和底部说明组成。用户输入什么就先
  /// 显示什么，只有填满整词后才统一自检，因此不会在输入中途逐字打断。
  Widget _buildSpellingInput(AppTokens tokens) {
    if (_preparing) {
      return const SizedBox(
        height:
            LetterSlotLayout.letterHeight +
            SpellingLayout.spellingStatusTop +
            SpellingLayout.spellingStatusHeight,
      );
    }
    final target = _targetSpelling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final offset = _showWrongFeedback
                ? _interpolateFrames(
                    SpellingLayout.shakeKeyframes,
                    _shakeController.value,
                  )
                : 0.0;
            return Transform.translate(offset: Offset(offset, 0), child: child);
          },
          child: _buildSlotRow(tokens, target),
        ),
        const SizedBox(height: SpellingLayout.spellingStatusTop),
        SizedBox(
          height: SpellingLayout.spellingStatusHeight,
          child: Center(child: _buildSpellingStatus(tokens)),
        ),
      ],
    );
  }

  /// 构建拼写区底部提示，状态只在整词完成后改变。
  Widget _buildSpellingStatus(AppTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    if (_showWrongFeedback) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        // 用同一条文字基线对齐 Tabler 图标和中文，避免图标看起来偏上或偏下。
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Baseline(
            baseline: 11,
            baselineType: TextBaseline.alphabetic,
            child: Icon(
              AppGlyph.wrong,
              size: AppIcon.i14,
              color: AppTokens.danger,
            ),
          ),
          const SizedBox(width: AppSpace.p1),
          Baseline(
            baseline: 11,
            baselineType: TextBaseline.alphabetic,
            child: Text(
              '拼写有误，再来一次',
              style: textTheme.fs6Semibold.copyWith(color: AppTokens.danger),
            ),
          ),
        ],
      );
    }
    if (_showCorrectFeedback) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            AppGlyph.correct,
            size: AppIcon.i14,
            color: AppTokens.success,
          ),
          const SizedBox(width: AppSpace.p1),
          Text(
            '拼写正确',
            style: textTheme.fs6Semibold.copyWith(color: AppTokens.success),
          ),
        ],
      );
    }
    return Text(
      '根据发音与释义写出单词',
      style: textTheme.fs6.copyWith(color: tokens.muted),
    );
  }

  /// 构建 HTML 原型中的下划线字母位。
  ///
  /// 所有非英文字母字符都直接显示，不占用需要用户点击的字母位；
  /// 例如 `o'clock` 开局就显示撇号，输入 `o` 后焦点直接落到 `c`。
  Widget _buildSlotRow(AppTokens tokens, String target) {
    final children = <Widget>[];
    for (var i = 0; i < target.length; i += 1) {
      final character = target[i];
      if (!_englishLetterPattern.hasMatch(character)) {
        children.add(
          SizedBox(
            width: character == ' '
                ? LetterSlotLayout.letterWidth * 0.55
                : LetterSlotLayout.letterWidth * 0.65,
            height: LetterSlotLayout.letterHeight,
            child: Center(
              child: Text(
                character == ' ' ? '' : character,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: LetterSlotLayout.letterTextSize,
                  fontWeight: AppWeight.semibold,
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final isFilled = i < _typedLetters.length;
      final isActive = i == _typedLetters.length && !_inputLocked;
      final entryToken = isFilled && i < _typedEntryTokens.length
          ? _typedEntryTokens[i]
          : null;
      final lineColor = _showWrongFeedback
          ? AppTokens.danger
          : _showCorrectFeedback
          ? AppTokens.success
          : isFilled
          ? tokens.text.withValues(alpha: AppAlpha.a36)
          : isActive
          ? AppTokens.primary
          : tokens.check;
      final textColor = _showWrongFeedback
          ? AppTokens.danger
          : _showCorrectFeedback
          ? AppTokens.success
          : tokens.text;
      children.add(
        LetterSlot(
          // 保留稳定的字母格 key，避免影响外部定位；动画是否重新开始由
          // entryToken 明确控制，而不是依赖字母格整体销毁重建。
          key: Key('spelling-slot-$i'),
          entryToken: entryToken,
          text: isFilled ? _typedLetters[i] : null,
          isActive: isActive,
          lineColor: lineColor,
          textColor: textColor,
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: LetterSlotLayout.letterGap,
      runSpacing: LetterSlotLayout.letterRunGap,
      children: children,
    );
  }

  ///
  /// 构建底部 26 键键盘。
  ///
  /// `edgeToEdge` 让键盘面板与底部区域同色并铺满可用宽度；组件内部保留
  /// 10px 左右和顶部留白，SafeArea 则负责底部手势导航区域的留白。
  Widget _buildKeyboard() {
    return QwertyKeyboard(
      edgeToEdge: true,
      enabled: !_inputLocked && !_preparing,
      onLetterTap: _onKeyTap,
      onDeleteTap: _onBackspace,
    );
  }

  ///
  /// 构建结算页，版式复刻听音辨义完成页那种极简收尾。
  ///
  /// 从上到下：圆形图标底盘 → 主标题 → 一行说明 → 返回按钮。
  /// 2×2 统计卡与「需加强」名单已随结算页统一走简单显示而下线，唯一保留的
  /// 信息是「全对 / 拼错几次」——对复习类应用来说，副标题一句话足够交代。
  Widget _buildSummary(AppTokens tokens) {
    final items = <SettlementWordItem>[];
    for (final outcome in _outcomes) {
      final word = widget.words.firstWhere(
        (item) => item.spelling == outcome.spelling,
        orElse: () => widget.words.first,
      );
      final id = word.id;
      final draft = id == null ? null : _progress.settlementFor(id);
      final correct = draft?.isCorrect ?? outcome.wrongCount == 0;
      items.add(
        SettlementWordItem(
          word: outcome.spelling,
          isCorrect: correct,
          usedTime: Duration(seconds: draft?.usedTimeSeconds ?? 0),
          // 本轮开始时的难度：草稿里记着就用草稿的，拿不到就退回到单词当前的难度。
          difficultyBefore: draft?.difficultyBefore ?? word.difficulty,
          recentResults:
              draft?.recentResults ?? <bool?>[correct, null, null, null, null],
          streak: draft != null && draft.streak > 0 ? draft.streak : null,
          initialAdjust: difficultyAdjustFromDelta(
            draft?.suggestedAdjustment ?? 0,
          ),
        ),
      );
    }
    return SettlementSummary(
      key: const Key('settlement-spelling'),
      items: items,
      // 结算页顶部用所有单词明细的实际用时汇总；右上角仍显示页面停留时间。
      aggregatedWordElapsed: Duration(
        seconds: items.fold<int>(
          0,
          (sum, item) => sum + (item.usedTime?.inSeconds ?? 0),
        ),
      ),
      onAdjust: (index, adjust) {
        final word = widget.words.firstWhere(
          (item) => item.spelling == items[index].word,
          orElse: () => widget.words.first,
        );
        final id = word.id;
        if (id != null) unawaited(_progress.adjustSettlement(id, adjust));
      },
      onRetry: () => unawaited(_leaveSummary(retry: true)),
      onConfirm: _leaveSummary,
    );
  }

  /// 提交结算草稿后离开本页；重开信号交给首页处理。
  Future<void> _leaveSummary({bool retry = false}) async {
    if (!_showSummary) {
      Navigator.of(context).pop();
      return;
    }
    if (_isCommittingSummary) return;
    _isCommittingSummary = true;
    try {
      await _progress.commitSettlement();
      if (mounted) Navigator.of(context).pop(retry);
    } catch (error) {
      _isCommittingSummary = false;
      debugPrint('提交拼写巩固结算失败：$error');
    }
  }

  ///
  /// 把本局用时格式化成计时文字：不足一小时 mm:ss，满一小时 hh:mm:ss。
  String _formatElapsed() => formatTimerSeconds(_elapsedSeconds);
}

///
/// 按 CSS 关键帧计算某一时刻的取值。
///
/// 生活化解释：关键帧只规定了 6 个时间点的位置，两点之间匀速移动，
/// 这个函数就是在算「现在走到两个关键帧之间的哪个位置了」。
double _interpolateFrames(List<double> frames, double t) {
  // 6 个关键帧把动画切成 5 段，先算出落在第几段、段内进度多少。
  final scaled = (t * (frames.length - 1)).clamp(
    0.0,
    (frames.length - 1).toDouble(),
  );
  final index = scaled.floor().clamp(0, frames.length - 2);
  final fraction = scaled - index;
  // 段内线性插值。
  return frames[index] + (frames[index + 1] - frames[index]) * fraction;
}
