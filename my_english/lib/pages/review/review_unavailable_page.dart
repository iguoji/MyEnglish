// material.dart 提供页面骨架、布局与文字组件。
import 'package:flutter/material.dart';
// Tabler 图标负责返回与模式状态图标，保持全应用视觉一致。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 设计令牌统一提供页面、文字和边框颜色。
import '../../common/theme.dart';

///
/// 尚未开发复习模块的独立占位页面。
///
/// 每个入口传入自己的标题和当天公共词单数量；未来真实玩法完成后，可以直接
/// 用对应页面替换本路由，而首页的每日选词与模块会话结构无需调整。
///
class ReviewUnavailablePage extends StatelessWidget {
  /// 创建某个未开放复习模块的占位页面。
  const ReviewUnavailablePage({
    required this.title,
    required this.wordCount,
    super.key,
  });

  /// 当前复习模块名称。
  final String title;

  /// 今天公共复习词单的实际单词数量。
  final int wordCount;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(TablerIcons.chevronLeft),
                    color: tokens.text,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      TablerIcons.hourglassEmpty,
                      size: 34,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '暂未开放',
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '今日词单 $wordCount 个',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
