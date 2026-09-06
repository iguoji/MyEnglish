// material.dart 提供布局与手势组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';

// 首页专属尺寸表：本组件的宽高从这里取名字，数值继承设计令牌总表。
import '../home_layout.dart';
// 复习模块标识与三态进度模型。
import '../../../../models/session.dart';

///
/// 复习模式快速入口：2×2 卡片网格。
///
/// 每张卡片显示三种状态之一：
/// - **待完成**：今天还没开过局，或者上一局中断、失败了；
/// - **进行中**：今天有一局主线正开着，用户做到一半退了出来；
/// - **已完成**：今天有一局主线把全部单词操作完了一遍，不论过程中是否答错。
///
/// 不再显示百分比：主线的判定标准是「走完一遍才算过」，中间过程的百分比
/// 既无法预示结果，也可能误导用户。已完成之后再进模块是无限巩固练习，
/// 卡片会在「已完成」后面补一个「巩固中」的小尾巴。
///
class ReviewModeGrid extends StatelessWidget {
  ///
  /// 创建网格。
  const ReviewModeGrid({
    required this.moduleStates,
    required this.dailyGoal,
    required this.onOpenModule,
    super.key,
  });

  ///
  /// 今天四个复习模块各自的三态进度；没出现的模块按「待完成」处理。
  final Map<ReviewModule, ReviewModuleState> moduleStates;

  ///
  /// 今天的实际题量，显示在标题右侧。
  final int dailyGoal;

  ///
  /// 点击任意一张卡片；由首页统一判断该开主线还是开巩固。
  final ValueChanged<ReviewModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题 + 副提示。右侧统计文本包 Flexible 省略，防大字体溢出。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '开始复习',
              // 16 号粗那一档：和候选项同字号，靠字重把区块标题顶出来。
              style: textTheme.fs4Bold,
            ),
            Flexible(
              child: Text(
                // 四个模块共用今天这一批词，所以只显示一个总题量。
                '今日目标 $dailyGoal 个',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.fs6.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.p3),
        // 2×2 网格：两行「IntrinsicHeight + Row(Expanded)」的手动网格。
        // 卡片高度由内容自然撑开、行内取较高者对齐，任何字体缩放下都不会溢出。
        _buildRow(
          tokens,
          first: ReviewModule.listeningMeaning,
          firstIcon: AppGlyph.moduleListening,
          firstDesc: '听音选词 · 辨别正确含义',
          second: ReviewModule.meaningMatch,
          secondIcon: AppGlyph.moduleMeaningMatch,
          secondDesc: '释义配对 · 连续匹配',
        ),
        const SizedBox(height: AppSpace.p2),
        _buildRow(
          tokens,
          first: ReviewModule.spellingReinforcement,
          firstIcon: AppGlyph.moduleListeningMeaning,
          firstDesc: '拼写训练 · 强化单词记忆',
          second: ReviewModule.meaningWordChoice,
          secondIcon: AppGlyph.moduleMeaningWordChoice,
          secondDesc: '根据含义 · 选出正确单词',
        ),
      ],
    );
  }

  ///
  /// 构建一行两张等宽卡片。
  Widget _buildRow(
    AppTokens tokens, {
    required ReviewModule first,
    required IconData firstIcon,
    required String firstDesc,
    required ReviewModule second,
    required IconData secondIcon,
    required String secondDesc,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ModeCard(
              icon: firstIcon,
              module: first,
              desc: firstDesc,
              // 缺省值让「今天还没开过局」和「今天没这条记录」表现完全一致。
              state: moduleStates[first] ?? ReviewModuleState.empty,
              onTap: () => onOpenModule(first),
              tokens: tokens,
            ),
          ),
          const SizedBox(width: AppSpace.p2),
          Expanded(
            child: _ModeCard(
              icon: secondIcon,
              module: second,
              desc: secondDesc,
              state: moduleStates[second] ?? ReviewModuleState.empty,
              onTap: () => onOpenModule(second),
              tokens: tokens,
            ),
          ),
        ],
      ),
    );
  }
}

///
/// 单张复习模式卡片。
///
class _ModeCard extends StatelessWidget {
  ///
  /// 创建一张卡片。
  const _ModeCard({
    required this.icon,
    required this.module,
    required this.desc,
    required this.state,
    required this.onTap,
    required this.tokens,
  });

  /// 左上角图标。
  final IconData icon;

  /// 卡片对应的复习模块。
  final ReviewModule module;

  /// 一句话说明。
  final String desc;

  /// 今天的三态进度。
  final ReviewModuleState state;

  /// 点击回调。
  final VoidCallback onTap;

