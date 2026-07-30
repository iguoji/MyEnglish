// material.dart 提供 ColorScheme 和 ThemeData，类似小程序 app.wxss 的全局样式能力。
import 'package:flutter/material.dart';

/// 应用级主题配置；页面从 Theme.of(context) 取颜色，才能同时适配 Light 与 Dark。
abstract final class AppTheme {
  /// Tabler 主蓝色，作为按钮、选中项和进度状态的品牌色。
  static const primaryColor = Color(0xFF206BC4);

  /// 浅色页面背景（设计稿 cPage）。
  static const backgroundColor = Color(0xFFF6F8FB);

  /// 浅色主要文字（设计稿 cTx）。
  static const textColor = Color(0xFF182433);

  /// 浅色次要文字（设计稿 cTs）。
  static const mutedColor = Color(0xFF667382);

  /// 浅色输入框等控件边框（设计稿 cIb）。
  static const borderColor = Color(0xFFDCE1E7);

  /// Tabler 浅色表格分隔线，对应 `--tblr-border-color: #e6e7e9`。
  static const tableBorderColor = Color(0xFFE6E7E9);

  /// 深色页面背景（设计稿 cPage）。
  static const darkBackgroundColor = Color(0xFF141A22);

  /// 深色列表和输入框表面（设计稿 cCard）。
  static const darkSurfaceColor = Color(0xFF1B232E);

  /// 深色主要文字（设计稿 cTx）。
  static const darkTextColor = Color(0xFFE6EBF1);

  /// 深色次要文字（设计稿 cTs）。
  static const darkMutedColor = Color(0xFF93A0AF);

  /// 深色输入框等控件边框（设计稿 cIb）。
  static const darkBorderColor = Color(0xFF364250);

