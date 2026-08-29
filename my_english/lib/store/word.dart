// convert.dart 提供 jsonDecode/jsonEncode，用于解析导入文件与编码数据列表。
import 'dart:convert';

// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SQLite。
import 'package:flutter/services.dart';

// Word 模型位于全局 models 目录，任何页面都能直接复用。
import '../models/word.dart';

///
/// 选词层级：两层规则只有「难度」和「复习时间」谁排前面不同。
///
enum PickLayer {
  ///
  /// 第一层：难度降序打头，专挑最难的词。占每日目标的 40%。
  hard(1),

  ///
  /// 第二层：复习时间升序打头，专挑最久没碰的词。占剩下的 60%。
  ///
  /// 补词、巩固局选明日词等不需要难度分流的场景也用这一层。
  stale(2);

  ///
  /// 绑定原生约定的整数值。
  const PickLayer(this.code);

  ///
  /// 传给原生的整数值。
  final int code;
}

///
/// 单词 Store 接口：定义单词数据的读写契约，具体实现可以是本地或测试替身。
///
abstract interface class WordStore {
  ///
  /// 一次读取全部未删除单词（含它们的全部释义）。
  Future<List<Word>> getAll();

  ///
  /// 按 id 读取指定单词，用于复习后只回刷相关单词。
  Future<List<Word>> getByIds(List<int> ids);

  ///
  /// 按含义主键反查它们所属的单词。
  ///
  /// 看义选词的数据列表存的是含义主键，恢复会话时靠它把候选单词捞回来。
  Future<List<Word>> getByMeaningIds(List<int> meaningIds);

  ///
  /// 创建一个单词，并返回主键。
  Future<int> create(Word word);

  ///
  /// 更新已有单词；释义整体替换。
  Future<void> update(Word word);

  ///
  /// 软删除指定单词。
  Future<void> delete(int id);

  ///
  /// 回写一个单词的混淆词。
  Future<void> saveWordConfusions(int wordId, List<String> confusions);

  ///
  /// 回写一条释义的混淆含义。
  Future<void> saveMeaningConfusions(int meaningId, List<String> confusions);

  ///
  /// 回写一个单词的音节拆分。
  Future<void> saveWordSyllables(int wordId, List<String> syllables);

  ///
  /// 按复习规则挑单词，返回主键列表。
  ///
  /// [limit] 是要挑几个；[exclude] 是本轮已经选过、不能再选的主键。
  Future<List<int>> pickWords({
    required int limit,
    List<int> exclude,
    PickLayer layer,
  });

  ///
  /// 导入完整备份：先清空，再整库替换。
  Future<void> importData(Map<String, Object?> data);

  ///
  /// 导出完整备份；时间字段同时给出可读时间与精确毫秒。
  Future<Map<String, Object?>> exportData();

  ///
  /// 清空全部业务数据；设置与离线语音由调用方另行清空。
  Future<void> clearAll();
}

///
/// 本地单词 Store：全部读写都通过 MethodChannel 交给 Android 原生 SQLite。
///
/// App 只依赖本地数据，首次启动即为空库，单词由用户导入或手动添加。
///
class LocalWordStore implements WordStore {
  ///
  /// 允许测试注入原生通道；正式 App 使用默认值。
  const LocalWordStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用同一个实例。
  static const LocalWordStore instance = LocalWordStore();

  ///
  /// 通道名必须与 Android MainActivity 完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 读写数据用的原生通道。
  final MethodChannel _channel;

  @override
  Future<List<Word>> getAll() async {
    final rows = await _channel.invokeListMethod<Object?>('getAllWords');
    // null 不等于空列表，必须明确报告协议错误。
    if (rows == null) throw StateError('原生 SQLite 没有返回单词列表');
    return parseWordMaps(rows, sourceLabel: 'SQLite');
  }

  @override
  Future<List<Word>> getByIds(List<int> ids) async {
    // 空列表直接返回，避免原生拼出无意义的 IN ()。
    if (ids.isEmpty) return const <Word>[];
    final rows = await _channel.invokeListMethod<Object?>('getWordsByIds', ids);
    if (rows == null) return const <Word>[];
    return parseWordMaps(rows, sourceLabel: 'SQLite');
  }

  @override
  Future<List<Word>> getByMeaningIds(List<int> meaningIds) async {
    if (meaningIds.isEmpty) return const <Word>[];
    final rows = await _channel.invokeListMethod<Object?>(
      'getWordsByMeaningIds',
      meaningIds,
    );
    if (rows == null) return const <Word>[];
    return parseWordMaps(rows, sourceLabel: 'SQLite');
  }

