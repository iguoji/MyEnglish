// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SAF 文件读写。
import 'package:flutter/services.dart';

///
/// 文件读写服务：通过原生 SAF（系统文件选择器）选 JSON、写导出文件。
///
/// 这里刻意不引入第三方 file_picker 插件——它在 AGP 9 的构建链下会跳过
/// Kotlin 插件编译，导致原生类缺失、构建失败。改用和 word_store / settings
/// 同风格的原生 MethodChannel 自己实现，少一个依赖、构建更稳。
///
class NativeFileIo {
  ///
  /// 允许测试注入原生通道；正式 App 使用默认值。
  ///
  /// @param  MethodChannel?  channel
  ///
  const NativeFileIo({MethodChannel? channel})
    // 没有注入通道时使用 MainActivity 注册的固定名称。
    : _channel = channel ?? _defaultChannel;

  ///
  /// 通道名必须与 Android MainActivity 完全一致。
  ///
  /// @var MethodChannel
  ///
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/file_io',
  );

  ///
  /// 文件操作调用的原生通道。
  ///
  /// @var MethodChannel
  ///
  final MethodChannel _channel;

  ///
  /// 打开系统文件选择器，只列出 JSON，返回所选文件的文本内容。
  ///
  /// 用户取消选择时返回 null，调用方不应做任何改动。
  ///
  /// @return `Future<String?>`
  ///
  Future<String?> pickJsonText() {
    // 原生用 ACTION_OPEN_DOCUMENT 选文件并读成文本后回传。
    return _channel.invokeMethod<String?>('pickJsonText');
  }

  ///
  /// 打开系统保存框，把 [jsonText] 写到用户指定的位置。
  ///
  /// [fileName] 作为系统保存框预填的文件名（例如 MyEnglish-2026-07-28.json）。
  /// 返回真实保存位置的 Uri 字符串；用户取消保存时返回 null。
  ///
  /// @param  String  fileName
  /// @param  String  jsonText
  /// @return `Future<String?>`
  ///
  Future<String?> writeExportJson({
    required String fileName,
    required String jsonText,
  }) {
    // 原生用 ACTION_CREATE_DOCUMENT 预填文件名，由系统把文本落盘到用户选的位置。
    return _channel.invokeMethod<String?>('writeExportJson', <String, Object?>{
      'fileName': fileName,
      'jsonText': jsonText,
    });
  }
}
