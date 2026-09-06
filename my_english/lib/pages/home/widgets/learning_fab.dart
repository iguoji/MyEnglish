// material.dart 提供动画、按钮、阴影和布局组件。
import 'package:flutter/material.dart';

// 引入设计稿颜色令牌，保证浅色与深色模式一致。
import '../../../common/theme.dart';

// 首页专属尺寸表：本组件的宽高从这里取名字，数值继承设计令牌总表。
import 'home_layout.dart';

///
/// 首页右下角“学习”悬浮菜单。
///
/// 关闭时只显示主按钮；展开后显示随身听、听音辨义和对应的继续入口。
///
/// 用 StatefulWidget + 显式 AnimationController 驱动所有展开/收起动画，
/// 避免 StatelessWidget 重建时 AnimatedSwitcher 偶发“瞬间切换不播放”的问题。
///
class LearningFab extends StatefulWidget {
  ///
  /// 所有状态由首页统一管理，组件本身只负责显示与转发点击。
  const LearningFab({
    required this.isOpen,
    required this.targetCount,
    required this.showPlayerResume,
    required this.showListeningMeaningResume,
    required this.onToggle,
    required this.onOpenPlayer,
    required this.onOpenListeningMeaning,
    required this.onContinuePlayer,
    required this.onContinueListeningMeaning,
    super.key,
  });

  ///
  /// 是否已经展开两个学习入口。
  final bool isOpen;

  ///
  /// 当前学习范围的单词数。
  final int targetCount;

  ///
  /// 是否存在未完成的随身听会话。
  final bool showPlayerResume;

  ///
  /// 是否存在未完成的听音辨义会话。
  final bool showListeningMeaningResume;

  ///
  /// 点击“学习/收起”主按钮时执行。
  final VoidCallback onToggle;

  ///
  /// 点击随身听时执行。
  final VoidCallback onOpenPlayer;

  ///
  /// 点击听音辨义时执行。
  final VoidCallback onOpenListeningMeaning;

  ///
  /// 点击随身听右侧“继续”时执行。
  final VoidCallback onContinuePlayer;

  ///
  /// 点击听音辨义右侧“继续”时执行。
  final VoidCallback onContinueListeningMeaning;

  ///
  /// 创建悬浮学习菜单状态。
  @override
  State<LearningFab> createState() => _LearningFabState();
}

///
/// 主按钮文字样式（学习 / 收起 共用，保证切换时宽度一致）。
///
/// 写成函数而不是常量，是因为字号、字重现在统一由主题的文字档位说话：
/// 这里读「按钮文字」那一档，只把蓝底上的白字叠上去。
TextStyle _labelStyle(BuildContext context) =>
    Theme.of(context).textTheme.fs5Semibold.copyWith(color: Colors.white);

