// material.dart 提供布局与滚动组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';
// 引入首页顶部问候与统计行。
import '../home_header.dart';
// 趋势曲线卡片。
import 'review_trend_chart.dart';
// 打卡热力图卡片。
import 'checkin_heatmap_card.dart';
// 复习模式 2x2 网格。
import 'review_mode_grid.dart';
// 词义连连首页进度模型（来自本局会话，不写复习记录）。
import '../../../meaning_match/meaning_match_page.dart';

///
/// 首页上层仪表盘：问候 → 统计 → 趋势曲线 → 打卡卡片 → 复习模式入口。
///
/// 仪表盘自身可滚动，底部只为上滑箭头保留必要的点击与安全空间。
///
class HomeDashboard extends StatelessWidget {
  /// 创建仪表盘。
  const HomeDashboard({
    required this.now,
    required this.wordCount,
    required this.dailyGoal,
    required this.reviewModeDailyGoal,
    required this.reviewCount,
    required this.reviewCountsByModule,
    required this.meaningMatchProgress,
    required this.refreshToken,
    required this.onMenuPressed,
    required this.onOpenListeningMeaning,
    required this.onOpenMeaningMatch,
    required this.onOpenSpellingReinforcement,
    required this.onOpenMeaningWordChoice,
    super.key,
  });

  /// 当前时间，用于问候语。
  final DateTime now;

  /// 已收录单词总数。
  final int wordCount;

  /// 每日复习目标。
  final int dailyGoal;

  /// 四种复习模式当天冻结的共同目标。
  final int reviewModeDailyGoal;

  /// 今日已完成复习数。
  final int reviewCount;

  /// 四种复习模式各自的今日完成量。
  final Map<String, int> reviewCountsByModule;

  /// 词义连连首页进度（来自本局会话，不写复习记录）；无会话时为 null。
  final MeaningMatchProgress? meaningMatchProgress;

  ///
  /// 复习数据回刷序号：每从复习模块返回一次就 +1。
  ///
  /// 趋势曲线与打卡日历各自持有异步查询结果，只在第一次出现时查库；
  /// 把这个序号透传下去，它们才知道“外面的复习数据变了，请重查一次”。
  ///
  /// @var int
  ///
  final int refreshToken;

  /// 点击汉堡菜单。
  final VoidCallback onMenuPressed;

  /// 打开听音辨义；当前复用已有默写流程。
  final VoidCallback onOpenListeningMeaning;

  /// 打开词义连连页面。
  final VoidCallback onOpenMeaningMatch;

  /// 打开拼写巩固页面。
  final VoidCallback onOpenSpellingReinforcement;

  /// 打开看义选词页面。
  final VoidCallback onOpenMeaningWordChoice;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 页面安全边界线：问候语与汉堡菜单距屏幕左右边缘的距离。
    // ListView 本身不再带水平内边距，改由各子块自行留边——
    // 这样趋势曲线图才能铺满整行宽，让曲线、渐变、分割线画到屏幕边缘。
    const edgeInset = 20.0;
    // 统一的水平留边：给不需要全出血的内容块使用。
    const horizontalPadding = EdgeInsets.symmetric(horizontal: edgeInset);
    return Container(
      color: tokens.page,
      child: ListView(
        // 底部 72 = 40 像素箭头点击区 + 18 像素安全距离 + 14 像素呼吸空间。
        // 原来的 140 同时照顾旧悬浮学习按钮；按钮移除后不再保留那块大空白。
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 72),
        children: [
          // 顶部问候与统计行（留在安全边界内）。
          Padding(
            padding: horizontalPadding,
            child: HomeHeader(
              now: now,
              wordCount: wordCount,
              dailyGoal: dailyGoal,
              reviewCount: reviewCount,
              onMenuPressed: onMenuPressed,
            ),
          ),
          const SizedBox(height: 20),
          // 趋势曲线（含时间范围 tabs）：整体铺满屏幕宽度；
          // 图内部自行把 tabs 与节点文字约束在安全边界内，
          // 只有曲线、渐变、分割线突破边界抵达屏幕边缘。
          // refreshToken 变化时曲线会重新查库，复习完返回首页即可看到新数据。
          ReviewTrendChart(refreshToken: refreshToken),
          const SizedBox(height: 20),
          // 30 天打卡质量卡片（留在安全边界内）；传入每日目标用于分档。
          Padding(
            padding: horizontalPadding,
            child: CheckinHeatmapCard(
              dailyGoal: dailyGoal,
              refreshToken: refreshToken,
            ),
          ),
          const SizedBox(height: 24),
          // 复习模式入口（留在安全边界内）。
          Padding(
            padding: horizontalPadding,
            child: ReviewModeGrid(
              reviewCountsByModule: reviewCountsByModule,
              meaningMatchProgress: meaningMatchProgress,
              dailyGoal: reviewModeDailyGoal,
              onOpenListeningMeaning: onOpenListeningMeaning,
              onOpenMeaningMatch: onOpenMeaningMatch,
              onOpenSpellingReinforcement: onOpenSpellingReinforcement,
              onOpenMeaningWordChoice: onOpenMeaningWordChoice,
            ),
          ),
        ],
      ),
    );
  }
}
