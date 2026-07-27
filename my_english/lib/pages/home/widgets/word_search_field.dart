// 引入 Flutter Material 组件，类似小程序页面使用 input 和 icon 的基础组件库。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供统一的搜索图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

/// 首页搜索框；组件本身不保存关键词，只把输入变化通知给父页面。
class WordSearchField extends StatelessWidget {
  /// required 表示调用方必须传 onChanged，类似 PHP 方法中的必填参数。
  const WordSearchField({required this.onChanged, super.key});

  /// `ValueChanged<String>` 表示接收字符串但不返回结果的回调，类似小程序 bindinput。
  final ValueChanged<String> onChanged;

  /// Flutter 每次需要绘制本组件时都会调用 build。
  @override
  Widget build(BuildContext context) {
    // 读取当前 Light/Dark 的完整 Material 3 色板。
    final colorScheme = Theme.of(context).colorScheme;
    // SizedBox 明确限定输入框高度，类似给小程序 input 设置 height: 40px。
    return SizedBox(
      // Flutter 使用逻辑像素；这里按需求固定为 40。
      height: 40,
      // DecoratedBox 只负责背景、边框和圆角，类似一个带 WXSS 的外层 view。
      child: DecoratedBox(
        // decoration 对应 CSS/WXSS 的视觉样式集合。
        decoration: BoxDecoration(
          // 输入框使用当前主题 surface。
          color: colorScheme.surface,
          // 四周使用 Tabler 风格的一像素浅色边框。
          border: Border.all(color: colorScheme.outline),
          // 8 像素圆角与设计稿输入框一致。
          borderRadius: BorderRadius.circular(8),
        ),
        // TextField 对应小程序 input；输入值变化时会调用 onChanged。
        child: TextField(
          // 把用户输入原样交给父页面，父页面再负责搜索状态和过滤逻辑。
          onChanged: onChanged,
          // 明确指定文字垂直居中，解决默认基线造成的视觉偏移。
          textAlignVertical: TextAlignVertical.center,
          // style 是用户实际输入文字的样式，不是 placeholder 的样式。
          style: TextStyle(
            // 输入内容使用主要文字颜色。
            color: colorScheme.onSurface,
            // 与 placeholder 保持相同字号，切换时不会跳动。
            fontSize: 14,
            // 1.2 行高让中文字形在 44 高输入框内视觉居中。
            height: 1.2,
          ),
          // InputDecoration 对应小程序 input 的 placeholder、前置图标和内部间距配置。
          decoration: InputDecoration(
            // isDense 移除 Material 输入框额外的默认垂直留白。
            isDense: true,
            // 搜索框为空时显示的提示文字。
            hintText: '搜索单词',
            // placeholder 单独设置相同字号和行高，确保与输入文字位置一致。
            hintStyle: TextStyle(
              // 提示文字使用弱化颜色。
              color: colorScheme.onSurfaceVariant,
              // 提示文字字号为 14。
              fontSize: 14,
              // 与输入文字使用相同的 1.2 行高。
              height: 1.2,
            ),
            // prefixIcon 相当于小程序 input 左侧放置一个 icon 节点。
            prefixIcon: Icon(
              // 使用 Flutter 自带的搜索图标。
              TablerIcons.search,
              // 图标颜色与 placeholder 保持一致。
              color: colorScheme.onSurfaceVariant,
              // 设计稿使用更轻量的小图标，这里取 20 兼顾清晰度。
              size: 20,
            ),
            // 将图标区域固定为 40×40，让图标在输入框内严格居中。
            prefixIconConstraints: const BoxConstraints(
              // 图标占位的最小宽度。
              minWidth: 40,
              // 图标占位的最小高度与输入框一致。
              minHeight: 40,
            ),
            // 外层 DecoratedBox 已经画了边框，所以关闭 TextField 自带边框。
            border: InputBorder.none,
            // 清除默认内边距，由固定高度和 textAlignVertical 共同控制居中。
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
