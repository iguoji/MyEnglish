// convert.dart 提供 jsonDecode，作用类似 PHP 的 json_decode。
import 'dart:convert';

// services.dart 提供 rootBundle 和 MethodChannel。
import 'package:flutter/services.dart';

// Word 模型位于全局 models 目录，任何页面都能直接复用。
import '../models/word.dart';

/// JSON 文本加载函数类型；测试可以注入假文件而无需依赖真机资源。
typedef WordJsonLoader = Future<String> Function();

/// Flutter 资源清单中明确没有 words.json 时使用的专用异常。
class WordJsonAssetNotFoundException implements Exception {
  /// 该异常没有动态字段，可以复用 const 实例。
  const WordJsonAssetNotFoundException();

  /// 输出给日志和调试器的清晰原因。
  @override
  String toString() => '安装包中不存在 ${LocalWordStore.jsonAssetPath}';
}

/// 当前进程选定的数据源；一旦选定，在 App 退出前不会切换。
enum WordDataSource {
  /// 工程内 JSON 存在，全部 CRUD 只操作内存。
  jsonMemory,

  /// JSON 不存在，全部 CRUD 交给 Android SQLite 持久化。
  sqlite,
}

/// 单词 Store 接口，类似小程序 Store 或 PHP 的 WordStoreInterface。
abstract interface class WordStore {
  /// 一次读取全部单词。
  Future<List<Word>> getAll();

  /// 创建一个 Word，并返回主键。
  Future<int> create(Word word);

  /// 更新已有 Word。
  Future<void> update(Word word);

  /// 删除指定 Word。
  Future<void> delete(int id);
}

/// 同时支持“JSON 只读文件 + 内存修改”和“SQLite 持久化”的本地 Store。
class LocalWordStore implements WordStore {
  /// 允许测试注入 JSON loader 和原生通道；正式 App 使用默认值。
  LocalWordStore({WordJsonLoader? jsonLoader, MethodChannel? channel})
    // 没有注入 loader 时读取 Flutter 打包资源。
    : _jsonLoader = jsonLoader ?? _loadBundledWordsJson,
      // 没有注入通道时使用 Android MainActivity 注册的固定名称。
      _channel = channel ?? _defaultChannel;

  /// App 默认复用同一个实例，使 JSON 模式下的内存修改在当前进程持续有效。
  static final LocalWordStore instance = LocalWordStore();

  /// JSON 在 Flutter 工程内的固定资源路径。
  static const String jsonAssetPath = 'assets/data/words.json';

  /// 通道名必须与 Android MainActivity 完全一致。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  /// 读取 JSON 文本的函数。
  final WordJsonLoader _jsonLoader;

  /// SQLite 模式调用的原生通道。
  final MethodChannel _channel;

  /// 非空表示本进程已经锁定数据源。
  WordDataSource? _activeSource;

  /// 防止多个页面同时首次访问时重复选择数据源。
  Future<void>? _sourceSelection;

  /// JSON 模式当前内存数据；后续 CRUD 只整体替换此列表，不写文件或数据库。
  List<Word> _memoryWords = const <Word>[];

  /// 暴露只读数据源状态，便于未来设置页提示“当前为 JSON 调试模式”。
  WordDataSource? get activeSource => _activeSource;

  /// 从已经登记到 pubspec 的 Flutter 资源中读取 JSON。
  static Future<String> _loadBundledWordsJson() async {
    // AssetManifest 类似小程序构建后的资源清单，可准确区分缺失文件与读取失败。
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    // 清单里确实没有目标文件时，才抛出允许回退 SQLite 的专用异常。
    if (!assetManifest.listAssets().contains(jsonAssetPath)) {
      throw const WordJsonAssetNotFoundException();
    }
    // 文件已登记后再读取；空文件、损坏或 I/O 错误都不能伪装成“不存在”。
    return rootBundle.loadString(jsonAssetPath);
  }

  /// 读取全部数据；首次调用会先确定本进程的数据源。
  @override
  Future<List<Word>> getAll() async {
    // create/update/delete 也复用该选择流程，保证它们不会在初始化前误写 SQLite。
    await _ensureSourceSelected();

    // JSON 存在时始终返回当前内存状态，不重新读文件覆盖临时修改。
    if (_activeSource == WordDataSource.jsonMemory) return _memoryWords;

    // 只有明确锁定 SQLite 后才调用原生查询。
    return _loadSqliteWords();
  }

  /// 新增 Word；JSON 模式追加到内存，SQLite 模式持久化。
  @override
  Future<int> create(Word word) async {
    // 即使调用方没有先 getAll，也必须先检查 JSON 是否存在。
    await _ensureSourceSelected();

    // JSON 模式绝不调用 MethodChannel 写接口。
    if (_activeSource == WordDataSource.jsonMemory) {
      // 新内存主键使用当前最大值加一，作用类似内存版 AUTO_INCREMENT。
      final generatedId =
          _memoryWords.fold<int>(0, (maximum, item) {
            // 没有 id 的旧数据不参与最大值比较。
            final itemId = item.id;
            // 返回当前更大的值。
            return itemId != null && itemId > maximum ? itemId : maximum;
          }) +
          1;
      // 统一补齐创建和更新时间。
      final now = DateTime.now();
      // 创建带内存主键的新对象。
      final createdWord = Word(
        id: generatedId,
        spelling: word.spelling,
        meanings: word.meanings,
        difficulty: word.difficulty,
        reviewedAt: word.reviewedAt,
        createdAt: word.createdAt ?? now,
        updatedAt: word.updatedAt ?? now,
        deletedAt: word.deletedAt,
      );
      // spelling 允许重复，所以直接追加新记录，不再按拼写合并。
      _memoryWords = List<Word>.unmodifiable(<Word>[
        ..._memoryWords,
        createdWord,
      ]);
      // 返回刚刚生成的内存主键。
      return generatedId;
    }

    // SQLite 模式把完整 Map 交给原生事务。
    final id = await _channel.invokeMethod<int>('createWord', word.toMap());
    // 原生必须返回自增主键，null 代表接口约定被破坏。
    if (id == null) throw StateError('SQLite 创建单词后没有返回主键');
    // 返回持久化主键。
    return id;
  }

