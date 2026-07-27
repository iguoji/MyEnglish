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
    super.key,
  });

  /// 本轮参与默写的单词。
  final List<Word> words;

  /// 与首页、随身听共用的发音服务。
  final WordAudioPlayer audioPlayer;

  /// 当前发音口音。
  final PronunciationAccent accent;

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
  // 发音图标是否显示。
  bool _isPlaying = false;
  // 底部反馈文案。
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

  @override
  void initState() {
    super.initState();
    _options = _buildOptions();
    // 与原型一致，进入每个新词后自动播放一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _playAudio());
  }

  /// 生成当前阶段的一个正确答案和三个干扰答案。
  List<DictationOption> _buildOptions() {
    final correct = _stage == DictationStage.word
        ? _currentWord.spelling
        : _availableMeanings[_meaningIndex].definitions[_definitionIndex];
    final variants = _stage == DictationStage.word
        ? _wordVariants(correct)
        : _definitionVariants(correct);
    final options = <DictationOption>[
      DictationOption(text: correct, isCorrect: true),
      for (final variant in variants.take(3))
        DictationOption(text: variant, isCorrect: false),
    ];
    options.shuffle(_random);
    return options;
  }

  /// 通过交换、删除或替换字母生成拼写干扰项。
  List<String> _wordVariants(String word) {
    final output = <String>{};
    final letters = word.split('');
    if (letters.length > 2) {
      final swapped = [...letters];
      final first = max(1, letters.length ~/ 3);
      final second = min(letters.length - 1, first + 1);
      final temp = swapped[first];
      swapped[first] = swapped[second];
      swapped[second] = temp;
      output.add(swapped.join());
    }
    // 上面的级联写法不适合取 join 结果，因此显式补一个删除版本。
    if (letters.length > 1) {
      final removed = [...letters]..removeAt(letters.length ~/ 2);
      output.add(removed.join());
    }
    final vowels = <String>['a', 'e', 'i', 'o', 'u'];
    final replaced = [...letters];
    if (replaced.isNotEmpty) {
      final index = replaced.length ~/ 2;
      replaced[index] = vowels.firstWhere(
        (value) => value != replaced[index].toLowerCase(),
        orElse: () => 'a',
      );
      output.add(replaced.join());
    }
    var suffix = 1;
    while (output.length < 3) {
      output.add('$word${String.fromCharCode(96 + suffix)}');
      suffix++;
    }
    output.remove(word);
    return output.take(3).toList(growable: false);
  }

  /// 通过替换、删除和交换汉字生成释义干扰项。
  List<String> _definitionVariants(String definition) {
    final output = <String>{};
    final chars = definition.split('');
    if (chars.length > 2) {
      final swapped = [...chars];
      final index = chars.length ~/ 2;
      final next = min(chars.length - 1, index + 1);
      final temp = swapped[index];
      swapped[index] = swapped[next];
      swapped[next] = temp;
      output.add(swapped.join());

      final removed = [...chars]..removeAt(index);
      output.add(removed.join());
    }
    if (chars.isNotEmpty) {
      final replaced = [...chars];
      replaced[chars.length ~/ 2] = '意';
      output.add(replaced.join());
    }
    var suffix = 1;
    while (output.length < 3) {
      // 用列表重复并拼接字符，效果类似 PHP 的 str_repeat，初学者更易理解。
      output.add('$definition${List<String>.filled(suffix, '呀').join()}');
      suffix++;
    }
    output.remove(definition);
    return output.take(3).toList(growable: false);
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
    if (_isDone) return;
    if (_stage == DictationStage.word) {
      setState(() {
        _hintLevel = min(
          max(1, _currentWord.spelling.length - 1),
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
    if (_isDone || _wrongOptions.contains(option.text)) return;
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
        _nextWord('正确！');
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
      _nextWord('本词完成！');
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

  /// 完成当前词并进入下一词；最后一词结束后显示统计页。
  void _nextWord(String message) {
    if (_wordIndex + 1 >= widget.words.length) {
      setState(() {
        _isDone = true;
        _isPlaying = false;
        _feedback = '';
      });
      unawaited(widget.audioPlayer.stop().catchError((Object _) {}));
      return;
    }
    setState(() {
      _wordIndex++;
      _stage = DictationStage.word;
      _meaningIndex = 0;
      _definitionIndex = 0;
      _hintLevel = 0;
      _wrongOptions.clear();
      _feedback = message;
      _feedbackColor = const Color(0xFF2FB344);
      _options = _buildOptions();
    });
    unawaited(_playAudio());
  }

  /// 当前拼写显示：单词阶段只公开提示字母，其余改成下划线。
  String get _shownWord {
    if (_stage == DictationStage.definition) return _currentWord.spelling;
    final letters = _currentWord.spelling.split('');
    return [
      for (var index = 0; index < letters.length; index++)
        index < _hintLevel ? letters[index] : '_',
    ].join(' ');
  }

  /// 已答对的释义，用于逐步补全答案卡。
  List<({String pos, String definition})> get _solvedDefinitions {
    if (_stage != DictationStage.definition) return const [];
    final rows = <({String pos, String definition})>[];
    for (var meaningIndex = 0; meaningIndex < _meaningIndex; meaningIndex++) {
      final meaning = _availableMeanings[meaningIndex];
      rows.add((pos: meaning.pos, definition: meaning.definitions.join('；')));
    }
    if (_definitionIndex > 0) {
      final meaning = _availableMeanings[_meaningIndex];
      rows.add((
        pos: meaning.pos,
        definition: meaning.definitions.take(_definitionIndex).join('；'),
      ));
    }
    return rows;
  }

  String get _stageLabel {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  _PlainIconButton(
                    key: const Key('close-dictation'),
                    icon: TablerIcons.chevronLeft,
                    onTap: () => Navigator.pop(context),
                  ),
                  Text(
                    '默写',
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_isDone ? widget.words.length : _wordIndex + 1} / ${widget.words.length}',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: AppTokens.accent,
                  backgroundColor: tokens.sub,
                ),
              ),
            ),
            if (_isDone)
              Expanded(child: _buildDone(tokens))
            else
              Expanded(child: _buildQuestion(tokens)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(AppTokens tokens) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              // 新版原型将“提示、播放”放在内容左侧。
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _OutlineAction(
                  key: const Key('dictation-hint'),
                  label: '提示',
                  foreground: tokens.textMedium,
                  border: tokens.inputBorder,
                  onTap: _showHint,
                ),
                const SizedBox(width: 10),
                _OutlineAction(
                  key: const Key('dictation-play'),
                  icon: _isPlaying
                      ? TablerIcons.volume2
                      : TablerIcons.playerPlay,
                  label: '播放',
                  foreground: AppTokens.accent,
                  border: AppTokens.accent,
                  onTap: _playAudio,
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _shownWord,
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    if (_isPlaying)
                      const Icon(
                        TablerIcons.volume2,
                        size: 18,
                        color: AppTokens.accent,
                      ),
                  ],
                ),
                for (final row in _solvedDefinitions) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          row.pos,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.definition,
                          style: TextStyle(
                            color: tokens.text,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              _stageLabel,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                // 原型选项的最小高度是 48 像素。
                mainAxisExtent: 48,
              ),
              itemCount: _options.length,
              itemBuilder: (context, index) {
                final option = _options[index];
                final wrong = _wrongOptions.contains(option.text);
                return Material(
                  color: wrong
                      ? AppTokens.danger.withValues(alpha: 0.08)
                      : tokens.card,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: wrong ? null : () => _pickOption(option),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: wrong ? AppTokens.danger : tokens.inputBorder,
                        ),
                      ),
                      child: Text(
                        option.text,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: TextStyle(
                          color: wrong ? AppTokens.danger : tokens.text,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Text(
              // 原型反馈区只使用文字颜色表达状态，不添加额外图标。
              _feedback,
              style: TextStyle(
                color: _feedbackColor ?? tokens.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
  const _PlainIconButton({required this.icon, required this.onTap, super.key});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Icon(icon, size: 23, color: tokens.text),
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    required this.foreground,
    required this.border,
    required this.onTap,
    this.icon,
    super.key,
  });

  // 仅当原型存在图标语义时传入 Tabler 图标；纯文字按钮保持纯文字。
  final IconData? icon;
  final String label;
  final Color foreground;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: tokens.card,
      side: BorderSide(color: border),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return SizedBox(
      // 与原型一致，操作按钮固定 32 像素高。
      height: 32,
      child: icon == null
          ? OutlinedButton(
              onPressed: onTap,
              style: buttonStyle,
              child: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 15),
              label: Text(label),
              style: buttonStyle,
            ),
    );
  }
}
