// dart:async 提供 unawaited，播放音频时不阻塞按钮响应。
import 'dart:async';
// dart:convert 提供 jsonEncode，用结构化数组生成不会碰撞的候选缓存 key。
import 'dart:convert';
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
// 引入全局 Toast 工具，层级高于 BottomSheet。
import '../../common/toast.dart';
// 引入词义模型。
import '../../models/meaning.dart';
// 引入单词模型。
import '../../models/word.dart';
// 引入可恢复的学习会话模型。
import '../../models/learning_session.dart';
// 引入音频播放接口。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入独立候选项生成服务，页面只负责当前答题状态。
import 'services/listening_meaning_option_generator.dart';
// 引入听音辨义记录 Store：点击下一题时写入结果并驱动难度变化。
import '../../models/review_session.dart';
import '../../store/review_record.dart';
import '../../store/review_session.dart';
import '../review/services/session_progress_sink.dart';
// 引入听音辨义候选项缓存 Store，让每道题长期复用相同干扰项。
import '../../store/listening_meaning_option_cache.dart';
// 引入学习会话 Store，持续保存本轮单词顺序与答题进度。
import '../../store/learning_session.dart';
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
  ///
  /// @var ListeningMeaningStage
  ///
  word,

  ///
  /// 按顺序选择每条中文释义的阶段。
  ///
  /// @var ListeningMeaningStage
  ///
  definition,
}

///
/// 一个可点击的听音辨义候选答案。
///
/// @property String text 用户看到的候选文本。
/// @property bool isCorrect 是否为当前小题正确答案。
///
class ListeningMeaningOption {
  ///
  /// 创建听音辨义候选答案。
  ///
  /// @param  String  text 用户看到的候选文本。
  /// @param  bool  isCorrect 是否为当前小题正确答案。
  ///
  const ListeningMeaningOption({required this.text, required this.isCorrect});

  ///
  /// 用户看到的候选文本。
  ///
  /// @var String
  ///
  final String text;

  ///
  /// 是否为当前小题正确答案。
  ///
  /// @var bool
  ///
  final bool isCorrect;
}

///
/// 全屏听音辨义页面。
///
class ListeningMeaningPage extends StatefulWidget {
  ///
  /// 创建单词听音辨义页面。
  ///
  /// @param  `List<Word>`  words 本轮固定顺序的学习列表。
  /// @param  WordAudioPlayer  audioPlayer 单词发音服务。
  /// @param  PronunciationAccent  accent 当前发音口音。
  /// @param  ReviewRecordStore?  recordStore 可替换的复习记录 Store。
  /// @param  ListeningMeaningOptionCacheStore?  optionCacheStore 可替换的候选缓存 Store。
  /// @param  LearningSession?  initialSession 普通入口需要恢复的长期会话。
  /// @param  LearningSessionStore?  sessionStore 可替换的长期会话 Store。
  /// @param  ReviewSession?  reviewSession 复习模块本局的会话；普通入口为 null。
  /// @param  ReviewSessionStore?  reviewSessionStore 可替换的复习会话 Store。
  /// @param  String  definitionSeparator 多条释义之间的分隔符。
  ///
  /// @param  Key?  key
  ///
  const ListeningMeaningPage({
    required this.words,
    required this.audioPlayer,
    required this.accent,
    this.recordStore,
    this.optionCacheStore,
    this.initialSession,
    this.sessionStore,
    this.reviewSession,
    this.reviewSessionStore,
    this.definitionSeparator = '、',
    super.key,
  }) : assert(words.length > 0, '听音辨义页至少需要一个学习单词');

  ///
  /// 本轮参与听音辨义的单词。
  ///
  /// @var `List<Word>`
  ///
  final List<Word> words;

  ///
  /// 与首页、随身听共用的发音服务。
  ///
  /// @var WordAudioPlayer
  ///
  final WordAudioPlayer audioPlayer;

  ///
  /// 当前发音口音。
  ///
  /// @var PronunciationAccent
  ///
  final PronunciationAccent accent;

  ///
  /// 复习记录存储；正式环境使用全局实例，测试可注入独立通道。
  ///
  /// @var ReviewRecordStore?
  ///
  final ReviewRecordStore? recordStore;

  ///
  /// 复习模块本局的会话；从词库底部进入的普通练习为 null。
  ///
  /// 它同时决定三件事：进度存到哪张表、复习记录归到哪一局、
  /// 以及答题要不要推进单词的复习时间（巩固局不推进）。
  ///
  /// @var ReviewSession?
  ///
  final ReviewSession? reviewSession;

  ///
  /// 复习会话存储；只有 [reviewSession] 非空时才会用到。
  ///
  /// @var ReviewSessionStore?
  ///
  final ReviewSessionStore? reviewSessionStore;

  ///
  /// 候选项缓存存储；正式环境使用 SQLite，测试可注入独立通道。
  ///
  /// @var ListeningMeaningOptionCacheStore?
  ///
  final ListeningMeaningOptionCacheStore? optionCacheStore;

  ///
  /// 从首页“继续”入口传入的历史会话；null 表示开始一轮新听音辨义。
  ///
  /// @var LearningSession?
  ///
  final LearningSession? initialSession;

  ///
  /// 学习会话存储；正式环境使用 SQLite，测试可注入内存实现。
  ///
  /// @var LearningSessionStore?
  ///
  final LearningSessionStore? sessionStore;

  ///
  /// 已答出的同词性中文释义之间使用的全角分隔符。
  ///
  /// @var String
  ///
  final String definitionSeparator;

  ///
  /// 创建听音辨义页面状态。
  ///
  /// @return `State<ListeningMeaningPage>` 管理答题、播放和恢复流程的状态对象。
  ///
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
  ///
  /// @var Random
  ///
  final Random _random = Random(20260727);

  ///
  /// 当前单词在本轮固定列表中的下标。
  ///
  /// @var int
  ///
  int _wordIndex = 0;

  ///
  /// 当前正在进行拼写选择还是释义选择。
  ///
  /// @var ListeningMeaningStage
  ///
  ListeningMeaningStage _stage = ListeningMeaningStage.word;

  ///
  /// 当前词性组在有效释义列表中的下标。
  ///
  /// @var int
  ///
  int _meaningIndex = 0;

  ///
  /// 当前中文释义在词性组内部的下标。
  ///
  /// @var int
  ///
  int _definitionIndex = 0;

  ///
  /// 拼写阶段已经通过提示公开的开头字母数量。
  ///
  /// @var int
  ///
  int _hintLevel = 0;

  ///
  /// 整轮累计答错次数，供完成状态页展示。
  ///
  /// @var int
  ///
  int _errors = 0;

  ///
  /// 当前单词累计选错候选项的次数，每个新词都会重置。
  ///
  /// @var int
  ///
  int _currentWrong = 0;

  ///
  /// 当前单词累计使用提示的次数，每个新词都会重置。
  ///
  /// @var int
  ///
  int _currentHints = 0;

  ///
  /// 本轮已经完成的单词主键，退出时交给首页定向刷新。
  ///
  /// @var `Set<int>`
  ///
  final Set<int> _reviewedWordIds = <int>{};

