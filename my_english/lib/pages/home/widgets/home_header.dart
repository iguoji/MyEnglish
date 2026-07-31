// material.dart 提供 Text、Row 等界面组件，类似小程序内置的 view、text 组件集合。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供统一的 Tabler 图标字形，禁止回退到 Flutter 内置 Icons。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

///
/// 首页顶部：左侧问候语与收录统计，右侧汉堡菜单按钮。
///
/// [StatelessWidget] 表示该组件自己不保存状态，类似一个只根据传入参数输出 HTML 的
/// PHP 模板，或只根据 properties 渲染的小程序组件。
///
class HomeHeader extends StatelessWidget {
  ///
  /// `const` 构造函数表示参数不变时 Flutter 可以复用该组件，减少重复创建对象。
  ///
  /// @param  DateTime  now
  /// @param  int  wordCount
  /// @param  int  dailyGoal
  /// @param  int  reviewCount
  /// @param  VoidCallback  onMenuPressed
  /// @param  Key?  key
  ///
  const HomeHeader({
    required this.now,
    required this.wordCount,
    required this.dailyGoal,
    required this.reviewCount,
    required this.onMenuPressed,
    super.key,
  });

  ///
  /// 用于计算问候语的当前时间；由首页在构建时传入。
  ///
  /// @var DateTime
  ///
  final DateTime now;

  ///
  /// 已收录单词总数，显示在副标题里。
  ///
  /// @var int
  ///
  final int wordCount;

  ///
  /// 每日复习目标，显示在副标题里。
  ///
  /// @var int
  ///
  final int dailyGoal;

  ///
  /// 今日复习已完成的单词数（去重），来自真实 record，显示在副标题里。
  ///
  /// @var int
  ///
  final int reviewCount;

  ///
  /// 点击右上角汉堡按钮时由首页打开右侧抽屉菜单。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onMenuPressed;

  ///
  /// `@override` 表示这里重写 Flutter 父类规定的 build 方法，类似实现框架约定的入口。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);

    // Row 让问候文字在左、汉堡按钮在右。
    return Row(
      // 顶部对齐避免按钮影响两行文字的位置。
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Expanded 让左侧文字占用按钮之外的全部宽度。
        Expanded(
          // Column 类似纵向排列的多个 view。
          child: Column(
            // 两行文字左对齐。
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行显示根据当前小时得到的问候语。
              Text(
                // 调用本文件私有方法生成问候语。
                _greeting(now),
                // 24 号半粗与设计稿标题一致。
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  // 设计稿标题带 -0.2 的字距。
                  letterSpacing: -0.2,
                ),
              ),
              // 标题与副标题之间 4 像素间距。
              const SizedBox(height: 4),
              // 第二行按设计稿显示收录统计与今日复习进度。
              Text(
                // 今日复习数来自真实记录：今天已默写（按词去重）的单词数 / 每日目标。
                '已收录 $wordCount 个单词 · 今日复习 $reviewCount/$dailyGoal',
                // 13 号次要文字。
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        // 与左侧标题保留 8 像素间距。
        const SizedBox(width: 8),
        // Semantics 为读屏工具提供按钮语义。
        Semantics(
          button: true,
          label: '菜单',
          // InkWell 提供点击反馈；整块 40×40 都是触控区域。
          child: InkWell(
            // key 供 Widget 测试准确点击。
            key: const Key('open-menu'),
            // 点击由首页打开右侧抽屉。
            onTap: onMenuPressed,
            // 圆角反馈与按钮尺寸贴合。
            borderRadius: BorderRadius.circular(8),
            // SizedBox 固定触控区域为 40×40，图标贴右对齐右侧分界线。
            child: SizedBox(
              width: 40,
              height: 40,
              // Align(centerRight) 让 20px 图标在 40×40 触控区内靠右、垂直居中，
              // 使其右边缘对齐右侧分界线；SizedBox 的紧约束会把字形挤到左上角，
              // 必须显式对齐才能贴右。
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  // menu2 是 Tabler 的三横线菜单图标，不再用 Container 手工模拟图标。
                  TablerIcons.menu2,
                  size: 20,
                  color: tokens.text,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 按小时返回问候语；阈值与设计稿保持一致。
  ///
  /// @param  DateTime  time
  /// @return String
  ///
  String _greeting(DateTime time) {
    // 从 DateTime 取 0—23 的小时数，相当于 PHP 的 (int) date('G')。
    final hour = time.hour;
    // 00:00—05:59 属于深夜。
    if (hour < 6) return '夜深了';
    // 06:00—11:59 显示早上好。
    if (hour < 12) return '早上好';
    // 12:00—17:59 显示下午好。
    if (hour < 18) return '下午好';
    // 其余时间统一显示晚上好。
    return '晚上好';
  }
}
