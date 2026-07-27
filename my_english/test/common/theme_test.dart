// flutter_test 提供普通 test 和 expect 断言。
import 'package:flutter_test/flutter_test.dart';
// material.dart 提供 Colors、NoSplash 和 WidgetState，检查文字按钮交互样式。
import 'package:flutter/material.dart';
// 引入项目 Material 3 双主题。
import 'package:my_english/common/theme.dart';

/// 验证 Material 3 与 Light/Dark 基础配置。
void main() {
  // 两种主题都必须使用 Material 3，不能出现组件行为不一致。
  test('both app themes use Material 3', () {
    // 浅色主题开启 Material 3。
    expect(AppTheme.light.useMaterial3, isTrue);
    // 深色主题也开启 Material 3。
    expect(AppTheme.dark.useMaterial3, isTrue);
    // 两种主题亮度正确。
    expect(AppTheme.light.brightness.name, 'light');
    expect(AppTheme.dark.brightness.name, 'dark');
    // 浅色 Tabler 分隔线保持需求中的 #E6E7E9。
    expect(AppTheme.light.dividerColor, AppTheme.tableBorderColor);
    // 深色使用独立分隔线，不能继续显示刺眼浅灰。
    expect(AppTheme.dark.dividerColor, AppTheme.darkTableBorderColor);
  });

  // 全局 TextButton（如重新加载、设置完成）按下时不能出现 Material 默认背景。
  test('text buttons never paint a pressed background', () {
    // 逐一验证浅色与深色主题，避免切换主题后问题重新出现。
    for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      // 取得全局 TextButton 样式。
      final style = theme.textButtonTheme.style!;
      // 按下状态解析后必须仍为完全透明。
      expect(
        style.overlayColor!.resolve(const <WidgetState>{WidgetState.pressed}),
        Colors.transparent,
      );
      // 水波纹工厂必须使用 NoSplash，不能在文字后方扩散色块。
      expect(style.splashFactory, NoSplash.splashFactory);
    }
  });
}