  ///
  /// 是否已经提交最后一个单词并进入完成状态页。
  ///
  /// @var bool
  ///
  bool _isDone = false;

  ///
  /// 当前单词是否已经完成全部拼写和释义步骤。
  ///
  /// @var bool
  ///
  bool _isCurrentWordComplete = false;

  ///
  /// 是否正在提交当前题，用于阻止连续点击产生重复记录。
  ///
  /// @var bool
  ///
  bool _isSavingCompletion = false;

  ///
  /// 当前单词的发音是否仍在播放。
  ///
  /// @var bool
  ///
  bool _isPlaying = false;

  ///
  /// 当前音频请求代次，只允许最新请求更新播放状态。
  ///
  /// @var int
  ///
  int _playGeneration = 0;

  /// 当前进入听音辨义页面后是否已经提示过系统 TTS。
  /// @var bool
  bool _hasShownTtsNotice = false;

  ///
  /// 中间信息面板当前展示的反馈文案。
  ///
  /// @var String
  ///
  String _feedback = '';

  ///
  /// 反馈语义颜色，null 表示使用普通次要文字色。
  ///
  /// @var Color?
  ///
  Color? _feedbackColor;

  ///
  /// 当前拼写或释义步骤展示的四个候选项。
  ///
  /// @var `List<ListeningMeaningOption>`
  ///
  List<ListeningMeaningOption> _options = const [];

  ///
  /// 已经选错的候选文本集合，界面会标红并禁用这些项。
  ///
  /// @var `Set<String>`
  ///
  final Set<String> _wrongOptions = <String>{};

  ///
  /// 候选缓存读取代次，阻止旧异步结果覆盖已经切换的新题。
  ///
  /// @var int
  ///
  int _optionLoadGeneration = 0;

  ///
  /// 当前候选是否直接来自恢复快照，避免首帧重新打乱顺序。
  ///
  /// @var bool
  ///
  bool _restoredExactOptions = false;

  ///
  /// 当前正在听音辨义的单词。
  ///
  /// @return Word 听音辨义列表当前下标对应的单词。
  ///
  Word get _currentWord => widget.words[_wordIndex];

  ///
  /// 正式页面复用单例，测试传入独立 Store 后不会触碰真实原生通道。
  ///
  /// @return ReviewRecordStore 当前页面实际使用的复习记录 Store。
  ///
  ReviewRecordStore get _recordStore =>
      widget.recordStore ?? LocalReviewRecordStore.instance;

  ///
  /// 正式页面复用 SQLite 单例，测试可传入自定义 MethodChannel。
  ///
  /// @return ListeningMeaningOptionCacheStore 当前页面实际使用的候选缓存 Store。
  ///
  ListeningMeaningOptionCacheStore get _optionCacheStore =>
      widget.optionCacheStore ?? ListeningMeaningOptionCacheStore.instance;

  ///
  /// 正式页面使用 SQLite 单例，Widget 测试可传入内存 Store。
  ///
  /// @return LearningSessionStore 当前页面实际使用的学习会话 Store。
  ///
  LearningSessionStore get _sessionStore =>
      widget.sessionStore ?? LocalLearningSessionStore.instance;

  ///
  /// 正式页面使用 SQLite 单例，Widget 测试可传入内存 Store。
  ///
  /// @return ReviewSessionStore 当前页面实际使用的复习会话 Store。
  ///
  ReviewSessionStore get _reviewSessionStore =>
      widget.reviewSessionStore ?? LocalReviewSessionStore.instance;

  ///
  /// 本轮进度的落盘出口，在 initState 里按入口类型创建一次。
  ///
  /// 从首页复习模块进来就写复习会话（有成败），从词库底部进来就写长期会话
  /// （做完即删）。页面其余代码只调用它的 save / finish，不关心区别。
  ///
  /// @var SessionProgressSink
  ///
  late final SessionProgressSink _progress;

  ///
  /// 本轮记录归属的复习模块。
  ///
  /// 从词库底部进入的普通练习同样按「听音辨义」归类：它确实是在练这个玩法，
  /// 记录该计入今日统计。首页四张卡片的三态来自会话表而不是记录表，
  /// 所以普通练习不会让今天的模块任务凭空变成「已完成」。
  ///
  /// @return ReviewModule 写入记录时使用的模块标识。
  ///
  ReviewModule get _recordModule => ReviewModule.listeningMeaning;

  ///
  /// 本轮答题是否需要推进单词的复习时间。
  ///
  /// 只有「无限巩固练习」不推进——那批词里混着明天要背的，推进了明天就选不到。
  /// 普通练习和每日主线都正常推进。
  ///
  /// @return bool 需要推进时返回 true。
  ///
  bool get _updatesReviewedAt =>
      widget.reviewSession?.updatesReviewedAt ?? true;

  ///
  /// 获取当前单词中包含有效释义的词性组。
  ///
  /// @return `List<Meaning>` 至少包含一条释义的 Meaning 列表。
  ///
  List<Meaning> get _availableMeanings => _currentWord.meanings
      .where((meaning) => meaning.definitions.isNotEmpty)
      .toList(growable: false);

  ///
  /// 当前拼写中的真实英文字母数量；空格和连字符不会生成占位槽。
  ///
  /// @return int 当前拼写中的英文字母数量。
  ///
  int get _currentWordLetterCount => _currentWord.spelling.runes
      .map((codePoint) => String.fromCharCode(codePoint))
      .where((character) => RegExp(r'^[A-Za-z]$').hasMatch(character))
      .length;

