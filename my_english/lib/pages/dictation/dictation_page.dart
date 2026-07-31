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
import 'services/dictation_option_generator.dart';
// 引入默写记录 Store：点击下一题时写入结果并驱动难度变化。
import '../../store/record.dart';
// 引入默写候选项缓存 Store，让每道题长期复用相同干扰项。
import '../../store/dictation_option_cache.dart';
// 引入学习会话 Store，持续保存本轮单词顺序与答题进度。
import '../../store/learning_session.dart';
// 引入默写页面集中管理的布局尺寸。
import 'widgets/dictation_layout.dart';
// 引入中部三个只读子模块，页面文件只保留答题状态与事件流程。
import 'widgets/dictation_question_content.dart';

/// 默写的两个答题阶段：先辨认拼写，再逐条辨认释义。
enum DictationStage { word, definition }

/// 一个可点击答案，`isCorrect` 相当于原型对象里的 `c` 字段。
class DictationOption {
  const DictationOption({required this.text, required this.isCorrect});

  final String text;
  final bool isCorrect;
}

/// 全屏默写页面。
class DictationPage extends StatefulWidget {
  const DictationPage({
    required this.words,
    required this.audioPlayer,
    required this.accent,
    this.recordStore,
    this.optionCacheStore,
    this.initialSession,
    this.sessionStore,
    this.definitionSeparator = '、',
    super.key,
  }) : assert(words.length > 0, '默写页至少需要一个学习单词');

  /// 本轮参与默写的单词。
  final List<Word> words;

  /// 与首页、随身听共用的发音服务。
  final WordAudioPlayer audioPlayer;

  /// 当前发音口音。
  final PronunciationAccent accent;

  /// 默写记录存储；正式环境使用全局实例，测试可注入独立通道。
  final RecordStore? recordStore;

  /// 候选项缓存存储；正式环境使用 SQLite，测试可注入独立通道。
  final DictationOptionCacheStore? optionCacheStore;

  /// 从首页“继续”入口传入的历史会话；null 表示开始一轮新默写。
  final LearningSession? initialSession;

  /// 学习会话存储；正式环境使用 SQLite，测试可注入内存实现。
  final LearningSessionStore? sessionStore;

  /// 已答出的同词性中文释义之间使用的全角分隔符。
  final String definitionSeparator;

