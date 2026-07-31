import 'dart:convert';

/// 学习会话类型；每一种学习方式在本地最多保留一条未完成记录。
enum LearningSessionType {
  /// 随身听播放进度。
  listening('listening'),

  /// 单词默写答题进度。
  dictation('dictation');

  /// 绑定不受枚举重命名影响的数据库键。
  ///
  /// @param `String` storageKey SQLite 使用的稳定主键文本。
  const LearningSessionType(this.storageKey);

  /// 写入数据库主键的文本，不依赖 Dart 枚举名称自动转换。
  ///
  /// @var `String`
  final String storageKey;

  /// 从数据库键恢复会话类型。
  ///
  /// @param `String` value SQLite 返回的 session_type。
  /// @return `LearningSessionType` 匹配的学习会话类型。
  static LearningSessionType fromStorageKey(String value) {
    // values 对应 PHP 枚举的 cases()，从全部合法类型中查找稳定存储键。
    return values.firstWhere(
      // 找到 storageKey 完全一致的枚举项。
      (type) => type.storageKey == value,
      // 未知值说明数据库记录损坏，主动抛错而不是误用其他学习模式。
      orElse: () => throw FormatException('未知学习会话类型：$value'),
    );
  }
}

/// 一次未完成的学习会话。
///
/// [wordIds] 固定进入页面时的单词顺序，[state] 保存不同页面自己的进度字段。
/// 两者分开存储后，首页只需读取单词 id 就能判断“继续”入口是否可用，页面再解释状态。
class LearningSession {
  /// 创建一条可恢复的学习会话快照。
  ///
  /// @param `LearningSessionType` type 学习模式。
  /// @param `List<int>` wordIds 固定顺序的单词主键。
  /// @param `Map<String, Object?>` state 页面自己的进度数据。
  /// @param `DateTime?` updatedAt 原生数据库最后更新时间。
  const LearningSession({
    required this.type,
    required this.wordIds,
    required this.state,
    this.updatedAt,
  });

  /// 随身听或默写。
  ///
  /// @var `LearningSessionType`
  final LearningSessionType type;

  /// 进入学习页时的单词主键快照，顺序就是用户当时看到的学习顺序。
  ///
  /// @var `List<int>`
  final List<int> wordIds;

  /// 页面自行维护的进度快照。
  ///
  /// @var `Map<String, Object?>`
  final Map<String, Object?> state;

  /// 原生保存时间，仅用于诊断和未来展示，不参与当前恢复逻辑。
  ///
  /// @var `DateTime?`
  final DateTime? updatedAt;

  /// 把 MethodChannel 返回的一行 SQLite 数据转换成模型。
  ///
  /// @param `Map<Object?, Object?>` map 原生通道返回的一行会话数据。
  /// @return `LearningSession` 完成校验且不可变的会话快照。
  factory LearningSession.fromMap(Map<Object?, Object?> map) {
    // 先读取会话类型，它相当于 Laravel 模型的主键和类型字段。
    final rawType = map['session_type']?.toString();
    // 缺少类型时无法判断由哪个页面解释 state，必须中止恢复。
    if (rawType == null || rawType.isEmpty) {
      throw const FormatException('学习会话缺少 session_type');
    }

    // SQLite 保存的是 JSON 文本，这里还原进入页面时固定的单词数组。
    final decodedWordIds = jsonDecode(map['word_ids_json']?.toString() ?? '[]');
    // 单词主键必须使用数组承载，防止字符串被错误地逐字符处理。
    if (decodedWordIds is! List) {
      throw const FormatException('学习会话 word_ids_json 必须是数组');
    }
    // 列表推导相当于 PHP foreach：逐项校验并转换原生数字类型。
    final wordIds = <int>[
      for (final value in decodedWordIds)
        if (value is num)
          // MethodChannel Long 和 JSON 数字统一转换成 Dart int。
          value.toInt()
        else
          // 任一主键无效都会让整个恢复列表不可信，因此直接抛出异常。
          throw const FormatException('学习会话单词 id 必须是数字'),
    ];

    // 页面状态同样由 JSON 文本还原，结构类似小程序 Page.data。
    final decodedState = jsonDecode(map['state_json']?.toString() ?? '{}');
    // 页面状态必须是键值对象，数组和标量都无法按字段名恢复。
    if (decodedState is! Map) {
      throw const FormatException('学习会话 state_json 必须是对象');
    }
    // 将动态键统一转成字符串，得到页面可安全按字段名读取的 Map。
    final state = <String, Object?>{
      for (final entry in decodedState.entries)
        entry.key.toString(): entry.value,
    };

    // 原生更新时间使用毫秒时间戳；旧记录缺失该字段时保持 null。
    final rawUpdatedAt = map['updated_at'];
    final updatedAt = rawUpdatedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(rawUpdatedAt.toInt())
        : null;

    // 列表与状态 Map 都冻结，避免页面修改已读取的历史快照。
    return LearningSession(
      type: LearningSessionType.fromStorageKey(rawType),
      wordIds: List<int>.unmodifiable(wordIds),
      state: Map<String, Object?>.unmodifiable(state),
      updatedAt: updatedAt,
    );
  }

  /// 转成 MethodChannel 可传输的数据。
  ///
  /// @return `Map<String, Object?>` 原生 SQLite Store 需要的字段集合。
  Map<String, Object?> toMap() => <String, Object?>{
    // 同类型会话使用同一个主键，新快照会覆盖旧快照。
    'session_type': type.storageKey,
    // JSON 数组保留用户进入页面时的单词顺序。
    'word_ids_json': jsonEncode(wordIds),
    // 页面状态编码成 JSON 对象后由 SQLite 作为文本保存。
    'state_json': jsonEncode(state),
  };
}

/// 从会话快照读取整数，字段缺失或类型错误时使用页面默认值。
///
/// @param `Object?` value JSON 状态中的动态字段值。
/// @param `int` fallback 字段不可用时采用的页面默认值。
/// @return `int` 可供页面边界校验的整数。
int readLearningSessionInt(Object? value, {required int fallback}) {
  // JSON 数字统一转成 int；坏数据按小程序 data 默认值继续运行页面。
  return value is num ? value.toInt() : fallback;
}
