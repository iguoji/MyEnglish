// material.dart 提供 WidgetsFlutterBinding 和 runApp，作用类似小程序启动框架。
import 'package:flutter/material.dart';

// 引入应用根组件，作用类似 PHP 入口 require App，或小程序加载 app 配置。
import 'app.dart';
// 引入全局设置 Store；启动时要先从 Android 本地存储读取它。
import 'store/settings.dart';
// default_vocabulary.dart 提供首次安装时的离线词库初始化流程。
import 'services/default_vocabulary.dart';
// word.dart 提供 Android SQLite Store 实现。
import 'store/word.dart';

///
/// Dart 程序固定从 main 函数开始执行，对应 PHP 请求进入 index.php 的第一行。
///
/// @return `Future<void>`
///
Future<void> main() async {
  // 在调用原生 SharedPreferences 前初始化 Flutter 与 Android 的消息通道。
  WidgetsFlutterBinding.ensureInitialized();
  // 等待本地设置读取完成，避免先闪一次 Light 再突然切换 Dark。
  final settings = await SettingsStore.load();
  // 在首页创建前先导入内置词库，避免首屏先显示空列表。
  try {
    await DefaultVocabularyService.initialize(store: LocalWordStore.instance);
  } catch (error, stackTrace) {
    // 初始化失败不阻止用户进入 App；首页仍可使用手动导入功能。
    debugPrint('内置词库初始化失败：$error');
    debugPrintStack(stackTrace: stackTrace);
  }
  // runApp 把 MainApp 挂到屏幕，并把已经读取好的设置传给全局应用。
  runApp(MainApp(settings: settings));
}
