import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// 一行已保存的音节划分结果。
class SyllableRow {
  final List<String> parts; // 切好的音节块，如 ["tradi", "tion"]
  final String source; // 来源：algo=算法默认 / refresh=刷新备选 / user=用户手动
  const SyllableRow(this.parts, this.source);
}

/// 音节划分存储接口。
///
/// "结果存哪儿"在测试和真实 App 里不一样：测试用内存，App 用手机数据库。
/// [SyllableService]（`lib/services/syllable_service.dart`）只认这个接口，
/// 不关心底层具体实现。
abstract interface class SyllableStore {
  /// 取出某单词已保存的划分（没有则返回 null）。
  Future<SyllableRow?> getDivision(String word);

  /// 保存/覆盖某单词的划分（upsert 语义：有则更新，无则插入）。
  Future<void> saveDivision(String word, List<String> parts, String source);
}

/// 通过 MethodChannel 把音节划分存到 Android 原生 SQLite 的正式实现。
///
/// 必须和 MainActivity.kt 里注册的通道名 `my_english/syllable` 完全一致，
/// 否则 Dart 发出的请求 Android 端收不到。
class LocalSyllableStore implements SyllableStore {
  // 这座"桥"的端口名；两端（Dart / Kotlin）必须相同。
  static const MethodChannel _channel = MethodChannel('my_english/syllable');

  /// 读取某单词已保存的划分。
  @override
  Future<SyllableRow?> getDivision(String word) async {
    // invokeMethod 第一个参数是"方法名"，第二个是参数 Map，对应 Kotlin 的 when 分支。
    final result = await _channel.invokeMethod('getSyllableDivision', {
      'word': word,
    });
    if (result == null) return null;
    // Android 回传的是 {syllables: "[\"tra\",\"di\"]", source: "algo"} 这样的 Map。
    final map = Map<String, dynamic>.from(result as Map);
    final parts = List<String>.from(jsonDecode(map['syllables'] as String));
    return SyllableRow(parts, map['source'] as String);
  }

  /// 保存/覆盖某单词的划分（upsert：有则更新，无则插入）。
  @override
  Future<void> saveDivision(
    String word,
    List<String> parts,
    String source,
  ) async {
    // 数组要先序列化成 JSON 字符串才能跨这座桥传输。
    await _channel.invokeMethod('saveSyllableDivision', {
      'word': word,
      'syllables': jsonEncode(parts),
      'source': source,
    });
  }
}
