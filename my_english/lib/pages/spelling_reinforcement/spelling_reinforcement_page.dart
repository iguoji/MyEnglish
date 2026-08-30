// dart:async 提供 Timer（切词停顿、抖动解锁）与 unawaited（落盘不阻塞交互）。
import 'dart:async';
// dart:math 提供 Random（确定性打乱候选片段）与 max/min。
import 'dart:math';
// material.dart 提供全屏页面、进度条与按钮。
import 'package:flutter/material.dart';
// services.dart 提供 HapticFeedback，答错时给一次轻微震动。
import 'package:flutter/services.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局设计令牌（颜色变量，随亮色/深色主题自动切换）。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角时间超过一小时改用 hh:mm:ss，不足用 mm:ss。
import '../../common/date.dart';
// 引入全局 Toast 工具，播放失败时提示用户。
import '../../common/toast.dart';
// 引入单词数据模型，首页会把当天固定词单传进来。
import '../../models/word.dart';
// 引入音节切分服务：默认切法、换一种切法、用户手动切法都走它。
import '../../services/syllable_service.dart';
// 引入音频播放接口，与首页、随身听共用同一个实现。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入单词 Store，用来把现算出来的音节拆分回写到单词行。
import '../../store/word.dart';
// 引入统一的进度出口，屏蔽「长期会话」与「复习会话」的差别。
import '../review/services/session_progress.dart';
// 引入本页面专用的候选片段生成器。
import 'services/spelling_chunk_generator.dart';
// 引入集中管理的页面布局尺寸。
import 'widgets/spelling_layout.dart';

///
/// Tabler 成功绿（`--tblr-success`），用于填对的占位格与结算页「一次拼对」。
const Color _kSuccess = Color(0xFF2FB344);

///
/// Tabler 橙色（`--tblr-orange`），用于结算页「需加强」。
const Color _kOrange = Color(0xFFF76707);

///
/// Tabler 青色（`--tblr-teal`），用于「手动拆分」模式徽标。
const Color _kTeal = Color(0xFF0CA678);

///
/// Tabler 紫色（`--tblr-purple`），用于「逐字母拼写」模式徽标。
const Color _kPurple = Color(0xFFAE3EC9);

///
/// 徽标与淡色底的兑色比例。
///
/// 生活化解释：Tabler 的 `bg-blue-lt` 是「往白底里滴一点蓝」得到的浅色块。
/// 写成比例而不是写死颜色，深色主题下兑出来就是「黑里透蓝」，
/// 不会在深色界面上突然出现一块刺眼的白。
const double _kSoftBackgroundAlpha = 0.13;

///
/// 一个单词最多允许错几次，之后自动揭示答案。
///
/// 为什么需要这个上限：如果答错只是抖一下就没事，逐字母模式下最笨的办法是
/// 26 个键挨着试，一定能过关，「拼写失误」这个统计也就失去意义。设了上限之后
/// 答错有了真实代价，同时也给「怎么都想不起来」的用户留了出口——
/// 揭示答案的那一刻，正是记忆真正被加强的时候。

///
/// 拼写巩固的两种作答方式。
///
enum SpellingMode {
  ///
  /// 片段模式：从打乱的候选块里按顺序挑出正确的几块（原型「音节拼写」）。
  chunk,

  ///
  /// 逐字母模式：用 26 键键盘一个字母一个字母拼（原型「逐字母拼写」）。
  ///
  /// 算法拆不开的短词（如 bowl）与含空格、连字符的词条都走这里。
  letter,
}

///
/// 一个单词这一局的最终结果，供结算页统计与「需加强」列表使用。
///
class SpellingWordOutcome {
  ///
  /// 创建一条单词结果。
  const SpellingWordOutcome({required this.spelling, required this.wrongCount});

  ///
  /// 单词拼写，直接显示在「需加强」标签上。
  final String spelling;

  ///
  /// 这个词累计答错几次。
  final int wrongCount;

  ///
  /// 是否一次就拼对（全程没错）。
  bool get isPerfect => wrongCount == 0;
}

///
/// 拼写巩固页面。
///
/// 玩法：听发音、看中文释义，把这个单词拼出来。拼的方式有两种，由音节切分
/// 算法决定：
/// - **片段模式**：能拆开的词（如 tradition → tra / di / tion）把正确片段和
///   一批形近干扰项打乱，用户按顺序挑；
/// - **逐字母模式**：拆不开的短词（如 bowl）或含空格、连字符的词条，用 26 键
///   键盘逐字母拼。
///
/// 底部两个工具：换一种拆分方式（刷新）、自己动手拆分（剪刀）。一个词错满
/// 答错只会抖动提示，不会揭示答案——想不起来就一直试，
/// 也让答错有真实代价。
///
/// 界面复刻 `ui/拼写巩固.html` 原型，只有「左上返回图标 + 中间数字进度 + 进度条」
/// 沿用听音辨义与词义连连的样式，让三个复习模块看起来是同一套产品。
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
    this.syllableService,
    this.wordStore,
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

  ///
  /// 音节切分服务；正式环境走 Android SQLite，测试可注入内存实现。
  final SyllableService? syllableService;

  ///
  /// 单词 Store：现算出来的音节拆分要回写到单词行。
  ///
  /// 正式环境使用 SQLite 单例，Widget 测试可传入内存替身。
  final WordStore? wordStore;

  ///
  /// 创建拼写巩固页面状态。
  @override
  State<SpellingReinforcementPage> createState() =>
      _SpellingReinforcementPageState();
}

