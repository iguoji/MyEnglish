// material.dart 提供 ChangeNotifier 和 ThemeMode，管理全局设置通知与主题模式。
import 'package:flutter/material.dart';
// services.dart 提供 MethodChannel，让 Dart 读写原生 settings 表。
import 'package:flutter/services.dart';

///
/// 单词发音口音；枚举比到处传递字符串更不容易写错。
///
enum PronunciationAccent {
  ///
  /// 美式发音，也是第一次安装时的默认值。
  american,

  ///
  /// 英式发音。
  british,
}

///
/// 为口音枚举补充存储值和界面文字。
///
extension PronunciationAccentDetails on PronunciationAccent {
  ///
  /// settings 表中保存的稳定字符串。
  String get storageValue => switch (this) {
    PronunciationAccent.american => 'american',
    PronunciationAccent.british => 'british',
  };

  ///
  /// 设置面板显示的简短名称。
  String get label => switch (this) {
    PronunciationAccent.american => '美式',
    PronunciationAccent.british => '英式',
  };
}

///
/// 中文释义之间使用的全角分隔符。
///
enum DefinitionSeparator {
  ///
  /// 中文顿号。
  ideographicComma,

  ///
  /// 中文全角逗号。
  fullWidthComma,

  ///
  /// 中文全角分号，也是首次安装时的默认值。
  fullWidthSemicolon,
}

///
/// 为释义分隔符补充持久化值与真正显示的全角符号。
///
extension DefinitionSeparatorDetails on DefinitionSeparator {
  ///
  /// 保存英文稳定值，避免标点编码差异影响迁移。
  String get storageValue => switch (this) {
    DefinitionSeparator.ideographicComma => 'ideographic_comma',
    DefinitionSeparator.fullWidthComma => 'full_width_comma',
    DefinitionSeparator.fullWidthSemicolon => 'full_width_semicolon',
  };

  ///
  /// App 拼接中文释义时真正使用的全角标点。
  String get symbol => switch (this) {
    DefinitionSeparator.ideographicComma => '、',
    DefinitionSeparator.fullWidthComma => '，',
    DefinitionSeparator.fullWidthSemicolon => '；',
  };
}

///
/// 用户选择的主题；当前只开放 Light 与 Dark。
///
enum AppThemePreference {
  ///
  /// 浅色主题，也是第一次安装时的默认值。
  light,

  ///
  /// 深色主题。
  dark,
}

///
/// 为主题枚举补充持久化值、界面文字和 Flutter ThemeMode。
///
extension AppThemePreferenceDetails on AppThemePreference {
  ///
  /// settings 表中使用的稳定字符串。
  String get storageValue => switch (this) {
    AppThemePreference.light => 'light',
    AppThemePreference.dark => 'dark',
  };

  ///
  /// 设置面板显示的名称。
  String get label => switch (this) {
    AppThemePreference.light => 'Light',
    AppThemePreference.dark => 'Dark',
  };

  ///
  /// MaterialApp 真正需要的主题模式。
  ThemeMode get themeMode => switch (this) {
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}

///
/// 全站文字大小档位，也就是俗称的「老年版」开关。
///
/// 它不是「把某几处字号改大」，而是给整个 App 拧一个放大倍数：所有文字
/// ——标题、正文、按钮、候选词、结算页的大数字——一起按同一比例变大，
/// 版式比例保持不变。所以这里只有三个档位，没有「单独调某一处」的选项。
///
/// 实现上不动 `AppFont` 那张字号表里的任何数值（见 `common/design/fonts.dart`），
/// 而是在 App 最外层设置一个文字缩放器。这样做的好处很实际：以后新增页面
/// 不需要为放大做任何额外处理，写 `AppFont.fs5` 就自动跟着一起变大。
///
enum AppFontScale {
  ///
  /// 标准：不放大，也是第一次安装时的默认值。
  standard,

  ///
  /// 大：放大约一成半，适合觉得默认字号偏小但又不想太挤的情况。
  large,

  ///
  /// 特大：放大约三成，是本项目做过耐压测试的上限。
  ///
  /// 再往上不开放，是因为超过这个倍数后候选按钮、顶栏这类固定高度的地方
  /// 会开始裁字——与其让用户选到一个会出错的档位，不如把上限画在这里。
  huge,
}

///
/// 为字体大小档位补充持久化值、界面文字和真正的放大倍数。
///
extension AppFontScaleDetails on AppFontScale {
  ///
  /// settings 表中保存的稳定字符串。
  ///
  /// 存英文而不是存倍数：万一以后想把「大」从 1.15 调成 1.2，
  /// 已经选了「大」的用户会跟着一起变，而不是被永久钉在旧倍数上。
  String get storageValue => switch (this) {
    AppFontScale.standard => 'standard',
    AppFontScale.large => 'large',
    AppFontScale.huge => 'huge',
  };

