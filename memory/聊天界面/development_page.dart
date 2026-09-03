// dart:async 提供页面计时器、延迟切题和 unawaited 异步播放。

import 'dart:async';
// dart:math 用于让键入中的圆点产生轻微呼吸动画，并稳定打乱候选项。
import 'dart:math' as math;

// material.dart 提供页面骨架、列表、按钮、动画和文本布局。
import 'package:flutter/material.dart';
// HapticFeedback 让选项点按有轻微触觉反馈，和其他复习页面保持一致。
import 'package:flutter/services.dart';
// 所有可见图标都使用本地保存的 Tabler 图标，不依赖网络字体。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 复用应用统一的日期计时格式。
import '../../common/date.dart';
// 复用应用统一的颜色令牌，自动适配亮色和深色主题。
import '../../common/theme.dart';
// 单条释义模型，用于生成题目和候选项。
import '../../models/meaning.dart';
// 单词模型，演示页只读它，不修改里面的任何字段。
import '../../models/word.dart';
// 发音服务沿用正式复习模块的轮转渠道逻辑。
import '../../services/word_audio.dart';
// 当前用户选择的美式/英式发音设置。
import '../../store/settings.dart';
// 词库读取接口；本页面不会调用任何写入方法。
import '../../store/word.dart';
// 聊天气泡、键盘和顶部尺寸所对应的原型布局常量。
import 'widgets/development_layout.dart';

part 'widgets/development_answer_area.dart';
part 'widgets/development_bubbles.dart';
part 'widgets/development_controls.dart';
part 'widgets/development_feedback.dart';
part 'widgets/development_models.dart';

///
/// 「开发模块」二级页面。
///
/// 这是一个纯演示页面：进入后只读当前词库，按 id 升序取前 50 个单词，
/// 不创建会话、不记录点击、不更新难度、不保存候选项。退出页面后演示状态
/// 随页面一起销毁，下一次进入会重新从第一题开始。
///
class DevelopmentPage extends StatefulWidget {
  /// 创建开发模块演示页。
  const DevelopmentPage({
    required this.wordStore,
    required this.audioPlayer,
    required this.accent,
    super.key,
  });

  /// 只读获取全部单词的接口。
  final WordStore wordStore;

  /// 复用首页传入的音频播放器。
  final WordAudioPlayer audioPlayer;

  /// 用户在设置中选择的发音口音。
  final PronunciationAccent accent;

  @override
  State<DevelopmentPage> createState() => _DevelopmentPageState();
}