///
/// 管理拼写巩固的当前单词、切分方案、作答进度与结算。
///
/// 这里同时驱动三条动画：作答区淡入、答错抖动、填对弹入，
/// 因此使用可挂多个 Ticker 的 TickerProviderStateMixin（复数版）。
///
class _SpellingReinforcementPageState extends State<SpellingReinforcementPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  ///
  /// 确定性随机种子：同一个单词永远得到同一种候选片段顺序。
  ///
  /// 生活化解释：中途退出再进来时，候选区的按钮排列必须和离开前一模一样，
  /// 否则用户会以为题目被换掉了。种子 + 单词下标就能保证这一点，
  /// 也就不必把整个候选池写进数据库。
  static const int _seed = 0x5370656C; // 'Spel'

  ///
  /// 当前单词在本局固定词单中的下标。
  int _wordIndex = 0;

  ///
  /// 当前单词的切分结果；长度为 1 表示这个词拆不开。
  List<String> _parts = const <String>[];

  ///
  /// 当前作答方式。
  SpellingMode _mode = SpellingMode.letter;

  ///
  /// 片段模式下已经填对的占位格数量。
  int _filledChunks = 0;

  ///
  /// 逐字母模式下已经拼出的字符（含自动补上的空格与连字符）。
  final List<String> _typedLetters = <String>[];

  ///
  /// 当前单词打乱后的候选片段池。
  List<SpellingChunk> _pool = const <SpellingChunk>[];

  ///
  /// 是否处于「自己动手拆分」的编辑态。
  bool _manualMode = false;

  ///
  /// 手动拆分的剪口位置集合；元素 n 表示在第 n 个字母之后剪开。
  final Set<int> _manualCuts = <int>{};

  ///
  /// 当前单词已经答错的次数；只用于结算页统计，不再触发任何自动揭示。
  int _currentWrong = 0;

  ///
  /// 本局每个已完成单词的结果，供结算页统计与「需加强」列表使用。
  final List<SpellingWordOutcome> _outcomes = <SpellingWordOutcome>[];

  ///
  /// 本局累计答错次数（跨单词累加），决定这一局的错误统计。
  int _errors = 0;

  ///
  /// 本局已经过去的毫秒数；只在页面处于前台且未结算时累加。
  int _elapsedMs = 0;

  ///
  /// 本局是否已经把全部单词走完一遍。
  bool _completed = false;

  ///
  /// 是否正在等待音节切分结果（读数据库或现场计算）。
  ///
  /// 这段时间作答区留空，避免用旧单词的候选块闪一下。
  bool _preparing = true;

  ///
  /// 答错反馈或切词停顿期间的输入锁。
  ///
  /// 生活化解释：答错后按钮要红着脸抖 0.35 秒、拼对后最后一格要绿着停 0.5 秒。
  /// 这两段时间如果还能继续点，反馈会被下一次点击立刻打断，用户根本看不清
  /// 自己错在哪、或者错误会被记到下一个单词头上。
  bool _inputLocked = false;

  ///
  /// 正在播放答错抖动的候选片段在池中的下标；-1 表示当前没有。
  int _wrongChunkIndex = -1;

  ///
  /// 正在播放答错抖动的键盘按键字母；空串表示当前没有。
  String _wrongKeyLabel = '';

  ///
  /// 正在播放答错抖动的占位格下标；-1 表示当前没有。
  int _wrongSlotIndex = -1;

  ///
  /// 刷新按钮是否正在抖动（提示「没有别的拆分方式了」）。
  bool _refreshShaking = false;

  ///
  /// 当前单词的发音是否仍在播放。
  bool _isPlaying = false;

  ///
  /// 当前音频请求代次，只允许最新请求更新播放状态。
  int _playGeneration = 0;

  ///
  /// 本次进入页面后是否已经提示过正在使用系统 TTS。
  bool _hasShownTtsNotice = false;

  ///
  /// 已经写过复习记录的单词下标，防止恢复进度后重复写入。
  final Set<int> _recordedIndexes = <int>{};

  ///
  /// 答错抖动的解锁定时器；页面销毁时必须取消，避免定时器泄漏。
  Timer? _unlockTimer;

  ///
  /// 刷新按钮抖动的复位定时器。
  ///
  /// 与 [_unlockTimer] 分开：这两段抖动可能在 350 毫秒内先后发生，
  /// 共用一把定时器会让先开始的那段永远复位不了。
  Timer? _refreshShakeTimer;

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
  /// 作答区淡入控制器：切词或切换作答方式时从 0 播到 1（原型 `.fade-switch`）。
  late final AnimationController _fadeController;

  ///
  /// 答错抖动控制器：同一时刻只会有一个元素在抖，因此共用一个控制器。
  late final AnimationController _shakeController;

  ///
  /// 填对弹入控制器：每填对一格都从 0 重新播到 1（原型 `popIn`）。
  late final AnimationController _popController;

  ///
  /// 本局进度的落盘出口，在 initState 里创建一次。
  SessionProgress get _progress => widget.progress;

  ///
  /// 音节切分服务；正式环境走 Android SQLite，测试可注入内存实现。
  late final SyllableService _syllables;

  ///
  /// 当前正在拼写的单词。
  Word get _currentWord => widget.words[_wordIndex];

  ///
  /// 本局总词量。
  int get _total => widget.words.length;

  ///
  /// 是否展示结算页。
  bool get _showSummary => _completed;

  ///
  /// 一次就拼对的单词数量（全程没错、也没被揭示）。
  int get _perfectCount =>
      _outcomes.where((outcome) => outcome.isPerfect).length;

  ///
  /// 需要加强的单词：错过或被揭示过答案的那些。
  List<SpellingWordOutcome> get _weakOutcomes =>
      _outcomes.where((outcome) => !outcome.isPerfect).toList(growable: false);

  ///
  /// 顶栏中间显示的「第几个」：结算时显示总数，答题时显示当前序号。
  int get _displayIndex => _showSummary ? _total : _wordIndex + 1;

  ///
  /// 进度条填充比例：已经完成的单词数占总数的比例。
  double get _progressRatio =>
      _total > 0 ? (_outcomes.length / _total).clamp(0.0, 1.0) : 0.0;

  ///
  /// 当前单词是否允许手动拆分。
  ///
  /// 含空格、连字符或撇号的词条（ice cream、T-shirt、I'm）拆出来的片段会很怪，
  /// 这类词固定走逐字母模式，剪刀按钮直接禁用。
  bool get _canManualSplit =>
      RegExp(r'^[A-Za-z]{2,}$').hasMatch(_currentWord.spelling.trim());

  // ===== 以下为生命周期 =====

  ///
  /// 初始化页面：建好动画与进度出口，恢复历史进度，再准备第一个单词。
  @override
  void initState() {
    super.initState();
    // 监听前后台变化：退到后台停表并停止发音，回到前台再继续。
    WidgetsBinding.instance.addObserver(this);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: SpellingLayout.fadeDurationMs),
      // 初值直接给 1：首帧就是完整不透明，只有切词时才重播。
      value: 1,
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: SpellingLayout.shakeDurationMs),
    );
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: SpellingLayout.popDurationMs),
      value: 1,
    );
    // 音节服务是纯计算的；算出来的拆分由本页回写到单词行。
    _syllables = widget.syllableService ?? SyllableService();
    // 先恢复历史进度（可能直接恢复到已结算状态），再准备当前单词。
    _restoreProgress();
    if (!_showSummary) {
      // keepProgress 必须为 true：上一行刚恢复出来的「当前词已填几格 / 已拼哪些
      // 字母」由 _adoptParts 决定保留还是清零，漏传就等于把续玩进度扔掉。
      unawaited(_prepareCurrentWord(autoSpeak: true, keepProgress: true));
      _startElapsedTimer();
    } else {
      _preparing = false;
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
    final session = _progress.session;
    // 当前单词下标；夹在合法区间内，防止词库变动后越界。
    _wordIndex = session.cursor.clamp(0, _total - 1);
    _elapsedMs = session.elapsed * 1000;
    // 累计错误由记录直接数出来：错完就退、退完再进，不能刷出一局「全对」。
    _errors = _progress.wrongCount;

    // 回放已完成单词的结果：一个词只要在记录里出现过「答对」，就算走完了。
    for (
      var index = 0;
      index < _wordIndex && index < widget.words.length;
      index += 1
    ) {
      final word = widget.words[index];
      final wordId = word.id;
      if (wordId == null) continue;
      final wordProgress = _progress.progressOf(wordId);
      _outcomes.add(
        SpellingWordOutcome(
          spelling: word.spelling,
          // 这个词在本局错过几次，直接数记录。
          wrongCount: _progress.allRecords
              .where((record) => record.wordId == wordId && !record.isCorrect)
              .length,
        ),
      );
      // 已经结算过的词不再重复结算。
      if (wordProgress.answeredMeaningIds.isNotEmpty ||
          wordProgress.spellingDone) {
        _recordedIndexes.add(index);
      }
    }
    // 全部走完就直接进结算页。
    _completed = _outcomes.length >= _total;
  }

  ///
  /// 准备当前单词：取切分方案、决定作答方式、生成候选池。
  ///
  /// [autoSpeak] 为 true 时在准备完成后自动发一次音（进入新词时用）。
  /// [keepProgress] 为 true 表示这是恢复进度，不重置已填格数。
  Future<void> _prepareCurrentWord({
    bool autoSpeak = false,
    bool keepProgress = false,
  }) async {
    final spelling = _currentWord.spelling.trim();
    // 含空格、连字符或撇号的词条不做片段拆分：切出来的块很怪，也没法生成干扰项。
    List<String> parts;
    if (!_canManualSplit) {
      parts = <String>[spelling];
    } else {
      // 音节拆分住在单词行上：存过就直接用，没存过当场算一份并回写。
      if (_currentWord.syllables.isNotEmpty) {
        parts = _currentWord.syllables;
      } else {
        parts = _syllables.split(spelling);
        unawaited(_saveSyllables(parts));
      }
    }
    if (!mounted) return;
    setState(() {
      _adoptParts(parts, keepProgress: keepProgress);
      _preparing = false;
    });
    // 作答区整块淡入上移，对应原型的 fade-switch。
    _fadeController.forward(from: 0);
    // 恢复的快照可能正好停在「最后一格已填、还没翻页」那半秒里（用户就在那时
    // 退出）。这种词其实已经拼完了，必须接着把它翻过去：片段模式下所有正确
    // 片段都已变灰不可点，用户手上没有任何操作能让它继续，这一局会卡死。
    if (keepProgress && _isCurrentWordComplete) {
      _onWordSolved();
      return;
    }
    if (autoSpeak) _scheduleAutoSpeak();
  }

  ///
  /// 当前单词是不是已经拼完了。
  ///
  /// 两种作答方式各有各的「拼完」标准：片段模式看格子填满没有，
  /// 逐字母模式看字符数够不够。空拼写的脏数据不算拼完，否则会一直自动翻页。
  bool get _isCurrentWordComplete {
    if (_mode == SpellingMode.chunk) {
      return _parts.isNotEmpty && _filledChunks >= _parts.length;
    }
    final target = _currentWord.spelling.trim();
    return target.isNotEmpty && _typedLetters.length >= target.length;
  }

  ///
  /// 采用一份切分结果：决定作答方式并重建候选池。
  ///
  /// 必须在 setState 内部调用。[keepProgress] 为 true 时保留已填进度
  /// （恢复会话用），否则清零重来（切词或换拆分方式用）。
  void _adoptParts(List<String> parts, {bool keepProgress = false}) {
    // 切分结果为空是不该发生的防御分支，按整词处理。
    _parts = parts.isEmpty ? <String>[_currentWord.spelling.trim()] : parts;
    // 真正拆得开（两块以上）才进片段模式，否则用键盘逐字母拼。
    // 这里必须判 length > 1 而不是 isNotEmpty：音节服务对拆不开的词
    // 会返回「整词」这一个元素，那种情况下片段模式只有一个按钮，点一下就过关。
    _mode = _parts.length > 1 ? SpellingMode.chunk : SpellingMode.letter;
    if (!keepProgress) {
      _filledChunks = 0;
      _typedLetters.clear();
    }
    // 片段池必须跟着切分方案一起重建，否则会拿上一种切法的按钮去拼新切法。
    _pool = _mode == SpellingMode.chunk
        ? SpellingChunkGenerator.buildPool(
            parts: _parts,
            // 种子里混入单词下标与切分方案，保证「同一个词的同一种切法」
            // 每次都得到相同顺序，而不同的词或不同切法各有各的顺序。
            random: Random(_seed ^ _wordIndex ^ _parts.join('|').hashCode),
          )
        : const <SpellingChunk>[];
    // 逐字母模式下开头可能就是非字母字符（理论上不会），先自动补齐。
    if (_mode == SpellingMode.letter) _autoFillNonLetters();
    // 恢复进度时可能读到越界的旧快照，夹回合法范围。
    _filledChunks = _filledChunks.clamp(0, _parts.length);
    if (_typedLetters.length > _currentWord.spelling.trim().length) {
      _typedLetters.removeRange(
        _currentWord.spelling.trim().length,
        _typedLetters.length,
      );
    }
    // 换过切分方式后手动编辑态要收起来，剪口也不再有意义。
    _manualMode = false;
    _manualCuts.clear();
  }

  ///
  /// 逐字母模式下自动补齐当前位置之后的非字母字符。
  ///
  /// 生活化解释：ice cream 中间那个空格、T-shirt 中间那个连字符，用户在 26 键
  /// 键盘上根本打不出来。所以每拼完一个字母，就顺手把后面紧跟着的空格、
  /// 连字符、撇号自动填上，光标停在下一个真正需要用户输入的字母上。
  void _autoFillNonLetters() {
    final target = _currentWord.spelling.trim();
    while (_typedLetters.length < target.length) {
      final next = target[_typedLetters.length];
      if (RegExp(r'^[A-Za-z]$').hasMatch(next)) break;
      _typedLetters.add(next);
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
  /// 打断旧音频，确保切词后立即播放新单词。
  Future<void> _playAudio({bool interrupt = false}) async {
    if (_showSummary) return;
    // 手动点击且正在播放中：保持防连点体验，直接忽略。
    if (_isPlaying && !interrupt) return;
    // 领取本次播放的代次号（前置 ++ 先自增再取值，保证全局唯一且递增）。
    final generation = ++_playGeneration;
    setState(() => _isPlaying = true);
    try {
      // await 会一直等到原生音频播放完毕（或被新播放打断而抛异常）。
      await widget.audioPlayer.playRandomChannel(
        _currentWord.spelling,
        widget.accent,
      );
      // 随机渠道模式下 TTS 可能是被故意选中（而非网络兜底），此时不提示网络不可用。
      final playback = widget.audioPlayer.consumeLastPlayback();
      if (!_hasShownTtsNotice &&
          playback.usedTts &&
          !playback.isRandomChannel) {
        _hasShownTtsNotice = true;
        if (mounted) {
          Toast.show(context, '当前网络音频不可用，正在使用系统 TTS 朗读');
        }
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
        setState(() => _isPlaying = false);
      }
    }
  }

  // ===== 以下为作答交互 =====

  ///
  /// 点击一个候选片段。
  ///
  /// [index] 是它在候选池中的下标，用于定位该抖哪一个按钮
  /// （同一个文本可能在池里出现多次，只能靠下标区分）。
  void _onChunkTap(int index) {
    if (_showSummary || _inputLocked || _manualMode || _preparing) return;
    // 格子已经填满就不再取「这一格该填什么」——那会越界。填满后正常是锁着输入
    // 等翻页，但恢复进度时可能一进来就是填满状态。
    if (_filledChunks >= _parts.length) return;
    // 已经用掉的按钮不再响应（视觉上也是变灰的）。
    if (_isChunkUsed(index)) return;
    final expected = _parts[_filledChunks];
    final picked = _pool[index].text;
    // 判错：文本不对，或文本对但不是这一格该填的（顺序错）。
    if (picked != expected) {
      _onWrongAnswer(chunkIndex: index, slotIndex: _filledChunks);
      return;
    }
    setState(() => _filledChunks += 1);
    // 填对的那一格弹一下，视觉上确认「这块放进去了」。
    _popController.forward(from: 0);
    unawaited(_persist());
    // 全部格子填满：这个词拼完了。
    if (_filledChunks >= _parts.length) _onWordSolved();
  }

  ///
  /// 判断候选池中某个按钮是否已经被用掉。
  ///
  /// 规则：按顺序消耗。第 k 格填的必然是 `_parts[k]`，所以「已用掉的按钮」
  /// 就是那些文本出现在 `_parts` 前 `_filledChunks` 项里、且在池中同名按钮里
  /// 排在前面的那几个。这样 ["tar","tar"] 这种重复片段也能正确变灰两个。
  bool _isChunkUsed(int index) {
    final text = _pool[index].text;
    // 这个文本在「已填部分」里出现了几次，就该有几个同名按钮变灰。
    var consumed = 0;
    for (var k = 0; k < _filledChunks && k < _parts.length; k += 1) {
      if (_parts[k] == text) consumed += 1;
    }
    if (consumed == 0) return false;
    // 该按钮是池中第几个同名按钮。
    var rank = 0;
    for (var i = 0; i < index; i += 1) {
      if (_pool[i].text == text) rank += 1;
    }
    return rank < consumed;
  }

  ///
  /// 点击键盘上的一个字母。
  void _onKeyTap(String letter) {
    if (_showSummary || _inputLocked || _manualMode || _preparing) return;
    final target = _currentWord.spelling.trim();
    // 已经拼满就不再接受输入（切词停顿期间的保险）。
    if (_typedLetters.length >= target.length) return;
    final expected = target[_typedLetters.length];
    // 键盘统一显示小写，比较时忽略大小写；存进去的是词库里的原始大小写。
    if (letter.toLowerCase() != expected.toLowerCase()) {
      _onWrongAnswer(keyLabel: letter, slotIndex: _typedLetters.length);
      return;
    }
    setState(() {
      _typedLetters.add(expected);
      // 紧跟其后的空格、连字符自动补上，光标落到下一个真正要输入的字母。
      _autoFillNonLetters();
    });
    _popController.forward(from: 0);
    unawaited(_persist());
    if (_typedLetters.length >= target.length) _onWordSolved();
  }

  ///
  /// 点击退格：删掉最后一个用户输入的字母。
  ///
  /// 自动补上的空格与连字符会一并退掉——它们不是用户输入的，
  /// 留在那里会让用户以为退格失灵了。
  void _onBackspace() {
    if (_showSummary || _inputLocked || _manualMode || _preparing) return;
    if (_typedLetters.isEmpty) return;
    setState(() {
      // 先退掉末尾那些自动补的非字母字符。
      while (_typedLetters.isNotEmpty &&
          !RegExp(r'^[A-Za-z]$').hasMatch(_typedLetters.last)) {
        _typedLetters.removeLast();
      }
      // 再退掉一个真正的字母。
      if (_typedLetters.isNotEmpty) _typedLetters.removeLast();
    });
    unawaited(_persist());
  }

  ///
  /// 处理一次答错：累计错误、抖动反馈、留一条记录。
  ///
  /// [chunkIndex] 片段模式下点错的按钮下标；[keyLabel] 逐字母模式下点错的字母；
  /// [slotIndex] 当前正在填的那一格，用来让占位格一起变红抖动。
  void _onWrongAnswer({int? chunkIndex, String? keyLabel, int? slotIndex}) {
    setState(() {
      _errors += 1;
      _currentWrong += 1;
      _wrongChunkIndex = chunkIndex ?? -1;
      _wrongKeyLabel = keyLabel ?? '';
      _wrongSlotIndex = slotIndex ?? -1;
      _inputLocked = true;
    });
    _shakeController.forward(from: 0);
    // 轻微震动：眼睛在看占位格时，手上也能感到「这下错了」。
    unawaited(HapticFeedback.selectionClick());
    // 记一条「点错了」：结算难度时靠它判定这一轮答错，
    // 首页的复习数字与热力图也靠这些记录汇总。
    unawaited(
      _recordAttempt(
        // 记下用户实际点的那个音节块或字母，回看时能看出错在哪。
        input: keyLabel ?? (chunkIndex != null ? _pool[chunkIndex].text : ''),
        isCorrect: false,
      ),
    );
    unawaited(_persist());
    _unlockTimer?.cancel();
    _unlockTimer = Timer(
      const Duration(milliseconds: SpellingLayout.shakeDurationMs),
      () {
        if (!mounted) return;
        setState(() {
          _wrongChunkIndex = -1;
          _wrongKeyLabel = '';
          _wrongSlotIndex = -1;
          _inputLocked = false;
        });
      },
    );
  }

  ///
  /// 当前单词拼对：记一条、锁住输入、停顿一下再进下一个词。
  void _onWordSolved() {
    // 拼对也留痕：没有这一条，本局这个词在数据库里就等于「没练过」，
    // 首页的今日复习数与打卡热力图都统计不到它。
    unawaited(_recordAttempt(input: _currentWord.spelling, isCorrect: true));
    setState(() => _inputLocked = true);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(
      const Duration(milliseconds: SpellingLayout.wordAdvanceDelayMs),
      _goToNextWord,
    );
  }

  ///
  /// 结束当前单词并推进：写记录、清状态，还有词就准备下一个，否则结算。
  void _goToNextWord() {
    if (!mounted) return;
    // 先把这个词的结果定格下来（结算页统计与「需加强」名单都靠它）。
    final outcome = SpellingWordOutcome(
      spelling: _currentWord.spelling,
      wrongCount: _currentWrong,
    );
    // 这个词尘埃落定，给它结算难度。
    unawaited(_recordCurrentWord(outcome));

    final isLast = _wordIndex + 1 >= _total;
    setState(() {
      _outcomes.add(outcome);
      _currentWrong = 0;
      _inputLocked = false;
      if (isLast) {
        _completed = true;
      } else {
        _wordIndex += 1;
        // 新词的切分方案要重新取，先清空避免旧候选闪一帧。
        _parts = const <String>[];
        _pool = const <SpellingChunk>[];
        _filledChunks = 0;
        _typedLetters.clear();
        _preparing = true;
      }
    });
    if (isLast) {
      // 整局已经结束，彻底停表，避免结算页期间定时器继续空转。
      _stopElapsedTimer();
      unawaited(_finishSession());
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
    try {
      await _progress.record(
        wordId: wordId,
        input: input,
        isCorrect: isCorrect,
      );
    } catch (error) {
      // 写记录失败不该打断答题，最多这一次点击没留痕。
      debugPrint('写入拼写巩固点击记录失败：$error');
    }
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
      await _progress.settle(wordId);
    } catch (error) {
      // 结算失败不该打断正在进行的一局；集合里放回去，后面还有机会补算。
      _recordedIndexes.remove(_wordIndex);
      debugPrint('拼写巩固结算单词失败：$error');
    }
  }

  ///
  /// 把当场算出来的音节拆分回写到单词行。
  ///
  /// 写失败只记日志：拆分是可再生的派生数据，下次进来重算一遍就有了。
  Future<void> _saveSyllables(List<String> parts) async {
    final wordId = _currentWord.id;
    if (wordId == null) return;
    try {
      await (widget.wordStore ?? LocalWordStore.instance).saveWordSyllables(
        wordId,
        parts,
      );
    } catch (error) {
      debugPrint('保存音节拆分失败：$error');
    }
  }

  // ===== 以下为两个工具按钮 =====

  ///
  /// 换一种拆分方式。
  ///
  /// 走音节服务的 `nextAlternative`，并要求它跳过「整词」那一档——整词只会
  /// 生成一个候选按钮，点一下就过关，等于把题目送掉。若这个词根本没有别的
  /// 合法切法（返回结果和当前一样），刷新按钮抖一下表示「就这一种」。
  ///
  /// 注意：这个动作会把新切法写进音节表（source=refresh），也就是说下次遇到
  /// 这个词时默认就是新切法。这是音节服务既有的设计，拼写巩固沿用它，
  /// 用户会感到「我调过的拆分方式被记住了」。
  Future<void> _refreshSplit() async {
    if (_showSummary || _inputLocked || _manualMode || _preparing) return;
    // 含空格连字符的词条固定走逐字母模式，没有拆分可换。
    if (!_canManualSplit) {
      _shakeRefreshButton();
      return;
    }
    final before = _parts.join('|');
    List<String> next;
    try {
      next = _syllables.nextAlternative(
        _currentWord.spelling.trim(),
        current: _parts,
        splitOnly: true,
      );
    } catch (error) {
      debugPrint('切换音节划分失败：$error');
      _shakeRefreshButton();
      return;
    }
    if (!mounted) return;
    // 没有别的切法（含「用户手动划分不参与刷新」这种情况）：抖一下维持原状。
    if (next.join('|') == before) {
      _shakeRefreshButton();
      return;
    }
    setState(() => _adoptParts(next));
    _fadeController.forward(from: 0);
    unawaited(_persist());
  }

  ///
  /// 让刷新按钮抖一下，表示「这个词没有别的拆分方式了」。
  void _shakeRefreshButton() {
    setState(() => _refreshShaking = true);
    _shakeController.forward(from: 0);
    // 刻意不复用 _unlockTimer：那把定时器归答错反馈用。两者共用的话，抖动这
    // 350 毫秒里答一次错就会把这里的复位回调取消掉，_refreshShaking 永久停在
    // true，之后每次答错刷新按钮都会莫名跟着一起抖。
    _refreshShakeTimer?.cancel();
    _refreshShakeTimer = Timer(
      const Duration(milliseconds: SpellingLayout.shakeDurationMs),
      () {
        if (!mounted) return;
        setState(() => _refreshShaking = false);
      },
    );
  }

  ///
  /// 进入或退出「自己动手拆分」编辑态。
  void _toggleManualSplit() {
    if (_showSummary || _inputLocked || _preparing) return;
    if (!_canManualSplit) return;
    setState(() {
      _manualMode = !_manualMode;
      // 每次进入都从当前切分方案的剪口开始，用户可以在它基础上增删。
      _manualCuts.clear();
      if (_manualMode) {
        var position = 0;
        for (var i = 0; i < _parts.length - 1; i += 1) {
          position += _parts[i].length;
          _manualCuts.add(position);
        }
      }
    });
    _fadeController.forward(from: 0);
  }

  ///
  /// 在第 [position] 个字母之后添加或取消一个剪口。
  void _toggleCut(int position) {
    setState(() {
      if (!_manualCuts.remove(position)) _manualCuts.add(position);
    });
  }

  ///
  /// 按当前剪口应用手动拆分。
  ///
  /// 手动划分是最高优先级（source=user），落库之后连「刷新」都不会覆盖它——
  /// 这是音节服务既有的规则：用户亲手划的，机器不该擅自改回去。
  Future<void> _applyManualSplit() async {
    final spelling = _currentWord.spelling.trim();
    final cuts = _manualCuts.toList()..sort();
    // 一个剪口都没有等于整词，那就不是「拆分」了。
    if (cuts.isEmpty) return;
    final parts = <String>[];
    var previous = 0;
    for (final cut in <int>[...cuts, spelling.length]) {
      // 越界或重复的剪口一律跳过，保证切出来的每一块都非空。
      if (cut <= previous || cut > spelling.length) continue;
      parts.add(spelling.substring(previous, cut));
      previous = cut;
    }
    // 切不出两块以上就没有意义，维持原状。
    if (parts.length < 2) return;
    try {
      await _saveSyllables(parts);
    } catch (error) {
      // 落库失败不影响本局按新切法作答，只是下次进来不会记住。
      debugPrint('保存手动音节划分失败：$error');
    }
    if (!mounted) return;
    setState(() => _adoptParts(parts));
    _fadeController.forward(from: 0);
    unawaited(_persist());
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
  /// 再练一组。
  ///
  /// 这里不在页面内部重开，而是带着「再来一局」的信号退回首页，由首页重新
  /// 走一遍 ReviewFlow。原因是「下一局该开什么」并不由本页面决定：
  /// - 刚才那局失败了 → 下一局仍是今天的主线，单词还是今天这批；
  /// - 刚才那局过关了 → 下一局是无限巩固，单词换成「今天一半 + 明天一半」。
  ///
  /// 判断这件事需要完整词库，只有首页有。放在这里猜等于把规则抄两份，
  /// 迟早会和 ReviewFlow 对不上。用户感受不到差别——依然是点一下就重开。
  void _restart() {
    // 先停掉所有定时器，避免转场期间回调还在跑。
    _stopElapsedTimer();
    _advanceTimer?.cancel();
    _unlockTimer?.cancel();
    _refreshShakeTimer?.cancel();
    _autoSpeakTimer?.cancel();
    Navigator.pop(context, true);
  }

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
    // 退后台时让下一次播放重新提示 TTS，并作废正在进行的播放请求。
    _hasShownTtsNotice = false;
    ++_playGeneration;
    if (mounted) setState(() => _isPlaying = false);
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    if (!_showSummary) unawaited(_persist());
  }

  ///
  /// 页面被移出导航栈（返回/退出）时立即停表。
  @override
  void deactivate() {
    // 转场一开始就把计时器停掉，把主线程让给返回动画，避免卡顿。
    _stopElapsedTimer();
    super.deactivate();
  }

  /// 页面被重新挂回树时恢复计时，兼容返回手势取消等临时离场场景。
  @override
  void activate() {
    super.activate();
    if (!_showSummary) _startElapsedTimer();
  }

  @override
  void dispose() {
    // 注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    _stopElapsedTimer();
    _advanceTimer?.cancel();
    _unlockTimer?.cancel();
    _refreshShakeTimer?.cancel();
    _autoSpeakTimer?.cancel();
    _fadeController.dispose();
    _shakeController.dispose();
    _popController.dispose();
    // 离场即停声，避免退回首页后还在念这个单词。
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    // 停表并保存当前进度；completed 也会在此落盘（首页据此显示状态）。
    unawaited(_persist());
    super.dispose();
  }

  // ===== 以下为界面构建 =====

  ///
  /// 构建拼写巩固页面。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.card,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏与进度条：三个复习模块完全一致，切换时顶部不跳动。
            _buildHeader(tokens),
            if (_showSummary)
              Expanded(child: _buildSummary(tokens))
            else
              Expanded(child: _buildGame(tokens)),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建顶栏与进度条。
  ///
  /// 左：返回键（与另两个模块完全相同的 34×34 画布 + 21 像素 Tabler 图标）；
  /// 中：第几个 / 总数（16 像素等宽数字）；
  /// 右：与左侧等宽的占位，保证中间数字严格居中（原型也是这么做的）。
  Widget _buildHeader(AppTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SpellingLayout.pageInset,
            SpellingLayout.headerTop,
            SpellingLayout.pageInset,
            0,
          ),
          // 用 Stack 而不是 Row：左右两侧宽度不一定相等，
          // 只有绝对定位才能保证中间数字严格居中。
          child: SizedBox(
            height: SpellingLayout.headerButtonSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$_displayIndex / $_total',
                      key: const Key('spelling-progress-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: SpellingLayout.headerProgressTextSize,
                        fontWeight: FontWeight.w600,
                        // 等宽数字让计数变化时视觉中心不抖动。
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: SpellingLayout.headerButtonSize,
                    height: SpellingLayout.headerButtonSize,
                    child: InkWell(
                      key: const Key('close-spelling'),
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(
                        SpellingLayout.headerButtonSize / 2,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          TablerIcons.chevronLeft,
                          size: SpellingLayout.headerIconSize,
                          color: tokens.textMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatElapsed(),
                    key: const Key('spelling-elapsed'),
                    style: TextStyle(
                      color: tokens.textMedium,
                      // 与听音辨义、看义选词、词义连连右上角时间保持同一字号。
                      fontSize: SpellingLayout.headerTimerTextSize,
                      fontWeight: FontWeight.w500,
                      // 等宽数字让秒数变化时整体宽度稳定，右侧不抖动。
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SpellingLayout.pageInset,
            SpellingLayout.progressTop,
            SpellingLayout.pageInset,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SpellingLayout.progressRadius),
            child: LinearProgressIndicator(
              key: const Key('spelling-progress'),
              value: _progressRatio,
              minHeight: SpellingLayout.progressHeight,
              backgroundColor: tokens.sub,
              color: AppTokens.accent,
            ),
          ),
        ),
      ],
    );
  }

  ///
  ///
  /// 构建答题主体：模式徽标 + 占位格 + 全部含义 + 作答区 + 底部工具条。
  ///
  /// 整块主体都可以点：点在空白处（不是按钮上）会重播发音，与原型一致。
  /// behavior: opaque 让透明的空白区域也能接收点击。
  Widget _buildGame(AppTokens tokens) {
    return GestureDetector(
      key: const Key('spelling-blank-replay'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_playAudio()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SpellingLayout.pageInset,
          SpellingLayout.bodyVerticalInset,
          SpellingLayout.pageInset,
          SpellingLayout.bodyVerticalInset + SpellingLayout.toolBarBottomGap,
        ),
        child: Column(
          children: [
            // 顶部只有模式徽标，不再叠加释义和喇叭。
            _buildQuestionHeader(tokens),
            const SizedBox(height: SpellingLayout.badgeBottomGap),
            // 中间是拼写占位格。
            _buildSlotRow(tokens),
            const SizedBox(height: SpellingLayout.meaningBottomGap),
            // 占位格之后展示当前单词的全部含义与词性，作为拼写时的确认参照。
            _buildMeanings(tokens),
            const SizedBox(height: SpellingLayout.slotBottomGap),
            // 作答区贴着底部：键盘和候选块靠下，拇指更容易够到。
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(child: _buildAnswerArea(tokens)),
              ),
            ),
            const SizedBox(height: SpellingLayout.toolBarTop),
            _buildToolBar(tokens),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建题面顶部：只显示当前模式徽标，帮助用户知道自己在练哪种拼写。
  ///
  /// 中文释义移到占位格下方 [_buildMeanings] 集中展示，顶部不再重复出现；
  /// 同时去掉了原先的喇叭按钮，发音仍可通过点空白区域重播。
  Widget _buildQuestionHeader(AppTokens tokens) {
    // 三种作答方式各有一个颜色，和原型的三种徽标底色对应。
    final (label, color) = switch (_mode) {
      SpellingMode.chunk => ('片段拼写', AppTokens.accent),
      SpellingMode.letter => ('逐字母拼写', _kPurple),
    };
    // 手动拆分过的词单独用青色，让用户知道现在用的是自己划的切法。
    final isManual = _manualCuts.isNotEmpty && _mode == SpellingMode.chunk;
    final badgeLabel = isManual ? '手动拆分' : label;
    final badgeColor = isManual ? _kTeal : color;

    // 顶部只保留一个居中的模式徽标。
    return Column(
      children: [
        Container(
          key: const Key('spelling-mode-badge'),
          padding: const EdgeInsets.symmetric(
            horizontal: SpellingLayout.badgePaddingHorizontal,
            vertical: SpellingLayout.badgePaddingVertical,
          ),
          decoration: BoxDecoration(
            // 把主色按极低比例兑进卡片底色，得到 Tabler `bg-*-lt` 那种淡底；
            // 深色主题下兑出来是「黑里透色」，不会突然出现刺眼的白块。
            color: Color.alphaBlend(
              badgeColor.withValues(alpha: _kSoftBackgroundAlpha),
              tokens.card,
            ),
            borderRadius: BorderRadius.circular(SpellingLayout.badgeRadius),
          ),
          child: Text(
            badgeLabel,
            style: TextStyle(
              color: badgeColor,
              fontSize: SpellingLayout.badgeTextSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建当前单词的全部含义与词性列表。
  ///
  /// 放在占位格下方，借鉴随身听的排版：每条含义都从同一根竖线起，左边固定
  /// 宽度的词性列（n. / vt. …）严格对齐，右侧展示该词性下的全部中文释义，
  /// 让用户在拼写答案时能一眼比对其中的任一含义。
  Widget _buildMeanings(AppTokens tokens) {
    // 词性分组由模型统一整理好，页面直接照着画。
    final meanings = _currentWord.meaningGroups;
    // 完全没有释义时给一句话，避免整段含义区空白。
    if (meanings.isEmpty) {
      return Center(
        child: Text(
          '（这个词还没有中文释义）',
          style: TextStyle(
            color: tokens.muted,
            fontSize: SpellingLayout.meaningTextSize,
          ),
        ),
      );
    }
    // 居中但内容左对齐，行内用 Row 让词性与释义各自固定在一列里。
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        // 限制最大宽度，避免超长释义在平板上横向铺满整行影响阅读。
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < meanings.length; index += 1) ...[
              if (index > 0)
                const SizedBox(height: SpellingLayout.meaningRowGap),
              // 词性在固定宽度列，释义撑满剩余宽度，纵向都从顶部开始对齐。
              Row(
                key: Key(
                  'spelling-meaning-${meanings[index].meanings.first.id}',
                ),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: SpellingLayout.posColumnWidth,
                    child: Text(
                      meanings[index].pos,
                      key: Key(
                        'spelling-pos-${meanings[index].meanings.first.id}',
                      ),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: SpellingLayout.meaningPosTextSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: SpellingLayout.posMeaningGap),
                  Expanded(
                    child: Text(
                      meanings[index].joinedDefinitions('，'),
                      key: Key(
                        'spelling-definition-${meanings[index].meanings.first.id}',
                      ),
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: SpellingLayout.meaningTextSize,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  ///
  /// 构建占位格区：片段模式一格一块，逐字母模式一格一个字母。
  ///
  /// 逐字母模式下的空格与连字符不占格子，直接以文本形式显示在两格之间——
  /// 它们是自动补上的，做成格子会让用户以为需要自己输入。
  Widget _buildSlotRow(AppTokens tokens) {
    // 切分方案还没取回来时先留白，避免用旧词的格子闪一帧。
    if (_preparing) {
      return const SizedBox(height: SpellingLayout.slotHeight);
    }
    final children = <Widget>[];
    if (_mode == SpellingMode.chunk) {
      for (var i = 0; i < _parts.length; i += 1) {
        children.add(
          _SpellingSlot(
            key: Key('spelling-slot-$i'),
            text: i < _filledChunks ? _parts[i] : '',
            isFilled: i < _filledChunks,
            isWrong: _wrongSlotIndex == i,
            // 只有刚填上的那一格才播弹入动画。
            isJustFilled: i == _filledChunks - 1,
            isLetterSlot: false,
            tokens: tokens,
            shake: _shakeController,
            pop: _popController,
          ),
        );
      }
    } else {
      final target = _currentWord.spelling.trim();
      for (var i = 0; i < target.length; i += 1) {
        final character = target[i];
        // 非字母（空格、连字符、撇号）不做格子，只占一点视觉宽度。
        if (!RegExp(r'^[A-Za-z]$').hasMatch(character)) {
          children.add(
            SizedBox(
              width: SpellingLayout.slotGap * 2,
              height: SpellingLayout.letterSlotSize,
              child: Center(
                child: Text(
                  // 空格显示成什么都没有，连字符与撇号原样显示。
                  character == ' ' ? '' : character,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: SpellingLayout.slotTextSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
          continue;
        }
        final isFilled = i < _typedLetters.length;
        children.add(
          _SpellingSlot(
            key: Key('spelling-slot-$i'),
            text: isFilled ? _typedLetters[i] : '',
            isFilled: isFilled,
            isWrong: _wrongSlotIndex == i,
            isJustFilled: i == _typedLetters.length - 1,
            isLetterSlot: true,
            tokens: tokens,
            shake: _shakeController,
            pop: _popController,
          ),
        );
      }
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: SpellingLayout.slotGap,
      runSpacing: SpellingLayout.slotGap,
      children: children,
    );
  }

  ///
  /// 构建作答区：手动拆分编辑态 / 候选片段 / 26 键键盘三者之一。
  ///
  /// 整块随切换淡入上移，对应原型的 `.fade-switch`。
  Widget _buildAnswerArea(AppTokens tokens) {
    if (_preparing) return const SizedBox.shrink();
    final Widget content;
    if (_manualMode) {
      content = _buildManualSplit(tokens);
    } else if (_mode == SpellingMode.chunk) {
      content = _buildChunks(tokens);
    } else {
      content = _buildKeyboard(tokens);
    }
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (_, child) => Opacity(
        opacity: _fadeController.value,
        child: Transform.translate(
          offset: Offset(
            0,
            (1 - _fadeController.value) * SpellingLayout.fadeSlideOffset,
          ),
          child: child,
        ),
      ),
      child: content,
    );
  }

  ///
  /// 构建候选片段区（片段模式）。
  Widget _buildChunks(AppTokens tokens) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: SpellingLayout.chunkGap,
      runSpacing: SpellingLayout.chunkGap,
      children: <Widget>[
        for (var i = 0; i < _pool.length; i += 1)
          _ChunkButton(
            key: Key('spelling-chunk-$i'),
            text: _pool[i].text,
            isUsed: _isChunkUsed(i),
            isWrong: _wrongChunkIndex == i,
            tokens: tokens,
            shake: _shakeController,
            onTap: () => _onChunkTap(i),
          ),
      ],
    );
  }

  ///
  /// 构建 26 键键盘（逐字母模式）。
  ///
  /// 退格键放在第三行末尾——真实手机键盘就在那个位置，原型把它放在行首，
  /// 用户会习惯性地按到 z。
  Widget _buildKeyboard(AppTokens tokens) {
    const rows = <String>['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (
          var rowIndex = 0;
          rowIndex < rows.length;
          rowIndex += 1
        ) ...<Widget>[
          if (rowIndex > 0) const SizedBox(height: SpellingLayout.keyRowGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 间隔只加在按键之间，不能每颗键后面都挂一个：行尾多出来的那 6 像素
              // 会算进 Row 的宽度，整行跟着左偏 3 像素，与有退格键的第三行错位。
              for (final (index, letter)
                  in rows[rowIndex].split('').indexed) ...<Widget>[
                if (index > 0) const SizedBox(width: SpellingLayout.keyGap),
                Flexible(
                  child: _KeyboardKey(
                    key: Key('spelling-key-$letter'),
                    label: letter,
                    isWrong: _wrongKeyLabel == letter,
                    tokens: tokens,
                    shake: _shakeController,
                    onTap: () => _onKeyTap(letter),
                  ),
                ),
              ],
              // 第三行末尾补一个退格键，宽度略大于字母键。
              if (rowIndex == rows.length - 1) ...<Widget>[
                const SizedBox(width: SpellingLayout.keyGap),
                _KeyboardKey(
                  key: const Key('spelling-key-backspace'),
                  icon: TablerIcons.backspace,
                  isFunction: true,
                  isWrong: false,
                  tokens: tokens,
                  shake: _shakeController,
                  onTap: _onBackspace,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  ///
  /// 构建手动拆分编辑态。
  ///
  /// 字母之间的每个空隙都是一个可点的「剪口」，点一下加一刀、再点一下取消。
  Widget _buildManualSplit(AppTokens tokens) {
    final spelling = _currentWord.spelling.trim();
    final letters = spelling.split('');
    final bar = <Widget>[];
    for (var i = 0; i < letters.length; i += 1) {
      bar.add(
        SizedBox(
          width: SpellingLayout.splitLetterWidth,
          height: SpellingLayout.splitRowHeight,
          child: Center(
            child: Text(
              letters[i],
              style: TextStyle(
                color: tokens.text,
                fontSize: SpellingLayout.splitLetterTextSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
      // 最后一个字母之后不需要剪口（那就是词尾）。
      if (i == letters.length - 1) continue;
      final position = i + 1;
      final isActive = _manualCuts.contains(position);
      bar.add(
        SizedBox(
          width: SpellingLayout.splitGapWidth,
          height: SpellingLayout.splitRowHeight,
          child: InkWell(
            key: Key('spelling-cut-$position'),
            onTap: () => _toggleCut(position),
            child: Center(
              child: Transform.scale(
                scale: isActive ? SpellingLayout.splitGapActiveScale : 1,
                child: Icon(
                  TablerIcons.slash,
                  size: SpellingLayout.splitGapIconSize,
                  color: isActive ? AppTokens.accent : tokens.check,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              TablerIcons.infoCircle,
              size: SpellingLayout.splitTipTextSize,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '点击字母间隙添加 / 取消拆分点',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: SpellingLayout.splitTipTextSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: SpellingLayout.splitSectionGap),
        Wrap(alignment: WrapAlignment.center, children: bar),
        const SizedBox(height: SpellingLayout.splitSectionGap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('spelling-apply-split'),
              // 一刀都没划时按钮不可用：那等于整词，不是拆分。
              onPressed: _manualCuts.isEmpty
                  ? null
                  : () => unawaited(_applyManualSplit()),
              icon: const Icon(TablerIcons.check, size: 16),
              label: const Text('按此拆分作答'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    SpellingLayout.chunkRadius,
                  ),
                ),
              ),
            ),
            const SizedBox(width: SpellingLayout.toolButtonGap),
            TextButton(
              key: const Key('spelling-cancel-split'),
              onPressed: _toggleManualSplit,
              child: Text('取消', style: TextStyle(color: tokens.textSecondary)),
            ),
          ],
        ),
      ],
    );
  }

  ///
  /// 构建底部工具条：换一种拆分方式 / 自己动手拆分。
  ///
  /// 含空格连字符的词条两个按钮都禁用（那类词固定逐字母拼），
  /// 禁用时图标变淡，用户一眼能看出「这里现在没得调」。
  Widget _buildToolBar(AppTokens tokens) {
    final enabled = _canManualSplit && !_showSummary && !_preparing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ToolButton(
          key: const Key('spelling-refresh-split'),
          icon: TablerIcons.refresh,
          tooltip: '换一种拆分方式',
          isEnabled: enabled && !_manualMode,
          // 没有别的切法时这个按钮会抖一下，提示「就这一种」。
          isShaking: _refreshShaking,
          tokens: tokens,
          shake: _shakeController,
          onTap: () => unawaited(_refreshSplit()),
        ),
        const SizedBox(width: SpellingLayout.toolButtonGap),
        _ToolButton(
          key: const Key('spelling-manual-split'),
          icon: TablerIcons.scissors,
          tooltip: '自己动手拆分',
          isEnabled: enabled,
          isActive: _manualMode,
          tokens: tokens,
          shake: _shakeController,
          onTap: _toggleManualSplit,
        ),
      ],
    );
  }

  ///
  /// 构建结算页，版式复刻原型的「拼写完成」页。
  ///
  /// 从上到下：圆形图标底盘 → 主标题 → 副标题 → 2×2 统计卡 →
  /// 需加强单词列表 → 再练一组按钮。
  ///
  /// 与原型的一处差异：原型左下那格是「完成词汇」，但它恒等于总词量
  /// （拼对才能进下一个），没有任何信息量。这里换成「需加强」，
  /// 并在下面补一份具体的单词名单——对复习类应用来说，
  /// 「哪几个词没拿下」才是结算页最该给的东西。
  Widget _buildSummary(AppTokens tokens) {
    final weak = _weakOutcomes;
    return LayoutBuilder(
      // 内容高度可能超过矮屏幕，用可滚动容器兜底，同时保持「空间够就垂直居中」。
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpellingLayout.summaryInset,
          vertical: SpellingLayout.summarySectionGap,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.maxHeight - SpellingLayout.summarySectionGap * 2,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 圆形图标底盘：直径 64，底色是成功绿的 10% 淡版。
              Center(
                child: Container(
                  width: SpellingLayout.summaryAvatarSize,
                  height: SpellingLayout.summaryAvatarSize,
                  decoration: BoxDecoration(
                    color: _kSuccess.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: tokens.cardShadow,
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    TablerIcons.confetti,
                    size: SpellingLayout.summaryAvatarIconSize,
                    color: _kSuccess,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '拼写完成',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: SpellingLayout.summaryTitleSize,
                  fontWeight: FontWeight.bold,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                weak.isEmpty ? '本组 $_total 个单词全部一次拼对' : '本组 $_total 个单词已全部拼写完毕',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: SpellingLayout.summarySubtitleSize,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: SpellingLayout.summarySectionGap),
              // 上排：一次拼对 / 拼写失误。
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('spelling-stat-perfect'),
                        icon: TablerIcons.flame,
                        label: '一次拼对',
                        value: '$_perfectCount',
                        unit: '共 $_total 个',
                        color: _kSuccess,
                        tokens: tokens,
                      ),
                    ),
                    const SizedBox(width: SpellingLayout.summaryStatGap),
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('spelling-stat-errors'),
                        icon: TablerIcons.x,
                        label: '拼写失误',
                        value: '$_errors',
                        unit: '次',
                        color: AppTokens.danger,
                        tokens: tokens,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SpellingLayout.summaryStatGap),
              // 下排：需加强 / 用时。
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('spelling-stat-weak'),
                        icon: TablerIcons.bulb,
                        label: '需加强',
                        value: '${weak.length}',
                        unit: '个单词',
                        color: _kOrange,
                        tokens: tokens,
                      ),
                    ),
                    const SizedBox(width: SpellingLayout.summaryStatGap),
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('spelling-stat-time'),
                        icon: TablerIcons.clock,
                        label: '用时',
                        value: _formatElapsed(),
                        unit: '本组训练',
                        color: AppTokens.accent,
                        tokens: tokens,
                        isTimeValue: true,
                      ),
                    ),
                  ],
                ),
              ),
              // 需加强名单：错过或被揭示答案的词，用户可以照着这份名单再练。
              if (weak.isNotEmpty) ...[
                const SizedBox(height: SpellingLayout.summarySectionGap),
                _buildWeakList(tokens, weak),
              ],
              const SizedBox(height: SpellingLayout.summarySectionGap),
              SizedBox(
                height: SpellingLayout.summaryButtonHeight,
                child: FilledButton.icon(
                  key: const Key('spelling-restart'),
                  onPressed: _restart,
                  icon: const Icon(TablerIcons.rotateClockwise, size: 18),
                  label: const Text('再练一组'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: SpellingLayout.summaryButtonTextSize,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        SpellingLayout.chunkRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ///
  /// 构建「需加强」单词名单。
  ///
  /// 被揭示答案的词用危险红、只是错过几次的用橙色，一眼能分出轻重。
  Widget _buildWeakList(AppTokens tokens, List<SpellingWordOutcome> weak) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '这几个词需要再练',
          style: TextStyle(
            fontSize: SpellingLayout.summaryStatLabelSize,
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: SpellingLayout.weakChipGap),
        Wrap(
          spacing: SpellingLayout.weakChipGap,
          runSpacing: SpellingLayout.weakChipGap,
          children: <Widget>[
            for (final outcome in weak)
              Container(
                key: Key('spelling-weak-${outcome.spelling}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: SpellingLayout.weakChipPaddingHorizontal,
                  vertical: SpellingLayout.weakChipPaddingVertical,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    // 错满 2 次以上标红，其余标橙；「被揭示答案」这一档
                    // 随提示功能一起下线了。
                    (outcome.wrongCount >= 2 ? AppTokens.danger : _kOrange)
                        .withValues(alpha: _kSoftBackgroundAlpha),
                    tokens.card,
                  ),
                  borderRadius: BorderRadius.circular(
                    SpellingLayout.weakChipRadius,
                  ),
                ),
                child: Text(
                  outcome.spelling,
                  style: TextStyle(
                    color: outcome.wrongCount >= 2
                        ? AppTokens.danger
                        : _kOrange,
                    fontSize: SpellingLayout.weakChipTextSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
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

///
/// 一个占位格。
///
/// 样式复刻原型 `.slot`：默认是虚线灰框 + 极淡底色的空格子；填对后转成
/// 实线绿框 + 淡绿底 + 绿字（`.filled`）；判错时红框抖动（`.error`）。
///
class _SpellingSlot extends StatelessWidget {
  ///
  /// 创建一个占位格。
  const _SpellingSlot({
    required this.text,
    required this.isFilled,
    required this.isWrong,
    required this.isJustFilled,
    required this.isLetterSlot,
    required this.tokens,
    required this.shake,
    required this.pop,
    super.key,
  });

  ///
  /// 格子里显示的内容；空串表示还没填。
  final String text;

  ///
  /// 是否已经填对。
  final bool isFilled;

  ///
  /// 是否正在播放判错反馈。
  final bool isWrong;

  ///
  /// 是否是刚刚填上的那一格（只有它播弹入动画）。
  final bool isJustFilled;

  ///
  /// 是否是逐字母模式的小格子（固定 40×40，不随内容变宽）。
  final bool isLetterSlot;

  ///
  /// 当前主题设计令牌。
  final AppTokens tokens;

  ///
  /// 父级共用的抖动控制器。
  final AnimationController shake;

  ///
  /// 父级共用的弹入控制器。
  final AnimationController pop;

  ///
  /// 输出一个带状态色的占位格。
  @override
  Widget build(BuildContext context) {
    // 三种状态各有一套配色：判错优先于填对，因为它是即时反馈。
    final stateColor = isWrong
        ? AppTokens.danger
        : isFilled
        ? _kSuccess
        : null;
    final borderColor = stateColor ?? tokens.check;
    final background = stateColor == null
        ? tokens.expand
        : Color.alphaBlend(
            stateColor.withValues(alpha: _kSoftBackgroundAlpha),
            tokens.card,
          );

    // 片段格不设固定宽度，靠 minWidth + 内容撑开；因此内部居中必须用
    // 会收缩包裹的 Center(widthFactor/heightFactor: 1)。
    // 不能用裸 Center 或 Container.alignment：这两种写法在有界约束下都会
    // 把格子撑到父级最大宽度，Wrap 里就变成一格一行。
    Widget slot = Container(
      width: isLetterSlot ? SpellingLayout.letterSlotSize : null,
      height: isLetterSlot
          ? SpellingLayout.letterSlotSize
          : SpellingLayout.slotHeight,
      constraints: isLetterSlot
          ? null
          : const BoxConstraints(minWidth: SpellingLayout.slotMinWidth),
      padding: isLetterSlot
          ? null
          : const EdgeInsets.symmetric(
              horizontal: SpellingLayout.slotPaddingHorizontal,
            ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SpellingLayout.slotRadius),
        border: Border.all(
          color: borderColor,
          width: SpellingLayout.slotBorderWidth,
        ),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          text,
          style: TextStyle(
            color: stateColor ?? tokens.text,
            fontSize: SpellingLayout.slotTextSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    // 刚填上的那一格弹一下：先缩到 0.85，冲到 1.06，再落回 1。
    if (isJustFilled && isFilled) {
      slot = AnimatedBuilder(
        animation: pop,
        builder: (_, child) {
          final t = pop.value;
          // 0 → 0.6 从 0.85 冲到 1.06，0.6 → 1 再落回 1，与原型关键帧一致。
          final scale = t < 0.6
              ? SpellingLayout.popMinScale +
                    (SpellingLayout.popMaxScale - SpellingLayout.popMinScale) *
                        (t / 0.6)
              : SpellingLayout.popMaxScale -
                    (SpellingLayout.popMaxScale - 1) * ((t - 0.6) / 0.4);
          return Transform.scale(scale: scale, child: child);
        },
        child: slot,
      );
    }

    // 判错时左右甩动，和候选按钮同一条曲线。
    if (isWrong) {
      slot = AnimatedBuilder(
        animation: shake,
        builder: (_, child) => Transform.translate(
          offset: Offset(
            _interpolateFrames(SpellingLayout.shakeKeyframes, shake.value),
            0,
          ),
          child: child,
        ),
        child: slot,
      );
    }
    return slot;
  }
}

///
/// 一个候选片段按钮（片段模式）。
///
/// 样式复刻原型 `.chunk-btn`：默认是浅色描边的圆角按钮；挑中填入后转成
/// 半透明的成功绿（`.used`）；挑错时红框抖动（`.error`）。
class _ChunkButton extends StatelessWidget {
  ///
  /// 创建一个候选片段按钮。
  const _ChunkButton({
    required this.text,
    required this.isUsed,
    required this.isWrong,
    required this.tokens,
    required this.shake,
    required this.onTap,
    super.key,
  });

  ///
  /// 按钮上显示的片段文字。
  final String text;

  ///
  /// 是否已经被挑中填入占位格；挑中后变半透明且不再可点。
  final bool isUsed;

  ///
  /// 是否正在播放挑错反馈（红框 + 抖动）。
  final bool isWrong;

  ///
  /// 当前主题设计令牌。
  final AppTokens tokens;

  ///
  /// 父级共用的抖动控制器；同一时刻只会有一个片段在抖。
  final AnimationController shake;

  ///
  /// 点击片段。
  final VoidCallback onTap;

  ///
  /// 输出一个带状态色的候选片段按钮。
  @override
  Widget build(BuildContext context) {
    // 状态色：判错优先（红），已用次之（绿），否则无。
    final stateColor = isWrong
        ? AppTokens.danger
        : isUsed
        ? _kSuccess
        : null;
    final borderColor = stateColor ?? tokens.border;
    final background = stateColor == null
        ? tokens.card
        : Color.alphaBlend(
            stateColor.withValues(alpha: _kSoftBackgroundAlpha),
            tokens.card,
          );

    Widget button = Material(
      color: background,
      borderRadius: BorderRadius.circular(SpellingLayout.chunkRadius),
      child: InkWell(
        onTap: isUsed ? null : onTap,
        borderRadius: BorderRadius.circular(SpellingLayout.chunkRadius),
        child: Opacity(
          // 已用片段保留 35% 不透明度，既能看清又明确表示「用过了」。
          opacity: isUsed ? SpellingLayout.chunkUsedOpacity : 1,
          // 候选按钮同样是「minWidth + 内容」定宽，内部居中必须用会收缩
          // 包裹的 Center(widthFactor/heightFactor: 1)，否则会撑满整行。
          child: Container(
            constraints: const BoxConstraints(
              minWidth: SpellingLayout.chunkMinWidth,
              minHeight: SpellingLayout.chunkMinHeight,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 6,
              horizontal: SpellingLayout.chunkPaddingHorizontal,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SpellingLayout.chunkRadius),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                text,
                style: TextStyle(
                  color: stateColor ?? tokens.text,
                  fontSize: SpellingLayout.chunkTextSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 挑错时左右甩动，与占位格共用同一条关键帧曲线。
    if (isWrong) {
      button = AnimatedBuilder(
        animation: shake,
        builder: (_, child) => Transform.translate(
          offset: Offset(
            _interpolateFrames(SpellingLayout.shakeKeyframes, shake.value),
            0,
          ),
          child: child,
        ),
        child: button,
      );
    }
    return button;
  }
}

///
/// 一个键盘按键（逐字母模式）。
///
/// 样式复刻原型 `.kb-key`：字母键是白底描边，功能键（退格）是浅灰底；
/// 按错时整颗键变红并抖动。按键高度刻意抬到 44，满足真机最小触控尺寸。
class _KeyboardKey extends StatelessWidget {
  ///
  /// 创建一个键盘按键。
  const _KeyboardKey({
    this.label,
    this.icon,
    this.isFunction = false,
    required this.isWrong,
    required this.tokens,
    required this.shake,
    required this.onTap,
    super.key,
  });

  ///
  /// 字母键显示的字母；功能键留空。
  final String? label;

  ///
  /// 功能键显示的图标（如退格）；字母键留空。
  final IconData? icon;

  ///
  /// 是否功能键；功能键用浅灰底、更宽、次级文字色。
  final bool isFunction;

  ///
  /// 是否正在播放按错反馈（红色 + 抖动）。
  final bool isWrong;

  ///
  /// 当前主题设计令牌。
  final AppTokens tokens;

  ///
  /// 父级共用的抖动控制器。
  final AnimationController shake;

  ///
  /// 按下按键。
  final VoidCallback onTap;

  ///
  /// 输出一个按键。
  @override
  Widget build(BuildContext context) {
    // 功能键默认偏中性灰，字母键用主文字色；按错时统一覆盖成红色。
    final baseColor = isFunction ? tokens.textSecondary : tokens.text;
    final baseBackground = isFunction ? tokens.sub : tokens.card;
    final color = isWrong ? AppTokens.danger : baseColor;
    final borderColor = isWrong ? AppTokens.danger : tokens.border;
    final background = isWrong
        ? Color.alphaBlend(
            AppTokens.danger.withValues(alpha: _kSoftBackgroundAlpha),
            tokens.card,
          )
        : baseBackground;

    Widget keyButton = Material(
      color: background,
      borderRadius: BorderRadius.circular(SpellingLayout.keyRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpellingLayout.keyRadius),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isFunction
                ? SpellingLayout.functionKeyMaxWidth
                : SpellingLayout.keyMaxWidth,
            minHeight: SpellingLayout.keyHeight,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SpellingLayout.keyRadius),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: color)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      color: color,
                      fontSize: SpellingLayout.keyTextSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );

    if (isWrong) {
      keyButton = AnimatedBuilder(
        animation: shake,
        builder: (_, child) => Transform.translate(
          offset: Offset(
            _interpolateFrames(SpellingLayout.shakeKeyframes, shake.value),
            0,
          ),
          child: child,
        ),
        child: keyButton,
      );
    }
    return keyButton;
  }
}

///
/// 底部一个工具按钮（刷新拆分 / 手动拆分）。
///
/// 样式复刻原型 `.tool-btn`：默认是中性灰的方形描边按钮；激活时（手动拆分
/// 已开启）转成主色描边、主色图标与极淡主色底；没有别的拆法时刷新按钮会抖一下。
class _ToolButton extends StatelessWidget {
  ///
  /// 创建一个工具按钮。
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    this.isEnabled = true,
    this.isActive = false,
    this.isShaking = false,
    required this.tokens,
    required this.shake,
    required this.onTap,
    super.key,
  });

  ///
  /// 按钮内的 Tabler 图标。
  final IconData icon;

  ///
  /// 长按或悬停时的提示文案。
  final String tooltip;

  ///
  /// 是否可点；不可点时变灰且不响应。
  final bool isEnabled;

  ///
  /// 是否处于激活态（手动拆分已开启）。
  final bool isActive;

  ///
  /// 是否正在抖动（仅刷新按钮在「没有别的拆法」时用）。
  final bool isShaking;

  ///
  /// 当前主题设计令牌。
  final AppTokens tokens;

  ///
  /// 父级共用的抖动控制器。
  final AnimationController shake;

  ///
  /// 点击按钮。
  final VoidCallback onTap;

  ///
  /// 输出一个工具按钮。
  @override
  Widget build(BuildContext context) {
    final accent = AppTokens.accent;
    final color = !isEnabled
        ? tokens.textSecondary.withValues(alpha: 0.5)
        : isActive
        ? accent
        : tokens.textSecondary;
    final borderColor = isActive ? accent : tokens.border;
    final background = isActive
        ? Color.alphaBlend(
            accent.withValues(alpha: _kSoftBackgroundAlpha),
            tokens.card,
          )
        : tokens.card;

    Widget button = Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(SpellingLayout.toolButtonRadius),
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(SpellingLayout.toolButtonRadius),
          child: Container(
            width: SpellingLayout.toolButtonSize,
            height: SpellingLayout.toolButtonSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                SpellingLayout.toolButtonRadius,
              ),
              border: Border.all(color: borderColor),
            ),
            child: Icon(icon, size: SpellingLayout.toolIconSize, color: color),
          ),
        ),
      ),
    );

    if (isShaking) {
      button = AnimatedBuilder(
        animation: shake,
        builder: (_, child) => Transform.translate(
          offset: Offset(
            _interpolateFrames(SpellingLayout.shakeKeyframes, shake.value),
            0,
          ),
          child: child,
        ),
        child: button,
      );
    }
    return button;
  }
}

///
/// 结算页的一张统计卡。
///
/// 样式复刻原型结算区的 `.card`：浅底描边卡片，内部从上到下是
///「图标 + 标签」「主数值」「单位说明」三行。主数值默认用大号字，
///只有「用时」这一格因为是定宽的时间串，单独用小一号字以免撑爆。
class _SummaryStatCard extends StatelessWidget {
  ///
  /// 创建一张统计卡。
  const _SummaryStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.tokens,
    this.isTimeValue = false,
    super.key,
  });

  ///
  /// 标签左侧的主题色图标。
  final IconData icon;

  ///
  /// 标签文字（如「一次拼对」）。
  final String label;

  ///
  /// 主数值（如拼对个数或 00:00）。
  final String value;

  ///
  /// 单位说明（如「个单词」「本组训练」）。
  final String unit;

  ///
  /// 图标与主数值的主题色。
  final Color color;

  ///
  /// 当前主题设计令牌。
  final AppTokens tokens;

  ///
  /// 主数值是否是定宽时间串；是则用小一号字号。
  final bool isTimeValue;

  ///
  /// 输出一张统计卡。
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: SpellingLayout.summaryStatPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: tokens.sub,
        borderRadius: BorderRadius.circular(SpellingLayout.summaryStatRadius),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标签行：主题色图标 + 次级灰文字。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: SpellingLayout.summaryStatIconSize,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: SpellingLayout.summaryStatLabelSize,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 主数值：等宽字体保证数字跳变时宽度不抖。
          Text(
            value,
            style: TextStyle(
              fontSize: isTimeValue
                  ? SpellingLayout.summaryStatTimeSize
                  : SpellingLayout.summaryStatValueSize,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: TextStyle(
              fontSize: SpellingLayout.summaryStatUnitSize,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