  @override
  State<DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<DictationPage> {
  // 固定种子使测试和界面复现更稳定，同时每题仍会有不同顺序。
  final Random _random = Random(20260727);
  // 当前单词下标。
  int _wordIndex = 0;
  // 当前答题阶段。
  DictationStage _stage = DictationStage.word;
  // 当前词义块下标。
  int _meaningIndex = 0;
  // 当前词义块中的释义下标。
  int _definitionIndex = 0;
  // 单词阶段已经公开的开头字母数。
  int _hintLevel = 0;
  // 整轮累计答错次数，完成状态页用它展示本轮统计。
  int _errors = 0;
  // 当前单词本次默写累计选错候选词的次数（每个新词重置）。
  int _currentWrong = 0;
  // 当前单词本次默写累计点击提示的次数（每个新词重置）。
  int _currentHints = 0;
  // 本轮复习完成过的单词主键集合，退出时带回首页用于定向回刷。
  final Set<int> _reviewedWordIds = <int>{};
  // 是否已经提交最后一个单词并进入整轮完成状态页。
  bool _isDone = false;
  // 当前单词的拼写和全部含义是否均已答对，完成后等待用户点击下一题。
  bool _isCurrentWordComplete = false;
  // 是否正在把当前题提交给原生事务；用于阻止连续点击产生重复记录。
  bool _isSavingCompletion = false;
  // 发音图标是否显示。
  bool _isPlaying = false;
  // 发音请求代次号：每发起一次播放就 +1，相当于给这次播放发一张"号码牌"。
  //
  // 为什么需要它？因为 `_playAudio` 是异步的（await 原生播放直到音频结束），
  // 当奖励音频还没播完、用户就点了"下一题"时，新播放会打断旧播放，
  // 旧的那次 await 随后才抛出中断异常并进入 finally。若不加区分，
  // 旧调用的 finally 会把 `_isPlaying` 置回 false，把新播放的"播放中"状态误清掉。
  // 有了代次号，旧调用发现自己的号码牌已经过期，就什么都不做，直接安静退出。
  int _playGeneration = 0;
  // 中间信息面板中的反馈文案。
  String _feedback = '';
  // 反馈颜色；null 时使用次要文字色。
  Color? _feedbackColor;
  // 当前选项列表。
  List<DictationOption> _options = const [];
  // 已选错的文案集合，错误选项会红色并禁用。
  final Set<String> _wrongOptions = <String>{};
  // 候选缓存读取代次号；切换小题后，较早返回的异步结果不得覆盖新题。
  int _optionLoadGeneration = 0;
  // true 表示当前四个候选直接来自会话快照，首帧无需重新打乱缓存候选。
  bool _restoredExactOptions = false;

  Word get _currentWord => widget.words[_wordIndex];

  /// 正式页面复用单例，测试传入独立 Store 后不会触碰真实原生通道。
  RecordStore get _recordStore => widget.recordStore ?? RecordStore.instance;

  /// 正式页面复用 SQLite 单例，测试可传入自定义 MethodChannel。
  DictationOptionCacheStore get _optionCacheStore =>
      widget.optionCacheStore ?? DictationOptionCacheStore.instance;

  /// 正式页面使用 SQLite 单例，Widget 测试可传入内存 Store。
  LearningSessionStore get _sessionStore =>
      widget.sessionStore ?? LocalLearningSessionStore.instance;

  List<Meaning> get _availableMeanings => _currentWord.meanings
      .where((meaning) => meaning.definitions.isNotEmpty)
      .toList(growable: false);

  /// 当前拼写中的真实英文字母数量；空格和连字符不会生成占位槽。
  int get _currentWordLetterCount => _currentWord.spelling.runes
      .map((codePoint) => String.fromCharCode(codePoint))
      .where((character) => RegExp(r'^[A-Za-z]$').hasMatch(character))
      .length;

  @override
  void initState() {
    super.initState();
    // 继续模式先恢复小题下标、错误和候选顺序；新开始则保留默认字段。
    _restoreInitialSession();
    // 完成待提交态没有候选；普通状态若快照无合法候选则同步生成标准四选一。
    if (_isCurrentWordComplete) {
      _options = const <DictationOption>[];
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

  /// 从历史会话恢复当前默写状态；所有动态字段都经过边界校验。
  void _restoreInitialSession() {
    // 没有会话就是一次全新的默写。
    final session = widget.initialSession;
    if (session == null || session.type != LearningSessionType.dictation) {
      return;
    }
    // 先恢复单词下标，后续释义边界都依赖当前单词。
    final state = session.state;
    _wordIndex = _readSessionInt(
      state['wordIndex'],
      fallback: 0,
    ).clamp(0, widget.words.length - 1);
    // 只有明确的 definition 才进入释义阶段，其余坏值安全回到拼写阶段。
    _stage = state['stage'] == DictationStage.definition.name
        ? DictationStage.definition
        : DictationStage.word;
    // 当前单词没有可答释义时不能恢复到 definition，否则 getter 会越界。
    if (_availableMeanings.isEmpty) _stage = DictationStage.word;
    if (_stage == DictationStage.definition) {
      _meaningIndex = _readSessionInt(
        state['meaningIndex'],
        fallback: 0,
      ).clamp(0, _availableMeanings.length - 1);
      _definitionIndex = _readSessionInt(
        state['definitionIndex'],
        fallback: 0,
      ).clamp(0, _availableMeanings[_meaningIndex].definitions.length - 1);
    }
    // 计数都不能为负数；提示级别额外受当前单词字母数约束。
    _hintLevel = _readSessionInt(
      state['hintLevel'],
      fallback: 0,
    ).clamp(0, _currentWordLetterCount);
    _errors = max(0, _readSessionInt(state['errors'], fallback: 0));
    _currentWrong = max(0, _readSessionInt(state['currentWrong'], fallback: 0));
    _currentHints = max(0, _readSessionInt(state['currentHints'], fallback: 0));
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
      _feedback = '不对，再试试';
      _feedbackColor = AppTokens.danger;
    }
    // 候选快照必须恰好四项、只有一个正确项且文本仍匹配当前正确答案。
    final rawOptions = state['options'];
    if (!_isCurrentWordComplete && rawOptions is List) {
      final restored = <DictationOption>[];
      for (final rawOption in rawOptions) {
        if (rawOption is! Map ||
            rawOption['text'] is! String ||
            rawOption['isCorrect'] is! bool) {
          restored.clear();
          break;
        }
        restored.add(
          DictationOption(
            text: rawOption['text']! as String,
            isCorrect: rawOption['isCorrect']! as bool,
          ),
        );
      }
      final correctOptions = restored
          .where((option) => option.isCorrect)
          .toList();
      if (restored.length == 4 &&
          correctOptions.length == 1 &&
          correctOptions.single.text == _currentCorrectAnswer) {
        _options = List<DictationOption>.unmodifiable(restored);
        _restoredExactOptions = true;
      }
    }
  }

  /// 把当前答题状态写入 SQLite；页面交互先完成，持久化失败不阻断答题。
  Future<void> _persistSession() async {
    // 正式词库单词都有主键；临时测试对象缺少 id 时不制造无法恢复的记录。
    final wordIds = widget.words.map((word) => word.id).toList(growable: false);
    if (wordIds.any((id) => id == null) || _isDone) return;
    try {
      await _sessionStore.save(
        LearningSession(
          type: LearningSessionType.dictation,
          wordIds: wordIds.cast<int>(),
          state: <String, Object?>{
            'wordIndex': _wordIndex,
            'stage': _stage.name,
            'meaningIndex': _meaningIndex,
            'definitionIndex': _definitionIndex,
            'hintLevel': _hintLevel,
            'errors': _errors,
            'currentWrong': _currentWrong,
            'currentHints': _currentHints,
            'isCurrentWordComplete': _isCurrentWordComplete,
            'feedback': _feedback,
            'feedbackTone': _feedbackColor == AppTokens.danger
                ? 'danger'
                : (_feedbackColor == const Color(0xFF2FB344)
                      ? 'success'
                      : 'neutral'),
            'wrongOptions': _wrongOptions.toList(growable: false),
            'options': <Map<String, Object?>>[
              for (final option in _options)
                <String, Object?>{
                  'text': option.text,
                  'isCorrect': option.isCorrect,
                },
            ],
          },
        ),
      );
    } catch (error) {
      debugPrint('保存默写进度失败：$error');
    }
  }

  /// 整轮完成后删除默写会话，首页随即隐藏对应“继续”入口。
  Future<void> _deleteSession() async {
    try {
      await _sessionStore.delete(LearningSessionType.dictation);
    } catch (error) {
      debugPrint('删除默写进度失败：$error');
    }
  }

  /// 当前小题的正确答案：拼写阶段是单词，释义阶段是当前中文释义。
  String get _currentCorrectAnswer => _stage == DictationStage.word
      ? _currentWord.spelling
      : _availableMeanings[_meaningIndex].definitions[_definitionIndex];

  /// 当前小题的稳定缓存 key；内容字段参与 key，数据被编辑后会自然切换到新缓存。
  String get _currentOptionCacheKey {
    // 拼写题由版本、类型、单词主键和当前拼写共同确定。
    if (_stage == DictationStage.word) {
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

  /// 按当前阶段生成指定数量的干扰项。
  List<String> _generateCurrentDistractors({int count = 3}) {
    // 拼写题与释义题分别复用原有生成规则，来源仍严格限制在本轮学习列表。
    return _stage == DictationStage.word
        ? DictationOptionGenerator.buildWordDistractors(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            count: count,
          )
        : DictationOptionGenerator.buildDefinitionDistractors(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            count: count,
          );
  }

  /// 用指定干扰项组装一个正确答案和三个干扰答案，并打乱显示位置。
  List<DictationOption> _buildOptions({List<String>? distractors}) {
    // 未传缓存时同步生成，确保页面首帧已经有完整四选一。
    final resolvedDistractors = distractors ?? _generateCurrentDistractors();
    // 候选生成器固定返回三个唯一干扰项，并优先使用同长度与相似度规则。
    // 正确项与三个干扰项组成始终固定的四选一列表。
    final options = <DictationOption>[
      DictationOption(text: _currentCorrectAnswer, isCorrect: true),
      for (final distractor in resolvedDistractors.take(3))
        DictationOption(text: distractor, isCorrect: false),
    ];
    // 使用页面内的固定种子随机源打乱位置，同一正确答案不会总出现在同一行。
    options.shuffle(_random);
    // 再次冻结列表，状态层只在进入下一小题时整体替换它。
    return List<DictationOption>.unmodifiable(options);
  }

  /// 判断 SQLite 返回的缓存是否仍能安全组成标准四选一。
  bool _isValidCachedDistractors(List<String> distractors, String correct) {
    // 必须精确三项，否则继续使用页面已经同步生成的标准结果。
    if (distractors.length != 3) return false;
    // 英文忽略大小写，中文转换后不受影响；同时排除正确答案与重复项。
    final normalizedCorrect = correct.trim().toLowerCase();
    final normalized = distractors
        .map((value) => value.trim().toLowerCase())
        .toSet();
    return normalized.length == 3 && !normalized.contains(normalizedCorrect);
  }

  /// 命中缓存就替换同步结果；首次遇到该题则把当前生成结果保存到 SQLite。
  Future<void> _restoreOrCreateCurrentOptionCache() async {
    // 每次进入新小题先领取一个代次号，用来识别晚到的旧请求。
    final generation = ++_optionLoadGeneration;
    // 在 await 前抓取当前题身份与数据，后续切题不会改变这些局部变量。
    final cacheKey = _currentOptionCacheKey;
    final correct = _currentCorrectAnswer;
    final wordId = _currentWord.id;
    final generatedDistractors = _options
        .where((option) => !option.isCorrect)
        .map((option) => option.text)
        .toList(growable: false);
    try {
      // 从原生 SQLite 查询这道题以前使用过的干扰项。
      final cachedDistractors = await _optionCacheStore.getDistractors(
        cacheKey,
      );
      // 命中合法缓存时，只允许仍处于同一小题的请求更新页面。
      if (cachedDistractors != null &&
          _isValidCachedDistractors(cachedDistractors, correct)) {
        if (!mounted || generation != _optionLoadGeneration) return;
        setState(() {
          // 正确答案继续取最新模型，仅把三个干扰项换成缓存值。
          _options = _buildOptions(distractors: cachedDistractors);
        });
        // 候选顺序属于可恢复状态，缓存替换后同步保存当前页面快照。
        unawaited(_persistSession());
        return;
      }
      // 没有缓存或缓存损坏时，保存首帧已经显示的三个生成结果。
      await _optionCacheStore.saveDistractors(
        cacheKey: cacheKey,
        wordId: wordId,
        distractors: generatedDistractors,
      );
    } catch (error) {
      // 缓存是体验增强，不应因原生通道异常阻断答题；保留同步生成结果即可。
      debugPrint('读取或保存默写候选缓存失败：$error');
    }
  }

  /// 调用真实发音服务，并在播放期间显示 Tabler 音量图标。
  ///
  /// [interrupt] 决定"当前已经有音频在播"时的策略，类似小程序里两种点击语义：
  /// - false（默认，用户手动点播放按钮）：正在播就忽略这次点击，避免连点导致反复重播；
  /// - true（切下一题 / 再试一次这类自动播放）：**强制打断**正在播的旧音频。
  ///   这是本次修复的关键——答对后的"奖励发音"还没结束时点下一题，
  ///   必须允许新单词把它顶掉，否则新题永远发不出声。
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
      await widget.audioPlayer.play(_currentWord.spelling, widget.accent);
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

  /// 点击提示：拼写阶段逐字公开，释义阶段公开首字。
  void _showHint() {
    // 整轮或当前单词已经完成时，不再改变提示状态。
    if (_isDone || _isCurrentWordComplete) return;
    if (_stage == DictationStage.word) {
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

  /// 选择答案：错项变红并禁用；正确时推进到下一小题。
  ///
  /// 触觉反馈策略：
  /// - 选错：heavyImpact（重震），配合选项抖动动画，错误感强烈。
  /// - 选对：lightImpact（轻触），页面立即切换为新题，视觉变化即反馈。
  void _pickOption(DictationOption option) {
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
        _feedback = '不对，再试试';
        _feedbackColor = AppTokens.danger;
      });
      // 保存错项文本与错误计数，重新进入后不能通过退出页面清除错误。
      unawaited(_persistSession());
      return;
    }

    // 轻触震动确认选对，不拖延答题节奏。
    HapticFeedback.lightImpact();

    if (_stage == DictationStage.word) {
      if (_availableMeanings.isEmpty) {
        // 没有释义的单词在拼写答对后就完成，等待用户手动进入下一题。
        _completeCurrentWord();
        return;
      }
      setState(() {
        _stage = DictationStage.definition;
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
    final replacement = _stage == DictationStage.word
        ? DictationOptionGenerator.findReplacementWordDistractor(
            correct: _currentCorrectAnswer,
            sourceWords: widget.words,
            excluded: excluded,
          )
        : DictationOptionGenerator.findReplacementDefinitionDistractor(
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
    final updatedOptions = List<DictationOption>.from(_options);
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
      updatedOptions[optionIndex] = DictationOption(
        text: replacement,
        isCorrect: false,
      );
      // 正确答案移动到随机目标位置，交互不会暴露它的身份。
      updatedOptions[correctTarget] = selectedOption;
    } else {
      // 普通干扰项只替换自身位置，其余三个按钮完全不动。
      updatedOptions[optionIndex] = DictationOption(
        text: replacement,
        isCorrect: false,
      );
    }
    setState(() {
      // 移除已消失文本的红色禁用状态，新候选可以正常点击。
      _wrongOptions.removeAll(removedWrongOptions);
      // 冻结新列表，保持页面状态只能整体更新。
      _options = List<DictationOption>.unmodifiable(updatedOptions);
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

  /// 把长按刷新后的三个干扰项覆盖进当前小题缓存。
  Future<void> _persistRefreshedOptions({
    required String cacheKey,
    required int? wordId,
    required List<DictationOption> options,
  }) async {
    try {
      // 正确答案不写缓存，只提取三个干扰项。
      final distractors = options
          .where((option) => !option.isCorrect)
          .map((option) => option.text)
          .toList(growable: false);
      await _optionCacheStore.saveDistractors(
        cacheKey: cacheKey,
        wordId: wordId,
        distractors: distractors,
      );
    } catch (error) {
      // 页面替换已经完成；记录错误并提示缓存失败，下次进入仍可继续正常答题。
      debugPrint('保存刷新后的默写候选缓存失败：$error');
      if (mounted) Toast.show(context, '候选词已刷新，但缓存保存失败');
    }
  }

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
      _options = const <DictationOption>[];
      // 中间信息面板告知用户当前单词已经完成。
      _feedback = '本词完成！';
      // 绿色只用于正确完成反馈。
      _feedbackColor = const Color(0xFF2FB344);
    });
    // “本词完成、等待下一题”是重要恢复点；此时仍不能提前写默写记录。
    unawaited(_persistSession());
    // 自动重播一次发音作为答对奖励：既有听觉反馈，又强化单词记忆。
    // interrupt: true —— 若用户刚好手动点了播放，奖励发音直接接管，不会被忽略。
    unawaited(_playAudio(interrupt: true));
  }

  /// 把当前单词的本次默写结果写入记录 Store。
  ///
  /// 这一步只在用户点击「下一题」后发生；停留在完成态或点击「再试一次」都不会
  /// 写数据库。此时 [_currentWrong]/[_currentHints] 仍保存着本词累计数据。
  /// 若单词没有主键（极端情况）则直接跳过，并允许页面继续推进。
  ///
  /// 关于 isCorrect 的口径（重要）：默写只能以"全部选对"结束，所以不能用"是否
  /// 完成"来判断对错。真正有意义的判定是**本次过程中有没有选错过候选词**：
  /// - 一次没错（[_currentWrong] == 0）→ 视为本次默写正确；
  /// - 中途选错过 → 视为本次默写错误，原生据此把难度 +1。
  /// 点击提示只作为 hintCount 留档，不影响正误判定（提示不等于答错）。
  Future<bool> _recordCompletion() async {
    // 取出当前单词主键。
    final wordId = _currentWord.id;
    // 没有主键无法落库；它通常只会出现在尚未保存的测试数据中。
    if (wordId == null) return true;
    try {
      // 等待原生事务真正结束后才允许切题，确保首页回刷时能读取到最新数据。
      await _recordStore.addCompletion(
        // 本次是否"一次做对"：零错选才算正确，见上方口径说明。
        wordId: wordId,
        isCorrect: _currentWrong == 0,
        wrongCount: _currentWrong,
        hintCount: _currentHints,
      );
      // 只有事务成功后才把 id 带回首页，避免首页回刷一条并未更新的数据。
      _reviewedWordIds.add(wordId);
      // true 告诉按钮流程可以安全进入下一题。
      return true;
    } catch (error) {
      // 保留日志便于开发时定位原生数据库异常。
      debugPrint('记录默写结果失败：$error');
      // 页面仍存在时给用户明确反馈，并停留在本题以便再次点击重试。
      if (mounted) Toast.show(context, '保存默写结果失败，请重试');
      // false 阻止切题，避免用户误以为本次结果已经保存。
      return false;
    }
  }

  /// 退出默写页，并把本次复习过的单词 id 集合带回首页，供其定向回刷。
  ///
  /// 通过 [Navigator.pop] 的结果参数传出，避免首页重新加载整库。
  void _exitDictation() {
    // 用户点击下一题后必须等事务结束；保存中主动返回会让首页漏掉最新回刷 id。
    if (_isSavingCompletion) return;
    // 把收集到的 id 列表作为路由结果返回给上一页。
    Navigator.pop(context, _reviewedWordIds.toList());
  }

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
      unawaited(_deleteSession());
      // 停止可能仍在播放的答对奖励音频。
      unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
      return;
    }
    // 一次 setState 完整重置新单词的全部答题状态。
    setState(() {
      // 保持 widget.words 原始顺序，只把下标向后移动一位。
      _wordIndex++;
      // 每个新单词都从拼写阶段开始。
      _stage = DictationStage.word;
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
      _stage = DictationStage.word;
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

  /// 构建当前单词的完整步骤清单：先“听音选词”，再逐条词性释义。
  ///
  /// 每个步骤都从一开始列出，状态随答题进度在 未开始/进行中/已完成 之间变化。
  /// 组件只负责按状态渲染，不关心答题下标。
  List<DictationStep> _buildSteps() {
    // 步骤集合从“听音选词”开始，拼写答对后它转为已完成。
    final steps = <DictationStep>[
      DictationStep(
        kind: DictationStepKind.word,
        title: '听音选词',
        // 完成后把正确单词带进步骤，便于在步骤下方直接回显。
        word: _currentWord.spelling,
        // 拼写阶段结束后，单词步骤即视为完成；否则当前就是进行中的那一步。
        status: _stage == DictationStage.definition || _isCurrentWordComplete
            ? DictationStepStatus.done
            : (_stage == DictationStage.word
                  ? DictationStepStatus.active
                  : DictationStepStatus.pending),
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
          _stage == DictationStage.definition &&
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
        DictationStep(
          kind: DictationStepKind.meaning,
          title: '释义',
          status: isMeaningDone
              ? DictationStepStatus.done
              : (isMeaningActive
                    ? DictationStepStatus.active
                    : DictationStepStatus.pending),
          pos: pos,
          definitions: definitions,
        ),
      );
    }
    // 冻结列表，展示组件只读取，不修改步骤状态。
    return List<DictationStep>.unmodifiable(steps);
  }

  String get _stageLabel {
    // 完成后的提示不再要求选择，只说明当前单词已完成。
    if (_isCurrentWordComplete) return '当前单词已完成';
    // 拼写阶段引导用户通过发音选出单词。
    if (_stage == DictationStage.word) return '听音，选出正确的单词';
    final meaning = _availableMeanings[_meaningIndex];
    final pos = meaning.pos.trim().isEmpty ? '释义' : meaning.displayPos;
    return '$pos · 选择释义 ${_definitionIndex + 1}/${meaning.definitions.length}';
  }

  @override
  void dispose() {
    // 系统返回或路由销毁前补写最终答题状态；完成页已经删除会话，不能重新创建。
    if (!_isDone) unawaited(_persistSession());
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    super.dispose();
  }

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
            DictationLayout.pageInset,
            DictationLayout.headerTop,
            DictationLayout.pageInset,
            0,
          ),
          // Row 将返回按钮、中央进度和右侧占位区排成一行。
          child: Row(
            children: [
              // 返回按钮的 34 像素点击画布直接贴齐左侧页面边距。
              _PlainIconButton(
                key: const Key('close-dictation'),
                icon: TablerIcons.chevronLeft,
                alignment: Alignment.centerLeft,
                onTap: _exitDictation,
              ),
              // Expanded 占用左右等宽画布之间的全部空间。
              Expanded(
                // 当前题号放在中间，不再由左侧“默写”标题把它挤到右边。
                child: Text(
                  '${_isDone ? widget.words.length : _wordIndex + 1} / ${widget.words.length}',
                  key: const Key('dictation-progress-label'),
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
              // 右侧用与返回按钮等宽的固定画布承载难度，中央题号仍保持绝对居中。
              SizedBox(
                width: DictationLayout.headerButtonSize,
                height: DictationLayout.headerButtonSize,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _DictationDifficultyBadge(
                    difficulty: _currentWord.difficulty,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 进度条的左右边界与顶栏严格对齐。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DictationLayout.pageInset,
            DictationLayout.progressTop,
            DictationLayout.pageInset,
            0,
          ),
          // ClipRRect 只把线性进度条的两端裁成轻微圆角。
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const Key('dictation-progress-bar'),
              value: progress,
              minHeight: DictationLayout.progressHeight,
              color: AppTokens.accent,
              backgroundColor: tokens.sub,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion(AppTokens tokens) {
    // 底部控件虽然脱离普通布局，但滚动内容仍需保留等高的尾部内边距，
    // 否则较长 Steps 的最后几行会被悬浮候选区遮住。
    final bottomOverlayHeight = _isCurrentWordComplete
        ? DictationLayout.nextControlsExtent
        : DictationLayout.bottomControlsExtent;
    // Stack 对应小程序 position + z-index：列表是中间层，底部控件作为最后绘制的顶层。
    return Stack(
      key: const Key('dictation-question-stack'),
      fit: StackFit.expand,
      children: [
        // 第一层兼具“透明播放命中层”和可滚动内容容器：GestureDetector 自身不绘制颜色，
        // 但会占满顶部区域以下的全部空间。它包在 ScrollView 外层，因此轻点播放，
        // 纵向拖动时 ScrollView 的手势识别器仍可赢得手势竞争并正常滚动。
        Positioned.fill(
          child: GestureDetector(
            key: const Key('dictation-question-audio-overlay'),
            behavior: HitTestBehavior.translucent,
            onTap: _playAudio,
            child: Semantics(
              button: true,
              label: '播放当前单词发音',
              child: SingleChildScrollView(
                key: const Key('dictation-question-scroll'),
                padding: EdgeInsets.fromLTRB(
                  DictationLayout.pageInset,
                  DictationLayout.questionVerticalInset,
                  DictationLayout.pageInset,
                  bottomOverlayHeight + DictationLayout.questionVerticalInset,
                ),
                // Align 让窄屏占满可用宽度，宽屏限制宽度后仍保持水平居中。
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DictationLayout.questionMaxWidth,
                    ),
                    // 独立组件按“单词卡、提示横幅、全量步骤”从上到下输出。
                    child: DictationQuestionContent(
                      spelling: _currentWord.spelling,
                      revealedLetterCount: _hintLevel,
                      revealWholeWord:
                          _stage == DictationStage.definition ||
                          _isCurrentWordComplete,
                      onSpeakerTap: _playAudio,
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
      ],
    );
  }

  /// 构建贴近底部安全区的候选与操作区。
  Widget _buildBottomControls(AppTokens tokens) {
    // Padding 在 SafeArea 已避开系统手势条后，再提供 20 像素底部留白。
    return Padding(
      key: const Key('dictation-bottom-controls'),
      padding: const EdgeInsets.fromLTRB(
        DictationLayout.pageInset,
        DictationLayout.bottomSectionTop,
        DictationLayout.pageInset,
        DictationLayout.bottomInset,
      ),
      // 固定两栏总高度，左右两组控件都以同一条底边向上堆叠。
      child: SizedBox(
        key: const Key('dictation-control-columns'),
        height: DictationLayout.optionStackHeight,
        // Row 将左侧四个候选词和右侧两个操作按钮分成两栏。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左栏获得三份宽度，是右栏的三倍。
            Expanded(
              key: const Key('dictation-option-column'),
              flex: DictationLayout.optionColumnFlex,
              // Column 让四个候选词从共同底边向上占满四行。
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var index = 0; index < _options.length; index++) ...[
                    // 每个选项由独立 _OptionCard 管理，支持错选抖动动画。
                    _OptionCard(
                      key: ValueKey(
                        'dictation-option-$index-${_options[index].text}',
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
                      const SizedBox(height: DictationLayout.optionGap),
                  ],
                ],
              ),
            ),
            // 两栏之间只使用正常布局间距，不使用任何偏移。
            const SizedBox(width: DictationLayout.columnGap),
            // 右栏获得一份宽度，把主要空间留给可能较长的候选词。
            Expanded(
              key: const Key('dictation-action-column'),
              flex: DictationLayout.actionColumnFlex,
              // end 让播放先贴齐底边，提示再依照间距堆叠到它上方。
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 提示按钮放在播放按钮正上方。
                  _OutlineAction(
                    key: const Key('dictation-hint'),
                    icon: TablerIcons.bulb,
                    label: '提示',
                    foreground: tokens.textMedium,
                    border: tokens.inputBorder,
                    height: DictationLayout.actionHeight,
                    horizontalPadding: 8,
                    onTap: _showHint,
                  ),
                  // 两个右侧按钮使用与候选词相同的纵向间距。
                  const SizedBox(height: DictationLayout.optionGap),
                  // 播放按钮作为右栏最后一项，底边直接对齐第四个候选词。
                  _OutlineAction(
                    key: const Key('dictation-play'),
                    icon: _isPlaying
                        ? TablerIcons.volume2
                        : TablerIcons.playerPlay,
                    label: '播放',
                    foreground: Colors.white,
                    border: AppTokens.accent,
                    background: AppTokens.accent,
                    height: DictationLayout.actionHeight,
                    horizontalPadding: 8,
                    onTap: _playAudio,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建当前单词全部答对后的底部操作区：左「再试一次」+ 右「下一题」。
  ///
  /// 两个按钮通过 Expanded 各占一半宽度，中间用 [DictationLayout.columnGap]
  /// 留出间距（相当于小程序里 flex:1 + margin 的写法）。
  /// 左侧是次要操作（描边样式），右侧是主操作（蓝色实心）。
  Widget _buildNextQuestionButton(AppTokens tokens) {
    // 最后一题提交后会进入完成状态页，因此主操作使用“完成”语义。
    final isLastWord = _wordIndex + 1 >= widget.words.length;
    // Padding 与普通候选区共用相同的左右、顶部和安全区留白。
    return Padding(
      key: const Key('dictation-next-area'),
      padding: const EdgeInsets.fromLTRB(
        DictationLayout.pageInset,
        DictationLayout.bottomSectionTop,
        DictationLayout.pageInset,
        DictationLayout.bottomInset,
      ),
      // SizedBox 固定整行高度，两个按钮上下边界完全一致。
      child: SizedBox(
        width: double.infinity,
        height: DictationLayout.actionHeight,
        // Row 横向排列两个按钮，类似小程序的 display:flex。
        child: Row(
          children: [
            // 左半：次要操作「再试一次」，把当前题退回初始状态重做。
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('retry-dictation-word'),
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
                  minimumSize: const Size(0, DictationLayout.actionHeight),
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
            const SizedBox(width: DictationLayout.columnGap),
            // 右半：普通题进入「下一题」，最后一题提交后进入完成状态页。
            Expanded(
              // FilledButton.icon 用蓝色背景表达当前的主操作。
              child: FilledButton.icon(
                key: const Key('next-dictation-word'),
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
                  minimumSize: const Size(0, DictationLayout.actionHeight),
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

  /// 构建整轮默写完成状态页，展示题量、累计错选次数和返回入口。
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
              '默写完成',
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
              key: const Key('finish-dictation'),
              onPressed: _exitDictation,
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

/// 默写顶栏难度徽章：正数使用危险色，其余情况用成功色显示 0。
class _DictationDifficultyBadge extends StatelessWidget {
  /// 创建当前单词的只读难度徽章。
  const _DictationDifficultyBadge({required this.difficulty});

  /// 模型中的可空难度；历史异常负数也按无难度处理。
  final int? difficulty;

  /// 输出固定高度的 Tabler 软色 Badge。
  @override
  Widget build(BuildContext context) {
    // 只有真实正数才是需要提醒的难度，其余值统一归零。
    final normalizedDifficulty = (difficulty ?? 0) > 0 ? difficulty! : 0;
    // 正数采用 Tabler danger，零采用 Tabler success green。
    final foreground = normalizedDifficulty > 0
        ? AppTokens.danger
        : const Color(0xFF2FB344);
    return Container(
      key: const Key('dictation-difficulty-badge'),
      constraints: const BoxConstraints(minWidth: 22, maxWidth: 34),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 13% 软色背景与首页难度 Badge 保持同一 Tabler 视觉。
        color: foreground.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      // FittedBox 只在极大数值超过 34 像素画布时缩小，避免顶栏溢出。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          normalizedDifficulty.toString(),
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _PlainIconButton extends StatelessWidget {
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

  /// Flutter 每次需要绘制顶栏按钮时调用此方法。
  @override
  Widget build(BuildContext context) {
    // 读取当前亮色或深色主题中的文字颜色。
    final tokens = AppTokens.of(context);
    // SizedBox 明确约束点击画布，不让图标自身的透明空间影响顶栏对齐。
    return SizedBox(
      width: DictationLayout.headerButtonSize,
      height: DictationLayout.headerButtonSize,
      // InkWell 提供点击命中与圆形按压反馈。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          DictationLayout.headerButtonSize / 2,
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

class _OutlineAction extends StatelessWidget {
  /// 构建右侧的提示或播放按钮。
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

  /// 仅当按钮具有图标语义时传入 Tabler 图标。
  final IconData? icon;

  /// 按钮中显示的命令文字。
  final String label;

  /// 图标和文字的前景色。
  final Color foreground;

  /// 按钮一像素外边框的颜色。
  final Color border;

  /// 可选按钮背景色；播放主操作传入蓝色，提示按钮则沿用卡片色。
  final Color? background;

  /// 点击按钮时执行的业务操作。
  final VoidCallback onTap;

  /// 按钮的固定高度，底部操作区使用 48 像素。
  final double height;

  /// 按钮文字两侧留白，窄右栏使用较紧凑的值。
  final double horizontalPadding;

  /// Flutter 绘制提示或播放按钮时调用此方法。
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

/// 候选词卡片：错选时触发左右抖动动画，配合触觉反馈传达错误感。
///
/// 动画时长 300ms，振幅从 ±8px 衰减到 0，类似微信摇一摇的阻尼抖动。
/// 正确选项不做动画——页面立即切换为新题，视觉变化本身就是反馈。
class _OptionCard extends StatefulWidget {
  const _OptionCard({
    required this.option,
    required this.index,
    required this.wrong,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  /// 当前选项数据（文本 + 是否正确）。
  final DictationOption option;

  /// 选项在四选一列表中的位置（0-3），用于 A/B/C/D badge。
  final int index;

  /// 是否已被选错；从 false 变 true 时触发抖动。
  final bool wrong;

  /// 点击回调；错选后由调用方传入 null 禁用。
  final VoidCallback onTap;

  /// 长按回调；即使该项已经选错，仍允许用户把它刷新成新候选。
  final VoidCallback onLongPress;

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard>
    with SingleTickerProviderStateMixin {
  // 抖动动画控制器，300ms 一次完整衰减。
  late final AnimationController _shakeController;
  // 抖动位移曲线：从 0 出发，经过 ±8px 衰减振荡，最终回到 0。
  late final Animation<double> _shakeAnimation;

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

  @override
  void didUpdateWidget(covariant _OptionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从"未错"变为"已错"时触发抖动。
    if (!oldWidget.wrong && widget.wrong) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

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
      // 以下与原 _buildOption 的 UI 完全一致，仅改为从 widget 读取参数。
      child: Material(
        key: Key('dictation-option-${widget.index}'),
        color: wrong ? AppTokens.danger.withValues(alpha: 0.08) : tokens.card,
        borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
        child: InkWell(
          onTap: wrong ? null : widget.onTap,
          // 长按不参与答题判定，只打开刷新候选词确认框。
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
          child: Container(
            height: DictationLayout.optionHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: DictationLayout.optionHorizontalInset,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
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
                    key: Key('dictation-option-badge-${widget.index}'),
                    width: DictationLayout.optionBadgeSize,
                    height: DictationLayout.optionBadgeSize,
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
                        DictationLayout.optionBadgeSize +
                        DictationLayout.optionHorizontalInset,
                  ),
                  child: Text(
                    widget.option.text,
                    key: Key('dictation-option-label-${widget.index}'),
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

/// 从动态 JSON 状态读取整数；类型不符时使用明确默认值。
int _readSessionInt(Object? value, {required int fallback}) {
  // jsonDecode 的整数属于 num，统一转成 Dart int。
  if (value is num) return value.toInt();
  // 旧版本或坏数据缺失字段时保持页面可用。
  return fallback;
}
