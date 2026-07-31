// material.dart 提供动画、按钮、阴影和布局组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 是项目唯一允许使用的界面图标来源。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿颜色令牌，保证浅色与深色模式一致。
import '../../../common/theme.dart';

/// 首页右下角“学习”悬浮菜单。
///
/// 关闭时只显示主按钮；展开后显示随身听、默写和对应的继续入口。
///
/// 用 StatefulWidget + 显式 AnimationController 驱动所有展开/收起动画，
/// 避免 StatelessWidget 重建时 AnimatedSwitcher 偶发“瞬间切换不播放”的问题。
class LearningFab extends StatefulWidget {
  /// 所有状态由首页统一管理，组件本身只负责显示与转发点击。
  const LearningFab({
    required this.isOpen,
    required this.targetCount,
    required this.showPlayerResume,
    required this.showDictationResume,
    required this.onToggle,
    required this.onOpenPlayer,
    required this.onOpenDictation,
    required this.onContinuePlayer,
    required this.onContinueDictation,
    super.key,
  });

  /// 是否已经展开两个学习入口。
  final bool isOpen;

  /// 当前学习范围的单词数。
  final int targetCount;

  /// 是否存在未完成的随身听会话。
  final bool showPlayerResume;

  /// 是否存在未完成的默写会话。
  final bool showDictationResume;

  /// 点击“学习/收起”主按钮时执行。
  final VoidCallback onToggle;

  /// 点击随身听时执行。
  final VoidCallback onOpenPlayer;

  /// 点击默写时执行。
  final VoidCallback onOpenDictation;

  /// 点击随身听右侧“继续”时执行。
  final VoidCallback onContinuePlayer;

  /// 点击默写右侧“继续”时执行。
  final VoidCallback onContinueDictation;

  @override
  State<LearningFab> createState() => _LearningFabState();
}

/// 主按钮文字样式（学习 / 收起 共用，保证切换时宽度一致）。
const TextStyle _labelStyle = TextStyle(
  color: Colors.white,
  fontSize: 14.5,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.5,
);