  ///
  /// 设置面板显示的简短名称。
  String get label => switch (this) {
    AppFontScale.standard => '标准',
    AppFontScale.large => '大',
    AppFontScale.huge => '特大',
  };

  ///
  /// 全站文字的放大倍数。
  ///
  /// 1.15 与 1.3 是刻意选的：跨度太小用户看不出区别，跨度太大就会撑破布局。
  /// 这两个数配合「特大」档跑过一轮耐压测试，六个页面都不裁字。
  double get multiplier => switch (this) {
    AppFontScale.standard => 1.0,
    AppFontScale.large => 1.15,
    AppFontScale.huge => 1.3,
  };
}

///
/// 全局设置 Store：内存状态 + settings 表持久化。
///
/// settings 表就是一个可持久化的 Redis：一行一个 key，value 永远是文本，
/// 由 type 列声明它真正是什么类型。所以这里读写时要显式给出类型，
/// 让原生能在写入时就把「int 的 key 塞进了一段文本」这类错误拦下来。
///
class SettingsStore extends ChangeNotifier {
  ///
  /// 私有构造器确保生产环境必须先通过 [load] 读取持久化值。
  ///
  /// 参数用位置形式：命名参数不能以下划线开头，而这两个字段必须是私有的。
  SettingsStore._(this._channel, this._values);

  ///
  /// 原生通道名必须与 MainActivity 注册值保持一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/settings',
  );

  ///
  /// null 表示测试使用纯内存模式，不访问 Android。
  final MethodChannel? _channel;

  ///
  /// 当前全部设置值；只允许通过下面的 setter 修改。
  _Values _values;

  // ---- settings 表里的键名；改这里等于改数据库，务必谨慎 ----------------

  /// 发音口音。
  static const String keyAccent = 'accent';

  /// 界面主题。
  static const String keyTheme = 'theme';

  /// 全站文字大小档位（老年版开关）。
  static const String keyFontScale = 'fontScale';

  /// 中文释义分隔符。
  static const String keyDefinitionSeparator = 'definitionSeparator';

  /// 每日复习目标数量。
  static const String keyDailyGoal = 'dailyGoal';

  /// 词义连连每局倒计时秒数。
  static const String keyMeaningMatchDuration = 'meaningMatchDuration';

  /// 随身听：每个单词重复播放几遍。
  static const String keyListeningRepeat = 'listeningRepeat';

  /// 随身听：两遍之间间隔几秒。
  static const String keyListeningInterval = 'listeningInterval';

  /// 随身听：整轮放完后是否从头循环。
  static const String keyListeningLoop = 'listeningLoop';

  /// 随身听：是否默认展开全部释义。
  static const String keyListeningRevealAll = 'listeningRevealAll';

  ///
  /// App 启动时调用：先读取 settings 表，再创建可供页面监听的 Store。
  static Future<SettingsStore> load({
    MethodChannel channel = _defaultChannel,
  }) async {
    try {
      // 原生返回 { key: {value, type} }；一次读全部，启动只查一次库。
      final rows = await channel.invokeMapMethod<String, Object?>(
        'getSettings',
      );
      return SettingsStore._(
        channel,
        _Values.fromRows(rows ?? const <String, Object?>{}),
      );
    } on MissingPluginException catch (error, stackTrace) {
      // Hot Restart 只更新 Dart；旧 APK 没有重新编译 Kotlin 时会暂时找不到新通道。
      debugPrint('原生设置通道尚未注册，将临时使用内存默认值：$error');
      // 输出堆栈，便于确认是否需要停止 App 后完整重新构建。
      debugPrintStack(stackTrace: stackTrace);
      // channel=null 让本次旧原生壳中的后续修改只更新内存，不再重复抛异常。
      return SettingsStore._(null, const _Values());
    } on PlatformException catch (error, stackTrace) {
      // 设置读取失败不应让 App 白屏；控制台保留原因并使用明确默认值启动。
      debugPrint('本地设置读取失败，将使用默认值：$error');
      debugPrintStack(stackTrace: stackTrace);
      // 仍保留 channel，让用户后续修改设置时可以再次尝试持久化。
      return SettingsStore._(channel, const _Values());
    }
  }

