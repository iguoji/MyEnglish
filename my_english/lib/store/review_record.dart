import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/review_record.dart';
import '../models/review_session.dart';

///
/// 复习记录 Store 接口。
///
/// 每答完一个单词就新增一条记录；连对次数、难度和复习时间由原生数据库在
/// 同一个事务里更新，Dart 只负责把「这次错了几下、提示了几次」交上去。
///
/// **统计口径（首页数字、趋势曲线、打卡热力图三处完全一致）**：
/// 只统计「一气呵成」的记录，也就是这一遍一个都没错。练了但错过的词不算数——
/// 用户要看的是「今天真正拿下了多少个词」。不区分模块，也不区分主线还是巩固：
/// 练了就算。
///
abstract interface class ReviewRecordStore {
  ///
  /// 记录一次单词复习结果。
  ///
  /// 原生在同一个事务里固定做四件事，调用方无需关心：
  /// 1. 插入一条复习记录；
  /// 2. 按「答对 +1 / 答错归 0」更新连对次数；
  /// 3. 按「错一次 +1 / 连对满 5 的倍数 -1，下限 0」调整单词难度；
  /// 4. 只有 [updateReviewedAt] 为 true 时才推进单词的复习时间。
  ///
  /// 关于正误口径：判定标准是**这一遍有没有选错过**，不是「最后有没有做完」。
  /// [wrongCount] 为 0 就算正确；点提示只作为 [hintCount] 留档，不影响判定。
  Future<ReviewRecordResult> add({
    required int wordId,
    required ReviewModule module,
    required int? sessionId,
    required int wrongCount,
    required int hintCount,
    required bool updateReviewedAt,
    Map<String, Object?> extra,
  });

  ///
  /// 读取今日全部复习记录（含答错的那些）。
  Future<List<ReviewRecord>> getTodayRecords();

  ///
  /// 今日一次做对过的不同单词 id 列表（去重）。
  Future<List<int>> getTodayReviewWordIds();

  ///
  /// 今日复习数量：今天「一次做对」过的不同单词数。
  Future<int> getTodayReviewWordCount();

  ///
  /// 按天统计复习单词数（每天按单词去重）。
  Future<Map<String, int>> getDailyReviewCounts({DateTime? since});

  ///
  /// 按月统计复习单词数（每月按单词去重）。
  Future<Map<String, int>> getMonthlyReviewCounts({DateTime? since});
}

///
/// 通过项目现有 word_store 通道访问 Android SQLite 的正式实现。
///
class LocalReviewRecordStore implements ReviewRecordStore {
  ///
  /// 允许测试注入原生通道；正式 App 使用默认值。
  const LocalReviewRecordStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用实例。
  static const LocalReviewRecordStore instance = LocalReviewRecordStore();

  ///
  /// 通道名必须与 Android MainActivity 完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 读写记录用的原生通道。
  final MethodChannel _channel;

  ///
  /// 记录一次单词复习结果。
  ///
  /// 原生在同一个事务里固定做四件事，调用方无需关心：
  /// 1. 插入一条复习记录；
  /// 2. 按「答对 +1 / 答错归 0」更新连对次数；
  /// 3. 按「错一次 +1 / 连对满 5 的倍数 -1，下限 0」调整单词难度；
  /// 4. 只有 [updateReviewedAt] 为 true 时才推进单词的复习时间。
  ///
  /// 关于正误口径：判定标准是**这一遍有没有选错过**，不是「最后有没有做完」。
  /// [wrongCount] 为 0 就算正确；点提示只作为 [hintCount] 留档，不影响判定。
  @override
  Future<ReviewRecordResult> add({
    required int wordId,
    required ReviewModule module,
    required int? sessionId,
    required int wrongCount,
    required int hintCount,
    required bool updateReviewedAt,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'addReviewRecord',
      <String, Object?>{
        'wordId': wordId,
        'module': module.storageKey,
        'sessionId': sessionId,
        'wrongCount': wrongCount < 0 ? 0 : wrongCount,
        'hintCount': hintCount < 0 ? 0 : hintCount,
        'updateReviewedAt': updateReviewedAt,
        // 扩展字段统一编码成 JSON 文本，由 SQLite 作为 TEXT 保存。
        'extraJson': jsonEncode(extra),
      },
    );
    if (raw == null) throw const FormatException('原生没有返回复习记录写入结果');
    return ReviewRecordResult.fromMap(Map<Object?, Object?>.from(raw));
  }