class _LearningFabState extends State<LearningFab>
    with SingleTickerProviderStateMixin {
  // 统一驱动所有展开/收起动画的计时器；isOpen 翻转时在 didUpdateWidget 中正/反向播放。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  // 缓出曲线，让位移/淡入在尾段更柔和、过渡更自然。
  late final Animation<double> _expand = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  // 叉叉图标进入时从 -90° 旋转归位到 0°，实现“叉叉旋转出现”。
  late final Animation<double> _rotation = Tween<double>(
    begin: -0.25,
    end: 0,
  ).animate(_expand);
  // 入口从自身高度 40% 的下方滑入，对应原型“从下面位移并淡入”。
  late final Animation<Offset> _slideUp = Tween<Offset>(
    begin: const Offset(0, 0.4),
    end: Offset.zero,
  ).animate(_expand);

  @override
  void initState() {
    super.initState();
    // 初始若已展开（一般不会），直接把动画定位到终点，避免首帧跳变。
    if (widget.isOpen) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant LearningFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // isOpen 翻转即播放/倒放，保证动画一定触发，不依赖 StatelessWidget 的重建细节。
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    // 计时器必须释放，否则会泄漏并持续占用帧回调。
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 读取当前主题下的卡片、边框与文字颜色。
    final tokens = AppTokens.of(context);
    // 设计稿要求所有入口靠右对齐，并保持 10 像素纵向间距。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 入口区：随展开进度淡入 + 从下方滑入；SizeTransition 让收起时高度归零、不占空间。
        // Offstage 仅在“完全收起”时隐藏，既保证收起动画完整播放，又让测试在关闭态找不到入口文字。
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) =>
              Offstage(offstage: _controller.isDismissed, child: child),
          child: SizeTransition(
            sizeFactor: _expand,
            // 从底部向上展开，贴合“入口出现在按钮上方”的视觉。
            // 从底部向上展开，贴合“入口出现在按钮上方”的视觉。
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _expand,
              child: SlideTransition(
                position: _slideUp,
                child: _buildActions(tokens),
              ),
            ),
          ),
        ),
        // 主按钮严格复刻 46 高、23 圆角和右侧 20/左侧 16 的内边距。
        Material(
          color: AppTokens.accent,
          borderRadius: BorderRadius.circular(23),
          elevation: 8,
          shadowColor: AppTokens.accent.withValues(alpha: 0.42),
          child: InkWell(
            key: const Key('toggle-learning-menu'),
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(23),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 图标层：书本淡出 / 叉叉旋转淡入，二者共用计时器，必动。
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // 学习（书本）图标：展开时淡出，不旋转。
                        FadeTransition(
                          opacity: ReverseAnimation(_expand),
                          child: const Icon(
                            TablerIcons.book,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                        // 收起（叉叉）图标：展开时旋转 -90°→0° 并淡入。
                        RotationTransition(
                          turns: _rotation,
                          child: FadeTransition(
                            opacity: _expand,
                            child: const Icon(
                              TablerIcons.x,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 9),
                    // 文字随状态切换；原型动画焦点在“图标淡出/叉叉旋转/入口上滑”，
                    // 文字不做交叉淡入以免关闭态仍残留“收起”节点（影响测试与可访问性）。
                    Text(widget.isOpen ? '收起' : '学习', style: _labelStyle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 展开菜单中的两个白色胶囊入口（随身听 / 默写）。
  Widget _buildActions(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _LearningActionRow(
        actionKey: const Key('open-player'),
        continueKey: const Key('continue-player'),
        icon: TablerIcons.headphones,
        label: '随身听 · ${widget.targetCount}',
        onTap: widget.onOpenPlayer,
        showContinue: widget.showPlayerResume,
        onContinue: widget.onContinuePlayer,
        tokens: tokens,
      ),
      const SizedBox(height: 10),
      _LearningActionRow(
        actionKey: const Key('open-dict'),
        continueKey: const Key('continue-dictation'),
        icon: TablerIcons.pencil,
        label: '默写 · ${widget.targetCount}',
        onTap: widget.onOpenDictation,
        showContinue: widget.showDictationResume,
        onContinue: widget.onContinueDictation,
        tokens: tokens,
      ),
      const SizedBox(height: 10),
    ],
  );
}

/// 一行学习入口：左侧开始新一轮，存在历史时在右侧动画显示“继续”。
class _LearningActionRow extends StatelessWidget {
  /// 创建一行按钮，并由 [showContinue] 决定右侧历史入口是否占位。
  const _LearningActionRow({
    required this.actionKey,
    required this.continueKey,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.showContinue,
    required this.onContinue,
    required this.tokens,
  });

  /// 左侧主入口测试标识。
  final Key actionKey;

  /// 右侧继续入口测试标识。
  final Key continueKey;

  /// 左侧入口的 Tabler 图标。
  final IconData icon;

  /// 左侧入口文案与目标单词数。
  final String label;

  /// 开始新一轮的点击事件。
  final VoidCallback onTap;

  /// true 时显示继续按钮，false 时动画收回并且不保留间距。
  final bool showContinue;

  /// 恢复历史会话的点击事件。
  final VoidCallback onContinue;

  /// 当前明暗主题设计令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 左侧按钮始终存在，点击后开始一轮全新的学习。
        _LearningAction(
          key: actionKey,
          icon: icon,
          label: label,
          onTap: onTap,
          tokens: tokens,
        ),
        // AnimatedSwitcher 同时处理淡入与横向展开；无历史时 child 真正缩成 0 宽。
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          reverseDuration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axis: Axis.horizontal,
              alignment: Alignment.centerRight,
              child: child,
            ),
          ),
          child: showContinue
              ? Row(
                  key: const ValueKey<String>('learning-resume-visible'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 两个独立按钮之间保留清晰间隔，避免单手点击时误触主入口。
                    const SizedBox(width: 8),
                    _LearningContinueAction(
                      key: continueKey,
                      onTap: onContinue,
                      tokens: tokens,
                    ),
                  ],
                )
              : const SizedBox(key: ValueKey<String>('learning-resume-hidden')),
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

/// 学习主入口右侧的“继续”按钮，视觉上保持 Tabler 的轻量次要操作层级。
class _LearningContinueAction extends StatelessWidget {
  /// 创建继续按钮。
  const _LearningContinueAction({
    required this.onTap,
    required this.tokens,
    super.key,
  });

  /// 点击后恢复对应学习会话。
  final VoidCallback onTap;

  /// 当前主题颜色。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.accent.withValues(alpha: 0.28)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 所有图标都来自 Tabler；playerPlay 明确表达“从进度继续”。
              Icon(TablerIcons.playerPlay, size: 15, color: AppTokens.accent),
              SizedBox(width: 6),
              Text(
                '继续',
                style: TextStyle(
                  color: AppTokens.accent,
                  fontSize: 13,
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
