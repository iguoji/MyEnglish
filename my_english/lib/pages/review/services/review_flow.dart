import 'dart:math';

import '../../../models/daily_word_set.dart';
import '../../../models/review_session.dart';
import '../../../models/word.dart';
import '../../../store/daily_word_set.dart';
import '../../../store/review_session.dart';
import 'review_word_selector.dart';

///
/// 打开一个复习模块时需要的全部东西。
///
/// [session] 是这一局本身，[words] 是按会话顺序组装好的最新单词数据。
/// 页面拿到它就能直接开始答题，不必再回头查词库。
///
class ReviewEntry {
  ///
  /// 创建一次模块入口结果。
  const ReviewEntry({required this.session, required this.words});

  ///
  /// 本局会话，含状态、类型与页面进度。
  final ReviewSession session;

  ///
  /// 按会话固定顺序组装的最新单词数据。
  final List<Word> words;
}

///
/// 复习模块的核心流程：先备好今天的词库，再决定这一局怎么开。
///
/// 整个复习模块只有两个入口动作，都在这里：
/// - [resolveWordSet]：拿到「今天要背的这一批词」，没有就按排序规则建一份；
/// - [openModule]：拿到「这个模块现在该进的这一局」，续上旧局或开一局新的。
///
class ReviewFlow {
  ///
  /// 创建复习流程服务。
  ReviewFlow({
    required this.wordSetStore,
    required this.sessionStore,
    Random? random,
  }) : _random = random ?? Random();

  ///
  /// 每日词库 Store。
  final DailyWordSetStore wordSetStore;

  ///
  /// 模块会话 Store。
  final ReviewSessionStore sessionStore;

  ///
  /// 巩固局「随机一半」使用的随机源。
  final Random _random;

  ///
  /// 拿到今天的每日词库；数量与设置对不上时就地修正。
  ///
  /// 流程（对应《复习模块》文档的「创建词库」）：
  /// 1. 今天还没建过 → 按两层规则选出目标数量，落库；
  ///    第一层按难度降序取 40%，第二层按复习时间升序取剩下的 60%。
  /// 2. 已经建过 → 先剔除已被删除的单词，再比对数量：
  ///    - 多了：从前面截取，多出来的那部分丢掉；
  ///    - 少了：**排除已有的那些**，再按**单层规则**（第二层）补足差额。
  ///      补词只走第二层，不重新做难度分流，避免替换掉用户已在练的词。
  ///      这里必须排除已有 id——已经练过的词复习时间刚被推进，会掉到排序后面，
  ///      而没练的词还排在最前，不排除的话补进来的就是词库里已有的那几个，
  ///      同一个词会在词库里出现两次。
  ///    - 正好：只有在剔除过删除词时才需要重新落库，否则原样返回。
  ///
  /// 目标数量取「设置里的每日复习」和「词库里实际有多少词」中较小的那个。
  /// 词库只有 30 个词、目标却设成 100 时，如果不取小值，
  /// 每次打开模块都会白白重写一次词库，而且主线永远判不了完成。
  Future<DailyWordSet?> resolveWordSet(
    List<Word> allWords, {
    required int dailyGoal,
  }) async {
    // 只有已经落库、拿到主键的单词才能进词库。
    final available = <Word>[
      for (final word in allWords)
        if (word.id != null) word,
    ];
    // 一个可用单词都没有，谈不上建库。
    if (available.isEmpty) return null;
    // 目标不能超过实际拥有的单词数，否则永远补不满。
    final target = dailyGoal < available.length ? dailyGoal : available.length;
    // 目标为 0（用户把每日复习设成了 0）同样没有词库可建。
    if (target <= 0) return null;

    // 按主键建索引，后面判断「这个词还在不在」是 O(1)。
    final wordsById = <int, Word>{for (final word in available) word.id!: word};
    final existing = await wordSetStore.getToday();

    // 今天第一次进复习模块：按两层规则选出前 target 个。
    // 第一层拿走难度最高的 40%，第二层补上复习时间最早的 60%，
    // 两者合并即今天的词库（顺序为第一层在前、第二层在后）。
    if (existing == null) {
      return wordSetStore.saveToday(_idsOf(ReviewWordSelector.selectTwoLayer(
        available,
        limit: target,
      )));
    }

    // 保留仍存在单词的原始顺序；被删掉的主键直接剔除。
    final kept = <int>[
      for (final id in existing.wordIds)
        if (wordsById.containsKey(id)) id,
    ];
    // 剔除过内容说明词库被编辑过，即使数量凑巧对得上也要重新落库。
    final wasRepaired = kept.length != existing.wordIds.length;

    if (kept.length > target) {
      // 目标调小了：从前面截取。会话已经在改设置时被中断，
      // 所以「截掉后面那截」不会丢掉用户正在做的进度。
      return wordSetStore.saveToday(kept.sublist(0, target));
    }

    if (kept.length < target) {
      // 目标调大了或有词被删了：排除已有的，再从排序结果里补足差额。
      final supplement = ReviewWordSelector.select(
        available,
        limit: target - kept.length,
        exclude: kept.toSet(),
      );
      return wordSetStore.saveToday(<int>[...kept, ..._idsOf(supplement)]);
    }

    // 数量正好：只有真的剔除过删除词才需要重写，否则原样复用。
    if (wasRepaired) return wordSetStore.saveToday(kept);
    return existing;
  }

