import '../../widgets/choice_option_grid.dart';
import 'dart:math' show max;
// dart:async 提供 unawaited，播放音频时不阻塞按钮响应。
import 'dart:async';
import '../../services/study_open_timing.dart';
// dart:math 用于打乱答案顺序和生成干扰项。
import '../../models/session_question.dart';
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
// 引入结算草稿模型。
import '../../models/settlement.dart';
import '../../models/session_record.dart';
// 引入音频播放接口。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入单词 Store：混淆词第一次生成后要回写到单词行 / 含义行。
import '../../store/word.dart';
// 引入独立候选项生成服务，页面只负责当前答题状态。
import '../review/services/session_progress.dart';
// 引入听音辨义页面集中管理的布局尺寸。
// 引入全站统一的二次确认对话框：长按刷新候选词时弹的就是它。
import '../../widgets/app_confirm_dialog.dart';
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
import '../../widgets/settlement_summary.dart';
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
  bool _isSavingAnswer = false;
  ListeningMeaningOption? _pendingChoice;

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

  ///
  /// 页面进入后已用毫秒数，用于右上角 mm:ss 计时。
  int _elapsedMs = 0;

  ///
  /// 每秒推进一次 [\_elapsedMs] 的定时器；退后台停表、回前台继续。
  Timer? _elapsedTimer;

  ///
  /// 当前拼写或释义步骤展示的四个候选项。
  ///
  /// 换小题时**不清空**这个列表。清空会让候选区整块塌成 0 高、白卡被顶下去，
  /// 等新候选读回来再长回原样——看起来就是「整个页面刷新了一遍」。
  /// 旧候选留在原位，新候选读回来后原地替换（四张卡不重建，只有文字交叉淡入）。
  List<ListeningMeaningOption> _options = const [];

  ///
  /// [\_options] 里这批候选属于哪一道小题；null 表示当前没有候选。
  ///
  /// 只在候选读取失败时用得上：屏幕上残留的候选如果属于上一道小题，
  /// 就必须清掉（留着会被点到当前小题头上，凭空记一次错）；属于本道小题
  /// 就原样留着，长按刷新失败不该把好好的候选一起弄没。
  int? _optionsQuestionId;

  ///
  /// 当前小题的候选是否还在读库。
  ///
  /// 新小题的混淆词要走一次 SQLite 生成与写回，这段时间里同步拿不到候选。
  /// 这段过渡期用本标记把候选卡片的点击挡掉——屏幕上还是上一小题的词。
  bool _optionsPending = false;

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

  ///
  /// 本局进度的落盘出口。
  SessionProgress get _progress => widget.progress;

  ///
  /// 单词 Store：混淆词回写走它。

  ///
  /// 当前单词的全部释义（摊平后的一维列表），只作听音辨义的抽题池。
  ///
  /// 听音辨义按「一条释义一小题」推进，所以这里要的是摊平结果而不是分组。
  /// 本模块「只能动词合并」：用 [Word.verbMergedMeanings]，模型只在动词词性内
  /// 去重、合并（vi./vt. 并成 `vi. vt.`），非动词相同中文保留为独立小题。这里不再整理。
  List<Meaning> get _availableMeanings => _currentWord.verbMergedMeanings;

  ///
  /// 初始化听音辨义页面并恢复可用的历史状态。
  @override
  void initState() {
    super.initState();
    StudyOpenTiming.of(_progress.session)?.mark('page_init');
    // 监听 App 前后台变化，后台停止音频并让下次播放重新提示 TTS。
    WidgetsBinding.instance.addObserver(this);
    // 继续模式先恢复小题下标、错误和候选顺序；新开始则保留默认字段。
    _restoreInitialSession();
    // 完成待提交态没有候选；普通状态若快照无合法候选则挂起点击等异步结果。
    if (_isCurrentWordComplete) {
      _options = const <ListeningMeaningOption>[];
      _optionsQuestionId = null;
      _optionsPending = false;
    } else if (!_restoredExactOptions) {
      _refreshOptions();
    }
    // 每次进入都覆盖同类型旧会话；新开始会保存本次新的单词列表。
    unawaited(_persistSession());
    // 首帧后并行读取候选缓存和自动发音；同步生成的选项保证等待 SQLite 时页面不空白。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final timing = StudyOpenTiming.of(_progress.session);
      timing?.pageFrame(context);
      if (!_optionsPending && (_options.isNotEmpty || _isCurrentWordComplete)) {
        timing?.controlsReady();
      }
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
    // 进入页面（或续玩回到题目）的这一刻，就是当前单词的起跑时间。
    // 累计错误由记录直接数出来：错完就退、退完再进，不能刷出一局「全对」。

    final wordId = _currentWord.id;
    if (wordId == null) return;
    final wordProgress = _progress.progressOf(wordId);
    // 本词累计错次先落地，**必须在下面任何一条 return 之前**。
    // 生活化解释：以前这一行写在最后，而「本词已经答完」那条分支会提前返回，
    // 于是错了几次的词退出去再进来，计数器归零，白卡底部就从「本题已答错 N 次」
    // 变成「一气呵成 · 完美通过！」——错过的记录还在库里，只是没人去数。
    // 现在不管从哪条分支返回，N 都已经还原好了。
    _currentWrong = wordProgress.wrongCount;
    if (wordProgress.spellingDone && _availableMeanings.isEmpty) {
      _isCurrentWordComplete = true;
      return;
    }

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
    // 注意这里只负责「哪几个候选要变红」，不再顺手把它的条数当成错次——
    // 那是当前小问的条数，而白卡底部要的是整词累计，两者只在第一个小问相等。
    final wrong = _stage == ListeningMeaningStage.word
        ? wordProgress.spellingWrongInputs
        : wordProgress.wrongInputsByMeaning[_availableMeanings[_meaningIndex]
                  .id] ??
              const <String>{};
    _wrongOptions.addAll(wrong);
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
  Future<void> _finishSession() =>
      _progress.finish(cursor: widget.words.length, elapsed: _elapsedSeconds);

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
  SessionSubQuestion? get _currentQuestion => _progress.questionFor(
    wordId: _currentWord.id,
    meaningId: _stage == ListeningMeaningStage.word
        ? null
        : _availableMeanings[_meaningIndex].id,
  );

  /// 已保存的选项可直接显示，未生成时等待共用服务成功落库。
  List<ListeningMeaningOption> _buildOptions() {
    final question = _currentQuestion;
    if (question == null) return const [];
    final cached = _progress.cachedOptionsFor(question);
    if (cached == null) return const [];
    return <ListeningMeaningOption>[
      for (final text in cached)
        ListeningMeaningOption(
          text: text,
          isCorrect: text == _currentCorrectAnswer,
        ),
    ];
  }

  ///
  /// 换小题时刷新候选区：同步拿得到就立刻换，拿不到就保留旧候选并挂起点击。
  ///
  /// [\_buildOptions] 读的是会话快照里的候选，新小题的混淆词还没落库时它只能是
  /// 空数组——而空数组会让整个候选区塌掉（见 [\_options] 的说明）。所以这里
  /// 宁可不换：同步空手而归就挂起点击，等 [\_restoreOrCreateCurrentConfusions]
  /// 把候选读回来原地替换。四个调用点（进入页面、拼写转释义、下一条含义、
  /// 换词与重做）都走这一个出口，行为不会各写各的。
  void _refreshOptions() {
    final next = _buildOptions();
    if (next.isNotEmpty) {
      _options = next;
      _optionsQuestionId = _currentQuestion?.id;
      _optionsPending = false;
      return;
    }
    _optionsPending = true;
  }

  Future<void> _restoreOrCreateCurrentConfusions({bool refresh = false}) async {
    final generation = ++_optionLoadGeneration;
    final question = _currentQuestion;
    if (question == null) return;
    try {
      final options = await _progress.optionsFor(question, refresh: refresh);
      if (!mounted || generation != _optionLoadGeneration) return;
      setState(() {
        // 候选到位：原地替换旧候选。四张卡保持同一个 element，只有卡里的
        // 文字交叉淡入，所以不会出现「整块从无到有」的刷新感。
        _options = <ListeningMeaningOption>[
          for (final text in options)
            ListeningMeaningOption(
              text: text,
              isCorrect: question.answers.contains(text),
            ),
        ];
        _optionsQuestionId = question.id;
        // 候选已就位，解除换小题期间的点击保护。
        _optionsPending = false;
      });
      StudyOpenTiming.of(_progress.session)?.controlsReady();
    } catch (error) {
      if (mounted && generation == _optionLoadGeneration) {
        setState(() {
          // 读不回来的这一道小题，如果和屏幕上残留的候选不是同一道，
          // 就必须清掉：留着会被点到当前小题头上，凭空记一次错。
          if (_optionsQuestionId != question.id) {
            _options = const <ListeningMeaningOption>[];
            _optionsQuestionId = null;
          }
          // 同一道小题的候选仍然有效（长按刷新失败就是这一种），原样留着。
          _optionsPending = false;
        });
        Toast.show(context, '候选保存失败：$error');
      }
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
      // 播音不附带任何提示：TTS 现在也是轮转队列的正常一员，轮到它出声并不代表
      // 网络坏了；只有 TTS 引擎本身不可用（下方专用异常）时才需要向用户说明。
    } on WordAudioTtsUnavailableException catch (error) {
      // 设备没有可用的离线英语 TTS（且网络发音未能成功兜住）时给出明确提示，
      // 不带“播放失败”前缀，直接展示原因，方便用户去装语音包或联网。
      if (mounted && generation == _playGeneration) {
        Toast.show(context, error.toString());
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
          // 重试成功同样静默结束，无需提示来源。
        } on WordAudioTtsUnavailableException catch (ttsError) {
          // 重试兜底到 TTS 但引擎不可用时，展示原因而不是“播放失败”前缀。
          if (mounted && generation == _playGeneration) {
            Toast.show(context, ttsError.toString());
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
  Future<void> _pickOption(ListeningMeaningOption option) async {
    // 当前单词完成后已经只能点击"下一题"，旧选项不再响应。
    if (_isDone ||
        _isSavingAnswer ||
        _optionsPending ||
        _optionsQuestionId != _currentQuestion?.id ||
        _isCurrentWordComplete ||
        _wrongOptions.contains(option.text)) {
      return;
    }
    setState(() {
      _isSavingAnswer = true;
      _pendingChoice = option;
    });
    if (option.isCorrect) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    try {
      // 点击立刻反馈，短动画与落盘同时进行；成功保存后才换题。
      await Future.wait<void>(<Future<void>>[
        _recordAnswer(input: option.text, isCorrect: option.isCorrect),
        if (option.isCorrect && !MediaQuery.disableAnimationsOf(context))
          Future<void>.delayed(const Duration(milliseconds: AppDuration.ms160)),
      ], eagerError: true);
    } catch (error) {
      if (mounted) Toast.show(context, '答案保存失败：$error');
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingAnswer = false;
          _pendingChoice = null;
        });
      }
    }
    if (!mounted) return;
    if (!option.isCorrect) {
      // 重震动传达错误感，无需音效也能感知。
      setState(() {
        _wrongOptions.add(option.text);
        // 整轮错误统计供完成状态页展示，不会因重做当前单词而回退。
        // 当前单词的选错次数同步累加，用于落 record。
        _currentWrong++;
      });
      // 记一条「点错了」：现场恢复靠它把候选置灰，结算也靠它判定这一轮答错。

      // 保存错项文本与错误计数，重新进入后不能通过退出页面清除错误。
      unawaited(_persistSession());
      return;
    }

    // 轻触震动确认选对，不拖延答题节奏。
    // 答对同样留痕：重进时靠它判断「拼写那步过了没有、答到第几条释义」。
    // 必须在下面切换阶段之前记，否则会记到下一小题头上。

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
        // 不在这里清空候选：清空会让底部整块塌掉，看起来像页面刷新。
        _refreshOptions();
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
      // 同上：旧含义的候选留在原位，新含义的候选读回来原地替换。
      _refreshOptions();
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
    await _progress.record(
      wordId: wordId,
      meaningId: meaningId,
      input: input,
      isCorrect: isCorrect,
      elapsed: _elapsedSeconds,
    );
  }

  ///
  /// 长按候选项后询问是否刷新；确认后保持四选一结构并立即替换当前文本。
  Future<void> _requestOptionRefresh(int optionIndex) async {
    if (_isDone ||
        _isCurrentWordComplete ||
        _isSavingAnswer ||
        _optionsPending ||
        optionIndex >= _options.length) {
      return;
    }
    final confirmed = await _showOptionRefreshDialog(
      _options[optionIndex].text,
    );
    if (!confirmed || !mounted || _isCurrentWordComplete) return;
    // 刷新后仍统一排序，不能把正确答案人为挪到一个随机按钮上。
    await _restoreOrCreateCurrentConfusions(refresh: true);
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
      // 完成后不再保留可点击选项数据；这是**有意**收起候选区
      // （底部要换成「再试一次 / 下一题」两颗按钮），和换小题时的
      // 「不该塌却塌了」不是一回事。
      _options = const <ListeningMeaningOption>[];
      _optionsQuestionId = null;
      _optionsPending = false;
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
    // 用户点击下一题或结算页按钮后必须等事务结束；保存中主动返回会让首页
    // 漏掉最新回刷 id，也可能让结算草稿来不及落盘。
    if (_isSavingCompletion) return;
    if (_isDone) {
      if (mounted) setState(() => _isSavingCompletion = true);
      unawaited(
        widget.progress
            .commitSettlement()
            .then((_) {
              if (!mounted) return;
              Navigator.pop(context, _reviewedWordIds.toList());
            })
            .catchError((Object error) {
              debugPrint('提交听音辨义结算失败：$error');
              if (mounted) {
                setState(() => _isSavingCompletion = false);
                Toast.show(context, '保存结算失败，请重试：$error');
              }
            }),
      );
      return;
    }
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
      // 会话完成和全部草稿都保存成功，才能显示可调整的结算页。
      // 失败时保留当前题与完成按钮，用户可以再次提交同一份结果。
      try {
        await _finishSession();
      } catch (error) {
        if (mounted) {
          setState(() => _isSavingCompletion = false);
          Toast.show(context, '保存结算失败，请重试：$error');
        }
        return;
      }
      if (!mounted) return;
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
      // 根据新的 _wordIndex 换候选；同步拿不到就保留旧候选并挂起点击。
      _refreshOptions();
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
  Future<void> _retryCurrentWord() async {
    // 只有当前题处于"已完成"状态时才会出现这个按钮，其余情况忽略调用。
    if (!_isCurrentWordComplete || _isDone || _isSavingCompletion) return;
    _isSavingCompletion = true;
    try {
      await _progress.retryWord(_currentWord.id!);
    } catch (error) {
      if (mounted) Toast.show(context, '重试保存失败：$error');
      return;
    } finally {
      _isSavingCompletion = false;
    }
    if (!mounted) return;

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
      // 重新换当前单词的拼写候选；同步拿不到就挂起点击等异步结果。
      _refreshOptions();
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
    // 这里**绝对不能再按释义文字去重**（历史上有一个 `shown` 集合）。
    // steps 的下标就是本页 `_meaningIndex` 的坐标系，而 `_meaningIndex` 走的
    // `_availableMeanings`（即 [Word.verbMergedMeanings]）只在动词词性内部合并，
    // 非动词的同一句中文一律保留成独立小题。这里多去一次重，steps 就比
    // `_availableMeanings` 少一格，此后每一格整体错位——光标停在后一条含义上、
    // 答对时揭开的是下一条，最后一条含义永远揭不开，槽位数也凭空少一个。
    // 真实例子：close 的 `v. 接近` 与 `adv. 接近` 文字相同，`adv.` 行就只剩
    // 「靠近 / 紧挨着」两个槽位，而实际要答三条。
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
    StudyOpenTiming.of(_progress.session)?.cancel('page_closed');
    _progress.detach();
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
      canPop: !_isSavingCompletion && !_isDone,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isDone) _exitListeningMeaning();
      },
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
  Widget _buildBottomControls(AppTokens tokens) => ChoiceOptionGrid(
    options: _options.map((option) => option.text).toList(),
    // 以屏幕上这份候选所属的小题为准，等新候选实际显示时才开始换题防连点。
    questionKey: _optionsQuestionId ?? (_wordIndex, _stage, _meaningIndex),
    keyPrefix: 'listening-meaning-option',
    // 字号不在这里指定：候选卡的 14 号半粗是全站统一口径，写死在
    // ChoiceOptionGrid 里，听音辨义和看义选词长得一模一样。
    wrong: <String>{
      ..._wrongOptions,
      if (_pendingChoice?.isCorrect == false) _pendingChoice!.text,
    },
    correct: <String>{
      if (_pendingChoice?.isCorrect == true) _pendingChoice!.text,
    },
    // 候选还在读库时一律不接受点击：屏幕上那四个词属于上一小题，
    // 点下去会记到当前小题头上。
    enabled: !_isSavingAnswer && !_optionsPending,
    onTap: (text) =>
        _pickOption(_options.firstWhere((option) => option.text == text)),
    onLongPress: (text) => _requestOptionRefresh(
      _options.indexWhere((option) => option.text == text),
    ),
  );

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
    final items = <SettlementWordItem>[
      for (final word in widget.words)
        if (word.id != null)
          _settlementItem(word, widget.progress.settlementFor(word.id!)),
    ];
    return SettlementSummary(
      key: const Key('settlement-listeningMeaning'),
      items: items,
      isBusy: _isSavingCompletion,
      // 结算页顶部用所有单词明细的实际用时汇总；右上角仍显示页面停留时间。
      aggregatedWordElapsed: Duration(
        seconds: items.fold<int>(
          0,
          (sum, item) => sum + (item.usedTime?.inSeconds ?? 0),
        ),
      ),
      onAdjust: (index, adjust) async {
        final id = widget.words[index].id;
        if (id != null) await widget.progress.adjustSettlement(id, adjust);
      },
      onRetry: () {
        if (_isSavingCompletion) return;
        setState(() => _isSavingCompletion = true);
        unawaited(
          widget.progress
              .commitSettlement()
              .then((_) {
                if (mounted) Navigator.pop(context, true);
              })
              .catchError((Object error) {
                debugPrint('提交听音辨义结算失败：$error');
                if (mounted) {
                  setState(() => _isSavingCompletion = false);
                  Toast.show(context, '保存结算失败，请重试：$error');
                }
              }),
        );
      },
      onConfirm: _exitListeningMeaning,
    );
  }

  /// 把结算草稿转换成公共结算组件的一行展示数据。
  SettlementWordItem _settlementItem(Word word, SettlementDraft? draft) {
    final value = draft;
    final isCorrect = value?.isCorrect ?? !_progressOf(word.id!).hasAnyWrong;
    return SettlementWordItem(
      word: word.spelling,
      isCorrect: isCorrect,
      usedTime: Duration(seconds: value?.usedTimeSeconds ?? 0),
      // 本轮开始时的难度：草稿里记着就用草稿的，拿不到就退回到单词当前的难度。
      difficultyBefore: value?.difficultyBefore ?? word.difficulty,
      recentResults:
          value?.recentResults ?? <bool?>[isCorrect, null, null, null, null],
      streak: value != null && value.streak > 0 ? value.streak : null,
      initialAdjust: difficultyAdjustFromDelta(value?.suggestedAdjustment ?? 0),
    );
  }

  WordProgress _progressOf(int wordId) => widget.progress.progressOf(wordId);
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