  ///
  /// 初始化听音辨义页面并恢复可用的历史状态。
  ///
  /// @return void
  ///
  @override
  void initState() {
    super.initState();
    // 监听 App 前后台变化，后台停止音频并让下次播放重新提示 TTS。
    WidgetsBinding.instance.addObserver(this);
    // 按入口类型选定进度出口：复习模块写复习会话，词库底部写长期会话。
    final reviewSession = widget.reviewSession;
    _progress = reviewSession == null
        ? LearningSessionProgressSink(
            store: _sessionStore,
            type: LearningSessionType.listeningMeaning,
            wordIds: widget.words.map((word) => word.id),
            session: widget.initialSession,
          )
        : ReviewSessionProgressSink(
            store: _reviewSessionStore,
            session: reviewSession,
          );
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
        unawaited(_restoreOrCreateCurrentOptionCache());
      }
      // 完成待提交态不自动重播，普通小题进入后保持原有自动发音体验。
      if (!_isCurrentWordComplete) unawaited(_playAudio());
    });
  }

  ///
  /// 从历史会话恢复当前听音辨义状态；所有动态字段都经过边界校验。
  ///
  /// @return void
  ///
  void _restoreInitialSession() {
    // 出口给出的快照为空就是一次全新的听音辨义。
    final state = _progress.initialState;
    if (state.isEmpty) return;
    // 先恢复单词下标，后续释义边界都依赖当前单词。
    _wordIndex = readLearningSessionInt(
      state['wordIndex'],
      fallback: 0,
    ).clamp(0, widget.words.length - 1);
    // 只有明确的 definition 才进入释义阶段，其余坏值安全回到拼写阶段。
    _stage = state['stage'] == ListeningMeaningStage.definition.name
        ? ListeningMeaningStage.definition
        : ListeningMeaningStage.word;
    // 当前单词没有可答释义时不能恢复到 definition，否则 getter 会越界。
    if (_availableMeanings.isEmpty) _stage = ListeningMeaningStage.word;
    if (_stage == ListeningMeaningStage.definition) {
      _meaningIndex = readLearningSessionInt(
        state['meaningIndex'],
        fallback: 0,
      ).clamp(0, _availableMeanings.length - 1);
      _definitionIndex = readLearningSessionInt(
        state['definitionIndex'],
        fallback: 0,
      ).clamp(0, _availableMeanings[_meaningIndex].definitions.length - 1);
    }
    // 计数都不能为负数；提示级别额外受当前单词字母数约束。
    _hintLevel = readLearningSessionInt(
      state['hintLevel'],
      fallback: 0,
    ).clamp(0, _currentWordLetterCount);
    _errors = max(0, readLearningSessionInt(state['errors'], fallback: 0));
    _currentWrong = max(
      0,
      readLearningSessionInt(state['currentWrong'], fallback: 0),
    );
    _currentHints = max(
      0,
      readLearningSessionInt(state['currentHints'], fallback: 0),
    );
    _isCurrentWordComplete = state['isCurrentWordComplete'] is bool
        ? state['isCurrentWordComplete']! as bool
        : false;
    // 错误项文本恢复后仍保持红色禁用，避免退出页面就能重新点同一个错项。
    final rawWrongOptions = state['wrongOptions'];
    if (rawWrongOptions is List) {
      _wrongOptions.addAll(rawWrongOptions.whereType<String>());
    }
    // 优先恢复快照中的提示文字，让释义首字提示和“正确”反馈也保持离开前状态。
    final savedFeedback = state['feedback'];
    final savedFeedbackTone = state['feedbackTone'];
    if (savedFeedback is String) {
      _feedback = savedFeedback;
      _feedbackColor = switch (savedFeedbackTone) {
        'danger' => AppTokens.danger,
        'success' => const Color(0xFF2FB344),
        _ => null,
      };
    } else if (_isCurrentWordComplete) {
      // 兼容尚未保存 feedback 字段的早期快照。
      _feedback = '本词完成！';
      _feedbackColor = const Color(0xFF2FB344);
    } else if (_wrongOptions.isNotEmpty) {
      _feedback = '答错 · 难度将 +1';
      _feedbackColor = AppTokens.danger;
    }
    // 候选快照必须恰好四项、只有一个正确项且文本仍匹配当前正确答案。
    final rawOptions = state['options'];
    if (!_isCurrentWordComplete && rawOptions is List) {
      final restored = <ListeningMeaningOption>[];
      for (final rawOption in rawOptions) {
        if (rawOption is! Map ||
            rawOption['text'] is! String ||
            rawOption['isCorrect'] is! bool) {
          restored.clear();
          break;
        }
        restored.add(
          ListeningMeaningOption(
            text: rawOption['text']! as String,
            isCorrect: rawOption['isCorrect']! as bool,
          ),
        );
      }
      final correctOptions = restored
          .where((option) => option.isCorrect)
          .toList();
      // 四个显示文本按去空格和忽略英文大小写判重，历史坏快照不能绕过去重规则。
      final normalizedOptionTexts = restored
          .map((option) => option.text.trim().toLowerCase())
          .where((text) => text.isNotEmpty)
          .toSet();
      if (restored.length == 4 &&
          normalizedOptionTexts.length == 4 &&
          correctOptions.length == 1 &&
          correctOptions.single.text == _currentCorrectAnswer) {
        _options = List<ListeningMeaningOption>.unmodifiable(restored);
        _restoredExactOptions = true;
      }
    }
  }

  ///
  /// 把当前答题状态写入 SQLite；页面交互先完成，持久化失败不阻断答题。
  ///
  /// @return `Future<void>` 会话保存完成后的异步结果。
  ///
  Future<void> _persistSession() => _progress.save(
    // 完成页已经结算过这一局，禁止 dispose 再把状态写回「进行中」。
    enabled: !_isDone,
    // 本轮累计错误数决定整局的成败，必须和进度一起落盘。
    wrongTotal: _errors,
    // state 相当于小程序 Page.data 的可持久化子集。
    state: <String, Object?>{
      // 保存当前单词在固定学习列表中的下标。
      'wordIndex': _wordIndex,
      // 保存拼写或释义阶段。
      'stage': _stage.name,
      // 保存当前词性组下标。
      'meaningIndex': _meaningIndex,
      // 保存当前词性组中的释义下标。
      'definitionIndex': _definitionIndex,
      // 保存已经公开的拼写提示字母数。
      'hintLevel': _hintLevel,
      // 保存本轮累计错误数，供完成页统计。
      'errors': _errors,
      // 保存当前单词的错误次数，提交记录时使用。
      'currentWrong': _currentWrong,
      // 保存当前单词的提示次数，提交记录时使用。
      'currentHints': _currentHints,
      // 保存当前单词是否已完成并等待点击下一题。
      'isCurrentWordComplete': _isCurrentWordComplete,
      // 保存用户当前看到的提示或结果反馈。
      'feedback': _feedback,
      // 颜色不能直接编码 JSON，因此保存可恢复的语义名称。
      'feedbackTone': _feedbackColor == AppTokens.danger
          ? 'danger'
          : (_feedbackColor == const Color(0xFF2FB344) ? 'success' : 'neutral'),
      // 保存已经选错的文本，恢复后继续保持红色禁用。
      'wrongOptions': _wrongOptions.toList(growable: false),
      // 保存四个候选的文本、正误和固定顺序。
      'options': <Map<String, Object?>>[
        for (final option in _options)
          // 每个候选转成 JSON 可编码的普通 Map。
          <String, Object?>{'text': option.text, 'isCorrect': option.isCorrect},
      ],
    },
  );

  ///
  /// 整轮跑完后给这一局结算。
  ///
  /// 判定规则很简单：整轮一次都没错（[_errors] 为 0）才算「完成」，
  /// 中途错过任何一次都算「失败」，下次进模块会重开一局从头再来。
  /// 词库底部的普通练习没有成败之分，出口内部会直接把长期快照删掉，
  /// 首页随即隐藏对应的「继续」入口。
  ///
  /// @return `Future<void>` 结算完成后的异步结果。
  ///
  Future<void> _finishSession() => _progress.finish(
    // 一次没错才算这一局过关。
    perfect: _errors == 0,
    wrongTotal: _errors,
  );

  ///
  /// 当前小题的正确答案：拼写阶段是单词，释义阶段是当前中文释义。
  ///
  /// @return String 当前候选列表唯一的正确文本。
  ///
  String get _currentCorrectAnswer => _stage == ListeningMeaningStage.word
      ? _currentWord.spelling
      : _availableMeanings[_meaningIndex].definitions[_definitionIndex];

  ///
  /// 当前小题的稳定缓存 key；内容字段参与 key，数据被编辑后会自然切换到新缓存。
  ///
  /// @return String 可唯一标识当前拼写题或释义题的缓存键。
  ///
  String get _currentOptionCacheKey {
    // 拼写题由版本、类型、单词主键和当前拼写共同确定。
    if (_stage == ListeningMeaningStage.word) {
      return jsonEncode(<Object?>[
        'v1',
        'word',
        _currentWord.id,
        _currentWord.spelling,
      ]);
    }
    // 释义题还要区分 Meaning 与其中的第几条定义，避免同词多义互相覆盖。
    final meaning = _availableMeanings[_meaningIndex];
    return jsonEncode(<Object?>[
      'v1',
      'definition',
      _currentWord.id,
      _currentWord.spelling,
      meaning.id,
      meaning.index,
      meaning.pos,
      _definitionIndex,
      _currentCorrectAnswer,
    ]);
  }

  ///
  /// 按当前阶段生成指定数量的干扰项。
  ///
  /// @param  int  count 需要生成的干扰项数量。
  /// @return `List<String>` 与当前正确答案不同的候选文本。
  ///
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
          );
  }

  ///
  /// 用指定干扰项和正确答案位置组装完整四选一。
  ///
  /// @param  `List<String>?`  distractors 可复用的固定干扰项；为空时现场生成。
  /// @param  int?  correctIndex 正确答案的固定下标；为空时只在首次生成时随机一次。
  /// @return `List<ListeningMeaningOption>` 一个正确项加三个干扰项的只读列表。
  ///
  List<ListeningMeaningOption> _buildOptions({
    List<String>? distractors,
    int? correctIndex,
  }) {
    // 未传缓存时同步生成，确保页面首帧已经有完整四选一。
    final resolvedDistractors = distractors ?? _generateCurrentDistractors();
    // 候选生成器固定返回三个唯一干扰项，并优先使用同长度与相似度规则。
    // 先保持三个干扰项的缓存顺序，稍后再把正确答案插入其固定位置。
    final options = <ListeningMeaningOption>[
      for (final distractor in resolvedDistractors.take(3))
        ListeningMeaningOption(text: distractor, isCorrect: false),
    ];
    // 没有历史位置表示首次生成，用随机位置避免所有正确答案总在同一行。
    final resolvedCorrectIndex =
        correctIndex ?? _random.nextInt(options.length + 1);
    // 缓存读取前已经校验范围；这里仍用 clamp 防止未来其他调用传入坏下标。
    final safeCorrectIndex = resolvedCorrectIndex
        .clamp(0, options.length)
        .toInt();
    // 正确答案文本永远取当前模型，只把位置作为缓存的一部分长期复用。
    options.insert(
      safeCorrectIndex,
      ListeningMeaningOption(text: _currentCorrectAnswer, isCorrect: true),
    );
    // 再次冻结列表，状态层只在进入下一小题时整体替换它。
    return List<ListeningMeaningOption>.unmodifiable(options);
  }

  ///
  /// 从当前四个可见候选提取可持久化的三个干扰项和正确答案位置。
  ///
  /// @param  `List<ListeningMeaningOption>`  options 当前完整四选一。
  /// @return ListeningMeaningOptionCacheEntry 可直接写入 SQLite 的缓存数据。
  ///
  ListeningMeaningOptionCacheEntry _cacheEntryFromOptions(
    List<ListeningMeaningOption> options,
  ) {
    // 标准列表只有一个正确项；若未来调用给出坏数据，indexWhere 的 -1 会被 Store 拒绝。
    final correctIndex = options.indexWhere((option) => option.isCorrect);
    // 移除正确答案后，三个干扰项仍保持它们在页面上的相对顺序。
    final distractors = options
        .where((option) => !option.isCorrect)
        .map((option) => option.text)
        .toList(growable: false);
    return ListeningMeaningOptionCacheEntry(
      distractors: List<String>.unmodifiable(distractors),
      correctIndex: correctIndex,
    );
  }

  ///
  /// 判断 SQLite 返回的缓存是否仍能安全组成标准四选一。
  ///
  /// @param  ListeningMeaningOptionCacheEntry  cache 缓存中的三个干扰项和正确答案位置。
  /// @param  String  correct 当前小题正确答案。
  /// @return bool 候选数量、唯一性和排除正确答案是否全部有效。
  ///
  bool _isValidCachedOptions(ListeningMeaningOptionCacheEntry cache, String correct) {
    // 取出三个干扰项，下面统一执行数量和文本检查。
    final distractors = cache.distractors;
    // 必须精确三项，否则继续使用页面已经同步生成的标准结果。
    if (distractors.length != 3) return false;
    // null 只允许表示旧版本缓存；已有位置必须严格处于四个按钮范围内。
    final correctIndex = cache.correctIndex;
    if (correctIndex != null && (correctIndex < 0 || correctIndex >= 4)) {
      return false;
    }
    // 英文忽略大小写，中文转换后不受影响；同时排除正确答案与重复项。
    final normalizedCorrect = correct.trim().toLowerCase();
    final normalized = distractors
        .map((value) => value.trim().toLowerCase())
        .toSet();
    return normalized.length == 3 && !normalized.contains(normalizedCorrect);
  }

  ///
  /// 命中缓存就替换同步结果；首次遇到该题则把当前生成结果保存到 SQLite。
  ///
  /// @return `Future<void>` 缓存读取或创建完成后的异步结果。
  ///
  Future<void> _restoreOrCreateCurrentOptionCache() async {
    // 每次进入新小题先领取一个代次号，用来识别晚到的旧请求。
    final generation = ++_optionLoadGeneration;
    // 在 await 前抓取当前题身份与数据，后续切题不会改变这些局部变量。
    final cacheKey = _currentOptionCacheKey;
    final correct = _currentCorrectAnswer;
    final wordId = _currentWord.id;
    // 首帧同步生成的数据已经包含完整顺序，缓存缺失或旧缓存升级时可以直接保存。
    final generatedCache = _cacheEntryFromOptions(_options);
    try {
      // 从原生 SQLite 查询这道题以前使用过的候选名字和正确答案位置。
      final cachedOptions = await _optionCacheStore.getOptions(cacheKey);
      // 命中合法缓存时，只允许仍处于同一小题的请求更新页面。
      if (cachedOptions != null &&
          _isValidCachedOptions(cachedOptions, correct)) {
        if (!mounted || generation != _optionLoadGeneration) return;
        // 版本 8 之前只保存三个名字；沿用当前首帧位置并在本次读取后补存。
        final resolvedCorrectIndex =
            cachedOptions.correctIndex ?? generatedCache.correctIndex!;
        setState(() {
          // 正确答案继续取最新模型，其余名字和四个按钮位置全部按缓存恢复。
          _options = _buildOptions(
            distractors: cachedOptions.distractors,
            correctIndex: resolvedCorrectIndex,
          );
        });
        // 候选顺序属于可恢复状态，缓存替换后同步保存当前页面快照。
        unawaited(_persistSession());
        // 旧缓存缺少正确答案位置时原地升级；三个已有干扰项不会改变。
        if (cachedOptions.correctIndex == null) {
          await _optionCacheStore.saveOptions(
            cacheKey: cacheKey,
            wordId: wordId,
            distractors: cachedOptions.distractors,
            correctIndex: resolvedCorrectIndex,
          );
        }
        return;
      }
      // 没有缓存或缓存损坏时，保存首帧已经显示的名字和完整位置。
      await _optionCacheStore.saveOptions(
        cacheKey: cacheKey,
        wordId: wordId,
        distractors: generatedCache.distractors,
        correctIndex: generatedCache.correctIndex!,
      );
    } catch (error) {
      // 缓存是体验增强，不应因原生通道异常阻断答题；保留同步生成结果即可。
      debugPrint('读取或保存听音辨义候选缓存失败：$error');
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
  ///
  /// @param  bool  interrupt 是否允许当前请求打断正在播放的旧音频。
  /// @return `Future<void>` 当前音频播放结束或被打断后的异步结果。
  ///
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
      await widget.audioPlayer.play(_currentWord.spelling, widget.accent);
      // 只有真正由离线 TTS 成功朗读时才显示一次来源提示。
      if (!_hasShownTtsNotice &&
          await widget.audioPlayer.consumeLastPlaybackUsedTts()) {
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
          await widget.audioPlayer.play(_currentWord.spelling, widget.accent);
          // 解码失败重试成功后，同样检查真实播放来源。
          if (!_hasShownTtsNotice &&
              await widget.audioPlayer.consumeLastPlaybackUsedTts()) {
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

  /// App 离开前台时停止当前发音，并重置下一次播放的 TTS 提示状态。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _hasShownTtsNotice = false;
    ++_playGeneration;
    if (mounted) {
      // 退后台时同步更新内存和界面状态，回到前台后播放按钮保持暂停样式。
      setState(() => _isPlaying = false);
    }
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
  }

  ///
  /// 点击提示：拼写阶段逐字公开，释义阶段公开首字。
  ///
  /// @return void
  ///
  void _showHint() {
    // 整轮或当前单词已经完成时，不再改变提示状态。
    if (_isDone || _isCurrentWordComplete) return;
    if (_stage == ListeningMeaningStage.word) {
      setState(() {
        _hintLevel = min(
          // 至少公开一个字母；多字母单词最多保留最后一个槽位不公开。
          max(1, _currentWordLetterCount - 1),
          _hintLevel + 1,
        );
        // 每点一次提示都计入当前单词的提示次数。
        _currentHints++;
        _feedback = '已显示开头字母';
        _feedbackColor = null;
      });
      // 提示级别和点击次数会影响当前题展示与最终记录，必须立即保存。
      unawaited(_persistSession());
      return;
    }
    final definition =
        _availableMeanings[_meaningIndex].definitions[_definitionIndex];
    setState(() {
      // 释义阶段的提示同样计入次数。
      _currentHints++;
      _feedback = definition.isEmpty ? '当前释义为空' : '提示：以「${definition[0]}」开头';
      _feedbackColor = null;
    });
    // 释义提示次数同样进入当前会话快照。
    unawaited(_persistSession());
  }

  ///
  /// 选择答案：错项变红并禁用；正确时推进到下一小题。
  ///
  /// 触觉反馈策略：
  /// - 选错：heavyImpact（重震），配合选项抖动动画，错误感强烈。
  /// - 选对：lightImpact（轻触），页面立即切换为新题，视觉变化即反馈。
  ///
  /// @param  ListeningMeaningOption  option 用户点击的候选项。
  /// @return void
  ///
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
      // 保存错项文本与错误计数，重新进入后不能通过退出页面清除错误。
      unawaited(_persistSession());
      return;
    }

    // 轻触震动确认选对，不拖延答题节奏。
    HapticFeedback.lightImpact();

    if (_stage == ListeningMeaningStage.word) {
      if (_availableMeanings.isEmpty) {
        // 没有释义的单词在拼写答对后就完成，等待用户手动进入下一题。
        _completeCurrentWord();
        return;
      }
      setState(() {
        _stage = ListeningMeaningStage.definition;
        _meaningIndex = 0;
        _definitionIndex = 0;
        _wrongOptions.clear();
        _feedback = '正确！';
        _feedbackColor = const Color(0xFF2FB344);
        _options = _buildOptions();
      });
      // 拼写答对并进入释义阶段后立即保存新的小题下标和候选顺序。
      unawaited(_persistSession());
      // 当前小题已经切到第一条释义，异步恢复或创建它自己的稳定候选缓存。
      unawaited(_restoreOrCreateCurrentOptionCache());
      return;
    }

    var nextMeaning = _meaningIndex;
    var nextDefinition = _definitionIndex + 1;
    if (nextDefinition >= _availableMeanings[nextMeaning].definitions.length) {
      nextDefinition = 0;
      nextMeaning++;
    }
    if (nextMeaning >= _availableMeanings.length) {
      // 最后一条释义答对后隐藏选项和工具按钮，显示下一题。
      _completeCurrentWord();
      return;
    }
    setState(() {
      _meaningIndex = nextMeaning;
      _definitionIndex = nextDefinition;
      _wrongOptions.clear();
      _feedback = '正确！';
      _feedbackColor = const Color(0xFF2FB344);
      _options = _buildOptions();
    });
    // 每推进一条释义都更新恢复点。
    unawaited(_persistSession());
    // 下一条释义拥有独立缓存，不能沿用上一条释义的三个干扰项。
    unawaited(_restoreOrCreateCurrentOptionCache());
  }

  ///
  /// 长按候选项后询问是否刷新；确认后保持四选一结构并立即替换当前文本。
  ///
  /// @param  int  optionIndex 用户长按的候选项下标。
  /// @return `Future<void>` 确认、替换和缓存写入启动后的异步结果。
  ///
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
          );
    // 极小或异常词库可能耗尽所有可用变体，此时保留原候选并给出说明。
    if (replacement == null) {
      Toast.show(context, '暂时没有可用的新候选词');
      return;
    }

    // 保存当前题身份，页面更新后异步覆盖同一条 SQLite 缓存。
    final cacheKey = _currentOptionCacheKey;
    final wordId = _currentWord.id;
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
        cacheKey: cacheKey,
        wordId: wordId,
        options: updatedOptions,
      ),
    );
  }

  ///
  /// 显示刷新确认框；返回 true 表示用户确认替换当前候选词。
  ///
  /// @param  String  optionText 当前候选项文本。
  /// @return `Future<bool>` 用户是否确认刷新。
  ///
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
  /// @param  String  cacheKey 当前小题的稳定缓存键。
  /// @param  int?  wordId 当前单词主键。
  /// @param  `List<ListeningMeaningOption>`  options
  /// @return `Future<void>` 缓存覆盖完成后的异步结果。
  ///
  Future<void> _persistRefreshedOptions({
    required String cacheKey,
    required int? wordId,
    required List<ListeningMeaningOption> options,
  }) async {
    try {
      // 正确答案文本不写缓存，只保存三个干扰项和正确答案当前所在位置。
      final cache = _cacheEntryFromOptions(options);
      await _optionCacheStore.saveOptions(
        cacheKey: cacheKey,
        wordId: wordId,
        distractors: cache.distractors,
        correctIndex: cache.correctIndex!,
      );
    } catch (error) {
      // 页面替换已经完成；记录错误并提示缓存失败，下次进入仍可继续正常答题。
      debugPrint('保存刷新后的听音辨义候选缓存失败：$error');
      if (mounted) Toast.show(context, '候选词已刷新，但缓存保存失败');
    }
  }

  ///
  /// 标记当前单词的拼写和全部释义均已答对。
  ///
  /// @return void
  ///
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
  /// @return `Future<bool>` 数据库事务是否成功；没有主键时返回 true 并跳过写入。
  ///
  Future<bool> _recordCompletion() async {
    // 取出当前单词主键。
    final wordId = _currentWord.id;
    // 没有主键无法落库；它通常只会出现在尚未保存的测试数据中。
    if (wordId == null) return true;
    try {
      // 等待原生事务真正结束后才允许切题，确保首页回刷时能读取到最新数据。
      // 连对次数、难度与复习时间都由原生在同一个事务里一并更新。
      await _recordStore.add(
        wordId: wordId,
        module: _recordModule,
        // 复习模块的记录挂到本局会话上；词库底部的普通练习不属于任何一局。
        sessionId: widget.reviewSession?.id,
        // 本次选错次数为 0 时原生判定为"一气呵成"，见上方口径说明。
        wrongCount: _currentWrong,
        hintCount: _currentHints,
        // 巩固局不推进复习时间，否则明天那批词今天就被消耗掉了。
        updateReviewedAt: _updatesReviewedAt,
      );
      // 只有事务成功后才把 id 带回首页，避免首页回刷一条并未更新的数据。
      _reviewedWordIds.add(wordId);
      // true 告诉按钮流程可以安全进入下一题。
      return true;
    } catch (error) {
      // 保留日志便于开发时定位原生数据库异常。
      debugPrint('记录听音辨义结果失败：$error');
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
  ///
  /// @return void
  ///
  void _exitListeningMeaning() {
    // 用户点击下一题后必须等事务结束；保存中主动返回会让首页漏掉最新回刷 id。
    if (_isSavingCompletion) return;
    // 把收集到的 id 列表作为路由结果返回给上一页。
    Navigator.pop(context, _reviewedWordIds.toList());
  }

  ///
  /// 用户点击底部长条按钮后先提交当前结果，再进入下一词或整轮完成页。
  ///
  /// @return `Future<void>` 记录事务与页面推进完成后的异步结果。
  ///
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
      // 释义下标回到第一项。
      _definitionIndex = 0;
      // 新单词还未使用提示。
      _hintLevel = 0;
      // 清除上一题的错误禁用项。
      _wrongOptions.clear();
      // 新单词的错误/提示计数归零，重新开始统计。
      _currentWrong = 0;
      _currentHints = 0;
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
    unawaited(_restoreOrCreateCurrentOptionCache());
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
  ///
  /// @return void
  ///
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
      // 释义下标回到第一项。
      _definitionIndex = 0;
      // 收起此前公开的开头字母。
      _hintLevel = 0;
      // 清除被标红禁用的错误候选项。
      _wrongOptions.clear();
      // 本题错误/提示计数归零，重做后按新一次成绩落库。
      _currentWrong = 0;
      _currentHints = 0;
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
    unawaited(_restoreOrCreateCurrentOptionCache());
    // 与进入新题一致自动发音；同样要打断可能仍在播放的奖励音频。
    unawaited(_playAudio(interrupt: true));
  }

  ///
  /// 构建当前单词的完整步骤清单：先“听音选词”，再逐条词性释义。
  ///
  /// 每个步骤都从一开始列出，状态随答题进度在 未开始/进行中/已完成 之间变化。
  /// 组件只负责按状态渲染，不关心答题下标。
  ///
  /// @return `List<ListeningMeaningStep>` 当前单词的不可变步骤列表。
  ///
  List<ListeningMeaningStep> _buildSteps() {
    // 步骤集合从“听音选词”开始，拼写答对后它转为已完成。
    final steps = <ListeningMeaningStep>[
      ListeningMeaningStep(
        kind: ListeningMeaningStepKind.word,
        title: '听音选词',
        // 完成后把正确单词带进步骤，便于在步骤下方直接回显。
        word: _currentWord.spelling,
        // 拼写阶段结束后，单词步骤即视为完成；否则当前就是进行中的那一步。
        status: _stage == ListeningMeaningStage.definition || _isCurrentWordComplete
            ? ListeningMeaningStepStatus.done
            : (_stage == ListeningMeaningStage.word
                  ? ListeningMeaningStepStatus.active
                  : ListeningMeaningStepStatus.pending),
      ),
    ];
    // 每个词性释义都对应一个独立步骤，进入新词时一次性全部列出。
    for (
      var meaningIndex = 0;
      meaningIndex < _availableMeanings.length;
      meaningIndex += 1
    ) {
      final meaning = _availableMeanings[meaningIndex];
      // 整词完成，或当前下标已跳过该词性，说明这条释义已经全部答对。
      final isMeaningDone =
          _isCurrentWordComplete || meaningIndex < _meaningIndex;
      // 释义阶段且正停留在当前词性时，该步骤处于进行中。
      final isMeaningActive =
          !_isCurrentWordComplete &&
          _stage == ListeningMeaningStage.definition &&
          meaningIndex == _meaningIndex;
      // 已答出的释义：完成步骤显示全部，进行中步骤只显示已答对的部分。
      List<String>? definitions;
      if (isMeaningDone) {
        definitions = List<String>.unmodifiable(meaning.definitions);
      } else if (isMeaningActive) {
        definitions = List<String>.unmodifiable(
          meaning.definitions.take(_definitionIndex),
        );
      }
      // 没有词性的旧数据用“释义”兜底，避免步骤出现空标题。
      final pos = meaning.pos.trim().isEmpty ? '释义' : meaning.displayPos;
      steps.add(
        ListeningMeaningStep(
          kind: ListeningMeaningStepKind.meaning,
          title: '释义',
          status: isMeaningDone
              ? ListeningMeaningStepStatus.done
              : (isMeaningActive
                    ? ListeningMeaningStepStatus.active
                    : ListeningMeaningStepStatus.pending),
          pos: pos,
          definitions: definitions,
        ),
      );
    }
    // 冻结列表，展示组件只读取，不修改步骤状态。
    return List<ListeningMeaningStep>.unmodifiable(steps);
  }

  ///
  /// 返回当前答题阶段的用户可见名称。
  ///
  /// @return String “听音选词”或“释义”。
  ///
  String get _stageLabel {
    // 完成后的提示不再要求选择，只说明当前单词已完成。
    if (_isCurrentWordComplete) return '当前单词已完成';
    // 拼写阶段引导用户通过发音选出单词。
    if (_stage == ListeningMeaningStage.word) return '听音，选出正确的单词';
    final meaning = _availableMeanings[_meaningIndex];
    final pos = meaning.pos.trim().isEmpty ? '释义' : meaning.displayPos;
    return '$pos · 选择释义 ${_definitionIndex + 1}/${meaning.definitions.length}';
  }

  ///
  /// 释放音频请求并补写尚未完成的页面状态。
  ///
  /// @return void
  ///
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
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 当前听音辨义状态对应的完整界面。
  ///
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
              else
                Expanded(child: _buildQuestion(tokens)),
            ],
          ),
        ),
      ),
    );
  }

  ///
  /// 构建顶栏与进度条，布局结构和随身听页面保持一致。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @param  double  progress 当前单词在学习列表中的进度比例。
  /// @return Widget 返回按钮、题量、难度徽章和进度条。
  ///
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
          // Row 将返回按钮、中央进度和右侧占位区排成一行。
          child: Row(
            children: [
              // 返回按钮的 34 像素点击画布直接贴齐左侧页面边距。
              _PlainIconButton(
                key: const Key('close-listeningMeaning'),
                icon: TablerIcons.chevronLeft,
                alignment: Alignment.centerLeft,
                onTap: _exitListeningMeaning,
              ),
              // Expanded 占用左右等宽画布之间的全部空间。
              Expanded(
                // 当前题号放在中间，不再由左侧“听音辨义”标题把它挤到右边。
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
              // 右侧保留与返回按钮等宽的空白画布，让中央题号继续保持绝对居中。
              SizedBox(
                width: ListeningMeaningLayout.headerButtonSize,
                height: ListeningMeaningLayout.headerButtonSize,
              ),
            ],
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
  /// 构建可滚动题目区、透明播放热区和悬浮候选区。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 占满顶部信息区以下空间的题目 Stack。
  ///
  Widget _buildQuestion(AppTokens tokens) {
    // 底部控件虽然脱离普通布局，但滚动内容仍需保留等高的尾部内边距，
    // 否则较长 Steps 的最后几行会被悬浮候选区遮住。
    final bottomOverlayHeight = _isCurrentWordComplete
        ? ListeningMeaningLayout.nextControlsExtent
        : ListeningMeaningLayout.bottomControlsExtent;
    // Stack 让底部控件覆盖滚动内容，同时保留整块内容区的播放热区。
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
                  bottomOverlayHeight + ListeningMeaningLayout.questionVerticalInset,
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
                      revealedLetterCount: _hintLevel,
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
        // 第二层最后绘制，相当于 zIndex:100；Positioned 使其脱离 Stack 普通布局，
        // 因此候选区不会压缩上面的内容层，并且按钮会优先于透明播放层接收点击。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _isCurrentWordComplete
              ? _buildNextQuestionButton(tokens)
              : _buildBottomControls(tokens),
        ),
        // 第三层：难度提示横幅，绘制在候选区之上的悬浮层（纯界面提示，不碰数据库）。
        // 悬浮在候选区正上方，既显眼又贴合现有卡片视觉，不与内容争夺布局空间。
        Positioned(
          left: ListeningMeaningLayout.pageInset,
          right: ListeningMeaningLayout.pageInset,
          // 紧贴候选控件顶边上方，露出完整横幅。
          bottom: bottomOverlayHeight + 12,
          child: Align(
            alignment: Alignment.center,
            child: _buildDifficultyHintBanner(tokens),
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
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 提示横幅或零尺寸占位。
  ///
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
  ///
  /// @return `({Color color, IconData icon, String? text})` 横幅视觉元组。
  ///
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
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 候选四选一或完成后的下一题操作区。
  ///
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
      // 固定两栏总高度，左右两组控件都以同一条底边向上堆叠。
      child: SizedBox(
        key: const Key('listening-meaning-control-columns'),
        height: ListeningMeaningLayout.optionStackHeight,
        // Row 将左侧四个候选词和右侧两个操作按钮分成两栏。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左栏获得三份宽度，是右栏的三倍。
            Expanded(
              key: const Key('listening-meaning-option-column'),
              flex: ListeningMeaningLayout.optionColumnFlex,
              // 候选组外包一层 AnimatedSwitcher：进入下一小题 / 下一词 / 刷新候选时，
              // 旧候选组向上推出、新候选组从下方升入，过渡期同时渲染两组四个按钮，
              // 形成清晰的「上一轮离场、本轮入场」层次感，不再整体下沉再回弹（仿 Duolingo / Quizlet 的整组切换）。
              child: AnimatedSwitcher(
                // 整组过渡时长，210ms（较原 320ms 减少约三分之一）让切换更利落。
                duration: const Duration(milliseconds: 210),
                // 进出用「方向一致的上推」：旧组向上淡出离场，新组从下方淡入归位，
                // 二者在垂直方向一进一退，衔接顺滑且层次分明。
                transitionBuilder: (child, animation) {
                  // AnimatedSwitcher 对离场子组件传入反向动画（status 为 reverse），
                  // 据此区分「离场」与「入场」并施加不同方向的位移与透明度。
                  final isLeaving = animation.status == AnimationStatus.reverse;
                  // 离场：从原位上移 16% 高度并淡出，像被推上去；入场：从下方 16% 升入归位并淡入。
                  final slide = isLeaving
                      ? Tween<Offset>(
                          begin: Offset.zero,
                          end: const Offset(0, -0.16),
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeInCubic,
                          ),
                        )
                      : Tween<Offset>(
                          begin: const Offset(0, 0.16),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        );
                  final fade = isLeaving
                      ? Tween<double>(begin: 1, end: 0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeInCubic,
                          ),
                        )
                      : Tween<double>(begin: 0, end: 1).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        );
                  return FadeTransition(
                    opacity: fade,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                // 用当前四个候选文本拼接成唯一 Key；文本变化即触发整组过渡，文本不变则不重启动画。
                child: Column(
                  key: ValueKey(
                    'listening-meaning-option-group-${_options.map((option) => option.text).join('|')}',
                  ),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var index = 0; index < _options.length; index++) ...[
                      // 每个选项由独立 _OptionCard 管理，支持错选抖动动画。
                      _OptionCard(
                        key: ValueKey(
                          'listening-meaning-option-$index-${_options[index].text}',
                        ),
                        option: _options[index],
                        index: index,
                        wrong: _wrongOptions.contains(_options[index].text),
                        onTap: () => _pickOption(_options[index]),
                        // 长按任意候选都进入同一刷新确认流程，不暴露正确答案身份。
                        onLongPress: () => _requestOptionRefresh(index),
                      ),
                      // 最后一行下方不再添加多余间距，它的底边就是整个控制区底边。
                      if (index < _options.length - 1)
                        const SizedBox(height: ListeningMeaningLayout.optionGap),
                    ],
                  ],
                ),
              ),
            ),
            // 两栏之间只使用正常布局间距，不使用任何偏移。
            const SizedBox(width: ListeningMeaningLayout.columnGap),
            // 右栏获得一份宽度，把主要空间留给可能较长的候选词。
            Expanded(
              key: const Key('listening-meaning-action-column'),
              flex: ListeningMeaningLayout.actionColumnFlex,
              // end 让播放先贴齐底边，提示再依照间距堆叠到它上方。
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 提示按钮放在播放按钮正上方。
                  _OutlineAction(
                    key: const Key('listening-meaning-hint'),
                    icon: TablerIcons.bulb,
                    label: '提示',
                    foreground: tokens.textMedium,
                    border: tokens.inputBorder,
                    height: ListeningMeaningLayout.actionHeight,
                    horizontalPadding: 8,
                    onTap: _showHint,
                  ),
                  // 两个右侧按钮使用与候选词相同的纵向间距。
                  const SizedBox(height: ListeningMeaningLayout.optionGap),
                  // 播放按钮作为右栏最后一项，底边直接对齐第四个候选词。
                  _OutlineAction(
                    key: const Key('listening-meaning-play'),
                    icon: _isPlaying
                        ? TablerIcons.volume2
                        : TablerIcons.playerPlay,
                    label: '播放',
                    foreground: Colors.white,
                    border: AppTokens.accent,
                    background: AppTokens.accent,
                    height: ListeningMeaningLayout.actionHeight,
                    horizontalPadding: 8,
                    // 底部播放按钮允许打断重播。
                    onTap: () => _playAudio(interrupt: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建当前单词全部答对后的底部操作区：左「再试一次」+ 右「下一题」。
  ///
  /// 两个按钮通过 Expanded 各占一半宽度，中间用 [ListeningMeaningLayout.columnGap]
  /// 留出间距（相当于小程序里 flex:1 + margin 的写法）。
  /// 左侧是次要操作（描边样式），右侧是主操作（蓝色实心）。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 再试一次和下一题的双按钮区域。
  ///
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
                  minimumSize: const Size(0, ListeningMeaningLayout.actionHeight),
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
                  minimumSize: const Size(0, ListeningMeaningLayout.actionHeight),
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
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 整轮完成后的状态页。
  ///
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
  ///
  /// @param  IconData  icon 需要显示的 Tabler 图标。
  /// @param  VoidCallback  onTap 点击回调。
  /// @param  AlignmentGeometry  alignment 图标在画布中的对齐方式。
  ///
  /// @param  Key?  key
  ///
  const _PlainIconButton({
    required this.icon,
    required this.onTap,
    this.alignment = Alignment.center,
    super.key,
  });

  ///
  /// 需要显示的 Tabler 图标。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 用户点击图标画布时执行的回调。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 图标在 34 像素画布中的对齐方式。
  ///
  /// @var AlignmentGeometry
  ///
  final AlignmentGeometry alignment;

  ///
  /// Flutter 每次需要绘制顶栏按钮时调用此方法。
  ///
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 固定点击画布的顶栏图标按钮。
  ///
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
/// 底部提示和播放入口共用的 Tabler 描边操作按钮。
///
class _OutlineAction extends StatelessWidget {
  ///
  /// 构建右侧的提示或播放按钮。
  ///
  /// @param  String  label 按钮文案。
  /// @param  Color  foreground 图标和文字颜色。
  /// @param  Color  border 外边框颜色。
  /// @param  VoidCallback  onTap 点击回调。
  /// @param  double  height 按钮固定高度。
  /// @param  double  horizontalPadding 水平内边距。
  /// @param  Color?  background 可选背景色。
  /// @param  IconData?  icon 可选 Tabler 图标。
  ///
  /// @param  Key?  key
  ///
  const _OutlineAction({
    required this.label,
    required this.foreground,
    required this.border,
    required this.onTap,
    this.height = 32,
    this.horizontalPadding = 16,
    this.background,
    this.icon,
    super.key,
  });

  ///
  /// 仅当按钮具有图标语义时传入 Tabler 图标。
  ///
  /// @var IconData?
  ///
  final IconData? icon;

  ///
  /// 按钮中显示的命令文字。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 图标和文字的前景色。
  ///
  /// @var Color
  ///
  final Color foreground;

  ///
  /// 按钮一像素外边框的颜色。
  ///
  /// @var Color
  ///
  final Color border;

  ///
  /// 可选按钮背景色；播放主操作传入蓝色，提示按钮则沿用卡片色。
  ///
  /// @var Color?
  ///
  final Color? background;

  ///
  /// 点击按钮时执行的业务操作。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 按钮的固定高度，底部操作区使用 48 像素。
  ///
  /// @var double
  ///
  final double height;

  ///
  /// 按钮文字两侧留白，窄右栏使用较紧凑的值。
  ///
  /// @var double
  ///
  final double horizontalPadding;

  ///
  /// Flutter 绘制提示或播放按钮时调用此方法。
  ///
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 统一尺寸的提示或播放按钮。
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前主题的卡片背景色。
    final tokens = AppTokens.of(context);
    // 两种按钮形态共用同一套颜色、边框、留白和文字规则。
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: background ?? tokens.card,
      side: BorderSide(color: border),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    // SizedBox 保证提示和播放在不同图标状态下都保持相同高度。
    return SizedBox(
      height: height,
      // 没有图标时使用普通 OutlinedButton，避免产生空的图标占位。
      child: icon == null
          ? OutlinedButton(
              onPressed: onTap,
              style: buttonStyle,
              child: Text(label),
            )
          // 播放按钮使用带 Tabler 图标的标准形态。
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 15),
              label: Text(label),
              style: buttonStyle,
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
  ///
  /// @param  ListeningMeaningOption  option 当前候选数据。
  /// @param  int  index 候选在四选一列表中的下标。
  /// @param  bool  wrong 是否已经选错。
  /// @param  VoidCallback  onTap 点击答题回调。
  /// @param  VoidCallback  onLongPress 长按刷新回调。
  ///
  /// @param  Key?  key
  ///
  const _OptionCard({
    required this.option,
    required this.index,
    required this.wrong,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  ///
  /// 当前选项数据（文本 + 是否正确）。
  ///
  /// @var ListeningMeaningOption
  ///
  final ListeningMeaningOption option;

  ///
  /// 选项在四选一列表中的位置（0-3），用于 A/B/C/D badge。
  ///
  /// @var int
  ///
  final int index;

  ///
  /// 是否已被选错；从 false 变 true 时触发抖动。
  ///
  /// @var bool
  ///
  final bool wrong;

  ///
  /// 点击回调；错选后由调用方传入 null 禁用。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 长按回调；即使该项已经选错，仍允许用户把它刷新成新候选。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onLongPress;

  ///
  /// 创建候选卡片动画状态。
  ///
  /// @return `State<_OptionCard>` 管理错误抖动动画的状态对象。
  ///
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
  ///
  /// @var AnimationController
  ///
  late final AnimationController _shakeController;

  ///
  /// 从零开始、经过正负位移并最终回到零的抖动曲线。
  ///
  /// @var `Animation<double>`
  ///
  late final Animation<double> _shakeAnimation;

  ///
  /// 初始化抖动动画控制器和位移序列。
  ///
  /// @return void
  ///
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
  ///
  /// @param  _OptionCard  oldWidget 更新前的候选卡片配置。
  /// @return void
  ///
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
  ///
  /// @return void
  ///
  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  ///
  /// 构建候选卡片及错误抖动效果。
  ///
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 可点击、长按并显示错误状态的候选卡片。
  ///
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final wrong = widget.wrong;
    // AnimatedBuilder 只在抖动期间重建，不影响正常状态下的性能。
    return AnimatedBuilder(
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
          borderRadius: BorderRadius.circular(ListeningMeaningLayout.cardRadius),
          child: Container(
            height: ListeningMeaningLayout.optionHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: ListeningMeaningLayout.optionHorizontalInset,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ListeningMeaningLayout.cardRadius),
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
                  child: Text(
                    widget.option.text,
                    key: Key('listening-meaning-option-label-${widget.index}'),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: TextStyle(
                      color: wrong ? AppTokens.danger : tokens.text,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
