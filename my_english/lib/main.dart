// material.dart 提供 WidgetsFlutterBinding 和 runApp，是应用的启动入口。
import 'package:flutter/material.dart';
// dart:ui 提供 PlatformDispatcher：挂 Dart 层未捕获异常回调时要用它。
import 'dart:ui';

// 引入应用根组件。
import 'app.dart';
// 引入全局设置 Store；启动时要先从 Android 本地存储读取它。
import 'store/settings.dart';
// 引入 Dart 侧日志入口：未捕获异常与关键事件会写进单日运行日志。
import 'services/app_log.dart';

///
/// Dart 程序固定从 main 函数开始执行，这里负责应用启动前的全部准备工作。
Future<void> main() async {
  // 在调用原生 SharedPreferences 前初始化 Flutter 与 Android 的消息通道。
  WidgetsFlutterBinding.ensureInitialized();
  // 打开日志开关；此后 AppLog 的调用才会真正转发给原生单文件日志。
  AppLog.enable();
  // 挂全局兜底：Flutter 构建/布局异常没被页面接住时，先写日志再走默认提示。
  FlutterError.onError = (FlutterErrorDetails details) {
    // 记录异常正文（含发生位置的上下文描述）。
    AppLog.e('flutter', details.exceptionAsString());
    // 保留 Flutter 默认的调试台输出行为，不影响开发期排查。
    FlutterError.presentError(details);
  };
  // 挂 Dart 层兜底：未捕获的异步异常同样写日志，返回 false 保留默认提示。
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLog.e('dart', '$error\n$stack');
    return false;
  };
  // 等待本地设置读取完成，避免先闪一次 Light 再突然切换 Dark。
  final settings = await SettingsStore.load();
  // 应用不附带默认词库；runApp 直接进入首页，用户可手动添加或导入自己的数据。
  runApp(MainApp(settings: settings));
}
