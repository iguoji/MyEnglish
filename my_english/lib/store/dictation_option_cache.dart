// services.dart 提供 MethodChannel，让 Dart 调用 Android SQLite 候选项缓存。
import 'package:flutter/services.dart';

///
/// 默写候选项缓存 Store：按一道具体小题的稳定 key 读写三个干扰项。
///
/// 这里不缓存正确答案，因为正确答案始终来自最新 Word/Meaning 模型；缓存只负责
/// 固定用户反复看到的干扰项，作用类似 PHP 项目里以 question_key 为键的缓存表。
///
class DictationOptionCacheStore {
  ///
  /// 允许 Widget 测试注入独立通道；正式 App 使用 word_store 通道。
  ///
  /// @param  MethodChannel?  channel
  ///
  const DictationOptionCacheStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// 正式页面复用同一个无状态 Store。
  ///
  /// @var DictationOptionCacheStore
  ///
  static const DictationOptionCacheStore instance = DictationOptionCacheStore();

  ///
  /// 通道名与 WordStore、RecordStore 共用，原生在同一 SQLite 事务体系内管理。
  ///
  /// @var MethodChannel
  ///
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 实际发送请求的原生通道。
  ///
  /// @var MethodChannel
  ///
  final MethodChannel _channel;

  ///
  /// 读取一道题已保存的干扰项；没有缓存时返回 null。
  ///
  /// @param  String  cacheKey
  /// @return `Future<List<String>?>`
  ///
  Future<List<String>?> getDistractors(String cacheKey) async {
    // 原生返回 List<String>?；Object? 泛型让这里能主动过滤损坏的动态值。
    final rawItems = await _channel.invokeListMethod<Object?>(
      'getDictationOptionCache',
      <String, Object?>{'cacheKey': cacheKey},
    );
    // null 明确表示这道题从未生成过缓存。
    if (rawItems == null) return null;
    // 只保留非空字符串，并保持 SQLite JSON 中的原始顺序。
    final distractors = <String>[];
    for (final rawItem in rawItems) {
      // 非字符串说明缓存损坏，直接忽略该项。
      if (rawItem is! String) continue;
      // 去掉意外空白，空字符串不可成为候选按钮。
      final value = rawItem.trim();
      if (value.isEmpty) continue;
      // 同一文本只保留第一次出现的位置。
      if (!distractors.contains(value)) distractors.add(value);
    }
    // 返回不可修改列表，页面只能整体替换缓存，不能原地篡改。
    return List<String>.unmodifiable(distractors);
  }

  ///
  /// 保存一道题当前使用的三个干扰项，已有 key 会被整体覆盖。
  ///
  /// @param  String  cacheKey
  /// @param  int?  wordId
  /// @param  `List<String>`  distractors
  /// @return `Future<void>`
  ///
  Future<void> saveDistractors({
    required String cacheKey,
    required int? wordId,
    required List<String> distractors,
  }) async {
    // MethodChannel Map 类似 PHP 调原生接口时提交的关联数组。
    await _channel.invokeMethod<void>(
      'saveDictationOptionCache',
      <String, Object?>{
        'cacheKey': cacheKey,
        // 测试或尚未落库的 Word 允许 id 为空，正式词库会携带真实外键。
        'wordId': wordId,
        // 复制列表，避免异步发送期间调用方又替换原集合。
        'distractors': List<String>.from(distractors),
      },
    );
  }
}
