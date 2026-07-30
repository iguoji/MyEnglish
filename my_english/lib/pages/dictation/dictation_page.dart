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
// 引入词义模型。
import '../../models/meaning.dart';
// 引入单词模型。
import '../../models/word.dart';
// 引入音频播放接口。
import '../../services/word_audio.dart';
// 引入口音设置枚举。
import '../../store/settings.dart';
// 引入独立候选项生成服务，页面只负责当前答题状态。
import 'services/dictation_option_generator.dart';
// 引入默写记录 Store：单词完成时写入结果并驱动难度变化。
import '../../store/record.dart';
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

/// 新版原型中的全屏默写页面。
class DictationPage extends StatefulWidget {
  const DictationPage({
    required this.words,
    required this.audioPlayer,
    required this.accent,
    this.definitionSeparator = '、',
    super.key,
  }) : assert(words.length > 0, '默写页至少需要一个学习单词');

  /// 本轮参与默写的单词。
  final List<Word> words;

  /// 与首页、随身听共用的发音服务。
  final WordAudioPlayer audioPlayer;

  /// 当前发音口音。
  final PronunciationAccent accent;

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
  // 整轮累计答错次数。
  int _errors = 0;
  // 当前单词本次默写累计选错候选词的次数（每个新词重置）。
  int _currentWrong = 0;
  // 当前单词本次默写累计点击提示的次数（每个新词重置）。
  int _currentHints = 0;
  // 本轮复习完成过的单词主键集合，退出时带回首页用于定向回刷。
  final Set<int> _reviewedWordIds = <int>{};
  // 是否已完成全部单词。
  bool _isDone = false;
  // 当前单词的拼写和全部含义是否均已答对，完成后等待用户点击下一题。
  bool _isCurrentWordComplete = false;
  // 发音图标是否显示。
  bool _isPlaying = false;
  // 中间信息面板中的反馈文案。
  String _feedback = '';
  // 反馈颜色；null 时使用次要文字色。
  Color? _feedbackColor;
  // 当前选项列表。
  List<DictationOption> _options = const [];
  // 已选错的文案集合，错误选项会红色并禁用。
  final Set<String> _wrongOptions = <String>{};

