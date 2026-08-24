// material.dart 提供 WidgetsFlutterBinding 和 runApp，是应用的启动入口。
import 'package:flutter/material.dart';

// 引入应用根组件。
import 'app.dart';
// 引入全局设置 Store；启动时要先从 Android 本地存储读取它。
import 'store/settings.dart';

///
/// Dart 程序固定从 main 函数开始执行，这里负责应用启动前的全部准备工作。
Future<void> main() async {
  // 在调用原生 SharedPreferences 前初始化 Flutter 与 Android 的消息通道。
  WidgetsFlutterBinding.ensureInitialized();
  // 等待本地设置读取完成，避免先闪一次 Light 再突然切换 Dark。
  final settings = await SettingsStore.load();
  // 应用不附带默认词库；runApp 直接进入首页，用户可手动添加或导入自己的数据。
  runApp(MainApp(settings: settings));
}
