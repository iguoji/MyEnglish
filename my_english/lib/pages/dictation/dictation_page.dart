// dart:async 提供 unawaited，播放音频时不阻塞按钮响应。
import 'dart:async';
// dart:math 用于打乱答案顺序和生成干扰项。
import 'dart:math';
// material.dart 提供全屏页面、进度条、卡片与按钮。
import 'package:flutter/material.dart';
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
        _feedback = '已显示开头字母';
        _feedbackColor = null;
      });
      return;
    }
    final definition =
        _availableMeanings[_meaningIndex].definitions[_definitionIndex];
    setState(() {
      _feedback = definition.isEmpty ? '当前释义为空' : '提示：以「${definition[0]}」开头';
      _feedbackColor = null;
    });
  }

  /// 选择答案：错项变红并禁用；正确时推进到下一小题。
  void _pickOption(DictationOption option) {
    // 当前单词完成后已经只能点击“下一题”，旧选项不再响应。
    if (_isDone ||
        _isCurrentWordComplete ||
        _wrongOptions.contains(option.text)) {
      return;
    }
    if (!option.isCorrect) {
      setState(() {
        _wrongOptions.add(option.text);
        _errors++;
        _feedback = '不对，再试试';
        _feedbackColor = AppTokens.danger;
      });
      return;
    }

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
  }

  /// 用户点击底部长条按钮后进入下一词；最后一词则显示统计页。
  void _goToNextWord() {
    // 只有当前题已完成才允许推进，防止外部误调用跳过题目。
    if (!_isCurrentWordComplete || _isDone) return;
    // 已经处于最后一个单词时，下一步是整轮完成页。
    if (_wordIndex + 1 >= widget.words.length) {
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

  /// 已答对的 Meaning，用于逐步补全第三个子模块中的只读卡片列表。
  List<Meaning> get _solvedMeanings {
    // 当前单词完成后必须展示完整含义，包括刚刚答对的最后一条。
    if (_isCurrentWordComplete) {
      // 返回原模型列表的只读视图，不在默写页中重新排序或合并释义。
      return List<Meaning>.unmodifiable(_availableMeanings);
    }
    // 拼写阶段尚未开始公开释义。
    if (_stage != DictationStage.definition) return const <Meaning>[];
    // solvedMeanings 相当于 PHP 中根据答题下标切片后得到的新数组。
    final solvedMeanings = <Meaning>[];
    // 已经完整答完的词性块可以直接复用原 Meaning 对象。
    for (var meaningIndex = 0; meaningIndex < _meaningIndex; meaningIndex++) {
      solvedMeanings.add(_availableMeanings[meaningIndex]);
    }
    // 当前词性只有在至少答对一条释义时才进入 Meaning 列表。
    if (_definitionIndex > 0) {
      final meaning = _availableMeanings[_meaningIndex];
      // 新建一个只含已答对释义的 Meaning，原始 Word 数据不会被页面修改。
      solvedMeanings.add(
        Meaning(
          index: meaning.index,
          pos: meaning.pos,
          definitions: List<String>.unmodifiable(
            meaning.definitions.take(_definitionIndex),
          ),
        ),
      );
    }
    // 冻结返回列表，展示组件只能读取，不能意外改变答题状态。
    return List<Meaning>.unmodifiable(solvedMeanings);
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
                onTap: () => Navigator.pop(context),
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
                // 独立组件按“单词占位卡、提示信息、Meaning 列表”从上到下输出。
                child: DictationQuestionContent(
                  spelling: _currentWord.spelling,
                  revealedLetterCount: _hintLevel,
                  revealWholeWord:
                      _stage == DictationStage.definition ||
                      _isCurrentWordComplete,
                  prompt: _stageLabel,
                  feedback: _feedback,
                  feedbackColor: _feedbackColor,
                  solvedMeanings: _solvedMeanings,
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
                    // 每个选项保留原有正确、错误和禁用逻辑。
                    _buildOption(tokens, _options[index], index),
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

  /// 构建一个候选词按钮，错误选项会变红并停止接收点击。
  Widget _buildOption(AppTokens tokens, DictationOption option, int index) {
    // 先从错误集合判断当前选项是否已经答错。
    final wrong = _wrongOptions.contains(option.text);
    // Material 提供按压水波纹需要的材质层和错误态背景。
    return Material(
      key: Key('dictation-option-$index'),
      color: wrong ? AppTokens.danger.withValues(alpha: 0.08) : tokens.card,
      borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
      // InkWell 负责点击；错误选项传入 null 后会自动禁用。
      child: InkWell(
        onTap: wrong ? null : () => _pickOption(option),
        borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
        // Container 固定每行高度并绘制对应状态的边框。
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
          // Stack 让左侧 badge 和中央候选文字分别依据按钮自身定位，互不挤压。
          child: Stack(
            alignment: Alignment.center,
            children: [
              // A/B/C/D 使用固定灰色正方形 badge，并始终贴齐按钮内容区左侧。
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: Key('dictation-option-badge-$index'),
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
                    // 轻微圆角仍保持清晰的正方形轮廓，不使用胶囊形状。
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    String.fromCharCode('A'.codeUnitAt(0) + index),
                    style: TextStyle(
                      color: wrong ? AppTokens.danger : tokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // 左右使用相同预留宽度，候选文本的中心仍等于整个按钮的中心。
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal:
                      DictationLayout.optionBadgeSize +
                      DictationLayout.optionHorizontalInset,
                ),
                // 最多显示两行文字，过长候选词使用省略号保护固定行高。
                child: Text(
                  option.text,
                  key: Key('dictation-option-label-$index'),
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
              onPressed: () => Navigator.pop(context),
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
