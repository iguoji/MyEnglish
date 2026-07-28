// material.dart 提供 ChangeNotifier 和 ThemeMode，管理全局设置通知与主题模式。
import 'package:flutter/material.dart';
// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SharedPreferences。
import 'package:flutter/services.dart';

/// 单词发音口音；枚举比到处传递字符串更不容易写错。
enum PronunciationAccent {
  /// 美式发音，也是第一次安装时的默认值。
  american,

  /// 英式发音。
  british,
}

/// 为口音枚举补充原生存储值和界面文字。
extension PronunciationAccentDetails on PronunciationAccent {
  /// Android SharedPreferences 中保存的稳定字符串。
  String get storageValue => switch (this) {
    PronunciationAccent.american => 'american',
    PronunciationAccent.british => 'british',
  };

  /// 设置面板显示的简短名称。
  String get label => switch (this) {
    PronunciationAccent.american => '美式',
    PronunciationAccent.british => '英式',
  };
}

/// 中文释义之间使用的全角分隔符。
enum DefinitionSeparator {
  /// 中文顿号，也是首次安装和旧版本升级后的默认值。
  ideographicComma,

  /// 中文全角逗号。
  fullWidthComma,

  /// 中文全角分号。
  fullWidthSemicolon,
}

/// 为释义分隔符补充持久化值与真正显示的全角符号。
extension DefinitionSeparatorDetails on DefinitionSeparator {
  /// Android SharedPreferences 保存英文稳定值，避免标点编码差异影响迁移。
  String get storageValue => switch (this) {
    DefinitionSeparator.ideographicComma => 'ideographic_comma',
    DefinitionSeparator.fullWidthComma => 'full_width_comma',
    DefinitionSeparator.fullWidthSemicolon => 'full_width_semicolon',
  };

  /// App 拼接中文释义时真正使用的全角标点。
  String get symbol => switch (this) {
    DefinitionSeparator.ideographicComma => '、',
    DefinitionSeparator.fullWidthComma => '，',
    DefinitionSeparator.fullWidthSemicolon => '；',
  };
}

/// 用户选择的主题；当前只允许需求中明确给出的 Light 与 Dark。
enum AppThemePreference {
  /// 浅色主题，也是第一次安装时的默认值。
  light,

  /// 深色主题。
  dark,
}

/// 为主题枚举补充持久化值、界面文字和 Flutter ThemeMode。
extension AppThemePreferenceDetails on AppThemePreference {
  /// Android SharedPreferences 中使用的稳定字符串。
  String get storageValue => switch (this) {
    AppThemePreference.light => 'light',
    AppThemePreference.dark => 'dark',
  };

  /// 设置面板显示的名称。
  String get label => switch (this) {
    AppThemePreference.light => 'Light',
    AppThemePreference.dark => 'Dark',
  };

  /// MaterialApp 真正需要的主题模式。
  ThemeMode get themeMode => switch (this) {
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}

/// 全局设置 Store，类似小程序的全局状态加 wx.setStorageSync。
class SettingsStore extends ChangeNotifier {
  /// 私有构造器确保生产环境必须先通过 load 读取原生持久化值。
  SettingsStore._({
    required this._channel,
    required this._accent,
    required this._theme,
    required this._definitionSeparator,
  });

  /// 原生通道名必须与 MainActivity 注册值保持一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/settings',
  );

  /// null 表示测试使用纯内存模式，不访问 Android。
  final MethodChannel? _channel;

  /// 当前口音设置；下划线字段只允许通过 setAccent 修改。
  PronunciationAccent _accent;

  /// 当前主题设置；下划线字段只允许通过 setTheme 修改。
  AppThemePreference _theme;

  /// 当前中文释义分隔符；下划线字段只允许通过 setDefinitionSeparator 修改。
  DefinitionSeparator _definitionSeparator;

  /// App 启动时调用：先读取 SharedPreferences，再创建可供页面监听的 Store。
  static Future<SettingsStore> load({
    MethodChannel channel = _defaultChannel,
  }) async {
    try {
      // invokeMapMethod 类似请求原生 Controller 返回一个设置关联数组。
      final values = await channel.invokeMapMethod<String, Object?>(
        'getSettings',
      );
      // 未保存或未知口音一律回退美式，确保旧版本数据不会导致启动失败。
      final accent = _accentFromStorage(values?['accent']);
      // 未保存或未知主题一律回退 Light。
      final theme = _themeFromStorage(values?['theme']);
      // 旧版本没有该字段时默认使用顿号。
      final definitionSeparator = _definitionSeparatorFromStorage(
        values?['definitionSeparator'],
      );
      // 把已读取值和生产通道一起保存。
      return SettingsStore._(
        channel: channel,
        accent: accent,
        theme: theme,
        definitionSeparator: definitionSeparator,
      );
    } on MissingPluginException catch (error, stackTrace) {
      // Hot Restart 只更新 Dart；旧 APK 没有重新编译 Kotlin 时会暂时找不到新通道。
      debugPrint('原生设置通道尚未注册，将临时使用内存默认值：$error');
      // 输出堆栈，便于确认是否需要停止 App 后完整重新构建。
      debugPrintStack(stackTrace: stackTrace);
      // channel=null 让本次旧原生壳中的后续修改只更新内存，不再重复抛异常。
      return SettingsStore._(
        channel: null,
        accent: PronunciationAccent.american,
        theme: AppThemePreference.light,
        definitionSeparator: DefinitionSeparator.ideographicComma,
      );
    } on PlatformException catch (error, stackTrace) {
      // 设置读取失败不应让 App 白屏；控制台保留原因并使用明确默认值启动。
      debugPrint('本地设置读取失败，将使用默认值：$error');
      // 堆栈帮助真机调试 MethodChannel 注册或原生存储问题。
      debugPrintStack(stackTrace: stackTrace);
      // 仍保留 channel，让用户后续修改设置时可以再次尝试持久化。
      return SettingsStore._(
        channel: channel,
        accent: PronunciationAccent.american,
        theme: AppThemePreference.light,
        definitionSeparator: DefinitionSeparator.ideographicComma,
      );
    }
  }

