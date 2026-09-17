import '../../widgets/question_content_transition.dart';
import '../../widgets/choice_option_grid.dart';
import '../../common/toast.dart';
// dart:async 提供 Timer，用于结算页展示本局用时。
import 'dart:async';
// dart:math 提供 max，读取快照时防止负数进度。
import 'dart:math';

// material.dart 提供全屏页面、进度条、卡片与按钮。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// 所有可见图标继续统一使用 Tabler。

// 引入应用设计令牌。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角时间超过一小时改用 hh:mm:ss，不足用 mm:ss。
import '../../common/date.dart';
// 引入单词模型。
import '../../models/word.dart';
import '../../models/settlement.dart';
// 引入音频播放接口：点击候选词或已答出的单词时朗读。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入全 App 共用的「下划线字母格」，与拼写巩固是同一个组件。
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
import '../../widgets/settlement_summary.dart';
import '../../widgets/answer_slots.dart';
// 引入复习模块共用的进度出口：负责把快照落进今天的会话。
import '../review/services/session_progress.dart';
// 引入含义序列与候选词构建服务。
import 'services/meaning_word_choice_round_builder.dart';
// 引入看义选词页面集中管理的布局尺寸。
import 'widgets/meaning_word_choice_layout.dart';

///
/// 只有 ASCII 英文字母才占一格下划线；撇号、连字符、空格由答案槽位当静态
/// 字符直接显示。判定规则与答案槽位组件同一处。
bool _isLetter(String character) => AnswerSlots.isLetter(character);

///
/// 全屏看义选词页面。
///
/// 玩法（白卡版，视觉与听音辨义、拼写巩固同源）：
/// 1. 正文是一张白卡，卡内内容垂直居中，从上到下依次是
///    「选择对应的单词」标签、中文释义大字、`词性 | 释义` 说明行、
///    与拼写巩固同款的下划线字母格、底部提示；
/// 2. 点错 → 该候选词禁用置灰（本题继续）；点对 → 对应那组字母格
///    一次填入整个单词并转绿；
/// 3. 一个含义可能匹配多个单词，因此字母格会排成多组，全部填满才进入下一含义；
/// 4. 全部含义走完 → 结算页。
///
/// 会话进度以 state_json 快照保存（会话表既有机制），续玩时完整恢复现场。
///
class MeaningWordChoicePage extends StatefulWidget {
  ///
  /// 创建看义选词页面。
  const MeaningWordChoicePage({
    required this.words,
    required this.title,
    required this.progress,
    required this.audioPlayer,
    required this.accent,
    super.key,
  }) : assert(words.length > 0, '看义选词至少需要一个单词');

  ///
  /// 首页按会话顺序传入的本局单词。
  final List<Word> words;

  ///
  /// 当前复习模块名称；顶栏中央显示数字进度，此处仅作语义标识。
  final String title;

  ///
  /// 本局的进度出口，由首页的 ReviewFlow 判定后传入。
  ///
  /// 它同时决定三件事：进度存到哪一局、每次点击记到哪一局，
  /// 以及答题要不要推进单词的复习时间（巩固局不推进）。
  final SessionProgress progress;

  ///
  /// 与首页、随身听共用的发音服务：点击候选词或单词气泡时朗读。
  final WordAudioPlayer audioPlayer;

  ///
  /// 当前发音口音。
  final PronunciationAccent accent;

  @override
  State<MeaningWordChoicePage> createState() => _MeaningWordChoicePageState();
}

