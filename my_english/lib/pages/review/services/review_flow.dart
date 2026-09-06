import 'dart:math';

import '../../../models/session.dart';
import '../../../models/session_record.dart';
import '../../../models/word.dart';
import '../../../models/word_set.dart';
import '../../../store/session.dart';
import '../../../store/word.dart';
// 运行日志：选词与开局的业务理由统一留痕，方便日后复查「当时为什么这么选」。
import '../../../services/app_log.dart';

///
/// 打开一个复习模块时需要的全部东西。
///
/// 页面拿到它就能直接开始答题，不必再回头查词库：
/// - [session] 是这一局本身，含数据列表、当前进度和已用时间；
/// - [words] 是这一局涉及的全部单词（含释义），按主键索引取用；
/// - [records] 是这一局已经产生的点击记录，用来还原「做到哪、踩过哪些坑」。
///
class ReviewEntry {
  ///
  /// 创建一次模块入口结果。
  const ReviewEntry({
    required this.session,
    required this.words,
    required this.records,
  });

  ///
  /// 本局会话。
  final Session session;

  ///
  /// 这一局涉及的全部单词，按主键索引。
  final Map<int, Word> words;

  ///
  /// 这一局已经产生的点击记录；全新一局时是空列表。
  final List<SessionRecord> records;

