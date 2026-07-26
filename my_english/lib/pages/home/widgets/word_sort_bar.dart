// material.dart 提供横向布局、文字按钮和排序方向图标。
import 'package:flutter/material.dart';

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

/// 搜索栏下方的四项排序工具栏。
class WordSortBar extends StatelessWidget {
  /// 当前字段、各字段方向和点击回调都由 HomePage 保存。
  const WordSortBar({
    required this.selectedField,
    required this.directions,
    required this.onSelected,
    super.key,
  });

  /// 当前高亮字段。
  final WordSortField selectedField;

  /// 除默认外每个字段上次使用的升降序。
  final Map<WordSortField, bool> directions;

  /// 点击选项时通知首页切换字段或方向。
  final ValueChanged<WordSortField> onSelected;

  /// 输出从左到右固定顺序的排序项。
  @override
  Widget build(BuildContext context) {
    // 小屏或大字体时允许横向滚动，避免四项文字和图标重叠。
    return SingleChildScrollView(
      // 排序本身是水平工具栏。
      scrollDirection: Axis.horizontal,
      // Row 按产品要求从左到右排列。
      child: Row(
        children: [
          // 默认项使用列表图标，没有升降序概念。
          _SortButton(
            field: WordSortField.original,
            label: '默认',
            isSelected: selectedField == WordSortField.original,
            onPressed: onSelected,
          ),
          // 字母默认升序，箭头状态由首页传入。
          _SortButton(
            field: WordSortField.alphabet,
            label: '字母',
            isSelected: selectedField == WordSortField.alphabet,
            isAscending: directions[WordSortField.alphabet] ?? true,
            onPressed: onSelected,
          ),
          // 难度默认降序。
          _SortButton(
            field: WordSortField.difficulty,
            label: '难度',
            isSelected: selectedField == WordSortField.difficulty,
            isAscending: directions[WordSortField.difficulty] ?? false,
            onPressed: onSelected,
          ),
          // 日期默认降序，即最近更新/加入的单词优先。
          _SortButton(
            field: WordSortField.date,
            label: '日期',
            isSelected: selectedField == WordSortField.date,
            isAscending: directions[WordSortField.date] ?? false,
            onPressed: onSelected,
          ),
        ],
      ),
    );
  }
}

/// 单个排序项；选中状态使用主题主色，未选中使用次要文字色。
class _SortButton extends StatelessWidget {
  /// 默认项不传 isAscending，其他三项必须传入方向。
  const _SortButton({
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

  /// true 是升序箭头，false 是降序箭头，null 代表默认项。
  final bool? isAscending;

  /// 点击后把字段交给首页。
  final ValueChanged<WordSortField> onPressed;

  /// 输出紧凑的文字加图标按钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前 Light/Dark 的语义色。
    final colorScheme = Theme.of(context).colorScheme;
    // 当前项用主色，其余项用次要文字色。
    final foregroundColor = isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    // 默认项显示列表，其他项显示当前升降序箭头。
    final icon = isAscending == null
        ? Icons.format_list_bulleted_rounded
        : isAscending!
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    // TextButton.icon 保证每项都采用“全文字 + 图标”。
    return TextButton.icon(
      // key 便于测试和未来自动化准确点击字段。
      key: Key('word-sort-${field.name}'),
      // 点击触发首页逻辑；再次点击当前非默认项会翻转方向。
      onPressed: () => onPressed(field),
      // 图标固定 16 像素，不会改变工具栏高度。
      icon: Icon(icon, size: 16),
      // label 完整显示中文字段名。
      label: Text(label),
      // 紧凑 Material 3 按钮保持工具栏工作型密度。
      style: TextButton.styleFrom(
        // 应用选中或未选中颜色。
        foregroundColor: foregroundColor,
        // 固定最小高度，避免交互时布局跳动。
        minimumSize: const Size(64, 36),
        // 左右 8 像素在四项之间形成稳定间距。
        padding: const EdgeInsets.symmetric(horizontal: 8),
        // 文字保持紧凑，不使用视口缩放字号。
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}
