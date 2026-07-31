// material.dart 提供底部面板、输入框与按钮。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供分组新增、排序和删除图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 分组内存 Store。
import '../../../store/group.dart';

/// 从页面底部弹出"分组管理"面板。
Future<void> showManageGroupsSheet(BuildContext context, GroupStore groups) {
  // showModalBottomSheet 提供标准弹出动画与遮罩。
  return showModalBottomSheet<void>(
    context: context,
    // 面板可能较高，允许自定义高度。
    isScrollControlled: true,
    // 背景色由内容自绘，保持与设计稿一致的圆角。
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ManageGroupsSheet(groups: groups),
  );
}

/// 分组管理面板：重命名、排序、删除与新建。
class _ManageGroupsSheet extends StatelessWidget {
  /// 接收全局分组 Store。
  const _ManageGroupsSheet({required this.groups});

  /// 所有修改直接写入该 Store。
  final GroupStore groups;

  /// 输出标题行与分组编辑列表。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让 Store 每次修改后刷新面板内容。
    return ListenableBuilder(
      listenable: groups,
      builder: (context, child) {
        // 当前分组快照。
        final list = groups.groups;
        // Container 绘制设计稿的顶部圆角卡片。
        return Container(
          // 最高占屏 70%，内部列表自行滚动。
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          // 上 16、下 30 与设计稿一致。
          // viewInsets.bottom 是系统键盘当前高度；isScrollControlled 的底部弹层不会
          // 被键盘自动顶起，必须在这里把键盘高度补进底部内边距，否则键盘会盖住
          // 可滚动列表里靠下的分组名输入框。
          padding: EdgeInsets.fromLTRB(
            0,
            16,
            0,
            30 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            // 高度只包住内容。
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题行：名称在左，"完成"在右。
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    // 面板标题。
                    Text(
                      '分组管理',
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // 撑开中间空间。
                    const Spacer(),
                    // 完成即关闭面板。
                    InkWell(
                      key: const Key('manage-done'),
                      onTap: () => Navigator.of(context).pop(),
                      // 纯文字“完成”不需要按压背景，只保留点击行为。
                      overlayColor: const WidgetStatePropertyAll<Color>(
                        Colors.transparent,
                      ),
                      // 禁止水波纹扩散，避免真机点击时出现一块灰色背景。
                      splashFactory: NoSplash.splashFactory,
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          color: AppTokens.accent,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 分组编辑区域可滚动。
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                  child: Column(
                    children: [
                      // 逐个分组生成编辑行。
                      for (var index = 0; index < list.length; index += 1) ...[
                        // 行间 8 像素间距。
                        if (index > 0) const SizedBox(height: 8),
                        // 单个分组编辑行。
                        _GroupEditRow(
                          groups: groups,
                          groupId: list[index].id,
                          name: list[index].name,
                          canMoveUp: index > 0,
                          canMoveDown: index < list.length - 1,
                        ),
                      ],
                      // 与新建按钮之间的间距。
                      const SizedBox(height: 10),
                      // 新建分组虚线按钮。
                      InkWell(
                        key: const Key('add-group'),
                        onTap: groups.add,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Flutter 无内置虚线边框，用浅色实线近似设计稿。
                            border: Border.all(color: tokens.check),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                TablerIcons.folderPlus,
                                size: 16,
                                color: tokens.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '新建分组',
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
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个分组的编辑行：名称输入 + 上移/下移/删除。
class _GroupEditRow extends StatelessWidget {
  /// 行内动作直接调用 Store。
  const _GroupEditRow({
    required this.groups,
    required this.groupId,
    required this.name,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  /// 全局分组 Store。
  final GroupStore groups;

  /// 当前行分组主键。
  final int groupId;

  /// 当前名称。
  final String name;

  /// 是否可以上移。
  final bool canMoveUp;

  /// 是否可以下移。
  final bool canMoveDown;

  /// 输出输入框与三个方块按钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);

    // Row 横向排列输入框与按钮。
    return Row(
      children: [
        // 名称输入框占据剩余宽度。
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextFormField(
              // initialValue + onChanged 避免为每行维护 controller。
              initialValue: name,
              onChanged: (value) => groups.rename(groupId, value),
              style: TextStyle(color: tokens.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tokens.inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTokens.accent),
                ),
              ),
            ),
          ),
        ),
        // 输入框与按钮组间距。
        const SizedBox(width: 8),
        // 上移按钮。
        _SquareButton(
          icon: TablerIcons.arrowUp,
          enabled: canMoveUp,
          onTap: () => groups.moveUp(groupId),
        ),
        const SizedBox(width: 8),
        // 下移按钮。
        _SquareButton(
          icon: TablerIcons.arrowDown,
          enabled: canMoveDown,
          onTap: () => groups.moveDown(groupId),
        ),
        const SizedBox(width: 8),
        // 删除按钮：点击后弹确认对话框，确认后才真正删除。
        // 分组里的单词由首页监听后移回"未分组"，因此允许删除任意分组（含最后一个）。
        _SquareButton(
          icon: TablerIcons.trash,
          enabled: true,
          onTap: () => _confirmDelete(context),
        ),
      ],
    );
  }

  /// 弹出删除确认对话框；用户确认后才执行 groups.remove。
  Future<void> _confirmDelete(BuildContext context) async {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // showDialog 返回 Future<bool?>：true=确认，false/null=取消。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        // 自绘圆角卡片，与删除单词对话框风格一致。
        backgroundColor: tokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            // 高度只包住内容。
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 对话框标题。
              Text(
                '删除分组',
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // 标题与正文间距。
              const SizedBox(height: 8),
              // 确认文案带分组名称。
              Text(
                '确定要删除分组「$name」吗？组内单词将自动移回未分组。',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              // 正文与按钮间距。
              const SizedBox(height: 18),
              // 取消与删除按钮。
              Row(
                children: [
                  // 取消按钮：描边样式。
                  Expanded(
                    child: InkWell(
                      key: const Key('group-delete-cancel'),
                      onTap: () => Navigator.of(dialogContext).pop(false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.inputBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '取消',
                          style: TextStyle(
                            color: tokens.textMedium,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 删除按钮：危险色实底。
                  Expanded(
                    child: InkWell(
                      key: const Key('group-delete-confirm'),
                      onTap: () => Navigator.of(dialogContext).pop(true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTokens.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '删除',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // 用户点击删除才执行；点击取消或点遮罩关闭都返回 false/null。
    if (confirmed == true) {
      groups.remove(groupId);
    }
  }
}

/// 34×34 描边方块按钮；不可用时降低透明度。
class _SquareButton extends StatelessWidget {
  /// 接收 Tabler 图标、可用状态与动作。
  const _SquareButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  /// 按钮使用的 Tabler 图标数据。
  final IconData icon;

  /// 是否可用。
  final bool enabled;

  /// 点击动作；不可用时不触发。
  final VoidCallback onTap;

  /// 输出方块按钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Opacity 表达设计稿的禁用视觉。
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: InkWell(
        // 不可用时不注册点击。
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.card,
            border: Border.all(color: tokens.inputBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: tokens.textMedium, size: 15),
        ),
      ),
    );
  }
}