  /// 更新 Word；数据源规则与 create 完全一致。
  @override
  Future<void> update(Word word) async {
    // 更新必须能定位已有记录。
    final id = word.id;
    // 缺少 id 时直接阻止操作。
    if (id == null) throw ArgumentError.value(id, 'word.id', '更新单词必须提供 id');

    // 先锁定数据源，禁止初始化前误写 SQLite。
    await _ensureSourceSelected();

    // JSON 模式只替换内存数据。
    if (_activeSource == WordDataSource.jsonMemory) {
      // 确认目标确实存在。
      if (!_memoryWords.any((item) => item.id == id)) {
        throw StateError('找不到要更新的内存单词 id=$id');
      }
      // 根据唯一主键 id 替换目标；相同 spelling 的其他 Word 保持不变。
      _memoryWords = List<Word>.unmodifiable(
        _memoryWords.map((item) => item.id == id ? word : item).toList(),
      );
      // 明确结束，下面的 SQLite 分支不会执行。
      return;
    }

    // SQLite 模式执行原生持久化事务。
    await _channel.invokeMethod<void>('updateWord', word.toMap());
  }

  /// 删除 Word；JSON 模式移出内存，SQLite 模式执行软删除。
  @override
  Future<void> delete(int id) async {
    // 同样先检查 JSON，避免首次动作就是删除时误写磁盘。
    await _ensureSourceSelected();

    // JSON 模式仅过滤当前 List。
    if (_activeSource == WordDataSource.jsonMemory) {
      // 生成不包含目标 id 的新列表。
      final remainingWords = _memoryWords
          .where((word) => word.id != id)
          .toList(growable: false);
      // 数量不变表示调用方给了不存在的 id。
      if (remainingWords.length == _memoryWords.length) {
        throw StateError('找不到要删除的内存单词 id=$id');
      }
      // 冻结新内存状态；JSON 文件本身不会发生变化。
      _memoryWords = List<Word>.unmodifiable(remainingWords);
      // 禁止继续落入 SQLite 分支。
      return;
    }

    // SQLite 模式通过 deleted_at 软删除。
    await _channel.invokeMethod<void>('deleteWord', <String, Object?>{
      'id': id,
    });
  }

  /// 确保整个进程只进行一次数据源选择。
  Future<void> _ensureSourceSelected() async {
    // 已经选定时立即返回。
    if (_activeSource != null) return;
    // 有其他调用正在选择时，共享同一个 Future。
    final runningSelection = _sourceSelection;
    // 等待正在执行的选择过程。
    if (runningSelection != null) return runningSelection;

    // 启动新的选择过程并保存引用。
    final newSelection = _selectSource();
    // 后来的调用会等待它。
    _sourceSelection = newSelection;
    try {
      // 等待 JSON 加载、解析或 SQLite 回退判断完成。
      await newSelection;
    } catch (_) {
      // 失败后允许用户点击“重新加载”再次尝试。
      _sourceSelection = null;
      // 保留原始异常和堆栈交给首页显示。
      rethrow;
    }
  }

  /// 严格执行“JSON 存在则内存，否则 SQLite”的选择规则。
  Future<void> _selectSource() async {
    // 先单独读取文本，以便只捕获“资源清单明确缺失”的专用异常。
    late final String jsonText;
    try {
      // 文件存在时取得完整文本。
      jsonText = await _jsonLoader();
    } on WordJsonAssetNotFoundException {
      // Flutter 资源清单中没有该文件时，才允许启用持久化数据。
      _activeSource = WordDataSource.sqlite;
      // 结束选择；此处不会读取或改写 JSON。
      return;
    }

    // 文件读到了以后，任何 JSON 格式错误都必须报告，不能退回旧 SQLite 掩盖问题。
    final parsedWords = _parseJsonWords(jsonText);
    // 保存保持原始数量与顺序的只读内存数据。
    _memoryWords = parsedWords;
    // 最后才锁定 JSON 模式，确保半解析状态不会对外可见。
    _activeSource = WordDataSource.jsonMemory;
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

/// 解析工程资源 JSON，并为首页错误区补充数组位置。
List<Word> _parseJsonWords(String jsonText) {
  // jsonDecode 遇到语法错误时会抛 FormatException，首页会显示其 offset。
  final decoded = jsonDecode(jsonText);
  // 顶层结构必须是 Word 数组。
  if (decoded is! List) {
    throw const FormatException('assets/data/words.json 顶层必须是数组');
  }
  // 复用 Map 转模型流程。
  return _parseWordMaps(decoded, sourceLabel: LocalWordStore.jsonAssetPath);
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