  /// 深色分组与列表分隔线（设计稿 cBd）。
  static const darkTableBorderColor = Color(0xFF2B3644);

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
    // 纯文字 TextButton 只改变文字本身，不在按下时出现灰色或蓝色背景块。
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(
        // pressed、hovered、focused 等状态都保持透明覆盖层。
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        // 同时关闭水波纹，避免透明覆盖层之外仍出现扩散动画。
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    // 轻提示 SnackBar：浅色界面下用深底浅字。
    // 注意 Material 3 默认 inverseSurface 在深色色板下偏白，这里显式覆盖，
    // 否则任何 SnackBar 在暗色模式都会变成刺眼的白条。
    snackBarTheme: SnackBarThemeData(
      // 复用浅色主文字色作为深色底，保证对比度。
      backgroundColor: AppTheme.textColor,
      // 提示文字白色，字号与设计稿吐司一致。
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
      // 操作按钮（若有）使用品牌蓝。
      actionTextColor: AppTheme.primaryColor,
    ),
    // Tooltip 同样指定深色底浅字，规避 Material 3 默认在深色 scheme 下的浅白底。
    tooltipTheme: const TooltipThemeData(
      // 圆角气泡，深色底。
      decoration: BoxDecoration(
        color: AppTheme.textColor,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      // 气泡内文字白色。
      textStyle: TextStyle(color: Colors.white, fontSize: 12),
    ),
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
    // 深色模式与浅色模式保持一致：纯文字按钮按下时不增加背景色。
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(
        // 所有交互状态都使用透明覆盖层。
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        // 禁用 Material 默认水波纹。
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    // 轻提示 SnackBar：深色界面下用深色底浅字。
    // 与浅色主题同理，必须显式覆盖 Material 3 默认 inverseSurface 浅白底。
    snackBarTheme: SnackBarThemeData(
      // 比深色 surface 略亮的深色底，仍保持黑底形态。
      backgroundColor: AppTheme.darkTableBorderColor,
      // 提示文字重用深色主文字色。
      contentTextStyle: const TextStyle(color: AppTheme.darkTextColor, fontSize: 13.5),
      // 操作按钮使用深色 scheme 提亮后的品牌蓝。
      actionTextColor: const Color(0xFF6EA8E5),
    ),
    // Tooltip 同样指定深色底浅字。
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppTheme.darkTableBorderColor,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: AppTheme.darkTextColor, fontSize: 12),
    ),
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

/// 设计稿色板的完整令牌集合，命名与设计稿 CSS 变量一一对应。
///
/// 页面通过 AppTokens.of(context) 取当前明暗对应的一组颜色，
/// 作用类似小程序在 WXSS 里读取一组主题 CSS 变量。
class AppTokens {
  /// 私有构造器；只允许使用下方两个预设实例。
  const AppTokens._({
    required this.page,
    required this.card,
    required this.sub,
    required this.expand,
    required this.border,
    required this.rowBorder,
    required this.text,
    required this.textSecondary,
    required this.textMedium,
    required this.inputBorder,
    required this.muted,
    required this.check,
    required this.listDate,
    required this.listDateEmpty,
  });

  /// 页面背景（cPage）。
  final Color page;

  /// 卡片与列表表面（cCard）。
  final Color card;

  /// 次级底色，如分组头与开关轨道（cSub）。
  final Color sub;

  /// 展开释义区域底色（cExp）。
  final Color expand;

  /// 分组与区域分隔线（cBd）。
  final Color border;

  /// 列表行分隔线（cRb）。
  final Color rowBorder;

  /// 主要文字（cTx）。
  final Color text;

  /// 次要文字（cTs）。
  final Color textSecondary;

  /// 中等强调文字（cTm）。
  final Color textMedium;

  /// 输入框与按钮边框（cIb）。
  final Color inputBorder;

  /// 弱化文字，如计数与占位（cMut）。
  final Color muted;

  /// 未选中复选框边框与开关轨道（chk）。
  final Color check;

  /// 列表右侧日期的极淡灰：刻意比 textSecondary 更弱，让辅助信息不抢眼。
  final Color listDate;

  /// 列表右侧无日期占位"00.00"的更淡灰：比 listDate 还弱，进一步降低存在感。
  final Color listDateEmpty;

  /// 品牌主色，与设计稿 accent 一致。
  static const Color accent = AppTheme.primaryColor;

  /// 危险色，用于删除与难度徽章。
  static const Color danger = Color(0xFFD63939);

  /// 浅色令牌，与设计稿浅色 CSS 变量一致。
  static const AppTokens light = AppTokens._(
    page: AppTheme.backgroundColor,
    card: Color(0xFFFFFFFF),
    sub: Color(0xFFF1F4F7),
    expand: Color(0xFFF8FAFC),
    border: AppTheme.tableBorderColor,
    rowBorder: Color(0xFFEEF0F3),
    text: AppTheme.textColor,
    textSecondary: AppTheme.mutedColor,
    textMedium: Color(0xFF3F4A58),
    inputBorder: AppTheme.borderColor,
    muted: Color(0xFF9AA3AF),
    check: Color(0xFFC6CCD3),
    // 比 muted(0xFF9AA3AF) 更浅，确保日期在白色卡片上几乎只是淡淡的水印感。
    listDate: Color(0xFF7E868F),
    // 无日期占位"00.00"比有日期更淡，接近背景几乎不可见。
    listDateEmpty: Color(0xFFE0E4E9),
  );

  /// 深色令牌，与设计稿深色 CSS 变量一致。
  static const AppTokens dark = AppTokens._(
    page: AppTheme.darkBackgroundColor,
    card: AppTheme.darkSurfaceColor,
    sub: Color(0xFF212B37),
    expand: Color(0xFF1F2833),
    border: AppTheme.darkTableBorderColor,
    rowBorder: Color(0xFF26303C),
    text: AppTheme.darkTextColor,
    textSecondary: AppTheme.darkMutedColor,
    textMedium: Color(0xFFC3CCD6),
    inputBorder: AppTheme.darkBorderColor,
    muted: Color(0xFF71808F),
    check: Color(0xFF4A5866),
    // 深色表面(#1B232E)上比 muted(0xFF71808F) 更暗，弱化到几乎不干扰正文。
    listDate: Color(0xFF98A4B2),
    // 无日期占位"00.00"比有日期更暗，融入深色背景几乎不可见。
    listDateEmpty: Color(0xFF3A4350),
  );

  /// 按当前主题亮度返回对应令牌集合。
  static AppTokens of(BuildContext context) {
    // 深色主题返回深色令牌，其余返回浅色令牌。
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}