  /// Widget 测试使用的纯内存 Store，不要求初始化 Android 插件。
  factory SettingsStore.inMemory({
    PronunciationAccent accent = PronunciationAccent.american,
    AppThemePreference theme = AppThemePreference.light,
    DefinitionSeparator definitionSeparator =
        DefinitionSeparator.ideographicComma,
  }) {
    // channel=null 时 setter 只更新内存并通知页面。
    return SettingsStore._(
      channel: null,
      accent: accent,
      theme: theme,
      definitionSeparator: definitionSeparator,
    );
  }

  /// 页面只读访问当前口音。
  PronunciationAccent get accent => _accent;

  /// 页面只读访问当前主题偏好。
  AppThemePreference get theme => _theme;

  /// 页面只读访问当前中文释义分隔符。
  DefinitionSeparator get definitionSeparator => _definitionSeparator;

  /// 每日复习目标；本轮先保存在内存，原生持久化随分组一起在下一轮落地。
  int _dailyGoal = 100;

  /// 页面只读访问每日复习目标。
  int get dailyGoal => _dailyGoal;

  /// 修改每日复习目标；负数一律钳制为 0。
  void setDailyGoal(int value) {
    // 目标不允许是负数。
    final normalized = value < 0 ? 0 : value;
    // 值没有变化时不触发重建。
    if (_dailyGoal == normalized) return;
    // 更新内存值。
    _dailyGoal = normalized;
    // 通知设置面板与首页副标题刷新。
    notifyListeners();
  }

  /// MaterialApp 直接读取的主题模式。
  ThemeMode get themeMode => _theme.themeMode;

  /// 修改并持久化口音；原生保存成功后才通知界面，避免显示与磁盘不一致。
  Future<void> setAccent(PronunciationAccent value) async {
    // 重复选择当前值时不做磁盘写入，也不触发无意义重建。
    if (_accent == value) return;
    // 生产模式把枚举转换成稳定字符串保存。
    await _channel?.invokeMethod<void>('setAccent', value.storageValue);
    // 保存成功后更新 Store 内存。
    _accent = value;
    // 通知设置面板和其他未来页面刷新。
    notifyListeners();
  }

  /// 修改并持久化主题；通知后 MaterialApp 会立即切换 light/dark。
  Future<void> setTheme(AppThemePreference value) async {
    // 当前值相同时无需再次写入。
    if (_theme == value) return;
    // 先交给 Android SharedPreferences 持久化。
    await _channel?.invokeMethod<void>('setTheme', value.storageValue);
    // 保存成功后替换内存值。
    _theme = value;
    // MaterialApp 正在监听 Store，因此会自动使用新的 ThemeMode。
    notifyListeners();
  }

  /// 修改并持久化中文释义分隔符；成功后所有正在监听的释义区域立即刷新。
  Future<void> setDefinitionSeparator(DefinitionSeparator value) async {
    // 重复选择当前符号时不写磁盘。
    if (_definitionSeparator == value) return;
    // 把枚举转换为原生端约定的稳定字符串。
    await _channel?.invokeMethod<void>(
      'setDefinitionSeparator',
      value.storageValue,
    );
    // 原生确认成功后再更新内存，保证页面显示与磁盘值一致。
    _definitionSeparator = value;
    // 通知首页、设置面板和后续学习页面读取新符号。
    notifyListeners();
  }

  /// 清空全部设置，恢复到首次安装的默认值。
  ///
  /// 对应首页「清空数据」入口：先请原生删除 SharedPreferences 中所有键值，
  /// 再把内存模型重置回美式 / Light / 顿号 / 100，并通知界面刷新（主题随之切回 Light）。
  Future<void> clearAll() async {
    // 原生清空偏好文件；channel 为 null 时（纯测试）只重置内存。
    await _channel?.invokeMethod<void>('clearAllSettings');
    // 重置内存默认值。
    _accent = PronunciationAccent.american;
    _theme = AppThemePreference.light;
    _definitionSeparator = DefinitionSeparator.ideographicComma;
    _dailyGoal = 100;
    // 通知设置面板、首页副标题与 MaterialApp 同步刷新。
    notifyListeners();
  }

  /// 把原生字符串转换成强类型口音。
  static PronunciationAccent _accentFromStorage(Object? value) {
    // 只有明确保存 british 才使用英式，其余值都采用默认美式。
    return value == PronunciationAccent.british.storageValue
        ? PronunciationAccent.british
        : PronunciationAccent.american;
  }

  /// 把原生字符串转换成强类型主题。
  static AppThemePreference _themeFromStorage(Object? value) {
    // 只有明确保存 dark 才启用深色，其余值都采用默认 Light。
    return value == AppThemePreference.dark.storageValue
        ? AppThemePreference.dark
        : AppThemePreference.light;
  }

  /// 把原生字符串转换成强类型中文释义分隔符。
  static DefinitionSeparator _definitionSeparatorFromStorage(Object? value) {
    // switch 明确列出两个非默认值；未知值与缺失值都安全回退顿号。
    return switch (value) {
      'full_width_comma' => DefinitionSeparator.fullWidthComma,
      'full_width_semicolon' => DefinitionSeparator.fullWidthSemicolon,
      _ => DefinitionSeparator.ideographicComma,
    };
  }
}
