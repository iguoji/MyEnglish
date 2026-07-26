// material.dart 提供 ColorScheme 和 ThemeData，类似小程序 app.wxss 的全局样式能力。
import 'package:flutter/material.dart';

/// 应用级主题配置；页面从 Theme.of(context) 取颜色，才能同时适配 Light 与 Dark。
abstract final class AppTheme {
  /// Tabler 主蓝色，作为按钮、选中项和进度状态的品牌色。
  static const primaryColor = Color(0xFF206BC4);

  /// 浅色页面背景。
  static const backgroundColor = Color(0xFFF5F7FB);

  /// 浅色主要文字。
  static const textColor = Color(0xFF1F2937);

  /// 浅色次要文字。
  static const mutedColor = Color(0xFF65748B);

  /// 浅色普通控件边框。
  static const borderColor = Color(0xFFD9DEE3);

  /// Tabler 浅色表格分隔线，对应 `--tblr-border-color: #e6e7e9`。
  static const tableBorderColor = Color(0xFFE6E7E9);

  /// 深色页面背景；与内容表面保持可识别但克制的层次。
  static const darkBackgroundColor = Color(0xFF15171A);

  /// 深色列表和输入框表面。
  static const darkSurfaceColor = Color(0xFF1D2125);

  /// 深色主要文字。
  static const darkTextColor = Color(0xFFF1F3F5);

  /// 深色次要文字。
  static const darkMutedColor = Color(0xFFA7B0BA);

  /// 深色控件边框。
  static const darkBorderColor = Color(0xFF3A4149);

  /// 深色表格行分隔线。
  static const darkTableBorderColor = Color(0xFF2B3035);

  /// Material 3 浅色色板；copyWith 固定项目需要的 Tabler 中性色。
  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        // seedColor 让 Material 3 自动派生按钮等语义颜色。
        seedColor: primaryColor,
        // 明确生成浅色色板。
        brightness: Brightness.light,
      ).copyWith(
        // 主操作沿用 Tabler 蓝。
        primary: primaryColor,
        // surface 是列表、输入框和底部面板的底色。
        surface: Colors.white,
        // onSurface 是 surface 上的主文字。
        onSurface: textColor,
        // onSurfaceVariant 用于日期、placeholder 等次要信息。
        onSurfaceVariant: mutedColor,
        // outline 用于输入框等普通边框。
        outline: borderColor,
        // outlineVariant 用于表格这类更轻的分隔线。
        outlineVariant: tableBorderColor,
        // 错误和难度统一采用 Tabler 红色。
        error: const Color(0xFFD63939),
      );

  /// Material 3 深色色板；字段含义与浅色完全一致。
  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        // 深色模式仍使用同一个品牌蓝生成语义色。
        seedColor: primaryColor,
        // 明确生成深色色板。
        brightness: Brightness.dark,
      ).copyWith(
        // 深色背景上的蓝色稍微提亮以保持对比度。
        primary: const Color(0xFF6EA8E5),
        // 深色内容表面。
        surface: darkSurfaceColor,
        // 深色主文字。
        onSurface: darkTextColor,
        // 深色次要文字。
        onSurfaceVariant: darkMutedColor,
        // 深色控件边框。
        outline: darkBorderColor,
        // 深色表格分隔线。
        outlineVariant: darkTableBorderColor,
        // 深色背景下使用更亮的红色保证可读性。
        error: const Color(0xFFFF6B6B),
      );

  /// 全局浅色主题；所有页面都继承同一套 Material 3 行为和颜色。
  static final ThemeData light = ThemeData(
    // 正式启用 Material 3；旧代码关闭它只是为了暂时规避默认尺寸变化。
    useMaterial3: true,
    // 注入上面定义的完整浅色色板。
    colorScheme: _lightScheme,
    // 页面外围使用略灰背景，内容列表仍使用白色 surface。
    scaffoldBackgroundColor: backgroundColor,
    // Divider 和自定义列表边线统一读取此颜色。
    dividerColor: tableBorderColor,
    // 不指定 fontFamily，让 Android 根据中英文自动选择系统字体。
    scrollbarTheme: const ScrollbarThemeData(
      // 桌面和移动端始终使用清晰但不过黑的灰蓝滑块。
      thumbColor: WidgetStatePropertyAll(Color(0xFF9AA6B2)),
      // 4 像素便于拖动，同时不会遮住日期。
      thickness: WidgetStatePropertyAll(4),
      // 仅做轻微圆角。
      radius: Radius.circular(2),
    ),
  );

  /// 全局深色主题；组件尺寸与浅色相同，只替换语义颜色。
  static final ThemeData dark = ThemeData(
    // 深色同样使用 Material 3，避免两种主题组件行为不一致。
    useMaterial3: true,
    // 注入深色色板。
    colorScheme: _darkScheme,
    // 页面外围使用比列表更深的背景。
    scaffoldBackgroundColor: darkBackgroundColor,
    // 深色列表分隔线。
    dividerColor: darkTableBorderColor,
    // 深色滚动条稍亮，保证真机上容易找到并拖动。
    scrollbarTheme: const ScrollbarThemeData(
      // 半亮灰色不会像纯白一样抢眼。
      thumbColor: WidgetStatePropertyAll(Color(0xFF7B8794)),
      // 与浅色保持相同可拖动宽度。
      thickness: WidgetStatePropertyAll(4),
      // 与浅色保持相同圆角。
      radius: Radius.circular(2),
    ),
  );
}
