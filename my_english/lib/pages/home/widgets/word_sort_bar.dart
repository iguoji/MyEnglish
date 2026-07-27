// material.dart 提供横向布局与文字按钮。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供升序、降序和可排序状态图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

/// 首页支持的排序字段；original 表示保持 Store/JSON 原始顺序。
enum WordSortField {
  /// 默认原始顺序。
  original,

  /// 按 spelling 字母排序。
  alphabet,

  /// 按 difficulty 排序。
  difficulty,

  /// 按 updatedAt ?? createdAt 排序。
  date,
}

/// 排序工具行：左侧四个排序项，右侧"折叠/展开"与"选择/完成"。
class WordSortBar extends StatelessWidget {
  /// 当前字段、各字段方向和全部动作都由 HomePage 保存并注入。
  const WordSortBar({
    required this.selectedField,
    required this.directions,
    required this.onSelected,
    required this.collapseLabel,
    required this.onToggleCollapseAll,
    required this.selectLabel,
    required this.onToggleSelectMode,
    super.key,
  });

  /// 当前高亮字段。
  final WordSortField selectedField;

  /// 除默认外每个字段上次使用的升降序。
  final Map<WordSortField, bool> directions;

  /// 点击排序项时通知首页切换字段或方向。
  final ValueChanged<WordSortField> onSelected;

  /// 右侧折叠按钮文案（折叠/展开）。
  final String collapseLabel;

  /// 点击折叠按钮时切换全部分组的展开状态。
  final VoidCallback onToggleCollapseAll;

  /// 右侧选择按钮文案（选择/完成）。
  final String selectLabel;

  /// 点击选择按钮时进入或退出选择模式。
  final VoidCallback onToggleSelectMode;

  /// 输出从左到右固定顺序的排序项与右侧动作。
  @override
  Widget build(BuildContext context) {
    // Row 按设计稿从左到右排列，排序项之间 18 像素间距。
    return Row(
      children: [
        // 排序项区域允许横向滚动，窄屏大字体时不会挤坏右侧动作。
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 默认项没有方向箭头。
                _SortChip(
                  field: WordSortField.original,
                  label: '默认',
                  isSelected: selectedField == WordSortField.original,
                  onPressed: onSelected,
                ),
                // 排序项之间的固定间距。
                const SizedBox(width: 18),
                // 字母排序，箭头方向由首页记录。
                _SortChip(
                  field: WordSortField.alphabet,
                  label: '字母',
                  isSelected: selectedField == WordSortField.alphabet,
                  isAscending: directions[WordSortField.alphabet] ?? true,
                  onPressed: onSelected,
                ),
                const SizedBox(width: 18),
                // 难度排序。
                _SortChip(
                  field: WordSortField.difficulty,
                  label: '难度',
                  isSelected: selectedField == WordSortField.difficulty,
                  isAscending: directions[WordSortField.difficulty] ?? false,
                  onPressed: onSelected,
                ),
                const SizedBox(width: 18),
                // 日期排序。
                _SortChip(
                  field: WordSortField.date,
                  label: '日期',
                  isSelected: selectedField == WordSortField.date,
                  isAscending: directions[WordSortField.date] ?? false,
                  onPressed: onSelected,
                ),
              ],
            ),
          ),
        ),
        // 排序区与右侧动作之间的间距。
        const SizedBox(width: 12),
        // 折叠/展开全部分组。
        _ActionText(
          key: const Key('toggle-collapse-all'),
          label: collapseLabel,
          color: AppTokens.accent,
          onTap: onToggleCollapseAll,
        ),
        // 两个动作之间的间距。
        const SizedBox(width: 18),
        // 进入/退出选择模式。
        _ActionText(
          key: const Key('toggle-select-mode'),
          label: selectLabel,
          color: AppTokens.accent,
          onTap: onToggleSelectMode,
        ),
      ],
    );
  }
}

/// 单个排序项：文字在左，紧贴其右显示 Tabler 排序方向图标。
class _SortChip extends StatelessWidget {
  /// 默认项不传 isAscending，其他三项必须传入方向。
  const _SortChip({
    required this.field,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.isAscending,
  });

  /// 当前按钮代表的字段。
  final WordSortField field;

  /// 界面显示文字。
  final String label;

  /// 是否为当前排序字段。
  final bool isSelected;

  /// true 升序、false 降序，null 代表默认项（无箭头）。
  final bool? isAscending;

  /// 点击后把字段交给首页。
  final ValueChanged<WordSortField> onPressed;