  ///
  /// 读取今日全部复习记录（原生已按 created_date = 今天 过滤）。
  ///
  /// 返回的是「今天写进数据库的全部记录」，含答错的那些，同一个单词可能出现
  /// 多条（一天练几遍就有几条）。去重与过滤交给调用方，与统计口径互不影响。
  @override
  Future<List<ReviewRecord>> getTodayRecords() async {
    final raw = await _channel.invokeListMethod<Object?>('getTodayReviewRecords');
    // 原生没有返回任何记录。
    if (raw == null) return const <ReviewRecord>[];
    final records = <ReviewRecord>[];
    for (final item in raw) {
      // 跳过类型不正确的元素，避免一条坏数据牵连整个列表。
      if (item is! Map) continue;
      records.add(ReviewRecord.fromMap(Map<Object?, Object?>.from(item)));
    }
    // 冻结列表，防止页面直接修改 Store 返回的顺序。
    return List<ReviewRecord>.unmodifiable(records);
  }

  ///
  /// 今日一次做对过的不同单词 id 列表（去重）。
  ///
  /// 首页「今日复习」明细用的就是它：今天有过「一气呵成」记录的那些单词。
  @override
  Future<List<int>> getTodayReviewWordIds() async {
    final records = await getTodayRecords();
    // Set 保持插入顺序同时去重。
    final ids = <int>{};
    for (final record in records) {
      // 只收「一次做对」的，与首页数字口径保持一致。
      if (record.isCorrect) ids.add(record.wordId);
    }
    return ids.toList();
  }

  ///
  /// 今日复习数量：今天「一次做对」过的不同单词数。
  ///
  /// 首页副标题「今日复习 X/目标」用的就是这个值。聚合用
  /// `COUNT(DISTINCT word_id)`，比把整天的记录都搬到 Dart 再去重更省。
  @override
  Future<int> getTodayReviewWordCount() async {
    final count = await _channel.invokeMethod<int>('getTodayReviewWordCount');
    // 原生空返回按 0 处理，避免首页统计中断。
    return count ?? 0;
  }

  ///
  /// 按天统计复习单词数（每天按单词去重），供趋势曲线与打卡热力图使用。
  ///
  /// 聚合（GROUP BY + COUNT(DISTINCT)）在原生 SQLite 完成，走 created_date
  /// 索引，本地库量级下为毫秒级；Dart 只拿到「日期 → 数量」的小表。
  /// 没有记录的日期不会出现在结果里，调用方按需补 0。
  @override
  Future<Map<String, int>> getDailyReviewCounts({DateTime? since}) async {
    // 起始日期格式化成原生一致的 yyyy-MM-dd；null 表示不限。
    final args = since == null
        ? null
        : <String, Object?>{'since': _dateKey(since)};
    final raw = await _channel.invokeListMethod<Object?>(
      'getDailyReviewCounts',
      args,
    );
    return _readCounts(raw, 'date');
  }

  ///
  /// 按月统计复习单词数（每月按单词去重），供趋势曲线「半年 / 一年」档使用。
  ///
  /// 按月去重才是正确口径：同一个词在同月的两天各拿下一次，月度只应算 1 次
  /// ——所以不能把每日去重数相加，而由 SQLite 直接按月 GROUP BY。
  @override
  Future<Map<String, int>> getMonthlyReviewCounts({DateTime? since}) async {
    // 起始月份格式化成原生一致的 yyyy-MM；null 表示不限。
    final args = since == null
        ? null
        : <String, Object?>{'since': _dateKey(since).substring(0, 7)};
    final raw = await _channel.invokeListMethod<Object?>(
      'getMonthlyReviewCounts',
      args,
    );
    return _readCounts(raw, 'month');
  }

  ///
  /// 把原生返回的 [{键: 值, count: n}] 列表整理成按键索引的 Map。
  Map<String, int> _readCounts(List<Object?>? raw, String keyField) {
    final counts = <String, int>{};
    if (raw == null) return counts;
    for (final item in raw) {
      // 跳过类型不正确的元素，避免异常数据牵连整个统计。
      if (item is! Map) continue;
      final key = item[keyField];
      final count = item['count'];
      if (key is! String || count is! int) continue;
      counts[key] = count;
    }
    return counts;
  }

  ///
  /// 把日期格式化成与原生一致的 yyyy-MM-dd 键。
  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
