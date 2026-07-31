// material.dart 提供卡片、文字、布局和主题能力，作用类似小程序页面的 WXML + WXSS。
import 'package:flutter/material.dart';
// Tabler 图标让提示信息与应用中的其他功能图标保持同一套视觉语言。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局颜色令牌，亮色和深色模式会自动选择对应颜色。
import '../../../common/theme.dart';
// 引入默写页面统一维护的尺寸，避免组件内部散落魔法数字。
import 'dictation_layout.dart';

/// 单个步骤的类型，决定左侧节点使用哪种 Tabler 图标。
///
/// 相当于把“听音选词”和“释义”两类任务各归为一种枚举值，
/// 页面只需要告诉步骤组件类型，由组件决定画什么图标。
enum DictationStepKind {
  /// 第一步：听音并从四个候选里选出正确单词。
  word,

  /// 后续步骤：辨认某个词性下的中文释义。
  meaning,
}

/// 步骤的三种状态，对应 Tabler Steps 的 已完成 / 进行中 / 未开始。
enum DictationStepStatus {
  /// 该步骤已经答对，节点用品牌蓝实心加勾选图标。
  done,

  /// 用户当前正在作答的步骤，节点用品牌蓝描边加对应图标。
  active,

  /// 尚未轮到的步骤，节点用灰色描边加淡化图标。
  pending,
}

/// 默写单词的某一学习步骤，例如“听音选词”或某个词性释义。
///
/// 这是一道题的“计划清单”里的一项，页面在进入新词时就一次性把
/// 全部步骤构建出来，组件只负责按状态渲染，不关心答题进度。
class DictationStep {
  /// 创建一条步骤；业务状态仍由父页面管理。
  const DictationStep({
    required this.kind,
    required this.title,
    required this.status,
    this.pos,
    this.definitions,
    this.word,
  });

  /// 步骤类型，决定左侧节点的图标。
  final DictationStepKind kind;

  /// 步骤主标题，例如“听音选词”或“释义”。
  final String title;

  /// 步骤当前状态，决定节点的配色与图标。
  final DictationStepStatus status;

  /// 释义步骤的词性（n. / vt. 等），听音步骤为 null。
  final String? pos;

  /// 已经公开给用户的释义列表；未开始或尚未答出时为空。
  final List<String>? definitions;

  /// 听音步骤完成后展示的正确单词；仅听音步骤使用，其余步骤为 null。
  final String? word;
}

/// 默写页中部内容：上方单词卡，中间独立提示横幅，下方全量纵向步骤。
class DictationQuestionContent extends StatelessWidget {
  /// 创建题目内容组件；页面状态只传数据，不把答题业务塞进展示组件。
  const DictationQuestionContent({
    required this.spelling,
    required this.revealedLetterCount,
    required this.revealWholeWord,
    required this.onSpeakerTap,
    required this.isPlaying,
    required this.prompt,
    required this.feedback,
    required this.feedbackColor,
    required this.steps,
    required this.definitionSeparator,
    super.key,
  });

  /// 当前题目的完整拼写；未答对前只用它计算占位瓷砖数量。
  final String spelling;

  /// 用户点击提示后，应该从左侧公开多少个英文字母。
  final int revealedLetterCount;

  /// true 表示拼写阶段已经完成，此时所有字母瓷砖都填入真实字母。
  final bool revealWholeWord;

  /// 点击单词卡上的听音按钮时执行的回调，复用页面已有的发音逻辑。
  final VoidCallback onSpeakerTap;

  /// 当前是否正在播放发音，用于切换听音按钮的图标。
  final bool isPlaying;

  /// 独立的当前操作要求，不再作为 Steps 的一项。
  final String prompt;

  /// 正确、错误或提示操作产生的即时反馈。
  final String feedback;

  /// 反馈的可选语义色；为空时使用普通次要文字颜色。
  final Color? feedbackColor;

  /// 进入新词时一次性列出的全部步骤，包含 听音选词 + 每个词性释义。
  final List<DictationStep> steps;

