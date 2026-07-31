// material.dart 提供输入框、按钮、布局和主题组件。
import 'package:flutter/material.dart';
// Tabler 图标包提供页面全部可见图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局设计令牌。
import '../../../common/theme.dart';
// 引入随身听统一布局尺寸。
import 'listening_layout.dart';

///
/// 播放列表顶部的紧凑搜索框，对应小程序中的受控 input 组件。
///
class ListeningPlaylistSearchField extends StatelessWidget {
  ///
  /// 父页面负责保存输入值，本组件只负责稳定尺寸和视觉样式。
  ///
  /// @param  TextEditingController  controller
  /// @param  AppTokens  tokens
  /// @param  `ValueChanged<String>`  onChanged
  /// @param  Key?  key
  ///
  const ListeningPlaylistSearchField({
    required this.controller,
    required this.tokens,
    required this.onChanged,
    super.key,
  });

  ///
  /// 控制器保存当前输入文本，作用类似小程序 input 的 value 双向绑定来源。
  ///
  /// @var TextEditingController
  ///
  final TextEditingController controller;

  ///
  /// 页面主题颜色集合。
  ///
  /// @var AppTokens
  ///
  final AppTokens tokens;

  ///
  /// 输入变化回调，父页面收到后更新搜索过滤条件。
  ///
  /// @var `ValueChanged<String>`
  ///
  final ValueChanged<String> onChanged;

  ///
  /// Flutter 每次绘制搜索区域时调用此方法。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // SizedBox 把输入框高度固定为 32，与左右两个图标按钮完全相等。
    return SizedBox(
      height: ListeningLayout.compactControlSize,
      // TextField 对应小程序 input，内部不再使用额外高度补丁。
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        // 明确要求文字在固定高度中垂直居中。
        textAlignVertical: TextAlignVertical.center,
        // 用户输入文字和 placeholder 使用相同字号与行高，切换时不会抖动。
        style: TextStyle(color: tokens.text, fontSize: 13, height: 1.2),
        // InputDecoration 统一管理搜索图标、提示文字、边框和内部留白。
        decoration: InputDecoration(
          // 紧凑模式移除 Material 默认的大块垂直留白。
          isDense: true,
          // 输入为空时显示简短提示。
          hintText: '搜索',
          // 提示文字与输入文字共用相同行高。
          hintStyle: TextStyle(color: tokens.muted, fontSize: 13, height: 1.2),
          // 搜索图标属于输入框内容，不额外占用独立按钮位置。
          prefixIcon: Icon(TablerIcons.search, size: 16, color: tokens.muted),
          // 图标占位高度与输入框一致，从约束层保证上下居中。
          prefixIconConstraints: const BoxConstraints(
            minWidth: ListeningLayout.compactControlSize,
            minHeight: ListeningLayout.compactControlSize,
          ),
          // 左侧宽度已由 prefixIconConstraints 提供，只给文字右侧保留 8 像素。
          contentPadding: const EdgeInsets.only(right: 8),
          // 未聚焦时使用普通输入框边框。
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: tokens.inputBorder),
          ),
          // 聚焦后只改变边框颜色，不改变宽度、高度或内边距。
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTokens.accent),
          ),
        ),
      ),
    );
  }
}

///
/// 设置面板中的数字步进器行，对应小程序中的“标签 + 减号 + 数值 + 加号”。
///
class ListeningSettingRow extends StatelessWidget {
  ///
  /// 父级提供当前数值和两个方向的可空回调。
  ///
  /// @param  String  label
  /// @param  int  value
  /// @param  VoidCallback?  onMinus
  /// @param  VoidCallback?  onPlus
  /// @param  Key?  key
  ///
  const ListeningSettingRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    super.key,
  });

  ///
  /// 左侧设置名称。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 中间显示的当前整数值。
  ///
  /// @var int
  ///
  final int value;

  ///
  /// 点击减号时执行；null 表示已经达到下限。
  ///
  /// @var VoidCallback?
  ///
  final VoidCallback? onMinus;

  ///
  /// 点击加号时执行；null 表示已经达到上限。
  ///
  /// @var VoidCallback?
  ///
  final VoidCallback? onPlus;

  ///
  /// Flutter 绘制每一项设置时调用 build。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前主题颜色。
    final tokens = AppTokens.of(context);
    // Container 固定行高并绘制底部分隔线。
    return Container(
      height: ListeningLayout.settingsRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.rowBorder)),
      ),
      // Row 把名称和步进控制器排列在同一行。
      child: Row(
        children: [
          // 左侧标签。
          Text(label, style: TextStyle(color: tokens.text, fontSize: 14.5)),
          // Spacer 把右侧控件推到行尾。
          const Spacer(),
          // 减号按钮。
          _StepButton(icon: TablerIcons.minus, onTap: onMinus),
          // 固定 44 像素数值区，位数变化时两侧按钮不会移动。
          SizedBox(
            width: 44,
            // 当前值水平居中。
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 加号按钮。
          _StepButton(icon: TablerIcons.plus, onTap: onPlus),
        ],
      ),
    );
  }
}

///
/// 数字步进器的单个方形图标按钮。
///
class _StepButton extends StatelessWidget {
  ///
  /// onTap 可以为空，Flutter 会据此禁用 InkWell。
  ///
  /// @param  IconData  icon
  /// @param  VoidCallback?  onTap
  ///
  const _StepButton({required this.icon, required this.onTap});

  ///
  /// 加号或减号图标。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 点击回调；null 表示当前方向不可继续调整。
  ///
  /// @var VoidCallback?
  ///
  final VoidCallback? onTap;

