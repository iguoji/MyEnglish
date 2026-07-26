// material.dart 提供 MaterialApp 和 SizedBox。
import 'package:flutter/material.dart';
// flutter_test 提供根组件 Widget 测试。
import 'package:flutter_test/flutter_test.dart';
// 引入应用根组件。
import 'package:my_english/app.dart';
// 引入可切换的内存设置 Store。
import 'package:my_english/store/settings.dart';

/// 验证根应用读取 Store 并立即应用 Material 3 主题。
void main() {
  // 主题切换后 MaterialApp 必须使用同一个设置状态。
  testWidgets('main app applies persisted light and dark preferences', (
    tester,
  ) async {
    // 模拟启动阶段已读取到默认 Light。
    final settings = SettingsStore.inMemory();
    // 渲染应用根组件。
    await tester.pumpWidget(MainApp(settings: settings));
    // 读取当前 MaterialApp 配置。
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    // 启动使用 Light。
    expect(app.themeMode, ThemeMode.light);
    // Light 主题开启 Material 3。
    expect(app.theme?.useMaterial3, isTrue);
    // Dark 主题也已经完整提供。
    expect(app.darkTheme?.useMaterial3, isTrue);

    // 模拟设置面板成功持久化 Dark。
    await settings.setTheme(AppThemePreference.dark);
    // 处理 ChangeNotifier 触发的根组件重建。
    await tester.pump();
    // 重新读取 MaterialApp。
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    // 当前模式立即变为 Dark。
    expect(app.themeMode, ThemeMode.dark);

    // 卸载首页以释放时钟 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
    // 根组件不再使用 Store 后释放它。
    settings.dispose();
  });
}
