// dart:async 提供 unawaited，让日志写盘不阻塞任何业务调用。
import 'dart:async';

// services.dart 提供 MethodChannel，把 Dart 侧事件转发给原生 AppLog 内核。
import 'package:flutter/services.dart';

///
/// Dart 侧日志入口：把事件转发给 Android 原生的单文件日志（AppLog）。
///
/// 设计要点（与原生侧约定一致）：
/// - 全 App 只有一个日志文件，只保留当天数据，跨天自动清空；
/// - 日志绝不能影响主流程：写入失败静默吞掉，也不阻塞调用方；
/// - 用 [_enabled] 开关区分生产与测试：main() 里 [enable] 之后才真正发通道，
///   其余时候（Widget 测试、单元测试）一律空操作，避免测试环境触碰原生通道。
///
class AppLog {
  ///
  /// 是否允许真正写日志；只有 main() 调用 [enable] 后才为 true。
  static bool _enabled = false;

  ///
  /// 通道名必须与 Android MainActivity 注册的原生通道完全一致。
  static const MethodChannel _channel = MethodChannel('my_english/app_log');

  ///
  /// 打开日志开关；只在应用 main() 启动时调用一次。
  static void enable() {
    _enabled = true;
  }

  ///
  /// 记一条 info 级日志。
  static void i(String tag, String message) => _write('info', tag, message);

  ///
  /// 记一条 error 级日志。
  static void e(String tag, String message) => _write('error', tag, message);

  ///
  /// 统一的写入口：先过开关，再以「发了就不管」的方式调原生通道。
  static void _write(String level, String tag, String message) {
    // 测试环境不打开开关，直接返回，不会触发任何原生调用。
    if (!_enabled) return;
    // 原生返回的 Future 不等待；catchError 吞掉通道不可用等一切异常。
    unawaited(
      _channel
          .invokeMethod<void>('append', <String, Object?>{
            'level': level,
            'tag': tag,
            'message': message,
          })
          .catchError((Object _) {}),
    );
  }
}
