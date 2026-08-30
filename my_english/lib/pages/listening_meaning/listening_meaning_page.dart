// dart:async 提供 unawaited，播放音频时不阻塞按钮响应。
import 'dart:async';
// dart:math 用于打乱答案顺序和生成干扰项。
import 'dart:math';
// material.dart 提供全屏页面、进度条、卡片与按钮。
import 'package:flutter/material.dart';
// services.dart 提供 HapticFeedback，为每次选择添加触觉反馈。
import 'package:flutter/services.dart';
// 所有可见图标继续统一使用 Tabler。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入应用设计令牌。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角时间超过一小时改用 hh:mm:ss。
import '../../common/date.dart';
// 引入全局 Toast 工具，层级高于 BottomSheet。
import '../../common/toast.dart';
// 引入词义模型。
import '../../models/meaning.dart';
// 引入单词模型。
import '../../models/word.dart';
// 引入音频播放接口。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入单词 Store：混淆词第一次生成后要回写到单词行 / 含义行。
import '../../store/word.dart';
// 引入独立候选项生成服务，页面只负责当前答题状态。
import 'services/listening_meaning_option_generator.dart';
import '../review/services/session_progress.dart';
// 引入听音辨义页面集中管理的布局尺寸。
import 'widgets/listening_meaning_layout.dart';
// 引入中部三个只读子模块，页面文件只保留答题状态与事件流程。
import 'widgets/listening_meaning_question_content.dart';

///
/// 听音辨义的两个答题阶段：先辨认拼写，再逐条辨认释义。
///
enum ListeningMeaningStage {
  ///
  /// 根据发音选择正确英文拼写的阶段。
  word,

  ///
  /// 按顺序选择每条中文释义的阶段。
  definition,
}

///
/// 一个可点击的听音辨义候选答案。
class ListeningMeaningOption {
  ///
  /// 创建听音辨义候选答案。
  const ListeningMeaningOption({required this.text, required this.isCorrect});

  ///
  /// 用户看到的候选文本。
  final String text;

  ///
  /// 是否为当前小题正确答案。
  final bool isCorrect;
}

///
/// 全屏听音辨义页面。
///
class ListeningMeaningPage extends StatefulWidget {
  ///
  /// 创建单词听音辨义页面。
  const ListeningMeaningPage({
    required this.words,
    required this.audioPlayer,
    required this.accent,
    required this.progress,
    this.wordStore,
    this.definitionSeparator = '、',
    super.key,
  }) : assert(words.length > 0, '听音辨义页至少需要一个学习单词');

  ///
  /// 本轮参与听音辨义的单词。
  final List<Word> words;

  ///
  /// 与首页、随身听共用的发音服务。
  final WordAudioPlayer audioPlayer;

  ///
  /// 当前发音口音。
  final PronunciationAccent accent;

  ///
  /// 本局的进度出口。
  ///
  /// 它同时决定三件事：进度存到哪一局、每次点击记到哪一局，
  /// 以及答题要不要推进单词的复习时间（巩固局不推进）。
  final SessionProgress progress;

  ///
  /// 单词 Store：第一次生成的混淆词要回写到单词行 / 含义行。
  ///
  /// 正式环境使用 SQLite 单例，Widget 测试可传入内存替身。
  final WordStore? wordStore;

  ///
  /// 已答出的同词性中文释义之间使用的全角分隔符。
  final String definitionSeparator;

  ///
  /// 创建听音辨义页面状态。
  @override
  State<ListeningMeaningPage> createState() => _ListeningMeaningPageState();
}

