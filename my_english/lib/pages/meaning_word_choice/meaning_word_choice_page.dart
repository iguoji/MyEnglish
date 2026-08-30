// dart:async 提供 Timer，用于结算页展示本局用时。
import 'dart:async';
// dart:math 提供 max，读取快照时防止负数进度。
import 'dart:math';

// material.dart 提供全屏页面、进度条、卡片与按钮。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// 所有可见图标继续统一使用 Tabler。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入应用设计令牌。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角时间超过一小时改用 hh:mm:ss，不足用 mm:ss。
import '../../common/date.dart';
// 引入单词模型。
import '../../models/word.dart';
// 引入音频播放接口：点击候选词或气泡单词时朗读。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入复习模块共用的进度出口：负责把快照落进今天的会话。
import '../review/services/session_progress.dart';
// 引入含义序列与候选词构建服务。
import 'services/meaning_word_choice_round_builder.dart';
// 引入看义选词页面集中管理的布局尺寸。
import 'widgets/meaning_word_choice_layout.dart';

///
/// 候选词「答对」后的禁用绿，与词义连连的匹配成功色完全一致。
const Color _kSuccess = Color(0xFF2FB344);

///
/// 聊天气泡的类型：左侧系统出的含义，右侧用户选中的单词。
enum _ChatBubbleKind { meaning, word }

///
/// 「正在输入」三点动画出现的侧别：只有左侧，用于含义气泡出现前。
enum _TypingSide { left }

///
/// 一条聊天气泡的只读数据。
///
/// 含义气泡带合并词性（如 `vi./vt.`），单词气泡只显示拼写并携带主键
/// （点击时用于发音），打字气泡是三点动画占位。
class _ChatBubble {
  ///
  /// 创建一条含义气泡；词性合并成 [posText]（可能为空，由 UI 决定是否展示）。
  const _ChatBubble.meaning({required this.posText, required this.text})
    : kind = _ChatBubbleKind.meaning,
      wordId = null;

  ///
  /// 创建一条单词气泡；[wordId] 用于点击时朗读发音。
  const _ChatBubble.word(this.text, {required this.wordId})
    : kind = _ChatBubbleKind.word,
      posText = null;

  ///
  /// 气泡类型。
  final _ChatBubbleKind kind;

  ///
  /// 含义气泡的词性文本；单词与打字气泡恒为 null。
  final String? posText;

  ///
  /// 气泡正文：含义文本或英文拼写；打字气泡为空。
  final String text;

  ///
  /// 单词气泡所属单词主键；其余气泡为 null。
  final int? wordId;
}

///
/// 全屏看义选词页面。
///
/// 玩法（微信聊天气泡式）：
/// 1. 左侧出现一个中文含义气泡，右下角出现候选单词；
/// 2. 点错 → 该候选词禁用置灰；点对 → 右侧出现该单词的气泡；
/// 3. 一个含义可能匹配多个单词，全部选出才进入下一含义；
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

