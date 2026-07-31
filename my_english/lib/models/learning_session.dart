// convert.dart 提供 JSON 编解码，让可变的页面进度可以作为结构化文本存入 SQLite。
import 'dart:convert';

/// 学习会话类型；每一种学习方式在本地最多保留一条未完成记录。
enum LearningSessionType {
  /// 随身听播放进度。
  listening('listening'),

  /// 单词默写答题进度。
  dictation('dictation');

  /// 创建枚举时同时保存 SQLite 使用的稳定字符串。
  const LearningSessionType(this.storageKey);

  /// 写入数据库主键的文本，不依赖 Dart 枚举名称自动转换。
  final String storageKey;

  /// 把 SQLite 返回的文本还原成枚举，未知值主动报错以暴露坏数据。
  static LearningSessionType fromStorageKey(String value) {
    // values 相当于 PHP 中枚举 cases()，逐个匹配稳定存储值。
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
  /// 创建一条强类型会话记录。
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

  /// 页面进度；字段由对应页面维护，类似小程序 Page.data 的持久化快照。
  final Map<String, Object?> state;

  /// 原生保存时间，仅用于诊断和未来展示，不参与当前恢复逻辑。
  final DateTime? updatedAt;

  /// 把 MethodChannel 返回的一行 SQLite 数据转换成模型。
  factory LearningSession.fromMap(Map<Object?, Object?> map) {
    // 类型字段必须存在，避免把坏数据误当成另一种学习方式。
    final rawType = map['session_type']?.toString();
    if (rawType == null || rawType.isEmpty) {
      throw const FormatException('学习会话缺少 session_type');
    }

    // 原生只传 JSON 字符串，Dart 负责恢复数组结构。
    final decodedWordIds = jsonDecode(map['word_ids_json']?.toString() ?? '[]');
    if (decodedWordIds is! List) {
      throw const FormatException('学习会话 word_ids_json 必须是数组');
    }
    // 每个 id 都必须是数字；SQLite 主键统一转成 Dart int。
    final wordIds = <int>[
      for (final value in decodedWordIds)
        if (value is num)
          value.toInt()
        else
          throw const FormatException('学习会话单词 id 必须是数字'),
    ];

    // 页面状态同样以 JSON object 保存，不能接受数组或普通字符串。
    final decodedState = jsonDecode(map['state_json']?.toString() ?? '{}');
    if (decodedState is! Map) {
      throw const FormatException('学习会话 state_json 必须是对象');
    }
    // Map.from 把 jsonDecode 的动态键收窄成页面可安全读取的字符串键。
    final state = <String, Object?>{
      for (final entry in decodedState.entries)
        entry.key.toString(): entry.value,
    };

    // updated_at 来自 SQLite 毫秒时间戳；缺失时保持 null。
    final rawUpdatedAt = map['updated_at'];
    final updatedAt = rawUpdatedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(rawUpdatedAt.toInt())
        : null;

    // 列表和 Map 都冻结，避免页面无意中改坏已读取的会话快照。
    return LearningSession(
      type: LearningSessionType.fromStorageKey(rawType),
      wordIds: List<int>.unmodifiable(wordIds),
      state: Map<String, Object?>.unmodifiable(state),
      updatedAt: updatedAt,
    );
  }

  /// 转成 MethodChannel 可传输的普通 Map；复杂结构在 Dart 端先编码为 JSON。
  Map<String, Object?> toMap() => <String, Object?>{
    // 类型是 SQLite 主键，同类型的新会话会直接覆盖旧会话。
    'session_type': type.storageKey,
    // JSON 数组保留学习列表顺序。
    'word_ids_json': jsonEncode(wordIds),
    // JSON 对象保存页面自己的进度字段。
    'state_json': jsonEncode(state),
  };
}