  @override
  Future<int> create(Word word) async {
    final id = await _channel.invokeMethod<int>('createWord', word.toMap());
    // 原生必须返回自增主键，null 代表接口约定被破坏。
    if (id == null) throw StateError('SQLite 创建单词后没有返回主键');
    return id;
  }

  @override
  Future<void> update(Word word) async {
    // 更新必须能定位已有记录。
    if (word.id == null) {
      throw ArgumentError.value(null, 'word.id', '更新单词必须提供 id');
    }
    // 一个调用同时更新单词主体和释义，任何一步失败都会整体回滚。
    await _channel.invokeMethod<void>('updateWord', word.toMap());
  }

  @override
  Future<void> delete(int id) => _channel.invokeMethod<void>(
    'deleteWord',
    <String, Object?>{'id': id},
  );

  @override
  Future<void> saveWordConfusions(int wordId, List<String> confusions) =>
      _channel.invokeMethod<void>('saveWordConfusions', <String, Object?>{
        'wordId': wordId,
        'confusions': confusions,
      });

  @override
  Future<void> saveMeaningConfusions(int meaningId, List<String> confusions) =>
      _channel.invokeMethod<void>('saveMeaningConfusions', <String, Object?>{
        'meaningId': meaningId,
        'confusions': confusions,
      });

  @override
  Future<void> saveWordSyllables(int wordId, List<String> syllables) =>
      _channel.invokeMethod<void>('saveWordSyllables', <String, Object?>{
        'wordId': wordId,
        'syllables': syllables,
      });

  @override
  Future<List<int>> pickWords({
    required int limit,
    List<int> exclude = const <int>[],
    PickLayer layer = PickLayer.stale,
  }) async {
    // 目标非正数时没有可选单词，不必打扰原生。
    if (limit <= 0) return const <int>[];
    final ids = await _channel.invokeListMethod<int>('pickWords', <String, Object?>{
      'limit': limit,
      'exclude': exclude,
      'layer': layer.code,
    });
    return ids == null ? const <int>[] : List<int>.unmodifiable(ids);
  }

  @override
  Future<void> importData(Map<String, Object?> data) =>
      _channel.invokeMethod<void>('importData', data);

  @override
  Future<Map<String, Object?>> exportData() async {
    final payload = await _channel.invokeMapMethod<Object?, Object?>('exportData');
    if (payload == null) throw StateError('SQLite 没有返回导出数据');
    return <String, Object?>{
      for (final entry in payload.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  }

  @override
  Future<void> clearAll() => _channel.invokeMethod<void>('clearAll');
}

///
/// 解析导入用的 JSON 文本，返回可直接交给原生的备份对象。
///
/// 只认 2.0 结构：顶层必须是对象且带 `words` 数组。旧版备份请先用
/// `tools/migrate_v2.py` 转换成新格式——旧结构里的分组、音标、词形
/// 在新库里已经没有位置，硬塞只会得到一份半对半错的数据。
Map<String, Object?> parseBackupJson(String jsonText) {
  // jsonDecode 遇到语法错误时会抛 FormatException，首页会显示其位置。
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('导入文件顶层必须是对象');
  }
  if (decoded['words'] is! List) {
    throw const FormatException(
      '导入文件缺少 words 数组。若这是 1.x 的旧备份，'
      '请先用 tools/migrate_v2.py 转换成新格式。',
    );
  }
  return <String, Object?>{
    for (final entry in decoded.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

///
/// 把动态 Map 数组逐条转换成强类型 Word，保持原始数量和顺序。
List<Word> parseWordMaps(
  List<dynamic> rawWords, {
  required String sourceLabel,
}) {
  final parsed = <Word>[];
  // 带下标循环可以在错误信息中指出具体第几条记录。
  for (var index = 0; index < rawWords.length; index += 1) {
    final rawWord = rawWords[index];
    // 每个元素必须是 JSON object 或 MethodChannel Map。
    if (rawWord is! Map) {
      throw FormatException('$sourceLabel 第 ${index + 1} 个单词必须是对象');
    }
    try {
      parsed.add(Word.fromMap(Map<Object?, Object?>.from(rawWord)));
    } on FormatException catch (error) {
      // 将内部字段错误包装上文件位置。
      throw FormatException('$sourceLabel 第 ${index + 1} 个单词格式错误：${error.message}');
    }
  }
  // 冻结列表，防止页面直接改变 Store 内部顺序或数量。
  return List<Word>.unmodifiable(parsed);
}