// 实现 WidgetsBindingObserver 以监听 App 前后台切换，退后台时落盘进度；
// SingleTickerProviderStateMixin 为「正在输入」三点动画提供 Ticker。
class _MeaningWordChoicePageState extends State<MeaningWordChoicePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  /// 全局被点错过的单词主键，结算页「需加强」名单用。
  final Set<int> _disabledWordIds = <int>{};

  /// 每轮答错次数（下标对齐 [_rounds]），结算页「一次选对」统计用。
  List<int> _roundWrongCounts = <int>[];

  /// 已写过复习记录的单词主键，防止续玩后重复写入。
  final Set<int> _recordedWordIds = <int>{};

  /// 本局累计答错次数；同时是会话的 wrongTotal。
  int _errors = 0;

  /// 本局累计用时（毫秒），结算页展示用。
  int _elapsedMs = 0;

  /// 是否已把全部含义走完一遍（进入结算页）。
  bool _completed = false;

  /// 聊天区气泡数据；恢复进度时先清空再按轮次重建。
  final List<_ChatBubble> _bubbles = <_ChatBubble>[];

  /// 气泡区滚动控制器：新气泡出现后滚到底部。
  final ScrollController _scrollController = ScrollController();

  /// 计时器：每秒把用时累加 1 秒。
  Timer? _elapsedTimer;

  /// 是否正在显示「正在输入」三点动画，以及它出现在哪一侧。
  ///
  /// null 表示没有动画；left = 含义气泡出现前；right = 单词气泡出现前。
  _TypingSide? _typingSide;

  /// 三点动画控制器：循环驱动三个圆点依次跳动。
  late final AnimationController _typingController;

  /// 假「正在输入」计时器：到时后把三点占位换成含义气泡。
  Timer? _typingTimer;

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
  int get _displayRound => _completed || _allRoundsDone
      ? _rounds.length
      : _roundIndex + 1;

  ///
  /// 页面初始化：接进度出口、恢复历史快照或开一局新的。
  @override
  void initState() {
    super.initState();
    // 注册生命周期监听，退后台时保存进度。
    WidgetsBinding.instance.addObserver(this);
    // 三点动画控制器：循环时长 0.9 秒，速度曲线让圆点有「呼吸」感。
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
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
    } else {
      // 续玩：重建聊天区气泡，并进入恢复出的当前轮。
      _rebuildBubbles();
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
        // 全局点错过的词在候选区一直保持红色标记。
        _disabledWordIds.add(record.wordId);
      }
    }

    // 找到第一轮「还有匹配词没答对」的，就是当前轮。
    var index = 0;
    while (index < _rounds.length) {
      final round = _rounds[index];
      final answered = answeredWordsByMeaning[round.meaningId] ?? const <int>{};
      if (!round.matchIds.every(answered.contains)) break;
      _recordedWordIds.addAll(round.matchIds);
      index += 1;
    }
    _roundIndex = index;
    // 全部答完 = 这一局已经走完一遍。
    if (_roundIndex >= _rounds.length) {
      _completed = true;
      return;
    }
    // 当前轮的现场：已答对的词恢复选中（候选区绿色、气泡照常显示）、
    // 已点错的候选置灰，答错次数回填。
    final current = _rounds[_roundIndex];
    _pickedIds = <int>{
      ...(answeredWordsByMeaning[current.meaningId] ?? const <int>{}),
    };
    final wrong = wrongByMeaning[current.meaningId] ?? const <int>{};
    _disabledIds = <int>{...wrong};
    _roundWrongCounts[_roundIndex] = wrong.length;
  }

  ///
  /// 构建一条含义气泡：词性合并成小标签（如 `vi./vt.`），空词性不展示。
  _ChatBubble _meaningBubbleFor(MeaningWordChoiceRound round) {
    final posParts = <String>[
      for (final pos in round.posGroup)
        if (pos.isNotEmpty && pos != '*') pos,
    ];
    return _ChatBubble.meaning(
      posText: posParts.isEmpty ? null : posParts.join('/'),
      text: round.definition,
    );
  }

  ///
  /// 恢复进度后重建聊天区气泡。
  ///
  /// 已完成的轮次：含义 + 全部匹配词气泡；当前轮：含义 + 已选出的词气泡。
  /// 之后轮次尚未开始，不产生任何气泡。
  void _rebuildBubbles() {
    _bubbles.clear();
    for (var index = 0; index < _roundIndex; index += 1) {
      final round = _rounds[index];
      _bubbles.add(_meaningBubbleFor(round));
      for (final wordId in round.matchIds) {
        final spelling = _wordsById[wordId]?.spelling ?? '';
        if (spelling.isNotEmpty) {
          _bubbles.add(_ChatBubble.word(spelling, wordId: wordId));
        }
      }
    }
    if (_roundIndex < _rounds.length) {
      final round = _rounds[_roundIndex];
      _bubbles.add(_meaningBubbleFor(round));
      for (final wordId in round.matchIds) {
        if (_pickedIds.contains(wordId)) {
          final spelling = _wordsById[wordId]?.spelling ?? '';
          if (spelling.isNotEmpty) {
            _bubbles.add(_ChatBubble.word(spelling, wordId: wordId));
          }
        }
      }
    }
  }

  /// ===== 轮次推进 =====

  ///
  /// 开始第 [index] 轮：生成候选词、先播放左侧「正在输入」三点动画，
  /// 延迟片刻后再插入含义气泡并落盘。
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
        // 新一轮先不露出候选词：等左侧「正在输入」三点动画播完、
        // 含义气泡出现后再把四个候选填出来，避免候选在出题动画中途挤进来。
        _candidates = const <MeaningWordChoiceCandidate>[];
      }
      // 新一局：含义气泡出现前，左侧先显示「正在输入」三点占位。
      // 续玩：含义气泡已在 _rebuildBubbles 里随历史消息一起重建，
      // 这里只补候选词现场，绝不能再播一次动画、插一次气泡。
      _typingSide = resume ? null : _TypingSide.left;
    });
    if (resume) {
      // 续玩恢复：候选词现场要在这里按当前轮重建。
      _candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
        round: _rounds[index],
        words: widget.words,
      );
      _scrollToBottom();
      unawaited(_persist());
      return;
    }
    // 启动三点动画，模拟对方正在输入。
    _typingController.repeat();
    _scrollToBottom();
    // 假输入结束后再插入含义气泡（聊天气泡式出题），
    // 并把四个候选词一并填出，与含义气泡同刻露出。
    _typingTimer?.cancel();
    _typingTimer = Timer(MeaningWordChoiceLayout.typingDelay, () {
      if (!mounted) return;
      setState(() {
        _typingSide = null;
        _bubbles.add(_meaningBubbleFor(_rounds[index]));
        // 候选词由服务生成：匹配词不足时用会话内干扰词补齐，按字母升序排列。
        _candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
          round: _rounds[index],
          words: widget.words,
        );
      });
      _typingController.stop();
      _typingController.value = 0;
      unawaited(_persist());
      _scrollToBottom();
    });
  }

  ///
  /// 用户点选一个候选词。
  void _onCandidateTap(int wordId) {
    // 已禁用或已选出的词不应再被点击。
    if (_disabledIds.contains(wordId) || _pickedIds.contains(wordId)) return;
    if (_completed) return;
    // 含义气泡还没出现（正在输入动画中）时不允许抢答。
    if (_typingSide != null) return;

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
      // 并把单词气泡直接弹出——正确的词不需要「正在输入」三点动画。
      HapticFeedback.lightImpact();
      setState(() {
        _pickedIds.add(wordId);
        if (spelling.isNotEmpty) {
          _bubbles.add(_ChatBubble.word(spelling, wordId: wordId));
        }
      });
      // 先记这一次「选对了」，现场恢复靠它判断这一轮答到哪了。
      unawaited(
        _recordPick(wordId: wordId, spelling: spelling, isCorrect: true),
      );
      // 该含义的全部匹配词都选出后立即结算。
      if (_currentRoundDone) {
        unawaited(_recordRound(_roundIndex));
      }
      _scrollToBottom();
      // 这一轮全部选对后，直接进下一轮（下一轮仍会先播左侧三点动画）。
      if (_currentRoundDone) {
        _startRound(_roundIndex + 1);
      } else {
        unawaited(_persist());
      }
    } else {
      // 答错：该候选词禁用置灰，错误数累计。
      setState(() {
        _disabledIds.add(wordId);
        _disabledWordIds.add(wordId);
        _errors += 1;
        _roundWrongCounts[_roundIndex] += 1;
      });
      // 记一条「点错了」：重进时靠它把这个候选继续置灰，
      // 结算也靠它判定这一轮该不该加难度。
      unawaited(_recordPick(wordId: wordId, spelling: spelling, isCorrect: false));
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
    _elapsedTimer?.cancel();
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
    _elapsedTimer?.cancel();
    if (!_completed) unawaited(_persist());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTimer?.cancel();
    _typingTimer?.cancel();
    _typingController.dispose();
    _scrollController.dispose();
    // 停表并保存当前进度；completed 也会在此落盘（首页据此显示状态）。
    unawaited(_persist());
    super.dispose();
  }

  ///
  /// 再玩一轮：带「再来一局」信号退回首页，由首页重新走 ReviewFlow。
  void _restart() {
    _elapsedTimer?.cancel();
    Navigator.pop(context, true);
  }

  ///
  /// 滚动到气泡区底部（reverse 列表的最新消息端）。
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  ///
  /// 开始计时；已运行时保持原样。
  void _startElapsedTimer() {
    if (_elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedMs += 1000);
    });
  }

  /// ===== 构建 =====

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 进度 = 已进入的轮数 ÷ 总轮数；与听音辨义口径一致。
    final progress = (_displayRound - 1) / max(_rounds.length, 1);

    return Scaffold(
      backgroundColor: tokens.page,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏与进度条和听音辨义完全一致，四个复习模块切换不跳动。
            _buildHeader(tokens, progress),
            if (_completed)
              Expanded(child: _buildSummary(tokens))
            else
              // 文档流布局：顶部 + 聊天区 + 候选词区，候选词不再悬浮。
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _buildChat(tokens)),
                    _buildCandidates(tokens),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建顶栏与进度条，布局结构与听音辨义页面保持完全一致。
  Widget _buildHeader(AppTokens tokens, double progress) {
    return Column(
      // 顶部区域只占自身实际高度，不抢占下方内容区的空间。
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MeaningWordChoiceLayout.pageInset,
            MeaningWordChoiceLayout.headerTop,
            MeaningWordChoiceLayout.pageInset,
            0,
          ),
          // 用 Stack 而不是 Row：左右两侧宽度不一定相等，
          // 只有绝对定位才能保证中间进度数字严格居中，右上可挂用时。
          child: SizedBox(
            height: MeaningWordChoiceLayout.headerButtonSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$_displayRound / ${_rounds.length}',
                      key: const Key('meaning-word-choice-progress-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: MeaningWordChoiceLayout.headerProgressTextSize,
                        fontWeight: FontWeight.w600,
                        // 等宽数字让计数变化时视觉中心不抖动。
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PlainIconButton(
                    key: const Key('close-meaningWordChoice'),
                    icon: TablerIcons.chevronLeft,
                    alignment: Alignment.centerLeft,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatElapsed(),
                    key: const Key('meaning-word-choice-elapsed'),
                    style: TextStyle(
                      color: tokens.textMedium,
                      fontSize: MeaningWordChoiceLayout.headerProgressTextSize - 3,
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
            MeaningWordChoiceLayout.pageInset,
            MeaningWordChoiceLayout.progressTop,
            MeaningWordChoiceLayout.pageInset,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              MeaningWordChoiceLayout.progressRadius,
            ),
            child: LinearProgressIndicator(
              key: const Key('meaning-word-choice-progress-bar'),
              value: progress,
              minHeight: MeaningWordChoiceLayout.progressHeight,
              color: AppTokens.accent,
              backgroundColor: tokens.sub,
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建聊天气泡区（reverse 列表：最新气泡固定在底部，旧气泡向上推）。
  ///
  /// 底部不预留空白：候选区悬浮盖在气泡上方属于刻意设计，内容被遮挡
  /// 一部分反而更像真实的聊天窗口，用户随时可以上滑查看。
  Widget _buildChat(AppTokens tokens) {
    return ListView.builder(
      key: const Key('meaning-word-choice-chat'),
      controller: _scrollController,
      // reverse 让最新消息贴底，天然满足「新气泡出现后自动可见」。
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        MeaningWordChoiceLayout.chatInset,
        MeaningWordChoiceLayout.bodyTop,
        MeaningWordChoiceLayout.chatInset,
        MeaningWordChoiceLayout.chatInset,
      ),
      // 「正在输入」三点占位也算一项，追加在最新位置。
      itemCount: _bubbles.length + (_typingSide != null ? 1 : 0),
      itemBuilder: (context, index) {
        // 视觉最底部（index 0）是三点动画；其余按倒序取气泡。
        if (_typingSide != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(
              bottom: MeaningWordChoiceLayout.bubbleGap,
            ),
            child: _buildTypingBubble(tokens, _typingSide!),
          );
        }
        final bubbleIndex =
            _bubbles.length - 1 - (index - (_typingSide != null ? 1 : 0));
        final bubble = _bubbles[bubbleIndex];
        return Padding(
          padding: const EdgeInsets.only(
            bottom: MeaningWordChoiceLayout.bubbleGap,
          ),
          child: _buildBubble(tokens, bubble),
        );
      },
    );
  }

  ///
  /// 构建「正在输入」三点占位气泡：按 [side] 靠左或靠右，三个点从左到右
  /// 依次点亮，模拟打字机逐字输入。
  Widget _buildTypingBubble(AppTokens tokens, _TypingSide side) {
    final isLeft = side == _TypingSide.left;
    // 与含义/单词气泡一致的圆角与尾巴方向。
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(MeaningWordChoiceLayout.bubbleRadius),
      topRight: const Radius.circular(MeaningWordChoiceLayout.bubbleRadius),
      bottomLeft: Radius.circular(
        isLeft
            ? MeaningWordChoiceLayout.bubbleTailRadius
            : MeaningWordChoiceLayout.bubbleRadius,
      ),
      bottomRight: Radius.circular(
        isLeft
            ? MeaningWordChoiceLayout.bubbleRadius
            : MeaningWordChoiceLayout.bubbleTailRadius,
      ),
    );

    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width: MeaningWordChoiceLayout.typingBubbleWidth,
        // 最低高度与普通气泡一致，三点内容不至于让气泡显得又窄又扁。
        constraints: const BoxConstraints(
          minHeight: MeaningWordChoiceLayout.bubbleMinHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MeaningWordChoiceLayout.bubblePaddingHorizontal,
          vertical: MeaningWordChoiceLayout.bubblePaddingVertical,
        ),
        decoration: BoxDecoration(
          color: isLeft ? tokens.card : AppTokens.accent,
          borderRadius: radius,
          border: isLeft ? Border.all(color: tokens.rowBorder) : null,
        ),
        child: AnimatedBuilder(
          animation: _typingController,
          builder: (context, child) {
            final t = _typingController.value;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < 3; i += 1) ...[
                  if (i > 0)
                    const SizedBox(width: MeaningWordChoiceLayout.typingDotGap),
                  _buildTypingDot(t, i, isLeft, tokens),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  ///
  /// 构建三点动画里的一个圆点；三个点按顺序从左到右依次点亮。
  ///
  /// 每个点在自己的时间片内从透明渐变到实色：点 0 先亮，点 1 跟上，
  /// 点 2 殿后，形成「正在输入」的推进感，而不是一起跳动。
  Widget _buildTypingDot(double t, int index, bool isLeft, AppTokens tokens) {
    // 每个点占用 1/3 周期：点 i 在 t ∈ [i/3, (i+1)/3] 区间内完成淡入。
    final progress = ((t - index / 3) * 3).clamp(0.0, 1.0);
    // 完成后保持常亮，等下一轮循环从头再来。
    final opacity = progress == 1.0 ? 0.25 + 0.75 * progress : progress;
    return Opacity(
      // 右侧（单词侧）的气泡是品牌蓝底，圆点用白色才看得清。
      opacity: opacity,
      child: Container(
        width: MeaningWordChoiceLayout.typingDotSize,
        height: MeaningWordChoiceLayout.typingDotSize,
        decoration: BoxDecoration(
          color: isLeft ? tokens.textSecondary : Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  ///
  /// 构建单条气泡：左侧含义（浅底）、右侧单词（品牌蓝底，可点击重播发音）。
  Widget _buildBubble(AppTokens tokens, _ChatBubble bubble) {
    final isMeaning = bubble.kind == _ChatBubbleKind.meaning;
    // 微信式圆角：贴近发送方向的一角更小，形成「尾巴」。
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(MeaningWordChoiceLayout.bubbleRadius),
      topRight: const Radius.circular(MeaningWordChoiceLayout.bubbleRadius),
      bottomLeft: Radius.circular(
        isMeaning
            ? MeaningWordChoiceLayout.bubbleTailRadius
            : MeaningWordChoiceLayout.bubbleRadius,
      ),
      bottomRight: Radius.circular(
        isMeaning
            ? MeaningWordChoiceLayout.bubbleRadius
            : MeaningWordChoiceLayout.bubbleTailRadius,
      ),
    );

    final bubbleWidget = Container(
      // 最低高度保证短内容（含三点动画）也有稳定的气泡轮廓。
      constraints: BoxConstraints(
        minHeight: MeaningWordChoiceLayout.bubbleMinHeight,
        maxWidth: MediaQuery.sizeOf(context).width *
            MeaningWordChoiceLayout.bubbleMaxWidthFactor,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: MeaningWordChoiceLayout.bubblePaddingHorizontal,
        vertical: MeaningWordChoiceLayout.bubblePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: isMeaning ? tokens.card : AppTokens.accent,
        borderRadius: radius,
        border: isMeaning ? Border.all(color: tokens.rowBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 含义气泡的词性标签：更小更轻，与正文区分。
          if (isMeaning && bubble.posText != null)
            Text(
              bubble.posText!,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: MeaningWordChoiceLayout.bubblePosTextSize,
              ),
            ),
          Text(
            bubble.text,
            style: TextStyle(
              color: isMeaning ? tokens.text : Colors.white,
              fontSize: MeaningWordChoiceLayout.bubbleTextSize,
              fontWeight: isMeaning ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    // 单词气泡可点击：重播该单词发音（与候选词点击同一条通道）。
    if (!isMeaning) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('meaning-word-choice-bubble-word-${bubble.wordId}'),
            onTap: () {
              final wordId = bubble.wordId;
              final spelling =
                  wordId == null ? null : _wordsById[wordId]?.spelling;
              if (spelling != null && spelling.isNotEmpty) {
                unawaited(_playWordAudio(spelling));
              }
            },
            borderRadius: radius,
            child: bubbleWidget,
          ),
        ),
      );
    }
    // 含义靠左、单词靠右，微信对话式排版。
    return Align(
      alignment: Alignment.centerLeft,
      child: bubbleWidget,
    );
  }

  ///
  /// 构建候选词区（文档流，位于聊天区下方）。
  ///
  /// 布局类似 flex 纵向结构：顶部 + 聊天区 + 候选词区；候选词**一行两个**，
  /// 宽度按可用空间均分。状态用颜色表达：点错的词置灰加删除线；
  /// 答对的词留在原位、变成词义连连同款的绿色禁用态。
  Widget _buildCandidates(AppTokens tokens) {
    // 候选词全部保留（答对的不再移除，只变色）。
    final visible = _candidates;
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MeaningWordChoiceLayout.pageInset,
        MeaningWordChoiceLayout.candidateTop,
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
    final picked = _pickedIds.contains(candidate.wordId);
    final disabled = _disabledIds.contains(candidate.wordId);
    final spelling = _wordsById[candidate.wordId]?.spelling ?? '';
    // 答对用绿色、点错用灰色，未处理保持卡片底色。
    final stateColor = picked
        ? _kSuccess
        : disabled
            ? tokens.textSecondary
            : null;
    final background = picked
        ? _kSuccess.withValues(alpha: 0.10)
        : disabled
            ? tokens.sub
            : tokens.card;

    // 按钮宽高固定，点击画布稳定，布局不随文字长短抖动。
    final button = Container(
      key: Key('meaning-word-choice-option-${candidate.wordId}'),
      width: width,
      height: MeaningWordChoiceLayout.candidateHeight,
      // 四边内边距统一：28 徽章 + 上下 8×2 = 44 正好占满按钮，
      // ABCD 距左/上/下完全等距，视觉对称。
      padding: const EdgeInsets.all(
        MeaningWordChoiceLayout.candidateContentInset,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          MeaningWordChoiceLayout.candidateRadius,
        ),
        border: Border.all(
          color: stateColor ?? tokens.rowBorder,
        ),
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
                  ? _kSuccess.withValues(alpha: 0.14)
                  : disabled
                      ? tokens.card
                      : tokens.sub,
              border: Border.all(
                color: stateColor ?? tokens.rowBorder,
              ),
              borderRadius: BorderRadius.circular(
                MeaningWordChoiceLayout.optionBadgeRadius,
              ),
            ),
            child: Text(
              String.fromCharCode('A'.codeUnitAt(0) + index),
              style: TextStyle(
                color: stateColor ?? tokens.textSecondary,
                fontSize: MeaningWordChoiceLayout.optionBadgeTextSize,
                fontWeight: FontWeight.w700,
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
                style: TextStyle(
                  color: stateColor ?? tokens.text,
                  fontSize: MeaningWordChoiceLayout.candidateTextSize,
                  fontWeight: FontWeight.w600,
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
  /// 构建结算页：一次选对 / 失误次数 / 用时 + 需加强名单 + 再来一轮。
  Widget _buildSummary(AppTokens tokens) {
    // 「一次选对」= 整轮没有点错过任何词的轮数。
    final perfectCount = _roundWrongCounts.where((count) => count == 0).length;
    // 点错过的单词拼写，按出现顺序去重；查不到拼写的旧主键自动跳过。
    final weakSpellings = <String>[
      for (final wordId in _disabledWordIds) ?_wordsById[wordId]?.spelling,
    ];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: MeaningWordChoiceLayout.summaryInset,
          vertical: MeaningWordChoiceLayout.summarySectionGap,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.maxHeight - MeaningWordChoiceLayout.summarySectionGap * 2,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 圆形图标底盘：直径 64，品牌蓝的 10% 淡版。
              Center(
                child: Container(
                  width: MeaningWordChoiceLayout.summaryAvatarSize,
                  height: MeaningWordChoiceLayout.summaryAvatarSize,
                  decoration: BoxDecoration(
                    color: AppTokens.accent.withValues(alpha: 0.1),
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
                    size: MeaningWordChoiceLayout.summaryAvatarIconSize,
                    color: AppTokens.accent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '看义选词完成',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MeaningWordChoiceLayout.summaryTitleSize,
                  fontWeight: FontWeight.bold,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                perfectCount == _rounds.length
                    ? '本组 ${_rounds.length} 个含义全部一次选对'
                    : '本组 ${_rounds.length} 个含义已全部完成',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MeaningWordChoiceLayout.summarySubtitleSize,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: MeaningWordChoiceLayout.summarySectionGap),
              // 上排统计卡：一次选对 / 失误次数 / 用时。
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('meaning-word-choice-stat-perfect'),
                        icon: TablerIcons.flame,
                        label: '一次选对',
                        value: '$perfectCount',
                        unit: '共 ${_rounds.length} 题',
                        color: AppTokens.accent,
                        tokens: tokens,
                      ),
                    ),
                    const SizedBox(width: MeaningWordChoiceLayout.summaryStatGap),
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('meaning-word-choice-stat-errors'),
                        icon: TablerIcons.x,
                        label: '失误次数',
                        value: '$_errors',
                        unit: '次',
                        color: AppTokens.danger,
                        tokens: tokens,
                      ),
                    ),
                    const SizedBox(width: MeaningWordChoiceLayout.summaryStatGap),
                    Expanded(
                      child: _SummaryStatCard(
                        key: const Key('meaning-word-choice-stat-time'),
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
              // 需加强名单：点错过的单词，照着这份名单再练。
              if (weakSpellings.isNotEmpty) ...[
                const SizedBox(height: MeaningWordChoiceLayout.summarySectionGap),
                Text(
                  '这几个词需要再练',
                  style: TextStyle(
                    fontSize: MeaningWordChoiceLayout.summaryStatLabelSize,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: MeaningWordChoiceLayout.bubbleGap),
                Wrap(
                  spacing: MeaningWordChoiceLayout.bubbleGap,
                  runSpacing: MeaningWordChoiceLayout.bubbleGap,
                  children: <Widget>[
                    for (final spelling in weakSpellings)
                      Container(
                        key: Key('meaning-word-choice-weak-$spelling'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: MeaningWordChoiceLayout.bubblePaddingHorizontal,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            MeaningWordChoiceLayout.weakChipRadius,
                          ),
                        ),
                        child: Text(
                          spelling,
                          style: TextStyle(
                            color: AppTokens.danger,
                            fontSize: MeaningWordChoiceLayout.weakChipTextSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: MeaningWordChoiceLayout.summarySectionGap),
              SizedBox(
                height: MeaningWordChoiceLayout.summaryButtonHeight,
                child: FilledButton.icon(
                  key: const Key('meaning-word-choice-restart'),
                  onPressed: _restart,
                  icon: const Icon(TablerIcons.rotateClockwise, size: 18),
                  label: const Text('再来一轮'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: MeaningWordChoiceLayout.summaryButtonTextSize,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        MeaningWordChoiceLayout.candidateRadius,
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
  /// 把本局用时格式化成计时文字：不足一小时 mm:ss，满一小时 hh:mm:ss。
  String _formatElapsed() => formatTimerSeconds(_elapsedSeconds);
}

///
/// 结算页统计卡：图标 + 标签 + 数值 + 单位。
///
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

  /// 统计项图标。
  final IconData icon;

  /// 统计项名称。
  final String label;

  /// 统计数值文本。
  final String value;

  /// 数值单位。
  final String unit;

  /// 图标与数值的主题色。
  final Color color;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 是否为时间值（数值通常两位，避免宽度抖动）。
  final bool isTimeValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(MeaningWordChoiceLayout.candidateRadius),
        border: Border.all(color: tokens.rowBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: MeaningWordChoiceLayout.summaryStatValueSize,
              fontWeight: FontWeight.w700,
              color: tokens.text,
              // 时间值等宽，避免秒数变化时卡片抖动。
              fontFeatures: isTimeValue
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: MeaningWordChoiceLayout.summaryStatLabelSize,
              color: tokens.textSecondary,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 11,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

///
/// 固定画布的顶栏图标按钮，与听音辨义页面中的实现保持一致。
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

  /// 需要显示的 Tabler 图标。
  final IconData icon;

  /// 用户点击图标画布时执行的回调。
  final VoidCallback onTap;

  /// 图标在 34 像素画布中的对齐方式。
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: MeaningWordChoiceLayout.headerButtonSize,
      height: MeaningWordChoiceLayout.headerButtonSize,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          MeaningWordChoiceLayout.headerButtonSize / 2,
        ),
        child: Align(
          alignment: alignment,
          child: Icon(
            icon,
            size: MeaningWordChoiceLayout.headerIconSize,
            color: tokens.textMedium,
          ),
        ),
      ),
    );
  }
}
