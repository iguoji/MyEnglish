// material.dart 提供 MaterialApp 和 StatelessWidget 等应用级组件。
import 'package:flutter/material.dart';

// 引入应用元信息（版本号、展示名来自 pubspec.yaml）。
import 'common/app_info.dart';
// 引入全局主题配置。
import 'common/theme.dart';
// 引入首页，作为应用启动后的第一个页面。
import 'pages/home/home.dart';
// 引入全局设置 Store，MaterialApp 会监听其中的主题变化。
import 'store/settings.dart';

///
/// 应用根组件；它负责全局配置，不处理首页内部业务。
///
class MainApp extends StatelessWidget {
  ///
  /// App 启动前必须传入已经读取本地数据的设置 Store。
  const MainApp({required this.settings, super.key});

  ///
  /// 口音与主题都由同一个全局 Store 管理。
  final SettingsStore settings;

  ///
  /// build 相当于输出应用最外层模板。
  @override
  Widget build(BuildContext context) {
    // ListenableBuilder 监听 settings，只有设置变化时才重建 MaterialApp。
    return ListenableBuilder(
      // SettingsStore 每次成功修改口音或主题都会发出通知。
      listenable: settings,
      // builder 根据最新主题输出应用根节点。
      builder: (context, child) {
        // MaterialApp 管理主题、页面导航和应用标题。
        return MaterialApp(
          // title 是系统任务列表等位置可能使用的应用名称，
          // 单一数据源是 pubspec.yaml 的 name 字段。
          title: AppInfo.displayName,
          // 关闭右上角 DEBUG 横幅；只影响显示，不影响调试能力。
          debugShowCheckedModeBanner: false,
          // 浅色完整使用 Material 3 配置。
          theme: AppTheme.light,
          // 深色完整使用 Material 3 配置。
          darkTheme: AppTheme.dark,
          // 从已持久化设置决定当前显示哪一种主题。
          themeMode: settings.themeMode,
          // builder 包在每一个页面的最外层，这里挂全站文字放大器。
          //
          // 「老年版」就是靠这一处实现的：不改任何页面、不改字号表里的任何数值，
          // 只在最外层声明「本 App 的文字统一按 x 倍显示」，所有文字连带行高、
          // 按钮内边距一起等比变大。
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(_textScale(context))),
            // home 已经给了 MaterialApp，child 不会为空；兜一个空盒子只为类型安全。
            child: child ?? const SizedBox.shrink(),
          ),
          // 首页和未来页面共享同一个设置对象。
          home: HomePage(settings: settings),
        );
      },
    );
  }

  ///
  /// 算出最终的文字放大倍数：手机系统的档位 × App 内的档位，并统一封顶。
  ///
  /// 为什么要把两者相乘，而不是直接用 App 内的档位覆盖掉系统设置：有些用户
  /// 已经在手机「显示与亮度」里把全局字体调大了，那是他对所有 App 的要求，
  /// 直接覆盖等于把这个要求撕掉，本 App 反而变成手机里字最小的那个。
  ///
  /// 为什么又必须封顶：两个倍数会叠乘。系统调到 1.3、App 里再选「特大」1.3，
  /// 总倍数就是 1.69——那是从来没测过的档位，候选按钮和顶栏会开始裁字。
  /// 所以最终倍数一律不超过「特大」这一档，也就是做过耐压测试的上限。
  ///
  /// 下限取 1.0 是同样的道理：字号表里最小的一档（[AppFont.fs6]）也只有 12 像素，
  /// 再按系统设置往下缩就没法读了。
  double _textScale(BuildContext context) {
    // 系统缩放器只提供「把某个字号缩放成多少」，不直接给倍数；
    // 那就拿正文档去问一次，再除回来，得到的商就是系统当前的倍数。
    final systemFactor =
        MediaQuery.textScalerOf(context).scale(AppFont.fs5) / AppFont.fs5;
    return (systemFactor * settings.fontScale.multiplier).clamp(
      1.0,
      AppFontScale.huge.multiplier,
    );
  }
}
