// material.dart 提供动画、按钮、阴影和布局组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 是项目唯一允许使用的界面图标来源。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿颜色令牌，保证浅色与深色模式一致。
import '../../../common/theme.dart';

/// 首页右下角“学习”悬浮菜单。
///
/// 它对应小程序里一个由 `fabOpen` 控制的自定义组件：关闭时只显示主按钮，
/// 打开时向上展开“随身听”和“默写”两个入口，同时显示轻量遮罩。
class LearningFab extends StatelessWidget {
  /// 所有状态由首页统一管理，组件本身只负责显示与转发点击。
  const LearningFab({
    required this.isOpen,
    required this.targetCount,
    required this.onToggle,
    required this.onOpenPlayer,
    required this.onOpenDictation,
    super.key,
  });

  /// 是否已经展开两个学习入口。
  final bool isOpen;

  /// 当前学习范围的单词数。
  final int targetCount;

  /// 点击“学习/收起”主按钮时执行。
  final VoidCallback onToggle;

  /// 点击随身听时执行。
  final VoidCallback onOpenPlayer;

  /// 点击默写时执行。
  final VoidCallback onOpenDictation;

  @override
  Widget build(BuildContext context) {
    // 读取当前主题下的卡片、边框与文字颜色。
    final tokens = AppTokens.of(context);
    // 设计稿要求所有入口靠右对齐，并保持 10 像素纵向间距。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // AnimatedSwitcher 对应原型 fabIn 动画，展开时两个按钮轻微上浮淡入。
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: isOpen
              ? Column(
                  key: const Key('learning-actions-open'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _LearningAction(
                      key: const Key('open-player'),
                      icon: TablerIcons.headphones,
                      label: '随身听 · $targetCount',
                      onTap: onOpenPlayer,
                      tokens: tokens,
                    ),
                    const SizedBox(height: 10),
                    _LearningAction(
                      key: const Key('open-dict'),
                      icon: TablerIcons.pencil,
                      label: '默写 · $targetCount',
                      onTap: onOpenDictation,
                      tokens: tokens,
                    ),
                    const SizedBox(height: 10),
                  ],
                )
              : const SizedBox.shrink(key: Key('learning-actions-closed')),
        ),
        // 主按钮严格复刻 46 高、23 圆角和右侧 20/左侧 16 的内边距。
        Material(
          color: AppTokens.accent,
          borderRadius: BorderRadius.circular(23),
          elevation: 8,
          shadowColor: AppTokens.accent.withValues(alpha: 0.42),
          child: InkWell(
            key: const Key('toggle-learning-menu'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(23),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 原型中的书本 SVG 和文字叉号都换成 Tabler 图标。
                    AnimatedRotation(
                      turns: isOpen ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        // book 是 Tabler 的展开书本图标，比 book2 更贴近原型中的学习入口。
                        isOpen ? TablerIcons.x : TablerIcons.book,
                        size: isOpen ? 17 : 19,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      isOpen ? '收起' : '学习',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 展开菜单中的单个白色胶囊入口。
class _LearningAction extends StatelessWidget {
  const _LearningAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tokens,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTokens.accent),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