  ///
  /// Widget 测试使用的纯内存 Store，不要求初始化 Android 插件。
  factory SettingsStore.inMemory({
    PronunciationAccent accent = PronunciationAccent.american,
    AppThemePreference theme = AppThemePreference.light,
    AppFontScale fontScale = AppFontScale.standard,
    DefinitionSeparator definitionSeparator =
        DefinitionSeparator.fullWidthSemicolon,
    int dailyGoal = 50,
    int meaningMatchDuration = 150,
    int listeningRepeat = 2,
    int listeningInterval = 2,
    bool listeningLoop = true,
    bool listeningRevealAll = false,
  }) {
    // channel=null 时 setter 只更新内存并通知页面。
    return SettingsStore._(
      null,
      _Values(
        accent: accent,
        theme: theme,
        fontScale: fontScale,
        definitionSeparator: definitionSeparator,
        dailyGoal: dailyGoal < 0 ? 0 : dailyGoal,
        meaningMatchDuration: meaningMatchDuration < 0
            ? 0
            : meaningMatchDuration,
        listeningRepeat: listeningRepeat.clamp(1, 9),
        listeningInterval: listeningInterval < 0 ? 0 : listeningInterval,
        listeningLoop: listeningLoop,
        listeningRevealAll: listeningRevealAll,
      ),
    );
  }

  // ---- 只读访问 ---------------------------------------------------------

  /// 当前发音口音。
  PronunciationAccent get accent => _values.accent;

  /// 当前主题偏好。
  AppThemePreference get theme => _values.theme;

  /// MaterialApp 直接读取的主题模式。
  ThemeMode get themeMode => _values.theme.themeMode;

  /// 当前文字大小档位。
  AppFontScale get fontScale => _values.fontScale;

  /// 当前中文释义分隔符。
  DefinitionSeparator get definitionSeparator => _values.definitionSeparator;

  /// 每日复习目标。
  int get dailyGoal => _values.dailyGoal;

  /// 词义连连每局倒计时秒数。
  int get meaningMatchDuration => _values.meaningMatchDuration;

  /// 随身听每个单词重复播放几遍。
  int get listeningRepeat => _values.listeningRepeat;

  /// 随身听两遍之间间隔几秒。
  int get listeningInterval => _values.listeningInterval;

  /// 随身听整轮放完后是否从头循环。
  bool get listeningLoop => _values.listeningLoop;

  /// 随身听是否默认展开全部释义。
  bool get listeningRevealAll => _values.listeningRevealAll;

  // ---- 修改 -------------------------------------------------------------

  ///
  /// 修改并持久化发音口音。
  Future<void> setAccent(PronunciationAccent value) async {
    // 重复选择当前值时不做磁盘写入，也不触发无意义重建。
    if (_values.accent == value) return;
    await _write(keyAccent, value.storageValue, 'string');
    _values = _values.copyWith(accent: value);
    notifyListeners();
  }

  ///
  /// 修改并持久化主题；通知后 MaterialApp 会立即切换 light/dark。
  Future<void> setTheme(AppThemePreference value) async {
    if (_values.theme == value) return;
    await _write(keyTheme, value.storageValue, 'string');
    _values = _values.copyWith(theme: value);
    notifyListeners();
  }

  ///
  /// 修改并持久化文字大小档位；通知后全站文字立即按新倍数重排。
  ///
  /// 和主题切换是同一种机制：这里只改一个档位值，页面本身一行都不用动，
  /// 由 App 最外层的文字缩放器统一放大（见 `lib/app.dart`）。
  Future<void> setFontScale(AppFontScale value) async {
    if (_values.fontScale == value) return;
    await _write(keyFontScale, value.storageValue, 'string');
    _values = _values.copyWith(fontScale: value);
    notifyListeners();
  }

  ///
  /// 修改并持久化中文释义分隔符；成功后全部释义文本立即刷新。
  Future<void> setDefinitionSeparator(DefinitionSeparator value) async {
    if (_values.definitionSeparator == value) return;
    await _write(keyDefinitionSeparator, value.storageValue, 'string');
    _values = _values.copyWith(definitionSeparator: value);
    notifyListeners();
  }

