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
              '专项复习模式',
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
        // 2×2 网格。
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          // 宽高比 1:1（正方形卡片）：内容含图标行 + 名称 + 两行描述 +
          // 进度条，1.1 的扁卡在大字体下会溢出约 1px，方形留足余量。
          childAspectRatio: 1.0,
          children: [
            _ModeCard(
              icon: TablerIcons.cards,
              badge: '$reviewCount/$dailyGoal',
              isActive: true,
              name: '卡片速记',
              desc: '看词识义 · 快速建立词感',
              progressPercent: progressPercent,
              onTap: onOpenCards,
              tokens: tokens,
            ),
            _ModeCard(
              icon: TablerIcons.pencil,
              badge: '$reviewCount/$dailyGoal',
              isActive: false,
              name: '拼写巩固',
              desc: '听写拼词 · 强化肌肉记忆',
              progressPercent: progressPercent,
              onTap: onOpenSpelling,
              tokens: tokens,
            ),
            _ModeCard(
              icon: TablerIcons.headphones,
              badge: '0/20',
              isActive: false,
              name: '听音辨义',
              desc: '纯听力辨析 · 摆脱视觉依赖',
              progressPercent: 0,
              onTap: () => onComingSoon('听音辨义'),
              tokens: tokens,
            ),
            _ModeCard(
              icon: TablerIcons.book2,
              badge: '0/30',
              isActive: false,
              name: '真题例句',
              desc: '语境选词 · 掌握真实搭配',
              progressPercent: 0,
              onTap: () => onComingSoon('真题例句'),
              tokens: tokens,
            ),
          ],
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
    return MediaQuery.withClampedTextScaling(
      // 卡片是紧凑型装饰组件，字号放大上限钳制到 1.25 倍：
      // 既保留弱视用户适度放大的无障碍能力，又避免系统超大字体
      // 把固定宽高比的网格卡片内容撑爆（横向/纵向溢出）。
      maxScaleFactor: 1.25,
      child: Material(
        color: tokens.card,
        borderRadius: BorderRadius.circular(18),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: tokens.cardShadow,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
      ),
    );
  }
}
