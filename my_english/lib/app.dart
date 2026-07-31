// material.dart 提供 MaterialApp 和 StatelessWidget 等应用级组件。
import 'package:flutter/material.dart';

// 引入全局主题，类似 PHP 模板加载公共 CSS 或小程序加载 app.wxss。
import 'common/theme.dart';
// 引入首页，类似在小程序 app.json 中把首页登记为第一个页面。
import 'pages/home/home.dart';
// 引入全局设置 Store，MaterialApp 会监听其中的主题变化。
import 'store/settings.dart';

/// 全局 ScaffoldMessenger Key，让 SnackBar 挂在根级 Scaffold 之上，
/// 不被 Drawer/BottomSheet 等高 zIndex 层级遮挡。
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 应用根组件；它负责全局配置，不处理首页内部业务。
class MainApp extends StatelessWidget {
  /// App 启动前必须传入已经读取本地数据的设置 Store。
  const MainApp({required this.settings, super.key});

  /// 口音与主题都由同一个全局 Store 管理。
  final SettingsStore settings;

  /// build 相当于输出应用最外层模板。
  @override
  Widget build(BuildContext context) {
    // ListenableBuilder 类似监听小程序全局 data，只有设置变化时才重建 MaterialApp。
    return ListenableBuilder(
      // SettingsStore 每次成功修改口音或主题都会发出通知。
      listenable: settings,
      // builder 根据最新主题输出应用根节点。
      builder: (context, child) {
        // MaterialApp 管理主题、页面导航和应用标题。
        return MaterialApp(
          // title 是系统任务列表等位置可能使用的应用名称。
          title: 'My English',
          // 关闭右上角 DEBUG 横幅；只影响显示，不影响调试能力。
          debugShowCheckedModeBanner: false,
          // 注入全局 ScaffoldMessenger Key，让 SnackBar 在最顶层显示。
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          // 浅色完整使用 Material 3 配置。
          theme: AppTheme.light,
          // 深色完整使用 Material 3 配置。
          darkTheme: AppTheme.dark,
          // 从已持久化设置决定当前显示哪一种主题。
          themeMode: settings.themeMode,
          // 首页和未来页面共享同一个设置对象。
          home: HomePage(settings: settings),
        );
      },
    );
  }
}
