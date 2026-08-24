import 'dart:convert';

///
/// 首页四个复习模块的稳定标识。
///
/// 这里的 [storageKey] 会直接写进 SQLite 的 `review_sessions.module` 和
/// `review_records.module`，界面上的名字以后怎么改都不影响历史数据的统计口径。
///
enum ReviewModule {
  ///
  /// 听音辨义：听发音，从四个候选里选出正确的拼写与释义。
  listeningMeaning('listening_meaning', '听音辨义'),

  ///
  /// 词义连连：左边单词、右边释义，限时连线配对。
  meaningMatch('meaning_match', '词义连连'),

  ///
  /// 拼写巩固：玩法尚未开放。
  spellingReinforcement('spelling_reinforcement', '拼写巩固'),

  ///
  /// 看义选词：玩法尚未开放。
  meaningWordChoice('meaning_word_choice', '看义选词');

  ///
  /// 绑定数据库稳定键与界面名称。
  const ReviewModule(this.storageKey, this.label);

  ///
  /// 写入数据库的稳定文本键，不依赖 Dart 枚举名称自动转换。
  final String storageKey;

  ///
  /// 界面与日志使用的中文名称。
  final String label;

  ///
  /// 该玩法是否已经开发完成并开放使用。
  ///
  /// 未开放的模块在首页显示灰色「即将开放」，不参与三态进度。
  bool get isAvailable => switch (this) {
    listeningMeaning || meaningMatch => true,
    spellingReinforcement || meaningWordChoice => false,
  };

  ///
  /// 从数据库键恢复模块；未知值返回 null 而不是抛错。
  ///
  /// 统计查询可能返回历史遗留的模块键，返回 null 让调用方安全跳过。
  static ReviewModule? tryFromStorageKey(String? value) {
    // 没有值时不必遍历，直接按「无法识别」处理。
    if (value == null || value.isEmpty) return null;
    for (final module in values) {
      if (module.storageKey == value) return module;
    }
    return null;
  }
}

///
/// 会话类型：这一局是「今天的任务」还是「练完之后的加练」。
///
enum ReviewSessionKind {
  ///
  /// 每日主线进度。
  ///
  /// 单词全部来自今天的每日词库；答题会推进单词的复习时间。
  /// 只要把这一批单词全部操作完一遍，模块进度就会显示「已完成」，
  /// 过程中答没答对不影响这个判定。
  daily(1),

  ///
  /// 无限巩固练习。
  ///
  /// 主线过关之后再进模块开的局，单词是「今天随机一半 + 明天随机一半」。
  /// 答题照样更新难度、照样写复习记录，但**不推进单词的复习时间**——
  /// 否则明天那批词会被提前消耗掉，明天就选不到它们了。
  reinforce(2);

  ///
  /// 绑定数据库存储值。
  const ReviewSessionKind(this.code);

  ///
  /// SQLite 保存的整数值。
  final int code;

  ///
  /// 这种会话是否需要推进单词的复习时间。
  bool get updatesReviewedAt => this == daily;

  ///
  /// 从数据库整数恢复会话类型。
  static ReviewSessionKind fromCode(Object? value) {
    // 数字之外的类型说明原生协议对不上，直接暴露问题而不是猜一个默认值。
    if (value is! num) throw FormatException('未知会话类型：$value');
    final code = value.toInt();
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    throw FormatException('未知会话类型：$value');
  }
}

///
/// 会话状态：这一局最后走到了哪一步。
///
enum ReviewSessionStatus {
  ///
  /// 进行中：同一模块同一天最多只有一条。
  active(1),

  ///
  /// 完成：这一局的单词（或卡片）已经全部操作完一遍，不论过程中是否答错。
  completed(2),

  ///
  /// 中断：用户改了「每日复习」数量，或者词库变动让这一局凑不齐了。
  aborted(3),

