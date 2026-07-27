// material.dart 提供弹出菜单、横向滚动与按钮组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 负责当前项、下拉和管理等全部图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

/// 首页分组视角；决定列表按什么维度分组显示。
enum GroupMode {
  /// 按用户自定义分组。
  custom,

  /// 按难度数值分组。
  difficulty,

  /// 按更新时间分组。
  updated,

  /// 按加入时间分组。
  added,
}

/// 为分组视角补充界面文字。
extension GroupModeDetails on GroupMode {
  /// 模式按钮与下拉菜单显示的名称。
  String get label => switch (this) {
    GroupMode.custom => '分组',
    GroupMode.difficulty => '难度',
    GroupMode.updated => '更新时间',
    GroupMode.added => '加入时间',
  };
}

/// 筛选 chip 的展示数据；由首页根据当前分组结果生成。
class GroupFilterChip {
  /// 创建一个 chip；key 为 null 表示"全部"。
  const GroupFilterChip({
    required this.sectionKey,
    required this.name,
    required this.isActive,
  });

  /// 对应分组区块的标识；null 表示不过滤。
  final String? sectionKey;

  /// chip 显示文字。
  final String name;

  /// 是否为当前生效的筛选项。
  final bool isActive;
}

/// 搜索框下方的分组行：模式下拉 + 横向筛选 chips + 分组管理按钮。
class GroupFilterBar extends StatelessWidget {
  /// 全部状态由首页管理，本组件只负责展示与回调。
  const GroupFilterBar({
    required this.mode,
    required this.chips,
    required this.onModeSelected,
    required this.onChipSelected,
    required this.onOpenManage,
    super.key,
  });

  /// 当前分组视角。
  final GroupMode mode;

  /// 当前可选的筛选 chips（含"全部"）。
  final List<GroupFilterChip> chips;

  /// 选择新的分组视角。
  final ValueChanged<GroupMode> onModeSelected;

  /// 点击某个筛选 chip；参数为 sectionKey，null 表示"全部"。
  final ValueChanged<String?> onChipSelected;

  /// 打开分组管理面板；仅自定义分组模式下可用。
  final VoidCallback onOpenManage;

  /// 输出模式按钮、chips 滚动区与管理按钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);

    // Row 横向排列三块内容，间距 10 像素。
    return Row(
      children: [
        // PopupMenuButton 点击后就地弹出四个模式选项。
        PopupMenuButton<GroupMode>(
          // key 供测试打开模式菜单。
          key: const Key('group-mode-button'),
          // 菜单弹在按钮正下方。
          position: PopupMenuPosition.under,
          // 按钮与菜单之间保留 6 像素间距。
          offset: const Offset(0, 6),
          // 长按提示用途。
          tooltip: '切换分组视角',
          // 选中后通知首页切换模式。
          onSelected: onModeSelected,
          // itemBuilder 逐个生成模式选项，当前项显示 Tabler 勾选图标并使用主色。
          itemBuilder: (context) => GroupMode.values
              .map(
                (option) => PopupMenuItem<GroupMode>(
                  // 每个选项都带 key，测试可以精确点击。
                  key: Key('group-mode-${option.name}'),
                  value: option,
                  // 与设计稿一致的紧凑高度。
                  height: 40,
                  child: Row(
                    // 文案在左勾选在右，中间留弹性空隙。
                    children: [
                      // 模式名称；当前项使用主色加粗。
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: option == mode
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: option == mode
                              ? AppTokens.accent
                              : tokens.text,
                        ),
                      ),
                      // 撑开中间空间。
                      const Spacer(),
                      // 当前项显示 Tabler 勾选图标，不再用文字字符模拟。
                      if (option == mode)
                        const Icon(
                          TablerIcons.check,
                          size: 14,
                          color: AppTokens.accent,
                        ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
          // child 是常驻按钮外观：模式名加 Tabler 下拉图标。
          child: Container(
            // 固定 32 高与设计稿一致。
            height: 32,
            // 左右 10 内边距。
            padding: const EdgeInsets.symmetric(horizontal: 10),
            // 卡片底、输入框边框、8 圆角。
            decoration: BoxDecoration(
              color: tokens.card,
              border: Border.all(color: tokens.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            // 内容横向排列并垂直居中。
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 当前模式名称。
                Text(
                  mode.label,
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // 名称与箭头间距。
                const SizedBox(width: 5),
                // 小号 Tabler 下拉箭头。
                Icon(
                  TablerIcons.chevronDown,
                  size: 14,
                  color: tokens.textSecondary,
                ),
              ],
            ),
          ),
        ),
        // 模式按钮与 chips 区之间的间距。
        const SizedBox(width: 10),
        // chips 占据剩余宽度并允许横向滚动。
        Expanded(
          child: SizedBox(
            // 固定高度避免滚动区域参与纵向拉伸。
            height: 28,
            // 横向列表逐个渲染 chip。
            child: ListView.separated(
              // 水平滚动，与设计稿 hscroll 一致。
              scrollDirection: Axis.horizontal,
              // chip 数量。
              itemCount: chips.length,
              // chip 之间 6 像素间距。
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              // 逐个构建胶囊按钮。
              itemBuilder: (context, index) {
                // 当前 chip 数据。
                final chip = chips[index];
                // InkWell 提供点击反馈。
                return InkWell(
                  onTap: () => onChipSelected(chip.sectionKey),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    // 垂直居中显示文字。
                    alignment: Alignment.center,
                    // 左右 12 内边距形成胶囊。
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // 选中实心主色，未选中卡片底描边。
                    decoration: BoxDecoration(
                      color: chip.isActive ? AppTokens.accent : tokens.card,
                      border: Border.all(
                        color: chip.isActive
                            ? AppTokens.accent
                            : tokens.inputBorder,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    // chip 文字。
                    child: Text(
                      chip.name,
                      style: TextStyle(
                        color: chip.isActive ? Colors.white : tokens.textMedium,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // chips 与管理按钮之间的间距。
        const SizedBox(width: 10),
        // 分组管理入口；非自定义分组模式降低透明度表示不可用。
        Opacity(
          opacity: mode == GroupMode.custom ? 1 : 0.35,
          child: InkWell(
            // key 供测试打开分组管理。
            key: const Key('open-manage'),
            onTap: onOpenManage,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              // 32×32 方形按钮。
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.card,
                border: Border.all(color: tokens.inputBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              // 列表管理图标近似设计稿的调节线条。
              child: Icon(
                TablerIcons.adjustmentsHorizontal,
                size: 16,
                color: tokens.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
