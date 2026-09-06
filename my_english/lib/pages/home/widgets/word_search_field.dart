// 引入 Flutter Material 组件，提供输入框和图标等基础组件。
import 'package:flutter/material.dart';

// 设计令牌：圆角台阶。
import '../../../common/theme.dart';

// 首页专属尺寸表：本组件的宽高从这里取名字，数值继承设计令牌总表。
import 'home_layout.dart';

///
/// 首页搜索框；组件本身不保存关键词，只把输入变化通知给父页面。
///
class WordSearchField extends StatelessWidget {
  ///
  /// required 表示调用方必须传 onChanged，不可省略。
  const WordSearchField({required this.onChanged, super.key});

  ///
  /// `ValueChanged<String>` 表示接收字符串但不返回结果的回调。
  final ValueChanged<String> onChanged;

  ///
  /// Flutter 每次需要绘制本组件时都会调用 build。
  @override
  Widget build(BuildContext context) {
    // 读取当前 Light/Dark 的项目颜色令牌。
    //
    // 这里刻意不读 Material 的 `colorScheme`：全站颜色只有 [AppTokens] 一个出处，
    // 同一种「输入框底色」不该有两个名字可以取。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // SizedBox 明确限定输入框高度为 40 逻辑像素。
    return SizedBox(
      // Flutter 使用逻辑像素；这里按需求固定为 40。
      height: WordSearchFieldLayout.fieldHeight,
      // DecoratedBox 只负责背景、边框和圆角这层视觉样式。
      child: DecoratedBox(
        // decoration 定义这层容器的视觉样式集合。
        decoration: BoxDecoration(
          // 输入框与卡片同底色。
          color: tokens.card,
          // 四周使用 Tabler 风格的一像素浅色边框。
          border: Border.all(color: tokens.inputBorder),
          // 8 像素圆角与设计稿输入框一致。
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        // TextField 是实际的输入控件；输入值变化时会调用 onChanged。
        child: TextField(
          // 把用户输入原样交给父页面，父页面再负责搜索状态和过滤逻辑。
          onChanged: onChanged,
          // 明确指定文字垂直居中，解决默认基线造成的视觉偏移。
          textAlignVertical: TextAlignVertical.center,
          // style 是用户实际输入文字的样式，不是 placeholder 的样式。
          // 颜色不必写——正文那一档自带主文字色。
          style: textTheme.fs5.copyWith(
            // 行距收到 `lh-sm` 那一档：输入框写死了高度，
            // 中文字形上下留白少，行距收紧才视觉居中。
            height: AppLine.lhSm,
          ),
          // InputDecoration 负责 placeholder、前置图标和内部间距配置。
          decoration: InputDecoration(
            // isDense 移除 Material 输入框额外的默认垂直留白。
            isDense: true,
            // 搜索框为空时显示的提示文字。
            hintText: '搜索单词',
            // placeholder 单独设置相同字号和行高，确保与输入文字位置一致。
            // 提示文字与输入文字读同一档，切换时不会跳动。
            hintStyle: textTheme.fs5.copyWith(
              // 提示文字读「弱化文字/占位」那一档，与添加单词表单里的
              // 含义输入框取同一个颜色——同一种 placeholder 不该有两种灰。
              color: tokens.muted,
              // 与输入文字读同一档行距，敲字前后不抖动。
              height: AppLine.lhSm,
            ),
            // prefixIcon 在输入框左侧放置一个图标。
            prefixIcon: Icon(
              // 使用 Flutter 自带的搜索图标。
              AppGlyph.search,
              // 图标颜色与 placeholder 保持一致。
              color: tokens.muted,
              // 设计稿使用更轻量的小图标，这里取顶栏那一档兼顾清晰度。
              size: AppIcon.i20,
            ),
            // 将图标区域固定为 40×40，让图标在输入框内严格居中。
            prefixIconConstraints: const BoxConstraints(
              // 图标占位的最小宽度。
              minWidth: WordSearchFieldLayout.iconBoxSize,
              // 图标占位的最小高度与输入框一致。
              minHeight: WordSearchFieldLayout.iconBoxSize,
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
