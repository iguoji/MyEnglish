// services.dart 提供 MethodChannel 与测试消息编码。
import 'package:flutter/services.dart';
// flutter_test 提供测试绑定、mock 通道和断言。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的全局设置 Store。
import 'package:my_english/store/settings.dart';

/// 验证设置启动读取、默认值和后续原生持久化调用。
void main() {
  // 初始化 Flutter 二进制消息测试环境。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 每个测试使用独立通道名，避免与其他测试互相影响。
  const channel = MethodChannel('test/settings');

  // 测试结束后清除 mock handler。
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 原生已保存值必须在 Store 创建时读取并映射成枚举。
  test('loads persisted values and writes later changes', () async {
    // 记录 Dart 发给原生的方法和参数。
    final calls = <MethodCall>[];
    // 注册假 Android SharedPreferences 通道。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // 保存每次调用。
          calls.add(call);
          // 启动读取返回英式和 Dark。
          if (call.method == 'getSettings') {
            return <String, Object?>{'accent': 'british', 'theme': 'dark'};
          }
          // setter 使用 null 表示保存成功。
          return null;
        });

    // 通过假通道加载 Store。
    final settings = await SettingsStore.load(channel: channel);
    // 启动值正确应用。
    expect(settings.accent, PronunciationAccent.british);
    expect(settings.theme, AppThemePreference.dark);
    // 修改回美式和 Light。
    await settings.setAccent(PronunciationAccent.american);
    await settings.setTheme(AppThemePreference.light);
    // MethodCall 未实现相等运算符，必须使用 flutter_test 的 isMethodCall 匹配器。
    expect(calls[1], isMethodCall('setAccent', arguments: 'american'));
    expect(calls[2], isMethodCall('setTheme', arguments: 'light'));
    // Store 内存同步更新。
    expect(settings.accent, PronunciationAccent.american);
    expect(settings.theme, AppThemePreference.light);
    // 释放 ChangeNotifier。
    settings.dispose();
  });

  // 未知或空存储值必须安全回退产品默认值。
  test('unknown stored values fall back to american and light', () async {
    // 返回旧版本可能留下的未知字符串。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, Object?>{
            'accent': 'unknown',
            'theme': 'system',
          },
        );

    // 加载 Store。
    final settings = await SettingsStore.load(channel: channel);
    // 产品默认口音是美式。
    expect(settings.accent, PronunciationAccent.american);
    // 产品默认主题是 Light，不跟随系统。
    expect(settings.theme, AppThemePreference.light);
    // 释放资源。
    settings.dispose();
  });

  // 每日复习目标当前为内存设置：默认 100，负数钳制为 0。
  test('daily goal defaults to 100 and never goes negative', () {
    // 纯内存 Store 即可验证。
    final settings = SettingsStore.inMemory();
    // 产品默认目标为 100。
    expect(settings.dailyGoal, 100);
    // 正常步进 +5。
    settings.setDailyGoal(105);
    expect(settings.dailyGoal, 105);
    // 负数一律钳制为 0。
    settings.setDailyGoal(-5);
    expect(settings.dailyGoal, 0);
    // 释放资源。
    settings.dispose();
  });

  // Hot Restart 使用旧原生 APK 时没有新通道，App 仍应使用内存默认值正常启动。
  test('missing native channel falls back to in-memory settings', () async {
    // 不注册 mock handler 等价于原生端没有实现 getSettings。
    final settings = await SettingsStore.load(channel: channel);
    // 启动继续使用产品默认值。
    expect(settings.accent, PronunciationAccent.american);
    expect(settings.theme, AppThemePreference.light);
    // channel 已被禁用，后续修改只更新内存且不会再次抛 MissingPluginException。
    await settings.setTheme(AppThemePreference.dark);
    // 当前进程内修改仍然立即生效。
    expect(settings.theme, AppThemePreference.dark);
    // 释放资源。
    settings.dispose();
  });
}