  /// 输出设计稿风格的纯文字排序项。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 选中项用主色，其余用中等文字色。
    final labelColor = isSelected ? AppTokens.accent : tokens.textMedium;
    // 默认项没有图标；未选中显示可排序，选中后显示当前升降方向。
    final IconData? sortIcon = isAscending == null
        ? null
        : isSelected
        ? (isAscending! ? TablerIcons.arrowUp : TablerIcons.arrowDown)
        : TablerIcons.arrowsSort;
    // 图标颜色：选中用主色，未选中用弱化色。
    final iconColor = isSelected ? AppTokens.accent : tokens.muted;

    // InkWell 提供点击反馈；纯文字按钮保持工具行紧凑。
    return InkWell(
      // key 便于测试和未来自动化准确点击字段。
      key: Key('word-sort-${field.name}'),
      // 点击触发首页逻辑；再次点击当前非默认项会翻转方向。
      onTap: () => onPressed(field),
      // 轻微圆角反馈。
      borderRadius: BorderRadius.circular(6),
      // 上下 4 像素让触控区域略大于文字。
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        // Row 排列文字与箭头。
        child: Row(
          // 行宽只包住内容。
          mainAxisSize: MainAxisSize.min,
          children: [
            // 字段名文字；选中加粗。
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            // 有排序状态时紧贴文字右侧放置 Tabler 图标。
            if (sortIcon != null) ...[
              const SizedBox(width: 3),
              Icon(sortIcon, color: iconColor, size: 13),
            ],
          ],
        ),
      ),
    );
  }
}

/// 右侧纯文字动作按钮（折叠/展开、选择/完成、全选、反选等复用）。
class _ActionText extends StatelessWidget {
  /// 接收文案、颜色与点击动作。
  const _ActionText({
    required this.label,
    required this.color,
    required this.onTap,
    this.fontWeight = FontWeight.w600,
    super.key,
  });

  /// 按钮文案。
  final String label;

  /// 文字颜色。
  final Color color;

  /// 文字字重，默认为半粗。
  final FontWeight fontWeight;

  /// 点击动作。
  final VoidCallback onTap;

  /// 输出带轻点反馈的文字按钮。
  @override
  Widget build(BuildContext context) {
    // InkWell 提供反馈但不引入 Material 按钮的默认尺寸膨胀。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        // 与排序项相同的纵向触控内边距。
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13.5,
            fontWeight: fontWeight,
          ),
        ),
      ),
    );
  }
}

/// 选择模式下的第二行工具：已选计数、全选、反选、移动、复制。
class WordSelectionBar extends StatelessWidget {
  /// 全部状态与动作由首页注入。
  const WordSelectionBar({
    required this.selectedCount,
    required this.onSelectAll,
    required this.onInvertSelection,
    required this.onMove,
    required this.onCopy,
    super.key,
  });

  /// 当前已选中的单词数量。
  final int selectedCount;

  /// 全选当前可见单词。
  final VoidCallback onSelectAll;

  /// 反选当前可见单词。
  final VoidCallback onInvertSelection;

  /// 移动所选到指定分组；没有选中时首页会忽略。
  final VoidCallback onMove;

  /// 复制所选到指定分组；没有选中时首页会忽略。
  final VoidCallback onCopy;

  /// 输出与设计稿一致的选择工具行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 有选中时移动/复制用主色，否则用弱化色表示不可用。
    final actionColor = selectedCount > 0 ? AppTokens.accent : tokens.check;

    // Row 排列计数与四个动作。
    return Row(
      children: [
        // 左侧计数与选择动作允许横向滚动，窄屏大字体时不溢出。
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 已选计数使用次要文字色。
                Text(
                  '已选 $selectedCount',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 13.5),
                ),
                const SizedBox(width: 18),
                // 全选当前可见单词。
                _ActionText(
                  key: const Key('select-all'),
                  label: '全选',
                  color: tokens.textMedium,
                  fontWeight: FontWeight.w500,
                  onTap: onSelectAll,
                ),
                const SizedBox(width: 18),
                // 反选当前可见单词。
                _ActionText(
                  key: const Key('invert-selection'),
                  label: '反选',
                  color: tokens.textMedium,
                  fontWeight: FontWeight.w500,
                  onTap: onInvertSelection,
                ),
              ],
            ),
          ),
        ),
        // 左区与移动/复制之间的间距。
        const SizedBox(width: 12),
        // 移动所选单词。
        _ActionText(
          key: const Key('move-selected'),
          label: '移动',
          color: actionColor,
          onTap: onMove,
        ),
        const SizedBox(width: 18),
        // 复制所选单词。
        _ActionText(
          key: const Key('copy-selected'),
          label: '复制',
          color: actionColor,
          onTap: onCopy,
        ),
      ],
    );
  }
}
