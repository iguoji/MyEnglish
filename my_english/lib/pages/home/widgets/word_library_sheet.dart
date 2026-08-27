// material.dart 提供布局、滚动与动画组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供抽屉内部与底部操作栏等图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 固定 40 高搜索框组件。
import 'word_search_field.dart';

///
/// 底部词库抽屉：可拖拽展开的搜索 + 筛选 + 单词列表容器。
///
/// 抽屉内容恒定按屏幕 88% 高度布局；展开时用 TweenAnimationBuilder 从屏幕
/// 底部滑出进场，收起时瞬间移除、不保留屏幕外的实例以免阴影残留。上滑提示
/// 文字已移入首页文档流，跟随复习模式入口出现，不再由抽屉自己绘制。
/// 内部 Column 的布局高度始终不变，因此动画过程中不会发生内容挤压或溢出。
///
class WordLibrarySheet extends StatefulWidget {
  /// 创建抽屉。
  const WordLibrarySheet({
    required this.expanded,
    required this.onExpandedChanged,
    required this.onSearchChanged,
    required this.groupFilterBar,
    required this.wordSortBar,
    required this.selectionBar,
    required this.listContent,
    required this.targetCount,
    required this.hasListeningSession,
    required this.hasListeningMeaningSession,
    required this.onOpenListening,
    required this.onOpenListeningMeaning,
    required this.onContinueListening,
    required this.onContinueListeningMeaning,
    super.key,
  });

  /// 当前是否展开；状态由首页统一保存，避免父子组件各维护一份结果。
  final bool expanded;

  /// 展开状态变化时通知首页更新。
  final ValueChanged<bool> onExpandedChanged;

  /// 搜索输入回调。
  final ValueChanged<String> onSearchChanged;

  /// 分组筛选行（模式 + chips + 管理）。
  final Widget groupFilterBar;

  /// 排序与动作行。
  final Widget wordSortBar;

  /// 选择模式下的第二行工具；非选择模式时传 SizedBox.shrink()。
  final Widget selectionBar;

  /// 列表区内容（含加载、错误、空状态与分组列表）。
  final Widget listContent;

  /// 当前筛选或勾选后会进入学习页的单词数量。
  final int targetCount;

  /// 是否存在尚未完成的随身听进度。
  final bool hasListeningSession;

  /// 是否存在尚未完成的听音辨义进度。
  final bool hasListeningMeaningSession;

  /// 从当前词库范围开始一轮新的随身听。
  final VoidCallback onOpenListening;

  /// 从当前词库范围开始一轮新的听音辨义。
  final VoidCallback onOpenListeningMeaning;

  /// 继续上一次随身听进度。
  final VoidCallback onContinueListening;

  /// 继续上一次听音辨义进度。
  final VoidCallback onContinueListeningMeaning;

  @override
  State<WordLibrarySheet> createState() => _WordLibrarySheetState();
}

///
/// 管理抽屉展开/收起状态。
///
class _WordLibrarySheetState extends State<WordLibrarySheet> {
  /// 切换抽屉状态，并同步通知首页更新展开状态。
  void _setExpanded(bool expanded) {
    // 状态没有变化时不重复通知首页。
    if (widget.expanded == expanded) return;
    // 首页收到通知后 setState，把新值重新传回本组件。
    widget.onExpandedChanged(expanded);
  }

  /// 点击抽屉顶部手柄时切换展开状态。
  void _toggle() => _setExpanded(!widget.expanded);