///
/// 管理听音辨义页面的题目进度、候选项、播放状态和会话持久化。
///
class _ListeningMeaningPageState extends State<ListeningMeaningPage>
    with WidgetsBindingObserver {
  ///
  /// 使用固定种子生成稳定且可复现的候选顺序。
  final Random _random = Random(20260727);

  ///
  /// 当前单词在本轮固定列表中的下标。
  int _wordIndex = 0;

  ///
  /// 当前正在进行拼写选择还是释义选择。
  ListeningMeaningStage _stage = ListeningMeaningStage.word;

  ///
  /// 当前词性组在有效释义列表中的下标。
  int _meaningIndex = 0;

  ///
  /// 整轮累计答错次数，供完成状态页展示。
  int _errors = 0;

  ///
  /// 当前单词累计选错候选项的次数，每个新词都会重置。
  int _currentWrong = 0;

  ///
  /// 本轮已经完成的单词主键，退出时交给首页定向刷新。
  final Set<int> _reviewedWordIds = <int>{};

  ///
  /// 是否已经提交最后一个单词并进入完成状态页。
  bool _isDone = false;

  ///
  /// 当前单词是否已经完成全部拼写和释义步骤。
  bool _isCurrentWordComplete = false;

  ///
  /// 是否正在提交当前题，用于阻止连续点击产生重复记录。
  bool _isSavingCompletion = false;

  ///
  /// 当前单词的发音是否仍在播放。
  bool _isPlaying = false;

  ///
  /// 当前音频请求代次，只允许最新请求更新播放状态。
  int _playGeneration = 0;

  /// 当前进入听音辨义页面后是否已经提示过系统 TTS。
  bool _hasShownTtsNotice = false;

  ///
  /// 页面进入后已用毫秒数，用于右上角 mm:ss 计时。
  int _elapsedMs = 0;

  ///
  /// 每秒推进一次 [\_elapsedMs] 的定时器；退后台停表、回前台继续。
  Timer? _elapsedTimer;

  ///
  /// 中间信息面板当前展示的反馈文案。
  String _feedback = '';

  ///
  /// 反馈语义颜色，null 表示使用普通次要文字色。
  Color? _feedbackColor;

  ///
  /// 当前拼写或释义步骤展示的四个候选项。
  List<ListeningMeaningOption> _options = const [];

  ///
  /// 已经选错的候选文本集合，界面会标红并禁用这些项。
  final Set<String> _wrongOptions = <String>{};

  ///
  /// 候选缓存读取代次，阻止旧异步结果覆盖已经切换的新题。
  int _optionLoadGeneration = 0;

  ///
  /// 当前候选是否直接来自恢复快照，避免首帧重新打乱顺序。
  final bool _restoredExactOptions = false;

  ///
  /// 当前正在听音辨义的单词。
  Word get _currentWord => widget.words[_wordIndex];

  ///
  /// 本局进度的落盘出口。
  SessionProgress get _progress => widget.progress;

  ///
  /// 单词 Store：混淆词回写走它。
  WordStore get _wordStore => widget.wordStore ?? LocalWordStore.instance;

  ///
  /// 获取当前单词中包含有效释义的词性组。
  ///
  /// 当前单词的全部释义（摊平后的一维列表）。
  ///
  /// 听音辨义按「一条释义一小题」推进，所以这里要的是摊平结果而不是分组。
  /// 模型已经去过重、合并过动词，这里不再做任何整理。
  List<Meaning> get _availableMeanings => _currentWord.allMeanings;

  ///
  /// 初始化听音辨义页面并恢复可用的历史状态。
  @override
  void initState() {
    super.initState();
    // 监听 App 前后台变化，后台停止音频并让下次播放重新提示 TTS。
    WidgetsBinding.instance.addObserver(this);
    // 继续模式先恢复小题下标、错误和候选顺序；新开始则保留默认字段。
    _restoreInitialSession();
    // 完成待提交态没有候选；普通状态若快照无合法候选则同步生成标准四选一。
    if (_isCurrentWordComplete) {
      _options = const <ListeningMeaningOption>[];
    } else if (!_restoredExactOptions) {
      _options = _buildOptions();
    }
    // 每次进入都覆盖同类型旧会话；新开始会保存本次新的单词列表。
    unawaited(_persistSession());
    // 首帧后并行读取候选缓存和自动发音；同步生成的选项保证等待 SQLite 时页面不空白。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 精确恢复的候选已经包含顺序；新题才从长期干扰项缓存恢复或创建。
      if (!_isCurrentWordComplete && !_restoredExactOptions) {
        unawaited(_restoreOrCreateCurrentConfusions());
      }
      // 完成待提交态不自动重播，普通小题进入后保持原有自动发音体验。
      if (!_isCurrentWordComplete) unawaited(_playAudio());
      // 进入页面先跑计时；退后台再停，回前台恢复。
      _startElapsedTimer();
    });
  }

  ///
  /// 从会话与点击记录恢复当前听音辨义状态。
  ///
  /// 2.0 起不再存页面快照——每一次点击都写了一条记录，把这一局这个单词的
  /// 记录翻一遍，就能精确还原：
  /// - 有一条「含义为空且答对」的记录 → 拼写那一步已经过了；
  /// - 答对过的含义主键集合 → 该跳到第几条释义；
  /// - 答错记录里的「实际输入」 → 哪几个候选该保持红色禁用。
  ///
  /// 候选**顺序**也不必存：混淆词本身已经落在单词行 / 含义行上，
  /// 顺序由它决定，每次进来都一样。
  void _restoreInitialSession() {
    final session = _progress.session;
    // 先恢复单词下标，后续释义边界都依赖当前单词。
    _wordIndex = session.cursor.clamp(0, widget.words.length - 1);
    // 已用时间来自会话字段（单位秒）；继续模式要累计，不能每次进入从 0 开始。
    _elapsedMs = session.elapsed * 1000;
    // 累计错误由记录直接数出来：错完就退、退完再进，不能刷出一局「全对」。
    _errors = _progress.wrongCount;

    final wordId = _currentWord.id;
    if (wordId == null) return;
    final wordProgress = _progress.progressOf(wordId);

    // 拼写那一步过了才进入释义阶段；当前单词没有可答释义时留在拼写阶段。
    if (wordProgress.spellingDone && _availableMeanings.isNotEmpty) {
      _stage = ListeningMeaningStage.definition;
      // 跳到第一条还没答对的释义。
      final nextIndex = _availableMeanings.indexWhere(
        (meaning) => !wordProgress.answeredMeaningIds.contains(meaning.id),
      );
      if (nextIndex < 0) {
        // 全部释义都答对了 = 这个词已经完成，等用户点「下一题」。
        _isCurrentWordComplete = true;
        _feedback = '本词完成！';
        _feedbackColor = const Color(0xFF2FB344);
        return;
      }
      _meaningIndex = nextIndex;
    } else {
      _stage = ListeningMeaningStage.word;
    }

    // 当前这一小题已经点错过哪些候选，恢复后继续保持红色禁用。
    final wrong = _stage == ListeningMeaningStage.word
        ? wordProgress.spellingWrongInputs
        : wordProgress.wrongInputsByMeaning[_availableMeanings[_meaningIndex].id] ??
              const <String>{};
    _wrongOptions.addAll(wrong);
    _currentWrong = wrong.length;
    if (_wrongOptions.isNotEmpty) {
      _feedback = '答错 · 难度将 +1';
      _feedbackColor = AppTokens.danger;
    }
  }

  ///
  /// 把当前进度写入 SQLite；页面交互先完成，持久化失败不阻断答题。
  ///
  /// 只写两个数：做到第几个词、已经花了多少秒。一个词内部走到哪一步
  /// （选拼写还是选第几条释义、点错过谁）全部由点击记录反查得出。
  Future<void> _persistSession() async {
    // 完成页已经结算过这一局，禁止 dispose 再把状态写回「进行中」。
    if (_isDone) return;
    // 本局已用时间（秒），右上角计时器实时推进这个值，供续玩回放。
    await _progress.save(cursor: _wordIndex, elapsed: _elapsedSeconds);
  }

  ///
  /// 本局已用秒数。
  int get _elapsedSeconds => (_elapsedMs ~/ 1000).clamp(0, 1 << 30);

  ///
  /// 把本局用时格式化成计时文字：不足一小时 mm:ss，满一小时 hh:mm:ss。
  String _formatElapsed() => formatTimerSeconds(_elapsedSeconds);

  ///
  /// 给这一局结算。
  ///
  /// 判定规则：只要把这一局的单词全部操作完一遍（走到这个方法时必然如此，
  /// 因为它只在最后一个单词提交成功后被调用），就算「完成」；中途累计的
  /// 答错次数只影响单词个体的难度与结算页展示，不影响整局成败。
  Future<void> _finishSession() => _progress.finish(
    // 走到这里说明全部单词都已操作完一遍，不论过程中是否答错，都算过关。
    perfect: true,
    cursor: widget.words.length,
    elapsed: _elapsedSeconds,
  );

  ///
  /// 当前小题的正确答案：拼写阶段是单词，释义阶段是当前中文释义。
  String get _currentCorrectAnswer => _stage == ListeningMeaningStage.word
      ? _currentWord.spelling
      : _availableMeanings[_meaningIndex].definition;

  ///
  /// 当前单词自身的全部中文释义集合。
  ///
  /// 一个单词往往有多个含义（例如 ability 的“能力 / 才能”），这些含义只能作为
  /// 同一道释义题的正确答案之一，永远不能互相充当混淆项。这里把它们收集起来，
  /// 传给释义干扰项生成器，让候选彻底避开当前单词。
  Set<String> get _currentWordProviderExcludedDefinitions => {
    for (final meaning in _currentWord.allMeanings)
      if (meaning.definition.trim().isNotEmpty) meaning.definition.trim(),
  };

  ///
  /// 按当前阶段生成指定数量的干扰项。
  List<String> _generateCurrentDistractors({int count = 3}) {
    // 拼写题与释义题分别复用原有生成规则，来源仍严格限制在本轮学习列表。
    return _stage == ListeningMeaningStage.word
        ? ListeningMeaningOptionGenerator.buildWordDistractors(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            count: count,
          )
        : ListeningMeaningOptionGenerator.buildDefinitionDistractors(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            count: count,
            excludeDefinitions: _currentWordProviderExcludedDefinitions,
          );
  }

  ///
  /// 当前小题已经落库的混淆词；没生成过时是空列表。
  ///
  /// 2.0 起混淆词不再有自己的缓存表，而是直接住在单词行 / 含义行的
  /// `confusions` 字段里，四个模块共用同一份。
  List<String> get _currentStoredConfusions =>
      _stage == ListeningMeaningStage.word
      ? _currentWord.confusions
      : _availableMeanings[_meaningIndex].confusions;

  ///
  /// 用指定干扰项组装完整四选一。
  ///
  /// 正确项与三个干扰项放在一起**按拼写字母升序**排：同一道题每次进来顺序都
  /// 一致（与看义选词、词义连连的候选口径统一），续玩时也就不必额外存位置。
  /// [distractors] 的长度被截到 3，保证最终恒为四格。
  List<ListeningMeaningOption> _buildOptions({List<String>? distractors}) {
    // 未传正确项混淆词时系统生成，确保页面首帧已经有完整四选一。
    final resolved = distractors ?? _generateCurrentDistractors();
    final correctText = _currentCorrectAnswer;
    // 四选一 = 三个干扰项 + 正确答案，放在一起统一排序。
    final picks = <String>[for (final distractor in resolved.take(3)) distractor, correctText];
    // 忽略大小写按字母升序；拼写完全相同（理论上被生成器去重排除了）才原样比较。
    picks.sort((first, second) {
      final byLetter = first.toLowerCase().compareTo(second.toLowerCase());
      return byLetter != 0 ? byLetter : first.compareTo(second);
    });
    // isCorrect 用文本判定：排序无论怎么搬，正确答案身份都不会丢失。
    return List<ListeningMeaningOption>.unmodifiable(<ListeningMeaningOption>[
      for (final text in picks)
        ListeningMeaningOption(text: text, isCorrect: text == correctText),
    ]);
  }

  ///
  /// 判断已落库的混淆词是否仍能安全组成标准四选一。
  bool _isValidConfusions(List<String> confusions, String correct) {
    // 必须精确三项，否则重新生成一份。
    if (confusions.length != 3) return false;
    // 英文忽略大小写，中文转换后不受影响；同时排除正确答案与重复项。
    final normalizedCorrect = correct.trim().toLowerCase();
    final normalized = confusions.map((v) => v.trim().toLowerCase()).toSet();
    return normalized.length == 3 && !normalized.contains(normalizedCorrect);
  }

  ///
  /// 混淆词已经存过就直接用，第一次遇到这道题则当场生成并回写。
  ///
  /// 生活化解释：每个单词、每条释义身上都挂着一小串「容易跟它搞混的东西」。
  /// 第一个用到它的模块负责把它算出来存好，之后所有模块直接复用。
  Future<void> _restoreOrCreateCurrentConfusions() async {
    // 每次进入新小题先领取一个代次号，用来识别晚到的旧请求。
    final generation = ++_optionLoadGeneration;
    // 在 await 前抓取当前题身份，后续切题不会改变这些局部变量。
    final correct = _currentCorrectAnswer;
    final isWordStage = _stage == ListeningMeaningStage.word;
    final wordId = _currentWord.id;
    final meaningId = isWordStage ? null : _availableMeanings[_meaningIndex].id;
    final stored = _currentStoredConfusions;

    // 已经存过合法的一份：直接用它重建候选。
    if (_isValidConfusions(stored, correct)) {
      if (!mounted || generation != _optionLoadGeneration) return;
      setState(() => _options = _buildOptions(distractors: stored));
      return;
    }
    // 没存过或已损坏：把首帧同步生成的那一份回写。
    final generated = _options
        .where((option) => !option.isCorrect)
        .map((option) => option.text)
        .toList(growable: false);
    if (generated.length != 3) return;
    try {
      if (isWordStage) {
        if (wordId != null) {
          await _wordStore.saveWordConfusions(wordId, generated);
        }
      } else if (meaningId != null) {
        await _wordStore.saveMeaningConfusions(meaningId, generated);
      }
    } catch (error) {
      // 混淆词是体验增强，不应因原生通道异常阻断答题；页面上已经有一份了。
      debugPrint('保存听音辨义混淆词失败：$error');
    }
  }

  ///
  /// 调用真实发音服务，并在播放期间显示 Tabler 音量图标。
  ///
  /// [interrupt] 为 false 时忽略播放中的重复点击；为 true 时允许自动播放
  /// 打断旧音频，确保切题后立即播放新单词。
  ///
  /// 底层原生播放器本身就支持"后来的请求替换先前请求"（旧请求会收到
  /// AUDIO_INTERRUPTED），所以这里只要不在 Dart 层把请求拦下来即可。
  Future<void> _playAudio({bool interrupt = false}) async {
    // 整轮已完成时不再发声。
    if (_isDone) return;
    // 手动点击且正在播放中：保持原有防连点体验，直接忽略。
    if (_isPlaying && !interrupt) return;
    // 领取本次播放的代次号（前置 ++ 先自增再取值，保证全局唯一且递增）。
    final generation = ++_playGeneration;
    // 立刻切到"播放中"，右下角播放按钮换成音量图标。
    setState(() => _isPlaying = true);
    try {
      // await 会一直等到原生音频播放完毕（或被新播放打断而抛异常）。
      await widget.audioPlayer.playRandomChannel(_currentWord.spelling, widget.accent);
      // 只有非随机渠道且真正由离线 TTS 兜底朗读时才显示一次来源提示；
      // 随机渠道模式下 TTS 可能是被故意选中，不再提示“网络不可用”。
      final playback = widget.audioPlayer.consumeLastPlayback();
      if (!_hasShownTtsNotice && playback.usedTts && !playback.isRandomChannel) {
        _hasShownTtsNotice = true;
        if (mounted) {
          Toast.show(context, '当前网络音频不可用，正在使用系统 TTS 朗读');
        }
      }
    } on WordAudioPlaybackException catch (firstError) {
      // 原生已经删除损坏缓存；同一代次立即重试一次，触发重新下载并播放。
      // 只重试解码失败，不重试网络失败，避免无网时让用户额外等待两轮超时。
      if (mounted && generation == _playGeneration) {
        try {
          await widget.audioPlayer.playRandomChannel(_currentWord.spelling, widget.accent);
          // 解码失败重试成功后，同样检查真实播放来源（不含随机渠道）。
          final retryPlayback = widget.audioPlayer.consumeLastPlayback();
          if (!_hasShownTtsNotice &&
              retryPlayback.usedTts &&
              !retryPlayback.isRandomChannel) {
            _hasShownTtsNotice = true;
            if (mounted) {
              Toast.show(context, '当前网络音频不可用，正在使用系统 TTS 朗读');
            }
          }
        } on WordAudioInterruptedException {
          // 用户在重试期间切题或退出时按正常中断处理，不弹错误。
        } catch (error) {
          // 自动恢复仍失败时保留第二次真实原因；没有原因时回退首次解码错误。
          if (mounted && generation == _playGeneration) {
            Toast.show(
              context,
              '播放失败：${error.toString().isEmpty ? firstError : error}',
            );
          }
        }
      }
    } on WordAudioInterruptedException {
      // 页面关闭或新播放替换旧播放时无需弹出错误。
    } catch (error) {
      // 只有仍是"最新一次播放"时才提示失败，过期的旧请求不打扰用户。
      if (mounted && generation == _playGeneration) {
        Toast.show(context, '播放失败：$error');
      }
    } finally {
      // 同理：号码牌过期说明已有更新的播放在跑，绝不能由旧请求清掉播放中状态。
      if (mounted && generation == _playGeneration) {
        setState(() => _isPlaying = false);
      }
    }
  }

  /// App 离开前台时停止当前发音与计时，并重置下一次播放的 TTS 提示状态。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回前台恢复计时，只在当前局尚未结束时继续。
      if (!_isDone && !_isCurrentWordComplete) _startElapsedTimer();
      return;
    }
    // 退后台停表，避免把后台停留时间计进本局。
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _hasShownTtsNotice = false;
    ++_playGeneration;
    if (mounted) {
      // 退后台时同步更新内存和界面状态，回到前台后播放按钮保持暂停样式。
      setState(() => _isPlaying = false);
    }
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
  }

  ///
  /// 启动（或恢复）每秒一次的计时；只在本局进行中生效。
  void _startElapsedTimer() {
    if (_elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isDone) return;
      setState(() => _elapsedMs += 1000);
    });
  }


  ///
  /// 选择答案：错项变红并禁用；正确时推进到下一小题。
  ///
  /// 触觉反馈策略：
  /// - 选错：heavyImpact（重震），配合选项抖动动画，错误感强烈。
  /// - 选对：lightImpact（轻触），页面立即切换为新题，视觉变化即反馈。
  void _pickOption(ListeningMeaningOption option) {
    // 当前单词完成后已经只能点击"下一题"，旧选项不再响应。
    if (_isDone ||
        _isCurrentWordComplete ||
        _wrongOptions.contains(option.text)) {
      return;
    }
    if (!option.isCorrect) {
      // 重震动传达错误感，无需音效也能感知。
      HapticFeedback.heavyImpact();
      setState(() {
        _wrongOptions.add(option.text);
        // 整轮错误统计供完成状态页展示，不会因重做当前单词而回退。
        _errors++;
        // 当前单词的选错次数同步累加，用于落 record。
        _currentWrong++;
        // 选错即预告难度会后 +1，与候选区上方的危险色横幅口径一致。
        _feedback = '答错 · 难度将 +1';
        _feedbackColor = AppTokens.danger;
      });
      // 记一条「点错了」：现场恢复靠它把候选置灰，结算也靠它判定这一轮答错。
      unawaited(_recordAnswer(input: option.text, isCorrect: false));
      // 保存错项文本与错误计数，重新进入后不能通过退出页面清除错误。
      unawaited(_persistSession());
      return;
    }

    // 轻触震动确认选对，不拖延答题节奏。
    HapticFeedback.lightImpact();
    // 答对同样留痕：重进时靠它判断「拼写那步过了没有、答到第几条释义」。
    // 必须在下面切换阶段之前记，否则会记到下一小题头上。
    unawaited(_recordAnswer(input: option.text, isCorrect: true));

    if (_stage == ListeningMeaningStage.word) {
      if (_availableMeanings.isEmpty) {
        // 没有释义的单词在拼写答对后就完成，等待用户手动进入下一题。
        _completeCurrentWord();
        return;
      }
      setState(() {
        _stage = ListeningMeaningStage.definition;
        _meaningIndex = 0;
        _wrongOptions.clear();
        _feedback = '正确！';
        _feedbackColor = const Color(0xFF2FB344);
        _options = _buildOptions();
      });
      // 拼写答对并进入释义阶段后立即保存新的小题下标和候选顺序。
      unawaited(_persistSession());
      // 当前小题已经切到第一条释义，异步恢复或创建它自己的稳定候选缓存。
      unawaited(_restoreOrCreateCurrentConfusions());
      return;
    }

    // 一行含义就是一条释义，所以「下一条」等于「下一个 Meaning」。
    final nextMeaning = _meaningIndex + 1;
    if (nextMeaning >= _availableMeanings.length) {
      // 最后一条释义答对后隐藏选项和工具按钮，显示下一题。
      _completeCurrentWord();
      return;
    }
    setState(() {
      _meaningIndex = nextMeaning;
      _wrongOptions.clear();
      _feedback = '正确！';
      _feedbackColor = const Color(0xFF2FB344);
      _options = _buildOptions();
    });
    // 每推进一条释义都更新恢复点。
    unawaited(_persistSession());
    // 下一条释义拥有独立缓存，不能沿用上一条释义的三个干扰项。
    unawaited(_restoreOrCreateCurrentConfusions());
  }

  ///
  /// 记一次点击，不论对错。
  ///
  /// 这是整个会话恢复的地基：每一次点击都留一条，重进时把这一局这个单词的
  /// 记录翻一遍就能精确还原「拼写过了没有、答到第几条释义、点错过哪些候选」。
  /// 结算难度时也靠它判断这一轮有没有错过。
  ///
  /// 拼写阶段的记录不带含义主键（它针对整个单词），释义阶段则带上当前这一条。
  Future<void> _recordAnswer({
    required String input,
    required bool isCorrect,
  }) async {
    final wordId = _currentWord.id;
    // 没有主键无法落库；它通常只会出现在尚未保存的测试数据中。
    if (wordId == null) return;
    // 先把「这一条记的是哪道小题」抓成局部变量再进异步。
    // 调用方紧接着就会推进阶段和下标，抓晚了会记到下一小题头上。
    final meaningId = _stage == ListeningMeaningStage.word
        // 拼写题针对整个单词，不属于某一条释义。
        ? null
        : _availableMeanings[_meaningIndex].id;
    try {
      await _progress.record(
        wordId: wordId,
        meaningId: meaningId,
        input: input,
        isCorrect: isCorrect,
      );
    } catch (error) {
      // 写记录失败不该打断答题，最多这一次点击没留痕。
      debugPrint('写入听音辨义点击记录失败：$error');
    }
  }

  ///
  /// 长按候选项后询问是否刷新；确认后保持四选一结构并立即替换当前文本。
  Future<void> _requestOptionRefresh(int optionIndex) async {
    // 完成态没有候选项；下标越界说明长按事件来自已经卸载的旧组件。
    if (_isDone ||
        _isCurrentWordComplete ||
        optionIndex < 0 ||
        optionIndex >= _options.length) {
      return;
    }
    // 在弹窗前抓取当前选项；Modal 会阻止用户同时切换题目。
    final selectedOption = _options[optionIndex];
    // 长按使用中等震动，让单手操作时即使没盯着屏幕也能确认手势已识别。
    HapticFeedback.mediumImpact();
    // 所有选项显示完全一致的确认框，避免用交互差异泄露哪一个是正确答案。
    final confirmed = await _showOptionRefreshDialog(selectedOption.text);
    // 用户取消、页面关闭或当前题已经完成时不做任何修改。
    if (!confirmed || !mounted || _isCurrentWordComplete || _isDone) return;

    // 新候选必须排除当前四项，确保用户能立刻看出确实发生了替换。
    final excluded = _options.map((option) => option.text);
    final replacement = _stage == ListeningMeaningStage.word
        ? ListeningMeaningOptionGenerator.findReplacementWordDistractor(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            excluded: excluded,
          )
        : ListeningMeaningOptionGenerator.findReplacementDefinitionDistractor(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            excluded: excluded,
            excludeDefinitions: _currentWordProviderExcludedDefinitions,
          );
    // 极小或异常词库可能耗尽所有可用变体，此时保留原候选并给出说明。
    if (replacement == null) {
      Toast.show(context, '暂时没有可用的新候选词');
      return;
    }

    // 保存当前题身份，页面更新后异步把新的混淆词回写到单词行 / 含义行。
    final isWordStage = _stage == ListeningMeaningStage.word;
    final anchorId = isWordStage
        ? _currentWord.id
        : _availableMeanings[_meaningIndex].id;
    // 复制只读列表，下面只修改这份临时数组。
    final updatedOptions = List<ListeningMeaningOption>.from(_options);
    // 记录所有被移除的旧干扰项，避免它们继续保持“已答错”的红色状态。
    final removedWrongOptions = <String>{selectedOption.text};
    if (selectedOption.isCorrect) {
      // 正确答案本身不能消失：从另外三个位置随机选一个，把正确答案移动过去。
      final targetIndices = <int>[
        for (var index = 0; index < updatedOptions.length; index += 1)
          if (index != optionIndex && !updatedOptions[index].isCorrect) index,
      ];
      // 标准四选一一定存在三个可用目标位置。
      final correctTarget =
          targetIndices[_random.nextInt(targetIndices.length)];
      // 目标位置原来的干扰项会被移除，因此一并清理错误标记。
      removedWrongOptions.add(updatedOptions[correctTarget].text);
      // 被长按位置立即显示全新干扰项。
      updatedOptions[optionIndex] = ListeningMeaningOption(
        text: replacement,
        isCorrect: false,
      );
      // 正确答案移动到随机目标位置，交互不会暴露它的身份。
      updatedOptions[correctTarget] = selectedOption;
    } else {
      // 普通干扰项只替换自身位置，其余三个按钮完全不动。
      updatedOptions[optionIndex] = ListeningMeaningOption(
        text: replacement,
        isCorrect: false,
      );
    }
    setState(() {
      // 移除已消失文本的红色禁用状态，新候选可以正常点击。
      _wrongOptions.removeAll(removedWrongOptions);
      // 冻结新列表，保持页面状态只能整体更新。
      _options = List<ListeningMeaningOption>.unmodifiable(updatedOptions);
    });
    // 长按刷新改变了当前可见候选，也要同步进会话快照。
    unawaited(_persistSession());
    // UI 已立即替换；SQLite 写入在后台完成，不让本地 I/O 拖慢手感。
    unawaited(
      _persistRefreshedOptions(
        isWordStage: isWordStage,
        anchorId: anchorId,
        options: updatedOptions,
      ),
    );
  }

  ///
  /// 显示刷新确认框；返回 true 表示用户确认替换当前候选词。
  Future<bool> _showOptionRefreshDialog(String optionText) async {
    // showDialog 的 null 表示点遮罩或系统返回，统一按取消处理。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        // 对话框跟随当前明暗主题。
        final tokens = AppTokens.of(dialogContext);
        return Dialog(
          backgroundColor: tokens.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题用 Tabler 刷新图标，不使用文字字符代替图标。
                Row(
                  children: [
                    const Icon(
                      TablerIcons.refresh,
                      size: 20,
                      color: AppTokens.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '刷新候选词',
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 明确指出用户刚才长按的文本，避免误操作。
                Text(
                  '是否将“$optionText”更换为新的候选词？',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    // 取消是次要命令，使用 Tabler X 图标和描边按钮。
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('cancel-option-refresh'),
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        icon: const Icon(TablerIcons.x, size: 16),
                        label: const Text('取消'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.textMedium,
                          side: BorderSide(color: tokens.inputBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 确认是主命令，使用品牌蓝与 Tabler 刷新图标。
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('confirm-option-refresh'),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        icon: const Icon(TablerIcons.refresh, size: 16),
                        label: const Text('刷新'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    // 只有显式点“刷新”才返回 true。
    return confirmed ?? false;
  }

  ///
  /// 把长按刷新后的候选名字和完整顺序覆盖进当前小题缓存。
   ///
  /// 把长按刷新后的混淆词回写到单词行 / 含义行。
  ///
  /// 用户对某个混淆词不满意，长按换一个——换完的这一批就是新的长期结果，
  /// 之后所有模块都会用到它，所以必须落库而不是只改内存。
  Future<void> _persistRefreshedOptions({
    required bool isWordStage,
    required int? anchorId,
    required List<ListeningMeaningOption> options,
  }) async {
    if (anchorId == null) return;
    // 正确答案不写进混淆词，只保存三个干扰项。
    final confusions = options
        .where((option) => !option.isCorrect)
        .map((option) => option.text)
        .toList(growable: false);
    try {
      if (isWordStage) {
        await _wordStore.saveWordConfusions(anchorId, confusions);
      } else {
        await _wordStore.saveMeaningConfusions(anchorId, confusions);
      }
    } catch (error) {
      // 页面替换已经完成；记录错误即可，下次进入仍可继续正常答题。
      debugPrint('保存刷新后的混淆词失败：$error');
    }
  }

  ///
  /// 标记当前单词的拼写和全部释义均已答对。
  void _completeCurrentWord() {
    // 单词完成给予中等震动，作为里程碑反馈。
    HapticFeedback.mediumImpact();
    // 当前题已经结束，作废尚未返回的候选缓存读取。
    _optionLoadGeneration++;
    // 只更新当前题状态，不在正确答案点击中立即跳走。
    setState(() {
      // 底部会根据这个字段从候选区切换为长条按钮。
      _isCurrentWordComplete = true;
      // 清空错误项状态。
      _wrongOptions.clear();
      // 完成后不再保留可点击选项数据。
      _options = const <ListeningMeaningOption>[];
      // 中间信息面板告知用户当前单词已经完成。
      // 全程零错选才是“一气呵成”，与候选区上方的成功横幅口径一致。
      _feedback = _currentWrong == 0 ? '一气呵成 · 完美通过！' : '本词完成！';
      // 绿色只用于正确完成反馈。
      _feedbackColor = const Color(0xFF2FB344);
    });
    // “本词完成、等待下一题”是重要恢复点；此时仍不能提前写听音辨义记录。
    unawaited(_persistSession());
    // 自动重播一次发音作为答对奖励：既有听觉反馈，又强化单词记忆。
    // interrupt: true —— 若用户刚好手动点了播放，奖励发音直接接管，不会被忽略。
    unawaited(_playAudio(interrupt: true));
  }

  ///
  /// 把当前单词的本次听音辨义结果写入记录 Store。
  ///
  /// 这一步只在用户点击「下一题」后发生；停留在完成态或点击「再试一次」都不会
  /// 写数据库。此时 [_currentWrong]/[_currentHints] 仍保存着本词累计数据。
  /// 若单词没有主键（极端情况）则直接跳过，并允许页面继续推进。
  ///
  /// 关于正误的口径（重要）：听音辨义只能以"全部选对"结束，所以不能用"是否
  /// 完成"来判断对错。真正有意义的判定是**本次过程中有没有选错过候选词**：
  /// - 一次没错（[_currentWrong] == 0）→ 视为本次听音辨义正确；
  /// - 中途选错过 → 视为本次听音辨义错误，原生据此把连对次数归零、难度 +1。
  /// 点击提示只作为 hintCount 留档，不影响正误判定（提示不等于答错）。
   ///
  /// 给当前单词结算：更新难度，必要时推进复习时间。
  ///
  /// 这一步只在用户点击「下一题」后发生；停留在完成态或点击「再试一次」都不会
  /// 结算。若单词没有主键（极端情况）则直接跳过，并允许页面继续推进。
  ///
  /// 关于正误的口径：听音辨义只能以「全部选对」结束，所以不能用「是否完成」
  /// 判断对错。真正有意义的判定是**本局这个词有没有点错过候选**——
  /// 每一次点击都写了记录，结算时由数据库直接数出来，页面不必自己记账。
  Future<bool> _recordCompletion() async {
    // 取出当前单词主键。
    final wordId = _currentWord.id;
    // 没有主键无法落库；它通常只会出现在尚未保存的测试数据中。
    if (wordId == null) return true;
    try {
      // 等待原生事务真正结束后才允许切题，确保首页回刷时能读取到最新数据。
      await _progress.settle(wordId);
      // 只有事务成功后才把 id 带回首页，避免首页回刷一条并未更新的数据。
      _reviewedWordIds.add(wordId);
      // true 告诉按钮流程可以安全进入下一题。
      return true;
    } catch (error) {
      // 保留日志便于开发时定位原生数据库异常。
      debugPrint('结算听音辨义单词失败：$error');
      // 页面仍存在时给用户明确反馈，并停留在本题以便再次点击重试。
      if (mounted) Toast.show(context, '保存听音辨义结果失败，请重试');
      // false 阻止切题，避免用户误以为本次结果已经保存。
      return false;
    }
  }

  ///
  /// 退出听音辨义页，并把本次复习过的单词 id 集合带回首页，供其定向回刷。
  ///
  /// 通过 [Navigator.pop] 的结果参数传出，避免首页重新加载整库。
  void _exitListeningMeaning() {
    // 用户点击下一题后必须等事务结束；保存中主动返回会让首页漏掉最新回刷 id。
    if (_isSavingCompletion) return;
    // 把收集到的 id 列表作为路由结果返回给上一页。
    Navigator.pop(context, _reviewedWordIds.toList());
  }

  ///
  /// 用户点击底部长条按钮后先提交当前结果，再进入下一词或整轮完成页。
  Future<void> _goToNextWord() async {
    // 只有当前题已完成才允许推进，防止外部误调用跳过题目。
    if (!_isCurrentWordComplete || _isSavingCompletion) return;
    // 先锁住两个完成态按钮，避免连点「下一题」插入重复记录。
    setState(() => _isSavingCompletion = true);
    // 本地 SQLite 事务完成后再换题，保证后续读到的是最新难度与复习时间。
    final didSave = await _recordCompletion();
    // 保存期间用户可能通过系统返回键关闭页面，异步回来后不能再调用 setState。
    if (!mounted) return;
    // 事务失败时解除按钮锁并停留在当前题，用户可以再次提交。
    if (!didSave) {
      setState(() => _isSavingCompletion = false);
      return;
    }
    // 最后一题提交成功后进入整轮完成状态页，由用户确认后再返回首页。
    if (_wordIndex + 1 >= widget.words.length) {
      // 整轮完成给予中等震动，与单词完成反馈保持一致。
      HapticFeedback.mediumImpact();
      // 作废尚未结束的奖励发音代次，防止旧请求随后覆盖完成页状态。
      _playGeneration++;
      setState(() {
        // 切换到整轮完成页面。
        _isDone = true;
        // 原生事务已经成功，解除保存期间的返回锁。
        _isSavingCompletion = false;
        // 完成页不显示播放中图标与当前单词反馈。
        _isPlaying = false;
        _feedback = '';
      });
      // 最后一题记录已经成功提交，整轮不再属于未完成历史。
      unawaited(_finishSession());
      // 停止可能仍在播放的答对奖励音频。
      unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
      return;
    }
    // 一次 setState 完整重置新单词的全部答题状态。
    setState(() {
      // 保持 widget.words 原始顺序，只把下标向后移动一位。
      _wordIndex++;
      // 每个新单词都从拼写阶段开始。
      _stage = ListeningMeaningStage.word;
      // 词性下标回到第一项。
      _meaningIndex = 0;
      // 清除上一题的错误禁用项。
      _wrongOptions.clear();
      // 新单词的错误计数归零，重新开始统计。
      _currentWrong = 0;
      // 新单词尚未完成。
      _isCurrentWordComplete = false;
      // 上一题事务已结束，新题允许正常交互。
      _isSavingCompletion = false;
      // 清除上一题的完成反馈。
      _feedback = '';
      // 反馈颜色恢复主题默认值。
      _feedbackColor = null;
      // 根据新的 _wordIndex 生成四个拼写候选项。
      _options = _buildOptions();
    });
    // 新单词从拼写阶段开始，保存推进后的下标与全新题面。
    unawaited(_persistSession());
    // 新单词的拼写题使用自己的持久化候选缓存。
    unawaited(_restoreOrCreateCurrentConfusions());
    // 与首次进入页面一致，新题自动发音一次。
    // interrupt: true 是本次 bug 的修复点：上一题答对后的"奖励发音"可能仍在播放，
    // 必须允许新单词直接把它打断，否则新题的发音会被旧音频挡住而完全听不到。
    unawaited(_playAudio(interrupt: true));
  }

  ///
  /// 用户点击"再试一次"：把当前单词整体退回刚进入这一题时的状态。
  ///
  /// 语义等同于"这道题重做一遍"：拼写没选、释义没选、提示未展开、错项全部清空，
  /// 并像刚进入新题一样自动发音一次。本题错误与提示次数也会归零，最终只提交
  /// 用户重做这一遍产生的数据。
  void _retryCurrentWord() {
    // 只有当前题处于"已完成"状态时才会出现这个按钮，其余情况忽略调用。
    if (!_isCurrentWordComplete || _isDone || _isSavingCompletion) return;
    // 轻触震动确认操作已被接受。
    HapticFeedback.lightImpact();
    // 一次 setState 完整回滚当前题的全部答题状态（与 _goToNextWord 相同的字段集，
    // 唯一区别是不移动 _wordIndex，仍停留在同一个单词上）。
    setState(() {
      // 回到拼写阶段，重新"听音选词"。
      _stage = ListeningMeaningStage.word;
      // 词性下标回到第一项。
      _meaningIndex = 0;
      // 清除被标红禁用的错误候选项。
      _wrongOptions.clear();
      // 本题错误计数归零，重做后按新一次成绩结算。
      _currentWrong = 0;
      // 退出完成态，底部重新显示四选一与提示/播放按钮。
      _isCurrentWordComplete = false;
      // 清除"本词完成！"反馈。
      _feedback = '';
      // 反馈颜色恢复主题默认值。
      _feedbackColor = null;
      // 重新生成当前单词的四个拼写候选项。
      _options = _buildOptions();
    });
    // 重做会清空本词旧状态，立即覆盖会话，避免下次恢复到已完成态。
    unawaited(_persistSession());
    // 重做回到当前单词拼写题，重新读取它此前缓存的三个干扰项。
    unawaited(_restoreOrCreateCurrentConfusions());
    // 与进入新题一致自动发音；同样要打断可能仍在播放的奖励音频。
    unawaited(_playAudio(interrupt: true));
  }

  ///
  /// 构建当前单词的完整步骤清单：先“听音选词”，再逐条词性释义。
  ///
  /// 每个步骤都从一开始列出，状态随答题进度在 未开始/进行中/已完成 之间变化。
  /// 组件只负责按状态渲染，不关心答题下标。
  List<ListeningMeaningStep> _buildSteps() {
    // 步骤集合从“听音选词”开始，拼写答对后它转为已完成。
    final steps = <ListeningMeaningStep>[
      ListeningMeaningStep(
        kind: ListeningMeaningStepKind.word,
        title: '听音选词',
        // 完成后把正确单词带进步骤，便于在步骤下方直接回显。
        word: _currentWord.spelling,
        // 拼写阶段结束后，单词步骤即视为完成；否则当前就是进行中的那一步。
        status:
            _stage == ListeningMeaningStage.definition || _isCurrentWordComplete
            ? ListeningMeaningStepStatus.done
            : (_stage == ListeningMeaningStage.word
                  ? ListeningMeaningStepStatus.active
                  : ListeningMeaningStepStatus.pending),
      ),
    ];
    // **一个词性一个步骤**，不是一条释义一个步骤。
    //
    // protect 在词库里是「* 保护；防护；扶持」——一个词性下三条释义，
    // 步骤条就该只有一格「释义」，格子里逐条填满，而不是并排三格都叫「释义」。
    // 答题仍然按单条释义推进（_meaningIndex 走的是摊平后的下标），
    // 这里只负责把它换算回「第几个词性分组、组内答到第几条」。
    var flatIndex = 0;
    for (final group in _currentWord.meaningGroups) {
      // 这一组在摊平列表里的区间是 [flatIndex, groupEnd)。
      final groupStart = flatIndex;
      final groupEnd = groupStart + group.meanings.length;
      flatIndex = groupEnd;

      // 整词完成，或答题下标已经走过这一组，说明这组全部答对了。
      final isGroupDone = _isCurrentWordComplete || _meaningIndex >= groupEnd;
      // 释义阶段且当前下标落在这一组区间内，这组正在进行中。
      final isGroupActive =
          !_isCurrentWordComplete &&
          _stage == ListeningMeaningStage.definition &&
          _meaningIndex >= groupStart &&
          _meaningIndex < groupEnd;

      // 已答出的释义：整组答完显示全部，进行中只显示已经答对的那几条。
      final answeredCount = isGroupDone
          ? group.meanings.length
          : (isGroupActive ? _meaningIndex - groupStart : 0);
      final definitions = answeredCount > 0
          ? List<String>.unmodifiable(<String>[
              for (final meaning in group.meanings.take(answeredCount))
                meaning.definition,
            ])
          : null;

      steps.add(
        ListeningMeaningStep(
          kind: ListeningMeaningStepKind.meaning,
          title: '释义',
          status: isGroupDone
              ? ListeningMeaningStepStatus.done
              : (isGroupActive
                    ? ListeningMeaningStepStatus.active
                    : ListeningMeaningStepStatus.pending),
          // 未选词性显示成星号，与词库里的「*」占位口径一致。
          pos: group.pos == '*' ? '*' : group.pos,
          definitions: definitions,
        ),
      );
    }
    // 冻结列表，展示组件只读取，不修改步骤状态。
    return List<ListeningMeaningStep>.unmodifiable(steps);
  }

  ///
  /// 返回当前答题阶段的用户可见名称。
  String get _stageLabel {
    // 完成后的提示不再要求选择，只说明当前单词已完成。
    if (_isCurrentWordComplete) return '当前单词已完成';
    // 拼写阶段引导用户通过发音选出单词。
    if (_stage == ListeningMeaningStage.word) return '听音，选出正确的单词';
    // 找到当前这条释义属于哪个词性分组，进度按「组内第几条 / 组内共几条」显示。
    var flatIndex = 0;
    for (final group in _currentWord.meaningGroups) {
      final groupEnd = flatIndex + group.meanings.length;
      if (_meaningIndex < groupEnd) {
        final pos = group.pos == '*' ? '*' : group.pos;
        return '$pos · 选择释义 ${_meaningIndex - flatIndex + 1}/${group.meanings.length}';
      }
      flatIndex = groupEnd;
    }
    // 理论上走不到这里；真走到了说明下标越界，给一句不会误导的兜底。
    return '选择释义';
  }

  ///
  /// 释放音频请求并补写尚未完成的页面状态。
  @override
  void deactivate() {
    // 路由刚被移出导航栈（手势/按钮返回的转场动画一开始）就立即作废在途异步任务，
    // 把主线程让给返回动画，避免“划动手势卡顿/掉帧”的问题。
    // 生活化解释：和随身听页退出时停掉自动播放是同一类处理——
    // 只要页面开始滑走，就不再允许后台的候选加载或发音回调去 setState 抢帧。
    // 注意：此时 State 仍是 mounted，若只靠 dispose 取消，转场动画期间仍在跑，
    // 所以必须在 deactivate（转场起点）就作废代次并把音频停下。
    // 让尚未结束的候选缓存读取失效，回调回来后不再改写已滑走的页面。
    _optionLoadGeneration++;
    // 让尚未结束的发音回调失效，避免转场期间再触发 setState。
    _playGeneration++;
    // 顺手停止可能仍在播放的发音，让位给返回动画。
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    super.deactivate();
  }

  @override
  void dispose() {
    // 页面销毁前注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    // 停掉右上角计时器，避免释放后回调。
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    // 系统返回（手势或返回键）时触发最后一博：立即把当前答题快照写入数据库。
    // _persistSession 内部本身是轻量的（key-value 存储），直接同步 await 不会显著阻塞转场，
    // 但能确保用户手势返回时，首页能在同一帧读到最新会话并立即重建「继续」入口卡片。
    if (!_isDone) {
      // ignore: discarded_futures —— dispose 中必须同步完成保存，不能丢
      _persistSession();
    }
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    super.dispose();
  }

  ///
  /// 构建听音辨义页、题目页或整轮完成页。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final progress =
        (_isDone ? widget.words.length : _wordIndex + 1) / widget.words.length;

    // 保存中禁止系统返回手势，避免事务成功后首页却收不到需要回刷的单词 id。
    return PopScope<Object?>(
      canPop: !_isSavingCompletion,
      child: Scaffold(
        backgroundColor: tokens.page,
        body: SafeArea(
          child: Column(
            children: [
              // 顶栏和进度条与随身听共用相同的位置、尺寸和对齐逻辑。
              _buildHeader(tokens, progress),
              if (_isDone)
                Expanded(child: _buildDone(tokens))
              else ...[
                // 可滚动题目区占满候选词以上的空间，轻点其中任意位置都能重播。
                Expanded(child: _buildQuestion(tokens)),
                // 难度横幅在文档流中贴着底部候选区正上方，不再悬浮遮挡内容。
                _buildDifficultyHintBanner(tokens),
                // 底部候选词位于文档流底部：一行两个，与看义选词一致。
                _isCurrentWordComplete
                    ? _buildNextQuestionButton(tokens)
                    : _buildBottomControls(tokens),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ///
  /// 构建顶栏与进度条，布局结构和随身听页面保持一致。
  Widget _buildHeader(AppTokens tokens, double progress) {
    // Column 让顶栏按钮行和进度条从上到下排列。
    return Column(
      // 顶部区域只占自身实际高度，不抢占中间题目区的空间。
      mainAxisSize: MainAxisSize.min,
      children: [
        // Padding 统一管理顶栏与屏幕边界的距离。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ListeningMeaningLayout.pageInset,
            ListeningMeaningLayout.headerTop,
            ListeningMeaningLayout.pageInset,
            0,
          ),
          // 用 Stack 而不是 Row：左右两侧宽度不一定相等，
          // 只有绝对定位才能保证中央题号严格居中，右上角挂 mm:ss 计时。
          child: SizedBox(
            height: ListeningMeaningLayout.headerButtonSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '${_isDone ? widget.words.length : _wordIndex + 1} / ${widget.words.length}',
                      key: const Key('listening-meaning-progress-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        // tabularFigures 让每个数字占用相同宽度，题号变化时视觉中心不抖动。
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PlainIconButton(
                    key: const Key('close-listeningMeaning'),
                    icon: TablerIcons.chevronLeft,
                    alignment: Alignment.centerLeft,
                    onTap: _exitListeningMeaning,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatElapsed(),
                    key: const Key('listening-meaning-elapsed'),
                    style: TextStyle(
                      color: tokens.textMedium,
                      fontSize: 13,
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
        // 进度条的左右边界与顶栏严格对齐。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ListeningMeaningLayout.pageInset,
            ListeningMeaningLayout.progressTop,
            ListeningMeaningLayout.pageInset,
            0,
          ),
          // ClipRRect 只把线性进度条的两端裁成轻微圆角。
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const Key('listening-meaning-progress-bar'),
              value: progress,
              minHeight: ListeningMeaningLayout.progressHeight,
              color: AppTokens.accent,
              backgroundColor: tokens.sub,
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建可滚动题目区与透明播放热区；底部候选词在文档流中（见页面 body）。
  Widget _buildQuestion(AppTokens tokens) {
    // Stack 底部候选区不再与滚动内容重叠（已移出到文档流），
    // 但透明播放层仍需覆盖整个可滚动区域，轻点任意位置都能重播。
    return Stack(
      key: const Key('listening-meaning-question-stack'),
      fit: StackFit.expand,
      children: [
        // 第一层兼具“透明播放命中层”和可滚动内容容器：GestureDetector 自身不绘制颜色，
        // 但会占满顶部区域以下的全部空间。它包在 ScrollView 外层，因此轻点播放，
        // 纵向拖动时 ScrollView 的手势识别器仍可赢得手势竞争并正常滚动。
        Positioned.fill(
          child: GestureDetector(
            key: const Key('listening-meaning-question-audio-overlay'),
            behavior: HitTestBehavior.translucent,
            // 点屏幕重播：允许打断正在播放的旧发音，立即播新的，不再需等播完。
            onTap: () => _playAudio(interrupt: true),
            child: Semantics(
              button: true,
              label: '播放当前单词发音',
              child: SingleChildScrollView(
                key: const Key('listening-meaning-question-scroll'),
                padding: EdgeInsets.fromLTRB(
                  ListeningMeaningLayout.pageInset,
                  ListeningMeaningLayout.questionVerticalInset,
                  ListeningMeaningLayout.pageInset,
                  ListeningMeaningLayout.questionVerticalInset,
                ),
                // Align 让窄屏占满可用宽度，宽屏限制宽度后仍保持水平居中。
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ListeningMeaningLayout.questionMaxWidth,
                    ),
                    // 独立组件按“单词卡、提示横幅、全量步骤”从上到下输出。
                    child: ListeningMeaningQuestionContent(
                      spelling: _currentWord.spelling,
                      revealWholeWord:
                          _stage == ListeningMeaningStage.definition ||
                          _isCurrentWordComplete,
                      // 单词卡上的发音按钮同样允许打断重播。
                      onSpeakerTap: () => _playAudio(interrupt: true),
                      isPlaying: _isPlaying,
                      prompt: _stageLabel,
                      feedback: _feedback,
                      feedbackColor: _feedbackColor,
                      steps: _buildSteps(),
                      definitionSeparator: widget.definitionSeparator,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 在底部操作区正上方显示结果提示横幅（纯界面提示，完全不经过数据库）。
  /// 它根据当前单词状态在「错误提示」与「正确提示」之间切换：
  ///
  /// - 错误提示（[ _currentWrong ] > 0）：本题选错过即展示，文案表达“当前单词错了几次”。
  ///   作答中途横幅位于候选区正上方；完成后若仍有错，则位于「再试一次 / 下一题」上方。
  /// - 正确提示（[ _isCurrentWordComplete ] 且全程零错选）：成功色横幅“一气呵成 · 完美通过！”。
  /// 其余状态（正在作答且尚未出错）返回零尺寸占位。
  ///
  /// 生活化解释：这道横幅是给用户看的即时反馈，不碰数据库。
  /// “难度 +1”真正发生是在点“下一题”写库那一刻；这里只告诉用户本题到底错了几次，
  /// 让他离场前心里有数，而不是等到下一轮才发现刚才选错过。
  Widget _buildDifficultyHintBanner(AppTokens tokens) {
    // 取出当前状态对应的语义色、图标与文案；text 为 null 表示无需提示。
    final visual = _difficultyHintVisual();
    // 没有任何需要提示的状态时，不渲染横幅，避免占用布局与误导用户。
    if (visual.text == null) return const SizedBox.shrink();

    // Container 复用单词卡同款圆角与描边，让横幅与界面其余卡片视觉一致。
    return Container(
      key: const Key('listening-meaning-difficulty-hint'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        // 危险用极淡红底，成功用极淡绿底，颜色再淡也不会丢失语义。
        color: visual.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ListeningMeaningLayout.cardRadius),
        // 同色描边强化边框，呼应 Tabler 的告警/成功徽章视觉。
        border: Border.all(color: visual.color.withValues(alpha: 0.55)),
      ),
      // Row 让图标与文案水平排列，整体按内容宽度收缩并居中。
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 16, color: visual.color),
          const SizedBox(width: 8),
          Text(
            visual.text!,
            style: TextStyle(
              color: visual.color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 返回难度提示横幅的视觉三要素：语义色、Tabler 图标、文案。
  ///
  /// 文案为 null 表示当前不需要展示任何提示。
  ({Color color, IconData icon, String? text}) _difficultyHintVisual() {
    // 错误提示：只要本题选错过（无论是否已完成），都展示累计错误次数。
    // - 作答中途：横幅位于候选区正上方，实时告诉用户已经错了几下；
    // - 完成后仍有错：横幅位于「再试一次 / 下一题」上方，让用户离场前看到总错次。
    // 文案表达“当前单词错了几次”，不再强调“难度 +1”（难度真正变化在点下一题写库时）。
    if (_currentWrong > 0) {
      return (
        color: AppTokens.danger,
        icon: TablerIcons.alertTriangle,
        text: '本题已答错 $_currentWrong 次',
      );
    }
    // 正确提示：完成且全程零错选，给出“一气呵成”的正向反馈（用户要求保持不变）。
    if (_isCurrentWordComplete) {
      return (
        color: const Color(0xFF2FB344),
        icon: TablerIcons.circleCheck,
        text: '一气呵成 · 完美通过！',
      );
    }
    // 其余状态（正在作答且尚未出错）不提示。
    return (
      color: AppTokens.danger,
      icon: TablerIcons.alertTriangle,
      text: null,
    );
  }

  ///
  /// 构建贴近底部安全区的候选与操作区。
  Widget _buildBottomControls(AppTokens tokens) {
    // Padding 在 SafeArea 已避开系统手势条后，再提供 20 像素底部留白。
    return Padding(
      key: const Key('listening-meaning-bottom-controls'),
      padding: const EdgeInsets.fromLTRB(
        ListeningMeaningLayout.pageInset,
        ListeningMeaningLayout.bottomSectionTop,
        ListeningMeaningLayout.pageInset,
        ListeningMeaningLayout.bottomInset,
      ),
      // 候选词位于文档流底部：与看义选词一致，一行两个、底边对齐，
      // 不再有悬浮右侧的播放按钮（重播交给单词卡听音钮与透明播放层）。
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 用父级实际宽度算按钮宽度：一行两个，各占 (宽 − 间距) / 2。
          final buttonWidth =
              (constraints.maxWidth - ListeningMeaningLayout.optionGap) / 2;
          // 候选组外包一层 AnimatedSwitcher：进入下一小题 / 下一词 / 刷新候选时，
          // 旧候选组淡出、新候选组淡入，整组切换不整体下沉回弹（仿 Duolingo / Quizlet）。
          return AnimatedSwitcher(
            // 整组过渡时长，210ms 让切换更利落。
            duration: const Duration(milliseconds: 210),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            // 用当前四个候选文本拼接成唯一 Key；文本变化即触发整组过渡。
            child: Wrap(
              key: ValueKey(
                'listening-meaning-option-group-${_options.map((option) => option.text).join('|')}',
              ),
              spacing: ListeningMeaningLayout.optionGap,
              runSpacing: ListeningMeaningLayout.optionGap,
              children: <Widget>[
                for (var index = 0; index < _options.length; index += 1)
                  // 每个选项由独立 _OptionCard 管理，支持错选抖动动画。
                  _OptionCard(
                    key: ValueKey(
                      'listening-meaning-option-$index-${_options[index].text}',
                    ),
                    option: _options[index],
                    index: index,
                    width: buttonWidth,
                    wrong: _wrongOptions.contains(_options[index].text),
                    onTap: () => _pickOption(_options[index]),
                    // 长按任意候选都进入同一刷新确认流程，不暴露正确答案身份。
                    onLongPress: () => _requestOptionRefresh(index),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  ///
  /// 构建当前单词全部答对后的底部操作区：左「再试一次」+ 右「下一题」。
  ///
  /// 两个按钮通过 Expanded 各占一半宽度，中间用 [ListeningMeaningLayout.columnGap]
  /// 留出间距。
  /// 左侧是次要操作（描边样式），右侧是主操作（蓝色实心）。
  Widget _buildNextQuestionButton(AppTokens tokens) {
    // 最后一题提交后会进入完成状态页，因此主操作使用“完成”语义。
    final isLastWord = _wordIndex + 1 >= widget.words.length;
    // Padding 与普通候选区共用相同的左右、顶部和安全区留白。
    return Padding(
      key: const Key('listening-meaning-next-area'),
      padding: const EdgeInsets.fromLTRB(
        ListeningMeaningLayout.pageInset,
        ListeningMeaningLayout.bottomSectionTop,
        ListeningMeaningLayout.pageInset,
        ListeningMeaningLayout.bottomInset,
      ),
      // SizedBox 固定整行高度，两个按钮上下边界完全一致。
      child: SizedBox(
        width: double.infinity,
        height: ListeningMeaningLayout.actionHeight,
        child: Row(
          children: [
            // 左半：次要操作「再试一次」，把当前题退回初始状态重做。
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('retry-listening-meaning-word'),
                onPressed: _isSavingCompletion ? null : _retryCurrentWord,
                // Tabler 的刷新图标表达"重来一遍"。
                icon: const Icon(TablerIcons.refresh, size: 17),
                label: const Text('再试一次'),
                style: OutlinedButton.styleFrom(
                  // 描边样式使用卡片底色，视觉权重低于右侧主操作。
                  backgroundColor: tokens.card,
                  foregroundColor: tokens.textMedium,
                  side: BorderSide(color: tokens.inputBorder),
                  // 高度由外层 SizedBox 决定，这里去掉按钮自带的最小宽高限制。
                  minimumSize: const Size(
                    0,
                    ListeningMeaningLayout.actionHeight,
                  ),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // 两个按钮之间的固定间距，复用候选区与操作区的同一套尺寸。
            const SizedBox(width: ListeningMeaningLayout.columnGap),
            // 右半：普通题进入「下一题」，最后一题提交后进入完成状态页。
            Expanded(
              // FilledButton.icon 用蓝色背景表达当前的主操作。
              child: FilledButton.icon(
                key: const Key('next-listening-meaning-word'),
                onPressed: _isSavingCompletion ? null : _goToNextWord,
                // 最后一题使用 Tabler 勾选图标，其余题使用向右箭头。
                icon: Icon(
                  isLastWord ? TablerIcons.check : TablerIcons.arrowRight,
                  size: 17,
                ),
                // 文案明确区分“继续答题”和“提交整轮”。
                label: Text(isLastWord ? '完成' : '下一题'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.accent,
                  foregroundColor: Colors.white,
                  // 与左侧按钮保持同样的高度基准和无额外内边距。
                  minimumSize: const Size(
                    0,
                    ListeningMeaningLayout.actionHeight,
                  ),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建整轮听音辨义完成状态页，展示题量、累计错选次数和返回入口。
  Widget _buildDone(AppTokens tokens) {
    // Center 让完成反馈在剩余页面区域中保持视觉居中。
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 绿色圆形图标作为整轮完成的主要视觉反馈。
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0x222FB344),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                TablerIcons.check,
                size: 32,
                color: Color(0xFF2FB344),
              ),
            ),
            const SizedBox(height: 12),
            // 状态标题说明本轮流程已经结束。
            Text(
              '听音辨义完成',
              style: TextStyle(
                color: tokens.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // 统计本轮总单词数与所有错选次数，重做不会抹去已经发生的错误。
            Text(
              '共 ${widget.words.length} 个单词 · 答错 $_errors 次',
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            // 返回按钮把成功提交的单词 id 一并交回首页进行定向回刷。
            FilledButton(
              key: const Key('finish-listeningMeaning'),
              onPressed: _exitListeningMeaning,
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(112, 40),
                shape: const StadiumBorder(),
              ),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

///
/// 听音辨义顶栏使用的无文字 Tabler 图标按钮。
///
class _PlainIconButton extends StatelessWidget {
  ///
  /// 构建固定画布的顶栏图标按钮。
  const _PlainIconButton({
    required this.icon,
    required this.onTap,
    this.alignment = Alignment.center,
    super.key,
  });

  ///
  /// 需要显示的 Tabler 图标。
  final IconData icon;

  ///
  /// 用户点击图标画布时执行的回调。
  final VoidCallback onTap;

  ///
  /// 图标在 34 像素画布中的对齐方式。
  final AlignmentGeometry alignment;

  ///
  /// Flutter 每次需要绘制顶栏按钮时调用此方法。
  @override
  Widget build(BuildContext context) {
    // 读取当前亮色或深色主题中的文字颜色。
    final tokens = AppTokens.of(context);
    // SizedBox 明确约束点击画布，不让图标自身的透明空间影响顶栏对齐。
    return SizedBox(
      width: ListeningMeaningLayout.headerButtonSize,
      height: ListeningMeaningLayout.headerButtonSize,
      // InkWell 提供点击命中与圆形按压反馈。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          ListeningMeaningLayout.headerButtonSize / 2,
        ),
        // Align 使用正常布局约束对齐图标，不需要负数偏移。
        child: Align(
          alignment: alignment,
          child: Icon(icon, size: 21, color: tokens.textMedium),
        ),
      ),
    );
  }
}

///
/// 候选词卡片：错选时触发左右抖动动画，配合触觉反馈传达错误感。
///
/// 动画时长 300ms，振幅从 ±8px 衰减到 0，类似微信摇一摇的阻尼抖动。
/// 正确选项不做动画——页面立即切换为新题，视觉变化本身就是反馈。
///
class _OptionCard extends StatefulWidget {
  ///
  /// 创建一个支持错误抖动和长按刷新的候选卡片。
  const _OptionCard({
    required this.option,
    required this.index,
    required this.wrong,
    required this.width,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  ///
  /// 当前选项数据（文本 + 是否正确）。
  final ListeningMeaningOption option;

  ///
  /// 选项在四选一列表中的位置（0-3），用于 A/B/C/D badge。
  final int index;

  ///
  /// 是否已被选错；从 false 变 true 时触发抖动。
  final bool wrong;

  ///
  /// 卡片宽度；两列网格中每张卡各占 (可用宽度 − 间距) / 2。
  final double width;

  ///
  /// 点击回调；错选后由调用方传入 null 禁用。
  final VoidCallback onTap;

  ///
  /// 长按回调；即使该项已经选错，仍允许用户把它刷新成新候选。
  final VoidCallback onLongPress;

  ///
  /// 创建候选卡片动画状态。
  @override
  State<_OptionCard> createState() => _OptionCardState();
}

///
/// 管理候选卡片选错后的水平衰减抖动动画。
///
class _OptionCardState extends State<_OptionCard>
    with SingleTickerProviderStateMixin {
  ///
  /// 驱动一次 300ms 抖动过程的动画控制器。
  late final AnimationController _shakeController;

  ///
  /// 从零开始、经过正负位移并最终回到零的抖动曲线。
  late final Animation<double> _shakeAnimation;

  ///
  /// 初始化抖动动画控制器和位移序列。
  @override
  void initState() {
    super.initState();
    // 300ms 衰减抖动，类似物理阻尼效果。
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // Tween 序列模拟阻尼振荡：8 → -6 → 4 → -2 → 0。
    _shakeAnimation = TweenSequence<double>(
      <TweenSequenceItem<double>>[
        // 第一帧向左偏移 8px。
        TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 20),
        // 反弹向右 6px。
        TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 25),
        // 再向左 4px。
        TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 25),
        // 向右 2px。
        TweenSequenceItem(tween: Tween(begin: -4, end: 2), weight: 15),
        // 回到原位。
        TweenSequenceItem(tween: Tween(begin: 2, end: 0), weight: 15),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));
  }

  ///
  /// 在候选从正常状态变为错误状态时启动抖动。
  @override
  void didUpdateWidget(covariant _OptionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从"未错"变为"已错"时触发抖动。
    if (!oldWidget.wrong && widget.wrong) {
      _shakeController.forward(from: 0);
    }
  }

  ///
  /// 释放抖动动画控制器。
  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  ///
  /// 构建候选卡片及错误抖动效果。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final wrong = widget.wrong;
    // 两列网格中每张卡固定一半宽度，卡片内部文字随宽度自适应。
    return SizedBox(
      width: widget.width,
      child: AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // Transform.translate 按 animation 值做水平位移。
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Material(
        key: Key('listening-meaning-option-${widget.index}'),
        color: wrong ? AppTokens.danger.withValues(alpha: 0.08) : tokens.card,
        borderRadius: BorderRadius.circular(ListeningMeaningLayout.cardRadius),
        child: InkWell(
          onTap: wrong ? null : widget.onTap,
          // 长按不参与答题判定，只打开刷新候选词确认框。
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(
            ListeningMeaningLayout.cardRadius,
          ),
          child: Container(
            height: ListeningMeaningLayout.optionHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: ListeningMeaningLayout.optionHorizontalInset,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                ListeningMeaningLayout.cardRadius,
              ),
              border: Border.all(
                color: wrong ? AppTokens.danger : tokens.inputBorder,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: Key('listening-meaning-option-badge-${widget.index}'),
                    width: ListeningMeaningLayout.optionBadgeSize,
                    height: ListeningMeaningLayout.optionBadgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: wrong
                          ? AppTokens.danger.withValues(alpha: 0.10)
                          : tokens.sub,
                      border: Border.all(
                        color: wrong ? AppTokens.danger : tokens.rowBorder,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      String.fromCharCode('A'.codeUnitAt(0) + widget.index),
                      style: TextStyle(
                        color: wrong ? AppTokens.danger : tokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal:
                        ListeningMeaningLayout.optionBadgeSize +
                        ListeningMeaningLayout.optionHorizontalInset,
                  ),
                  // FittedBox 自适应：单词过长时整体等比缩小字号塞进可用宽度，
                  // 不靠换行/省略号把长词截掉，保证每个候选都完整可见。
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.option.text,
                      key: Key('listening-meaning-option-label-${widget.index}'),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: wrong ? AppTokens.danger : tokens.text,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
