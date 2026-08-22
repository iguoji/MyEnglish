// material.dart 提供布局与手势组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供复习模式卡片使用的图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';
// 复习模式的稳定键与 record.module 保持一致。
import '../../../../store/record.dart';
// 词义连连首页进度模型（来自本局会话，不写复习记录）。
import '../../../meaning_match/meaning_match_page.dart';

///
/// 复习模式快速入口：2×2 卡片网格。
///
/// 听音辨义映射到现有默写流程；词义连连、拼写巩固与看义选词进入各自的
/// 未开放页面。四个回调相互独立，便于每个入口先准备当天共用词单。
///
class ReviewModeGrid extends StatelessWidget {
  /// 创建网格。
  const ReviewModeGrid({
    required this.reviewCountsByModule,
    required this.meaningMatchProgress,
    required this.dailyGoal,
    required this.onOpenListeningMeaning,
    required this.onOpenMeaningMatch,
    required this.onOpenSpellingReinforcement,
    required this.onOpenMeaningWordChoice,
    super.key,
  });

  /// 四种复习模式各自的今日完成量。
  final Map<String, int> reviewCountsByModule;

  /// 词义连连首页进度（来自本局会话，不写复习记录）；无会话时为 null。
  final MeaningMatchProgress? meaningMatchProgress;

  /// 每日复习目标。
  final int dailyGoal;

  /// 打开听音辨义（复用当前默写页面）。
  final VoidCallback onOpenListeningMeaning;

  /// 打开词义连连对应页面。
  final VoidCallback onOpenMeaningMatch;

  /// 打开拼写巩固对应页面。
  final VoidCallback onOpenSpellingReinforcement;

  /// 打开看义选词对应页面。
  final VoidCallback onOpenMeaningWordChoice;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
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
                // 当前仅「听音辨义」已开发，总目标即该模块目标；
                // 等更多玩法开放后，这里可以再展示分模块目标说明。
                '今日目标 $dailyGoal 个',
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
                  icon: TablerIcons.headphones,
                  name: '听音辨义',
                  desc: '听音选词 · 辨别正确含义',
                  reviewCount:
                      reviewCountsByModule[ReviewModule.listeningMeaning] ?? 0,
                  dailyGoal: dailyGoal,
                  isAvailable: true,
                  onTap: onOpenListeningMeaning,
                  tokens: tokens,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: TablerIcons.link,
                  name: '词义连连',
                  // 保持单行短句，避免两列卡片中出现不一致的描述高度。
                  desc: '释义配对 · 连续匹配',
                  // 词义连连不写复习记录，首页百分比只能来自本局会话：
                  // 有会话时用“已匹配/总配对”，无会话时归 0（分母置 0 让徽章显示 0%）。
                  reviewCount: meaningMatchProgress?.bestMatchedPairs ?? 0,
                  dailyGoal: meaningMatchProgress?.totalPairs ?? 0,
                  isAvailable: true,
                  onTap: onOpenMeaningMatch,
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
                  icon: TablerIcons.pencil,
                  name: '拼写巩固',
                  desc: '拼写训练 · 强化单词记忆',
                  reviewCount:
                      reviewCountsByModule[ReviewModule
                          .spellingReinforcement] ??
                      0,
                  dailyGoal: dailyGoal,
                  isAvailable: false,
                  onTap: onOpenSpellingReinforcement,
                  tokens: tokens,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: TablerIcons.listCheck,
                  name: '看义选词',
                  desc: '根据含义 · 选出正确单词',
                  reviewCount:
                      reviewCountsByModule[ReviewModule.meaningWordChoice] ?? 0,
                  dailyGoal: dailyGoal,
                  isAvailable: false,
                  onTap: onOpenMeaningWordChoice,
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
    required this.name,
    required this.desc,
    required this.reviewCount,
    required this.dailyGoal,
    required this.isAvailable,
    required this.onTap,
    required this.tokens,
  });

  final IconData icon;
  final String name;
  final String desc;
  final int reviewCount;
  final int dailyGoal;

  /// 该玩法是否已经开发完成并开放使用。
  ///
  /// 未开放时不显示进度条与百分比，避免「0%」让用户误以为没背够。
  final bool isAvailable;

  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // 每张卡片只读取自己所属模块的完成量，目标都取设置中的每日复习量。
    final progress = dailyGoal > 0
        ? (reviewCount / dailyGoal).clamp(0.0, 1.0)
        : 0.0;
    // 百分比向下取整：只要还差一个单词，就不会提前显示成红色的“100%”。
    final progressPercent = (progress * 100).floor();
    // 目标必须大于 0 且完成量达到目标才显示绿色“已完成”。
    final isCompleted = dailyGoal > 0 && reviewCount >= dailyGoal;
    // 未开放模块直接显示「即将开放」灰色徽章，不给用户虚假进度压力。
    // 已开放模块：未完成用 Tabler 红色制造压力，完成后切换为成功绿。
    final badgeColor = !isAvailable
        ? tokens.textSecondary
        : isCompleted
        ? const Color(0xFF2FB344)
        : Theme.of(context).colorScheme.error;
    final badgeText = !isAvailable
        ? '即将开放'
        : isCompleted
        ? '已完成'
        : '$progressPercent%';
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
                        color: badgeColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
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
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              // 描述与进度条之间留出间距。
              const SizedBox(height: 10),
              // 进度条。
              // 未开放模块不渲染真实进度条，避免 0% 的误导；
              // 用一条占位的细分隔线保持卡片视觉高度一致。
              if (isAvailable)
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
                          widthFactor: (progressPercent / 100).clamp(0.0, 1.0),
                          child: Container(color: AppTokens.accent),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // 占位分隔线：高度与真实进度条一致，保持四张卡片同高。
                Container(height: 4, color: tokens.sub),
            ],
          ),
        ),
      ),
    );
  }
}