  ///
  /// 修改并持久化每日复习目标；负数一律钳制为 0。
  ///
  /// 注意：改这个数字会让今天已经开着的每一局都对不上新词库，
  /// 调用方需要接着中断全部进行中的会话（见 SessionStore.abortActiveSessions）。
  Future<void> setDailyGoal(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_values.dailyGoal == normalized) return;
    await _write(keyDailyGoal, normalized.toString(), 'int');
    _values = _values.copyWith(dailyGoal: normalized);
    notifyListeners();
  }

  ///
  /// 修改并持久化词义连连每局倒计时秒数；负数一律钳制为 0。
  ///
  /// 该值与游戏内点击倒计时 `+30s` 共用：点击加时既延长当前局剩余时间，
  /// 也把全局默认值同步抬高，下一次进入词义连连会从更高的值开始。
  Future<void> setMeaningMatchDuration(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_values.meaningMatchDuration == normalized) return;
    await _write(keyMeaningMatchDuration, normalized.toString(), 'int');
    _values = _values.copyWith(meaningMatchDuration: normalized);
    notifyListeners();
  }

  ///
  /// 修改并持久化随身听重复遍数；允许 1～9 遍。
  Future<void> setListeningRepeat(int value) async {
    final normalized = value.clamp(1, 9);
    if (_values.listeningRepeat == normalized) return;
    await _write(keyListeningRepeat, normalized.toString(), 'int');
    _values = _values.copyWith(listeningRepeat: normalized);
    notifyListeners();
  }

  ///
  /// 修改并持久化随身听播放间隔秒数；负数一律钳制为 0。
  Future<void> setListeningInterval(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_values.listeningInterval == normalized) return;
    await _write(keyListeningInterval, normalized.toString(), 'int');
    _values = _values.copyWith(listeningInterval: normalized);
    notifyListeners();
  }

  ///
  /// 修改并持久化随身听是否循环。
  Future<void> setListeningLoop(bool value) async {
    if (_values.listeningLoop == value) return;
    await _write(keyListeningLoop, value ? 'true' : 'false', 'bool');
    _values = _values.copyWith(listeningLoop: value);
    notifyListeners();
  }

  ///
  /// 修改并持久化随身听是否默认展开全部释义。
  Future<void> setListeningRevealAll(bool value) async {
    if (_values.listeningRevealAll == value) return;
    await _write(keyListeningRevealAll, value ? 'true' : 'false', 'bool');
    _values = _values.copyWith(listeningRevealAll: value);
    notifyListeners();
  }

  ///
  /// 清空全部设置，恢复到首次安装的默认值。
  Future<void> clearAll() async {
    // 原生软删除 settings 表全部行；channel 为 null 时（纯测试）只重置内存。
    await _channel?.invokeMethod<void>('clearSettings');
    _values = const _Values();
    // 通知设置面板、首页副标题与 MaterialApp 同步刷新（主题会切回 Light）。
    notifyListeners();
  }

  ///
  /// 从数据库重新读取全部设置并覆盖内存值。
  ///
  /// 供「导入完整备份」后调用：备份里携带设置时，界面需要跟随导入后的
  /// 内容同步，而不是继续显示导入前的旧值。
  Future<void> reload() async {
    // 内存模式（测试或旧原生壳）没有通道可读，保持现状即可。
    if (_channel == null) return;
    try {
      final rows = await _channel.invokeMapMethod<String, Object?>(
        'getSettings',
      );
      _values = _Values.fromRows(rows ?? const <String, Object?>{});
      notifyListeners();
    } on PlatformException catch (error) {
      // 单次重载失败不阻断导入，界面继续使用旧值。
      debugPrint('本地设置重载失败，沿用当前设置：$error');
    } on MissingPluginException catch (error) {
      debugPrint('本地设置通道未注册，跳过重载：$error');
    }
  }

  ///
  /// 写入一个设置项；先等原生确认落盘，再更新内存值。
  ///
  /// 这个顺序保证界面显示的永远是磁盘上真实存在的值。
  Future<void> _write(String key, String value, String type) =>
      _channel?.invokeMethod<void>('setSetting', <String, Object?>{
        'key': key,
        'value': value,
        'type': type,
      }) ??
      Future<void>.value();
}

