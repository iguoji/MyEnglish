// material.dart 提供文字、纵向布局、骨架容器和 TextPainter。
import 'package:flutter/material.dart';

// 引入全局设计令牌。
import '../../../common/theme.dart';
// 引入单条词性与释义模型。
import '../../../models/meaning.dart';
// 引入单词模型。
import '../../../models/word.dart';
// 引入随身听统一布局尺寸。
import 'listening_layout.dart';

/// 答案卡正文组件，负责按“单词 → 词性 → 释义”的流程输出内容。
class ListeningAnswerContent extends StatelessWidget {
  /// 父页面传入当前单词和显示状态，本组件不自行保存业务数据。
  const ListeningAnswerContent({
    required this.word,
    required this.tokens,
    required this.definitionSeparator,
    required this.revealed,
    super.key,
  });

  /// 当前正在播放并需要展示的单词。
  final Word word;

  /// 当前主题颜色集合。
  final AppTokens tokens;

  /// 同一词性下多条释义之间使用的全角分隔符。
  final String definitionSeparator;

  /// true 显示真实单词和释义，false 在相同布局槽位内显示骨架。
  final bool revealed;

  /// Flutter 每次切换单词或显隐状态时都会重新调用 build。
  @override
  Widget build(BuildContext context) {
    // 单词样式只定义一次，真实文字和隐藏态的高度测量都会使用它。
    final spellingStyle = TextStyle(
      color: tokens.text,
      fontSize: 22,
      fontWeight: FontWeight.w600,
    );
    // 释义样式同样由真实内容和骨架占位共同使用，避免两套参数逐渐不一致。
    final definitionStyle = TextStyle(
      color: tokens.text,
      fontSize: 13.5,
      height: 1.5,
    );
    // Column 对应小程序纵向 flex，所有正文从左侧开始排列。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 单词槽位会按真实拼写测量高度，隐藏时只把内部替换成骨架。
        _StableAnswerSlot(
          key: const Key('listening-spelling-slot'),
          text: word.spelling,
          style: spellingStyle,
          revealed: revealed,
          // 骨架宽度按字符数估算，并限制在布局表定义的最大值以内。
          skeletonWidth:
              (ListeningLayout.spellingSkeletonBaseWidth +
                      word.spelling.length *
                          ListeningLayout.spellingSkeletonCharacterWidth)
                  .clamp(0, ListeningLayout.spellingSkeletonMaxWidth)
                  .toDouble(),
          skeletonHeight: 26,
          skeletonRadius: 6,
          skeletonColor: tokens.sub,
        ),
        // 单词与第一条词性之间保持固定 12 像素距离。
        const SizedBox(height: 12),
        // 每条 Meaning 交给独立组件，作用类似小程序 wx:for 渲染子组件。
        for (final meaning in word.meanings)
          _MeaningAnswerBlock(
            meaning: meaning,
            definitionSeparator: definitionSeparator,
            definitionStyle: definitionStyle,
            tokens: tokens,
            revealed: revealed,
          ),
        // 提示隐藏后仍保留原高度，避免长内容滚到底部时因总高度变化而校正滚动位置。
        Visibility(
          // 只有答案隐藏时真正绘制提示。
          visible: !revealed,
          // 以下三个 maintain 属性让隐藏后的提示继续占据相同布局高度。
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: Text(
            '按住卡片临时查看，点右上角眼睛常显',
            style: TextStyle(color: tokens.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// 一条“词性 + 释义”的答案块，对应小程序列表中的单个 meaning 子组件。
class _MeaningAnswerBlock extends StatelessWidget {
  /// 所有影响排版的数据都由父组件传入，避免子组件产生额外状态。
  const _MeaningAnswerBlock({
    required this.meaning,
    required this.definitionSeparator,
    required this.definitionStyle,
    required this.tokens,
    required this.revealed,
  });

  /// 当前词性和它的全部中文释义。
  final Meaning meaning;

  /// 多条释义之间使用的全角连接符号。
  final String definitionSeparator;

  /// 与真实文字高度测量共用的释义样式。
  final TextStyle definitionStyle;

  /// 当前主题颜色集合。
  final AppTokens tokens;

  /// 是否显示真实释义。
  final bool revealed;

  /// Flutter 绘制当前词性块时调用 build。
  @override
  Widget build(BuildContext context) {
    // 一个词性的 definitions 先连接成同一段文字，避免不必要的强制换行。
    final joinedDefinitions = meaning.definitions.join(definitionSeparator);
    // 骨架只估算视觉宽度，真实行高仍由 _StableAnswerSlot 精确测量。
    final skeletonWidth =
        (ListeningLayout.definitionSkeletonBaseWidth +
                joinedDefinitions.length *
                    ListeningLayout.definitionSkeletonCharacterWidth)
            .clamp(0, ListeningLayout.definitionSkeletonMaxWidth)
            .toDouble();
    // Column 让词性、间距和释义纵向排列。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 词性始终可见，不参与答案遮挡。
        Text(
          meaning.displayPos,
          // 稳定 key 让测试可以读取按住前后的绝对坐标。
          key: Key('listening-pos-${meaning.index}'),
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12.5,
            // 词性使用正常字体（用户明确不想要斜体）。
            fontStyle: FontStyle.normal,
          ),
        ),
        // 词性与释义之间固定保留 7 像素。
        const SizedBox(height: 7),
        // 底部 7 像素将当前释义和下一条词性分隔开。
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          // 释义槽位提前预留真实文字换行高度，显示时不会推动后续内容。
          child: _StableAnswerSlot(
            key: Key('listening-definition-${meaning.index}'),
            text: joinedDefinitions,
            style: definitionStyle,
            revealed: revealed,
            skeletonWidth: skeletonWidth,
            skeletonHeight: 15,
            skeletonRadius: 5,
            skeletonColor: tokens.sub,
          ),
        ),
      ],
    );
  }
}

/// 在同一高度内切换真实文字与骨架，作用类似小程序先计算行高再切换 visibility。
class _StableAnswerSlot extends StatelessWidget {
  /// 创建稳定槽位，真实文字和骨架所需数据都由父组件明确传入。
  const _StableAnswerSlot({
    required this.text,
    required this.style,
    required this.revealed,
    required this.skeletonWidth,
    required this.skeletonHeight,
    required this.skeletonRadius,
    required this.skeletonColor,
    super.key,
  });

