import 'dart:convert';

import 'session_question.dart';
import 'session_record.dart';
import 'word.dart';

///
/// 复习模块的稳定标识。
///
/// [storageKey] 会直接写进数据库的 `sessions.module`，
/// 界面上的名字以后怎么改都不影响历史数据的统计口径。
///
enum ReviewModule {
  ///
  /// 随身听：只放音、不答题，从词库底部进入，不写会话记录。
  listening('listening', '随身听'),

  ///
  /// 听音辨义：听发音，先从候选里选出正确拼写，再逐条选出正确释义。
  listeningMeaning('listening_meaning', '听音辨义'),

  ///
  /// 词义连连：左边单词、右边释义，把本局全部含义逐条连线配对。
  meaningMatch('meaning_match', '词义连连'),

  ///
  /// 拼写巩固：按音节块把单词拼回来。
  spellingReinforcement('spelling_reinforcement', '拼写巩固'),

  ///
  /// 看义选词：给出一条中文释义，从候选单词里选出对应的词。
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
  /// 是否出现在首页的复习模块网格里。
  ///
  /// 随身听是被动听、没有对错，不参与「今日主线过没过关」的三态判定，
  /// 因此仍然只从词库底部进入，播放清单和进度独立保存在设置中。
  bool get isReviewCard => this != ReviewModule.listening;

  ///
  /// 这个模块是否需要写会话记录。
  ///
  /// 随身听没有「对 / 错」可言，若也写记录，首页的复习数字和打卡热力图
  /// 会被「只是听了一遍」灌水。
  bool get writesRecords => this != ReviewModule.listening;

  ///
  /// 首页复习网格里按顺序显示的四个模块。
  static List<ReviewModule> get reviewCards =>
      values.where((module) => module.isReviewCard).toList(growable: false);

