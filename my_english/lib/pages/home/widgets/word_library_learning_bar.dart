import 'package:flutter/material.dart';

import '../../../common/theme.dart';
import '../../../models/session.dart';
import '../../../services/self_test_policy.dart';
import 'home_layout.dart';

/// 两行悬浮入口：无底色的词数，以及一个内部三分区的胶囊。
/// 菜单沿胶囊的中轴向上展开，共用一个背景与外轮廓；底部操作条始终保持固定尺寸。
class WordLibraryLearningBar extends StatefulWidget {
  const WordLibraryLearningBar({
    required this.listeningCount,
    required this.selectedCount,
    required this.selectedModule,
    required this.hasResume,
    required this.busy,
    required this.onModuleChanged,
    required this.onStart,
    required this.onContinue,
    super.key,
  });

  final int listeningCount;
  final int selectedCount;
  final ReviewModule selectedModule;
  final bool hasResume;
  final bool busy;
  final ValueChanged<ReviewModule> onModuleChanged;
  final VoidCallback onStart;
  final VoidCallback onContinue;

  @override
  State<WordLibraryLearningBar> createState() => _WordLibraryLearningBarState();
}

class _WordLibraryLearningBarState extends State<WordLibraryLearningBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: AppDuration.ms250),
  );
  late final CurvedAnimation _expansion = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  bool _menuOpen = false;

  void _setMenuOpen(bool open) {
    if (_menuOpen == open) return;
    setState(() => _menuOpen = open);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = open ? 1 : 0;
    } else if (open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _toggleMenu() {
    FocusManager.instance.primaryFocus?.unfocus();
    _setMenuOpen(!_menuOpen);
  }

  void _perform(VoidCallback action) {
    _setMenuOpen(false);
    action();
  }

  @override
  void didUpdateWidget(covariant WordLibraryLearningBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && _menuOpen) _setMenuOpen(false);
  }

  @override
  void dispose() {
    _expansion.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final isListening = widget.selectedModule == ReviewModule.listening;
    final count = isListening ? widget.listeningCount : widget.selectedCount;
    final reason = isListening
        ? (count == 0 ? '当前列表没有可播放的单词' : null)
        : SelfTestPolicy.unavailableReason(count);
    final canStart = !widget.busy && reason == null;
    final canContinue = !widget.busy && widget.hasResume;
    final continueLabel = isListening
        ? '继续随身听'
        : '继续${widget.selectedModule.label}自测';
    final radius = BorderRadius.circular(
      WordLibraryLayout.learningCapsuleHeight / 2,
    );

    return TapRegion(
      // 收起状态不挡住词库；展开后，点外面只收起菜单，不误选底下的单词。
      consumeOutsideTaps: _menuOpen,
      onTapOutside: (_) => _setMenuOpen(false),
      child: SizedBox(
        key: const Key('word-library-learning-bar'),
        width: WordLibraryLayout.learningCapsuleWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IgnorePointer(
              child: SizedBox(
                height: WordLibraryLayout.learningCountHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _moduleIcon(widget.selectedModule),
                      size: AppIcon.i16,
                      color: AppTokens.primary,
                    ),
                    const SizedBox(width: AppSpace.p1),
                    Text(
                      '$count 个单词',
                      key: const Key('word-library-target-count'),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.fs5Semibold.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: WordLibraryLayout.learningCountGap),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
              ),
              // 一张 Material 统一外轮廓，三个区域只切换状态色，不各自绘制圆角。
              // 描边代替阴影：改用全站统一的控件描边 rowBorder 勾出浅浅一圈轮廓，
              // 与首页热力图、四模块卡片同一口径；去掉原来的重描边 + 投影。
              child: Material(
                key: const Key('word-library-module-shell'),
                color: AppTokens.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 向上展开时胶囊的下边缘不动，词数随菜单顶部平滑上移。
                    // 菜单与当前模块居中对齐，不跟随左侧切换图标偏向左边。
                    SizeTransition(
                      sizeFactor: _expansion,
                      alignment: Alignment.bottomCenter,
                      child: IgnorePointer(
                        ignoring: !_menuOpen,
                        child: ExcludeSemantics(
                          excluding: !_menuOpen,
                          child: FadeTransition(
                            opacity: _expansion,
                            child: _buildMenu(tokens),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      key: const Key('word-library-module-pill'),
                      width: WordLibraryLayout.learningCapsuleWidth,
                      height: WordLibraryLayout.learningCapsuleHeight,
                      child: Row(
                        children: [
                          _segment(
                            key: const Key('word-library-module-switch'),
                            label: _menuOpen ? '收起模块列表' : '切换模块',
                            width: WordLibraryLayout.learningSideWidth,
                            enabled: !widget.busy,
                            background: AppTokens.primary,
                            onTap: _toggleMenu,
                            child: Icon(
                              AppGlyph.switchModule,
                              size: AppIcon.i20,
                              color: widget.busy
                                  ? Colors.white.withValues(alpha: AppAlpha.a56)
                                  : Colors.white,
                            ),
                          ),
                          _divider(tokens),
                          Expanded(
                            child: _segment(
                              key: const Key('word-library-module-start'),
                              label: '开始${widget.selectedModule.label}',
                              tooltip:
                                  reason ?? '开始${widget.selectedModule.label}',
                              enabled: canStart,
                              background: AppTokens.primary,
                              onTap: () => _perform(widget.onStart),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpace.p2,
                                ),
                                child: AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(
                                          milliseconds: AppDuration.ms160,
                                        ),
                                  child: FittedBox(
                                    key: ValueKey(widget.selectedModule),
                                    fit: BoxFit.scaleDown,
                                    child: _moduleLabel(
                                      widget.selectedModule,
                                      tokens,
                                      showIcon: false,
                                      foreground: canStart
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: AppAlpha.a56),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _divider(tokens),
                          _segment(
                            key: const Key('word-library-module-continue'),
                            label: continueLabel,
                            tooltip: widget.hasResume
                                ? continueLabel
                                : isListening
                                ? '暂无可继续的播放清单'
                                : '暂无已作答的自测进度',
                            width: WordLibraryLayout.learningSideWidth,
                            enabled: canContinue,
                            background: AppTokens.primary,
                            onTap: () => _perform(widget.onContinue),
                            child: Icon(
                              AppGlyph.play,
                              size: AppIcon.i20,
                              color: canContinue
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: AppAlpha.a56),
                            ),
                          ),
                        ],
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

  Widget _buildMenu(AppTokens tokens) => Container(
    // 展开列表底色用白色卡片，与下方实蓝操作条形成清晰的「下拉菜单 / 操作条」分区。
    // 白色列表加一圈全站统一控件描边 rowBorder，圆角与胶囊外壳一致。
    decoration: BoxDecoration(
      color: tokens.card,
      border: Border.all(color: tokens.rowBorder, width: AppStroke.thin),
      borderRadius: BorderRadius.circular(
        WordLibraryLayout.learningCapsuleHeight / 2,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpace.p2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final module in ReviewModule.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.p2),
              child: Semantics(
                selected: module == widget.selectedModule,
                child: InkWell(
                  key: Key('word-library-mode-${module.storageKey}'),
                  borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  onTap: () {
                    _setMenuOpen(false);
                    widget.onModuleChanged(module);
                  },
                  child: Container(
                    width: double.infinity,
                    height: AppSize.touchTarget,
                    decoration: BoxDecoration(
                      color: module == widget.selectedModule
                          ? Color.alphaBlend(
                              AppTokens.primary.withValues(alpha: AppAlpha.a10),
                              tokens.card,
                            )
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _moduleLabel(module, tokens),
                        if (module == widget.selectedModule)
                          const Positioned(
                            right: AppSpace.p3,
                            child: Icon(
                              AppGlyph.selected,
                              size: AppIcon.i16,
                              color: AppTokens.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.p3,
              AppSpace.p2,
              AppSpace.p3,
              AppSpace.p0,
            ),
            child: ColoredBox(
              color: tokens.rowBorder,
              child: const SizedBox(
                height: AppStroke.thin,
                width: double.infinity,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _moduleLabel(
    ReviewModule module,
    AppTokens tokens, {
    bool showIcon = true,
    Color? foreground,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showIcon)
        Icon(
          _moduleIcon(module),
          size: AppIcon.i20,
          color:
              foreground ??
              (module == widget.selectedModule
                  ? AppTokens.primary
                  : tokens.textSecondary),
        ),
      if (showIcon) const SizedBox(width: AppSpace.p2),
      Text(
        module.label,
        maxLines: 1,
        style: Theme.of(
          context,
        ).textTheme.fs5Semibold.copyWith(color: foreground ?? tokens.text),
      ),
    ],
  );

  Widget _divider(AppTokens tokens) => ColoredBox(
    color: Colors.white.withValues(alpha: AppAlpha.a28),
    child: const SizedBox(
      width: AppStroke.thin,
      height: WordLibraryLayout.learningDividerHeight,
    ),
  );

  Widget _segment({
    required Key key,
    required String label,
    String? tooltip,
    required bool enabled,
    required Color background,
    required VoidCallback onTap,
    required Widget child,
    double? width,
  }) => Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: Tooltip(
      message: tooltip ?? label,
      excludeFromSemantics: true,
      child: Listener(
        // 禁用的继续区仍占据自己的点击范围，不把手势穿透给背后的单词行。
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: background,
          child: InkWell(
            key: key,
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: width,
              height: WordLibraryLayout.learningCapsuleHeight,
              child: Center(child: ExcludeSemantics(child: child)),
            ),
          ),
        ),
      ),
    ),
  );

  static IconData _moduleIcon(ReviewModule module) => switch (module) {
    ReviewModule.listening => AppGlyph.moduleListening,
    ReviewModule.listeningMeaning => AppGlyph.moduleListeningMeaning,
    ReviewModule.meaningMatch => AppGlyph.moduleMeaningMatch,
    ReviewModule.spellingReinforcement => AppGlyph.moduleListening,
    ReviewModule.meaningWordChoice => AppGlyph.moduleMeaningWordChoice,
  };
}