///
/// 管理学习悬浮按钮的展开、旋转、位移和淡入动画。
///
class _LearningFabState extends State<LearningFab>
    with SingleTickerProviderStateMixin {
  ///
  /// 统一驱动所有展开或收起动画的控制器。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: AppDuration.ms250),
  );

  ///
  /// 让位移和淡入在尾段逐渐减速的缓出曲线。
  late final Animation<double> _expand = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  ///
  /// 控制关闭图标从负四分之一圈旋转到正常角度。
  late final Animation<double> _rotation = Tween<double>(
    begin: -0.25,
    end: 0,
  ).animate(_expand);

  ///
  /// 控制学习入口从自身高度 40% 的下方滑入。
  late final Animation<Offset> _slideUp = Tween<Offset>(
    begin: const Offset(0, 0.4),
    end: Offset.zero,
  ).animate(_expand);

  ///
  /// 初始化悬浮菜单动画。
  @override
  void initState() {
    super.initState();
    // 初始若已展开（一般不会），直接把动画定位到终点，避免首帧跳变。
    if (widget.isOpen) _controller.value = 1;
  }

  ///
  /// 响应父页面传入的展开状态变化。
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

  ///
  /// 释放菜单动画控制器。
  @override
  void dispose() {
    // 计时器必须释放，否则会泄漏并持续占用帧回调。
    _controller.dispose();
    super.dispose();
  }

  ///
  /// 构建悬浮学习菜单和主按钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前主题下的卡片、边框与文字颜色。
    final tokens = AppTokens.of(context);
    // 设计稿要求所有入口靠右对齐，上下之间隔一档常规间隙（`p2`）。
    //
    // 外面套一层 IconTheme：主按钮的书本/叉叉、每个入口的小图标一共 4 个，
    // 尺寸本来就必须一样，所以在这里写一次，下面各处不再各写 `size:`——
    // 和 CSS 里在父元素上定一次 `font-size` 是同一个道理。
    return IconTheme.merge(
      data: const IconThemeData(size: AppIcon.i16),
      child: Column(
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
          // 主按钮复刻设计稿：46 高、大面板那一档圆角（`roundedXxl`），
          // 左侧基准内边距、右侧再宽一档，让文字不贴着右边缘。
          Material(
            color: AppTokens.primary,
            borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
            elevation: LearningFabLayout.mainElevation,
            shadowColor: AppTokens.primary.withValues(alpha: AppAlpha.a42),
            child: InkWell(
              key: const Key('toggle-learning-menu'),
              onTap: widget.onToggle,
              borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
              child: SizedBox(
                height: LearningFabLayout.mainButtonHeight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpace.p3,
                    right: AppSpace.pBase,
                  ),
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
                              AppGlyph.study,
                              color: Colors.white,
                            ),
                          ),
                          // 收起（叉叉）图标：展开时旋转 -90°→0° 并淡入。
                          RotationTransition(
                            turns: _rotation,
                            child: FadeTransition(
                              opacity: _expand,
                              child: const Icon(
                                AppGlyph.dismiss,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSpace.p2),
                      // 文字随状态切换；原型动画焦点在“图标淡出/叉叉旋转/入口上滑”，
                      // 文字不做交叉淡入以免关闭态仍残留“收起”节点（影响测试与可访问性）。
                      Text(
                        widget.isOpen ? '收起' : '学习',
                        style: _labelStyle(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 展开菜单中的两个白色胶囊入口（随身听 / 听音辨义）。
  Widget _buildActions(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _LearningActionRow(
        actionKey: const Key('open-player'),
        continueKey: const Key('continue-player'),
        icon: AppGlyph.moduleListening,
        label: '随身听 · ${widget.targetCount}',
        onTap: widget.onOpenPlayer,
        showContinue: widget.showPlayerResume,
        onContinue: widget.onContinuePlayer,
        tokens: tokens,
      ),
      const SizedBox(height: AppSpace.p2),
      _LearningActionRow(
        actionKey: const Key('open-dict'),
        continueKey: const Key('continue-listening-meaning'),
        icon: AppGlyph.moduleListeningMeaning,
        label: '听音辨义 · ${widget.targetCount}',
        onTap: widget.onOpenListeningMeaning,
        showContinue: widget.showListeningMeaningResume,
        onContinue: widget.onContinueListeningMeaning,
        tokens: tokens,
      ),
      const SizedBox(height: AppSpace.p2),
    ],
  );
}

///
/// 一行学习入口：左侧开始新一轮，存在历史时在右侧动画显示“继续”。
///
class _LearningActionRow extends StatelessWidget {
  ///
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

  ///
  /// 左侧主入口测试标识。
  final Key actionKey;

  ///
  /// 右侧继续入口测试标识。
  final Key continueKey;

  ///
  /// 左侧入口的 Tabler 图标。
  final IconData icon;

  ///
  /// 左侧入口文案与目标单词数。
  final String label;

  ///
  /// 开始新一轮的点击事件。
  final VoidCallback onTap;

  ///
  /// true 时显示继续按钮，false 时动画收回并且不保留间距。
  final bool showContinue;

  ///
  /// 恢复历史会话的点击事件。
  final VoidCallback onContinue;

  ///
  /// 当前明暗主题设计令牌。
  final AppTokens tokens;

  ///
  /// 构建一行学习入口及可选的继续按钮。
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
          duration: const Duration(milliseconds: AppDuration.ms250),
          reverseDuration: const Duration(milliseconds: AppDuration.ms160),
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
                    const SizedBox(width: AppSpace.p2),
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

///
/// 展开菜单中的单个白色胶囊入口。
///
class _LearningAction extends StatelessWidget {
  ///
  /// 创建开始新学习的胶囊按钮。
  const _LearningAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tokens,
    super.key,
  });

  ///
  /// 按钮使用的 Tabler 图标。
  final IconData icon;

  ///
  /// 按钮文案。
  final String label;

  ///
  /// 点击后开始新学习。
  final VoidCallback onTap;

  ///
  /// 当前主题设计令牌。
  final AppTokens tokens;

  ///
  /// 构建开始新学习的胶囊按钮。
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
      elevation: LearningFabLayout.itemElevation,
      // 投影颜色读卡片那一档令牌，和词库面板、结算页圆盘同一个出处。
      //
      // 原来这里写的是 `Colors.black` 加 20% 透明——全站唯一一处不走令牌的投影，
      // 深色模式下也不会跟着变淡。「这颗胶囊比旁边浮得高」这件事由上面的
      // elevation 表达就够了，不需要再单独调一次颜色的深浅。
      shadowColor: tokens.cardShadow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
        child: Container(
          height: LearningFabLayout.itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.p3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTokens.primary),
              const SizedBox(width: AppSpace.p2),
              Text(label, style: textTheme.fs5Semibold),
            ],
          ),
        ),
      ),
    );
  }
}

///
/// 学习主入口右侧的“继续”按钮，视觉上保持 Tabler 的轻量次要操作层级。
///
class _LearningContinueAction extends StatelessWidget {
  ///
  /// 创建继续按钮。
  const _LearningContinueAction({
    required this.onTap,
    required this.tokens,
    super.key,
  });

  ///
  /// 点击后恢复对应学习会话。
  final VoidCallback onTap;

  ///
  /// 当前主题颜色。
  final AppTokens tokens;

  ///
  /// 构建轻量的继续按钮。
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppTokens.primary.withValues(alpha: AppAlpha.a10),
      borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
      elevation: LearningFabLayout.continueElevation,
      // 同上：投影颜色统一读令牌，浮得比主入口低由 elevation 说明。
      shadowColor: tokens.cardShadow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
        child: Container(
          height: LearningFabLayout.itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.p3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedXxl),
            border: Border.all(
              color: AppTokens.primary.withValues(alpha: AppAlpha.a28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 所有图标都来自 Tabler；playerPlay 明确表达“从进度继续”。
              const Icon(AppGlyph.play, color: AppTokens.primary),
              const SizedBox(width: AppSpace.p2),
              Text(
                '继续',
                style: textTheme.fs5Semibold.copyWith(color: AppTokens.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