  /// 最终需要显示的真实文字，也是隐藏态计算高度的数据源。
  final String text;

  /// 真实文字样式；字号、行高和字体都会参与高度计算。
  final TextStyle style;

  /// true 绘制文字，false 绘制骨架。
  final bool revealed;

  /// 骨架期望宽度，超过卡片可用宽度时会自动收窄。
  final double skeletonWidth;

  /// 骨架自身高度。
  final double skeletonHeight;

  /// 骨架圆角大小。
  final double skeletonRadius;

  /// 骨架背景颜色。
  final Color skeletonColor;

  /// Flutter 每次排版答案内容时调用 build。
  @override
  Widget build(BuildContext context) {
    // LayoutBuilder 提供当前卡片的真实可用宽度，等价于小程序读取节点宽度后计算换行。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 合并页面默认字体，保证 TextPainter 与最终 Text 使用完全相同的字体参数。
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
        // TextPainter 只做排版测量，不会把真实答案绘制到隐藏界面。
        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        // 先保存真实文字按当前宽度换行后的高度。
        final measuredTextHeight = painter.height;
        // 测量对象已完成使命，立即释放其内部段落资源。
        painter.dispose();
        // 槽位至少容纳骨架，也必须完整容纳真实文字；两种状态始终使用同一高度。
        final stableHeight = measuredTextHeight > skeletonHeight
            ? measuredTextHeight
            : skeletonHeight;
        // 桌面窄窗口或大字号下，骨架不能超过卡片当前可用宽度。
        final visibleSkeletonWidth = constraints.hasBoundedWidth
            ? skeletonWidth.clamp(0.0, constraints.maxWidth).toDouble()
            : skeletonWidth;
        // SizedBox 固定这一行最终参与父级 Column 排版的高度。
        return SizedBox(
          width: double.infinity,
          height: stableHeight,
          child: Align(
            alignment: Alignment.topLeft,
            // 只替换槽位内部内容，父级尺寸和后续词性坐标不会变化。
            child: revealed
                ? Text(text, style: effectiveStyle)
                : Container(
                    width: visibleSkeletonWidth,
                    height: skeletonHeight,
                    decoration: BoxDecoration(
                      color: skeletonColor,
                      borderRadius: BorderRadius.circular(skeletonRadius),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
