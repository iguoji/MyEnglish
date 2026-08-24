// services.dart 提供 MethodChannel，让 Dart 调用 Android SQLite 候选项缓存。
import 'package:flutter/services.dart';

///
/// 一道听音辨义小题已经固定下来的候选缓存。
///
/// 正确答案文本始终读取最新 Word/Meaning 模型，因此这里只保存三个干扰项及
/// 正确答案的显示下标。两部分组合后即可还原原来的四个候选及完整顺序。
///
class ListeningMeaningOptionCacheEntry {
  ///
  /// 创建一条不可变的候选缓存。
  const ListeningMeaningOptionCacheEntry({
    required this.distractors,
    required this.correctIndex,
  });

  ///
  /// 三个错误候选，顺序等同于从四个可见按钮中移除正确答案后的剩余顺序。
  final List<String> distractors;

  ///
  /// 正确答案在四个按钮中的下标；null 表示版本 8 之前保存的旧缓存尚无位置。
  final int? correctIndex;
}

///
/// 听音辨义候选项缓存 Store：按一道具体小题的稳定 key 读写候选名字和位置。
///
/// 以 question_key 为主键的一张缓存表；读取时会清理空值和重复值，
/// 页面再结合当前正确答案完成最终四选一校验。
///
class ListeningMeaningOptionCacheStore {
  ///
  /// 允许 Widget 测试注入独立通道；正式 App 使用 word_store 通道。
  const ListeningMeaningOptionCacheStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// 正式页面复用同一个无状态 Store。
  static const ListeningMeaningOptionCacheStore instance = ListeningMeaningOptionCacheStore();

  ///
  /// 通道名与 WordStore、RecordStore 共用，原生在同一 SQLite 事务体系内管理。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 实际发送请求的原生通道。
  final MethodChannel _channel;

  ///
  /// 读取一道题已保存的候选名字与正确答案位置；没有缓存时返回 null。
  Future<ListeningMeaningOptionCacheEntry?> getOptions(String cacheKey) async {
    // 原生返回 Map；Object? 泛型让这里能主动过滤损坏的动态值。
    final rawCache = await _channel.invokeMapMethod<Object?, Object?>(
      'getListeningMeaningOptionCache',
      <String, Object?>{'cacheKey': cacheKey},
    );
    // null 明确表示这道题从未生成过缓存。
    if (rawCache == null) return null;
    // distractors 类型不正确时按空列表处理，页面会判为损坏并覆盖成标准数据。
    final rawItems = rawCache['distractors'];
    // 只保留非空字符串，并保持 SQLite JSON 中的原始顺序。
    final distractors = <String>[];
    // 英文候选忽略大小写判重，中文调用 toLowerCase 后不会发生变化。
    final normalizedDistractors = <String>{};
    if (rawItems is List) {
      for (final rawItem in rawItems) {
        // 非字符串说明缓存损坏，直接忽略该项。
        if (rawItem is! String) continue;
        // 去掉意外空白，空字符串不可成为候选按钮。
        final value = rawItem.trim();
        if (value.isEmpty) continue;
        // 同一文本只保留第一次出现的位置，Ability/ability 也视为重复。
        if (normalizedDistractors.add(value.toLowerCase())) {
          distractors.add(value);
        }
      }
    }
    // 历史版本没有 correctIndex；非法值也按旧缓存处理，由页面选择位置后自动修复。
    final rawCorrectIndex = rawCache['correctIndex'];
    final correctIndex =
        rawCorrectIndex is int && rawCorrectIndex >= 0 && rawCorrectIndex < 4
        ? rawCorrectIndex
        : null;
    // 返回不可修改对象，页面只能整体替换缓存，不能原地篡改。
    return ListeningMeaningOptionCacheEntry(
      distractors: List<String>.unmodifiable(distractors),
      correctIndex: correctIndex,
    );
  }

  ///
  /// 保存一道题当前使用的三个干扰项及正确答案位置，已有 key 会被整体覆盖。
  Future<void> saveOptions({
    required String cacheKey,
    required int? wordId,
    required List<String> distractors,
    required int correctIndex,
  }) async {
    // 页面标准结构只能有三个干扰项，提前拒绝不完整数据，避免污染 SQLite。
    if (distractors.length != 3) {
      throw ArgumentError.value(distractors, 'distractors', '必须恰好包含三个候选');
    }
    // 保存前统一去除首尾空白，同时保留用户真正看到的大小写和原始顺序。
    final cleanedDistractors = distractors
        .map((value) => value.trim())
        .toList(growable: false);
    // 空文本和大小写意义上的重复文本都不能进入原生缓存。
    final normalizedDistractors = cleanedDistractors
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toSet();
    if (normalizedDistractors.length != 3) {
      throw ArgumentError.value(distractors, 'distractors', '候选不能为空或重复');
    }
    // 四个按钮的合法下标只有 0、1、2、3。
    if (correctIndex < 0 || correctIndex >= 4) {
      throw RangeError.range(correctIndex, 0, 3, 'correctIndex');
    }
    // 组装本次调用需要传给原生的参数集合。
    await _channel.invokeMethod<void>(
      'saveListeningMeaningOptionCache',
      <String, Object?>{
        'cacheKey': cacheKey,
        // 测试或尚未落库的 Word 允许 id 为空，正式词库会携带真实外键。
        'wordId': wordId,
        // 复制列表，避免异步发送期间调用方又替换原集合。
        'distractors': cleanedDistractors,
        // 保存正确答案位置，下一次进入不再重新打乱。
        'correctIndex': correctIndex,
      },
    );
  }
}