  /// 当前主题色板。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final phase = state.barPhase;
    // 底色：今日主线已完成走绿底（巩固的地基），否则灰底。
    final baseGreen =
        phase == ReviewBarPhase.dailyDone ||
        phase == ReviewBarPhase.reinforceActive ||
        phase == ReviewBarPhase.reinforceDone;
    final baseColor = baseGreen ? AppTokens.success : tokens.sub;
    // 前景叠加层：主线进行中用绿色，巩固用蓝色，按本局已完成单词数比例填充。
    final Color? fillColor;
    final double fillRatio;
    switch (phase) {
      case ReviewBarPhase.idle:
      case ReviewBarPhase.dailyDone:
        fillColor = null;
        fillRatio = 0;
      case ReviewBarPhase.dailyActive:
        fillColor = AppTokens.success;
        fillRatio = state.totalCount > 0
            ? (state.doneCount / state.totalCount).clamp(0.0, 1.0)
            : 0.0;
      case ReviewBarPhase.reinforceActive:
        fillColor = AppTokens.primary;
        fillRatio = state.totalCount > 0
            ? (state.doneCount / state.totalCount).clamp(0.0, 1.0)
            : 0.0;
      case ReviewBarPhase.reinforceDone:
        fillColor = AppTokens.primary;
        fillRatio = 1.0;
    }
    // 徽章文字与颜色：巩固的两种细分状态（巩固中 / 已巩固）直接吃模型聚合好的
    // 视觉阶段 [ReviewBarPhase]——只有 `fromMap` 会把「会话类型 + 状态」精确合成
    // 这两个阶段，普通构造默认落不到这里；其余状态按 [state.progress] 三态显示
    // （待完成用 Tabler 红制造压力 / 进行中用主色蓝 / 已完成用成功绿）。
    // 每种状态只显示一个三字以内的短词，绝不出现「已完成 · 巩固中」式组合文案。
    final (badgeText, badgeColor) = switch (phase) {
      ReviewBarPhase.reinforceActive => ('巩固中', AppTokens.primary),
      ReviewBarPhase.reinforceDone => ('已巩固', AppTokens.primary),
      _ => switch (state.progress) {
        ReviewModuleProgress.pending => ('待完成', AppTokens.danger),
        ReviewModuleProgress.active => ('进行中', AppTokens.primary),
        ReviewModuleProgress.completed => ('已完成', AppTokens.success),
      },
    };
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      elevation: HomeDashboardLayout.cardElevation,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.p3),
          decoration: BoxDecoration(
            // 显式填上白色卡片底色（深色主题下自动是对应的深色表面）。
            color: tokens.card,
            // 描边代替阴影：用分隔线色勾出轮廓，不再使用投影。
            border: Border.all(color: tokens.border),
            // 只保留一点点圆角。
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // 顶部：图标 + 状态徽章。徽章文本包 Flexible 省略收缩，
              // 防止长文案在窄卡片上把图标行撑出横向溢出。
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: AppIcon.i20, color: tokens.text),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.p2,
                        vertical: AppSpace.p1,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: AppAlpha.a14),
                        borderRadius: BorderRadius.circular(AppRadius.rounded),
                      ),
                      child: Text(
                        badgeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.fs6Bold.copyWith(
                          fontFamily: 'monospace',
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // 图标行与名称之间留出固定间距，避免过于紧凑也避免被拉散。
              const SizedBox(height: AppSpace.p2),
              // 模块名称。
              Text(
                module.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.fs4Bold,
              ),
              // 名称与描述之间紧凑一点。
              const SizedBox(height: AppSpace.p1),
              // 描述固定为单行；屏幕特别窄或系统字体较大时整体缩小，
              // 不允许换行改变同一行两张卡片的内容高度。
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    desc,
                    maxLines: 1,
                    style: textTheme.fs6.copyWith(
                      color: tokens.textSecondary,
                      height: AppLine.lhSm,
                    ),
                  ),
                ),
              ),
              // 描述与底部指示条之间留出间距。
              const SizedBox(height: AppSpace.p2),
              // 底部进度条双层叠加：底色=今日主线完成度（灰/绿），
              // 前景=当前这一局进度（绿=主线，蓝=巩固），按已完成单词比例填充。
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.roundedSm),
                child: SizedBox(
                  height: HomeDashboardLayout.modeProgressHeight,
                  child: Stack(
                    children: [
                      Container(color: baseColor),
                      if (fillColor != null && fillRatio > 0)
                        FractionallySizedBox(
                          widthFactor: fillRatio,
                          child: Container(color: fillColor),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
