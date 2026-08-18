import 'package:flutter/services.dart';

import '../models/record.dart';

///
/// 默写记录 Store：记录写入与「今日复习」查询都走原生 word_store 通道。
///
/// 每次默写提交都会新增记录；复习时间和难度由原生数据库在同一事务更新。
///
class RecordStore {
  ///
  /// 允许测试注入原生通道；正式 App 使用默认值。
  ///
  /// @param  MethodChannel?  channel 测试专用通道；为空时使用正式通道。
  ///
  RecordStore({MethodChannel? channel})
    // 没有注入通道时使用 Android MainActivity 注册的固定名称。
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用实例。
  ///
  /// @var RecordStore
  ///
  static final RecordStore instance = RecordStore();

  ///
  /// 通道名必须与 Android MainActivity 完全一致。
  ///
  /// @var MethodChannel
  ///
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 读写记录用的原生通道。
  ///
  /// @var MethodChannel
  ///
  final MethodChannel _channel;

  ///
  /// 记录一次单词默写结果。
  ///
  /// 参数对应页面在「用户完成单词并点击下一题」时提交的本次数据：
  /// - [wordId]：哪个单词；
  /// - [isCorrect]：本次是否"一次做对"（中途没有选错过候选词）；
  /// - [wrongCount]：本次选错候选词的次数；
  /// - [hintCount]：本次点击提示的次数。
  ///
  /// 原生内部固定执行三件事，调用方无需关心：插入一条新记录、更新单词的
  /// 复习时间、按「错了 +1 / 最近 5 条连续全对 -1」调整难度。
  ///
  /// @param  int  wordId 本次完成的单词主键。
  /// @param  bool  isCorrect 本次是否没有选错候选项。
  /// @param  int  wrongCount 本次选错候选项的次数。
  /// @param  int  hintCount 本次点击提示的次数。
  /// @return `Future<void>` 原生事务完成后的异步结果。
  ///
  Future<void> addCompletion({
    required int wordId,
    required bool isCorrect,
    required int wrongCount,
    required int hintCount,
  }) async {
    // 参数 Map 类似 Laravel Service 接收的 DTO，一次性交给原生事务处理。
    await _channel.invokeMethod<void>('addDictationRecord', <String, Object?>{
      // 关联本次默写的单词。
      'wordId': wordId,
      // 零错误完成时为 true，中途选错过则为 false。
      'isCorrect': isCorrect,
      // 错误次数参与记录展示和难度调整。
      'wrongCount': wrongCount,
      // 提示次数只记录行为，不直接改变正误结果。
      'hintCount': hintCount,
    });
  }

  ///
  /// 读取今日全部默写记录（原生已按 created_date = 今天 过滤）。
  ///
  /// 返回的是「今天写进数据库的全部记录」，同一个单词可能出现多条
  /// （一天里练了几遍就有几条）。UI 想展示「今天复习了哪些词」时再用
  /// [getTodayReviewWordIds] 去重即可。
  ///
  /// @return `Future<List<Record>>` 今日全部默写记录的不可变列表。
  ///
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

  ///
  /// 今日复习的单词 id 列表（去重）。
  ///
  /// 「今日复习」本质就是：今天存在记录的那些单词。这里取出去重后的
  /// wordId，页面再凭 id 去词库里取拼写/释义展示。
  ///
  /// @return `Future<List<int>>` 按首次出现顺序去重后的单词主键。
  ///
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

  ///
  /// 今日复习数量：按天 + 按单词汇总（同一个词今天练几遍都只算 1）。
  ///
  /// 首页副标题「今日复习 X/目标」用的就是这个值。这里直接让原生用
  /// `COUNT(DISTINCT word_id)` 聚合出数字，比把整天的记录都搬到 Dart 再去重更省。
  ///
  /// @return `Future<int>` 今日完成过默写的不同单词数量。
  ///
  Future<int> getTodayReviewWordCount() async {
    // 原生返回一个整数；通道异常由调用方 try/catch 兜底。
    final count = await _channel.invokeMethod<int>('getTodayReviewWordCount');
    // 原生空返回按 0 处理，避免首页统计中断。
    return count ?? 0;
  }

  ///
  /// 按天统计复习单词数（每天按单词去重），供趋势曲线与打卡质量卡使用。
  ///
  /// 聚合（GROUP BY + COUNT(DISTINCT)）在原生 SQLite 完成，走
  /// created_date 索引，本地库量级下为毫秒级；Dart 只拿到
  /// 「日期 → 数量」的小表。没有记录的日期不会出现在结果里，
  /// 调用方按需补 0。
  ///
  /// @param  DateTime?  since 起始日期（含）；null 表示统计全部历史。
  /// @return `Future<Map<String, int>>` 键为 'yyyy-MM-dd'，值为当天去重单词数。
  ///
  Future<Map<String, int>> getDailyReviewCounts({DateTime? since}) async {
    // 起始日期格式化成原生一致的 'yyyy-MM-dd'；null 表示不限。
    final args = since == null
        ? null
        : <String, Object?>{
            'since': _dateKey(since),
          };
    // 原生返回 [{date: 'yyyy-MM-dd', count: n}]；null 按空列表处理。
    final raw = await _channel.invokeListMethod<Object?>(
      'getDailyReviewCounts',
      args,
    );
    // 组装成按日期索引的 Map，方便调用方 O(1) 查某一天。
    final counts = <String, int>{};
    if (raw == null) return counts;
    for (final item in raw) {
      // 跳过类型不正确的元素，避免原生异常数据牵连整个统计。
      if (item is! Map) continue;
      final date = item['date'];
      final count = item['count'];
      if (date is! String || count is! int) continue;
      counts[date] = count;
    }
    return counts;
  }

  ///
  /// 按月统计复习单词数（每月按单词去重），供趋势曲线"半年/一年"档使用。
  ///
  /// 按月去重才是正确口径：同一个词在同月的两天各复习一遍，月度只应
  /// 算 1 次——所以不能把每日去重数相加，而由 SQLite 直接按月 GROUP BY。
  ///
  /// @param  DateTime?  since 起始月份（含，取其年月部分）；null 表示全部历史。
  /// @return `Future<Map<String, int>>` 键为 'yyyy-MM'，值为当月去重单词数。
  ///
  Future<Map<String, int>> getMonthlyReviewCounts({DateTime? since}) async {
    // 起始月份格式化成原生一致的 'yyyy-MM'；null 表示不限。
    final args = since == null
        ? null
        : <String, Object?>{
            'since': '${since.year.toString().padLeft(4, '0')}-'
                '${since.month.toString().padLeft(2, '0')}',
          };
    // 原生返回 [{month: 'yyyy-MM', count: n}]；null 按空列表处理。
    final raw = await _channel.invokeListMethod<Object?>(
      'getMonthlyReviewCounts',
      args,
    );
    // 组装成按月份索引的 Map。
    final counts = <String, int>{};
    if (raw == null) return counts;
    for (final item in raw) {
      if (item is! Map) continue;
      final month = item['month'];
      final count = item['count'];
      if (month is! String || count is! int) continue;
      counts[month] = count;
    }
    return counts;
  }

  ///
  /// 把日期格式化成与原生一致的 'yyyy-MM-dd' 键。
  ///
  /// @param  DateTime  d
  /// @return String
  ///
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