  /// 供外部测试或父组件展开抽屉。
  void expand() {
    _setExpanded(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 展开高度固定为屏幕的 88%；抽屉整体恒定此高度布局，永不溢出。
    final screenHeight = MediaQuery.of(context).size.height;
    final fullHeight = screenHeight * 0.88;
    return Positioned.fill(
      // Stack 把完全隐藏的词库面板与底部提示文字放在同一层管理。
      child: Stack(
        children: [
          // 词库面板：只在展开时存在。用 TweenAnimationBuilder 做出从屏幕
          // 底部滑出的入场动画；收起时彻底不渲染，避免留下白色阴影残留。
          if (widget.expanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // Offset(0, 1) 表示把面板向下平移自身高度，视觉上正好落到
              // 屏幕下方；动画结束时归位，看起来就是「从下滑出」的效果。
              child: TweenAnimationBuilder<Offset>(
                tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                // FractionalTranslation 按自身尺寸比例平移，不改变布局占位。
                builder: (context, offset, child) => FractionalTranslation(
                  translation: offset,
                  child: child,
                ),
                child: Container(
                  key: const Key('word-library-surface'),
                  height: fullHeight,
                  decoration: BoxDecoration(
                    color: tokens.card,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.cardShadow,
                        blurRadius: 24,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 顶部先留 8 像素，不让手柄紧贴圆角边缘；当前交互明确为点击收起。
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: _toggle,
                          behavior: HitTestBehavior.opaque,
                          child: const _DragHandle(),
                        ),
                      ),
                      // header 区：搜索 + 筛选 + 排序。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                        child: Column(
                          children: [
                            WordSearchField(onChanged: widget.onSearchChanged),
                            const SizedBox(height: 12),
                            widget.groupFilterBar,
                            const SizedBox(height: 12),
                            widget.wordSortBar,
                            if (widget.selectionBar is! SizedBox) ...[
                              const SizedBox(height: 10),
                              widget.selectionBar,
                            ],
                          ],
                        ),
                      ),
                      // 列表区填满抽屉剩余高度。
                      Expanded(child: widget.listContent),
                      // SafeArea 自动读取系统底部操作区；若外层已经避让过，
                      // Flutter 会把这部分归零，避免同一安全距离被重复计算。
                      SafeArea(
                        top: false,
                        minimum: const EdgeInsets.only(bottom: 12),
                        child: _WordLibraryLearningBar(
                          targetCount: widget.targetCount,
                          hasListeningSession: widget.hasListeningSession,
                          hasListeningMeaningSession:
                              widget.hasListeningMeaningSession,
                          onOpenListening: widget.onOpenListening,
                          onOpenListeningMeaning: widget.onOpenListeningMeaning,
                          onContinueListening: widget.onContinueListening,
                          onContinueListeningMeaning:
                              widget.onContinueListeningMeaning,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

///
/// 词库底部学习操作栏：随身听与听音辨义始终左右平铺。
///
class _WordLibraryLearningBar extends StatelessWidget {
  /// 创建底部学习操作栏。
  const _WordLibraryLearningBar({
    required this.targetCount,
    required this.hasListeningSession,
    required this.hasListeningMeaningSession,
    required this.onOpenListening,
    required this.onOpenListeningMeaning,
    required this.onContinueListening,
    required this.onContinueListeningMeaning,
  });

  /// 当前学习范围的单词数量。
  final int targetCount;

  /// 随身听是否存在可恢复进度。
  final bool hasListeningSession;

  /// 听音辨义是否存在可恢复进度。
  final bool hasListeningMeaningSession;

  /// 开始新的随身听。
  final VoidCallback onOpenListening;

  /// 开始新的听音辨义。
  final VoidCallback onOpenListeningMeaning;

  /// 继续随身听。
  final VoidCallback onContinueListening;

  /// 继续听音辨义。
  final VoidCallback onContinueListeningMeaning;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return ColoredBox(
      // 测试用它定位这一条，确认词库列表正好长到操作栏顶边为止。
      key: const Key('word-library-learning-bar'),
      color: tokens.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _LearningAction(
                key: const Key('word-library-listening-action'),
                icon: TablerIcons.headphones,
                label: '随身听',
                targetCount: targetCount,
                emphasized: false,
                hasResume: hasListeningSession,
                continueKey: const Key('word-library-listening-continue'),
                onOpen: onOpenListening,
                onContinue: onContinueListening,
                tokens: tokens,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LearningAction(
                key: const Key('word-library-listening-meaning-action'),
                icon: TablerIcons.pencil,
                label: '听音辨义',
                targetCount: targetCount,
                emphasized: true,
                hasResume: hasListeningMeaningSession,
                continueKey: const Key(
                  'word-library-listening-meaning-continue',
                ),
                onOpen: onOpenListeningMeaning,
                onContinue: onContinueListeningMeaning,
                tokens: tokens,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///
/// 单个学习入口：主区域开始新任务，可选的右侧小区域继续历史进度。
///
class _LearningAction extends StatelessWidget {
  /// 创建一个底部学习入口。
  const _LearningAction({
    required this.icon,
    required this.label,
    required this.targetCount,
    required this.emphasized,
    required this.hasResume,
    required this.continueKey,
    required this.onOpen,
    required this.onContinue,
    required this.tokens,
    super.key,
  });

  /// Tabler 模式图标。
  final IconData icon;

  /// 模式名称。
  final String label;

  /// 本次会学习的单词数量。
  final int targetCount;

  /// 是否使用蓝色主按钮样式。
  final bool emphasized;

  /// 是否显示继续入口。
  final bool hasResume;

  /// 继续按钮的稳定标识，测试和无障碍工具无需依赖中文文案查找。
  final Key continueKey;

  /// 开始新任务。
  final VoidCallback onOpen;

  /// 继续历史任务。
  final VoidCallback onContinue;

  /// 当前主题设计令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final foreground = emphasized ? Colors.white : tokens.text;
    final background = emphasized ? AppTokens.accent : tokens.card;
    final borderColor = emphasized ? AppTokens.accent : tokens.border;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 19, color: foreground),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        '$label · $targetCount',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasResume) ...[
              // 竖线把“继续”与“重新开始”分开，避免误触时覆盖旧进度。
              Container(
                width: 1,
                height: 26,
                color: foreground.withValues(alpha: 0.22),
              ),
              Tooltip(
                message: '继续$label',
                child: InkWell(
                  key: continueKey,
                  onTap: onContinue,
                  child: SizedBox(
                    width: 40,
                    height: 48,
                    child: Icon(
                      TablerIcons.playerPlay,
                      size: 17,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

///
/// 抽屉展开后的顶部手柄：提示用户点击即可收起。
///
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: double.infinity,
      height: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: tokens.muted,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 4),
          // 提示文字为装饰性小字，不随系统字体缩放：
          // 手柄区高度固定 32 像素，超大字体会把文字挤出造成溢出。
          Text(
            '点击收起',
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