  ///
  /// 失败：倒计时耗尽或用户中途退出，导致这一局没能把全部单词/卡片走完。
  failed(4);

  ///
  /// 绑定数据库存储值。
  const ReviewSessionStatus(this.code);

  ///
  /// SQLite 保存的整数值。
  final int code;

  ///
  /// 从数据库整数恢复状态。
  static ReviewSessionStatus fromCode(Object? value) {
    if (value is! num) throw FormatException('未知会话状态：$value');
    final code = value.toInt();
    for (final status in values) {
      if (status.code == code) return status;
    }
    throw FormatException('未知会话状态：$value');
  }
}

///
/// 一局复习会话。
///
/// [wordIds] 是这一局自己的单词快照，而不是只存一个词库编号——因为巩固局的
/// 单词横跨今明两天，不属于任何一个每日词库，光靠词库编号还原不出来。
/// [wordSetId] 保留成可空的来源标记，用于回溯这一局是从哪天的词库派生的。
class ReviewSession {
  ///
  /// 创建一局会话快照。
  const ReviewSession({
    required this.id,
    required this.module,
    required this.kind,
    required this.status,
    required this.wordSetId,
    required this.wordIds,
    required this.state,
    required this.wrongTotal,
    required this.sessionDate,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
  });

  /// SQLite 自增主键。
  final int id;

  /// 所属复习模块。
  final ReviewModule module;

  /// 主线还是巩固。
  final ReviewSessionKind kind;

  /// 当前状态。
  final ReviewSessionStatus status;

  /// 来源每日词库编号；巩固局或词库已被清理时为空。
  final int? wordSetId;

  /// 本局固定的答题顺序。
  final List<int> wordIds;

  /// 页面自己维护的进度快照，结构由各模块自行解释。
  final Map<String, Object?> state;

  /// 本局累计错误数；结算时 0 表示完成，大于 0 表示失败。
  final int wrongTotal;

  /// 开局当天的 yyyy-MM-dd。
  final String sessionDate;

  /// 开局时间。
  final DateTime? createdAt;

  /// 最后一次保存进度的时间。
  final DateTime? updatedAt;

  /// 结算时间；进行中为空。
  final DateTime? finishedAt;

  ///
  /// 这一局是否还能继续答题。
  bool get isActive => status == ReviewSessionStatus.active;

  ///
  /// 这一局答题时是否需要推进单词的复习时间。
  bool get updatesReviewedAt => kind.updatesReviewedAt;

  ///
  /// 把原生 MethodChannel 返回的一行数据转换成强类型模型。
  factory ReviewSession.fromMap(Map<Object?, Object?> map) {
    // 主键缺失说明原生协议对不上，无法定位这一局，必须暴露问题。
    final rawId = map['id'];
    if (rawId is! num) throw const FormatException('复习会话缺少有效 id');

    // 模块无法识别时同样中止：不能把一局会话记到错误的模块头上。
    final module = ReviewModule.tryFromStorageKey(map['module']?.toString());
    if (module == null) {
      throw FormatException('复习会话模块无法识别：${map['module']}');
    }

    // 单词主键数组由原生直接以数字列表传回，逐项收窄成 Dart int。
    final rawWordIds = map['word_ids'];
    if (rawWordIds is! List) {
      throw const FormatException('复习会话 word_ids 必须是数组');
    }
    final wordIds = <int>[
      for (final value in rawWordIds)
        if (value is num)
          value.toInt()
        else
          throw const FormatException('复习会话单词 id 必须是数字'),
    ];

    // 页面进度以 JSON 文本保存，这里还原成按字段名读取的 Map。
    final decodedState = jsonDecode(map['state_json']?.toString() ?? '{}');
    if (decodedState is! Map) {
      throw const FormatException('复习会话 state_json 必须是对象');
    }
    final state = <String, Object?>{
      for (final entry in decodedState.entries) entry.key.toString(): entry.value,
    };

    return ReviewSession(
      id: rawId.toInt(),
      module: module,
      kind: ReviewSessionKind.fromCode(map['kind']),
      status: ReviewSessionStatus.fromCode(map['status']),
      // 词库编号可空：巩固局横跨两天，或来源词库已被跨天清理。
      wordSetId: map['word_set_id'] is num
          ? (map['word_set_id']! as num).toInt()
          : null,
      wordIds: List<int>.unmodifiable(wordIds),
      state: Map<String, Object?>.unmodifiable(state),
      wrongTotal: map['wrong_total'] is num
          ? (map['wrong_total']! as num).toInt()
          : 0,
      sessionDate: map['session_date']?.toString() ?? '',
      createdAt: _readTime(map['created_at']),
      updatedAt: _readTime(map['updated_at']),
      finishedAt: _readTime(map['finished_at']),
    );
  }

