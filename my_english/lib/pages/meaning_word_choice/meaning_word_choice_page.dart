// material.dart 提供全屏页面、进度条与基础布局组件。
import 'package:flutter/material.dart';
// 所有可见图标继续统一使用 Tabler。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入应用设计令牌（颜色、圆角等统一设计变量）。
import '../../common/theme.dart';
// 引入单词模型。
import '../../models/word.dart';
// 引入看义选词页面集中管理的布局尺寸。
import 'widgets/meaning_word_choice_layout.dart';

///
/// 全屏看义选词页面。
///
/// 当前处于「整体框架」阶段：顶栏返回图标、中间数字进度与进度条
/// 已经和听音辨义完全一致，页面其余区域暂时留白，玩法落地后再填充。
///
class MeaningWordChoicePage extends StatefulWidget {
  ///
  /// 创建看义选词页面；本轮需要至少一个单词用于展示题号进度。
  const MeaningWordChoicePage({
    required this.words,
    super.key,
  }) : assert(words.length > 0, '看义选词页至少需要一个学习单词');

  ///
  /// 本轮参与看义选词的单词。
  final List<Word> words;

  @override
  State<MeaningWordChoicePage> createState() => _MeaningWordChoicePageState();
}

class _MeaningWordChoicePageState extends State<MeaningWordChoicePage> {
  ///
  /// 当前正在作答的单词下标，从 0 开始，顶栏题号显示为「下标 + 1」。
  ///
  /// 框架阶段固定停留在第一题，因此声明为 final；等玩法落地后，
  /// 这里会随答题进度递增，届时去掉 final 即可。
  final int _wordIndex = 0;

  ///
  /// 构建看义选词页面：顶栏 + 进度条 + 空白内容区。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 进度 = 已进入的题号 ÷ 总题数；和听音辨义口径一致。
    final progress = (_wordIndex + 1) / widget.words.length;

    return Scaffold(
      backgroundColor: tokens.page,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏与进度条和听音辨义完全一致，四个复习模块切换不跳动。
            _buildHeader(tokens, progress),
            // 内容区暂时留白，玩法落地后替换为真正的答题区。
            Expanded(child: _buildBody(tokens)),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建顶栏与进度条，布局结构与听音辨义页面保持完全一致。
  Widget _buildHeader(AppTokens tokens, double progress) {
    // Column 让顶栏按钮行和进度条从上到下排列。
    return Column(
      // 顶部区域只占自身实际高度，不抢占下方内容区的空间。
      mainAxisSize: MainAxisSize.min,
      children: [
        // Padding 统一管理顶栏与屏幕边界的距离。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MeaningWordChoiceLayout.pageInset,
            MeaningWordChoiceLayout.headerTop,
            MeaningWordChoiceLayout.pageInset,
            0,
          ),
          // Row 将返回按钮、中央进度和右侧占位区排成一行。
          child: Row(
            children: [
              // 返回按钮的 34 像素点击画布直接贴齐左侧页面边距。
              _PlainIconButton(
                key: const Key('close-meaningWordChoice'),
                icon: TablerIcons.chevronLeft,
                alignment: Alignment.centerLeft,
                onTap: () => Navigator.of(context).pop(),
              ),
              // Expanded 占用左右等宽画布之间的全部空间。
              Expanded(
                // 当前题号放在中间，视觉上绝对居中。
                child: Text(
                  '${_wordIndex + 1} / ${widget.words.length}',
                  key: const Key('meaning-word-choice-progress-label'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: MeaningWordChoiceLayout.headerProgressTextSize,
                    fontWeight: FontWeight.w600,
                    // tabularFigures 让每个数字占用相同宽度，题号变化时视觉中心不抖动。
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // 右侧保留与返回按钮等宽的空白画布，让中央题号继续保持绝对居中。
              SizedBox(
                width: MeaningWordChoiceLayout.headerButtonSize,
                height: MeaningWordChoiceLayout.headerButtonSize,
              ),
            ],
          ),
        ),
        // 进度条的左右边界与顶栏严格对齐。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MeaningWordChoiceLayout.pageInset,
            MeaningWordChoiceLayout.progressTop,
            MeaningWordChoiceLayout.pageInset,
            0,
          ),
          // ClipRRect 只把线性进度条的两端裁成轻微圆角。
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
  /// 构建内容区。
  ///
  /// 框架阶段刻意保持空白，只在正中放一行极轻的说明文字，
  /// 让人能确认页面框架已经就位；玩法落地后整块替换掉。
  Widget _buildBody(AppTokens tokens) {
    return Center(
      child: Text(
        '看义选词 · 玩法开发中',
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: 14,
        ),
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

  ///
  /// 需要显示的 Tabler 图标。
  final IconData icon;

  ///
  /// 用户点击图标画布时执行的回调。
  final VoidCallback onTap;

  ///
  /// 图标在 34 像素画布中的对齐方式。
  final AlignmentGeometry alignment;

  ///
  /// Flutter 每次需要绘制顶栏按钮时调用此方法。
  @override
  Widget build(BuildContext context) {
    // 读取当前亮色或深色主题中的文字颜色。
    final tokens = AppTokens.of(context);
    // SizedBox 明确约束点击画布，不让图标自身的透明空间影响顶栏对齐。
    return SizedBox(
      width: MeaningWordChoiceLayout.headerButtonSize,
      height: MeaningWordChoiceLayout.headerButtonSize,
      // InkWell 提供点击命中与圆形按压反馈。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          MeaningWordChoiceLayout.headerButtonSize / 2,
        ),
        // Align 使用正常布局约束对齐图标，不需要负数偏移。
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
