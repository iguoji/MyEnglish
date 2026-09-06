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
// 引入音频播放接口：点击候选词或已答出的单词时朗读。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入全 App 共用的「下划线字母格」，与拼写巩固是同一个组件。
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
import '../../widgets/letter_slot.dart';
// 引入复习模块共用的进度出口：负责把快照落进今天的会话。
import '../review/services/session_progress.dart';
// 引入含义序列与候选词构建服务。
import 'services/meaning_word_choice_round_builder.dart';
// 引入看义选词页面集中管理的布局尺寸。
import 'widgets/meaning_word_choice_layout.dart';

///
/// 只有 ASCII 英文字母才占一格下划线；撇号、连字符、空格直接显示。
final RegExp _englishLetterPattern = RegExp(r'^[A-Za-z]$');

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

  /// 已写过复习记录的单词主键，防止续玩后重复写入。
  final Set<int> _recordedWordIds = <int>{};

  /// 本局累计答错次数；同时是会话的 wrongTotal。
  int _errors = 0;

  /// 本局累计用时（毫秒），结算页展示用。
  int _elapsedMs = 0;

  /// 是否已把全部含义走完一遍（进入结算页）。
  bool _completed = false;

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
    // 数据列表就是打乱后的答题顺序，开局时已经定好并落库。
    _rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
      _progress.session.idItems,
      widget.words,
    );
    if (_rounds.isEmpty) return;
    _roundWrongCounts = List<int>.filled(_rounds.length, 0);

    // 已用时间来自会话字段，单位是秒。
    _elapsedMs = _progress.session.elapsed * 1000;
    // 累计答错数由记录直接数出来：错完就退、退完再进，不能刷出一局「全对」。
    _errors = _progress.wrongCount;

    // 回放记录：按「哪条含义答对了哪些词」推进轮次，按「哪条含义点错了谁」置灰候选。
    //
    // 一道含义可能匹配多个单词（如 eat 与 feed 都有「吃」），所以答对要记到
    // 「词」这一层而不是「含义」这一层：只选出其中一个词就退出，重进时这轮
    // 不能算完成，剩下的词还得继续选。
    final answeredWordsByMeaning = <int, Set<int>>{};
    final wrongByMeaning = <int, Set<int>>{};
    for (final record in _progress.allRecords) {
      final meaningId = record.meaningId;
      if (meaningId == null) continue;
      if (record.isCorrect) {
        (answeredWordsByMeaning[meaningId] ??= <int>{}).add(record.wordId);
      } else {
        (wrongByMeaning[meaningId] ??= <int>{}).add(record.wordId);
      }
    }

    // 找到第一轮「还有匹配词没答对」的，就是当前轮。
    //
    // 顺带把**每一轮**（含已经整轮答完、直接跳过去的历史轮）点错的次数都回填
    // 进 [_roundWrongCounts]：只回填当前轮的话，中途退出前那几轮的失误会在
    // 结算页「全部一次选对」的统计里凭空消失——明明错过一次，退出再进后却
    // 显示成本组从头到尾零失误。
    var index = 0;
    while (index < _rounds.length) {
      final round = _rounds[index];
      _roundWrongCounts[index] =
          (wrongByMeaning[round.meaningId] ?? const <int>{}).length;
      final answered = answeredWordsByMeaning[round.meaningId] ?? const <int>{};
      if (!round.matchIds.every(answered.contains)) break;
      _recordedWordIds.addAll(round.matchIds);
      index += 1;
    }
    _roundIndex = index;
    // 全部答完 = 这一局已经走完一遍。
    if (_roundIndex >= _rounds.length) {
      _completed = true;
      // 补盖收尾章：最后一轮答完后的「切轮停顿」（1.2 秒）里退出时，整局收尾
      // （finish）可能没来得及执行，会话会一直挂在「进行中」——首页永远差一格、
      // 今日主线也永远判不了完成。回放已经证明全部走完，这里直接补盖一次；
      // finish 自带防重，即使正常路径早已盖过也不会有副作用。
      unawaited(
        _progress.finish(
          perfect: true,
          cursor: _rounds.length,
          elapsed: _elapsedSeconds,
        ),
      );
      return;
    }
    // 当前轮的现场：已答对的词恢复选中（候选区绿色、气泡照常显示）、
    // 已点错的候选置灰（答错次数在上面的循环里已经回填过）。
    final current = _rounds[_roundIndex];
    _pickedIds = <int>{
      ...(answeredWordsByMeaning[current.meaningId] ?? const <int>{}),
    };
    final wrong = wrongByMeaning[current.meaningId] ?? const <int>{};
    _disabledIds = <int>{...wrong};
  }

  /// ===== 轮次推进 =====

  ///
  /// 开始第 [index] 轮：清空现场并生成候选词。
  ///
  /// 白卡版不再有「正在输入」的假动画，释义与候选词同时露出；换题时白卡
  /// 自己会淡入上移（见 [_buildQuestionCard]），节奏与听音辨义一致。
  void _startRound(int index, {bool resume = false}) {
    // 越界表示全部走完，直接结算。
    if (index >= _rounds.length) {
      _completeSession();
      return;
    }
    setState(() {
      _roundIndex = index;
      // 续玩时保留回放出来的现场（已选出的、已点错置灰的），不要清空。
      if (!resume) {
        _pickedIds = <int>{};
        _disabledIds = <int>{};
      }
      // 恢复出来的已答词不该重播填入动画，所以入场编号一律清空。
      _revealTokens.clear();
      // 候选词由服务生成：匹配词不足时用会话内干扰词补齐，按字母升序排列。
      _candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
        round: _rounds[index],
        words: widget.words,
      );
    });
    unawaited(_persist());
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
  void _onCandidateTap(int wordId) {
    // 已禁用或已选出的词不应再被点击。
    if (_disabledIds.contains(wordId) || _pickedIds.contains(wordId)) return;
    if (_completed) return;
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
    final spelling = _wordsById[wordId]?.spelling ?? '';
    if (spelling.isNotEmpty) unawaited(_playWordAudio(spelling));

    if (candidate.isMatch) {
      // 答对：先给一个轻震动反馈（和听音辨义一致），
      // 再给这个词发一张入场票，让它那组字母格把整词填进去。
      HapticFeedback.lightImpact();
      setState(() {
        _pickedIds.add(wordId);
        _revealTokens[wordId] = _revealSeq += 1;
      });
      // 先记这一次「选对了」，现场恢复靠它判断这一轮答到哪了。
      unawaited(
        _recordPick(wordId: wordId, spelling: spelling, isCorrect: true),
      );
      // 该含义的全部匹配词都选出后立即结算。
      if (_currentRoundDone) {
        unawaited(_recordRound(_roundIndex));
      }
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
        _errors += 1;
        _roundWrongCounts[_roundIndex] += 1;
      });
      // 记一条「点错了」：重进时靠它把这个候选继续置灰，
      // 结算也靠它判定这一轮该不该加难度。
      unawaited(
        _recordPick(wordId: wordId, spelling: spelling, isCorrect: false),
      );
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
    try {
      await _progress.record(
        wordId: wordId,
        meaningId: _rounds[_roundIndex].meaningId,
        // 记下用户实际点的那个词，回看时能看出把哪两个词搞混了。
        input: spelling,
        isCorrect: isCorrect,
      );
    } catch (error) {
      // 写记录失败不该打断答题，最多这一次点击没留痕。
      debugPrint('写入看义选词点击记录失败：$error');
    }
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
  /// 一轮含义答完：给该轮每个匹配单词结算。
  ///
  /// 「对 / 错」在点击的当下就已经逐次记进了会话记录，这里只负责结算：
  /// 结算会看「本局这个词有没有点错过」，据此更新难度与复习时间。
  /// 已结算过的词由集合挡住，续玩不重复算。
  Future<void> _recordRound(int index) async {
    final round = _rounds[index];
    for (final wordId in round.matchIds) {
      // 恢复进度后重复走到同一轮不该再算，用集合挡住。
      if (!_recordedWordIds.add(wordId)) continue;
      try {
        await _progress.settle(wordId);
      } catch (error) {
        // 结算失败不该打断正在进行的一局；集合里放回去，之后还有机会补算。
        _recordedWordIds.remove(wordId);
        debugPrint('看义选词结算单词失败：$error');
      }
    }
    unawaited(_persist());
  }

  ///
  /// 全部含义走完：停表、标记完成并结算这一局。
  void _completeSession() {
    // 整局已经结束，彻底停表，避免结算页期间定时器继续空转。
    _stopElapsedTimer();
    setState(() => _completed = true);
    // 判定规则与其他模块一致：把全部含义走完一遍即算完成，答错不影响整局成败。
    unawaited(
      _progress.finish(
        perfect: true,
        cursor: _rounds.length,
        elapsed: _elapsedSeconds,
      ),
    );
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
      header: ModuleHeader(
        leading: ModuleIconButton(
          key: const Key('close-meaningWordChoice'),
          icon: AppGlyph.back,
          alignment: Alignment.centerLeft,
          onTap: () => Navigator.of(context).pop(),
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
      body: _completed ? _buildSummary(tokens) : _buildQuestionCard(tokens),
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
            // 换题时整张卡淡入并轻微上移；同一题内反复重建不会重播（key 未变）。
            child: TweenAnimationBuilder<double>(
              key: ValueKey<int>(_roundIndex),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: AppDuration.ms250),
              curve: Curves.easeOut,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 8),
                  child: child,
                ),
              ),
              child: Container(
                key: const Key('meaning-word-choice-question-card'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: MeaningWordChoiceLayout.bodyCardPaddingHorizontal,
                  vertical: MeaningWordChoiceLayout.bodyCardPaddingVertical,
                ),
                decoration: BoxDecoration(
                  color: tokens.card,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(
                    MeaningWordChoiceLayout.bodyCardRadius,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.cardShadow,
                      offset: const Offset(0, AppShadow.cardOffsetY),
                      blurRadius: AppShadow.cardBlur,
                    ),
                  ],
                ),
                child: Center(
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
                      _buildAnswerSlots(tokens, round),
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
  /// 字母格用的是拼写巩固同一个组件（`lib/widgets/letter_slot.dart`），
  /// 所以两个模块的「填空」观感完全一致：这边不用键盘敲，选中正确候选后
  /// 整个单词一次填入并转绿。
  ///
  /// 排列顺序按拼写字母升序固定，闪烁光标落在第一个还没答出来的那组上。
  Widget _buildAnswerSlots(AppTokens tokens, MeaningWordChoiceRound round) {
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
            tokens,
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
  Widget _buildAnswerRow(
    AppTokens tokens,
    int wordId, {
    required bool isActiveWord,
  }) {
    final spelling = _wordsById[wordId]?.spelling ?? '';
    final revealed = _pickedIds.contains(wordId);
    final entryToken = _revealTokens[wordId];
    final children = <Widget>[];
    // 记住第一个字母的位置：光标只画在这一格上。
    var firstLetterIndex = -1;
    for (var index = 0; index < spelling.length; index += 1) {
      final character = spelling[index];
      // 撇号、连字符、空格这类非字母字符直接显示，不占用一格下划线。
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
                  color: revealed ? AppTokens.success : tokens.textSecondary,
                  fontSize: LetterSlotLayout.letterTextSize,
                  fontWeight: AppWeight.semibold,
                ),
              ),
            ),
          ),
        );
        continue;
      }
      if (firstLetterIndex < 0) firstLetterIndex = index;
      final isCaret = !revealed && isActiveWord && index == firstLetterIndex;
      children.add(
        LetterSlot(
          key: Key('meaning-word-choice-slot-$wordId-$index'),
          text: revealed ? character : null,
          isActive: isCaret,
          lineColor: revealed
              ? AppTokens.success
              : isCaret
              ? AppTokens.primary
              : tokens.check,
          textColor: AppTokens.success,
          entryToken: revealed ? entryToken : null,
          // 整词一次填入，用「轻轻浮现」那一档；敲键盘式的从零弹出会让
          // 一整排字母显得晚了一拍才出现。
          entryStyle: LetterEntryStyle.reveal,
        ),
      );
    }
    final row = Wrap(
      alignment: WrapAlignment.center,
      spacing: LetterSlotLayout.letterGap,
      runSpacing: LetterSlotLayout.letterRunGap,
      children: children,
    );
    // 还没答出来的组不可点：点它既没有发音可放，也不该泄露任何信息。
    if (!revealed || spelling.isEmpty) return row;
    return Semantics(
      button: true,
      label: '播放 $spelling 的发音',
      child: InkWell(
        key: Key('meaning-word-choice-answer-$wordId'),
        onTap: () => unawaited(_playWordAudio(spelling)),
        child: row,
      ),
    );
  }

  ///
  /// 构建候选词区（文档流，位于正文白卡下方）。
  ///
  /// 布局类似 flex 纵向结构：顶部 + 白卡 + 候选词区；候选词**一行两个**，
  /// 宽度按可用空间均分。状态用颜色表达：点错的词置灰加删除线；
  /// 答对的词留在原位、变成词义连连同款的绿色禁用态。
  Widget _buildCandidates(AppTokens tokens) {
    // 候选词全部保留（答对的不再移除，只变色）。
    final visible = _candidates;
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      // 顶部不留白：候选区与白卡之间的间距只由白卡底部的 bodyVerticalInset 承担，
      // 避免两段留白叠加成“正文和候选词之间空了一大块”。
      padding: const EdgeInsets.fromLTRB(
        MeaningWordChoiceLayout.pageInset,
        AppSpace.p0,
        MeaningWordChoiceLayout.pageInset,
        MeaningWordChoiceLayout.pageInset,
      ),
      // 用父级实际宽度算按钮宽度：一行两个，各占 (宽 − 间距) / 2。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buttonWidth =
              (constraints.maxWidth - MeaningWordChoiceLayout.candidateGap) / 2;
          return Wrap(
            spacing: MeaningWordChoiceLayout.candidateGap,
            runSpacing: MeaningWordChoiceLayout.candidateGap,
            children: <Widget>[
              for (var index = 0; index < visible.length; index += 1)
                _buildCandidateButton(
                  tokens,
                  visible[index],
                  index,
                  buttonWidth,
                ),
            ],
          );
        },
      ),
    );
  }

  ///
  /// 构建一个候选词按钮：左侧 A/B/C/D 序号方块 + 单词文本；
  /// 宽度由 [width] 决定（单列或网格共用）。
  Widget _buildCandidateButton(
    AppTokens tokens,
    MeaningWordChoiceCandidate candidate,
    int index,
    double width,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final picked = _pickedIds.contains(candidate.wordId);
    final disabled = _disabledIds.contains(candidate.wordId);
    final spelling = _wordsById[candidate.wordId]?.spelling ?? '';
    // 答对用绿色、点错用灰色，未处理保持卡片底色。
    final stateColor = picked
        ? AppTokens.success
        : disabled
        ? tokens.textSecondary
        : null;
    final background = picked
        ? AppTokens.success.withValues(alpha: AppAlpha.a10)
        : disabled
        ? tokens.sub
        : tokens.card;

    // 按钮宽度固定，点击画布稳定，布局不随文字长短抖动。
    final button = Container(
      key: Key('meaning-word-choice-option-${candidate.wordId}'),
      width: width,
      // 高度是「至少 44」而不是「就是 44」。
      //
      // 写死 44 有两个后果，都是安静发生的、不报错的：
      //
      //   1. 选了「大 / 特大」字号后，单词本身会变高，可高度不变，
      //      于是单词被 FittedBox 反过来压小——用户明明调大了字，
      //      候选词却一点没变大；
      //   2. 就算是标准字号，44 也本来就不够：按钮内容其实是
      //      「28 的 ABCD 徽章 + 上下 8 的内边距 + 上下 1 的描边」= 46。
      //      写死 44 的时候，多出来的 2 像素是从徽章身上抠的——
      //      本该是 28×28 的正方块，实测被压成了 28×26 的扁块。
      //
      // 改成最小高度后，按钮取自己算出来的自然高度（标准字号下 46），
      // 徽章恢复成正方形，字号调大时按钮也跟着一起长高。
      // 44 这个数保留为「手指可点的下限」：内容再怎么缩也不会低于它。
      constraints: const BoxConstraints(
        minHeight: MeaningWordChoiceLayout.candidateHeight,
      ),
      // 四边内边距统一：ABCD 距左 / 上 / 下完全等距，视觉对称。
      padding: const EdgeInsets.all(
        MeaningWordChoiceLayout.candidateContentInset,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          MeaningWordChoiceLayout.candidateRadius,
        ),
        border: Border.all(color: stateColor ?? tokens.rowBorder),
      ),
      child: Row(
        children: [
          // 序号方块：A/B/C/D，听音辨义候选词同款。
          Container(
            width: MeaningWordChoiceLayout.optionBadgeSize,
            height: MeaningWordChoiceLayout.optionBadgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: picked
                  ? AppTokens.success.withValues(alpha: AppAlpha.a14)
                  : disabled
                  ? tokens.card
                  : tokens.sub,
              border: Border.all(color: stateColor ?? tokens.rowBorder),
              borderRadius: BorderRadius.circular(
                MeaningWordChoiceLayout.optionBadgeRadius,
              ),
            ),
            child: Text(
              String.fromCharCode('A'.codeUnitAt(0) + index),
              // 序号方块里的字母比同字号标签更重一档，方块小才压得住。
              style: textTheme.fs6Bold.copyWith(
                color: stateColor ?? tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: MeaningWordChoiceLayout.optionBadgeGap),
          Expanded(
            // FittedBox 自适应：单词过长时整体等比缩小字号塞进一行，
            // 而不是截断成省略号让人看不全。中心偏左，紧贴序号徽章。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                spelling,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: textTheme.fs4Semibold.copyWith(
                  color: stateColor ?? tokens.text,
                  // 点错的词加删除线，一眼看出已排除。
                  decoration: disabled ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // 已禁用（答对或点错）的词不可再点；其余用 InkWell 提供按压反馈。
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: picked || disabled
            ? null
            : () => _onCandidateTap(candidate.wordId),
        borderRadius: BorderRadius.circular(
          MeaningWordChoiceLayout.candidateRadius,
        ),
        child: button,
      ),
    );
  }

  /// ===== 结算页 =====

  ///
  /// 构建结算页：圆形图标 + 标题 + 一行说明 + 返回按钮的极简收尾。
  Widget _buildSummary(AppTokens tokens) {
    // 「一次选对」= 整轮没有点错过任何词的轮数，只用来决定副标题说哪句话。
    final perfectCount = _roundWrongCounts.where((count) => count == 0).length;
    return ModuleSummaryView(
      icon: AppGlyph.correct,
      color: AppTokens.success,
      title: '看义选词完成',
      subtitle: perfectCount == _rounds.length
          ? '本组 ${_rounds.length} 个含义全部一次选对'
          : '共 ${_rounds.length} 个含义 · 失误 $_errors 次',
      actionLabel: '返回',
      actionKey: const Key('finish-meaningWordChoice'),
      onAction: () => Navigator.of(context).pop(),
    );
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