  ///
  /// 把原生毫秒时间戳转成 DateTime；缺失或为 0 时返回 null。
  static DateTime? _readTime(Object? value) {
    // 0 在数据库里代表「还没发生」，不能显示成 1970 年。
    if (value is! num || value.toInt() == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
}

///
/// 首页卡片需要的模块进度：待完成 / 进行中 / 已完成。
///
enum ReviewModuleProgress {
  ///
  /// 待完成：今天还没开过局，或者上一局中断、失败了。
  pending,

  ///
  /// 进行中：今天有一局主线正开着，用户做到一半退了出来。
  active,

  ///
  /// 已完成：今天有一局主线把全部单词操作完了一遍，不论过程中是否答错。
  completed;

  ///
  /// 首页徽章上显示的文字。
  String get label => switch (this) {
    pending => '待完成',
    active => '进行中',
    completed => '已完成',
  };
}

///
/// 某个模块今天的整体进度快照，由首页一次性读取四个模块后组装。
class ReviewModuleState {
  ///
  /// 创建一个模块的今日进度快照。
  const ReviewModuleState({
    required this.progress,
    this.isReinforcing = false,
  });

  ///
  /// 今天还没有任何记录时使用的默认值。
  static const ReviewModuleState empty = ReviewModuleState(
    progress: ReviewModuleProgress.pending,
  );

  /// 三态进度。
  final ReviewModuleProgress progress;

  /// 今天主线已过关，当前正在无限巩固练习。
  final bool isReinforcing;

  ///
  /// 把原生返回的一行状态转换成首页可直接使用的进度。
  ///
  /// 原生给的是「今天最新一条会话的类型和状态」外加「今天主线过没过关」。
  /// 三态由这两者合成：
  /// - 主线过关 → 已完成（哪怕现在正在加练，也仍然是已完成）；
  /// - 否则最新一条是进行中的主线 → 进行中；
  /// - 其余（中断、失败、今天没开过局）→ 待完成。
  factory ReviewModuleState.fromMap(Map<Object?, Object?> map) {
    final kind = ReviewSessionKind.fromCode(map['kind']);
    final status = ReviewSessionStatus.fromCode(map['status']);
    final dailyCompleted = map['daily_completed'] == true;
    // 主线过关是最强信号，即使现在正开着一局巩固也照样显示「已完成」。
    if (dailyCompleted) {
      return ReviewModuleState(
        progress: ReviewModuleProgress.completed,
        // 主线已过关且最新一条仍在进行中，说明用户正在加练。
        isReinforcing:
            kind == ReviewSessionKind.reinforce &&
            status == ReviewSessionStatus.active,
      );
    }
    // 主线还没过关：只有「正开着一局主线」才算进行中。
    if (kind == ReviewSessionKind.daily &&
        status == ReviewSessionStatus.active) {
      return const ReviewModuleState(progress: ReviewModuleProgress.active);
    }
    // 中断、失败或今天压根没开过局，都回到待完成。
    return ReviewModuleState.empty;
  }
}
