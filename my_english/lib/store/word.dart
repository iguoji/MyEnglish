// convert.dart 提供 jsonDecode，作用类似 PHP 的 json_decode。
import 'dart:convert';

// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SQLite。
import 'package:flutter/services.dart';

// Word 模型位于全局 models 目录，任何页面都能直接复用。
import '../models/word.dart';

/// 单词 Store 接口，类似小程序 Store 或 PHP 的 WordStoreInterface。
///
/// 现在数据只来自本地持久化（Android 原生 SQLite），接口方法也围绕
/// 「读取 / 增删改 / 整库导入 / 整库清空」这一组持久化操作设计。
abstract interface class WordStore {
  /// 一次读取全部未删除单词。
  Future<List<Word>> getAll();

  /// 按 id 读取指定单词（含 Meaning 与分组），用于复习后只回刷相关单词。
  Future<List<Word>> getByIds(List<int> ids);

  /// 创建一个 Word，并返回主键。
  Future<int> create(Word word);

  /// 更新已有 Word。
  Future<void> update(Word word);

  /// 删除指定 Word（软删除）。
  Future<void> delete(int id);

  /// 批量导入：先清空本地全部单词，再写入给定列表，保证导入即整库替换。
  ///
  /// 适用于导入原始 words.json（无分组信息，导入后单词回到未分组）。
  Future<void> importWords(List<Word> words);

  /// 导入完整备份（含 groups/words/members），由原生在事务内整库替换。
  ///
  /// 适用于导入本 App 导出的备份，分组与成员关系一并恢复。
  Future<void> importData(Map<String, Object?> data);

  /// 清空本地全部单词数据（单词、释义、分组与成员）。
  Future<void> clearAll();
}

/// 本地单词 Store：全部 CRUD 都通过 MethodChannel 交给 Android 原生 SQLite 持久化。
///
/// App 只依赖本地持久化数据，首次启动即为空库，单词由用户导入或手动添加；
/// 单词的 JSON 仅在用户主动执行「导入 / 导出」时出现，不参与默认加载。
class LocalWordStore implements WordStore {
  /// 允许测试注入原生通道；正式 App 使用默认值。
  LocalWordStore({MethodChannel? channel})
    // 没有注入通道时使用 Android MainActivity 注册的固定名称。
    : _channel = channel ?? _defaultChannel;

  /// App 默认复用同一个实例。
  static final LocalWordStore instance = LocalWordStore();

  /// 通道名必须与 Android MainActivity 完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  /// SQLite 模式调用的原生通道。
  final MethodChannel _channel;

  /// 读取全部数据，永远来自原生 SQLite。
  @override
  Future<List<Word>> getAll() async {
    // 直接走原生查询，不再有「JSON 内存」分支。
    return _loadSqliteWords();
  }

  /// 只回刷本次复习涉及的单词，避免重新加载整库。
  @override
  Future<List<Word>> getByIds(List<int> ids) async {
    // 空列表直接返回，避免原生拼出无意义的 IN ()。
    if (ids.isEmpty) return const <Word>[];
    // 把 id 列表交给原生做 IN 查询，复用与 getAll 相同的解析。
    final rawWords = await _channel.invokeListMethod<Object?>(
      'getWordsByIds',
      ids,
    );
    // 原生没有返回任何单词。
    if (rawWords == null) return const <Word>[];
    // 复用与 getAll 一致的逐条解析，转成强类型 Word。
    return _parseWordMaps(rawWords, sourceLabel: 'SQLite');
  }

  /// 新增 Word；主体、释义和分组关系交给同一个原生事务，返回自增主键。
  @override
  Future<int> create(Word word) async {
    // 把模型字段转成原生通道可传输的 Map。
    final id = await _channel.invokeMethod<int>('createWord', word.toMap());
    // 原生必须返回自增主键，null 代表接口约定被破坏。
    if (id == null) throw StateError('SQLite 创建单词后没有返回主键');
    // 返回持久化主键。
    return id;
  }

  /// 更新 Word；主体、释义和分组关系由原生在同一个事务内整体替换。
  @override
  Future<void> update(Word word) async {
    // 更新必须能定位已有记录。
    final id = word.id;
    // 缺少 id 时直接阻止操作。
    if (id == null) {
      throw ArgumentError.value(id, 'word.id', '更新单词必须提供 id');
    }
    // 一个调用同时更新单词主体、释义和分组关系，任何一步失败都会整体回滚。
    await _channel.invokeMethod<void>('updateWord', word.toMap());
  }

