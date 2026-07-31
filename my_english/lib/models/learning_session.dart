import 'dart:convert';

/// 学习会话类型；每一种学习方式在本地最多保留一条未完成记录。
enum LearningSessionType {
  /// 随身听播放进度。
  listening('listening'),

  /// 单词默写答题进度。
  dictation('dictation');

  /// 绑定不受枚举重命名影响的数据库键。
  const LearningSessionType(this.storageKey);

  /// 写入数据库主键的文本，不依赖 Dart 枚举名称自动转换。
  final String storageKey;

  /// 从数据库键恢复会话类型。
  static LearningSessionType fromStorageKey(String value) {
    return values.firstWhere(
      (type) => type.storageKey == value,
      orElse: () => throw FormatException('未知学习会话类型：$value'),
    );
  }
}

/// 一次未完成的学习会话。
///
/// [wordIds] 固定进入页面时的单词顺序，[state] 保存不同页面自己的进度字段。
/// 两者分开存储后，首页只需读取单词 id 就能判断“继续”入口是否可用，页面再解释状态。
class LearningSession {
  const LearningSession({
    required this.type,
    required this.wordIds,
    required this.state,
    this.updatedAt,
  });

  /// 随身听或默写。
  final LearningSessionType type;

  /// 进入学习页时的单词主键快照，顺序就是用户当时看到的学习顺序。
  final List<int> wordIds;

  /// 页面自行维护的进度快照。
  final Map<String, Object?> state;

  /// 原生保存时间，仅用于诊断和未来展示，不参与当前恢复逻辑。
  final DateTime? updatedAt;

  /// 把 MethodChannel 返回的一行 SQLite 数据转换成模型。
  factory LearningSession.fromMap(Map<Object?, Object?> map) {
    final rawType = map['session_type']?.toString();
    if (rawType == null || rawType.isEmpty) {
      throw const FormatException('学习会话缺少 session_type');
    }

    final decodedWordIds = jsonDecode(map['word_ids_json']?.toString() ?? '[]');
    if (decodedWordIds is! List) {
      throw const FormatException('学习会话 word_ids_json 必须是数组');
    }
    final wordIds = <int>[
      for (final value in decodedWordIds)
        if (value is num)
          value.toInt()
        else
          throw const FormatException('学习会话单词 id 必须是数字'),
    ];

    final decodedState = jsonDecode(map['state_json']?.toString() ?? '{}');
    if (decodedState is! Map) {
      throw const FormatException('学习会话 state_json 必须是对象');
    }
    final state = <String, Object?>{
      for (final entry in decodedState.entries)
        entry.key.toString(): entry.value,
    };

    final rawUpdatedAt = map['updated_at'];
    final updatedAt = rawUpdatedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(rawUpdatedAt.toInt())
        : null;

    return LearningSession(
      type: LearningSessionType.fromStorageKey(rawType),
      wordIds: List<int>.unmodifiable(wordIds),
      state: Map<String, Object?>.unmodifiable(state),
      updatedAt: updatedAt,
    );
  }

  /// 转成 MethodChannel 可传输的数据。
  Map<String, Object?> toMap() => <String, Object?>{
    'session_type': type.storageKey,
    'word_ids_json': jsonEncode(wordIds),
    'state_json': jsonEncode(state),
  };
}

/// 从会话快照读取整数，字段缺失或类型错误时使用页面默认值。
int readLearningSessionInt(Object? value, {required int fallback}) {
  return value is num ? value.toInt() : fallback;
}
