// services.dart 提供 MethodChannel，让 Dart 调用 Android SQLite。
import 'package:flutter/services.dart';

// 每日复习计划模型保存当天共用的目标与固定单词顺序。
import '../models/daily_review_plan.dart';

///
/// 每日公共复习词单 Store。
///
/// 日期判断统一交给 Android 本机时区处理，避免 Dart 与 SQLite 分别计算日期
/// 造成午夜边界不一致。数据库只保留当天一份计划，过期计划不会被返回。
///
abstract interface class DailyReviewPlanStore {
  /// 读取设备本地今天仍有效的公共复习词单。
  Future<DailyReviewPlan?> getToday();

  /// 保存并覆盖今天的公共复习词单。
  Future<DailyReviewPlan> saveToday({
    required int dailyGoal,
    required List<int> wordIds,
    required int selectionVersion,
  });
}

/// 通过项目现有 word_store 通道访问 Android SQLite 的正式实现。
class LocalDailyReviewPlanStore implements DailyReviewPlanStore {
  /// 允许测试注入独立通道；正式 App 使用默认 word_store 通道。
  const LocalDailyReviewPlanStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  /// App 默认复用实例。
  static const LocalDailyReviewPlanStore instance = LocalDailyReviewPlanStore();

  /// 与 Android MainActivity 注册值完全一致的通道。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  /// 实际执行原生调用的消息通道。
  final MethodChannel _channel;

  ///
  /// 读取设备本地今天仍有效的公共复习词单。
  ///
  /// @return `Future<DailyReviewPlan?>` 今天尚未生成时返回 null。
  ///
  @override
  Future<DailyReviewPlan?> getToday() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'getTodayReviewPlan',
    );
    if (raw == null) return null;
    return DailyReviewPlan.fromMap(Map<Object?, Object?>.from(raw));
  }

  ///
  /// 保存并覆盖今天的公共复习词单，同时清理其他日期的过期计划。
  ///
  /// @param  int  dailyGoal 当天冻结的目标数量。
  /// @param  `List<int>`  wordIds 固定顺序的单词主键。
  /// @param  int  selectionVersion 生成固定顺序时采用的规则版本。
  /// @return `Future<DailyReviewPlan>` 原生实际保存后的计划。
  ///
  @override
  Future<DailyReviewPlan> saveToday({
    required int dailyGoal,
    required List<int> wordIds,
    required int selectionVersion,
  }) async {
    if (dailyGoal < 0) {
      throw ArgumentError.value(dailyGoal, 'dailyGoal', '每日复习量不能为负数');
    }
    if (selectionVersion < 0) {
      throw ArgumentError.value(
        selectionVersion,
        'selectionVersion',
        '选词规则版本不能为负数',
      );
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'saveTodayReviewPlan',
      <String, Object?>{
        'dailyGoal': dailyGoal,
        'wordIds': List<int>.unmodifiable(wordIds),
        'selectionVersion': selectionVersion,
      },
    );
    if (raw == null) throw const FormatException('原生没有返回已保存的每日复习计划');
    return DailyReviewPlan.fromMap(Map<Object?, Object?>.from(raw));
  }
}