  /// 删除 Word；通过 deleted_at 软删除。
  @override
  Future<void> delete(int id) async {
    // 调用原生软删除，参数只带主键。
    await _channel.invokeMethod<void>('deleteWord', <String, Object?>{
      'id': id,
    });
  }

  /// 批量导入：清空旧数据后整库替换写入。
  @override
  Future<void> importWords(List<Word> words) async {
    // 把每条 Word 转成原生可接收的 Map 列表。
    final payload = words.map((word) => word.toMap()).toList();
    // 原生在事务内先清空再批量插入。
    await _channel.invokeMethod<void>('importWords', payload);
  }

  /// 清空本地全部单词、释义、分组、记录、默写候选缓存与学习会话。
  @override
  Future<void> clearAll() async {
    // 原生统一删除全部业务表记录，候选缓存也在同一清理入口中删除。
    await _channel.invokeMethod<void>('clearAllWords');
  }

  /// 导入完整备份（含 groups/words/members），由原生在事务内整库替换。
  @override
  Future<void> importData(Map<String, Object?> data) async {
    // 原生 importData 负责重建四张表并映射外键，保证分组关系不丢失。
    await _channel.invokeMethod<void>('importData', data);
  }

  /// 从 Android SQLite 一次读取全部 Word/Meaning。
  Future<List<Word>> _loadSqliteWords() async {
    // Android 返回普通 List<Map>；原生 null 属于接口错误。
    final rawWords = await _channel.invokeListMethod<Object?>('getAllWords');
    // null 不等于空列表，必须明确报告。
    if (rawWords == null) throw StateError('原生 SQLite 没有返回单词列表');
    // 转成模型；spelling 可重复，所以每条数据库记录都会被保留。
    return _parseWordMaps(rawWords, sourceLabel: 'SQLite');
  }
}

/// 解析导入用的 JSON 文本，返回强类型 Word 列表。
///
/// 兼容两种形态，方便「导入 words.json 原始词表」与「导入本 App 导出的备份」：
/// 1) 顶层是数组：直接当作单词列表；
/// 2) 顶层是对象且含 `words` 字段：取其中的数组（导出备份的结构）。
/// 每条记录里不存在的字段由 [Word.fromMap] 自然忽略，多余字段也不影响解析。
List<Word> parseWordsFromJsonText(String jsonText) {
  // jsonDecode 遇到语法错误时会抛 FormatException，首页会显示其 offset。
  final decoded = jsonDecode(jsonText);
  // 顶层数组：原始 words.json 形态。
  if (decoded is List) {
    return _parseWordMaps(decoded, sourceLabel: '导入文件');
  }
  // 顶层对象且含 words 数组：本 App 导出备份形态。
  if (decoded is Map && decoded['words'] is List) {
    return _parseWordMaps(decoded['words'] as List, sourceLabel: '导入文件');
  }
  // 既不是数组也不是含 words 的对象，明确报错。
  throw const FormatException('导入文件顶层必须是单词数组或包含 words 数组的对象');
}

/// 把动态 Map 数组逐条转换成强类型 Word，保持原始数量和顺序。
List<Word> _parseWordMaps(
  List<dynamic> rawWords, {
  required String sourceLabel,
}) {
  // 保存逐条转换结果。
  final parsedWords = <Word>[];
  // 带下标循环可以在错误信息中指出具体第几条记录。
  for (var index = 0; index < rawWords.length; index += 1) {
    // 读取当前原始对象。
    final rawWord = rawWords[index];
    // 每个元素必须是 JSON object 或 MethodChannel Map。
    if (rawWord is! Map) {
      throw FormatException('$sourceLabel 第 ${index + 1} 个单词必须是对象');
    }
    try {
      // Map.from 将动态键值收窄成 Word.fromMap 的输入类型。
      final wordMap = Map<Object?, Object?>.from(rawWord);
      // 转换并追加。
      parsedWords.add(Word.fromMap(wordMap));
    } on FormatException catch (error) {
      // 将内部字段错误包装上文件位置。
      throw FormatException(
        '$sourceLabel 第 ${index + 1} 个单词格式错误：${error.message}',
      );
    }
  }
  // 冻结列表，防止页面直接改变 Store 内部顺序或数量。
  return List<Word>.unmodifiable(parsedWords);
}