  /// 无障碍朗读多个释义时使用的分隔符，与首页设置保持一致。
  final String definitionSeparator;

  /// 先输出单词卡，再输出独立提示横幅，最后输出全部步骤轨道。
  @override
  Widget build(BuildContext context) {
    // 按当前主题读取卡片、文字和边框颜色。
    final tokens = AppTokens.of(context);
    // Column 等同小程序中的纵向 flex 容器，三个模块从顶部依次排列。
    return Column(
      key: const Key('dictation-question-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 第一个模块：重新设计的单词卡，把听音与字母瓷砖收进同一张卡。
        _WordCard(
          spelling: spelling,
          revealedLetterCount: revealedLetterCount,
          revealWholeWord: revealWholeWord,
          isPlaying: isPlaying,
          onSpeakerTap: onSpeakerTap,
          tokens: tokens,
        ),
        // 单词卡和提示横幅之间使用正常间距，不通过位移调整视觉位置。
        const SizedBox(height: DictationLayout.questionModuleGap),
        // 提示单独成卡，不再占用 Steps 的第一步。
        _PromptBanner(
          prompt: prompt,
          feedback: feedback,
          feedbackColor: feedbackColor,
          tokens: tokens,
        ),
        // 提示横幅与步骤轨道之间同样使用统一间距。
        const SizedBox(height: DictationLayout.questionModuleGap),
        // Tabler 风格 Steps 把全部步骤（听音选词 + 每条释义）一次性列出。
        _QuestionSteps(
          steps: steps,
          definitionSeparator: definitionSeparator,
          tokens: tokens,
        ),
      ],
    );
  }
}

/// 第一个模块：重新设计的单词卡。
///
/// 与旧版“下划线占位槽”不同，新版用等宽圆角瓷砖承载每个字母，
/// 未公开时瓷砖留空、公开后填入大写字母并染上品牌色，
/// 左上角放一个可点击的听音按钮，强化“听音选词”的操作语义。
class _WordCard extends StatelessWidget {
  /// 接收完整拼写、提示公开数量、播放状态与主题色。
  const _WordCard({
    required this.spelling,
    required this.revealedLetterCount,
    required this.revealWholeWord,
    required this.isPlaying,
    required this.onSpeakerTap,
    required this.tokens,
  });

  /// 当前单词完整拼写。
  final String spelling;

  /// 从左到右已经公开的字母数量。
  final int revealedLetterCount;

  /// 是否公开全部字母。
  final bool revealWholeWord;

  /// 是否正在播放发音。
  final bool isPlaying;

  /// 点击听音按钮时执行父页面的发音逻辑。
  final VoidCallback onSpeakerTap;

  /// 父组件已经读取的主题令牌。
  final AppTokens tokens;

