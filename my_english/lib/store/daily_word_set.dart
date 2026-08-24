// services.dart 提供 MethodChannel，让 Dart 调用 Android SQLite。
import 'package:flutter/services.dart';

// 每日词库模型保存当天四个模块共用的单词与顺序。
import '../models/daily_word_set.dart';

///
/// 每日词库 Store。
///
/// 日期判断统一交给 Android 本机时区处理，避免 Dart 与 SQLite 分别计算日期
/// 造成午夜边界不一致。数据库只保留当天一份词库，过期的会在保存时清掉。
///
abstract interface class DailyWordSetStore {
  ///
  /// 读取设备本地今天的每日词库。
  Future<DailyWordSet?> getToday();

  ///
  /// 保存（覆盖）今天的每日词库。
  Future<DailyWordSet> saveToday(List<int> wordIds);
}

///
/// 通过项目现有 word_store 通道访问 Android SQLite 的正式实现。
///
class LocalDailyWordSetStore implements DailyWordSetStore {
  ///
  /// 允许测试注入独立通道；正式 App 使用默认 word_store 通道。
  const LocalDailyWordSetStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用实例。
  static const LocalDailyWordSetStore instance = LocalDailyWordSetStore();

  ///
  /// 与 Android MainActivity 注册值完全一致的通道。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 实际执行原生调用的消息通道。
  final MethodChannel _channel;

  ///
  /// 读取设备本地今天的每日词库。
  @override
  Future<DailyWordSet?> getToday() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'getTodayWordSet',
    );
    // null 表示今天还没有点开过任何复习模块。
    if (raw == null) return null;
    return DailyWordSet.fromMap(Map<Object?, Object?>.from(raw));
  }

  ///
  /// 保存（覆盖）今天的每日词库，同时清掉更早日期的历史词库。
  @override
  Future<DailyWordSet> saveToday(List<int> wordIds) async {
    // 空词库无法支撑任何一局复习，直接在 Dart 层拒绝。
    if (wordIds.isEmpty) {
      throw ArgumentError.value(wordIds, 'wordIds', '每日词库单词列表不能为空');
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'saveTodayWordSet',
      <String, Object?>{'wordIds': List<int>.unmodifiable(wordIds)},
    );
    if (raw == null) throw const FormatException('原生没有返回已保存的每日词库');
    return DailyWordSet.fromMap(Map<Object?, Object?>.from(raw));
  }
}