  ///
  /// Flutter 绘制按钮时调用 build。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取主题颜色。
    final tokens = AppTokens.of(context);
    // 固定 28×28 点击画布。
    return SizedBox(
      width: 28,
      height: 28,
      // Material 提供 InkWell 绘制点击反馈所需的材质层。
      child: Material(
        color: tokens.card,
        borderRadius: BorderRadius.circular(8),
        // InkWell 在 onTap=null 时自动禁用交互。
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          // Container 绘制按钮的一像素边框。
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            // 禁用状态使用更浅颜色，但图标和画布尺寸保持不变。
            child: Icon(
              icon,
              size: 15,
              color: onTap == null ? tokens.muted : tokens.textMedium,
            ),
          ),
        ),
      ),
    );
  }
}

///
/// 固定画布图标按钮，只允许约束对齐，不提供任何人工位移参数。
///
class ListeningIconButton extends StatelessWidget {
  ///
  /// 图标按钮只接收图标、点击回调和画布内对齐方式。
  ///
  /// @param  IconData  icon
  /// @param  VoidCallback  onTap
  /// @param  Color?  color
  /// @param  AlignmentGeometry  alignment
  /// @param  Key?  key
  ///
  const ListeningIconButton({
    required this.icon,
    required this.onTap,
    this.color,
    this.alignment = Alignment.center,
    super.key,
  });

  ///
  /// Tabler 图标数据，相当于小程序 icon 组件的 type。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 点击后执行的业务回调。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 可选图标颜色，不传时使用主题中的中等文字颜色。
  ///
  /// @var Color?
  ///
  final Color? color;

  ///
  /// 图标画布在固定点击区域内的合法对齐方式，例如左中、右中或右上。
  ///
  /// @var AlignmentGeometry
  ///
  final AlignmentGeometry alignment;

  ///
  /// Flutter 每次需要绘制按钮时都会调用 build。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 从当前主题读取默认图标颜色。
    final tokens = AppTokens.of(context);
    // SizedBox 明确声明完整点击画布，不依赖图标自身透明区域计算尺寸。
    return SizedBox(
      width: ListeningLayout.headerButtonSize,
      height: ListeningLayout.headerButtonSize,
      // InkWell 负责点击命中和圆形触摸反馈。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          ListeningLayout.headerButtonSize / 2,
        ),
        // Align 使用父级约束做确定性对齐，不修改坐标也不允许子组件越界。
        child: Align(
          alignment: alignment,
          // Icon 画布固定为 21；更换图标时无需重新计算任何偏移值。
          child: Icon(icon, size: 21, color: color ?? tokens.textMedium),
        ),
      ),
    );
  }
}

///
/// 播放列表工具栏按钮，尺寸必须与搜索框高度一致。
///
class ListeningSmallIconButton extends StatelessWidget {
  ///
  /// 父页面必须提供图标和滚动回调。
  ///
  /// @param  IconData  icon
  /// @param  VoidCallback  onTap
  /// @param  Key?  key
  ///
  const ListeningSmallIconButton({
    required this.icon,
    required this.onTap,
    super.key,
  });

  ///
  /// 按钮内部的 Tabler 图标。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 点击后的滚动操作。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// Flutter 每次绘制工具栏时调用此方法。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前主题颜色。
    final tokens = AppTokens.of(context);
    // 按钮宽高与搜索框统一使用 32 像素。
    return SizedBox(
      width: ListeningLayout.compactControlSize,
      height: ListeningLayout.compactControlSize,
      // InkWell 提供点击反馈。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        // Container 绘制按钮背景边框。
        child: Container(
          decoration: BoxDecoration(
            // 边框颜色跟随主题。
            border: Border.all(color: tokens.inputBorder),
            // 圆角与搜索框一致。
            borderRadius: BorderRadius.circular(6),
          ),
          // 图标由按钮画布自然居中，不使用任何 Transform 或负数位置。
          child: Icon(icon, size: 14, color: tokens.textMedium),
        ),
      ),
    );
  }
}

///
/// “上一个/下一个”文字按钮，图标方向由父级明确指定。
///
class ListeningPlayerMoveButton extends StatelessWidget {
  ///
  /// 默认图标放在文字前；下一个按钮通过 iconAfterLabel 改到文字后。
  ///
  /// @param  IconData  icon
  /// @param  String  label
  /// @param  VoidCallback  onTap
  /// @param  bool  iconAfterLabel
  /// @param  Key?  key
  ///
  const ListeningPlayerMoveButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconAfterLabel = false,
    super.key,
  });

  ///
  /// Tabler 上一个或下一个图标。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 按钮可见文字。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 点击后执行跳词操作。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// false 对应“‹ 上一个”，true 对应“下一个 ›”。
  ///
  /// @var bool
  ///
  final bool iconAfterLabel;

  ///
  /// Flutter 绘制移动按钮时调用 build。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前主题颜色。
    final tokens = AppTokens.of(context);
    // TextButton 负责可访问点击区域和文字按钮反馈。
    return TextButton(
      onPressed: onTap,
      // 两个按钮共享前景色和字号字重。
      style: TextButton.styleFrom(
        foregroundColor: tokens.textMedium,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
      // 手工排列后，下一个按钮的图标可以放到文字右侧。
      child: Row(
        // Row 只占图标和文字所需宽度。
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上一个按钮先显示方向图标。
          if (!iconAfterLabel) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          // 两个按钮共用相同文字样式。
          Text(label),
          // 下一个按钮在文字后显示方向图标。
          if (iconAfterLabel) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 16),
          ],
        ],
      ),
    );
  }
}