  Word get _currentWord => widget.words[_wordIndex];

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
    _options = _buildOptions();
    // 每个新词的错误/提示计数从 0 开始。
    _currentWrong = 0;
    _currentHints = 0;
    // 与原型一致，进入每个新词后自动播放一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _playAudio());
  }

  /// 生成当前阶段的一个正确答案和三个干扰答案。
  List<DictationOption> _buildOptions() {
    // 拼写阶段的正确值是当前单词，含义阶段则是当前释义。
    final correct = _stage == DictationStage.word
        ? _currentWord.spelling
        : _availableMeanings[_meaningIndex].definitions[_definitionIndex];
    // 候选生成器固定返回三个唯一干扰项，并优先使用同长度与相似度规则。
    final distractors = _stage == DictationStage.word
        ? DictationOptionGenerator.buildWordDistractors(
            correct: correct,
            // 候选项严格从与随身听相同的学习列表中回退，不越过自选范围。
            sourceWords: widget.words,
          )
        : DictationOptionGenerator.buildDefinitionDistractors(
            correct: correct,
            // 含义检索同样只展平本轮学习列表的释义。
            sourceWords: widget.words,
          );
    // 正确项与三个干扰项组成始终固定的四选一列表。
    final options = <DictationOption>[
      DictationOption(text: correct, isCorrect: true),
      for (final distractor in distractors)
        DictationOption(text: distractor, isCorrect: false),
    ];
    // 使用页面内的固定种子随机源打乱位置，同一正确答案不会总出现在同一行。
    options.shuffle(_random);
    // 再次冻结列表，状态层只在进入下一小题时整体替换它。
    return List<DictationOption>.unmodifiable(options);
  }

  /// 调用真实发音服务，并在播放期间显示 Tabler 音量图标。
  Future<void> _playAudio() async {
    if (_isDone || _isPlaying) return;
    setState(() => _isPlaying = true);
    try {
      await widget.audioPlayer.play(_currentWord.spelling, widget.accent);
    } on WordAudioInterruptedException {
      // 页面关闭或新播放替换旧播放时无需弹出错误。
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播放失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isPlaying = false);
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
        _errors++;
        // 当前单词的选错次数同步累加，用于落 record。
        _currentWrong++;
        _feedback = '不对，再试试';
        _feedbackColor = AppTokens.danger;
      });
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
  }

  /// 标记当前单词的拼写和全部释义均已答对。
  void _completeCurrentWord() {
    // 单词完成给予中等震动，作为里程碑反馈。
    HapticFeedback.mediumImpact();
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
    // 自动重播一次发音作为答对奖励：既有听觉反馈，又强化单词记忆。
    unawaited(_playAudio());
    // 当前单词已完成，把本次默写结果写入记录（每天首条为准，异步、不阻塞）。
    _recordCompletion();
  }

  /// 把当前单词的本次默写结果写入记录 Store。
  ///
  /// 这一步发生在「单词完成」那一刻，此时 [_currentWrong]/[_currentHints]
  /// 仍保存着本词累计的选错与提示次数；即便用户随后返回首页也不影响已经落库。
  /// 若单词没有主键（极端情况）则直接跳过。
  void _recordCompletion() {
    // 取出当前单词主键。
    final wordId = _currentWord.id;
    // 没有主键无法落库，直接放弃记录。
    if (wordId == null) return;
    // 记录本次复习涉及的单词，退出首页时只回刷这些单词。
    _reviewedWordIds.add(wordId);
    // 用 unawaited 异步发送，不等待结果，也不阻断默写流程。
    unawaited(
      RecordStore.instance
          .addCompletion(
            // 能走到完成必然是最终全对，故 isCorrect 为 true。
            wordId: wordId,
            isCorrect: true,
            wrongCount: _currentWrong,
            hintCount: _currentHints,
          )
          // 记录失败只打印，不影响界面与后续答题。
          .catchError((Object error) {
        debugPrint('记录默写结果失败：$error');
      }),
    );
  }

  /// 退出默写页，并把本次复习过的单词 id 集合带回首页，供其定向回刷。
  ///
  /// 通过 [Navigator.pop] 的结果参数传出，避免首页重新加载整库。
  void _exitDictation() {
    // 把收集到的 id 列表作为路由结果返回给上一页。
    Navigator.pop(context, _reviewedWordIds.toList());
  }

  /// 用户点击底部长条按钮后进入下一词；最后一词则显示统计页。
  void _goToNextWord() {
    // 只有当前题已完成才允许推进，防止外部误调用跳过题目。
    if (!_isCurrentWordComplete || _isDone) return;
    // 已经处于最后一个单词时，下一步是整轮完成页。
    if (_wordIndex + 1 >= widget.words.length) {
      // 整轮完成给予中等震动，与单词完成同级但更持久。
      HapticFeedback.mediumImpact();
      setState(() {
        // 切换到整轮完成状态。
        _isDone = true;
        // 不再显示播放中图标。
        _isPlaying = false;
        // 整轮统计页不需要单词反馈文案。
        _feedback = '';
      });
      // 停止可能尚未结束的底层音频。
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
      // 清除上一题的完成反馈。
      _feedback = '';
      // 反馈颜色恢复主题默认值。
      _feedbackColor = null;
      // 根据新的 _wordIndex 生成四个拼写候选项。
      _options = _buildOptions();
    });
    // 与首次进入页面一致，新题自动发音一次。
    unawaited(_playAudio());
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
      final isMeaningActive = !_isCurrentWordComplete &&
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
      final pos = meaning.pos.trim().isEmpty ? '释义' : meaning.pos.trim();
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
    final pos = meaning.pos.isEmpty ? '释义' : meaning.pos;
    return '$pos · 选择释义 ${_definitionIndex + 1}/${meaning.definitions.length}';
  }

  @override
  void dispose() {
    unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final progress =
        (_isDone ? widget.words.length : _wordIndex + 1) / widget.words.length;

    return Scaffold(
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
              // 默写页没有设置按钮，但保留与左侧完全等宽的空画布以确保题号绝对居中。
              const SizedBox(
                key: Key('dictation-header-trailing-space'),
                width: DictationLayout.headerButtonSize,
                height: DictationLayout.headerButtonSize,
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
    // Column 把中间答题信息与固定底部操作区分成两个独立区域。
    return Column(
      children: [
        // Expanded 让中间区占用底部操作区之外的全部剩余高度。
        Expanded(
          // SingleChildScrollView 只负责内容过高时滚动，默认位置从顶部开始。
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: DictationLayout.pageInset,
              vertical: DictationLayout.questionVerticalInset,
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
        // 未完成时显示四选一与工具按钮，完成后整组替换为蓝色长条下一题按钮。
        _isCurrentWordComplete
            ? _buildNextQuestionButton()
            : _buildBottomControls(tokens),
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
                      key: ValueKey('dictation-option-$index-${_options[index].text}'),
                      option: _options[index],
                      index: index,
                      wrong: _wrongOptions.contains(_options[index].text),
                      onTap: () => _pickOption(_options[index]),
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

  /// 构建当前单词全部答对后的蓝色长条推进按钮。
  Widget _buildNextQuestionButton() {
    // 最后一个单词之后没有新题，此时按钮文案改为“完成”。
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
      // SizedBox 让按钮占满左右留白之间的全部宽度。
      child: SizedBox(
        width: double.infinity,
        height: DictationLayout.actionHeight,
        // FilledButton.icon 用蓝色背景表达当前唯一的主操作。
        child: FilledButton.icon(
          key: const Key('next-dictation-word'),
          onPressed: _goToNextWord,
          // 最后一题使用勾选图标，其他题使用向右箭头。
          icon: Icon(
            isLastWord ? TablerIcons.check : TablerIcons.arrowRight,
            size: 17,
          ),
          // 中间文字明确说明点击后的结果。
          label: Text(isLastWord ? '完成' : '下一题'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTokens.accent,
            foregroundColor: Colors.white,
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
    );
  }

  Widget _buildDone(AppTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Text(
              '默写完成',
              style: TextStyle(
                color: tokens.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '共 ${widget.words.length} 个单词 · 答错 $_errors 次',
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
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
    ).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeOut),
    );
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