  ///
  /// 从数据库键恢复模块；未知值返回 null 而不是抛错。
  ///
  /// 统计查询可能返回历史遗留的模块键，返回 null 让调用方安全跳过。
  static ReviewModule? tryFromStorageKey(String? value) {
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
enum SessionKind {
  ///
  /// 每日主线进度。
  ///
  /// 单词全部来自今天的词库；答题会推进单词的复习时间。
  /// 只要把这一批全部操作完一遍，模块进度就显示「已完成」，
  /// 过程中答没答对不影响这个判定。
  daily(1),

  ///
  /// 无限巩固练习。
  ///
  /// 主线过关之后再进模块开的局，单词是「今天随机一半 + 明天一半」。
  /// 答题照样更新难度、照样写记录，但**不推进单词的复习时间**——
  /// 否则明天那批词会被提前消耗掉，明天就选不到它们了。
  reinforce(2),

  /// 自选单词练习，与首页复习进度分别保存。
  selfTest(3);

  ///
  /// 绑定数据库存储值。
  const SessionKind(this.code);

  ///
  /// 数据库保存的整数值。
  final int code;

  ///
  /// 这种会话答题时是否需要推进单词的复习时间。
  bool get updatesReviewedAt => this == daily;

  ///
  /// 从数据库整数恢复会话类型。
  static SessionKind fromCode(Object? value) {
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
enum SessionStatus {
  ///
  /// 进行中：同一模块同一天最多只有一条。
  active(2),

  ///
  /// 完成：这一局的全部条目已经操作完一遍，不论过程中是否答错。
  completed(1),

  ///
  /// 中断：跨天清理或明确重新选择自测单词。
  aborted(3),

  ///
  /// 失败：由明确的失败动作写入；不限时的词义连连不会因普通退出自动失败。
  failed(0);

  ///
  /// 绑定数据库存储值。
  const SessionStatus(this.code);

  ///
  /// 数据库保存的整数值。
  final int code;

  ///
  /// 从数据库整数恢复状态。
  static SessionStatus fromCode(Object? value) {
    if (value is! num) throw FormatException('未知会话状态：$value');
    final code = value.toInt();
    for (final status in values) {
      if (status.code == code) return status;
    }
    throw FormatException('未知会话状态：$value');
  }
}

/// 一局会话和完整试卷。
///
/// groups 对应独立的大题、小题表；items / cursor 是供现有页面取词和显示进度的
/// 查询投影，不再作为 JSON 数组或下标保存到数据库。重复小题以独立 id 区分。
class Session {
  ///
  /// 创建一局会话。
  const Session({
    required this.id,
    required this.module,
    required this.kind,
    required this.status,
    required this.wordSetId,
    required this.items,
    required this.cursor,
    required this.elapsed,
    required this.date,
    this.createdAt,
    this.updatedAt,
    this.groups = const <SessionMainQuestion>[],
    this.snapshotWords = const <Word>[],
    this.records = const <SessionRecord>[],
    this.playback = const <String, Object?>{},
    this.settlementStatus = 0,
    this.answerSeconds = 0,
  });

  /// 完整试卷及开局时的词库内容，恢复不再读取已被编辑的现有词库。
  final List<SessionMainQuestion> groups;
  final List<Word> snapshotWords;
  final List<SessionRecord> records;
  final Map<String, Object?> playback;
  final int settlementStatus;
  final int answerSeconds;
  List<SessionSubQuestion> get questions => <SessionSubQuestion>[
    for (final group in groups) ...group.questions,
  ];

  /// 自增主键。
  final int id;

  /// 所属复习模块。
  final ReviewModule module;

  /// 复习、巩固或自测。
  final SessionKind kind;

  /// 当前状态。
  final SessionStatus status;

  /// 关联的每日计划编号；自测没有计划。
  final int? wordSetId;

  /// 原生根据大小题表生成的答题顺序视图，不是单独保存的编号数组。
  final List<Object?> items;

  /// 当前进度：普通模块是 [items] 的外层索引；词义连连是已完成的配对数。
  final int cursor;

  /// 本局已用时间，单位秒。
  final int elapsed;

  /// 开局当天的 yyyy-MM-dd。
  final String date;

  /// 开局时间。
  final DateTime? createdAt;

  /// 最后一次保存进度的时间。
  final DateTime? updatedAt;

  ///
  /// 本局一共几道题。
  ///
  /// 普通模块的一条外层元素就是一道题；词义连连的外层元素是一轮棋盘，
  /// 所以要展开后再数，不能直接返回 [items.length]。
  int get total =>
      module == ReviewModule.meaningMatch ? pairItems.length : items.length;

  ///
  /// 这一局是否还能继续答题。
  bool get isActive => status == SessionStatus.active;

  ///
  /// 这一局答题时是否需要推进单词的复习时间。
  bool get updatesReviewedAt => kind.updatesReviewedAt;

  ///
  /// 把数据列表读成一维主键数组（随身听 / 听音辨义 / 拼写巩固 / 看义选词）。
  List<int> get idItems => <int>[
    for (final item in items)
      if (item is num)
        item.toInt()
      else
        throw FormatException('${module.label}的数据列表元素必须是数字，实际为：$item'),
  ];

  ///
  /// 把数据列表读成「按轮次」的 [单词id, 含义id] 数对（词义连连）。
  ///
  /// 新会话的 [items] 是嵌套数组，外层每一项就是一轮；旧会话仍是扁平数组，
  /// 这里按旧页面的每轮 5 对规则切块，保证历史数据至少可以被读取。
  List<List<({int wordId, int meaningId})>> get pairRounds {
    if (items.isEmpty) return const <List<({int wordId, int meaningId})>>[];

    // 新格式：每个外层元素是一轮，轮内元素才是 [wordId, meaningId]。
    final isNested = items.every(
      (item) => item is List && (item.isEmpty || item.first is List),
    );
    if (isNested) {
      return List<List<({int wordId, int meaningId})>>.unmodifiable(
        items.map(_parsePairRound),
      );
    }

    // 旧格式：扁平 pair 列表按 5 对切块，仅作为兼容读取，不会用于新建会话。
    final flat = _parsePairRound(items);
    return List<List<({int wordId, int meaningId})>>.unmodifiable(
      <List<({int wordId, int meaningId})>>[
        for (var start = 0; start < flat.length; start += 5)
          flat.sublist(start, (start + 5).clamp(0, flat.length)),
      ],
    );
  }

  /// 把按轮次保存的配对摊平，供按单词查找、恢复和首页排序使用。
  List<({int wordId, int meaningId})> get pairItems =>
      <({int wordId, int meaningId})>[for (final round in pairRounds) ...round];

  /// 解析一轮 `[单词id, 含义id]`；数据损坏时明确抛错，不悄悄换题。
  List<({int wordId, int meaningId})> _parsePairRound(Object? rawRound) {
    if (rawRound is! List) {
      throw FormatException('${module.label}的配对轮次必须是数组，实际为：$rawRound');
    }
    return <({int wordId, int meaningId})>[
      for (final item in rawRound)
        if (item is List &&
            item.length >= 2 &&
            item[0] is num &&
            item[1] is num)
          (
            wordId: (item[0]! as num).toInt(),
            meaningId: (item[1]! as num).toInt(),
          )
        else
          throw FormatException(
            '${module.label}的配对元素必须是 [单词id, 含义id]，实际为：$item',
          ),
    ];
  }

  ///
  /// 把原生返回的一行数据转换成强类型模型。
  factory Session.fromMap(Map<Object?, Object?> map) {
    // 主键缺失说明原生协议对不上，无法定位这一局，必须暴露问题。
    final rawId = map['id'];
    if (rawId is! num) throw const FormatException('会话缺少有效 id');

    // 模块无法识别时同样中止：不能把一局会话记到错误的模块头上。
    final module = ReviewModule.tryFromStorageKey(map['module']?.toString());
    if (module == null) throw FormatException('会话模块无法识别：${map['module']}');

    // 正式接口直接返回大小题的顺序视图；历史调用的 JSON 字符串仍可读取。
    final rawItems = map['items'];
    final decodedItems = rawItems is List
        ? rawItems
        : jsonDecode(rawItems?.toString() ?? '[]');
    if (decodedItems is! List) {
      throw const FormatException('会话的数据列表必须是数组');
    }

    return Session(
      id: rawId.toInt(),
      module: module,
      kind: SessionKind.fromCode(map['kind']),
      status: SessionStatus.fromCode(map['status']),
      // 自测不关联每日计划，因此计划编号可以为空。
      wordSetId: map['word_set_id'] is num
          ? (map['word_set_id']! as num).toInt()
          : null,
      items: List<Object?>.unmodifiable(decodedItems),
      cursor: _readInt(map['cursor']),
      elapsed: _readInt(map['elapsed']),
      date: map['date']?.toString() ?? '',
      createdAt: _readTime(map['created_at']),
      updatedAt: _readTime(map['updated_at']),
      groups: <SessionMainQuestion>[
        for (final row in map['groups'] as List? ?? const [])
          SessionMainQuestion.fromMap(Map<Object?, Object?>.from(row as Map)),
      ],
      snapshotWords: <Word>[
        for (final row in map['words'] as List? ?? const [])
          Word.fromMap(Map<Object?, Object?>.from(row as Map)),
      ],
      records: <SessionRecord>[
        for (final row in map['records'] as List? ?? const [])
          SessionRecord.fromMap(Map<Object?, Object?>.from(row as Map)),
      ],
      playback: map['playback'] is Map
          ? Map<String, Object?>.from(map['playback'] as Map)
          : const <String, Object?>{},
      settlementStatus: _readInt(map['settlement_status']),
      answerSeconds: _readInt(map['answer_seconds']),
    );
  }

  ///
  /// 读取一个非负整数；缺失或类型错误时返回 0。
  static int _readInt(Object? value) {
    if (value is! num) return 0;
    final result = value.toInt();
    return result < 0 ? 0 : result;
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
  /// 已完成：今天有一局主线把全部条目操作完了一遍，不论过程中是否答错。
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
/// 复习卡片底部进度条的视觉阶段。
///
/// 进度条是双层叠加结构：底色表示「今日主线完成没完成」，前景色表示
/// 「当前这一局走到了哪里」。把视觉规则集中在一个枚举里，UI 只管照着画。
enum ReviewBarPhase {
  ///
  /// 今日主线还没开始：全灰。
  idle,

  ///
  /// 今日主线进行中：灰底 + 绿色按本局已完成条目比例填充。
  dailyActive,

  ///
  /// 今日主线已完成、尚未开始巩固：全绿。
  dailyDone,

  ///
  /// 巩固练习进行中：绿底 + 蓝色按本局已完成条目比例填充。
  reinforceActive,

  ///
  /// 巩固练习已完成：绿底 + 蓝色全满（底层绿色被完全覆盖，变成全蓝）。
  reinforceDone,
}

///
/// 某个模块今天的整体进度快照，由首页一次性读取全部模块后组装。
class ReviewModuleState {
  ///
  /// 创建一个模块的今日进度快照。
  const ReviewModuleState({
    required this.progress,
    this.isReinforcing = false,
    this.doneCount = 0,
    this.totalCount = 0,
    this.barPhase = ReviewBarPhase.idle,
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

  /// 进度条分子：本局已经操作完毕的条目数。
  final int doneCount;

  /// 进度条分母：本局总条目数。
  final int totalCount;

  /// 进度条视觉阶段，直接决定底色与前景色。
  final ReviewBarPhase barPhase;

  ///
  /// 把原生返回的一行状态转换成首页可直接使用的进度。
  ///
  /// 原生给的是「今天最新一条会话的类型和状态」外加「今天主线过没过关」。
  /// 三态由这两者合成：
  /// - 主线过关 → 已完成（哪怕现在正在加练，也仍然是已完成）；
  /// - 否则最新一条是进行中的主线 → 进行中；
  /// - 其余（中断、失败、今天没开过局）→ 待完成。
  factory ReviewModuleState.fromMap(Map<Object?, Object?> map) {
    final kind = SessionKind.fromCode(map['kind']);
    final status = SessionStatus.fromCode(map['status']);
    final dailyCompleted = map['daily_completed'] == true;
    final doneCount = Session._readInt(map['cursor']);
    final totalCount = Session._readInt(map['total']);

    // 主线过关是最强信号，即使现在正开着一局巩固也照样显示「已完成」。
    if (dailyCompleted) {
      final reinforcing =
          kind == SessionKind.reinforce && status == SessionStatus.active;
      return ReviewModuleState(
        progress: ReviewModuleProgress.completed,
        isReinforcing: reinforcing,
        doneCount: doneCount,
        totalCount: totalCount,
        // 巩固进行中→蓝在绿上；巩固完成→全蓝；其余→全绿。
        barPhase: reinforcing
            ? ReviewBarPhase.reinforceActive
            : kind == SessionKind.reinforce && status == SessionStatus.completed
            ? ReviewBarPhase.reinforceDone
            : ReviewBarPhase.dailyDone,
      );
    }
    // 主线还没过关：只有「正开着一局主线」才算进行中。
    if (kind == SessionKind.daily && status == SessionStatus.active) {
      return ReviewModuleState(
        progress: ReviewModuleProgress.active,
        doneCount: doneCount,
        totalCount: totalCount,
        barPhase: ReviewBarPhase.dailyActive,
      );
    }
    // 中断、失败或今天压根没开过局，都回到待完成。
    return ReviewModuleState.empty;
  }
}