  ///
  /// 这是不是一局刚开的新局（还没有任何记录）。
  bool get isFresh => records.isEmpty && session.cursor == 0;
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
    required this.wordStore,
    required this.sessionStore,
    Random? random,
  }) : _random = random ?? Random();

  ///
  /// 单词 Store：选词、按主键回捞单词都靠它。
  final WordStore wordStore;

  ///
  /// 词库 + 会话 + 记录 Store。
  final SessionStore sessionStore;

  ///
  /// 巩固局「随机一半」使用的随机源。
  final Random _random;

  ///
  /// 第一层（难词）占目标数量的比例；0.4 即 40%。
  static const double primaryRatio = 0.4;

  ///
  /// 按两层规则挑单词。
  ///
  /// - 第一层占 `ceil(数量 × 0.4)`：难度降序打头，专挑最难的；
  /// - 第二层占剩下的：复习时间升序打头，专挑最久没碰的，并排除第一层已选中的。
  ///
  /// 排序完全交给 SQLite——`words` 表上那两个索引就是为这两层建的，
  /// 排序不落临时表，也不必把整个词库搬到内存里排一遍。
  Future<List<int>> pickTwoLayer({
    required int limit,
    List<int> exclude = const <int>[],
  }) async {
    // 目标非正数时没有可选单词。
    if (limit <= 0) return const <int>[];
    // 向上取整：目标 5 时第一层拿 2 个而不是 1 个，宁可多一个也不少一个。
    final primaryCount = (limit * primaryRatio).ceil();
    final hard = await wordStore.pickWords(
      limit: primaryCount,
      exclude: exclude,
      layer: PickLayer.hard,
    );
    // 第二层配额 = 总数 − 第一层实际拿到的；第一层因向上取整超出时夹到 0。
    final secondaryCount = limit - hard.length;
    if (secondaryCount <= 0) return hard;
    final stale = await wordStore.pickWords(
      limit: secondaryCount,
      // 必须排除第一层已选中的，否则同一个词会在词库里出现两次。
      exclude: <int>[...exclude, ...hard],
      layer: PickLayer.stale,
    );
    // 留痕：配额怎么分、两层各拿到几个，复查「这轮为什么是这些词」先看这一行。
    AppLog.i(
      'review',
      '两层选词 limit=$limit 一层配额=ceil($limit×0.4)=$primaryCount 实得=${hard.length} 二层配额=limit-一层=$secondaryCount 实得=${stale.length} 传入排除=${exclude.length}个',
    );
    return List<int>.unmodifiable(<int>[...hard, ...stale]);
  }

  ///
  /// 拿到今天的复习词库；数量与设置对不上时就地修正。
  ///
  /// 流程（对应《复习模块》文档的「获取词库」）：
  /// 1. 今天还没建过 → 按两层规则选出目标数量，连同「明日单词列表」一起落库；
  /// 2. 已经建过 → 先剔除已被删除的单词，再比对数量：
  ///    - 多了：从前面截取，多出来的那部分丢掉；
  ///    - 少了：**排除已有的那些**，再按两层规则补足差额。
  ///      这里必须排除已有 id——已经练过的词复习时间刚被推进，会掉到排序后面，
  ///      而没练的词还排在最前，不排除的话补进来的就是词库里已有的那几个。
  ///    - 正好：只有在剔除过删除词时才需要重新落库，否则原样返回。
  ///
  /// 目标数量取「设置里的每日复习」和「词库里实际有多少词」中较小的那个：
  /// 词库只有 30 个词、目标却设成 100 时，如果不取小值，每次打开模块都会白白
  /// 重写一次词库，而且主线永远判不了完成。
  Future<WordSet?> resolveWordSet({
    required int dailyGoal,
    required int libraryCount,
    required String date,
  }) async {
    // 一个可用单词都没有，谈不上建库。
    if (libraryCount <= 0) return null;
    // 目标不能超过实际拥有的单词数，否则永远补不满。
    final target = dailyGoal < libraryCount ? dailyGoal : libraryCount;
    // 目标为 0（用户把每日复习设成了 0）同样没有词库可建。
    if (target <= 0) return null;

    final existing = await sessionStore.getLatestWordSet(date);

    // 今天第一次进复习模块：按两层规则选出前 target 个。
    if (existing == null) {
      // 记录建库原因：首次建库时「目标」取每日设置与词库实际数的较小值。
      AppLog.i(
        'review',
        '词库状态=首次建库 date=$date target=$target（每日设置=$dailyGoal 词库=$libraryCount 取较小）',
      );
      final today = await pickTwoLayer(limit: target);
      return _createWordSet(today: today, target: target, date: date);
    }

    // 确认词库里的每个词都还在（可能被用户删掉了）。
    final alive = await wordStore.getByIds(existing.todayWordIds);
    final aliveIds = <int>{for (final word in alive) word.id!};
    // 保留仍存在单词的原始顺序；被删掉的主键直接剔除。
    final kept = <int>[
      for (final id in existing.todayWordIds)
        if (aliveIds.contains(id)) id,
    ];
    // 剔除过内容说明词库被编辑过，即使数量凑巧对得上也要重新落库。
    final wasRepaired = kept.length != existing.todayWordIds.length;

    if (kept.length > target) {
      // 目标调小了：从前面截取。会话已经在改设置时被中断，
      // 所以「截掉后面那截」不会丢掉用户正在做的进度。
      AppLog.i(
        'review',
        '词库状态=截取 原保留=${kept.length}个 目标调小/有删词 target=$target 只留前 $target 个',
      );
      return _createWordSet(today: kept.sublist(0, target), target: target, date: date);
    }
    if (kept.length < target) {
      // 目标调大了或有词被删了：排除已有的，再按两层规则补足差额。
      // 40/60 是按**这次补的差额**分的，不是回过头去重算整份词库的比例。
      AppLog.i(
        'review',
        '词库状态=补足 已有=${kept.length}个 差=$target 排除已有避免刚练过的词再被选入 补选 limit=${target - kept.length}',
      );
      final supplement = await pickTwoLayer(
        limit: target - kept.length,
        exclude: kept,
      );
      return _createWordSet(
        today: <int>[...kept, ...supplement],
        target: target,
        date: date,
      );
    }
    // 数量正好：只有真的剔除过删除词才需要重写，否则原样复用。
    if (wasRepaired) {
      // 剔除过已删除的单词，即使数量凑巧没变也要重新落库清掉坏主键。
      return _createWordSet(today: kept, target: target, date: date);
    }
    // 词库没有变化：原样复用今天的词库，不重复建库。
    AppLog.i('review', '词库状态=原样复用 date=$date target=$target');
    return existing;
  }

  ///
  /// 落库一份新词库，同时算好今天的「明日单词列表」。
  ///
  /// 明日列表 = 同一套两层规则、排除今天这批之后排在最前面的一半（向下取整，
  /// 与巩固局「今日随机一半」的向上取整咬合，保证巩固局总题量不超过每日复习）。
  /// 它只服务于今天的巩固局：主线过关后再进模块，抽的是「今天一半 + 明天一半」。
  /// 明天会重新建库，不会复用这份列表。
  Future<WordSet> _createWordSet({
    required List<int> today,
    required int target,
    required String date,
  }) async {
    // 一半**向下**取整：巩固局由「今日随机一半（向上）」+「明日预选」拼成，
    // 若两边都向上取整，奇数目标会多出 1 个（每日 5 → 3 + 3 = 6，超过每日复习）。
    // 今日向上、明日向下正好咬合：每日 5 → 今日 3 + 明日 2 = 5，总题量不超额。
    // 明日预选只服务今天巩固局的预习，明天会重新建库，少预选一个不影响明天。
    final halfTarget = (target * 0.5).floor();
    // 明天的词有多少拿多少，凑不满一半也不用今天的词去补——
    // 巩固局本来就是加练，用今天的词填满反而会让同一批词被反复问到。
    final tomorrow = await pickTwoLayer(limit: halfTarget, exclude: today);
    // 记录明日预选的一半口径（向下取整），配巩固局今日侧「向上取整」互相咬合。
    AppLog.i(
      'review',
      '明日预选 half=floor($target×0.5)=$halfTarget 排除今天=$today.length 选出=${tomorrow.length}个 只服务今天巩固局，明天会重新建库',
    );
    final id = await sessionStore.createWordSet(
      wordCount: target,
      todayWordIds: today,
      tomorrowWordIds: tomorrow,
      date: date,
    );
    return WordSet(
      id: id,
      wordCount: today.length,
      todayWordIds: List<int>.unmodifiable(today),
      tomorrowWordIds: List<int>.unmodifiable(tomorrow),
      date: date,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  ///
  /// 拿到这个模块现在该进的这一局。
  ///
  /// 流程（对应《复习模块》文档的「点击模块」）：
  /// 1. 今天最新一条会话还在「进行中」且单词仍然有效 → 直接续上；
  /// 2. 今天已经有一局「完成」的主线 → 开一局**巩固**，
  ///    单词是「今天随机一半 + 明天一半」，答题不推进复习时间；
  /// 3. 其余情况（今天没开过局 / 上一局中断或失败）→ 开一局**主线**，
  ///    单词就是今天的整份词库。
  Future<ReviewEntry?> openModule(
    ReviewModule module, {
    required int dailyGoal,
    required int libraryCount,
    required String date,
  }) async {
    // 第一步永远是备好今天的词库，全部模块共用同一份。
    final wordSet = await resolveWordSet(
      dailyGoal: dailyGoal,
      libraryCount: libraryCount,
      date: date,
    );
    if (wordSet == null) return null;

    // 第二步：看看今天这个模块最新一条会话是什么情况。
    final latest = await sessionStore.getLatestSession(module, date);
    if (latest != null && latest.isActive) {
      final resumed = await _resume(latest, wordSet);
      if (resumed != null) return resumed;
      // 走到这里说明这一局已经没法续了，收尾成「中断」再开新局。
      await sessionStore.finishSession(
        sessionId: latest.id,
        status: SessionStatus.aborted,
      );
    }

    // 第三步：今天主线过关了没有，决定开主线还是开巩固。
    final completedDaily = await sessionStore.getCompletedDailySession(module, date);
    final kind = completedDaily == null ? SessionKind.daily : SessionKind.reinforce;
    // 记录这一局开「主线」还是「巩固」：今天主线没过关开主线，过关后开巩固。
    AppLog.i(
      'review',
      '开局决定 模块=${module.label} 类型=${kind == SessionKind.daily ? "主线" : "巩固"} date=$date 词数=${wordSet.todayWordIds.length}/${wordSet.tomorrowWordIds.length} wordSetId=${wordSet.id}',
    );
    final wordIds = kind == SessionKind.daily
        ? wordSet.todayWordIds
        : _buildReinforceWordIds(wordSet);

    // 按主键顺序组装单词；缺词说明词库刚变过，交给调用方提示后重试。
    final words = await _wordsInOrder(wordIds);
    if (words == null || words.isEmpty) return null;

    // 数据列表的形状由模块决定，见 ReviewModule 各自的注释。
    final items = _buildItems(module, wordIds, words);
    // 一条题都出不来（比如全部单词都没有释义）时不开局。
    if (items.isEmpty) return null;

    final sessionId = await sessionStore.createSession(
      module: module,
      kind: kind,
      // 巩固局的单词横跨今明两天，词库编号只作为来源标记留档。
      wordSetId: wordSet.id,
      items: items,
      date: date,
    );
    final session = await sessionStore.getLatestSession(module, date);
    // 刚建的这一局必须能立刻读回来，读不到说明写入没生效。
    if (session == null || session.id != sessionId) {
      throw StateError('新建的${module.label}会话无法读回');
    }
    return ReviewEntry(
      session: session,
      words: <int, Word>{for (final word in words) word.id!: word},
      records: const <SessionRecord>[],
    );
  }

  ///
  /// 从词库底部随手开一局（随身听 / 听音辨义）。
  ///
  /// 和 [openModule] 的区别：单词是用户当场挑的（勾选优先，否则当前可见），
  /// 不走今天的词库，所以：
  /// - 类型固定是**巩固**，答题不推进复习时间——这批词未必是今天该复习的；
  /// - 不参与「今日主线过没过关」的判定。
  ///
  /// 今天这个模块已经有一局进行中、而且用的就是这批词时直接续上；
  /// 换了一批词就把旧局判为中断，重开一局。
  Future<ReviewEntry?> openAdHoc(
    ReviewModule module, {
    required List<int> wordIds,
    required String date,
  }) async {
    // 一个词都没有就没什么可练的。
    if (wordIds.isEmpty) return null;

    final latest = await sessionStore.getLatestSession(module, date);
    if (latest != null && latest.isActive) {
      final words = await _wordsForSession(latest);
      // 单词全都还在、而且就是用户这次挑的这批，那就接着上次练。
      if (words != null &&
          words.isNotEmpty &&
          _sameWordSet(words.map((word) => word.id!).toSet(), wordIds.toSet())) {
        final records = await sessionStore.getSessionRecords(latest.id);
        return ReviewEntry(
          session: latest,
          words: <int, Word>{for (final word in words) word.id!: word},
          records: records,
        );
      }
      // 换了一批词，旧局已经代表不了用户现在想练的东西。
      await sessionStore.finishSession(
        sessionId: latest.id,
        status: SessionStatus.aborted,
      );
    }

    final words = await _wordsInOrder(wordIds);
    if (words == null || words.isEmpty) return null;
    final items = _buildItems(module, wordIds, words);
    if (items.isEmpty) return null;

    final sessionId = await sessionStore.createSession(
      module: module,
      // 随手练固定按巩固算：不推进复习时间，也不占用今天的主线名额。
      kind: SessionKind.reinforce,
      wordSetId: null,
      items: items,
      date: date,
    );
    final session = await sessionStore.getLatestSession(module, date);
    if (session == null || session.id != sessionId) {
      throw StateError('新建的${module.label}会话无法读回');
    }
    return ReviewEntry(
      session: session,
      words: <int, Word>{for (final word in words) word.id!: word},
      records: const <SessionRecord>[],
    );
  }

  ///
  /// 尝试续上一局进行中的会话；续不上返回 null。
  Future<ReviewEntry?> _resume(Session latest, WordSet wordSet) async {
    // 数据列表里引用的单词必须全都还在，缺一个就没法完整还原。
    final words = await _wordsForSession(latest);
    if (words == null || words.isEmpty) return null;

    // 主线局还要额外确认单词和今天的词库仍然一致：设置改过、词库补过词之后，
    // 旧的主线进度已经代表不了「今天的任务」，必须换新局。
    if (latest.kind == SessionKind.daily) {
      final sessionWordIds = words.map((word) => word.id!).toSet();
      if (!_sameWordSet(sessionWordIds, wordSet.todayWordIds.toSet())) return null;
    }

    final records = await sessionStore.getSessionRecords(latest.id);
    return ReviewEntry(
      session: latest,
      words: <int, Word>{for (final word in words) word.id!: word},
      records: records,
    );
  }

  ///
  /// 按会话的数据列表把涉及的单词捞回来；缺任何一个就返回 null。
  ///
  /// 缺词的会话没法完整还原，与其让用户进去看到少了几题，
  /// 不如直接判定这一局失效、重开一局干净的。
  Future<List<Word>?> _wordsForSession(Session session) async {
    // 看义选词的数据列表存的是含义主键，要反查所属单词。
    if (session.module == ReviewModule.meaningWordChoice) {
      final meaningIds = session.idItems;
      final words = await wordStore.getByMeaningIds(meaningIds);
      // 一个词都捞不回来说明这些含义全被删了。
      return words.isEmpty ? null : words;
    }
    final wordIds = session.module == ReviewModule.meaningMatch
        ? session.pairItems.map((pair) => pair.wordId).toList()
        : session.idItems;
    return _wordsInOrder(wordIds);
  }

  ///
  /// 按给定主键顺序组装单词；只要有一个词已不存在就返回 null。
  Future<List<Word>?> _wordsInOrder(List<int> ids) async {
    if (ids.isEmpty) return const <Word>[];
    // 一次查回来再按内存索引重排，避免逐个查库。
    final fetched = await wordStore.getByIds(ids.toSet().toList());
    final byId = <int, Word>{for (final word in fetched) word.id!: word};
    final ordered = <Word>[];
    for (final id in ids) {
      final word = byId[id];
      if (word == null) return null;
      ordered.add(word);
    }
    return List<Word>.unmodifiable(ordered);
  }

  ///
  /// 组装巩固局的单词：今天随机一半 + 明天那一半。
  ///
  /// 明天的词在建库时就按同一套两层规则算好并存进了词库表，这里直接取用。
  /// 明天的词不够一半时就少拿几个，不用今天的词补足——这一局的题量允许缩水。
  List<int> _buildReinforceWordIds(WordSet wordSet) {
    // 今日这边向上取整：宁可多练一个今天的词，巩固局不该让今日复习缩水。
    // 明日那边建库时向下取整（见 _createWordSet），两边咬合后总题量
    // = 每日复习数量（每日 5 → 今日 3 + 明日 2），不会超额。
    final halfTarget = (wordSet.todayWordIds.length * 0.5).ceil();
    final todayPicked = _pickRandom(wordSet.todayWordIds, halfTarget);
    // 两批混在一起再整体打乱，避免前半局全是今天、后半局全是明天。
    final merged = <int>[...todayPicked, ...wordSet.tomorrowWordIds]
      ..shuffle(_random);
    return List<int>.unmodifiable(merged);
  }

  ///
  /// 按模块生成这一局的数据列表。
  ///
  /// - 随身听 / 听音辨义 / 拼写巩固：`[单词id, ...]`，就是会话的单词顺序；
  /// - 词义连连：`[[单词id, 含义id], ...]`，每个词随机挑一条释义；
  /// - 看义选词：`[含义id, ...]`，按释义文本去重后每种取一个代表，再整体打乱。
  List<Object?> _buildItems(
    ReviewModule module,
    List<int> wordIds,
    List<Word> words,
  ) {
    switch (module) {
      case ReviewModule.listening:
      case ReviewModule.listeningMeaning:
      case ReviewModule.spellingReinforcement:
        return List<Object?>.unmodifiable(wordIds);

      case ReviewModule.meaningMatch:
        // 每个词随机挑一条释义，配成 [单词id, 含义id]。
        // 没有释义的词出不了题，直接跳过。
        //
        // 数据列表**不补位**：棋盘每组最多 5 对，最后一组不足 5 对就少显示
        // （页面按实际张数铺开、整块垂直居中）。过去为了凑满一组会把前面的
        // 词复制进末组，词太少时同一张卡会在棋盘里出现两次，而连对记录只认
        // 「单词+含义」——重进恢复现场时会把重复的卡认错格子、少恢复一条线。
        return List<Object?>.unmodifiable(<List<int>>[
          for (final word in words)
            if (word.allMeanings.isNotEmpty)
              _randomPairFor(word),
        ]);

      case ReviewModule.meaningWordChoice:
        // 按释义文本去重：同一句中文可能同时属于多个单词（eat 的「吃」和
        // feed 的「吃」），这时它们是同一道题，答案有多个。这里每种文本
        // 只留一个代表主键，运行时再把同文本的单词全部合并成正确答案。
        final seen = <String>{};
        final meaningIds = <int>[];
        for (final word in words) {
          for (final meaning in word.allMeanings) {
            final text = meaning.definition.trim();
            // 空释义不能成为一道题。
            if (text.isEmpty || meaning.id == null) continue;
            if (!seen.add(text)) continue;
            meaningIds.add(meaning.id!);
          }
        }
        // 全局打乱：同一个多义词的多条释义被拆散到全程，避免连续考同一个词。
        meaningIds.shuffle(_random);
        return List<Object?>.unmodifiable(meaningIds);
    }
  }

  ///
  /// 给词义连连挑一对 `[单词id, 含义id]`。
  ///
  /// 一个词往往有好几条释义，这里随机挑一条：同一批词多开几局，
  /// 出现的中文也会换着来，不至于每次都考同一句。
  List<int> _randomPairFor(Word word) {
    final meanings = word.allMeanings;
    return <int>[word.id!, meanings[_random.nextInt(meanings.length)].id!];
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
  /// 比较两组单词主键是否是同一批（不看顺序）。
  ///
  /// 巩固局会打乱顺序，主线局也可能因为补词而改变排列，
  /// 真正要判断的是「还是不是今天这批词」。
  bool _sameWordSet(Set<int> first, Set<int> second) {
    if (first.length != second.length) return false;
    return first.containsAll(second);
  }
}
