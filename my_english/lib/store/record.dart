// flutter/services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SQLite。
import 'package:flutter/services.dart';

// 记录模型位于全局 models 目录，与 word.dart 同层级。
import '../models/record.dart';

/// 默写记录 Store：记录写入与「今日复习」查询都走原生 word_store 通道。
///
/// 记录策略（2026-07-30 起）：**每次默写成功都插入一条新记录**，同一个单词
/// 一天可以有多条（重复练习、点了"再试一次"都会各留一条）。所以本 Store 负责：
/// 1) 把一次默写结果交给原生 `addDictationRecord`（插记录、更新复习时间、
///    调整难度都在原生同一个事务内完成）；
/// 2) 读取「今日复习」所需的记录列表与去重后的数量。
class RecordStore {
  /// 允许测试注入原生通道；正式 App 使用默认值。
  RecordStore({MethodChannel? channel})
    // 没有注入通道时使用 Android MainActivity 注册的固定名称。
    : _channel = channel ?? _defaultChannel;

  /// App 默认复用同一个实例，类似 PHP 单例 Store。
  static final RecordStore instance = RecordStore();

  /// 通道名必须与 Android MainActivity 完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  /// 读写记录用的原生通道。
  final MethodChannel _channel;

  /// 记录一次单词默写结果。
  ///
  /// 参数对应页面在「单词完成」那一刻统计出的本次数据：
  /// - [wordId]：哪个单词；
  /// - [isCorrect]：本次是否"一次做对"（中途没有选错过候选词）；
  /// - [wrongCount]：本次选错候选词的次数；
  /// - [hintCount]：本次点击提示的次数。
  ///
  /// 原生内部固定执行三件事，调用方无需关心：插入一条新记录、更新单词的
  /// 复习时间、按「错了 +1 / 最近 5 条连续全对 -1」调整难度。
  Future<void> addCompletion({
    required int wordId,
    required bool isCorrect,
    required int wrongCount,
    required int hintCount,
  }) async {
    // 把字段打包成原生能识别的 Map 再调用，类似 PHP 调原生插件时传关联数组。
    await _channel.invokeMethod<void>('addDictationRecord', <String, Object?>{
      'wordId': wordId,
      'isCorrect': isCorrect,
      'wrongCount': wrongCount,
      'hintCount': hintCount,
    });
  }

  /// 读取今日全部默写记录（原生已按 created_date = 今天 过滤）。
  ///
  /// 返回的是「今天写进数据库的全部记录」，同一个单词可能出现多条
  /// （一天里练了几遍就有几条）。UI 想展示「今天复习了哪些词」时再用
  /// [getTodayReviewWordIds] 去重即可。
  Future<List<Record>> getTodayRecords() async {
    // 原生返回 List<Map>，null 按空列表处理。
    final raw = await _channel.invokeListMethod<Object?>('getTodayReviewWords');
    // 原生没有返回任何记录。
    if (raw == null) return const <Record>[];
    // 逐条 Map 转成 Record 模型。
    final records = <Record>[];
    for (final item in raw) {
      // 跳过类型不正确的元素，避免原生崩溃牵连整个列表。
      if (item is! Map) continue;
      records.add(Record.fromMap(Map<Object?, Object?>.from(item)));
    }
    // 冻结列表，防止页面直接修改 Store 内部顺序。
    return List<Record>.unmodifiable(records);
  }

  /// 今日复习的单词 id 列表（去重）。
  ///
  /// 「今日复习」本质就是：今天存在记录的那些单词。这里取出去重后的
  /// wordId，页面再凭 id 去词库里取拼写/释义展示。
  Future<List<int>> getTodayReviewWordIds() async {
    // 先拿到今日全部记录。
    final records = await getTodayRecords();
    // 用 LinkedHashSet 保持出现顺序同时去重。
    final ids = <int>{};
    for (final record in records) {
      ids.add(record.wordId);
    }
    // 转成 List 返回。
    return ids.toList();
  }

  /// 今日复习数量：按天 + 按单词汇总（同一个词今天练几遍都只算 1）。
  ///
  /// 首页副标题「今日复习 X/目标」用的就是这个值。这里直接让原生用
  /// `COUNT(DISTINCT word_id)` 聚合出数字，比把整天的记录都搬到 Dart 再去重更省。
  Future<int> getTodayReviewWordCount() async {
    // 原生返回一个整数；通道异常由调用方 try/catch 兜底。
    final count = await _channel.invokeMethod<int>('getTodayReviewWordCount');
    // null（如旧版本原生尚未实现）按 0 处理，界面仍能正常显示。
    return count ?? 0;
  }
}