  ///
  /// 拿到这个模块现在该进的这一局。
  ///
  /// 流程（对应《复习模块》文档的「创建会话」）：
  /// 1. 今天最新一条会话还在「进行中」且单词仍然有效 → 直接续上；
  /// 2. 今天已经有一局「完成」的主线 → 开一局**巩固**，
  ///    单词是「今天随机一半 + 明天随机一半」，答题不推进复习时间；
  /// 3. 其余情况（今天没开过局 / 上一局中断或失败）→ 开一局**主线**，
  ///    单词就是今天的整份词库。
  Future<ReviewEntry?> openModule(
    ReviewModule module, {
    required List<Word> allWords,
    required int dailyGoal,
  }) async {
    // 第一步永远是备好今天的词库，四个模块共用同一份。
    final wordSet = await resolveWordSet(allWords, dailyGoal: dailyGoal);
    if (wordSet == null) return null;

    final wordsById = <int, Word>{
      for (final word in allWords)
        if (word.id != null) word.id!: word,
    };

    // 第二步：看看今天这个模块最新一条会话是什么情况。
    final latest = await sessionStore.getLatest(module);
    if (latest != null && latest.isActive) {
      final resumed = _wordsFor(latest.wordIds, wordsById);
      // 单词全都还在，才有可能续上这一局。
      if (resumed != null) {
        // 主线局还要额外确认单词和今天的词库仍然一致：设置改过、词库补过词
        // 之后，旧的主线进度已经代表不了「今天的任务」，必须换新局。
        final matchesWordSet =
            latest.kind == ReviewSessionKind.reinforce ||
            _sameIds(latest.wordIds, wordSet.wordIds);
        if (matchesWordSet) {
          return ReviewEntry(session: latest, words: resumed);
        }
      }
      // 走到这里说明这一局已经没法续了，收尾成「中断」再开新局。
      await sessionStore.finish(
        sessionId: latest.id,
        status: ReviewSessionStatus.aborted,
      );
    }

    // 第三步：今天主线过关了没有，决定开主线还是开巩固。
    final completedDaily = await sessionStore.getCompletedDaily(module);
    final wordIds = completedDaily == null
        ? wordSet.wordIds
        : _buildReinforceWordIds(
            todayIds: wordSet.wordIds,
            allWords: allWords,
            target: wordSet.wordIds.length,
          );

    final words = _wordsFor(wordIds, wordsById);
    // 组装不出完整单词说明词库刚刚发生了变化，交给调用方提示后重试。
    if (words == null || words.isEmpty) return null;

    final session = await sessionStore.create(
      module: module,
      kind: completedDaily == null
          ? ReviewSessionKind.daily
          : ReviewSessionKind.reinforce,
      // 巩固局的单词横跨今明两天，词库编号只作为来源标记留档。
      wordSetId: wordSet.id,
      wordIds: wordIds,
    );
    return ReviewEntry(session: session, words: words);
  }

  ///
  /// 组装巩固局的单词：今天随机一半 + 明天随机一半。
  ///
  /// 「明天的词」= 按同一套**两层规则**、**排除今天这批**之后排在最前面的那些。
  /// 这里不用「跳过前 N 个」的写法：今天的词刚被推进过复习时间，已经掉到排序
  /// 最后面去了，跳过前 N 个反而会跳错位置；词库总量不足两倍目标时更会直接
  /// 把今天的词又抓回来。排除法在任何词库规模下都正确。
  ///
  /// 明天的词不够一半时，缺口由今天的词补足，保证这一局的题量不缩水。
  List<int> _buildReinforceWordIds({
    required List<int> todayIds,
    required List<Word> allWords,
    required int target,
  }) {
    // 一半向上取整：目标 100 时今天出 50、明天出 50。
    final halfTarget = (target / 2).ceil();

    // 明天的候选：同一套两层规则，排除今天这批。
    final tomorrowIds = <int>[
      for (final word in ReviewWordSelector.selectTwoLayer(
        allWords,
        limit: halfTarget,
        exclude: todayIds.toSet(),
      ))
        if (word.id != null) word.id!,
    ];

    // 今天的一半随机抽；明天不够时今天多出一些补上。
    final todayQuota = target - tomorrowIds.length;
    final todayPicked = _pickRandom(todayIds, todayQuota);

    // 两批混在一起再整体打乱，避免前半局全是今天、后半局全是明天。
    final merged = <int>[...todayPicked, ...tomorrowIds]..shuffle(_random);
    return List<int>.unmodifiable(merged);
  }

  ///
  /// 从列表里随机抽取指定数量；数量超过列表长度时返回全部。
  List<int> _pickRandom(List<int> source, int count) {
    // 需要的比有的还多，那就全都要。
    if (count >= source.length) return List<int>.of(source);
    if (count <= 0) return const <int>[];
    // 洗牌后取前 count 个，等价于无放回随机抽样。
    final shuffled = List<int>.of(source)..shuffle(_random);
    return shuffled.sublist(0, count);
  }

  ///
  /// 按主键顺序组装单词；只要有一个词已不存在就返回 null。
  ///
  /// 缺词的会话没法完整还原，与其让用户进去看到少了几题，
  /// 不如直接判定这一局失效、重开一局干净的。
  List<Word>? _wordsFor(List<int> ids, Map<int, Word> wordsById) {
    final words = <Word>[];
    for (final id in ids) {
      final word = wordsById[id];
      if (word == null) return null;
      words.add(word);
    }
    return List<Word>.unmodifiable(words);
  }

  ///
  /// 取出单词列表中的主键；无主键的临时数据会被跳过。
  List<int> _idsOf(List<Word> words) => <int>[
    for (final word in words)
      if (word.id != null) word.id!,
  ];

  ///
  /// 逐项比较两个主键列表是否完全一致（含顺序）。
  bool _sameIds(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
