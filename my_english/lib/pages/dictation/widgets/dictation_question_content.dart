// material.dart 提供卡片、文字、布局和主题能力，作用类似小程序页面的 WXML + WXSS。
import 'package:flutter/material.dart';
// Tabler 图标让提示信息与应用中的其他功能图标保持同一套视觉语言。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局颜色令牌，亮色和深色模式会自动选择对应颜色。
import '../../../common/theme.dart';
// Meaning 模型承载一条“词性 + 多个释义”的只读数据。
import '../../../models/meaning.dart';
// 引入默写页面统一维护的尺寸，避免组件内部散落魔法数字。
import 'dictation_layout.dart';

/// 默写页中部内容：上方单词占位卡，下方 Tabler 风格纵向 Steps。
class DictationQuestionContent extends StatelessWidget {
  /// 创建题目内容组件；页面状态只传数据，不把答题业务塞进展示组件。
  const DictationQuestionContent({
    required this.spelling,
    required this.revealedLetterCount,
    required this.revealWholeWord,
    required this.prompt,
    required this.feedback,
    required this.feedbackColor,
    required this.solvedMeanings,
    required this.definitionSeparator,
    super.key,
  });

  /// 当前题目的完整拼写；未答对前只用它计算占位槽数量。
  final String spelling;

  /// 用户点击提示后，应该从左侧公开多少个英文字母。
  final int revealedLetterCount;

  /// true 表示拼写阶段已经完成，此时所有字母槽都填入真实字母。
  final bool revealWholeWord;

  /// 第二个子模块中的当前答题要求。
  final String prompt;

  /// 正确、错误或提示操作产生的即时反馈。
  final String feedback;

  /// 反馈的可选语义色；为空时使用普通次要文字颜色。
  final Color? feedbackColor;

  /// 已经答对并允许公开的 Meaning 列表。
  final List<Meaning> solvedMeanings;

  /// 无障碍朗读多个释义时使用的分隔符，与首页设置保持一致。
  final String definitionSeparator;

  /// 先输出单词占位卡，再输出从提示延伸至词性、含义的纵向步骤。
  @override
  Widget build(BuildContext context) {
    // 按当前主题读取卡片、文字和边框颜色。
    final tokens = AppTokens.of(context);
    // Column 等同小程序中的纵向 flex 容器，单词卡和 Steps 从顶部依次排列。
    return Column(
      key: const Key('dictation-question-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 第一个子模块只负责稳定展示逐字母占位卡。
        _WordPlaceholderCard(
          spelling: spelling,
          revealedLetterCount: revealedLetterCount,
          revealWholeWord: revealWholeWord,
          tokens: tokens,
        ),
        // 单词卡和 Steps 之间使用正常间距，不通过位移调整视觉位置。
        const SizedBox(height: DictationLayout.questionModuleGap),
        // Tabler 风格 Steps 把提示、词性和含义放在同一条纵向阅读轨道上。
        _QuestionSteps(
          prompt: prompt,
          feedback: feedback,
          feedbackColor: feedbackColor,
          meanings: solvedMeanings,
          definitionSeparator: definitionSeparator,
          tokens: tokens,
        ),
      ],
    );
  }
}

/// 第一个子模块：根据真实英文字母数量建立固定占位槽。
class _WordPlaceholderCard extends StatelessWidget {
  /// 接收完整拼写、提示公开数量和当前主题色。
  const _WordPlaceholderCard({
    required this.spelling,
    required this.revealedLetterCount,
    required this.revealWholeWord,
    required this.tokens,
  });

  /// 当前单词完整拼写。
  final String spelling;

  /// 从左到右已经公开的字母数量。
  final int revealedLetterCount;

  /// 是否公开全部字母。
  final bool revealWholeWord;

  /// 父组件已经读取的主题令牌。
  final AppTokens tokens;

