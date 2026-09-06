// dart:async 提供 unawaited，播放音频时不阻塞按钮响应。
import 'dart:async';
// dart:math 用于打乱答案顺序和生成干扰项。
import 'dart:math';
// material.dart 提供全屏页面、进度条、卡片与按钮。
import 'package:flutter/material.dart';
// services.dart 提供 HapticFeedback，为每次选择添加触觉反馈。
import 'package:flutter/services.dart';
// 所有可见图标继续统一使用 Tabler。

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
// 引入全站统一的二次确认对话框：长按刷新候选词时弹的就是它。
import '../../widgets/app_confirm_dialog.dart';
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
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
    this.corpusWords,
    this.wordStore,
    this.definitionSeparator = '、',
    super.key,
  }) : assert(words.length > 0, '听音辨义页至少需要一个学习单词');

  ///
  /// 本轮参与听音辨义的单词。
  final List<Word> words;

  ///
  /// 全库词库，仅用于生成中文释义混淆词的候选池；缺省回退到 [words]。
  ///
  /// 结合《含义混淆词.md》的共享汉字算法，混淆词要从**整个词库**几千条中文
  /// 释义里找共享字，而不是只从本轮学习列表里抽，否则找不到同类项。首页持有
  /// 全库字词，打开听音辨义时顺手传进来即可。
  final List<Word>? corpusWords;

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
  /// 生成中文释义干扰项的全库语料；页面没传时退回本轮学习列表。
  ///
  /// 只用于 [buildDefinitionDistractors] 的候选池，不参与答题进度。
  List<Word> get _corpusWords => widget.corpusWords ?? widget.words;

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
        return;
      }
      _meaningIndex = nextIndex;
    } else {
      _stage = ListeningMeaningStage.word;
    }

    // 当前这一小题已经点错过哪些候选，恢复后继续保持红色禁用。
    final wrong = _stage == ListeningMeaningStage.word
        ? wordProgress.spellingWrongInputs
        : wordProgress.wrongInputsByMeaning[_availableMeanings[_meaningIndex]
                  .id] ??
              const <String>{};
    _wrongOptions.addAll(wrong);
    _currentWrong = wrong.length;
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
    // 拼写题与释义题分别复用原有生成规则。拼写题仍从本轮学习列表里找形状相近
    // 的英文干扰项；释义题改为共享汉字算法，从全库语料里找共享字的同类中文释义。
    return _stage == ListeningMeaningStage.word
        ? ListeningMeaningOptionGenerator.buildWordDistractors(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            count: count,
          )
        : ListeningMeaningOptionGenerator.buildDefinitionDistractors(
            correct: _currentCorrectAnswer,
            sourceWords: _corpusWords,
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
    final picks = <String>[
      for (final distractor in resolved.take(3)) distractor,
      correctText,
    ];
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
      await widget.audioPlayer.playRandomChannel(
        _currentWord.spelling,
        widget.accent,
      );
      // 智能轮转下 TTS 只会作为“网络全部不可用”的最后兜底出现（不再被点名），
      // 因此只要本次确由 TTS 完成，就值得在同一页面首次提示一次网络音频不可用。
      final playback = widget.audioPlayer.consumeLastPlayback();
      if (!_hasShownTtsNotice && playback.usedTts) {
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
          await widget.audioPlayer.playRandomChannel(
            _currentWord.spelling,
            widget.accent,
          );
          // 解码失败重试成功后，同样检查真实播放来源并只在首次提示一次。
          final retryPlayback = widget.audioPlayer.consumeLastPlayback();
          if (!_hasShownTtsNotice && retryPlayback.usedTts) {
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
      // 当前单词已完成但整局尚未结束时，计时仍属于本局，回前台也要继续。
      if (!_isDone) _startElapsedTimer();
      return;
    }
    // 退后台停表，避免把后台停留时间计进本局。
    _stopElapsedTimer();
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
    if (_isDone || _elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isDone) return;
      setState(() => _elapsedMs += 1000);
    });
  }

  /// 停止并清空计时器引用，保证回到前台时能够重新创建计时器。
  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
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
            sourceWords: _corpusWords,
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
  ///
  /// 骨架交给公共组件 [AppConfirmDialog]，这里只填这一处特有的文案与图标。
  Future<bool> _showOptionRefreshDialog(String optionText) {
    return AppConfirmDialog.show(
      context,
      AppConfirmDialog(
        titleIcon: AppGlyph.retry,
        title: '刷新候选词',
        // 明确指出用户刚才长按的文本，避免误操作。
        message: '是否将“$optionText”更换为新的候选词？',
        cancelKey: const Key('cancel-option-refresh'),
        cancelIcon: AppGlyph.dismiss,
        confirmKey: const Key('confirm-option-refresh'),
        confirmIcon: AppGlyph.retry,
        confirmLabel: '刷新',
      ),
    );
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
      });
      // 整局已经结束，彻底停表，避免完成页期间定时器继续空转。
      _stopElapsedTimer();
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
  /// 构建当前单词的完整步骤清单：先“听音选词”，再逐条选择释义。
  ///
  /// 每个步骤都从一开始列出，状态随答题进度在 未开始/进行中/已完成 之间变化。
  /// 组件只负责按状态渲染，不关心答题下标。
  List<ListeningMeaningStep> _buildSteps() {
    // 步骤集合从“听音选词”开始，拼写答对后它转为已完成。
    final steps = <ListeningMeaningStep>[
      ListeningMeaningStep(
        kind: ListeningMeaningStepKind.word,
        title: '听音辨词',
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
    // steps 需要和实际操作次数一一对应，而不是按词性分组。
    // 例如 hard 有 1 个单词选择和 6 个释义选择，所以这里必须生成 7 格。
    // 正文仍会在 _MeaningStage 中按词性重新聚合，避免同一词性重复显示多个标签。
    var flatIndex = 0;
    for (final group in _currentWord.meaningGroups) {
      for (final meaning in group.meanings) {
        // _meaningIndex 是所有释义合并后的下标，因此每一条释义都能直接对应
        // steps 中的一格，顶部进度条就会真实反映用户还需要完成几次选择。
        final isDone = _isCurrentWordComplete || _meaningIndex > flatIndex;
        final isActive =
            !_isCurrentWordComplete &&
            _stage == ListeningMeaningStage.definition &&
            _meaningIndex == flatIndex;

        steps.add(
          ListeningMeaningStep(
            kind: ListeningMeaningStepKind.meaning,
            title: '选择释义',
            status: isDone
                ? ListeningMeaningStepStatus.done
                : (isActive
                      ? ListeningMeaningStepStatus.active
                      : ListeningMeaningStepStatus.pending),
            // 未选词性显示成星号，与词库里的「*」占位口径一致。
            pos: group.pos == '*' ? '*' : group.pos,
            // 每一条释义独立占一格；正文稍后会按词性聚合这些数据。
            definitionTexts: List<String>.unmodifiable(<String>[
              meaning.definition,
            ]),
            definitions: isDone
                ? List<String>.unmodifiable(<String>[meaning.definition])
                : null,
          ),
        );
        flatIndex += 1;
      }
    }
    // 冻结列表，展示组件只读取，不修改步骤状态。
    return List<ListeningMeaningStep>.unmodifiable(steps);
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
    // 路由开始离场后立即停表，避免转场期间继续累加本局用时。
    _stopElapsedTimer();
    super.deactivate();
  }

  /// 页面被重新挂回树时恢复计时，兼容返回手势取消等临时离场场景。
  @override
  void activate() {
    super.activate();
    if (!_isDone) _startElapsedTimer();
  }

  @override
  void dispose() {
    // 页面销毁前注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    // 停掉右上角计时器，避免释放后回调。
    _stopElapsedTimer();
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
  ///
  /// 骨架整块交给模块模板 [ModuleScaffold]：上段顶栏、中段题目、下段操作区。
  /// 下段这里塞的是「难度横幅 + 候选词（或下一题按钮）」两件叠在一起的东西，
  /// 所以先用一个 Column 打包再交给 `footer` 插槽。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 完成后题号停在总数上，不再继续加，否则会显示成「6 / 5」。
    final current = _isDone ? widget.words.length : _wordIndex + 1;

    return ModuleScaffold(
      // 保存中禁止系统返回手势，避免事务成功后首页却收不到需要回刷的单词 id。
      canPop: !_isSavingCompletion,
      header: ModuleHeader(
        leading: ModuleIconButton(
          key: const Key('close-listeningMeaning'),
          icon: AppGlyph.back,
          alignment: Alignment.centerLeft,
          onTap: _exitListeningMeaning,
        ),
        title: ModuleProgressLabel(
          textKey: const Key('listening-meaning-progress-label'),
          current: current,
          total: widget.words.length,
        ),
        trailing: ModuleTimeLabel(
          textKey: const Key('listening-meaning-elapsed'),
          text: _formatElapsed(),
        ),
        progress: current / widget.words.length,
        progressBarKey: const Key('listening-meaning-progress-bar'),
      ),
      // 可滚动题目区占满候选词以上的空间，轻点其中任意位置都能重播。
      body: _isDone ? _buildDone() : _buildQuestion(tokens),
      // 结果提示已移入白卡底部，下段只剩候选词 / 操作区，不再需要外层 Column 包裹。
      footer: _isDone
          ? null
          : _isCurrentWordComplete
              ? _buildNextQuestionButton(tokens)
              : _buildBottomControls(tokens),
    );
  }

  // 顶栏那一行（返回键、中间题号、右上角用时、进度条）已经整块交给模块模板的
  // ModuleHeader，本页不再自己拼一遍。

  ///
  /// 构建可滚动题目区与透明播放热区；底部候选词在文档流中（见页面 body）。
  Widget _buildQuestion(AppTokens tokens) {
    // 结果提示（错误次数 / 全对）先在这里算好，再交给正文白卡贴到底部展示，
    // 不再作为独立横幅插入白卡与候选区之间。
    final hint = _difficultyHintVisual();
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
              child: LayoutBuilder(
                builder: (context, viewportConstraints) {
                  // ScrollView 在纵向会放开子项高度，因此先用视口高度算出卡片
                  // 的最小高度，才能实现 HTML flex: 1 的“剩余空间占满”效果。
                  final minCardHeight = max(
                    0.0,
                    viewportConstraints.maxHeight -
                        ListeningMeaningLayout.questionVerticalInset * 2,
                  );
                  return SingleChildScrollView(
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
                        constraints: BoxConstraints(
                          minHeight: minCardHeight,
                          maxWidth: ListeningMeaningLayout.questionMaxWidth,
                        ),
                        // 独立组件按“正文 + 底部结果提示”从上到下输出。
                        child: ListeningMeaningQuestionContent(
                          spelling: _currentWord.spelling,
                          revealWholeWord:
                              _stage == ListeningMeaningStage.definition ||
                              _isCurrentWordComplete,
                          // 单词卡上的发音按钮同样允许打断重播。
                          onSpeakerTap: () => _playAudio(interrupt: true),
                          isPlaying: _isPlaying,
                          steps: _buildSteps(),
                          definitionSeparator: widget.definitionSeparator,
                          // 播音胶囊沿用拼写巩固模块的口音文案，确保设置和实际发音一致。
                          accentLabel: widget.accent.label,
                          // 结果提示（错误次数 / 全对）贴在白卡底部；不展示时 text 为 null。
                          hintText: hint.text,
                          hintColor: hint.color,
                          hintIcon: hint.icon,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }


  ///
  /// 返回结果提示（错误次数 / 全对）的视觉三要素：语义色、Tabler 图标、文案。
  ///
  /// 这组值交给正文白卡，由白卡贴在自己底部渲染（见
  /// [ListeningMeaningQuestionContent] 的 `hintText` / `hintColor` / `hintIcon`）；
  /// 文案为 null 表示当前不需要展示提示。
  ({Color color, IconData icon, String? text}) _difficultyHintVisual() {
    // 错误提示：只要本题选错过（无论是否已完成），都在白卡底部展示累计错误次数，
    // 文案表达“当前单词错了几次”，不再强调“难度 +1”（难度真正变化在点下一题写库时）。
    if (_currentWrong > 0) {
      return (
        color: AppTokens.danger,
        icon: AppGlyph.warning,
        text: '本题已答错 $_currentWrong 次',
      );
    }
    // 正确提示：完成且全程零错选，给出“一气呵成”的正向反馈（用户要求保持不变）。
    if (_isCurrentWordComplete) {
      return (
        color: AppTokens.success,
        icon: AppGlyph.allCorrect,
        text: '一气呵成 · 完美通过！',
      );
    }
    // 其余状态（正在作答且尚未出错）不提示。
    return (color: AppTokens.danger, icon: AppGlyph.warning, text: null);
  }

  ///
  /// 构建贴近底部安全区的候选与操作区。
  Widget _buildBottomControls(AppTokens tokens) {
      // Padding 在 SafeArea 已避开系统手势条后，再按 `bottomActionInset`
      // 那一档补一段底部留白，手指不会顶着屏幕最下沿去点候选词。
      //
      // 顶部不再留白：结果提示已移入白卡底部，白卡与候选区之间只剩正文滚动区
      // 底部那一段留白，避免两段留白叠加成“双倍间距”。
      return Padding(
      key: const Key('listening-meaning-bottom-controls'),
      padding: const EdgeInsets.fromLTRB(
        ListeningMeaningLayout.pageInset,
        AppSpace.p0,
        ListeningMeaningLayout.pageInset,
        ListeningMeaningLayout.bottomActionInset,
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
            // 整组过渡时长走 AppDuration 的 250 毫秒这一档，切换利落又不突兀。
            duration: const Duration(milliseconds: AppDuration.ms250),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            // 用当前四个候选文本拼接成唯一 Key；文本变化即触发整组过渡。
            child: Wrap(
              key: ValueKey(
                'listening-meaning-option-group-${_options.map((option) => option.text).join('|')}',
              ),
              spacing: ListeningMeaningLayout.optionGap,
              runSpacing: ListeningMeaningLayout.optionGap,
              // Wrap 不支持把同一行拉成等高，这里让矮的那张在行内垂直居中：
              // 某个候选换行变高时，旁边那张不会顶在上方显得歪。
              crossAxisAlignment: WrapCrossAlignment.center,
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
    final textTheme = Theme.of(context).textTheme;
    // 最后一题提交后会进入完成状态页，因此主操作使用“完成”语义。
    final isLastWord = _wordIndex + 1 >= widget.words.length;
      // Padding 与普通候选区共用相同的左右、顶部和安全区留白（顶部同为 0，
      // 间距只由正文滚动区底部那一段承担）。
      return Padding(
      key: const Key('listening-meaning-next-area'),
      padding: const EdgeInsets.fromLTRB(
        ListeningMeaningLayout.pageInset,
        AppSpace.p0,
        ListeningMeaningLayout.pageInset,
        ListeningMeaningLayout.bottomActionInset,
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
                icon: const Icon(AppGlyph.retry, size: AppIcon.i16),
                label: const Text('再试一次'),
                style: OutlinedButton.styleFrom(
                  // 底色、文字色、描边与圆角都继承主题里的次要按钮样式，
                  // 这里只写这一颗按钮特有的「贴满外层高度」。
                  minimumSize: const Size(
                    0,
                    ListeningMeaningLayout.actionHeight,
                  ),
                  padding: EdgeInsets.zero,
                  textStyle: textTheme.fs5Semibold,
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
                  isLastWord ? AppGlyph.finish : AppGlyph.nextQuestion,
                  size: AppIcon.i16,
                ),
                // 文案明确区分“继续答题”和“提交整轮”。
                label: Text(isLastWord ? '完成' : '下一题'),
                style: FilledButton.styleFrom(
                  // 蓝底白字与圆角来自主题里的主按钮样式，这里只写
                  // 「与左侧按钮保持同样的高度基准和无额外内边距」。
                  minimumSize: const Size(
                    0,
                    ListeningMeaningLayout.actionHeight,
                  ),
                  padding: EdgeInsets.zero,
                  textStyle: textTheme.fs5Semibold,
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
  Widget _buildDone() {
    // 完成屏版式已收进公共组件 ModuleSummaryView（四个模块同一套简单收尾：
    // 圆形图标 + 标题 + 一行说明 + 返回按钮），这里只填内容。
    return ModuleSummaryView(
      icon: AppGlyph.correct,
      color: AppTokens.success,
      title: '听音辨义完成',
      // 统计本轮总单词数与所有错选次数，重做不会抹去已经发生的错误。
      subtitle: '共 ${widget.words.length} 个单词 · 答错 $_errors 次',
      // 返回按钮把成功提交的单词 id 一并交回首页进行定向回刷。
      actionLabel: '返回',
      actionKey: const Key('finish-listeningMeaning'),
      onAction: _exitListeningMeaning,
    );
  }
}

///
/// 顶栏那个无文字图标按钮已经收进公共组件
/// `lib/widgets/module_scaffold.dart` 的 `ModuleIconButton`：原来本页和看义选词
/// 各有一个同名的私有 `_PlainIconButton`，随身听还有一个公开的
/// `ListeningIconButton`，三份实现做的是同一件事。
///
///
/// 候选词卡片：错选时触发左右抖动动画，配合触觉反馈传达错误感。
///
/// 动画时长走 AppDuration 的 250 毫秒这一档（收敛前写死 300），振幅从 ±8px
/// 衰减到 0，类似微信摇一摇的阻尼抖动。
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
  /// 驱动一次抖动过程的动画控制器。
  late final AnimationController _shakeController;

  ///
  /// 从零开始、经过正负位移并最终回到零的抖动曲线。
  late final Animation<double> _shakeAnimation;

  ///
  /// 初始化抖动动画控制器和位移序列。
  @override
  void initState() {
    super.initState();
    // 衰减抖动，类似物理阻尼效果。
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: AppDuration.ms250),
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
    final textTheme = Theme.of(context).textTheme;
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
          color: wrong
              ? AppTokens.danger.withValues(alpha: AppAlpha.a8)
              : tokens.card,
          borderRadius: BorderRadius.circular(
            ListeningMeaningLayout.optionCardRadius,
          ),
          child: InkWell(
            onTap: wrong ? null : widget.onTap,
            // 长按不参与答题判定，只打开刷新候选词确认框。
            onLongPress: widget.onLongPress,
            borderRadius: BorderRadius.circular(
              ListeningMeaningLayout.optionCardRadius,
            ),
            child: Container(
              // 高度只给下限：短候选词是 48 像素，长候选词换行后自动长高，
              // 卡片撑开而不是把多出来的那行文字裁掉。
              constraints: const BoxConstraints(
                minHeight: ListeningMeaningLayout.optionMinHeight,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ListeningMeaningLayout.optionHorizontalInset,
                vertical: AppSpace.p2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  ListeningMeaningLayout.optionCardRadius,
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
                      key: Key(
                        'listening-meaning-option-badge-${widget.index}',
                      ),
                      width: ListeningMeaningLayout.optionBadgeSize,
                      height: ListeningMeaningLayout.optionBadgeSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: wrong
                            ? AppTokens.danger.withValues(alpha: AppAlpha.a10)
                            : tokens.sub,
                        border: Border.all(
                          color: wrong ? AppTokens.danger : tokens.rowBorder,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.rounded),
                      ),
                      child: Text(
                        String.fromCharCode('A'.codeUnitAt(0) + widget.index),
                        // 序号取 12 号粗那一档：和候选词标签同字号，
                        // 但方块小，得靠字重压住。
                        style: textTheme.fs6Bold.copyWith(
                          color: wrong
                              ? AppTokens.danger
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    // 左侧让出序号方块的完整宽度，右侧只留和卡片内边距一样的呼吸空间，
                    // 省下来的宽度全给文字，能明显减少换行的次数。
                    padding: const EdgeInsets.only(
                      left:
                          ListeningMeaningLayout.optionBadgeSize +
                          ListeningMeaningLayout.optionHorizontalInset,
                      right: ListeningMeaningLayout.optionTextRightInset,
                    ),
                    child: _OptionLabel(
                      text: widget.option.text,
                      color: wrong ? AppTokens.danger : tokens.text,
                      labelKey: Key(
                        'listening-meaning-option-label-${widget.index}',
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

///
/// 候选词文本：一行放得下就用基准字号，需要换行时自动降 2 像素。
///
/// 生活化解释：短词按 14 像素正常显示；一旦这个词要折成两行，就把字缩到
/// 12 像素，两行加在一起的高度更矮，卡片也不会被撑得太厚。字只缩 2 像素，
/// 仍然看得清——不像以前那样为了塞进一行一路缩到几乎看不清。
class _OptionLabel extends StatelessWidget {
  ///
  /// 创建候选词文本。
  const _OptionLabel({
    required this.text,
    required this.color,
    required this.labelKey,
  });

  ///
  /// 候选词内容。
  final String text;

  ///
  /// 文字颜色（答错时是危险红）。
  final Color color;

  ///
  /// 传给内部 Text 的 key，供测试与定位使用。
  final Key labelKey;

  ///
  /// 按给定字号拼出候选词的文字样式。
  TextStyle _style(double fontSize) => TextStyle(
    color: color,
    fontSize: fontSize,
    // 读总表「紧凑单行」那一档：候选卡高度有限，行距收紧后两行仍装得进去，
    // 也不会因为行距过大把第三行挤出可视范围。
    height: AppLine.lhSm,
  );

  ///
  /// 判断这段文字在给定宽度下是否会被折行。
  ///
  /// 做法是拿一把“隐形的尺子”（TextPainter）先把文字按一行排一遍：
  /// 排不下就会被标记为超行，这时才需要降字号。
  bool _needsWrap(BuildContext context, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      // 跟随系统的字体缩放设置，避免开了大字体后判断失准。
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      // 与 Text 的默认断行策略保持一致。
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxWidth);
    // 一行之内排得下就是 false。
    return painter.didExceedMaxLines;
  }

  ///
  /// 构建候选词文本。
  @override
  Widget build(BuildContext context) {
    // LayoutBuilder 拿到父级真正给出的可用宽度，再决定用哪个字号。
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSize = ListeningMeaningLayout.optionTextSize;
        final baseStyle = _style(baseSize);
        // 需要换行就降 2 像素；否则保持基准字号。
        final fontSize = _needsWrap(context, baseStyle, constraints.maxWidth)
            ? baseSize - ListeningMeaningLayout.optionTextShrinkStep
            : baseSize;
        return Text(
          text,
          key: labelKey,
          textAlign: TextAlign.center,
          // 超过三行的极长文本才用省略号收尾。
          overflow: TextOverflow.ellipsis,
          maxLines: ListeningMeaningLayout.optionMaxLines,
          style: _style(fontSize),
        );
      },
    );
  }
}
