// flutter_test 提供普通 test 和 expect 断言。
import 'package:flutter_test/flutter_test.dart';
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
}
