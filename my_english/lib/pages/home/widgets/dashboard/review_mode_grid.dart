// material.dart 提供布局与手势组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供复习模式卡片使用的图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';

///
/// 复习模式快速入口：2×2 卡片网格。
///
/// 卡片速记与拼写巩固映射到现有随身听/默写；听音辨义与真题例句暂未实现，
/// 点击时调用 onComingSoon 回调提示「即将上线」。
///
class ReviewModeGrid extends StatelessWidget {
  /// 创建网格。
  const ReviewModeGrid({
    required this.targetCount,
    required this.reviewCount,
    required this.dailyGoal,
    required this.onOpenCards,
    required this.onOpenSpelling,
    required this.onComingSoon,
    super.key,
  });

  /// 当前学习范围的单词数，用于卡片速记/拼写巩固徽章。
  final int targetCount;

  /// 今日已完成复习数。
  final int reviewCount;

  /// 每日复习目标。
  final int dailyGoal;

  /// 打开卡片速记（映射到随身听）。
  final VoidCallback onOpenCards;

  /// 打开拼写巩固（映射到默写）。
  final VoidCallback onOpenSpelling;

  /// 未实现模式的统一提示回调。
  final void Function(String feature) onComingSoon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 今日进度比例。
    final progress = dailyGoal > 0
        ? (reviewCount / dailyGoal).clamp(0.0, 1.0)
        : 0.0;
    final progressPercent = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题 + 副提示。右侧统计文本包 Flexible 省略，防大字体溢出。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '开始复习',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: tokens.text,
              ),
            ),
            Flexible(
              child: Text(
                '计入今日 $reviewCount/$dailyGoal 目标',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: tokens.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 2×2 网格：改为两行「IntrinsicHeight + Row(Expanded)」的手动网格。
        // 原先用 GridView 固定 1:1 宽高比，卡片被强行撑成正方形，内容贴顶后
        // 底部留一大片空白；现在卡片高度由内容自然撑开、行内取较高者对齐，
        // 任何字体缩放下都不会溢出，也不会产生多余空白。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ModeCard(
                  icon: TablerIcons.cards,
                  badge: '$reviewCount/$dailyGoal',
                  isActive: true,
                  name: '卡片速记',
                  desc: '看词识义 · 快速建立词感',
                  progressPercent: progressPercent,
                  onTap: onOpenCards,
                  tokens: tokens,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: TablerIcons.pencil,
                  badge: '$reviewCount/$dailyGoal',
                  isActive: false,
                  name: '拼写巩固',
                  desc: '听写拼词 · 强化肌肉记忆',
                  progressPercent: progressPercent,
                  onTap: onOpenSpelling,
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ModeCard(
                  icon: TablerIcons.headphones,
                  badge: '0/20',
                  isActive: false,
                  name: '听音辨义',
                  desc: '纯听力辨析 · 摆脱视觉依赖',
                  progressPercent: 0,
                  onTap: () => onComingSoon('听音辨义'),
                  tokens: tokens,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: TablerIcons.book2,
                  badge: '0/30',
                  isActive: false,
                  name: '真题例句',
                  desc: '语境选词 · 掌握真实搭配',
                  progressPercent: 0,
                  onTap: () => onComingSoon('真题例句'),
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

///
/// 单张复习模式卡片。
///
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.badge,
    required this.isActive,
    required this.name,
    required this.desc,
    required this.progressPercent,
    required this.onTap,
    required this.tokens,
  });

  final IconData icon;
  final String badge;
  final bool isActive;
  final String name;
  final String desc;
  final int progressPercent;
  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // 卡片高度不再用固定宽高比强撑，改由内容自然撑开（见上方的
    // IntrinsicHeight 网格），因此无需再钳制字体缩放：系统大字体只会
    // 让卡片跟着变高，不会再有溢出风险，无障碍体验也更完整。
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(8),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // 显式填上白色卡片底色（深色主题下自动是对应的深色表面）。
            color: tokens.card,
            // 描边代替阴影：用分隔线色勾出轮廓，不再使用投影。
            border: Border.all(color: tokens.border),
            // 只保留一点点圆角。
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              // 改为顶部对齐 + 固定间距：原本 spaceBetween 会让 4 行内容在方形卡里
              // 被拉得过于分散；现在内容紧凑贴在顶部，行间距收拢、不再空旷。
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // 顶部：图标 + 徽章。徽章文本包 Flexible 省略收缩，
                // 防止长文案在窄卡片上把图标行撑出横向溢出。
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 20, color: tokens.text),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTokens.accent.withValues(alpha: 0.12)
                              : tokens.sub,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.w400,
                            color: isActive
                                ? AppTokens.accent
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // 图标行与名称之间留出固定间距，避免过于紧凑也避免被拉散。
                const SizedBox(height: 10),
                // 名称。
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
                // 名称与描述之间紧凑一点。
                const SizedBox(height: 4),
                // 描述。
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.textSecondary,
                    height: 1.3,
                  ),
                ),
                // 描述与进度条之间留出间距。
                const SizedBox(height: 10),
                // 进度条。
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        // 背景。
                        Container(color: tokens.sub),
                        // 填充。
                        FractionallySizedBox(
                          widthFactor:
                              (progressPercent / 100).clamp(0.0, 1.0),
                          child: Container(color: AppTokens.accent),
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