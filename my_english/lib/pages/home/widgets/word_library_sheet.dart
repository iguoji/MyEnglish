// material.dart 提供布局、滚动与动画组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 固定 40 高搜索框组件。
import 'word_search_field.dart';

///
/// 底部词库抽屉：可拖拽展开的搜索 + 筛选 + 单词列表容器。
///
/// 实现思路：抽屉内容恒定按屏幕 88% 高度布局（内部 Column 含 Expanded，
/// 数学上不会溢出），收起时用 [AnimatedSlide] 把整体滑到屏幕下方、
/// 只露出顶部 56 像素手柄；展开时滑回原位。相比「动画容器高度 +
/// 条件渲染内容」的方案，避免了动画第一帧内容挤进旧高度导致的
/// RenderFlex 溢出，且展开动画更接近真实抽屉的滑出效果。
///
class WordLibrarySheet extends StatefulWidget {
  /// 创建抽屉。
  const WordLibrarySheet({
    required this.onSearchChanged,
    required this.groupFilterBar,
    required this.wordSortBar,
    required this.selectionBar,
    required this.listContent,
    required this.onFabTap,
    required this.fabLabel,
    super.key,
  });

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

  /// 点击「学习」悬浮按钮。
  final VoidCallback onFabTap;

  /// 悬浮按钮文案。
  final String fabLabel;

  @override
  State<WordLibrarySheet> createState() => _WordLibrarySheetState();
}

///
/// 管理抽屉展开/收起状态。
///
class _WordLibrarySheetState extends State<WordLibrarySheet> {
  /// 是否已经展开。
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  /// 供外部测试或父组件展开抽屉。
  void expand() {
    if (!_expanded) setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 展开高度固定为屏幕的 88%；抽屉整体恒定此高度布局，永不溢出。
    final screenHeight = MediaQuery.of(context).size.height;
    final fullHeight = screenHeight * 0.88;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        // 收起时整体下移，只露出顶部 56 像素的手柄区；展开时归位。
        // 偏移量是相对自身高度的分数：1 表示完全移出，再留 56/fullHeight。
        offset: _expanded
            ? Offset.zero
            : Offset(0, 1 - 56 / fullHeight),
        child: Container(
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
              // 拖拽手柄（点击切换展开/收起）。
              GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: _DragHandle(expanded: _expanded),
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
              // 列表区。
              Expanded(child: widget.listContent),
            ],
          ),
        ),
      ),
    );
  }
}

///
/// 拖拽手柄：居中圆角条；展开时附带「下拉收起」提示，收起时附带「上滑查看词库」。
///
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.expanded});

  /// 当前是否展开。
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: double.infinity,
      height: 28,
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
          // 手柄区高度固定 28 像素，超大字体会把文字挤出造成溢出。
          Text(
            expanded ? '下拉收起' : '上滑查看词库',
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