///
/// 开发模块页面状态。
///
/// 页面状态只存在内存中，所有字段都服务于当前演示画面，没有任何持久化
/// 出口。生命周期观察用于让右上角已用时间在 App 进入后台时暂停，行为与
/// 听音辨义模块一致。
///
class _DevelopmentPageState extends State<DevelopmentPage>
    with WidgetsBindingObserver {
  /// 顶部返回按钮和系统返回手势共用的退出方法。
  final GlobalKey _pageKey = GlobalKey();

  /// 聊天列表控制器，用于每次追加消息后滚到最下方。
  final ScrollController _chatController = ScrollController();

  /// 固定在进度条下方的最新系统题目气泡，用于测量动态高度。
  final GlobalKey _pinnedQuestionKey = GlobalKey();

  /// 用于判断系统题目是否已经被滚动到聊天区域之外。
  final GlobalKey _latestQuestionKey = GlobalKey();

  /// 聊天区域的可视范围，用来计算题目是否已经离开屏幕。
  final GlobalKey _chatViewportKey = GlobalKey();

  /// 最新题目气泡的实际高度；释义展开后会自动更新，避免历史消息被遮住。
  double _pinnedQuestionHeight = 0;

  /// 避免同一帧内因为多个状态变化重复安排尺寸同步。
  bool _pinnedHeightSyncScheduled = false;

  /// 已经被推出聊天可视区域、需要暂时固定的系统题目消息。
  _DevelopmentMessage? _pinnedQuestion;

  /// 避免同一帧内重复检查最新题目的可见状态。
  bool _latestVisibilityCheckScheduled = false;

  /// 当前用于显示的前 50 个单词。
  List<Word> _words = const <Word>[];

  /// 聊天消息记录，只保存本次进入页面后的内存状态。
  final List<_DevelopmentMessage> _messages = <_DevelopmentMessage>[];

  /// 五种题型的当前下标。
  int _kindIndex = 0;

  /// 词库的当前下标。
  int _wordIndex = 0;

  /// 当前正在答的题目。
  _DevelopmentQuestion? _activeQuestion;

  /// 是否正在读取本地词库。
  bool _isLoading = true;

  /// 词库读取失败时使用的页面级错误状态。
  bool _loadFailed = false;

  /// 顶部计时器显示的已用秒数。
  int _elapsedSeconds = 0;

  /// 页面计时器；进入后台时取消，回到前台时重新创建。
  Timer? _elapsedTimer;

  /// 新题的“正在输入”动画结束定时器。
  Timer? _questionRevealTimer;

  /// 下一条题目的延迟切换定时器。
  Timer? _nextQuestionTimer;

  /// 选错后红色光晕的复位定时器。
  Timer? _wrongFlashTimer;

  /// 防止页面退出后仍然响应音频 Future 的当前播放题目。
  _DevelopmentQuestion? _playingQuestion;

  /// 五种题型固定顺序，单独列出便于读懂“轮流出题”的规则。
  static const List<_DevelopmentQuestionKind> _questionKinds =
      <_DevelopmentQuestionKind>[
        _DevelopmentQuestionKind.spellingMeaning,
        _DevelopmentQuestionKind.listeningWord,
        _DevelopmentQuestionKind.listeningMeaning,
        _DevelopmentQuestionKind.listeningSpelling,
        _DevelopmentQuestionKind.meaningWord,
      ];

  /// 空词库时用于补足四选一候选的静态演示文字。
  static const List<String> _meaningDistractors = <String>[
    '世界',
    '记忆',
    '道路',
    '返回',
    '安静的',
    '快速的',
    '建造',
    '温暖的',
    '寻找',
    '聆听',
  ];

  /// 页面第一次创建时启动数据读取、计时与前后台观察。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatController.addListener(_handleChatScroll);
    _startElapsedTimer();
    unawaited(_loadDemoWords());
  }

  /// 页面销毁时清理所有计时器、滚动控制器和正在播放的发音。
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTimer?.cancel();
    _questionRevealTimer?.cancel();
    _nextQuestionTimer?.cancel();
    _wrongFlashTimer?.cancel();
    _chatController.removeListener(_handleChatScroll);
    _chatController.dispose();
    // 音频停止是异步通道调用，页面不需要等待它完成才能销毁。
    unawaited(widget.audioPlayer.stop());
    super.dispose();
  }

  /// App 进入后台时暂停时间和发音，回到前台后继续计时。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startElapsedTimer();
      return;
    }
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    unawaited(widget.audioPlayer.stop());
    if (mounted && _playingQuestion != null) {
      setState(() {
        _playingQuestion?.isPlaying = false;
        _playingQuestion = null;
      });
    }
  }

  /// 创建每秒加一的已用时间计时器。
  void _startElapsedTimer() {
    if (_elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
  }

  /// 读取、排序并截取演示词库。
  Future<void> _loadDemoWords() async {
    try {
      final allWords = await widget.wordStore.getAll();
      // “按 id 升序”只对真实数据库主键有意义；没有 id 的临时对象不加入演示。
      final selected = allWords.where((word) => word.id != null).toList()
        ..sort((first, second) => first.id!.compareTo(second.id!));
      final demoWords = List<Word>.unmodifiable(selected.take(50));
      if (!mounted) return;
      setState(() {
        _words = demoWords;
        _isLoading = false;
        _loadFailed = false;
      });
      if (demoWords.isNotEmpty) {
        _queueNextQuestion();
      }
    } catch (error) {
      // 对用户只展示可理解的提示，详细异常留给调试日志定位。
      debugPrint('开发模块读取演示词库失败：$error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  /// 根据当前词和题型创建一道新题。
  _DevelopmentQuestion _createQuestion() {
    final word = _words[_wordIndex];
    final kind = _questionKinds[_kindIndex];
    final meanings = _meaningsOf(word);

    switch (kind) {
      case _DevelopmentQuestionKind.spellingMeaning:
        return _DevelopmentQuestion(kind: kind, word: word, meanings: meanings);
      case _DevelopmentQuestionKind.listeningWord:
        return _DevelopmentQuestion(
            kind: kind,
            word: word,
            meanings: meanings,
            correctAnswer: word.spelling,
          )
          ..options = _wordOptions(
            word.spelling,
            seed: (word.id ?? _wordIndex) + 11,
          );
      case _DevelopmentQuestionKind.listeningMeaning:
        final correct = meanings.first.definition;
        return _DevelopmentQuestion(
            kind: kind,
            word: word,
            meanings: meanings,
            correctAnswer: correct,
          )
          ..options = _meaningOptions(
            correct,
            seed: (word.id ?? _wordIndex) + 23,
          );
      case _DevelopmentQuestionKind.listeningSpelling:
        return _DevelopmentQuestion(kind: kind, word: word, meanings: meanings);
      case _DevelopmentQuestionKind.meaningWord:
        final correctMeaning = meanings.first.definition;
        return _DevelopmentQuestion(
            kind: kind,
            word: word,
            meanings: meanings,
            correctAnswer: word.spelling,
            promptText: correctMeaning,
          )
          ..options = _wordOptions(
            word.spelling,
            seed: (word.id ?? _wordIndex) + 37,
          );
    }
  }

  /// 读取一个单词的全部释义；空释义也能正常进入演示流程。
  List<Meaning> _meaningsOf(Word word) {
    if (word.allMeanings.isNotEmpty) {
      return List<Meaning>.unmodifiable(word.allMeanings);
    }
    // 真实词库通常不会出现空释义，但演示页仍然要能展示一条完整流程。
    return const <Meaning>[Meaning(pos: '*', definition: '暂无释义')];
  }

  /// 生成四个英文候选项，正确项的位置使用稳定随机顺序避免永远在第一项。
  List<String> _wordOptions(String correct, {required int seed}) {
    final pool = <String>{
      for (final word in _words)
        if (word.spelling != correct) word.spelling,
      // 词库不足四个词时仍保留原型的“四选一”外观。
      'example',
      'remember',
      'practice',
      'listen',
    };
    return _fourOptions(correct, pool, seed: seed);
  }

  /// 生成四个中文候选项，优先从当前 50 个词的其他释义中找干扰项。
  List<String> _meaningOptions(String correct, {required int seed}) {
    final pool = <String>{
      for (final word in _words)
        for (final meaning in _meaningsOf(word))
          if (meaning.definition != correct) meaning.definition,
      ..._meaningDistractors,
    };
    return _fourOptions(correct, pool, seed: seed);
  }

  /// 把正确答案与干扰项稳定打乱并截取成四个不重复选项。
  List<String> _fourOptions(
    String correct,
    Iterable<String> source, {
    required int seed,
  }) {
    final pool = source.where((value) => value.trim().isNotEmpty).toSet()
      ..remove(correct);
    final distractors = pool.toList()..shuffle(math.Random(seed));
    final options = <String>[correct, ...distractors.take(3)];
    // 只有极少量临时数据时，用不同文字补足 4 张卡，避免布局塌成一列。
    var fillerIndex = 1;
    while (options.length < 4) {
      final filler = '演示选项 $fillerIndex';
      if (!options.contains(filler)) options.add(filler);
      fillerIndex += 1;
    }
    options.shuffle(math.Random(seed + 101));
    return List<String>.unmodifiable(options);
  }

  /// 新题先显示原型中的三个“正在输入”圆点，动画结束后才显示答题区。
  void _queueNextQuestion() {
    if (_words.isEmpty || !mounted) return;
    _questionRevealTimer?.cancel();
    _nextQuestionTimer?.cancel();
    final question = _createQuestion();
    setState(() {
      // 新题出现后，上一道题即使曾经固定在顶部，也必须解除固定，
      // 避免旧题继续占用“当前题目”的冻结状态。
      _pinnedQuestion = null;
      _pinnedQuestionHeight = 0;
      _activeQuestion = question;
      _messages.add(_DevelopmentMessage.question(question));
    });
    _scrollToBottom();
    _questionRevealTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _activeQuestion != question) return;
      setState(() => question.isTyping = false);
      _scrollToBottom();
      if (question.kind.usesAudio) unawaited(_playQuestion(question));
    });
  }

  /// 把单词发音交给正式播放器，同时在气泡上显示播放状态。
  Future<void> _playQuestion(_DevelopmentQuestion question) async {
    if (!question.kind.usesAudio || !mounted) return;
    // 新播放会自动打断旧播放；页面状态同步切换到新题目。
    if (_playingQuestion != null && _playingQuestion != question) {
      _playingQuestion!.isPlaying = false;
    }
    _playingQuestion = question;
    setState(() => question.isPlaying = true);
    try {
      await widget.audioPlayer.playRandomChannel(
        question.word.spelling,
        widget.accent,
      );
    } catch (error) {
      // 演示页即使设备暂时没有网络音频，也应继续允许点选答题。
      debugPrint('开发模块播放发音失败：$error');
    } finally {
      // 旧题目的播放 Future 可能在新题目开始后才结束，只允许它清理自己的状态。
      if (mounted && _playingQuestion == question) {
        setState(() => question.isPlaying = false);
        _playingQuestion = null;
      }
    }
  }

  /// 点击题目气泡里的 Tabler 音量图标时重播当前单词。
  void _replayQuestion(_DevelopmentQuestion question) {
    // 历史题目也保留点击重播能力；只有等待中的占位气泡还没有可播放的
    // 内容，完成态不影响语音题再次播放。
    if (question.isTyping) return;
    unawaited(_playQuestion(question));
  }

  /// 键盘输入一个英文字母。
  void _handleKey(String letter) {
    final question = _activeQuestion;
    if (question == null || question.isTyping || question.isTransitioning) {
      return;
    }
    if (question.stage != _DevelopmentQuestionStage.spelling ||
        question.isDone) {
      return;
    }
    final expectedLength = _lettersOnly(question.word.spelling).length;
    if (question.typedLetters.length >= expectedLength) return;
    HapticFeedback.selectionClick();
    question.typedLetters.add(letter.toLowerCase());
    setState(() {});
    if (question.typedLetters.length == expectedLength) {
      _submitSpelling(question);
    }
  }

  /// 删除键盘输入的最后一个字母。
  void _handleBackspace() {
    final question = _activeQuestion;
    if (question == null || question.isTyping || question.isTransitioning) {
      return;
    }
    if (question.stage != _DevelopmentQuestionStage.spelling ||
        question.typedLetters.isEmpty) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => question.typedLetters.removeLast());
  }

  /// 判断键盘输入是否正确，并按题型进入下一阶段或完成题目。
  void _submitSpelling(_DevelopmentQuestion question) {
    final answer = question.typedLetters.join();
    final correct = _lettersOnly(question.word.spelling).toLowerCase();
    if (answer.toLowerCase() == correct) {
      if (question.kind == _DevelopmentQuestionKind.spellingMeaning) {
        _startMeaningStage(question);
      } else {
        // 听音拼写答对后，先把逐字母槽位收束成一个完整单词，再进入
        // 完成态；这与拼写选义题拼对后的展示保持一致。
        question.spellingSolved = true;
        _completeQuestion(question, question.word.spelling);
      }
      return;
    }
    _showWrongSpelling(question, answer);
  }

  /// 拼写选义题拼对单词后，按原型先显示单词，再开放释义候选。
  void _startMeaningStage(_DevelopmentQuestion question) {
    question.spellingSolved = true;
    question.stage = _DevelopmentQuestionStage.meaning;
    question.meaningIndex = 0;
    question.solvedMeaningCount = 0;
    // 关键：拼写选义题的含义选择阶段必须显式写入当前释义作为正确答案，
    // 否则 _handleChoice 里 `answer != correctAnswer` 始终成立（correctAnswer 为 null），
    // 四个候选会被误判为全部错误，永远无法进入下一步（able 卡死问题）。
    question.correctAnswer = question.meanings.first.definition;
    question.options = _meaningOptions(
      question.correctAnswer!,
      seed: (question.word.id ?? _wordIndex) + 53,
    );
    _messages.add(
      _DevelopmentMessage.user(question.word.spelling, isChecked: true),
    );
    setState(() {});
    _scrollToBottom();
  }

  /// 键盘拼错后留下红色用户气泡，并在短暂反馈后清空输入。
  void _showWrongSpelling(_DevelopmentQuestion question, String answer) {
    question.showWrongFlash = true;
    _messages.add(_DevelopmentMessage.user(answer, isDanger: true));
    HapticFeedback.mediumImpact();
    setState(() {});
    _scrollToBottom();
    _wrongFlashTimer?.cancel();
    _wrongFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _activeQuestion != question) return;
      setState(() {
        question.typedLetters.clear();
        question.showWrongFlash = false;
      });
    });
  }

  /// 处理四选一候选项点击。
  void _handleChoice(_DevelopmentQuestion question, String answer) {
    if (_activeQuestion != question ||
        question.isTyping ||
        question.isTransitioning ||
        question.isDone ||
        question.stage == _DevelopmentQuestionStage.spelling ||
        question.wrongAnswers.contains(answer)) {
      return;
    }
    if (answer != question.correctAnswer) {
      question.wrongAnswers.add(answer);
      question.showWrongFlash = true;
      _messages.add(_DevelopmentMessage.user(answer, isDanger: true));
      HapticFeedback.mediumImpact();
      setState(() {});
      _scrollToBottom();
      _wrongFlashTimer?.cancel();
      _wrongFlashTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted || _activeQuestion != question) return;
        setState(() => question.showWrongFlash = false);
      });
      return;
    }
    HapticFeedback.selectionClick();
    if (question.kind == _DevelopmentQuestionKind.spellingMeaning) {
      _completeMeaningChoice(question, answer);
    } else {
      _completeQuestion(question, answer);
    }
  }

  /// 处理拼写选义题当前释义的正确答案。
  void _completeMeaningChoice(_DevelopmentQuestion question, String answer) {
    question.solvedMeaningCount = question.meaningIndex + 1;
    _messages.add(_DevelopmentMessage.user(answer, isChecked: true));
    final isLast = question.meaningIndex >= question.meanings.length - 1;
    if (isLast) {
      _completeQuestion(question, null, addAnswer: false);
      return;
    }
    question.isTransitioning = true;
    setState(() {});
    _scrollToBottom();
    _nextQuestionTimer?.cancel();
    _nextQuestionTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted || _activeQuestion != question) return;
      question.meaningIndex += 1;
      question.correctAnswer =
          question.meanings[question.meaningIndex].definition;
      question.options = _meaningOptions(
        question.correctAnswer!,
        seed: (question.word.id ?? _wordIndex) + 53 + question.meaningIndex,
      );
      question.wrongAnswers.clear();
      question.isTransitioning = false;
      setState(() {});
      // 答题区重新出现后，聊天区域的可视高度会变小；这次滚动必须放在
      // 状态更新之后，确保使用新的 maxScrollExtent，避免最新消息被遮住。
      _scrollToBottom();
    });
  }

  /// 结束一题，把正确答案加入右侧聊天记录，再自动进入下一题。
  void _completeQuestion(
    _DevelopmentQuestion question,
    String? answer, {
    bool addAnswer = true,
  }) {
    question.stage = _DevelopmentQuestionStage.done;
    question.isTransitioning = false;
    if (addAnswer && answer != null) {
      _messages.add(_DevelopmentMessage.user(answer, isChecked: true));
    }
    setState(() {});
    _scrollToBottom();
    _nextQuestionTimer?.cancel();
    _nextQuestionTimer = Timer(const Duration(milliseconds: 480), () {
      if (!mounted || _activeQuestion != question) return;
      _wordIndex = (_wordIndex + 1) % _words.length;
      _kindIndex = (_kindIndex + 1) % _questionKinds.length;
      _queueNextQuestion();
    });
  }

  /// 只保留英文字母，键盘输入与 ice-cream、ice cream 等演示数据也能比较。
  String _lettersOnly(String value) => value.runes
      .map(String.fromCharCode)
      .where((character) => RegExp(r'[A-Za-z]').hasMatch(character))
      .join();

  /// 监听聊天滚动，分别处理题目冻结和已冻结题目回到原位。
  void _handleChatScroll() {
    if (!mounted || _messages.isEmpty) return;
    final latestIndex = _messages.lastIndexWhere((message) => !message.isUser);
    if (latestIndex < 0) return;
    final latestMessage = _messages[latestIndex];
    if (identical(_pinnedQuestion, latestMessage)) {
      _schedulePinnedQuestionReturnCheck(latestMessage);
    } else if (_pinnedQuestion == null) {
      _scheduleLatestQuestionVisibilityCheck(latestMessage);
    }
  }

  /// 滚动到聊天列表底部，让最新题目和错误消息始终可见。
  void _scrollToBottom() {
    // 如果列表已经在底部，不再创建 220ms 的动画；连续输入/出题时反复
    // animateTo 会让滚动模拟持续运行，是开发页 CPU 升高的主要来源之一。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatController.hasClients) return;
      final position = _chatController.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() < 1) return;
      _chatController.jumpTo(target);
    });
  }

  /// 顶部返回按钮的点击行为；不附带任何演示数据。
  void _exitPage() {
    unawaited(widget.audioPlayer.stop());
    if (mounted) Navigator.of(context).pop();
  }

  /// 页面整体构建：顶部结构复刻听音辨义，底部聊天和答题区复刻 HTML 原型。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      key: _pageKey,
      backgroundColor: tokens.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(tokens),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_loadFailed)
              Expanded(child: _buildEmptyState(tokens, '词库读取失败，请返回首页重试'))
            else if (_words.isEmpty)
              Expanded(child: _buildEmptyState(tokens, '暂无可演示单词\n请先在词库中录入单词'))
            else
              Expanded(child: _buildChat(tokens)),
            if (_words.isNotEmpty && _activeQuestion != null)
              _buildAnswerArea(tokens, _activeQuestion!),
          ],
        ),
      ),
    );
  }

  /// 顶部返回图标、中央进度和右侧已用时间，结构与听音辨义完全一致。
  Widget _buildHeader(AppTokens tokens) {
    final total = _words.isEmpty ? 50 : _words.length;
    final current = _words.isEmpty ? 1 : _wordIndex + 1;
    final progress = _words.isEmpty ? 0.0 : current / total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DevelopmentLayout.pageInset,
            DevelopmentLayout.headerTop,
            DevelopmentLayout.pageInset,
            0,
          ),
          child: SizedBox(
            height: DevelopmentLayout.headerButtonSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$current / $total',
                      key: const Key('development-progress-label'),
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _DevelopmentIconButton(
                    key: const Key('close-development-page'),
                    icon: TablerIcons.chevronLeft,
                    onTap: _exitPage,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatTimerSeconds(_elapsedSeconds),
                    key: const Key('development-elapsed'),
                    style: TextStyle(
                      color: tokens.textMedium,
                      fontSize: DevelopmentLayout.headerTimerTextSize,
                      fontWeight: FontWeight.w700,
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
            DevelopmentLayout.pageInset,
            DevelopmentLayout.progressTop,
            DevelopmentLayout.pageInset,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const Key('development-progress-bar'),
              value: progress.clamp(0.0, 1.0).toDouble(),
              minHeight: DevelopmentLayout.progressHeight,
              color: AppTokens.accent,
              backgroundColor: DevelopmentLayout.progressTrack,
            ),
          ),
        ),
      ],
    );
  }

  /// 空词库或读取失败时的居中提示。
  Widget _buildEmptyState(AppTokens tokens, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DevelopmentLayout.chatInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TablerIcons.messages, size: 32, color: tokens.textSecondary),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  /// 聊天滚动区：消息正常追加到底部，题目被推过顶部后才固定到顶部。
  ///
  /// 最新系统题目仍保留在 [_messages] 中。它刚追加时和普通消息一样处于
  /// 聊天列表底部；当后续用户消息把它的顶部推过聊天区域上沿后，才从滚动
  /// 列表中隐藏并固定到进度条下方。原位置会保留同样高度的占位，以便用户
  /// 回看历史时，题目能够在回到原位置后自动解除固定。
  Widget _buildChat(AppTokens tokens) {
    final pinnedIndex = _messages.lastIndexWhere((message) => !message.isUser);
    final latestMessage = pinnedIndex < 0 ? null : _messages[pinnedIndex];
    final isPinned =
        latestMessage != null && identical(_pinnedQuestion, latestMessage);

    if (latestMessage != null) {
      if (isPinned) {
        _schedulePinnedQuestionHeightSync();
      } else {
        _scheduleLatestQuestionVisibilityCheck(latestMessage);
      }
    }

    return KeyedSubtree(
      key: const Key('development-chat'),
      child: Stack(
        key: _chatViewportKey,
        children: [
          _buildChatList(
            tokens,
            _messages,
            measuredMessage: isPinned ? null : latestMessage,
            hiddenMessage: isPinned ? latestMessage : null,
            padding: const EdgeInsets.all(DevelopmentLayout.chatInset),
          ),
          if (isPinned)
            Positioned(
              top: DevelopmentLayout.chatInset,
              left: DevelopmentLayout.chatInset,
              right: DevelopmentLayout.chatInset,
              child: KeyedSubtree(
                key: _pinnedQuestionKey,
                // 固定后的外层刻意不设置颜色，让聊天内容可以自然透过，
                // 题目气泡自身的背景仍由 _SystemBubbleContainer 绘制。
                child: _buildMessage(context, tokens, latestMessage!),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建可滚动的历史消息列表，统一普通模式和固定题目模式的滚动行为。
  Widget _buildChatList(
    AppTokens tokens,
    List<_DevelopmentMessage> messages, {
    Key? key,
    _DevelopmentMessage? measuredMessage,
    _DevelopmentMessage? hiddenMessage,
    required EdgeInsets padding,
  }) {
    final rows = _buildMessageRows(
      tokens,
      messages,
      measuredMessage: measuredMessage,
      hiddenMessage: hiddenMessage,
    );
    return ListView.separated(
      key: key,
      controller: _chatController,
      padding: padding,
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: DevelopmentLayout.messageGap),
      itemBuilder: (context, index) => rows[index],
    );
  }

  /// 在题目气泡完成布局后读取它的高度，让历史列表为固定内容预留空间。
  ///
  /// 释义区会在拼写完成后展开，固定题目的高度不是一个常量。这里等 Flutter
  /// 完成一帧布局再测量，像给“冻结表头”量出真实高度，避免消息互相覆盖。
  void _schedulePinnedQuestionHeightSync() {
    if (_pinnedHeightSyncScheduled) return;
    _pinnedHeightSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinnedHeightSyncScheduled = false;
      if (!mounted) return;
      final size = _pinnedQuestionKey.currentContext?.size;
      if (size == null || (size.height - _pinnedQuestionHeight).abs() < .5) {
        return;
      }
      final shouldKeepBottom =
          _chatController.hasClients &&
          _chatController.position.pixels >=
              _chatController.position.maxScrollExtent - 24;
      setState(() => _pinnedQuestionHeight = size.height);
      if (shouldKeepBottom) _scrollToBottom();
    });
  }

  /// 检查最新系统题目的顶部是否已经被后续消息推出聊天区域上沿。
  ///
  /// 题目刚出现时不做固定，保持和普通聊天一样追加在底部。只有题目完整
  /// 越过可视区域上沿，且列表仍在底部附近（连续回答造成的典型场景），才切换
  /// 到固定显示；手动浏览历史时不会因为题目在屏幕下方就强行跳到顶部。
  void _scheduleLatestQuestionVisibilityCheck(
    _DevelopmentMessage latestMessage,
  ) {
    if (_latestVisibilityCheckScheduled) return;
    _latestVisibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestVisibilityCheckScheduled = false;
      if (!mounted || identical(_pinnedQuestion, latestMessage)) return;

      final latestContext = _latestQuestionKey.currentContext;
      final viewportContext = _chatViewportKey.currentContext;
      final position = _chatController.hasClients
          ? _chatController.position
          : null;
      if (viewportContext == null || position == null) return;

      final isNearBottom = position.pixels >= position.maxScrollExtent - 24;
      var isAboveViewport = false;
      double? latestHeight;
      if (latestContext == null) {
        // ListView 会回收距离较远的子项。最新题目在底部附近仍然找不到
        // 时，说明它已经被滚到上方并离开了屏幕。
        isAboveViewport = isNearBottom && position.maxScrollExtent > 0;
      } else {
        final latestRenderObject = latestContext.findRenderObject();
        final viewportRenderObject = viewportContext.findRenderObject();
        if (latestRenderObject is RenderBox &&
            viewportRenderObject is RenderBox) {
          final latestTop = latestRenderObject.localToGlobal(Offset.zero).dy;
          latestHeight = latestRenderObject.size.height;
          final viewportTop = viewportRenderObject
              .localToGlobal(Offset.zero)
              .dy;
          // 只要题目顶部越过聊天区域上沿就冻结，不再等整个气泡完全消失。
          isAboveViewport = isNearBottom && latestTop <= viewportTop;
        }
      }

      if (!isAboveViewport) return;
      final shouldKeepBottom = isNearBottom;
      setState(() {
        _pinnedQuestion = latestMessage;
        // 直接使用列表中的实测高度，避免切换为占位时先短暂塌陷一帧。
        if (latestHeight != null) _pinnedQuestionHeight = latestHeight;
      });
      if (shouldKeepBottom) _scrollToBottom();
    });
  }

  /// 检查已冻结题目的原位置是否重新回到聊天区域。
  ///
  /// 冻结题目在列表中保留一个同高占位。用户回看历史、滚动到这个占位的
  /// 顶部重新回到聊天区域上沿时，解除固定，让题目回到正常消息流中，而不是
  /// 一直悬在顶部遮住其他历史内容。
  void _schedulePinnedQuestionReturnCheck(
    _DevelopmentMessage pinnedMessage,
  ) {
    if (_latestVisibilityCheckScheduled) return;
    _latestVisibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestVisibilityCheckScheduled = false;
      if (!mounted || !identical(_pinnedQuestion, pinnedMessage)) return;

      final questionContext = _latestQuestionKey.currentContext;
      final viewportContext = _chatViewportKey.currentContext;
      if (questionContext == null || viewportContext == null) return;

      final questionRenderObject = questionContext.findRenderObject();
      final viewportRenderObject = viewportContext.findRenderObject();
      if (questionRenderObject is! RenderBox ||
          viewportRenderObject is! RenderBox) {
        return;
      }

      final questionTop = questionRenderObject.localToGlobal(Offset.zero).dy;
      final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
      if (questionTop < viewportTop) return;

      // 原位置已经回到聊天区域上沿或更下方，恢复为普通消息流中的题目。
      setState(() {
        _pinnedQuestion = null;
        _pinnedQuestionHeight = 0;
      });
    });
  }

  /// 把消息列表转成“行”列表：连续多条“用户错误”消息收成一个 [_ErrorStack]，
  /// 其余消息保持原样。单条错误不折叠，照常显示。
  List<Widget> _buildMessageRows(
    AppTokens tokens,
    List<_DevelopmentMessage> messages, {
    _DevelopmentMessage? measuredMessage,
    _DevelopmentMessage? hiddenMessage,
  }) {
    final rows = <Widget>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (message.isUser && message.isDanger) {
        final group = <_DevelopmentMessage>[];
        while (index < messages.length &&
            messages[index].isUser &&
            messages[index].isDanger) {
          group.add(messages[index]);
          index += 1;
        }
        if (group.length > 1) {
          rows.add(_ErrorStack(messages: group, tokens: tokens));
        } else {
          rows.add(_buildMessage(context, tokens, group.single));
        }
      } else {
        if (identical(message, hiddenMessage)) {
          // 固定题目仍占据原来的行高，只隐藏内容本身，滚动时才能准确判断
          // 用户是否已经回到这道题原本所在的位置。
          rows.add(
            KeyedSubtree(
              key: _latestQuestionKey,
              child: SizedBox(height: _pinnedQuestionHeight),
            ),
          );
        } else {
          final row = _buildMessage(context, tokens, message);
          rows.add(
            identical(message, measuredMessage)
                ? KeyedSubtree(key: _latestQuestionKey, child: row)
                : row,
          );
        }
        index += 1;
      }
    }
    return rows;
  }

  /// 根据消息身份绘制左侧系统气泡或右侧用户气泡。
  Widget _buildMessage(
    BuildContext context,
    AppTokens tokens,
    _DevelopmentMessage message,
  ) {
    final availableWidth =
        MediaQuery.sizeOf(context).width - DevelopmentLayout.chatInset * 2;
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: availableWidth * .82),
          child: _UserBubble(
            text: message.text ?? '',
            danger: message.isDanger,
            checked: message.isChecked,
            tokens: tokens,
          ),
        ),
      );
    }

    final question = message.question!;
    final isFullWidth =
        question.kind == _DevelopmentQuestionKind.spellingMeaning &&
        question.spellingSolved;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isFullWidth ? availableWidth : availableWidth * .82,
        ),
        child: question.isTyping
            ? const _TypingBubble()
            : question.kind == _DevelopmentQuestionKind.meaningWord
            ? _SystemTextBubble(text: question.promptText ?? '', tokens: tokens)
            : _QuestionBubble(
                question: question,
                tokens: tokens,
                onSpeakerTap: () => _replayQuestion(question),
              ),
      ),
    );
  }

  /// 底部答题区：键盘和四选一候选项共用原型的白底分隔线面板。
  ///
  /// 阶段提示（如“选择含义 1/2”）刻意放在白色面板之外、面板上方，
  /// 对应 HTML 原型的 #phaseFloat（浮在面板之上），避免它看起来像输入区的一部分。
  Widget _buildAnswerArea(AppTokens tokens, _DevelopmentQuestion question) {
    if (question.isTyping || question.isDone || question.isTransitioning) {
      return const SizedBox.shrink();
    }
    final isKeyboard = question.stage == _DevelopmentQuestionStage.spelling;
    final phaseText = question.stage == _DevelopmentQuestionStage.meaning
        ? '选择含义 ${question.meaningIndex + 1}/${question.meanings.length}'
        : null;
    final panel = Container(
      key: const Key('development-answer-area'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        DevelopmentLayout.answerPanelInset,
        // 顶部留出与左右一致的留白：键盘/候选项不再紧贴答题区上边线
        //（之前这一项是 0，所以“padding-top 明显没有”）。
        DevelopmentLayout.answerPanelInset,
        DevelopmentLayout.answerPanelInset,
        // 底部在统一留白之外，再补上刘海屏/Home 指示条的安全区，
        // 避免键盘紧贴屏幕底边。页面 SafeArea 的 bottom 是 false，
        // 所以这里手动把安全距离加进内边距里。
        DevelopmentLayout.answerPanelInset +
            MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isKeyboard)
            _DevelopmentKeyboard(
              onKeyTap: _handleKey,
              onBackspace: _handleBackspace,
              disabled: question.isTyping || question.isTransitioning,
              tokens: tokens,
            )
          else
            _DevelopmentChoices(
              options: question.options,
              wrongOptions: question.wrongAnswers,
              onTap: (answer) => _handleChoice(question, answer),
              tokens: tokens,
            ),
        ],
      ),
    );
    if (phaseText == null) return panel;
    // 阶段提示（HTML 原型 .phase-float）使用 Stack 浮在面板上方，不再单独
    // 占用一块带页面底色的布局区域。提示本身只有文字，没有背景、边框或阴影，
    // 因此不会再出现和聊天区域一样的色块。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        panel,
        Positioned(
          top:
              -(DevelopmentLayout.phaseFloatGap +
                  DevelopmentLayout.phaseFloatLineHeight),
          left: 0,
          right: 0,
          height: DevelopmentLayout.phaseFloatLineHeight,
          child: IgnorePointer(
            child: Center(
              child: Text(
                phaseText,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: DevelopmentLayout.phaseFloatTextSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