// 实现 WidgetsBindingObserver 以监听 App 前后台切换，退后台时落盘进度。
class _MeaningWordChoicePageState extends State<MeaningWordChoicePage>
    with WidgetsBindingObserver {
  ///
  /// 本局进度的落盘出口。
  SessionProgress get _progress => widget.progress;

  ///
  /// 记录 Store；正式环境用全局 SQLite 实现，测试可注入内存实现。
  ///
  /// 按单词主键反查拼写与模型；开局构建一次，恢复与渲染都用它。
  late final Map<int, Word> _wordsById;

  /// 打乱后的全部含义序列（答题顺序，开局生成后不再变化）。
  List<MeaningWordChoiceRound> _rounds = const <MeaningWordChoiceRound>[];

  /// 当前轮下标；进度条与数字进度都按它计算。
  int _roundIndex = 0;

  /// 当前轮的候选词列表（含正确答案与干扰项）。
  List<MeaningWordChoiceCandidate> _candidates =
      const <MeaningWordChoiceCandidate>[];

  /// 当前轮已正确选出的单词主键；对应按钮从候选区移除。
  Set<int> _pickedIds = <int>{};

  /// 当前轮被点错禁用的单词主键；对应按钮置灰不可再点。
  Set<int> _disabledIds = <int>{};

  /// 每轮答错次数（下标对齐 [_rounds]），结算页副标题判断「是否全对」用。
  List<int> _roundWrongCounts = <int>[];

  /// 本局累计用时（毫秒），结算页展示用。
  int _elapsedMs = 0;

  /// 是否已把全部含义走完一遍（进入结算页）。
  bool _completed = false;
  bool _savingAnswer = false;
  MeaningWordChoiceCandidate? _pendingChoice;
  int _candidateGeneration = 0;

  /// 新一轮的候选词是否还在读库。
  ///
  /// 换轮时不再先把候选区清空——那一清一填会让底部整块塌成 0 高再长回来，
  /// 上方的白卡跟着被顶上去又压下来，看起来就像「整块元素被显示/隐藏」。
  /// 现在旧候选留在原地，等新的读回来直接原地替换（文字交叉淡入），
  /// 这一段过渡期用这个标记把点击挡掉，免得误判成上一轮的答案。
  bool _candidatesPending = false;

  /// 结算草稿正在提交时锁住离开入口，避免重复应用难度。
  bool _isCommittingSummary = false;

  /// 计时器：每秒把用时累加 1 秒。
  Timer? _elapsedTimer;

  /// 本轮答完后延迟切题的定时器；离场时必须取消，否则会对已销毁页面 setState。
  Timer? _advanceTimer;

  /// 本轮每个已答出单词的入场编号；字母格靠它决定要不要重播填入动画。
  ///
  /// 只在「用户当场点对」时写入，续玩恢复出来的已答词不写，
  /// 这样重进页面不会把动画再放一遍。
  final Map<int, int> _revealTokens = <int, int>{};

  /// 入场编号发号器，保证每次填入都是一张全新的「电影票」。
  int _revealSeq = 0;

  ///
  /// 当前轮是否已把全部匹配词选出。
  bool get _currentRoundDone =>
      _roundIndex < _rounds.length &&
      _rounds[_roundIndex].matchIds.every(_pickedIds.contains);

  ///
  /// 全部含义是否已走完。
  bool get _allRoundsDone => _roundIndex >= _rounds.length;

  ///
  /// 顶栏显示的题号：结算时显示总题数，答题时显示当前轮。
  int get _displayRound =>
      _completed || _allRoundsDone ? _rounds.length : _roundIndex + 1;

  ///
  /// 页面初始化：接进度出口、恢复历史快照或开一局新的。
  @override
  void initState() {
    super.initState();
    // 注册生命周期监听，退后台时保存进度。
    WidgetsBinding.instance.addObserver(this);
    // 建立单词主键索引，后续按 id 反查拼写。
    _wordsById = <int, Word>{
      for (final word in widget.words)
        if (word.id != null) word.id!: word,
    };
    // 答题序列直接来自会话的数据列表，现场由点击记录回放得出。
    _restoreProgress();
    if (_progress.allRecords.isEmpty) {
      // 全新一局：从第一轮开始。
      _startRound(0);
      // 新局也必须从进入页面开始累计用时；此前只有续玩路径启动了计时器。
      _startElapsedTimer();
    } else {
      // 续玩：直接进入恢复出的当前轮，已答出的词会以填好的字母格呈现。
      if (!_completed && !_allRoundsDone) {
        _startRound(_roundIndex, resume: true);
        _startElapsedTimer();
      }
    }
    // 首次进入也要落一次进度：用户立刻退出时首页才能显示「进行中」。
    unawaited(_persist());
  }

  /// ===== 会话恢复 =====

  ///
  /// 从会话与点击记录恢复本局进度。
  ///
  /// 2.0 起答题序列不再存快照，而是由会话的**数据列表**（一串含义主键）
  /// 直接还原；「哪些轮已经答完、当前这轮点错过哪些候选」则回放点击记录得出。
  /// 这样就不存在「快照结构变了旧数据没法恢复」的问题。
  void _restoreProgress() {
    _rounds = MeaningWordChoiceRoundBuilder.buildSessionRounds(
      _progress.session,
      widget.words,
    );
    _roundWrongCounts = List<int>.filled(_rounds.length, 0);
    _elapsedMs = _progress.session.elapsed * 1000;
    var firstIncomplete = _rounds.length;
    for (var index = 0; index < _rounds.length; index++) {
      final round = _rounds[index];
      final records = _progress.allRecords.where(
        (record) => record.questionId == round.questionId,
      );
      _roundWrongCounts[index] = records
          .where((record) => !record.isCorrect)
          .length;
      final picked = records
          .where((record) => record.isCorrect)
          .expand((record) => record.answers)
          .map((text) => text.trim().toLowerCase())
          .toSet();
      final complete = round.matchIds.every(
        (id) => picked.contains(_wordsById[id]!.spelling.trim().toLowerCase()),
      );
      if (!complete && firstIncomplete == _rounds.length) {
        firstIncomplete = index;
      }
    }
    _roundIndex = firstIncomplete;
    if (_allRoundsDone) unawaited(_completeSession());
  }

  /// ===== 轮次推进 =====

  ///
  /// 开始第 [index] 轮：清空现场并生成候选词。
  ///
  /// 白卡版不再有「正在输入」的假动画，释义与候选词同时露出；换题时白卡
  /// 自己会淡入上移（见 [_buildQuestionCard]），节奏与听音辨义一致。
  Future<void> _startRound(int index, {bool resume = false}) async {
    if (index >= _rounds.length) {
      await _completeSession();
      return;
    }
    final generation = ++_candidateGeneration;
    setState(() {
      // 刻意不清空 _candidates：旧候选留在原位，等下面读回新的再原地替换，
      // 底部区域的高度全程不变，上方白卡不会被顶来顶去。
      _candidatesPending = true;
    });
    final round = _rounds[index];
    final question = _progress.questionFor(questionId: round.questionId);
    if (question == null) {
      // 题目对不上（数据异常）时立刻解开点击保护，不能把整页锁在旧候选上。
      setState(() => _candidatesPending = false);
      return;
    }
    try {
      final options = await _progress.optionsFor(question);
      if (!mounted || generation != _candidateGeneration) return;
      final candidates = <MeaningWordChoiceCandidate>[];
      for (var i = 0; i < options.length; i++) {
        final text = options[i];
        final matches = round.matchIds.where(
          (id) =>
              _wordsById[id]!.spelling.trim().toLowerCase() ==
              text.trim().toLowerCase(),
        );
        candidates.add(
          MeaningWordChoiceCandidate(
            wordId: matches.isEmpty ? -i - 1 : matches.first,
            spelling: text,
            isMatch: matches.isNotEmpty,
          ),
        );
      }
      final records = _progress.allRecords.where(
        (record) => record.questionId == question.id,
      );
      setState(() {
        _roundIndex = index;
        _pickedIds = <int>{};
        _disabledIds = <int>{};
        _revealTokens.clear();
        _candidates = candidates;
        // 新一轮候选就位，解除点击保护；这一步和 _candidates 在同一次 setState
        // 里完成，界面不会出现「已换词但仍点不动」的中间态。
        _candidatesPending = false;
        for (final record in records) {
          for (final candidate in candidates) {
            if (!record.answers.any(
              (text) =>
                  text.trim().toLowerCase() ==
                  candidate.spelling.trim().toLowerCase(),
            )) {
              continue;
            }
            if (record.isCorrect) {
              _pickedIds.add(candidate.wordId);
            } else {
              _disabledIds.add(candidate.wordId);
            }
          }
        }
      });
      await _persist();
    } catch (error) {
      // 读候选失败时也要解开保护，否则整页会卡死在「点不动的旧候选」上。
      if (mounted) {
        setState(() => _candidatesPending = false);
        Toast.show(context, '下一题准备失败，返回后可继续：$error');
      }
    }
  }

  ///
  /// 本轮答完后延迟切到下一轮，让刚填入的单词在屏幕上停留一下。
  void _scheduleNextRound() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(
      const Duration(milliseconds: MeaningWordChoiceLayout.roundAdvanceDelayMs),
      () {
        if (!mounted) return;
        _startRound(_roundIndex + 1);
      },
    );
  }

  ///
  /// 用户点选一个候选词。
  Future<void> _onCandidateTap(int wordId) async {
    // 已禁用或已选出的词不应再被点击。
    if (_disabledIds.contains(wordId) || _pickedIds.contains(wordId)) return;
    // 新一轮候选还在读库：屏幕上是上一轮的词，这一小段不接受点击。
    if (_candidatesPending) return;
    if (_completed || _savingAnswer) return;
    // 本轮已答完、正在等切题的这段空档里不再接受点击，
    // 否则用户还能在这 800 毫秒里点中干扰词、白记一次失误。
    if (_currentRoundDone) return;

    // 在候选列表里找到这个词，判断是否正确答案。
    MeaningWordChoiceCandidate? candidate;
    for (final item in _candidates) {
      if (item.wordId == wordId) {
        candidate = item;
        break;
      }
    }
    // 候选词来自旧快照但会话里已不存在：忽略点击。
    if (candidate == null) return;

    // 点击候选词立即朗读一次，无论对错都让用户听到这个词。
    final spelling = candidate.spelling;
    if (spelling.isNotEmpty) unawaited(_playWordAudio(spelling));

    setState(() {
      _savingAnswer = true;
      _pendingChoice = candidate;
    });
    if (candidate.isMatch) HapticFeedback.lightImpact();
    try {
      await _recordPick(
        wordId: wordId,
        spelling: spelling,
        isCorrect: candidate.isMatch,
      );
    } catch (error) {
      if (mounted) Toast.show(context, '答案保存失败：$error');
      return;
    } finally {
      if (mounted) {
        setState(() {
          _savingAnswer = false;
          _pendingChoice = null;
        });
      }
    }
    if (!mounted) return;
    if (candidate.isMatch) {
      // 答对：先给一个轻震动反馈（和听音辨义一致），
      // 再给这个词发一张入场票，让它那组字母格把整词填进去。
      setState(() {
        _pickedIds.add(wordId);
        _revealTokens[wordId] = _revealSeq += 1;
      });
      // 先记这一次「选对了」，现场恢复靠它判断这一轮答到哪了。

      // 该含义的全部匹配词都选出后立即结算。
      // 这一轮只写点击记录；所有含义都做完后再统一准备单词结算，
      // 避免多义词在第一条含义完成时提前降难度。
      // 这一轮全部选对后，稍作停顿再进下一轮：让用户看清刚填进去的单词。
      if (_currentRoundDone) {
        _scheduleNextRound();
      } else {
        unawaited(_persist());
      }
    } else {
      // 答错：该候选词禁用置灰，错误数累计。
      setState(() {
        _disabledIds.add(wordId);
        _roundWrongCounts[_roundIndex] += 1;
      });
      // 记一条「点错了」：重进时靠它把这个候选继续置灰，
      // 结算也靠它判定这一轮该不该加难度。

      unawaited(_persist());
    }
  }

  ///
  /// 记一次候选点击，不论对错。
  ///
  /// [wordId] 是被点的那个候选单词；含义主键取当前这一轮的代表含义，
  /// 重进时按它把记录对回具体某一道题。
  Future<void> _recordPick({
    required int wordId,
    required String spelling,
    required bool isCorrect,
  }) async {
    // 越界说明这一局已经走完，不该再产生记录。
    if (_roundIndex >= _rounds.length) return;
    await _progress.record(
      wordId: _rounds[_roundIndex].matchIds.first,
      questionId: _rounds[_roundIndex].questionId,
      input: spelling,
      isCorrect: isCorrect,
      elapsed: _elapsedSeconds,
    );
  }

  ///
  /// 播放一个单词的发音；失败静默，不打断答题。
  Future<void> _playWordAudio(String spelling) async {
    try {
      // 与听音辨义同源的随机渠道朗读，失败时内部会兜底到其他渠道。
      await widget.audioPlayer.playRandomChannel(spelling, widget.accent);
    } catch (error) {
      // 网络或缓存异常都不影响答题流程，这里只记录不打扰用户。
      debugPrint('播放看义选词发音失败：$error');
    }
  }

  ///
  ///
  /// 全部含义走完：停表、标记完成并结算这一局。
  Future<void> _completeSession() async {
    // 整局已经结束，彻底停表，避免结算页期间定时器继续空转。
    _stopElapsedTimer();
    // 只有全部含义都完成后才准备单词结算；多义词因此不会被提前奖励。
    await _progress.finish(cursor: _rounds.length, elapsed: _elapsedSeconds);
    if (mounted) setState(() => _completed = true);
  }

  /// ===== 持久化 =====

  ///
  /// 把当前进度写入 SQLite；页面交互先完成，持久化失败不阻断答题。
  ///
  /// 2.0 起只写两个数：答到第几轮、已经花了多少秒。剩下的现场（题序、
  /// 候选词、点错过谁）要么由数据列表固定、要么由点击记录反查，
  /// 不再需要维护一份会随结构变动而失效的快照。
  Future<void> _persist() async {
    // 已结算的局不能再被 dispose 时的延迟保存写回「进行中」。
    if (_completed) return;
    await _progress.save(cursor: _roundIndex, elapsed: _elapsedSeconds);
  }

  ///
  /// 本局已用秒数。
  int get _elapsedSeconds => (_elapsedMs ~/ 1000).clamp(0, 1 << 30);

  /// ===== 生命周期 =====

  ///
  /// App 前后台切换：退后台停表并保存，回前台继续计时。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_completed && !_allRoundsDone) _startElapsedTimer();
      return;
    }
    _stopElapsedTimer();
    if (!_completed) unawaited(_persist());
  }

  @override
  void dispose() {
    _progress.detach();
    _candidateGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _advanceTimer?.cancel();
    _stopElapsedTimer();
    // 停表并保存当前进度；completed 也会在此落盘（首页据此显示状态）。
    unawaited(_persist());
    super.dispose();
  }

  ///
  /// 开始计时；已运行时保持原样。
  void _startElapsedTimer() {
    if (_completed || _allRoundsDone || _elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _completed) return;
      setState(() => _elapsedMs += 1000);
    });
  }

  /// 停止并清空计时器引用，保证回到前台时可以重新启动。
  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  /// 页面开始离场时立即停表，避免转场动画期间继续累加本局用时。
  @override
  void deactivate() {
    _stopElapsedTimer();
    super.deactivate();
  }

  /// 页面被重新挂回树时恢复计时，兼容返回手势取消等临时离场场景。
  @override
  void activate() {
    super.activate();
    if (!_completed && !_allRoundsDone) _startElapsedTimer();
  }

  /// ===== 构建 =====

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 进度 = 已进入的轮数 ÷ 总轮数；与听音辨义口径一致。
    final progress = (_displayRound - 1) / max(_rounds.length, 1);

    // 上、中、下三段全部交给模块模板排版，四个复习模块顶栏因此严丝合缝。
    return ModuleScaffold(
      canPop: !_completed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _completed) unawaited(_leaveSummary());
      },
      header: ModuleHeader(
        leading: ModuleIconButton(
          key: const Key('close-meaningWordChoice'),
          icon: AppGlyph.back,
          alignment: Alignment.centerLeft,
          onTap: _leaveSummary,
        ),
        title: ModuleProgressLabel(
          textKey: const Key('meaning-word-choice-progress-label'),
          current: _displayRound,
          total: _rounds.length,
        ),
        trailing: ModuleTimeLabel(
          textKey: const Key('meaning-word-choice-elapsed'),
          text: _formatElapsed(),
        ),
        progress: progress,
        progressBarKey: const Key('meaning-word-choice-progress-bar'),
      ),
      // 中段：练完是结算页，练习中是正文白卡。
      body: _completed
          ? _buildSummary(tokens)
          : _allRoundsDone
          ? const Center(child: CircularProgressIndicator())
          : _buildQuestionCard(tokens),
      // 下段：候选词区（文档流，一行两个）；结算页没有这一段。
      footer: _completed ? null : _buildCandidates(tokens),
    );
  }

  ///
  /// 构建正文白卡。
  ///
  /// 结构与听音辨义题目卡同源：白卡浮在页面底色上，卡内内容垂直居中，
  /// 从上到下是「标签 → 中文释义大字 → `词性 | 释义` 说明 → 下划线字母格
  /// → 底部提示」。矮屏或系统大字号下白卡内容可滚动，不会溢出。
  Widget _buildQuestionCard(AppTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    final round = _rounds[_roundIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MeaningWordChoiceLayout.pageInset,
        MeaningWordChoiceLayout.bodyVerticalInset,
        MeaningWordChoiceLayout.pageInset,
        MeaningWordChoiceLayout.bodyVerticalInset,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('meaning-word-choice-question-scroll'),
          child: ConstrainedBox(
            // 空间够时白卡撑满正文区；内容更高时白卡自然变高并允许滚动。
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            // 白卡本体**不参与换题动画**：它的位置、描边、底色换一题都不会变，
            // 让它整张从全透明淡入（原来的做法）看起来就是「页面刷新了一下」。
            // 换题时留在原地的只有卡里的文字，所以变化的也只是文字本身。
            child: Container(
              key: const Key('meaning-word-choice-question-card'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: MeaningWordChoiceLayout.bodyCardPaddingHorizontal,
                vertical: MeaningWordChoiceLayout.bodyCardPaddingVertical,
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
                  MeaningWordChoiceLayout.bodyCardRadius,
                ),
              ),
              child: Center(
                child: QuestionContentTransition(
                  contentKey: round.questionId ?? _roundIndex,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTag(),
                      const SizedBox(
                        height: MeaningWordChoiceLayout.definitionTop,
                      ),
                      // 中文释义大字：本页唯一的视觉焦点。
                      Text(
                        round.definition,
                        key: const Key('meaning-word-choice-definition'),
                        textAlign: TextAlign.center,
                        maxLines: MeaningWordChoiceLayout.definitionMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.fs1Bold.copyWith(
                          // 读总表「会换行的标题与大字」那一档：这是全站最大的
                          // 一档字号，按正文行距排会一行一行散开。
                          height: AppLine.lhSm,
                        ),
                      ),
                      const SizedBox(
                        height: MeaningWordChoiceLayout.posLineTop,
                      ),
                      _buildPosLine(tokens, round),
                      const SizedBox(height: MeaningWordChoiceLayout.slotsTop),
                      _buildAnswerSlots(round),
                      const SizedBox(height: MeaningWordChoiceLayout.hintTop),
                      Text(
                        '选错的选项将被禁用，直到选中正确答案',
                        key: const Key('meaning-word-choice-hint'),
                        textAlign: TextAlign.center,
                        style: textTheme.fs6.copyWith(color: tokens.muted),
                      ),
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

  ///
  /// 构建卡片顶部的「选择对应的单词」标签。
  ///
  /// 用品牌蓝的一成淡底，弱于下方的释义大字，只负责说明这一题要做什么。
  Widget _buildTag() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('meaning-word-choice-tag'),
      padding: const EdgeInsets.symmetric(
        horizontal: MeaningWordChoiceLayout.tagPaddingHorizontal,
        vertical: MeaningWordChoiceLayout.tagPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: AppTokens.primary.withValues(alpha: AppAlpha.a10),
        borderRadius: BorderRadius.circular(MeaningWordChoiceLayout.tagRadius),
      ),
      child: Text(
        '选择对应的单词',
        style: textTheme.fs6Semibold.copyWith(color: AppTokens.primary),
      ),
    );
  }

  ///
  /// 构建「词性 | 释义」说明行。
  ///
  /// 「释义」两字是固定文案，变的只有前面的词性；同一句中文挂在多个词性下时
  /// （如 eat 的 vi. 与 vt.）用斜杠并列。词库里没填词性的含义，`displayPos`
  /// 已经给出星号，这里照原样显示成 `* | 释义`，与词性及含义面板的口径一致。
  Widget _buildPosLine(AppTokens tokens, MeaningWordChoiceRound round) {
    final textTheme = Theme.of(context).textTheme;
    final joined = round.posGroup
        .where((pos) => pos.trim().isNotEmpty)
        .join('/');
    // 理论上 displayPos 至少给一个星号；这里再兜一层，绝不出现空标签。
    final posText = joined.isEmpty ? '*' : joined;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: posText,
            style: const TextStyle(
              color: AppTokens.primary,
              fontWeight: AppWeight.semibold,
              fontFamily: 'monospace',
            ),
          ),
          TextSpan(
            text: ' | ',
            style: TextStyle(color: tokens.check),
          ),
          const TextSpan(text: '释义'),
        ],
      ),
      key: const Key('meaning-word-choice-pos-line'),
      textAlign: TextAlign.center,
      style: textTheme.fs5.copyWith(color: tokens.textSecondary),
    );
  }

  ///
  /// 构建下划线字母格区：一条释义对应几个单词，就排几组字母格。
  ///
  /// 字母格用的是拼写巩固同一个组件（`lib/widgets/answer_slots.dart`），
  /// 所以两个模块的「填空」观感完全一致：这边不用键盘敲，选中正确候选后
  /// 整个单词一次填入并转绿，字母按顺序依次弹出。
  ///
  /// 排列顺序按拼写字母升序固定，闪烁光标落在第一个还没答出来的那组上。
  Widget _buildAnswerSlots(MeaningWordChoiceRound round) {
    final ordered = <int>[...round.matchIds]
      ..sort((first, second) {
        final bySpelling = (_wordsById[first]?.spelling ?? '')
            .toLowerCase()
            .compareTo((_wordsById[second]?.spelling ?? '').toLowerCase());
        return bySpelling != 0 ? bySpelling : first.compareTo(second);
      });
    // 第一个还没答出来的词：光标就落在它的第一格上。
    int? activeWordId;
    for (final wordId in ordered) {
      if (!_pickedIds.contains(wordId)) {
        activeWordId = wordId;
        break;
      }
    }
    return Column(
      key: const Key('meaning-word-choice-answer-slots'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < ordered.length; index += 1) ...[
          if (index > 0)
            const SizedBox(height: MeaningWordChoiceLayout.slotRowGap),
          _buildAnswerRow(
            ordered[index],
            isActiveWord: ordered[index] == activeWordId,
          ),
        ],
      ],
    );
  }

  ///
  /// 构建一个答案单词的字母格；[isActiveWord] 决定要不要显示闪烁光标。
  ///
  /// 已答出的整组转绿，并且点一下可以重听发音——这一条能力从原来的
  /// 「点单词气泡重播」平移过来，去掉气泡后没有丢。
  Widget _buildAnswerRow(int wordId, {required bool isActiveWord}) {
    final spelling = _wordsById[wordId]?.spelling ?? '';
    final revealed = _pickedIds.contains(wordId);
    final entryToken = _revealTokens[wordId];
    final row = AnswerSlots(
      // 已答出的整组转绿；光标只落在当前作答那一组的第一个字母上。
      tone: revealed ? AnswerSlotTone.correct : AnswerSlotTone.neutral,
      showCaret: !revealed && isActiveWord,
      cells: [
        for (var index = 0; index < spelling.length; index += 1)
          // 撇号、连字符、空格这类非字母字符是静态字符，直接显示，不占下划线。
          if (!_isLetter(spelling[index]))
            AnswerSlotCell.static(
              spelling[index],
              key: Key('meaning-word-choice-slot-$wordId-$index'),
            )
          else
            AnswerSlotCell(
              key: Key('meaning-word-choice-slot-$wordId-$index'),
              text: spelling[index],
              filled: revealed,
              // 整组共用同一张入场票：组件按格子顺序给每个字母递增延迟。
              entryToken: revealed ? entryToken : null,
            ),
      ],
    );
    // 还没答出来的组不可点：点它既没有发音可放，也不该泄露任何信息。
    //
    // 这层包装**始终存在**，只是未答出时不响应点击：答出的那一刻若才套上
    // Semantics + InkWell，整排槽位的组件树形状就变了，Flutter 会把它销毁
    // 重建，新建的首帧不播入场动画，整词就会「啪」一下同时出现。
    final canReplay = revealed && spelling.isNotEmpty;
    return Semantics(
      button: canReplay,
      label: canReplay ? '播放 $spelling 的发音' : null,
      child: InkWell(
        key: Key('meaning-word-choice-answer-$wordId'),
        onTap: canReplay ? () => unawaited(_playWordAudio(spelling)) : null,
        child: row,
      ),
    );
  }

  ///
  /// 构建候选词区（文档流，位于正文白卡下方）。
  ///
  /// 布局类似 flex 纵向结构：顶部 + 白卡 + 候选词区；候选词**一行两个**，
  /// 宽度按可用空间均分。与听音辨义共用中性卡面，
  /// 右侧的 Tabler 对错图标表示作答结果，错项文字适当弱化。
  Widget _buildCandidates(AppTokens tokens) => ChoiceOptionGrid(
    options: _candidates.map((candidate) => candidate.spelling).toList(),
    questionKey: _roundIndex,
    keyPrefix: 'meaning-word-choice-option',
    // 新一轮候选还在路上时，屏幕上还是上一轮的词，一律不接受点击。
    enabled: !_savingAnswer && !_candidatesPending,
    correct: <String>{
      if (_pendingChoice?.isMatch == true) _pendingChoice!.spelling,
      for (final candidate in _candidates)
        if (_pickedIds.contains(candidate.wordId)) candidate.spelling,
    },
    wrong: <String>{
      if (_pendingChoice?.isMatch == false) _pendingChoice!.spelling,
      for (final candidate in _candidates)
        if (_disabledIds.contains(candidate.wordId)) candidate.spelling,
    },
    onTap: (text) => _onCandidateTap(
      _candidates.firstWhere((candidate) => candidate.spelling == text).wordId,
    ),
  );

  ///
  /// 构建结算页：圆形图标 + 标题 + 一行说明 + 返回按钮的极简收尾。
  Widget _buildSummary(AppTokens tokens) {
    final items = <SettlementWordItem>[];
    final seen = <int>{};
    for (final word in _wordsById.values) {
      final id = word.id;
      if (id == null || !seen.add(id)) continue;
      final draft = _progress.settlementFor(id);
      final correct = draft?.isCorrect ?? !_progress.progressOf(id).hasAnyWrong;
      items.add(
        SettlementWordItem(
          word: word.spelling,
          isCorrect: correct,
          // 看义选词不按单词计时，结算页这一行不显示用时。
          usedTime: null,
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
      key: const Key('settlement-meaningWordChoice'),
      items: items,
      isBusy: _isCommittingSummary,
      // 看义选词无法按单词拆分时间，所以结算页不显示用时。
      showTotalElapsed: false,
      onAdjust: (index, adjust) async {
        final id = _wordsById.values.elementAt(index).id;
        if (id != null) await _progress.adjustSettlement(id, adjust);
      },
      onRetry: () => unawaited(_leaveSummary(retry: true)),
      onConfirm: _leaveSummary,
    );
  }

  /// 提交结算草稿后离开本页；重开信号交给首页处理。
  Future<void> _leaveSummary({bool retry = false}) async {
    if (!_completed) {
      Navigator.of(context).pop();
      return;
    }
    if (_isCommittingSummary) return;
    setState(() => _isCommittingSummary = true);
    try {
      await _progress.commitSettlement();
      if (mounted) Navigator.of(context).pop(retry);
    } catch (error) {
      debugPrint('提交看义选词结算失败：$error');
      if (mounted) {
        setState(() => _isCommittingSummary = false);
        Toast.show(context, '保存结算失败，请重试：$error');
      }
    }
  }

  ///
  /// 把本局用时格式化成计时文字：不足一小时 mm:ss，满一小时 hh:mm:ss。
  String _formatElapsed() => formatTimerSeconds(_elapsedSeconds);
}

///
/// 固定画布的顶栏图标按钮已抽成公共组件 [ModuleIconButton]（见
/// `lib/widgets/module_scaffold.dart`）：原来这里和听音辨义各有一个私有的
/// `_PlainIconButton`，随身听还有一个公开的 `ListeningIconButton`，
/// 三份实现做的是同一件事。