  /// 绘制带边框的单词卡，左侧听音按钮 + 右侧居中字母瓷砖。
  @override
  Widget build(BuildContext context) {
    // runes 按字符读取拼写，避免直接按 UTF-16 单元拆分造成字符数量错误。
    final characters = spelling.runes
        .map((codePoint) => String.fromCharCode(codePoint))
        .toList(growable: false);
    // 只统计 A-Z 字母；空格或连字符会显示间隔，但不会虚增占位瓷砖。
    final letterCount = characters.where(_isEnglishLetter).length;
    // 未公开答案时，无障碍工具只朗读字母数，不能提前泄露正确拼写。
    final semanticLabel = revealWholeWord ? '单词 $spelling' : '$letterCount 个字母';
    // Material 同时绘制背景、圆角与完整边框，圆角处不会因裁剪丢失边线。
    return Material(
      key: const Key('dictation-word-card'),
      // 用极淡的品牌色铺底，让单词卡成为页面视觉焦点。
      color: AppTokens.accent.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      // Semantics 为读屏保留“字母数量/完整单词”信息，子瓷砖本身不重复朗读。
      child: Semantics(
        label: semanticLabel,
        container: true,
        // 固定卡高度，让中部区域不随单词长短跳动。
        child: SizedBox(
          key: const Key('dictation-word-slot'),
          height: DictationLayout.wordCardHeight,
          // Padding 防止较长单词直接贴到卡片左右边框。
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DictationLayout.wordCardHorizontalInset,
            ),
            // Row 让听音按钮占据左侧固定宽度，字母瓷砖在剩余空间居中。
            child: Row(
              children: [
                // 左上角的听音按钮，点击即重听当前单词。
                _CardSpeakerButton(
                  isPlaying: isPlaying,
                  onTap: onSpeakerTap,
                  tokens: tokens,
                ),
                // 听音按钮与瓷砖之间保留紧凑间距。
                const SizedBox(width: DictationLayout.wordCardInnerGap),
                // Expanded 让瓷砖在去掉听音按钮后的区域里水平居中。
                Expanded(
                  // Center 保证瓷砖整体在卡片中垂直居中。
                  child: Center(
                    // FittedBox 仅在超长单词超过卡片宽度时整体等比缩小。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      // ExcludeSemantics 防止每个字母与上方合并语义重复朗读。
                      child: ExcludeSemantics(child: _buildTiles(characters)),
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

  /// 把拼写转换为若干字母瓷砖；非字母字符只作为分隔符显示。
  Widget _buildTiles(List<String> characters) {
    // letterIndex 只计算英文字母，因此连字符不会消耗提示公开数量。
    var letterIndex = 0;
    // Row 的宽度由全部瓷砖决定，再由外层 Center 整体居中。
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
    // 空格只形成单词间隔，不显示文字，也不创建字母瓷砖。
    if (character.trim().isEmpty) {
      return const <Widget>[SizedBox(width: DictationLayout.wordSpaceWidth)];
    }
    // 连字符或撇号按原文显示，使复合词仍保持正确结构。
    if (letterIndex == null) {
      return <Widget>[
        SizedBox(
          height: DictationLayout.wordTileHeight,
          child: Center(
            child: Text(
              character,
              style: TextStyle(
                color: tokens.textSecondary,
                // 标点随字母同步放大，避免在瓷砖卡中显得过小。
                fontSize: 30,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (hasFollowingCharacter)
          const SizedBox(width: DictationLayout.wordTileGap),
      ];
    }
    // 拼写已答对时公开全部字母，否则仅公开提示数量以内的左侧字母。
    final isRevealed = revealWholeWord || letterIndex < revealedLetterCount;
    // 每个英文字母固定使用一个圆角瓷砖，真实文字出现时不改变任何几何尺寸。
    return <Widget>[
      Container(
        key: Key('dictation-tile-$letterIndex'),
        width: DictationLayout.wordTileWidth,
        height: DictationLayout.wordTileHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 已公开的瓷砖使用极淡品牌色底，未公开则使用次级底色。
          color: isRevealed
              ? AppTokens.accent.withValues(alpha: 0.08)
              : tokens.sub,
          borderRadius: BorderRadius.circular(DictationLayout.wordTileRadius),
          // 已公开瓷砖描品牌色边，未公开使用普通输入边框。
          border: Border.all(
            color: isRevealed
                ? AppTokens.accent.withValues(alpha: 0.5)
                : tokens.inputBorder,
          ),
        ),
        child: Text(
          // 公开的字母统一大写，视觉更整齐；未公开时瓷砖留空。
          isRevealed ? character.toUpperCase() : '',
          key: Key('dictation-tile-letter-$letterIndex'),
          style: TextStyle(
            // 整词完成后用品牌色高亮庆祝，否则用主文字色。
            color: revealWholeWord ? AppTokens.accent : tokens.text,
            // 字号跟随布局常量，保证与测试约定一致。
            fontSize: DictationLayout.wordLetterFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (hasFollowingCharacter)
        const SizedBox(width: DictationLayout.wordTileGap),
    ];
  }
}

/// 单词卡左上角的听音按钮：品牌色描边的圆形，点击重听当前单词。
class _CardSpeakerButton extends StatelessWidget {
  /// 创建听音按钮。
  const _CardSpeakerButton({
    required this.isPlaying,
    required this.onTap,
    required this.tokens,
  });

  /// 是否正在播放，用于切换音量图标。
  final bool isPlaying;

  /// 点击时执行父页面的发音逻辑。
  final VoidCallback onTap;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 使用 Material + InkWell 获得按压水波纹与点击命中。
  @override
  Widget build(BuildContext context) {
    // 圆形画布，内部居中显示 Tabler 音量图标。
    return Material(
      // 极淡品牌色底，呼应“点击即可听音”的操作意图。
      color: AppTokens.accent.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      // InkWell 提供点击；onTap 来自父页面，复用同一套发音服务。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        // SizedBox 固定点击画布，不让图标透明空间影响卡片对齐。
        child: SizedBox(
          width: DictationLayout.wordCardSpeakerSize,
          height: DictationLayout.wordCardSpeakerSize,
          child: Center(
            child: Icon(
              // 播放中显示双声波图标，空闲显示单声波图标。
              isPlaying ? TablerIcons.volume2 : TablerIcons.volume,
              size: 20,
              color: AppTokens.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// 独立的提示横幅：从 Steps 中拆出，专门承载“当前这一小步要做什么”。
///
/// 旧版把“提示”当成 Steps 第一步，导致进度被它占掉一格；
/// 现在 Steps 只表达“听音选词 + 各释义”的计划，提示单独成卡更清晰。
class _PromptBanner extends StatelessWidget {
  /// 创建提示横幅。
  const _PromptBanner({
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

  /// 文本全部从横幅顶部开始排列，不再使用独立背景卡叠在步骤里。
  @override
  Widget build(BuildContext context) {
    // Container 绘制与单词卡同款的边框与圆角，保持组件一致性。
    return Container(
      key: const Key('dictation-prompt-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(DictationLayout.cardRadius),
        border: Border.all(color: tokens.border),
      ),
      // 内部列承载“当前要求”标题、要求正文与反馈三行。
      child: Column(
        key: const Key('dictation-prompt-information'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部小标题：灯泡图标 + “当前要求”，明确这是动态指引。
          Row(
            children: [
              Icon(TablerIcons.bulb, size: 15, color: tokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                '当前要求',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 当前这一阶段的具体要求，例如“听音，选出正确的单词”。
          Text(
            prompt,
            key: const Key('dictation-stage-label'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // 固定高度反馈区，文案出现时横幅不抖动。
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
      ),
    );
  }
}

/// Tabler 风格纵向 Steps：进入新词时一次性列出全部步骤。
///
/// 第一步永远是“听音选词”，后续每个词性释义各占一步，
/// 步骤状态随答题进度在 未开始 / 进行中 / 已完成 之间切换。
class _QuestionSteps extends StatelessWidget {
  /// 创建整条步骤轨道；业务状态仍由父页面管理。
  const _QuestionSteps({
    required this.steps,
    required this.definitionSeparator,
    required this.tokens,
  });

  /// 当前单词的全部步骤，已含各自状态。
  final List<DictationStep> steps;

  /// 无障碍朗读多个释义时使用的分隔符。
  final String definitionSeparator;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 输出一条连续的左侧轨道，所有步骤内容在右侧居上对齐。
  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('dictation-vertical-steps'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 每个步骤都从一开始列出，不再等答对后才出现。
        for (var index = 0; index < steps.length; index += 1)
          _VerticalStepItem(
            stepIndex: index,
            stepKey: Key('dictation-step-$index'),
            status: steps[index].status,
            isLast: index == steps.length - 1,
            icon: _stepIcon(steps[index]),
            tokens: tokens,
            // 释义步骤的内容 key 沿用旧命名，便于测试和后续定位。
            contentKey: steps[index].kind == DictationStepKind.word
                ? const Key('dictation-step-word')
                : Key('dictation-step-meaning-${index - 1}'),
            child: _StepContent(
              step: steps[index],
              tokens: tokens,
              definitionSeparator: definitionSeparator,
            ),
          ),
      ],
    );
  }

  /// 根据步骤类型与状态选择节点图标。
  IconData _stepIcon(DictationStep step) {
    // 已完成的步骤一律用勾选图标表达“做完了”。
    if (step.status == DictationStepStatus.done) return TablerIcons.check;
    // 听音步骤用耳机图标，释义步骤用列表详情图标。
    return step.kind == DictationStepKind.word
        ? TablerIcons.headphones
        : TablerIcons.listDetails;
  }
}

/// 一条纵向 Step：左侧节点和连接线，右侧为当前步骤内容。
class _VerticalStepItem extends StatelessWidget {
  /// 创建一个稳定的纵向步骤行。
  const _VerticalStepItem({
    required this.stepIndex,
    required this.stepKey,
    required this.status,
    required this.isLast,
    required this.icon,
    required this.contentKey,
    required this.tokens,
    required this.child,
  });

  /// 当前步骤下标，用于生成稳定测试 key。
  final int stepIndex;

  /// 直接挂在 Row 上的 key，几何测试能读取真实步骤边界。
  final Key stepKey;

  /// 当前步骤状态，决定节点配色与图标颜色。
  final DictationStepStatus status;

  /// 最后一步不再向下绘制连接线。
  final bool isLast;

  /// 节点内显示的 Tabler 图标。
  final IconData icon;

  /// 右侧内容容器的 key，便于测试按步骤定位。
  final Key contentKey;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 步骤右侧的具体内容。
  final Widget child;

  /// 使用 IntrinsicHeight 让左侧连接线自动匹配右侧内容高度。
  @override
  Widget build(BuildContext context) {
    // 已完成：品牌蓝实心；进行中：白底品牌蓝描边；未开始：卡片底灰描边。
    final nodeColor = status == DictationStepStatus.done
        ? AppTokens.accent
        : status == DictationStepStatus.active
        ? Colors.white
        : tokens.card;
    // 未开始使用更淡的 check 灰描边，其余状态都用品牌蓝描边。
    final nodeBorder = status == DictationStepStatus.pending
        ? tokens.check
        : AppTokens.accent;
    // 关键：蓝底节点（已完成）内必须用白色图标，否则蓝图标在蓝底上不可见；
    // 白底节点（进行中）用品牌蓝图标，卡片底节点（未开始）用弱化灰图标。
    final iconColor = status == DictationStepStatus.done
        ? Colors.white
        : status == DictationStepStatus.pending
        ? tokens.muted
        : AppTokens.accent;
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
                    color: nodeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: nodeBorder),
                  ),
                  child: Icon(
                    icon,
                    size: DictationLayout.stepIconSize,
                    color: iconColor,
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
                // 用统一 key 承载右侧内容，便于测试定位这一步骤。
                child: Container(key: contentKey, child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个步骤的右侧内容：标题 + 状态标签，释义步骤额外展示词性与已答释义。
class _StepContent extends StatelessWidget {
  /// 创建一条步骤内容。
  const _StepContent({
    required this.step,
    required this.tokens,
    required this.definitionSeparator,
  });

  /// 当前步骤的数据与状态。
  final DictationStep step;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 读屏合并多个释义时使用的分隔符。
  final String definitionSeparator;

  /// 按“标题、状态、释义”的阅读顺序输出步骤正文。
  @override
  Widget build(BuildContext context) {
    // 未开始步骤标题用弱化色，进行中/已完成用主文字色突出。
    final titleColor = step.status == DictationStepStatus.pending
        ? tokens.textSecondary
        : tokens.text;
    // 正文先把标题、可选词性标签与右侧状态标签排成一行。
    final body = Column(
      key: const Key('dictation-step-body'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              step.title,
              style: TextStyle(
                color: titleColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            // 释义步骤在标题后展示词性小标签。
            if (step.pos != null) ...[
              const SizedBox(width: 8),
              _PosBadge(pos: step.pos!, tokens: tokens),
            ],
            // 状态标签推到最右侧，一眼看清进度。
            const Spacer(),
            _StatusTag(status: step.status, tokens: tokens),
          ],
        ),
        // 听音步骤完成后直接回显正确单词；释义步骤展示已答释义 chips。
        if (step.kind == DictationStepKind.word &&
            step.status == DictationStepStatus.done) ...[
          const SizedBox(height: 6),
          // 复用释义 chip 的同款浅色标签，展示用户刚刚选对的单词。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: tokens.sub,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              // 与单词卡瓷砖保持一致，统一大写展示。
              step.word != null ? step.word!.toUpperCase() : '',
              style: TextStyle(
                color: tokens.textMedium,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else if (step.definitions != null &&
            step.definitions!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (
                var definitionIndex = 0;
                definitionIndex < step.definitions!.length;
                definitionIndex += 1
              )
                Container(
                  key: Key('dictation-definition-chip-$definitionIndex'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.sub,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    step.definitions![definitionIndex],
                    style: TextStyle(color: tokens.textMedium, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ] else if (step.status != DictationStepStatus.done) ...[
          const SizedBox(height: 6),
          Text('待完成', style: TextStyle(color: tokens.muted, fontSize: 12.5)),
        ],
      ],
    );
    // 听音步骤完成后回显正确单词，释义步骤合并词性与已答释义，均给读屏一句语义。
    if ((step.kind == DictationStepKind.meaning && step.definitions != null) ||
        (step.kind == DictationStepKind.word &&
            step.status == DictationStepStatus.done)) {
      final label = step.kind == DictationStepKind.word
          ? '正确单词 ${step.word ?? ''}'
          : '词性 ${step.pos?.toUpperCase() ?? '释义'}，含义 ${step.definitions!.join(definitionSeparator)}';
      return Semantics(
        label: label,
        container: true,
        // ExcludeSemantics 避免子 chips 再次被逐条朗读。
        child: ExcludeSemantics(child: body),
      );
    }
    // 听音步骤未答完、或未公开释义的步骤不需要额外语义合并。
    return body;
  }
}

/// 释义步骤标题后的词性小标签，沿用首页表单的只读 badge 视觉。
class _PosBadge extends StatelessWidget {
  /// 创建词性标签。
  const _PosBadge({required this.pos, required this.tokens});

  /// 词性文本，例如 n. / vt.。
  final String pos;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 用无边框的极淡品牌色胶囊承载词性文字，去掉生硬的 1px 方框。
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 极淡品牌色底，轻量不抢眼，呼应 Tabler 的 badge 视觉。
        color: AppTokens.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        // 词性大写显示。
        pos.toUpperCase(),
        style: TextStyle(
          // 文字直接用眼色，不再套边框；保持正体，不斜体。
          color: AppTokens.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 步骤右侧的状态标签：已完成 / 作答中 / 待完成。
class _StatusTag extends StatelessWidget {
  /// 创建状态标签。
  const _StatusTag({required this.status, required this.tokens});

  /// 当前步骤状态。
  final DictationStepStatus status;

  /// 当前主题令牌。
  final AppTokens tokens;

  /// 根据状态切换文案、底色与文字色。
  @override
  Widget build(BuildContext context) {
    // 已完成与作答中借用品牌色，未开始用中性灰，视觉权重从强到弱。
    final label = status == DictationStepStatus.done
        ? '已完成'
        : status == DictationStepStatus.active
        ? '作答中'
        : '待完成';
    final backgroundColor = status == DictationStepStatus.done
        ? AppTokens.accent.withValues(alpha: 0.10)
        : status == DictationStepStatus.active
        ? AppTokens.accent.withValues(alpha: 0.12)
        : tokens.sub;
    final foregroundColor = status == DictationStepStatus.pending
        ? tokens.muted
        : AppTokens.accent;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        // 胶囊形状让状态标签更轻量。
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