///
/// 全部设置值的不可变快照。
///
/// 单独抽一个类，是为了让「读一批 → 整体替换」比逐个字段赋值更不容易漏。
class _Values {
  ///
  /// 创建一份设置快照；每个字段的默认值就是首次安装时的值。
  const _Values({
    this.accent = PronunciationAccent.american,
    this.theme = AppThemePreference.light,
    this.fontScale = AppFontScale.standard,
    this.definitionSeparator = DefinitionSeparator.fullWidthSemicolon,
    this.dailyGoal = 50,
    this.meaningMatchDuration = 150,
    this.listeningRepeat = 2,
    this.listeningInterval = 2,
    this.listeningLoop = true,
    this.listeningRevealAll = false,
  });

  final PronunciationAccent accent;
  final AppThemePreference theme;
  final AppFontScale fontScale;
  final DefinitionSeparator definitionSeparator;
  final int dailyGoal;
  final int meaningMatchDuration;
  final int listeningRepeat;
  final int listeningInterval;
  final bool listeningLoop;
  final bool listeningRevealAll;

  ///
  /// 从原生返回的 `{ key: {value, type} }` 组装快照。
  ///
  /// 任何一项缺失或格式不对都安全回退到默认值——设置读坏了最多是界面样式
  /// 变回默认，绝不能让 App 起不来。
  factory _Values.fromRows(Map<String, Object?> rows) {
    String? text(String key) {
      final row = rows[key];
      if (row is! Map) return null;
      return row['value']?.toString();
    }

    int number(String key, int fallback) {
      final parsed = int.tryParse(text(key) ?? '');
      // 负数和非数字都视为损坏数据，回退到产品默认值。
      return parsed != null && parsed >= 0 ? parsed : fallback;
    }

    bool flag(String key, bool fallback) => switch (text(key)) {
      'true' => true,
      'false' => false,
      // 未保存或值损坏时使用默认值。
      _ => fallback,
    };

    return _Values(
      // 只有明确保存 british 才使用英式，其余值都采用默认美式。
      accent: text(SettingsStore.keyAccent) == 'british'
          ? PronunciationAccent.british
          : PronunciationAccent.american,
      // 只有明确保存 dark 才启用深色，其余值都采用默认 Light。
      theme: text(SettingsStore.keyTheme) == 'dark'
          ? AppThemePreference.dark
          : AppThemePreference.light,
      fontScale: switch (text(SettingsStore.keyFontScale)) {
        'large' => AppFontScale.large,
        'huge' => AppFontScale.huge,
        // 未知值与缺失值都回落标准档：字太大读不下去也好过 App 起不来。
        _ => AppFontScale.standard,
      },
      definitionSeparator: switch (text(SettingsStore.keyDefinitionSeparator)) {
        'ideographic_comma' => DefinitionSeparator.ideographicComma,
        'full_width_comma' => DefinitionSeparator.fullWidthComma,
        // 未知值与缺失值都安全回退分号（首次安装的默认值）。
        _ => DefinitionSeparator.fullWidthSemicolon,
      },
      dailyGoal: number(SettingsStore.keyDailyGoal, 50),
      meaningMatchDuration: number(SettingsStore.keyMeaningMatchDuration, 150),
      // 重复遍数是 1～9，0 遍等于不播放，没有意义。
      listeningRepeat: number(SettingsStore.keyListeningRepeat, 2).clamp(1, 9),
      listeningInterval: number(SettingsStore.keyListeningInterval, 2),
      listeningLoop: flag(SettingsStore.keyListeningLoop, true),
      listeningRevealAll: flag(SettingsStore.keyListeningRevealAll, false),
    );
  }

  ///
  /// 复制并替换部分字段；没传的字段保持原值。
  _Values copyWith({
    PronunciationAccent? accent,
    AppThemePreference? theme,
    AppFontScale? fontScale,
    DefinitionSeparator? definitionSeparator,
    int? dailyGoal,
    int? meaningMatchDuration,
    int? listeningRepeat,
    int? listeningInterval,
    bool? listeningLoop,
    bool? listeningRevealAll,
  }) => _Values(
    accent: accent ?? this.accent,
    theme: theme ?? this.theme,
    fontScale: fontScale ?? this.fontScale,
    definitionSeparator: definitionSeparator ?? this.definitionSeparator,
    dailyGoal: dailyGoal ?? this.dailyGoal,
    meaningMatchDuration: meaningMatchDuration ?? this.meaningMatchDuration,
    listeningRepeat: listeningRepeat ?? this.listeningRepeat,
    listeningInterval: listeningInterval ?? this.listeningInterval,
    listeningLoop: listeningLoop ?? this.listeningLoop,
    listeningRevealAll: listeningRevealAll ?? this.listeningRevealAll,
  );
}