  /// 绘制带边框的单词卡，并把全部占位槽作为一个整体居中。
  @override
  Widget build(BuildContext context) {
    // runes 按字符读取拼写，避免直接按 UTF-16 单元拆分造成字符数量错误。
    final characters = spelling.runes
        .map((codePoint) => String.fromCharCode(codePoint))
        .toList(growable: false);
    // 只统计 A-Z 字母；空格或连字符会显示间隔，但不会虚增占位槽。
    final letterCount = characters.where(_isEnglishLetter).length;
    // 未公开答案时，无障碍工具只朗读字母数，不能提前泄露正确拼写。
    final semanticLabel = revealWholeWord ? '单词 $spelling' : '$letterCount 个字母';
    // Material 同时绘制背景、圆角与完整边框，圆角处不会因裁剪丢失边线。
    return Material(
      key: const Key('dictation-word-card'),
      color: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      // Semantics 为读屏保留“字母数量/完整单词”信息，子槽本身不重复朗读。
      child: Semantics(
        label: semanticLabel,
        container: true,
        child: SizedBox(
          key: const Key('dictation-word-slot'),
          height: DictationLayout.wordCardHeight,
          // Padding 防止较长单词直接贴到卡片左右边框。
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DictationLayout.wordCardHorizontalInset,
            ),
            // Center 保证占位槽整体在卡片中水平和垂直居中。
            child: Center(
              // FittedBox 仅在超长单词超过卡片宽度时整体等比缩小。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // ExcludeSemantics 防止每个字母与上方合并语义重复朗读。
                child: ExcludeSemantics(child: _buildSlots(characters)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 把拼写转换为若干字母槽；非字母字符只作为分隔符显示。
  Widget _buildSlots(List<String> characters) {
    // letterIndex 只计算英文字母，因此连字符不会消耗提示公开数量。
    var letterIndex = 0;
    // Row 的宽度由全部槽位决定，再由外层 Center 整体居中。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 使用普通 for 循环，方便同时维护原字符位置与纯字母位置。
        for (
          var characterIndex = 0;
          characterIndex < characters.length;
          characterIndex += 1
        )
          ..._buildCharacter(
            character: characters[characterIndex],
            characterIndex: characterIndex,
            letterIndex: _isEnglishLetter(characters[characterIndex])
                ? letterIndex++
                : null,
            hasFollowingCharacter: characterIndex < characters.length - 1,
          ),
      ],
    );
  }

  /// 为一个字符生成界面节点；返回 List 是为了同时附加相邻字符间距。
  List<Widget> _buildCharacter({
    required String character,
    required int characterIndex,
    required int? letterIndex,
    required bool hasFollowingCharacter,
  }) {
    // 空格只形成单词间隔，不显示文字，也不创建字母占位线。
    if (character.trim().isEmpty) {
      return const <Widget>[SizedBox(width: DictationLayout.wordSpaceWidth)];
    }
    // 连字符或撇号按原文显示，使复合词仍保持正确结构。
    if (letterIndex == null) {
      return <Widget>[
        SizedBox(
          height: DictationLayout.letterSlotHeight,
          child: Center(
            child: Text(
              character,
              style: TextStyle(
                color: tokens.textSecondary,
                // 标点随字母同步放大，避免在 44 像素单词中显得过小。
                fontSize: 36,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (hasFollowingCharacter)
          const SizedBox(width: DictationLayout.letterSlotGap),
      ];
    }
    // 拼写已答对时公开全部字母，否则仅公开提示数量以内的左侧字母。
    final isRevealed = revealWholeWord || letterIndex < revealedLetterCount;
    // 每个英文字母固定使用一个槽位，真实文字出现时不改变任何几何尺寸。
    return <Widget>[
      Container(
        key: Key('dictation-letter-slot-$letterIndex'),
        width: DictationLayout.letterSlotWidth,
        height: DictationLayout.letterSlotHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.check, width: 2)),
        ),
        child: Text(
          isRevealed ? character : '',
          key: Key('dictation-letter-value-$letterIndex'),
          style: TextStyle(
            color: tokens.text,
            // 原字号为 22，本轮按照需求准确放大为两倍的 44。
            fontSize: DictationLayout.wordLetterFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (hasFollowingCharacter)
        const SizedBox(width: DictationLayout.letterSlotGap),
    ];
  }
}

/// Tabler 风格纵向 Steps：第一步是提示，后续步骤是已经公开的 Meaning。
class _QuestionSteps extends StatelessWidget {
  /// 创建整条步骤轨道；业务状态仍由父页面管理。
  const _QuestionSteps({
    required this.prompt,
    required this.feedback,
    required this.feedbackColor,
    required this.meanings,
    required this.definitionSeparator,
    required this.tokens,
  });

  /// 当前答题要求。
  final String prompt;

  /// 当前即时反馈。
  final String feedback;

  /// 反馈的可选语义色。
  final Color? feedbackColor;

  /// 已经答对并允许公开的 Meaning。
  final List<Meaning> meanings;

  /// 无障碍朗读多个释义时使用的分隔符。
  final String definitionSeparator;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 输出一条连续的左侧轨道，所有步骤内容在右侧居上对齐。
  @override
  Widget build(BuildContext context) {
    // 即使尚未答出 Meaning，也保留一个未激活步骤，使提示到含义的流程可见。
    final hasSolvedMeanings = meanings.isNotEmpty;
    return Column(
      key: const Key('dictation-vertical-steps'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第 0 步始终显示当前提示，并连接到下方 Meaning 步骤。
        _VerticalStepItem(
          stepIndex: 0,
          stepKey: const Key('dictation-step-prompt'),
          icon: TablerIcons.bulb,
          isActive: true,
          isLast: false,
          tokens: tokens,
          child: _PromptStepContent(
            prompt: prompt,
            feedback: feedback,
            feedbackColor: feedbackColor,
            tokens: tokens,
          ),
        ),
        // Meaning 步骤使用独立容器 key，便于测试和后续样式定位。
        Column(
          key: const Key('dictation-meaning-section'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasSolvedMeanings)
              // 未答出释义时显示灰色等待节点，而不是伪造一条 Meaning。
              _VerticalStepItem(
                stepIndex: 1,
                stepKey: const Key('dictation-step-meaning-empty'),
                isActive: false,
                isLast: true,
                tokens: tokens,
                child: _MeaningEmptyStep(tokens: tokens),
              )
            else
              // 每个词性块对应一个步骤，多个 Meaning 会沿同一条轨道继续向下排列。
              for (var index = 0; index < meanings.length; index += 1)
                _VerticalStepItem(
                  stepIndex: index + 1,
                  stepKey: Key('dictation-step-meaning-$index'),
                  // 列表图标只表达“这是 Meaning 步骤”，不误导为整个词性已经全部答完。
                  icon: TablerIcons.listDetails,
                  isActive: true,
                  isLast: index == meanings.length - 1,
                  tokens: tokens,
                  child: _MeaningStepContent(
                    meaning: meanings[index],
                    meaningIndex: index,
                    definitionSeparator: definitionSeparator,
                    tokens: tokens,
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

/// 一条纵向 Step：左侧节点和连接线，右侧为当前步骤内容。
class _VerticalStepItem extends StatelessWidget {
  /// 创建一个稳定的纵向步骤行。
  const _VerticalStepItem({
    required this.stepIndex,
    required this.stepKey,
    required this.isActive,
    required this.isLast,
    required this.tokens,
    required this.child,
    this.icon,
  });

  /// 当前步骤下标，用于生成稳定测试 key。
  final int stepIndex;

  /// 直接挂在 Row 上的 key，几何测试能读取真实步骤边界。
  final Key stepKey;

  /// true 使用品牌蓝节点，false 使用灰色等待节点。
  final bool isActive;

  /// 最后一步不再向下绘制连接线。
  final bool isLast;

  /// 激活节点内可选的 Tabler 图标。
  final IconData? icon;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 步骤右侧的具体内容。
  final Widget child;

  /// 使用 IntrinsicHeight 让左侧连接线自动匹配右侧内容高度。
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        key: stepKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 固定宽度的轨道列保证所有步骤节点具有同一个水平中心。
          SizedBox(
            width: DictationLayout.stepMarkerSize,
            child: Column(
              children: [
                // 圆形节点模拟 Tabler Steps 的状态点。
                Container(
                  key: Key('dictation-step-marker-$stepIndex'),
                  width: DictationLayout.stepMarkerSize,
                  height: DictationLayout.stepMarkerSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive ? AppTokens.accent : tokens.card,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive ? AppTokens.accent : tokens.check,
                    ),
                  ),
                  // 激活步骤显示 Tabler 图标，等待步骤只显示一个灰色实心点。
                  child: isActive && icon != null
                      ? Icon(icon, size: 12, color: Colors.white)
                      : Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: tokens.check,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
                // 非末步从节点下缘向下一步骤绘制连续竖线。
                if (!isLast)
                  Expanded(
                    child: Container(
                      key: Key('dictation-step-connector-$stepIndex'),
                      width: DictationLayout.stepConnectorWidth,
                      color: tokens.inputBorder,
                    ),
                  ),
              ],
            ),
          ),
          // 左侧轨道与右侧正文保持 Tabler 风格的紧凑间距。
          const SizedBox(width: DictationLayout.stepContentGap),
          // Expanded 让长提示与释义使用剩余宽度并自然换行。
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : DictationLayout.stepVerticalGap,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DictationLayout.stepContentMinHeight,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 提示步骤正文：标题、当前操作要求和固定高度反馈区。
class _PromptStepContent extends StatelessWidget {
  /// 创建提示步骤内容。
  const _PromptStepContent({
    required this.prompt,
    required this.feedback,
    required this.feedbackColor,
    required this.tokens,
  });

  /// 当前操作要求。
  final String prompt;

  /// 当前即时反馈。
  final String feedback;

  /// 反馈语义颜色。
  final Color? feedbackColor;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 文本全部从步骤顶部开始排列，不再使用独立背景卡。
  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('dictation-prompt-information'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '提示',
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          prompt,
          key: const Key('dictation-stage-label'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          key: const Key('dictation-feedback-slot'),
          height: DictationLayout.feedbackHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              feedback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: feedbackColor ?? tokens.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 尚未解出 Meaning 时的灰色等待步骤。
class _MeaningEmptyStep extends StatelessWidget {
  /// 创建等待步骤内容。
  const _MeaningEmptyStep({required this.tokens});

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 仅呈现当前状态，不虚构词性或释义。
  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('dictation-meaning-slot'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meaning',
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text('暂无已完成的含义', style: TextStyle(color: tokens.muted, fontSize: 12.5)),
      ],
    );
  }
}

/// 已公开的 Meaning 步骤：上方词性，下方释义标签。
class _MeaningStepContent extends StatelessWidget {
  /// 创建一条只读 Meaning 步骤。
  const _MeaningStepContent({
    required this.meaning,
    required this.meaningIndex,
    required this.definitionSeparator,
    required this.tokens,
  });

  /// 当前词性和释义数据。
  final Meaning meaning;

  /// 当前 Meaning 下标，用于生成不重复的释义标签 key。
  final int meaningIndex;

  /// 读屏合并多个释义时使用的分隔符。
  final String definitionSeparator;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 按“词性、含义”的阅读顺序输出步骤正文。
  @override
  Widget build(BuildContext context) {
    // 没有词性的旧数据使用“释义”兜底，避免界面出现空标签。
    final pos = meaning.pos.trim().isEmpty ? '释义' : meaning.pos.trim();
    // Semantics 把分散的视觉标签合并成一句完整的读屏文本。
    return Semantics(
      label: '词性 $pos，含义 ${meaning.definitions.join(definitionSeparator)}',
      container: true,
      child: ExcludeSemantics(
        child: Column(
          key: Key('dictation-meaning-card-$meaningIndex'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行明确标注词性，右侧沿用首页表单的只读 badge 视觉。
            Row(
              children: [
                Text(
                  '词性',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 54,
                    minHeight: 26,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: tokens.inputBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pos,
                    style: TextStyle(
                      color: tokens.textMedium,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // “含义”单独成行，下面的每条释义继续使用首页表单的灰色标签。
            Text(
              '含义',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (
                  var definitionIndex = 0;
                  definitionIndex < meaning.definitions.length;
                  definitionIndex += 1
                )
                  Container(
                    key: Key(
                      'dictation-definition-chip-$meaningIndex-$definitionIndex',
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.sub,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      meaning.definitions[definitionIndex],
                      style: TextStyle(
                        color: tokens.textMedium,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 判断单个字符是否为英文 A-Z；默写词库当前以英文单词为业务范围。
bool _isEnglishLetter(String character) {
  // 正则只匹配一个 ASCII 英文字母，空格、连字符和撇号都会返回 false。
  return RegExp(r'^[A-Za-z]$').hasMatch(character);
}
