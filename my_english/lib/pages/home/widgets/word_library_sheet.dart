// material.dart 提供布局、滚动与动画组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

// 首页专属尺寸表：本组件的宽高从这里取名字，数值继承设计令牌总表。
import 'home_layout.dart';
// 固定 40 高搜索框组件。
import 'word_search_field.dart';

///
/// 底部词库抽屉：可拖拽展开的搜索 + 排序 + 单词列表容器。
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
    required this.wordSortBar,
    required this.selectionBar,
    required this.listContent,
    required this.learningBar,
    super.key,
  });

  /// 当前是否展开；状态由首页统一保存，避免父子组件各维护一份结果。
  final bool expanded;

  /// 展开状态变化时通知首页更新。
  final ValueChanged<bool> onExpandedChanged;

  /// 搜索输入回调。
  final ValueChanged<String> onSearchChanged;

  /// 排序与动作行。
  final Widget wordSortBar;

  /// 选择模式下的第二行工具；非选择模式时传 SizedBox.shrink()。
  final Widget selectionBar;

  /// 列表区内容（含加载、错误、空状态与分组列表）。
  final Widget listContent;

  /// 主播放按钮和自测模式入口，由首页传入同一份选词及恢复状态。
  final Widget learningBar;

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
    final fullHeight = screenHeight * WordLibraryLayout.heightRatio;
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
                duration: const Duration(milliseconds: AppDuration.ms250),
                curve: Curves.easeOutCubic,
                // FractionalTranslation 按自身尺寸比例平移，不改变布局占位。
                builder: (context, offset, child) =>
                    FractionalTranslation(translation: offset, child: child),
                child: Container(
                  key: const Key('word-library-surface'),
                  height: fullHeight,
                  decoration: BoxDecoration(
                    color: tokens.card,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.roundedXxl),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.cardShadow,
                        blurRadius: WordLibraryLayout.panelShadowBlur,
                        offset: const Offset(
                          0,
                          WordLibraryLayout.panelShadowOffsetY,
                        ),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          // 顶部先留 8 像素，不让手柄紧贴圆角边缘；当前交互明确为点击收起。
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpace.p2),
                            child: GestureDetector(
                              onTap: _toggle,
                              behavior: HitTestBehavior.opaque,
                              child: const _DragHandle(),
                            ),
                          ),
                          // header 区：搜索 + 排序。
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.pBase,
                              AppSpace.p1,
                              AppSpace.pBase,
                              AppSpace.p2,
                            ),
                            child: Column(
                              children: [
                                WordSearchField(
                                  onChanged: widget.onSearchChanged,
                                ),
                                // 排序行被两条参考线夹在中间：上面是搜索框底边框，
                                // 下面是列表顶那条 1px 分隔线。想让排序文字到两侧的
                                // 视觉距离相等，骨架必须对称：
                                //   上方 = 本段 p2(8) + 排序项顶内边距 p1(4) = 12
                                //   下方 = 排序项底内边距 p1(4) + 本区底内边距 p2(8) = 12
                                // 两侧同为 12，排序行才正好居中；原来这里用 p3(16)，
                                // 上方是 20、下方是 12，文字就整体偏向了列表那条线。
                                const SizedBox(height: AppSpace.p2),
                                widget.wordSortBar,
                                if (widget.selectionBar is! SizedBox) ...[
                                  const SizedBox(height: AppSpace.p2),
                                  widget.selectionBar,
                                ],
                              ],
                            ),
                          ),
                          // 列表区填满抽屉剩余高度。
                          Expanded(child: widget.listContent),
                        ],
                      ),
                      // 两行入口以面板底部为锚点悬浮，不再挤占列表高度，也没有整条底色。
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom:
                            MediaQuery.paddingOf(context).bottom +
                            WordLibraryLayout.learningBottom,
                        child: Center(child: widget.learningBar),
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
/// 抽屉展开后的顶部手柄：提示用户点击即可收起。
///
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: double.infinity,
      height: WordLibraryLayout.dragBarAreaHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: WordLibraryLayout.dragBarWidth,
            height: WordLibraryLayout.dragBarHeight,
            decoration: BoxDecoration(
              color: tokens.muted,
              borderRadius: BorderRadius.circular(AppRadius.roundedPill),
            ),
          ),
          const SizedBox(height: AppSpace.p1),
          // 提示文字为装饰性小字，不随系统字体缩放：
          // 手柄区高度固定 32 像素，超大字体会把文字挤出造成溢出。
          Text(
            '点击收起',
            textScaler: TextScaler.noScaling,
            style: textTheme.fs6.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
