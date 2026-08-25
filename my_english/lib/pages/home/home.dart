// dart:async 提供 Timer 和 unawaited，分别用于搜索防抖和触发异步任务。
import 'dart:async';
// convert 提供 jsonDecode / JsonEncoder，用于解析导入 JSON 与生成导出 JSON。
import 'dart:convert';

// material.dart 提供页面、布局、加载指示器和按钮等 Flutter UI 组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供分组头的勾选和折叠方向图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
// url_launcher 用于点击仓库地址时用系统默认浏览器打开外部链接。
import 'package:url_launcher/url_launcher.dart';
// services 提供剪贴板，用于点击作者邮箱时把内容复制到系统剪贴板。
import 'package:flutter/services.dart';

// 引入公共主题与设计令牌。
import '../../common/theme.dart';
// 引入全局 Toast 工具，替代 ScaffoldMessenger，层级高于 Drawer/BottomSheet。
import '../../common/toast.dart';
// 日期 helper 负责列表与分组标题的日期格式。
import '../../common/date.dart';
// Word 是全应用共享模型，不属于首页私有文件。
import '../../models/word.dart';
// 学习会话模型用于判断随身听和听音辨义是否存在未完成历史。
import '../../models/learning_session.dart';
// 每日词库保存四个模块当天共用的单词主键与顺序。
import '../../models/daily_word_set.dart';
// 复习会话模型提供模块标识、主线/巩固类型与三态进度。
import '../../models/review_session.dart';
// 音频服务由首页、随身听和听音辨义共同复用。
import '../../services/word_audio.dart';
// 离线语音缓存进度服务：首页加载词库后把单词列表交给它，供抽屉"离线语音"使用。
import '../../services/word_audio_cache.dart';
// 原生 SAF 文件读写服务：导入选 JSON、导出写文件，不依赖第三方 file_picker。
import '../../services/file_io.dart';
// 全屏听音辨义页。
import '../listening_meaning/listening_meaning_page.dart';
// 全屏随身听页。
import '../listening/listening_page.dart';
// 词义连连骨架页（顶部框架已就位，候选词区域待接入）。
import '../meaning_match/meaning_match_page.dart';
// 拼写巩固页：听发音、看释义拼出单词，片段与逐字母两种作答方式。
import '../spelling_reinforcement/spelling_reinforcement_page.dart';
// 三个未开发复习模块使用各自标题的独立占位页面。
import '../review/review_unavailable_page.dart';
// 分组 Store 通过原生 SQLite 提供持久化的自定义分组数据。
import '../../store/group.dart';
// 设置 Store 提供持久化口音、主题与每日复习目标。
import '../../store/settings.dart';
// 单词 Store 同样放在页面目录之外，其他页面可以直接复用。
import '../../store/word.dart';
// 复习记录 Store：今日复习数量从真实记录读取，而非写死 0。
import '../../store/review_record.dart';
// 学习会话 Store 负责读取和删除本地恢复点。
import '../../store/learning_session.dart';
// 每日词库 Store 独立于普通随身听/听音辨义会话。
import '../../store/daily_word_set.dart';
// 复习会话 Store 管理四个模块的每日主线与巩固练习。
import '../../store/review_session.dart';
// 复习流程服务把「备词库 → 开会话」这两步收敛到一处。
import '../review/services/review_flow.dart';
// 分组行：模式切换、筛选 chips 与分组管理入口。
import 'widgets/group_filter_bar.dart';
// 右侧抽屉菜单。
import 'widgets/home_drawer.dart';
// 分组管理面板。
import 'widgets/manage_groups_sheet.dart';
// 移动/复制目标选择面板。
import 'widgets/group_picker_sheet.dart';
// 添加/修改单词表单。
import 'widgets/word_form_sheet.dart';
// 设计稿风格的单词行。
import 'widgets/word_list_tile.dart';
// 排序行与选择模式工具行。
import 'widgets/word_sort_bar.dart';
// 纯排序服务负责搜索过滤和多级稳定排序，页面只提供当前交互参数。
import 'services/home_word_sorter.dart';

// 仪表盘：趋势曲线 + 打卡热力图 + 复习模式入口。
import 'widgets/dashboard/home_dashboard.dart';
// 底部词库抽屉。
import 'widgets/word_library_sheet.dart';

///
/// 首页组件：仪表盘、词库抽屉与数据管理的统一入口页面。
///
class HomePage extends StatefulWidget {
  ///
  /// store 允许测试注入假实现；真实 App 不传时使用原生 SQLite Store。
  const HomePage({
    super.key,
    this.store,
    this.settings,
    this.audioPlayer,
    this.fileIo,
    this.sessionStore,
    this.wordSetStore,
    this.reviewSessionStore,
  });

  ///
  /// 依赖以接口类型声明，页面不关心数据具体来自 SQLite 还是测试内存。
  final WordStore? store;

  ///
  /// 全局设置由 MainApp 注入；独立测试不传时使用纯内存默认值。
  final SettingsStore? settings;

  ///
  /// 音频接口允许测试注入，不依赖真实网络和 Android MediaPlayer。
  final WordAudioPlayer? audioPlayer;

  ///
  /// 文件读写接口允许测试注入，不依赖真实系统选择器与 Android SAF。
  final LocalFileIo? fileIo;

  ///
  /// 学习会话接口允许测试注入内存实现；正式 App 使用 SQLite。
  final LearningSessionStore? sessionStore;

  /// 每日词库接口允许测试注入内存实现；正式 App 使用 SQLite。
  final DailyWordSetStore? wordSetStore;

  /// 复习会话接口允许测试注入内存实现；正式 App 使用 SQLite。
  final ReviewSessionStore? reviewSessionStore;

  ///
  /// 为页面创建保存 data 和生命周期的 State。
  @override
  State<HomePage> createState() => _HomePageState();
}

///
/// 一个分组区块：标题信息与其中经过搜索、排序后的单词。
///
class _WordSection {
  ///
  /// 创建区块。
  const _WordSection({
    required this.key,
    required this.name,
    required this.words,
  });

  ///
  /// 稳定标识，用于折叠与筛选（如 c1、d5、u20260726）。
  final String key;

  ///
  /// 分组标题文字。
  final String name;

  ///
  /// 区块内经过搜索过滤与排序的单词。
  final List<Word> words;
}

///
/// 下划线表示状态类仅当前文件可见；Observer 接收 App Show/Hide 等状态。
///
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  ///
  /// Scaffold key 用于以编程方式打开右侧抽屉。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 底部词库是否已经展开；默认 false，确保词库面板完全位于屏幕下方。
  bool _wordLibraryExpanded = false;

  /// 当前这次全屏触摸累计的纵向移动量；负数表示向上滑。
  double _globalVerticalDrag = 0;

  /// 当前手势是否已经触发过词库展开，避免同一次滑动重复调用。
  bool _globalSwipeHandled = false;

  /// 全屏上滑需要累计达到的距离；180 明显高于普通浏览时的一小段滚动，
  /// 只有一次较长、明确的上滑才会展开词库。
  static const double _wordLibrarySwipeDistance = 180;

  ///
  /// Scrollbar 和 CustomScrollView 必须共享同一个控制器，滑块才可以被直接拖动。
  final ScrollController _scrollController = ScrollController();

  ///
  /// 搜索防抖定时器；上万条数据时避免每按一个键立即重复过滤。
  Timer? _searchDebounce;

  ///
  /// 单词加载超时定时器；页面提前关闭时必须主动取消，避免留下仍在等待的任务。
  Timer? _loadTimeout;

  ///
  /// 页面最终使用的单词 Store，在 initState 中完成一次赋值。
  late final WordStore _store;

  ///
  /// 首页和设置面板共享的设置 Store。
  late final SettingsStore _settings;

  ///
  /// true 表示首页为了测试自行创建了内存设置，dispose 时需要释放。
  late final bool _ownsSettings;

  ///
  /// 真正执行缓存和播放的音频接口。
  late final WordAudioPlayer _audioPlayer;

  /// 当前前台会话是否已经提示过系统 TTS。
  bool _hasShownTtsNotice = false;

  ///
  /// 原生 SAF 文件读写服务：导入选 JSON、导出写文件。
  /// 默认走 Android 原生通道；测试可注入假通道避免真正弹出系统选择器。
  late final LocalFileIo _fileIo;

  ///
  /// 随身听和听音辨义共用的学习会话持久化接口。
  late final LearningSessionStore _sessionStore;

  /// 四个复习模块当天共用的每日词库持久化接口。
  late final DailyWordSetStore _wordSetStore;

  /// 四个复习模块的会话持久化接口。
  late final ReviewSessionStore _reviewSessionStore;

  ///
  /// 复习流程服务：备今天的词库、决定这一局开主线还是开巩固。
  late final ReviewFlow _reviewFlow;

  ///
  /// 自定义分组 Store；分组与成员关系均由原生 SQLite 持久化。
  final GroupStore _groups = GroupStore();

  ///
  /// Store 一次加载全部未删除单词；每组 SliverList 仍然只惰性构建可见行。
  List<Word> _allWords = const <Word>[];

  ///
  /// 今日复习已完成的单词数（去重），来自真实 record，用于副标题展示。
  int _reviewCount = 0;

  ///
  /// 今天四个复习模块各自的三态进度：待完成 / 进行中 / 已完成。
  ///
  /// 今天还没开过局的模块不会出现在这里，读取时按 [ReviewModuleState.empty] 处理。
  Map<ReviewModule, ReviewModuleState> _reviewModuleStates =
      const <ReviewModule, ReviewModuleState>{};

  ///
  /// 仪表盘“回刷序号”：每完成一次复习数据回刷就 +1。
  ///
  /// 生活化解释：趋势曲线和打卡日历这两张卡片各自管着自己的数据，只在第一次
  /// 出现时查一次数据库，之后首页再怎么 setState 它们都不会重查。这个数字就是
  /// 给它们发的“通知单号”——号变了就说明复习数据更新了，请重新查一次。
  int _dashboardRefreshToken = 0;

  /// 今天已经生成的每日词库；null 表示今天尚未点击过任何复习模块。
  DailyWordSet? _dailyWordSet;

  ///
  /// 正在打开的模块，以及它那一次「备词库 → 开会话」的共享任务。
  ///
  /// 生活化解释：用户手快连点两下「听音辨义」，第二下会直接复用第一下的
  /// 结果，而不是再走一遍完整流程，否则同一模块会冒出两局。
  ///
  /// 键必须带上模块：连点的如果是两张不同的卡片，第二张要老老实实自己去开局，
  /// 不能拿第一张的结果——那会让词义连连拿到听音辨义的会话。
  (ReviewModule, Future<ReviewEntry?>)? _openModuleRequest;

  ///
  /// 上一次已知的每日复习数量，用来发现用户在抽屉里改了设置。
  ///
  /// 数量一变，今天这批词就要重新算，所有进行中的会话必须强行中断。
  int? _lastKnownDailyGoal;

  ///
  /// 保存已展开的 Word 对象；spelling 可重复，所以不能把拼写当作行身份。
  final Set<Word> _expandedWords = <Word>{};

  ///
  /// 选择模式下被勾选的 Word 对象集合。
  final Set<Word> _selectedWords = <Word>{};

  ///
  /// 本地尚未完成的学习会话；两种类型各自最多一条。
  Map<LearningSessionType, LearningSession> _learningSessions =
      const <LearningSessionType, LearningSession>{};

  ///
  /// 当前处于下载或播放状态的具体 Word 对象。
  Word? _playingWord;

  ///
  /// 当前左滑露出操作区的行；同一时刻最多一行。
  Word? _swipedWord;

  ///
  /// 当前分组视角，默认按自定义分组。
  GroupMode _mode = GroupMode.custom;

  ///
  /// 当前筛选的分组区块 key；null 表示"全部"。
  String? _filterKey;

  ///
  /// 已折叠的分组区块 key 集合。
  final Set<String> _collapsedKeys = <String>{};

  ///
  /// 是否处于选择模式。
  bool _selectMode = false;

  ///
  /// 当前使用的排序字段，默认按“字母”规则（spelling 升序）展示。
  WordSortField _sortField = WordSortField.original;

  ///
  /// 每个可排序字段各自记住方向；true 升序，false 降序。
  final Map<WordSortField, bool> _sortDirections = <WordSortField, bool>{
    // 默认（已对齐“字母”）第一次点击从 A 到 Z。
    WordSortField.original: true,
    // 含义永远升序：先按释义数量，再按释义字符总数，简单单词排在前面。
    WordSortField.meaning: true,
    // 难度第一次点击从高到低。
    WordSortField.difficulty: false,
    // 日期第一次点击从最近到最早。
    WordSortField.date: false,
  };

  ///
  /// 当前真正参与过滤的小写搜索词。
  String _query = '';

  ///
  /// 页面是否仍在等待 SQLite 查询。
  bool _isLoading = true;

  ///
  /// 数据加载异常；null 表示没有错误。
  Object? _loadError;

  ///
  /// 列表静态日期使用的年份参考值。
  late DateTime _dateReference;

  ///
  /// StatefulWidget 生命周期方法，只在首页首次创建时执行一次。
  @override
  void initState() {
    // 保留 StatefulWidget 父类初始化流程。
    super.initState();
    // 同一初始时刻供问候语和列表年份判断使用。
    final initialTime = DateTime.now();
    // 有测试 Store 就使用注入值，否则使用全局 SQLite Store。
    _store = widget.store ?? LocalWordStore.instance;
    // 记录设置 Store 是否由首页临时创建。
    _ownsSettings = widget.settings == null;
    // 生产环境使用 MainApp 注入值，独立 Widget 测试使用默认内存设置。
    _settings = widget.settings ?? SettingsStore.inMemory();
    // 生产环境默认走 Android 原生服务，测试可以注入立即完成的假播放器。
    _audioPlayer = widget.audioPlayer ?? LocalWordAudioPlayer();
    // 生产环境默认走 Android 原生 SAF 通道，测试可以注入假文件服务。
    _fileIo = widget.fileIo ?? const LocalFileIo();
    // 生产环境复用 SQLite 单例，测试可用内存 Store 精确控制“继续”入口。
    _sessionStore = widget.sessionStore ?? LocalLearningSessionStore.instance;
    // 每日词库与复习会话各用独立 Store，不与普通学习会话混为一种数据。
    _wordSetStore = widget.wordSetStore ?? LocalDailyWordSetStore.instance;
    _reviewSessionStore =
        widget.reviewSessionStore ?? LocalReviewSessionStore.instance;
    // 复习流程只依赖上面两个 Store，测试注入内存实现即可完整验证选词与开局。
    _reviewFlow = ReviewFlow(
      wordSetStore: _wordSetStore,
      sessionStore: _reviewSessionStore,
    );
    // 记下启动时的每日复习量，之后靠它发现用户在抽屉里改过设置。
    _lastKnownDailyGoal = _settings.dailyGoal;
    // 初始化列表年份参考。
    _dateReference = initialTime;
    // 注册 App 前后台观察者。
    WidgetsBinding.instance.addObserver(this);
    // 监听设置变化，让副标题的复习目标即时刷新。
    _settings.addListener(_handleExternalChange);
    // 监听分组变化：分组被删除时把其中单词移回"未分组"。
    _groups.addListener(_handleGroupsChanged);
    // 先加载分组（决定分组列表与顺序），再加载单词及其分组关系。
    unawaited(_groups.load());
    // 异步加载全部 Word/Meaning；方法内部完成 setState。
    unawaited(_loadWords());
    // 读取今日复习数量，让副标题的「今日复习 X/目标」显示真实数据而非写死的 0。
    unawaited(_loadReviewProgress());
    // 若今天已经建过词库，先恢复它供首页展示。
    unawaited(_loadDailyWordSet());
    // 独立读取未完成会话，不让辅助数据阻塞首页单词列表首屏。
    unawaited(_loadLearningSessions());
    // 跨天后昨天没打完的局挂着没有意义，启动时统一收成「中断」。
    unawaited(_abortStaleReviewSessions());
  }

  ///
  /// 把昨天及更早还挂在「进行中」的复习会话统一改成「中断」。
  ///
  /// 生活化解释：昨天做到一半退出去了，今天再打开 App，那一局已经没有意义
  /// ——今天有今天的词库。不收掉的话，数据库里会攒下一堆永远不会结束的局。
  Future<void> _abortStaleReviewSessions() async {
    try {
      // onlyStale 为 true 表示只动「不是今天」的会话，今天的进度完整保留。
      await _reviewSessionStore.abortActive(onlyStale: true);
    } catch (error) {
      // 清理属于后台维护动作，失败只写日志，绝不影响首页展示。
      debugPrint('清理过期复习会话失败：$error');
    }
  }

  ///
  /// 设置或分组内容变化时触发整页重建。
  void _handleExternalChange() {
    // 页面已卸载时不再处理任何状态。
    if (!mounted) return;
    // 每日复习量变了：今天这批词要重新算，所有进行中的会话必须强行中断。
    if (_lastKnownDailyGoal != _settings.dailyGoal) {
      _lastKnownDailyGoal = _settings.dailyGoal;
      unawaited(_handleDailyGoalChanged());
    }
    // 页面存活时才重建。
    setState(() {});
  }

  ///
  /// 用户改了「每日复习」数量后的收尾。
  ///
  /// 按《复习模块》的约定，数量一变就强行中断所有模块的会话：旧的那一局
  /// 已经代表不了今天的任务了。词库本身不在这里改——下次点开任意模块时，
  /// [ReviewFlow.resolveWordSet] 会按新数量截取或补足。
  Future<void> _handleDailyGoalChanged() async {
    try {
      // onlyStale 为 false 表示今天的局也一起收掉。
      await _reviewSessionStore.abortActive();
    } catch (error) {
      // 即使这里失败也不会出错：下次开局时流程会发现单词对不上，照样中断重开。
      debugPrint('中断复习会话失败：$error');
    }
    if (!mounted) return;
    // 内存里缓存的旧词库数量已经不对，清掉让下次开局重新读取。
    setState(() => _dailyWordSet = null);
    // 四张卡片的三态、头部数字与曲线一起重算。
    await _refreshReviewDashboard();
  }

  ///
  /// 分组列表变化：清理指向已删除分组的单词与筛选。
  void _handleGroupsChanged() {
    // 先按通用逻辑重建界面。
    _handleExternalChange();
    // 再把孤儿单词移回"未分组"。
    unawaited(_reassignOrphanWords());
  }

  ///
  /// 把指向已删除分组的单词批量移回"未分组"（防御性清理）。
  Future<void> _reassignOrphanWords() async {
    // 收集所有仍然指向不存在分组的单词（理论上 deleteGroup 已清成员关系）。
    final orphans = _allWords
        .where(
          (word) =>
              word.groupIds.any((groupId) => _groups.byId(groupId) == null),
        )
        .toList(growable: false);
    // 没有孤儿时直接结束。
    if (orphans.isEmpty) return;
    // 逐个更新回"未分组"（groupIds 清空）。
    for (final word in orphans) {
      await _store.update(word.withGroup(null));
    }
    // 更新完成后刷新列表数据。
    await _refreshWords();
  }

  ///
  /// 按当前页面状态创建纯排序服务；服务不持有 Widget，可独立测试。
  HomeWordSorter get _wordSorter => HomeWordSorter(
    // 分组视角决定日期字段取 reviewedAt、updatedAt 或 createdAt。
    mode: _mode,
    // 当前排序入口由工具栏维护。
    field: _sortField,
    // 各字段保留自己的升降序。
    directions: _sortDirections,
    // 搜索防抖完成后保存的小写查询词。
    query: _query,
  );

  ///
  /// 返回当前分组视角下列表行应展示的日期。
  DateTime? _listDateOf(Word word) => _wordSorter.dateOf(word);

  ///
  /// 对一个区块执行搜索过滤与稳定排序。
  List<Word> _filterAndSort(List<Word> source) {
    // 业务比较规则集中在独立服务，页面只负责提供当前交互状态。
    return _wordSorter.filterAndSort(source);
  }

  ///
  /// 按当前分组视角把全部单词组织成区块列表。
  List<_WordSection> _buildSections() {
    // 汇总结果。
    final sections = <_WordSection>[];
    // 自定义分组视角。
    if (_mode == GroupMode.custom) {
      // 没有任何分组的单词全部归入"未分组"（groupIds 为空即未分组）。
      final ungrouped = _allWords
          .where((word) => word.groupIds.isEmpty)
          .toList();
      // 未分组只有在确实有单词或没有任何自定义分组时才显示。
      // 它最先加入 sections，因此筛选行中的优先级固定为“全部”之后第一项。
      if (ungrouped.isNotEmpty || _groups.groups.isEmpty) {
        sections.add(
          _WordSection(
            key: 'c0',
            name: GroupStore.ungroupedName,
            words: _filterAndSort(ungrouped),
          ),
        );
      }
      // 已存在的自定义分组排在“未分组”之后，并保持用户自己的管理顺序（允许 0 词）。
      // 一个单词若被复制进多个分组，会同时出现在这些分组的 section 中。
      for (final group in _groups.groups) {
        sections.add(
          _WordSection(
            key: 'c${group.id}',
            name: group.name,
            words: _filterAndSort(
              _allWords
                  .where((word) => word.groupIds.contains(group.id))
                  .toList(),
            ),
          ),
        );
      }
      return sections;
    }
    // 难度视角：数值从高到低，"无难度"固定在最后。
    if (_mode == GroupMode.difficulty) {
      // 业务约定：难度 0 与"无难度"(null) 是同一概念，内部必须合并成同一个组，
      // 不能像以前那样把 0 显示成"难度 0"、把 null 显示成"无难度"分成两个区块。
      // 因此先把每个单词的难度按 null→0 归一成 int，再收集去重。
      final values = <int>{
        for (final word in _allWords) word.difficulty ?? 0,
      }.toList()..sort((a, b) => b.compareTo(a));
      // 逐个难度生成区块；分区筛选与单词归属都用 (difficulty ?? 0) 比较。
      for (final value in values) {
        sections.add(
          _WordSection(
            // 合并后 0 与 null 共用 key 'd0'，不再出现 'dx'。
            key: 'd$value',
            // 值为 0 表示"无难度"（含原 null 单词），其余显示具体难度。
            name: value == 0 ? '无难度' : '难度 $value',
            words: _filterAndSort(
              _allWords
                  .where((word) => (word.difficulty ?? 0) == value)
                  .toList(),
            ),
          ),
        );
      }
      return sections;
    }
    // 时间视角分组：复用 _listDateOf 确保分组日期与列表行显示日期完全一致。
    // 复习时间视角 → reviewedAt；更新时间视角 → updatedAt；加入时间视角 → createdAt。
    ///
    /// 读取当前分组视角下用于分段的单词日期。
    DateTime? dateOf(Word word) => _listDateOf(word);
    // 收集出现过的"天"数字键（yyyyMMdd），null 单独一组。
    final dayKeys = <int>{};
    var hasNullDate = false;
    for (final word in _allWords) {
      final date = dateOf(word);
      if (date == null) {
        hasNullDate = true;
      } else {
        final local = date.toLocal();
        dayKeys.add(local.year * 10000 + local.month * 100 + local.day);
      }
    }
    // 日期从新到旧排列。
    final sortedKeys = dayKeys.toList()..sort((a, b) => b.compareTo(a));
    // 视角前缀让折叠状态在三个时间视角之间互不串扰。
    final prefix = switch (_mode) {
      // 复习时间视角前缀 r。
      GroupMode.reviewed => 'r',
      // 更新时间视角前缀 u。
      GroupMode.updated => 'u',
      // 加入时间视角前缀 a。
      _ => 'a',
    };
    // 逐天生成区块。
    for (final dayKey in sortedKeys) {
      // 还原该天日期对象用于格式化标题。
      final day = DateTime(
        dayKey ~/ 10000,
        dayKey % 10000 ~/ 100,
        dayKey % 100,
      );
      sections.add(
        _WordSection(
          key: '$prefix$dayKey',
          name: formatWordDate(day, _dateReference),
          words: _filterAndSort(
            _allWords.where((word) {
              final date = dateOf(word);
              if (date == null) return false;
              final local = date.toLocal();
              return local.year * 10000 + local.month * 100 + local.day ==
                  dayKey;
            }).toList(),
          ),
        ),
      );
    }
    // 没有日期的单词固定放在最后一组；复习时间视角下"没有日期"即"从未复习"。
    if (hasNullDate) {
      sections.add(
        _WordSection(
          key: '${prefix}0',
          name: _mode == GroupMode.reviewed ? '未复习' : '无日期',
          words: _filterAndSort(
            _allWords.where((word) => dateOf(word) == null).toList(),
          ),
        ),
      );
    }
    return sections;
  }

  ///
  /// 点击排序项：新字段使用预设方向，再点当前字段则切换方向。
  void _handleSortSelected(WordSortField field) {
    // setState 同时处理字段选择和当前字段方向翻转。
    // 默认项现已支持升降序切换，因此与其他字段走同一套逻辑。
    setState(() {
      // 再次点击当前字段时翻转升降序。
      if (_sortField == field) {
        _sortDirections[field] = !(_sortDirections[field] ?? true);
      } else {
        // 第一次切到该字段时保留它自己的默认或上次方向。
        _sortField = field;
      }
    });
  }

  ///
  /// 从 Store 一次读取全部本地单词（带加载与错误界面）。
  Future<void> _loadWords() async {
    // 重试时立即切回加载状态并清空旧错误。
    setState(() {
      // 显示进度指示器。
      _isLoading = true;
      // 清除上次 PlatformException。
      _loadError = null;
    });

    // 保存“本次请求”的 Timer；finally 只清理它，不会误伤之后可能发起的新请求。
    Timer? requestTimeout;
    try {
      // Completer 用于手动控制这个异步结果何时完成、成功还是失败。
      final loadResult = Completer<List<Word>>();
      // 先取得 Store 的异步结果；数据来自 Android 原生通道（本地 SQLite 持久化）。
      final storeRequest = _store.getAll();
      // 如果上一次加载仍残留超时计时，先取消，保证同一页面同时只有一个超时闹钟。
      _loadTimeout?.cancel();
      // 单独保存本次 Timer，finally 才不会误取消未来另一轮加载新建的 Timer。
      final currentTimeout = Timer(const Duration(seconds: 8), () {
        // Store 已经返回时不能重复完成 Completer。
        if (loadResult.isCompleted) return;
        // 原生通道长期不回包时转成可见错误，页面会显示“重新加载”。
        loadResult.completeError(StateError('数据源读取超时（原生通道无响应）'));
      });
      // 把本次 Timer 放进局部引用，供 finally 在成功、异常两种路径统一释放。
      requestTimeout = currentTimeout;
      // 保存到字段后，dispose 中才能主动取消它。
      _loadTimeout = currentTimeout;
      // Store 成功时把单词列表转交给统一的 loadResult。
      unawaited(
        storeRequest.then(
          (words) {
            // 超时已经先发生时忽略迟到结果，避免重复完成 Future。
            if (!loadResult.isCompleted) loadResult.complete(words);
          },
          onError: (Object error, StackTrace stackTrace) {
            // Store 自身失败时保留原始异常与堆栈，方便错误界面和日志定位。
            if (!loadResult.isCompleted) {
              loadResult.completeError(error, stackTrace);
            }
          },
        ),
      );
      // await 等待这个 Future 完成，后续 UI 逻辑无需区分数据来自成功路径还是超时路径。
      final words = await loadResult.future;
      // 页面可能在查询期间被关闭；mounted=false 时不能再 setState。
      if (!mounted) return;
      // 一次写入全部数据并结束加载状态。
      setState(() {
        // 保存本地 SQLite 持久化返回的 Word/Meaning（App 仅此一种数据来源）。
        _allWords = words;
        // 数据重载后清除已经不存在的展开、选中与滑动状态。
        _expandedWords.removeWhere((word) => !words.contains(word));
        _selectedWords.removeWhere((word) => !words.contains(word));
        if (_swipedWord != null && !words.contains(_swipedWord)) {
          _swipedWord = null;
        }
        // 隐藏加载指示器。
        _isLoading = false;
      });
      // 把最新词库告知离线语音缓存服务，用于计算总数与初始已缓存百分比。
      // 通道不可用（如单元测试无原生实现）时服务内部会安全回退为 0。
      unawaited(
        WordAudioCache.instance.setWordList(
          words.map((word) => word.spelling).toList(),
        ),
      );
    } catch (error, stackTrace) {
      // 调试控制台保留完整错误和调用堆栈，真机日志也能直接查到根因。
      debugPrint('单词数据加载失败：$error');
      // stackTrace 记录完整调用堆栈，帮助定位具体代码行。
      debugPrintStack(stackTrace: stackTrace);
      // 页面已销毁时不再处理错误 UI。
      if (!mounted) return;
      // 保存错误并结束加载状态，界面会显示重试按钮。
      setState(() {
        // 记录原始异常供调试。
        _loadError = error;
        // 隐藏加载动画。
        _isLoading = false;
      });
    } finally {
      // 无论成功、Store 报错还是超时，本次计时器都必须停止。
      requestTimeout?.cancel();
      // 只有字段仍指向本次 Timer 时才清空，避免覆盖后来一轮加载的引用。
      if (identical(_loadTimeout, requestTimeout)) _loadTimeout = null;
    }
  }

  ///
  /// 增删改之后的轻量刷新：重新读取数据但不显示整页加载圈。
  Future<void> _refreshWords() async {
    // 读取最新数据。
    final words = await _store.getAll();
    // 页面可能已销毁。
    if (!mounted) return;
    // 建立仍然存在的数据库主键集合，用来检查当天公共词单是否需要补位。
    final existingWordIds = <int>{
      for (final word in words)
        if (word.id != null) word.id!,
    };
    // 与 _loadWords 相同的状态清理。
    setState(() {
      _allWords = words;
      _expandedWords.removeWhere((word) => !words.contains(word));
      _selectedWords.removeWhere((word) => !words.contains(word));
      if (_swipedWord != null && !words.contains(_swipedWord)) {
        _swipedWord = null;
      }
      // 词库里的单词被删除时只释放内存缓存，不直接丢掉数据库中的其余顺序。
      // 下次进入任意复习模块时，ReviewFlow 会读取原词库、保留仍有效的 id，
      // 再按同一套排序规则补足缺口。
      final wordSet = _dailyWordSet;
      if (wordSet != null &&
          wordSet.wordIds.any((id) => !existingWordIds.contains(id))) {
        _dailyWordSet = null;
      }
    });
    // 增删改后同样刷新离线语音缓存服务的总数与已缓存百分比。
    unawaited(
      WordAudioCache.instance.setWordList(
        words.map((word) => word.spelling).toList(),
      ),
    );
    // 编辑或删除单词可能由原生同步作废学习会话，刷新后立即同步继续入口。
    await _loadLearningSessions();
  }

  ///
  /// 读取今日复习数与四个模块各自的三态进度。
  ///
  /// 今日复习数的口径是「今天一次做对过的不同单词数」——练了但错过的不算，
  /// 用户要看的是真正拿下了多少个词。通道不可用（如单元测试）时静默回退为
  /// 空值，不影响首页其余功能。
  Future<void> _loadReviewProgress() async {
    // try/catch 兜底原生通道异常，保证首页在测试或异常环境下不崩溃。
    try {
      // 两个查询彼此独立，并发执行让首页数字几乎瞬间到位。
      final results = await Future.wait<Object>(<Future<Object>>[
        LocalReviewRecordStore.instance.getTodayReviewWordCount(),
        _reviewSessionStore.getTodayStates(),
      ]);
      // 页面可能在异步期间被关闭。
      if (!mounted) return;
      // 更新副标题与四张卡片的展示数据。
      setState(() {
        _reviewCount = results[0] as int;
        _reviewModuleStates =
            results[1] as Map<ReviewModule, ReviewModuleState>;
      });
    } catch (error, stackTrace) {
      // 调试输出保留完整错误与堆栈，方便真机日志定位。
      debugPrint('读取今日复习进度失败：$error');
      debugPrintStack(stackTrace: stackTrace);
      // 页面已销毁则不处理 UI。
      if (!mounted) return;
      // 通道异常时回退为空，副标题与卡片仍可正常显示。
      setState(() {
        _reviewCount = 0;
        _reviewModuleStates = const <ReviewModule, ReviewModuleState>{};
      });
    }
  }

  ///
  /// 从任意复习模块返回首页后，把仪表盘上的全部进度重新算一遍。
  ///
  /// 生活化解释：以前只有“手势返回”这条路会回刷进度，而从完成页点箭头返回时
  /// 只补了单词数据，导致头部「今日复习 X/目标」、四张模式卡的百分比、趋势曲线
  /// 和打卡日历全都停留在进入模块前的旧数字。这里把四件事一次做完：
  /// 1. 重新统计今日复习量（头部副标题 + 听音辨义等卡片百分比）；
  /// 2. 重新读取当天冻结的公共词单（四张卡片共用的分母）；
  /// 3. 重新读取未完成会话（词义连连百分比 + 各模块「继续」入口）；
  /// 4. 递增回刷序号，通知趋势曲线与打卡日历重查数据库。
  ///
  /// 三个读取彼此独立，用 Future.wait 并发执行，回到首页几乎瞬间完成。
  Future<void> _refreshReviewDashboard() async {
    await Future.wait<void>(<Future<void>>[
      _loadReviewProgress(),
      _loadDailyWordSet(),
      _loadLearningSessions(),
    ]);
    // 页面可能在等待期间被关闭。
    if (!mounted) return;
    // 序号变化会让两张自管数据的卡片在 didUpdateWidget 里重新查询。
    setState(() => _dashboardRefreshToken += 1);
  }

  ///
  /// 读取今天已经建好的每日词库，只恢复数据，不主动创建。
  Future<void> _loadDailyWordSet() async {
    try {
      // null 表示今天还没有点开过任何复习模块。
      final wordSet = await _wordSetStore.getToday();
      if (!mounted) return;
      // 原生没有返回词库时也要清掉内存旧值，避免跨天后仍显示昨天那批词。
      setState(() => _dailyWordSet = wordSet);
    } catch (error) {
      // 词库属于辅助状态，读取失败不应阻断首页和底部普通学习入口。
      debugPrint('读取今日词库失败：$error');
    }
  }

  ///
  /// 打开一个复习模块：备好今天的词库，再决定这一局开主线还是开巩固。
  ///
  /// 真正的判断逻辑全在 [ReviewFlow.openModule] 里，这里只负责三件事：
  /// 1. 用一个共享 Future 挡住快速连点，避免同一模块冒出两局；
  /// 2. 把结果里的词库同步进内存，供首页展示；
  /// 3. 把原生异常转成用户看得懂的提示。
  Future<ReviewEntry?> _openReviewSession(ReviewModule module) {
    // 同一个模块已经有请求在跑时直接共用，杜绝连点开出两局。
    final running = _openModuleRequest;
    if (running != null && running.$1 == module) return running.$2;

    final request = _openReviewSessionInternal(module);
    _openModuleRequest = (module, request);
    // 请求结束后释放临时引用，下一次点击会重新走完整流程。
    unawaited(
      request.whenComplete(() {
        // 只清理自己那一条，避免把后来者的请求误删。
        if (identical(_openModuleRequest?.$2, request)) {
          _openModuleRequest = null;
        }
      }),
    );
    return request;
  }

  ///
  /// 实际执行「备词库 → 开会话」，并把异常收敛成一次用户提示。
  Future<ReviewEntry?> _openReviewSessionInternal(ReviewModule module) async {
    try {
      final entry = await _reviewFlow.openModule(
        module,
        allWords: _allWords,
        dailyGoal: _settings.dailyGoal,
      );
      if (!mounted) return null;
      // 词库为空说明本地一个可复习的单词都没有。
      if (entry == null) {
        Toast.show(context, '当前词库没有可复习单词');
        return null;
      }
      // 把这一局用的词库同步进内存，首页无需再查一次数据库。
      unawaited(_loadDailyWordSet());
      return entry;
    } catch (error, stackTrace) {
      debugPrint('打开复习模块失败：$error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) Toast.show(context, '打开${module.label}失败，请重试');
      return null;
    }
  }

  ///
  /// 读取随身听与听音辨义的未完成会话，失败时只隐藏“继续”按钮，不影响首页主体。
  Future<void> _loadLearningSessions() async {
    try {
      // 这里只剩随身听和词库底部的普通听音辨义：它们长期有效、不按日期过期，
      // 用户什么时候想接着练都行。四个复习模块的每日进度由复习会话单独管理。
      final sessions = await _sessionStore.getAll();
      if (!mounted) return;
      setState(() {
        _learningSessions = <LearningSessionType, LearningSession>{
          for (final session in sessions) session.type: session,
        };
      });
    } catch (error, stackTrace) {
      // 辅助能力异常只写调试日志，不能让首页进入整页错误状态。
      debugPrint('读取学习进度失败：$error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _learningSessions = const <LearningSessionType, LearningSession>{};
      });
    }
  }

  ///
  /// 按会话中的 id 顺序，从当前最新词库重新组装学习列表。
  List<Word> _wordsForSession(LearningSession session) {
    // 当前词库按主键建立索引，编辑后的拼写、释义和难度会自然使用最新值。
    final wordsById = <int, Word>{
      for (final word in _allWords)
        if (word.id != null) word.id!: word,
    };
    // 任一单词已不存在就不能完整恢复旧状态，返回空列表交给点击流程清理。
    if (session.wordIds.any((id) => !wordsById.containsKey(id))) {
      return const <Word>[];
    }
    // for 按持久化 id 数组原顺序取值，不受首页当前筛选和排序影响。
    return List<Word>.unmodifiable(session.wordIds.map((id) => wordsById[id]!));
  }

  ///
  /// 打开一轮随身听；[session] 非空时从历史状态继续，否则覆盖为新会话。
  Future<void> _openListening(
    List<Word> words, {
    LearningSession? session,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListeningPage(
          words: words,
          audioPlayer: _audioPlayer,
          accent: _settings.accent,
          definitionSeparator: _settings.definitionSeparator.symbol,
          initialSession: session,
          sessionStore: _sessionStore,
        ),
      ),
    );
    // 页面退出时会补写最终快照；返回后重新读取，让“继续”按钮立即反映结果。
    if (mounted) await _refreshReviewDashboard();
  }

  ///
  /// 打开一轮听音辨义，并保留原有的复习数据定向回刷逻辑。
  ///
  /// 两个入口共用这一个方法：
  /// - 词库底部的普通听音辨义：传 [session]，长期进度存在 learning_sessions；
  /// - 首页「听音辨义」复习模块：传 [reviewSession]，每日进度存在 review_sessions。
  Future<void> _openListeningMeaning(
    List<Word> words, {
    LearningSession? session,
    ReviewSession? reviewSession,
  }) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<dynamic>(
        builder: (_) => ListeningMeaningPage(
          words: words,
          audioPlayer: _audioPlayer,
          accent: _settings.accent,
          definitionSeparator: _settings.definitionSeparator.symbol,
          // 普通入口用长期会话，复习模块用当天的复习会话，二者互不影响。
          initialSession: session,
          sessionStore: _sessionStore,
          reviewSession: reviewSession,
          reviewSessionStore: _reviewSessionStore,
        ),
      ),
    );
    if (!mounted) return;
    if (result is List<int>) {
      // 正常返回（顶部箭头）：页面 pop 时带回 id 列表，只回刷这些单词即可。
      unawaited(_mergeReviewedWords(result));
    }
    // 无论顶部箭头还是手势返回，仪表盘上的进度都必须重算一次：
    // 头部「今日复习 X/目标」、四张模式卡的三态、趋势曲线与打卡日历。
    await _refreshReviewDashboard();
  }

  ///
  /// 打开首页四个复习模块。
  ///
  /// 「今天该进哪一局」全部由 [ReviewFlow] 判断，这里只负责按模块跳到对应页面。
  /// 玩法尚未开放的两个模块直接进占位页，不建词库也不开会话——避免它们的
  /// 「已完成」状态凭空出现在首页上。
  Future<void> _openReviewModule(ReviewModule module) async {
    // 未开放的玩法只展示占位页，不参与今天的词库与会话。
    if (!module.isAvailable) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReviewUnavailablePage(
            title: module.label,
            wordCount: _dailyWordSet?.wordCount ?? _settings.dailyGoal,
          ),
        ),
      );
      return;
    }

    // 备好今天的词库并拿到这一局：可能是续上的旧局、新的主线，也可能是巩固。
    final entry = await _openReviewSession(module);
    if (!mounted || entry == null) return;

    switch (module) {
      case ReviewModule.listeningMeaning:
        // 听音辨义复用成熟的答题页，只是进度改存到复习会话里。
        await _openListeningMeaning(entry.words, reviewSession: entry.session);
      case ReviewModule.meaningMatch:
        // 词义连连：传入本局会话（续玩）、会话 Store 与设置 Store（倒计时 +30 写全局）。
        final playAgain = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
           builder: (_) => MeaningMatchPage(
             words: entry.words,
             title: module.label,
             reviewSession: entry.session,
             reviewSessionStore: _reviewSessionStore,
             settings: _settings,
              audioPlayer: _audioPlayer,
              accent: _settings.accent,
           ),
          ),
        );
        if (!mounted) return;
        // 连完一局回来，三态、头部数字与曲线一起重算。
        await _refreshReviewDashboard();
        // 结算页点了「再挑战一次」：由 ReviewFlow 重新判断该开主线还是巩固，
        // 用户感受上还是点一下就重开，但规则只有一份。
        if (playAgain == true && mounted) {
          await _openReviewModule(module);
        }
      case ReviewModule.spellingReinforcement:
        // 拼写巩固：传入本局会话（续玩）、会话 Store、发音服务与当前口音。
        final playAgain = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => SpellingReinforcementPage(
              words: entry.words,
              title: module.label,
              reviewSession: entry.session,
              audioPlayer: _audioPlayer,
              accent: _settings.accent,
              reviewSessionStore: _reviewSessionStore,
            ),
          ),
        );
        if (!mounted) return;
        // 拼完一局回来，三态、头部数字与曲线一起重算。
        await _refreshReviewDashboard();
        // 结算页点了「再练一组」：由 ReviewFlow 重新判断该开主线还是巩固。
        if (playAgain == true && mounted) {
          await _openReviewModule(module);
        }
      case ReviewModule.meaningWordChoice:
        // 上面的 isAvailable 判断已经拦下这个，这里只是让 switch 覆盖完整。
        break;
    }
  }

  ///
  /// 点击“继续”后校验会话列表并进入对应页面；坏快照会被立即删除。
  Future<void> _continueLearning(LearningSessionType type) async {
    // 按按钮所属类型读取会话；异步回刷期间记录可能已经被完成流程删除。
    final session = _learningSessions[type];
    if (session == null) return;
    final words = _wordsForSession(session);
    if (words.isEmpty) {
      // 无法完整组装说明词库已经变化，保留按钮只会让用户反复进入失败。
      await _sessionStore.delete(type);
      if (!mounted) return;
      setState(() {
        final next = Map<LearningSessionType, LearningSession>.from(
          _learningSessions,
        );
        next.remove(type);
        _learningSessions = next;
      });
      Toast.show(context, '上次学习列表已失效，请重新开始');
      return;
    }
    // 类型决定目标页；传入 session 后页面会在首帧恢复自己的详细状态。
    if (type == LearningSessionType.listening) {
      await _openListening(words, session: session);
    } else {
      await _openListeningMeaning(words, session: session);
    }
  }

  ///
  /// 听音辨义返回后只回刷本次复习涉及的单词，避免重新加载整库。
  ///
  /// [ids] 是本次听音辨义完成过的单词主键集合；只向原生请求这些单词的最新数据
  /// （含更新后的 difficulty / reviewedAt），再用新对象原地替换 [_allWords] 中
  /// 同 id 的项，其余单词保持原位与顺序。原生或通道异常时静默忽略，界面不崩。
  Future<void> _mergeReviewedWords(List<int> ids) async {
    // 没有 id 时直接结束，界面保持不动。
    if (ids.isEmpty) return;
    try {
      // 只拉取相关单词，而非全部。
      final fresh = await _store.getByIds(ids);
      // 页面可能已销毁。
      if (!mounted) return;
      // 用新数据原地替换，不重建整个列表。
      setState(() {
        final byId = <int, Word>{for (final word in fresh) word.id!: word};
        _allWords = _allWords.map((word) {
          final id = word.id;
          if (id != null && byId.containsKey(id)) return byId[id]!;
          return word;
        }).toList();
      });
    } catch (error, stackTrace) {
      // 调试输出保留完整错误，方便真机日志定位；回刷失败不影响已完成的复习记录。
      debugPrint('回刷复习单词失败：$error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  ///
  /// App 生命周期变化：从后台恢复或进入后台时分别处理。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed 表示 App 回到前台。
    if (state == AppLifecycleState.resumed) {
      // 获取恢复时真实时间。
      final resumedAt = DateTime.now();
      // 跨年后重新构建静态列表日期；问候语也顺带刷新。
      setState(() {
        _dateReference = resumedAt;
        // 日期已经变化时先同步清空旧词库，避免原生异步读取完成前误用昨天那批词。
        if (_dailyWordSet?.setDate != _localDateKey(resumedAt)) {
          _dailyWordSet = null;
        }
      });
      // 后台待了一夜再回来，昨天没打完的局要先收成「中断」，
      // 否则今天点开模块会续上昨天那一局。
      unawaited(_abortStaleReviewSessions());
      // 回到前台时把仪表盘的进度整体重算：今日复习数、每日词库、未完成会话，
      // 以及趋势曲线与打卡日历（跨天或后台产生过记录时保持准确）。
      unawaited(_refreshReviewDashboard());
      // 防止继续执行下面停止逻辑。
      return;
    }
    // 离开前台后，下次播放要重新提示一次 TTS 兜底来源。
    _hasShownTtsNotice = false;
    // 离开前台时停止发音，避免 App 隐藏后继续播。
    unawaited(_stopAudio());
  }

  ///
  /// 把本地时间转换成每日词库使用的 yyyy-MM-dd 键。
  String _localDateKey(DateTime dateTime) {
    // 补齐月份和日期为两位数字。
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day';
  }

  ///
  /// 搜索框输入回调，使用 120ms 防抖保护上万条内存过滤。
  void _handleSearchChanged(String value) {
    // 标准化大小写和首尾空格。
    final normalizedQuery = value.trim().toLowerCase();
    // 每次输入先取消上一个尚未执行的过滤任务。
    _searchDebounce?.cancel();
    // 120ms 内没有新输入才真正更新 query。
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      // 页面卸载或值未变化时不刷新。
      if (!mounted || _query == normalizedQuery) return;
      // 更新查询关键字并触发过滤后的列表重建。
      setState(() => _query = normalizedQuery);
    });
  }

  ///
  /// 点击单词行：滑动打开时先收起；选择模式切换勾选；否则播放并展开。
  void _handleRowTap(Word word) {
    // 有行处于滑动打开状态时，本次点击只负责收起。
    if (_swipedWord != null) {
      setState(() => _swipedWord = null);
      return;
    }
    // 选择模式下点击整行等于切换勾选。
    if (_selectMode) {
      _toggleSelected(word);
      return;
    }
    // 设计稿行为：点击同时播放发音并切换释义展开。
    setState(() {
      // 有释义才有展开状态可切换。
      if (word.meanings.isNotEmpty) {
        final wasExpanded = _expandedWords.remove(word);
        if (!wasExpanded) _expandedWords.add(word);
      }
    });
    // 播放当前口音发音。
    unawaited(_playWord(word));
  }

  ///
  /// 切换某行的选中状态。
  void _toggleSelected(Word word) {
    // setState 同步刷新勾选框与计数。
    setState(() {
      final wasSelected = _selectedWords.remove(word);
      if (!wasSelected) _selectedWords.add(word);
    });
  }

  ///
  /// 行左滑打开或关闭操作区。
  void _handleSwipeChanged(Word word, bool open) {
    // 选择模式下禁止滑出操作区，与设计稿一致。
    if (open && _selectMode) return;
    // 更新当前滑动行。
    setState(() => _swipedWord = open ? word : null);
  }

  ///
  /// 点击单词文字后按当前口音播放；同一行播放中重复点击直接忽略。
  Future<void> _playWord(Word word) async {
    // 下载中和播放中都属于 active，同一个 Word 不重新开始。
    if (identical(_playingWord, word)) return;
    // 记录当前行，喇叭动画立即出现，不等待网络请求完成。
    setState(() => _playingWord = word);
    try {
      // 读取点击时的口音快照；设置变化只影响下一次播放。
      final accent = _settings.accent;
      // 原生先查口音缓存，再按不背单词、有道顺序下载并播放。
      await _audioPlayer.play(word.spelling, accent);
      // 只有真正使用本地 TTS 并成功朗读后，才在本次前台会话第一次提示。
      if (!_hasShownTtsNotice &&
          await _audioPlayer.consumeLastPlaybackUsedTts()) {
        _hasShownTtsNotice = true;
        if (mounted) {
          Toast.show(context, '当前网络音频不可用，正在使用系统 TTS 朗读');
        }
      }
    } on WordAudioInterruptedException {
      // 点击其他单词或页面进入后台属于正常中断，不显示错误。
    } catch (error, stackTrace) {
      // 控制台保留完整错误便于真机排查音源、网络或解码问题。
      debugPrint('单词发音失败（${word.spelling}）：$error');
      // 同时记录 Dart 调用堆栈。
      debugPrintStack(stackTrace: stackTrace);
      // 只有当前请求仍对应这行时才提示；旧请求失败不能干扰新播放。
      if (mounted && identical(_playingWord, word)) {
        // Toast 基于根 Overlay，层级高于 Drawer/BottomSheet。
        Toast.show(context, '无法播放"${word.spelling}"：$error');
      }
    } finally {
      // 只有当前行仍是这次请求时才隐藏喇叭；旧 Future 不能清掉新行状态。
      if (mounted && identical(_playingWord, word)) {
        setState(() => _playingWord = null);
      }
    }
  }

  ///
  /// 主动停止音频并立即移除播放动画。
  Future<void> _stopAudio() async {
    // 没有下载或播放时不调用原生通道。
    if (_playingWord == null) return;
    // mounted 时立即清除动画状态。
    if (mounted) setState(() => _playingWord = null);
    try {
      // 原生会让旧 play Future 以可忽略的中断结束。
      await _audioPlayer.stop();
    } catch (error, stackTrace) {
      // 停止失败不阻断生命周期，只保留调试信息。
      debugPrint('停止单词发音失败：$error');
      // 输出调用堆栈。
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  ///
  /// 打开添加/修改单词表单；editing 为 null 表示新增。
  void _openWordForm({Word? editing}) {
    // 表单提交由首页执行 Store 操作。
    unawaited(
      showWordFormSheet(
        context,
        groups: _groups,
        editing: editing,
        onSubmit: (result) => _submitWordForm(result, editing: editing),
      ),
    );
  }

  ///
  /// 执行表单提交：新增走 create，编辑走 update。
  Future<void> _submitWordForm(WordFormResult result, {Word? editing}) async {
    try {
      // 表单每次只选一个分组，这里把单值转成单元素列表（null 表示未分组）。
      // 方案 A 的 groupMember 多对多允许跨组，但表单提交语义是"整体归属到某一组"。
      final groupIds = result.groupId == null
          ? const <int>[]
          : <int>[result.groupId!];
      // 编辑模式：在原对象基础上替换拼写、释义与分组。
      if (editing != null) {
        await _store.update(
          editing.edited(
            spelling: result.spelling,
            meanings: result.meanings,
            groupId: result.groupId,
          ),
        );
      } else {
        // 新增模式：交给 Store 生成主键与时间。
        await _store.create(
          Word(
            spelling: result.spelling,
            meanings: result.meanings,
            // 直接把单分组写进 groupIds，原生建完单词后逐条补 groupMember。
            groupIds: groupIds,
          ),
        );
      }
      // 无论新增或编辑都刷新列表。
      await _refreshWords();
    } catch (error) {
      // 失败时保留面板并提示原因。
      if (!mounted) return;
      Toast.show(context, '保存单词失败：$error');
    }
  }

  ///
  /// 弹出删除确认对话框。
  void _confirmDelete(Word word) {
    // 先收起滑动操作区。
    setState(() => _swipedWord = null);
    // showDialog 展示设计稿风格的居中确认卡。
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          // 读取当前明暗对应的设计令牌。
          final tokens = AppTokens.of(dialogContext);
          // Dialog 自绘圆角卡片。
          return Dialog(
            backgroundColor: tokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                // 高度只包住内容。
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 对话框标题。
                  Text(
                    '删除单词',
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 标题与正文间距。
                  const SizedBox(height: 8),
                  // 确认文案带上单词拼写。
                  Text(
                    '确定要删除「${word.spelling}」吗？此操作无法撤销。',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  // 正文与按钮间距。
                  const SizedBox(height: 18),
                  // 取消与删除按钮。
                  Row(
                    children: [
                      // 取消按钮：描边样式。
                      Expanded(
                        child: InkWell(
                          key: const Key('delete-cancel'),
                          onTap: () => Navigator.of(dialogContext).pop(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: tokens.inputBorder),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                color: tokens.textMedium,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 删除按钮：危险色实底。
                      Expanded(
                        child: InkWell(
                          key: const Key('delete-confirm'),
                          onTap: () {
                            // 先关闭对话框再执行删除。
                            Navigator.of(dialogContext).pop();
                            unawaited(_deleteWord(word));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTokens.danger,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '删除',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  ///
  /// 真正执行删除并刷新列表。
  Future<void> _deleteWord(Word word) async {
    try {
      // 没有主键的数据无法定位，直接提示。
      final id = word.id;
      if (id == null) throw StateError('该单词缺少 id，无法删除');
      // 交给 SQLite Store 软删除；测试注入的 Store 遵守同一接口约定。
      await _store.delete(id);
      // 刷新列表。
      await _refreshWords();
    } catch (error) {
      // 删除失败提示原因。
      if (!mounted) return;
      Toast.show(context, '删除失败：$error');
    }
  }

  ///
  /// 打开移动/复制目标分组选择面板。
  Future<void> _pickGroupAndApply({required bool isCopy}) async {
    // 没有选中任何单词时忽略（按钮颜色已提示不可用）。
    if (_selectedWords.isEmpty) return;
    // 组装目标列表：全部自定义分组（复制模式下不含「未分组」）。
    final targets = <GroupPickerTarget>[
      for (final group in _groups.groups)
        GroupPickerTarget(
          groupId: group.id,
          name: group.name,
          wordCount: _allWords
              .where((word) => word.groupIds.contains(group.id))
              .length,
        ),
    ];
    // 移动模式额外允许「未分组」（把单词移出所有分组）；
    // 复制是加入目标组，目标不能是「未分组」，因此排除。
    if (!isCopy) {
      targets.add(
        GroupPickerTarget(
          groupId: null,
          name: GroupStore.ungroupedName,
          wordCount: _allWords.where((word) => word.groupIds.isEmpty).length,
        ),
      );
    }
    // 弹出选择面板等待用户挑选。
    final picked = await showGroupPickerSheet(
      context,
      title: '${isCopy ? '复制' : '移动'} ${_selectedWords.length} 个单词到',
      targets: targets,
    );
    // 用户直接关闭面板时不执行任何操作。
    if (picked == null || !mounted) return;
    // record 第一个位置就是目标分组 id。
    final targetGroupId = picked.$1;
    try {
      if (isCopy) {
        // 复制：保留原组并加入目标分组（同一单词可存在于多个分组）。
        // 复制模式 targets 不含「未分组」，targetGroupId 必为非空。
        for (final word in _selectedWords) {
          await _store.update(word.withAddedGroup(targetGroupId!));
        }
      } else {
        // 移动：把所属分组整体替换为目标（空列表即移回未分组）。
        for (final word in _selectedWords) {
          await _store.update(word.withGroup(targetGroupId));
        }
      }
    } catch (error) {
      // 批量操作中途失败：仅把错误原因提示给用户，
      // 收尾（清选择+刷新）交给下方 finally 统一执行。
      if (!mounted) return;
      Toast.show(context, '操作失败：$error');
    } finally {
      // 抽成独立 async 函数，避免 finally 里用 return 提前退出引发 lint；
      // 同时集中处理「组件已卸载」的情况，让 finally 只做纯粹的收尾。
      await _finishGroupApply();
    }
  }

  ///
  /// 移动/复制收尾：清空选择并刷新界面。
  ///
  /// 无论操作成功还是中途异常都调用，避免「原生已部分落库但 UI 仍是旧状态」
  /// 的不一致窗口。组件卸载后不再触碰状态。
  Future<void> _finishGroupApply() async {
    // 组件已销毁则不操作，避免触发已卸载的 setState。
    if (!mounted) return;
    // 清空勾选，退出选择模式。
    _selectedWords.clear();
    // 从原生重新聚合最新分组关系并重建列表。
    await _refreshWords();
  }

  ///
  /// 尚未实现具体页面的菜单项使用统一提示。
  void _showComingSoon(String feature) {
    Toast.show(context, '「$feature」功能正在整理中');
  }

  ///
  /// 统一的轻提示，全系统使用同一 Toast 接口，层级高于 Drawer/BottomSheet。
  void _showSnackBar(String message) {
    // 系统文件选择器或数据库操作返回时页面可能已销毁，此时不再访问 Overlay。
    if (!mounted) return;
    // Toast 基于根 Overlay，不被任何 modal route 遮挡。
    Toast.show(context, message);
  }

  ///
  /// 数据导入：打开系统文件选择器读取 JSON，解析后整库替换写入本地。
  Future<void> _importData() async {
    // 先关闭抽屉，避免遮挡系统选择器。
    Navigator.of(context).pop();
    try {
      // 打开系统文件选择器，只列出 JSON；用户取消时返回 null，不做任何改动。
      final jsonText = await _fileIo.pickJsonText();
      // 取消选择或读到空文本都直接返回。
      if (jsonText == null || jsonText.isEmpty) return;
      // 先整体解析一次，原始数组与包含 words 的对象最终都交给 SQLite 动态导入。
      final decoded = jsonDecode(jsonText);
      final Map<String, Object?> payload;
      if (decoded is List) {
        // 旧 words.json 是顶层数组，只包装 words，不制造额外版本信息。
        payload = <String, Object?>{'words': decoded};
      } else if (decoded is Map && decoded['words'] is List) {
        // 完整导出对象保留 groups/members；只接收字符串键。
        payload = <String, Object?>{
          for (final entry in decoded.entries)
            if (entry.key is String) entry.key! as String: entry.value,
        };
      } else {
        throw const FormatException('导入文件必须是单词数组或包含 words 数组的对象');
      }
      final words = payload['words']! as List;
      if (words.isEmpty) {
        _showSnackBar('文件中没有可导入的单词');
        return;
      }
      // 原生层查询 PRAGMA 表结构，存在的字段按类型写入，未知字段自动忽略。
      await _store.importData(payload);
      final importedCount = words.length;
      // 文件携带 groups 才会替换分组，此时同步刷新内存列表。
      if (payload['groups'] is List) await _groups.load();
      // 文件操作期间首页可能已退出，后续不能再更新页面状态或发起页面刷新。
      if (!mounted) return;
      // 原生整库导入会同步清除学习会话，首页立即移除两个“继续”按钮。
      if (mounted) {
        setState(() {
          _learningSessions = const <LearningSessionType, LearningSession>{};
          // 整库导入会清空原生的每日词库、会话与复习记录，内存同步失效。
          _dailyWordSet = null;
          _reviewModuleStates = const <ReviewModule, ReviewModuleState>{};
          _reviewCount = 0;
        });
      }
      // 重新加载首页列表，让新数据立即显示。
      unawaited(_loadWords());
      // 提示成功导入的数量。
      _showSnackBar('已导入 $importedCount 个单词');
    } on FormatException catch (error) {
      // JSON 结构或字段错误，显示具体原因便于修正文件。
      _showSnackBar('导入失败：${error.message}');
    } catch (error) {
      // 文件读取或原生写入异常，显示可读详情。
      _showSnackBar('导入失败：${_describeLoadError(error)}');
    }
  }

  ///
  /// 数据导出：把本地全部单词、分组与成员关系聚合为 JSON，通过系统保存框写出。
  ///
  /// 导出结构在 words.json 基础上新增 groups 与 members 两段，原生 importData
  /// 导入时连同分组与多对多关系整库还原，避免备份丢失归类信息。
  Future<void> _exportData() async {
    // 先关闭抽屉，避免遮挡系统保存框。
    Navigator.of(context).pop();
    try {
      // 原生层直接读取 words/meanings/groups/group_members 真实字段。
      final payload = await _store.exportData();
      // 缩进格式，便于人读与二次编辑。
      final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
      // 文件名：App 名 + 当前日期，例如 MyEnglish-2026-07-28.json。
      final fileName =
          'MyEnglish-${DateTime.now().toIso8601String().substring(0, 10)}.json';
      // 通过系统保存框写出；由原生 SAF 把文本落盘到用户选择的位置。
      final savedUri = await _fileIo.writeExportJson(
        fileName: fileName,
        jsonText: jsonText,
      );
      // 用户取消保存不提示。
      if (savedUri == null) return;
      // 系统保存框返回时首页可能已经销毁。
      if (!mounted) return;
      // 提示导出数量（系统已落盘到用户指定的位置）。
      final exportedWords = payload['words'] as List? ?? const <Object?>[];
      _showSnackBar('已导出 ${exportedWords.length} 个单词');
    } catch (error) {
      // 读取或保存异常，显示可读详情。
      _showSnackBar('导出失败：${_describeLoadError(error)}');
    }
  }

  ///
  /// 清空数据：二次确认后清空单词、释义与全部设置。
  Future<void> _clearData() async {
    // 先关闭抽屉，避免遮挡确认弹窗。
    Navigator.of(context).pop();
    // 危险操作必须二次确认，避免误触。
    final confirmed = await _showClearConfirmDialog();
    // 用户取消则什么都不做。
    if (!confirmed || !mounted) return;
    try {
      // 清空 SQLite 全部业务数据，包含单词、释义、分组、记录、候选缓存和学习会话。
      await _store.clearAll();
      // 清空设置（原生 SharedPreferences 清空 + 内存重置为默认值）。
      await _settings.clearAll();
      // 一并清空离线语音缓存文件（word_audio 目录下全部 mp3），并重置进度。
      await WordAudioCache.instance.clearCacheFiles();
      // 多项原生清理完成前用户可能已经离开首页。
      if (!mounted) return;
      // 清空内存分组；原生 group 表已由 WordStore.clearAll 在 SQLite 侧一并清空。
      _groups.clear();
      // 与原生删除保持同步，让继续入口无需等待下一次读取就立即消失。
      setState(() {
        _learningSessions = const <LearningSessionType, LearningSession>{};
        // 原生已清空每日词库与全部复习数据，避免卡片继续显示旧状态。
        _dailyWordSet = null;
        _reviewModuleStates = const <ReviewModule, ReviewModuleState>{};
        _reviewCount = 0;
      });
      // 重新加载空列表。
      unawaited(_loadWords());
      // 提示已清空。
      _showSnackBar('已清空全部本地数据');
    } catch (error) {
      // 清空异常，显示可读详情。
      _showSnackBar('清空失败：${_describeLoadError(error)}');
    }
  }

  ///
  /// 清空数据的二次确认弹窗，返回 true 表示用户确认清空。
  Future<bool> _showClearConfirmDialog() async {
    // showDialog 返回 bool?，确认按钮 pop(true)。
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        // 读取当前明暗对应的设计令牌。
        final tokens = AppTokens.of(dialogContext);
        // Dialog 自绘圆角卡片。
        return Dialog(
          backgroundColor: tokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              // 高度只包住内容。
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 对话框标题。
                Text(
                  '清空数据',
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // 标题与正文间距。
                const SizedBox(height: 8),
                // 明确告知后果，不可恢复。
                Text(
                  '将删除全部单词（含释义）、所有设置与已下载的离线语音音频，此操作不可恢复。',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                // 正文与按钮间距。
                const SizedBox(height: 18),
                // 取消与确认按钮。
                Row(
                  children: [
                    // 取消按钮：描边样式。
                    Expanded(
                      child: InkWell(
                        key: const Key('clear-cancel'),
                        onTap: () => Navigator.of(dialogContext).pop(false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: tokens.inputBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '取消',
                            style: TextStyle(color: tokens.text, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    // 按钮之间留白。
                    const SizedBox(width: 12),
                    // 确认清空按钮：主色填充。
                    Expanded(
                      child: InkWell(
                        key: const Key('clear-confirm'),
                        onTap: () => Navigator.of(dialogContext).pop(true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTokens.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '确认清空',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    // null（点遮罩关闭）视为取消。
    return result == true;
  }

  ///
  /// 将任意异常转换成用户可见的详情，不再只显示笼统失败文案。
  String _describeLoadError(Object error) {
    // toString 会保留 PlatformException code、JSON offset 和 StateError 信息。
    final details = error.toString();
    // 极少数自定义异常可能返回空文本，此时至少显示运行时类型。
    return details.trim().isEmpty ? error.runtimeType.toString() : details;
  }

  ///
  /// 页面卸载时释放 Observer、Timer 和监听器。
  @override
  void dispose() {
    // 移除 App 生命周期监听。
    WidgetsBinding.instance.removeObserver(this);
    // 取消尚未执行的搜索防抖。
    _searchDebounce?.cancel();
    // 页面关闭后不再需要加载超时提醒，主动取消可避免测试或真实页面残留计时任务。
    _loadTimeout?.cancel();
    // 移除设置与分组监听。
    _settings.removeListener(_handleExternalChange);
    _groups.removeListener(_handleGroupsChanged);
    // 释放内存分组 Store。
    _groups.dispose();
    // 只有确实正在播放时才调用 stop，避免独立 Widget 测试访问不存在的原生插件。
    if (_playingWord != null) {
      // dispose 中不能 await；服务自身会正确释放原生资源。
      unawaited(
        _audioPlayer.stop().catchError((Object error) {
          // 页面已销毁，只把停止失败写入调试控制台。
          debugPrint('首页销毁时停止发音失败：$error');
        }),
      );
    }
    // 释放可拖动滚动条和列表共用的控制器。
    _scrollController.dispose();
    // 仅释放首页自行创建的测试内存设置；MainApp 注入的全局 Store 继续存在。
    if (_ownsSettings) _settings.dispose();
    // 最后执行父类清理。
    super.dispose();
  }

  ///
  /// 根据加载状态选择进度、错误、空状态或高性能列表。
  Widget _buildListContent(
    List<_WordSection> shownSections,
    bool hasVisibleRows,
  ) {
    // 数据源尚未返回时显示居中进度圈。
    if (_isLoading) {
      // SizedBox 限定小型进度圈尺寸。
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          // CircularProgressIndicator 显示加载中的旋转指示圈。
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // Store 抛错时同时显示可恢复操作与实际异常详情。
    if (_loadError != null) {
      // SingleChildScrollView 防止较长错误在小屏幕发生纵向溢出。
      return Center(
        child: SingleChildScrollView(
          // 错误区与屏幕边缘保持足够距离。
          padding: const EdgeInsets.all(24),
          child: Column(
            // mainAxisSize.min 让内容不强制撑满整个滚动区域。
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用户首先看到简短结论。
              const Text(
                '单词数据加载失败',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              // 标题与详情之间留白。
              const SizedBox(height: 8),
              // SelectableText 允许长按选择并复制真机上的具体错误。
              SelectableText(
                // key 让测试能确认具体错误确实已经输出到页面。
                key: const Key('word-load-error-details'),
                // 输出原始 FormatException 或 PlatformException 内容。
                _describeLoadError(_loadError!),
                // 错误详情居中阅读。
                textAlign: TextAlign.center,
                // 使用次要颜色与较小字号，不抢过错误标题。
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              // 详情与按钮间距。
              const SizedBox(height: 8),
              // TextButton 承载点击重试的操作。
              TextButton(
                // 点击后重新执行 Store 查询。
                onPressed: _loadWords,
                // 按钮文字。
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    // 搜索无匹配或完全没有数据时显示空状态。
    if (!hasVisibleRows && shownSections.isEmpty) {
      // 空状态占据列表剩余区域中心。
      return Center(
        child: Text(
          // 有搜索词时按设计稿提示"未找到相关单词"。
          _query.isEmpty ? '暂无单词' : '未找到相关单词',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }

    // Scrollbar 提供始终可见且可直接拖动到任意位置的滑块。
    return Scrollbar(
      // 与 CustomScrollView 共用控制器，否则拖动滑块无法控制列表。
      controller: _scrollController,
      // 真机上无需先滚动一次就能看到滑块。
      thumbVisibility: true,
      // interactive=true 允许手指或鼠标按住滑块快速拖到底部。
      interactive: true,
      // CustomScrollView 允许分组头使用原生 Sliver 吸顶，同时仍然惰性创建单词行。
      child: CustomScrollView(
        // key 供测试准确识别首页真正的纵向业务列表。
        key: const Key('word-list-scroll-view'),
        // 使用同一个 ScrollController。
        controller: _scrollController,
        // 默认只预构建视口外 250 逻辑像素的行；快速滑动到底部时，
        // 行还没建好就滚到了，会出现“空白后补建”的顿挫。这里把预构建范围
        // 放大到 1000 像素（约多缓存 25 行），让手指快速甩动时提前建好，滑动更跟手。
        // 注：新版 scrollCacheExtent 所需的 ScrollCacheExtent 类型当前 SDK 未对外导出，
        // 暂时保留 cacheExtent（仅 info 级弃用提示，不影响运行）。
        // ignore: deprecated_member_use
        cacheExtent: 1000,
        // slivers 按顺序拼接多个“吸顶标题 + 长列表”区块。
        slivers: [
          // 每个分组都由一个固定高度吸顶头和一个惰性单词列表组成。
          for (final section in shownSections)
            // SliverMainAxisGroup 把标题和本组单词限制在同一滚动区段；
            // 当前组结束时，下一组标题会把旧标题顶走，而不是让多个标题叠在顶部。
            SliverMainAxisGroup(
              slivers: [
                // pinned=true 让当前分组行停在列表顶部，直到下一分组将它顶走。
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    // 头部内容仍复用原来的折叠、整组选中交互。
                    child: _buildSectionHeader(section),
                  ),
                ),
                // 分组折叠后只保留吸顶标题，不再生成其中的单词行。
                if (!_collapsedKeys.contains(section.key))
                  SliverList(
                    // SliverChildBuilderDelegate 只创建屏幕附近的行，适合上万单词。
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildWordRow(section.words[index]),
                      childCount: section.words.length,
                      // 默认即为 true：被滚出屏幕的行保留 Element，滚回时无需重建，
                      // 直接复用已缓存的 Widget 树，滚动更顺滑。
                      addAutomaticKeepAlives: true,
                      // 默认即为 true：每行独立一层，行内文字/图标变化不触发整列重绘。
                      addRepaintBoundaries: true,
                    ),
                  ),
              ],
            ),
          // 操作栏已经位于列表外部，列表末尾只保留正常呼吸空间即可。
          const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
        ],
      ),
    );
  }

  ///
  /// 构造一个分组头；独立成方法后，普通位置与 Sliver 吸顶位置使用完全相同的交互。
  Widget _buildSectionHeader(_WordSection section) {
    // 当前分组是否已经全部选中。
    final isAllSelected =
        section.words.isNotEmpty &&
        section.words.every(_selectedWords.contains);
    // 返回原有的分组头组件，视觉尺寸与样式不变。
    return _SectionHeader(
      section: section,
      isCollapsed: _collapsedKeys.contains(section.key),
      selectMode: _selectMode,
      isAllSelected: isAllSelected,
      onTap: () => setState(() {
        // 点击分组头切换折叠状态。
        if (!_collapsedKeys.remove(section.key)) {
          _collapsedKeys.add(section.key);
        }
      }),
      onToggleSelect: () => setState(() {
        // 已经全选时整组取消，否则把该组全部加入选择集合。
        if (isAllSelected) {
          _selectedWords.removeAll(section.words);
        } else {
          _selectedWords.addAll(section.words);
        }
      }),
    );
  }

  ///
  /// 构造单个单词行；由每个分组自己的 SliverList 按需调用。
  Widget _buildWordRow(Word word) {
    // 返回原有单词行组件，播放、展开、选择和左滑逻辑全部保持不变。
    return WordListTile(
      // ObjectKey 使用对象身份，同 spelling 的多条数据不会冲突。
      key: ObjectKey(word),
      // 传入一次性加载的数据项。
      item: word,
      // 传入静态年份参考。
      dateReference: _dateReference,
      // 按当前分组模式计算列表行应显示的日期（复习/更新/加入时间其一）。
      displayDate: _listDateOf(word),
      // 根据页面 Set 判断当前行是否展开。
      isExpanded: _expandedWords.contains(word),
      // 全部中文释义统一使用首页设置中选择的全角分隔符。
      definitionSeparator: _settings.definitionSeparator.symbol,
      // 只有当前具体对象显示播放动画。
      isPlaying: identical(_playingWord, word),
      // 选择模式与勾选状态。
      selectMode: _selectMode,
      isSelected: _selectedWords.contains(word),
      // 当前行是否滑开操作区。
      isSwipedOpen: identical(_swipedWord, word),
      // 点击整行：播放并展开 / 勾选 / 收起滑动。
      onTap: () => _handleRowTap(word),
      // 勾选框独立切换选中。
      onToggleSelect: () => _toggleSelected(word),
      // 滑动打开或关闭操作区。
      onSwipeChanged: (open) => _handleSwipeChanged(word, open),
      // 左滑操作：修改与删除。
      onEdit: () {
        // 先收起操作区再打开表单。
        setState(() => _swipedWord = null);
        _openWordForm(editing: word);
      },
      onDelete: () => _confirmDelete(word),
    );
  }

  ///
  /// 打开 GitHub 仓库：用系统默认浏览器跳转到项目主页。
  Future<void> _openGithub() async {
    // 先把抽屉收起，避免浏览器唤起后抽屉仍残留在界面上。
    _scaffoldKey.currentState?.closeEndDrawer();
    // 拼接完整 https 地址，确保默认浏览器能正确处理。
    final uri = Uri.parse('https://github.com/iguoji/MyEnglish');
    // canLaunchUrl 先确认本机存在可处理该链接的浏览器，避免直接 launch 抛异常。
    if (await canLaunchUrl(uri)) {
      // externalApplication 表示跳出本 App，交给系统默认浏览器打开。
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // 极端情况（无浏览器）静默失败，不打断用户。
      debugPrint('无法打开浏览器：$uri');
    }
  }

  ///
  /// 复制作者邮箱到系统剪贴板，并用 SnackBar 提示。
  Future<void> _copyEmail() async {
    // 作者邮箱地址（与抽屉页脚展示保持一致）。
    const email = 'asgeg@qq.com';
    // Clipboard 属于系统服务，复制后其他 App 可粘贴。
    await Clipboard.setData(const ClipboardData(text: email));
    // 组件可能已被销毁（如快速返回），先确认仍挂载再弹提示。
    if (!mounted) return;
    // 收起抽屉，让底部 Toast 完整可见。
    _scaffoldKey.currentState?.closeEndDrawer();
    // Toast 基于根 Overlay，层级高于 Drawer。
    Toast.show(context, '已复制作者邮箱：$email');
  }

  ///
  /// 把当前 State 转成界面树。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 组织全部分组区块。
    final sections = _buildSections();
    // 当前筛选 key 失效（分组被删除等）时回退到"全部"。
    final activeFilter = sections.any((section) => section.key == _filterKey)
        ? _filterKey
        : null;
    // 应用筛选后的区块。
    var shownSections = activeFilter == null
        ? sections
        : sections.where((section) => section.key == activeFilter).toList();
    // 搜索时隐藏没有匹配的分组。
    if (_query.isNotEmpty) {
      shownSections = shownSections
          .where((section) => section.words.isNotEmpty)
          .toList();
    }
    // 当前可见（参与全选与随身听/听音辨义目标）的全部单词。
    final visibleWords = <Word>[
      for (final section in shownSections) ...section.words,
    ];
    // 把首页当前顺序冻结成只读快照，页面跳转后不受后续重建中的临时列表影响。
    final visibleWordSnapshot = List<Word>.unmodifiable(visibleWords);
    // 筛选 chips 使用未过滤的区块名（含"全部"）。
    final chips = <GroupFilterChip>[
      GroupFilterChip(
        sectionKey: null,
        name: '全部',
        isActive: activeFilter == null,
      ),
      for (final section in sections)
        GroupFilterChip(
          sectionKey: section.key,
          name: section.name,
          isActive: activeFilter == section.key,
        ),
    ];
    // 随身听/听音辨义的目标数量：有勾选用勾选数，否则用全部可见数。
    final selectedVisible = visibleWords.where(_selectedWords.contains).length;
    final targetCount = selectedVisible > 0
        ? selectedVisible
        : visibleWords.length;
    // 真正传给学习页面的数据必须保持当前列表顺序；有选择时仅保留勾选项。
    final learningWords = List<Word>.unmodifiable(
      selectedVisible > 0
          ? visibleWordSnapshot.where(_selectedWords.contains)
          : visibleWordSnapshot,
    );
    // 只有本地确实存在未完成记录时才让对应“继续”按钮参与布局与动画。
    final hasListeningSession = _learningSessions.containsKey(
      LearningSessionType.listening,
    );
    final hasListeningMeaningSession = _learningSessions.containsKey(
      LearningSessionType.listeningMeaning,
    );
    // 复习模块的实际题量以今天已建好的词库为准；词库还没建时先用设置值预告。
    // 词库总量不足目标时（比如只录了 30 个词、目标却是 50），这里显示的是真实的 30。
    final reviewModeDailyGoal = _dailyWordSet?.wordCount ?? _settings.dailyGoal;
    // 全部可见分组是否都已折叠，决定按钮文案。
    final allCollapsed =
        shownSections.isNotEmpty &&
        shownSections.every((section) => _collapsedKeys.contains(section.key));

    // Scaffold 是页面根骨架；endDrawer 提供右侧抽屉。
    return Scaffold(
      key: _scaffoldKey,
      // 右侧抽屉菜单。
      endDrawer: HomeDrawer(
        // 添加单词：先关抽屉再开表单。
        onAddWord: () {
          Navigator.of(context).pop();
          _openWordForm();
        },
        // 全局设置 Store：设置项已内嵌到抽屉中，点击即生效，无需再开独立窗口。
        settings: _settings,
        // 离线语音缓存服务：抽屉"离线语音"入口读取百分比并驱动后台预缓存。
        cache: WordAudioCache.instance,
        // 数据导入：方法内部会先关抽屉再弹出系统文件选择器。
        onImport: () => unawaited(_importData()),
        // 数据导出：方法内部会先关抽屉再弹出系统保存框。
        onExport: () => unawaited(_exportData()),
        // 清空数据：方法内部会先关抽屉再弹二次确认。
        onClearData: () => unawaited(_clearData()),
        // 仓库地址：用系统默认浏览器打开 GitHub（externalApplication 即跳出本 App）。
        onOpenGithub: () => unawaited(_openGithub()),
        // 作者邮箱：复制到剪贴板并提示。
        onCopyEmail: () => unawaited(_copyEmail()),
      ),
      // SafeArea 避开状态栏、刘海和底部手势区。
      body: PopScope<void>(
        // 词库展开时，系统返回手势先执行“收起词库”；收起后才允许离开首页。
        canPop: !_wordLibraryExpanded,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !_wordLibraryExpanded) return;
          setState(() => _wordLibraryExpanded = false);
        },
        child: SafeArea(
          // Listener 包住整棵页面内容，只旁听已经命中的原始触摸事件，不会像
          // Stack 顶层透明组件那样挡住下面的菜单按钮、卡片和滚动区域。
          child: Listener(
            key: const Key('home-global-swipe-listener'),
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              // 新触摸开始时清空上一次累计距离与触发标记。
              _globalVerticalDrag = 0;
              _globalSwipeHandled = false;
            },
            onPointerMove: (event) {
              // 累加每一小段纵向位移，向上移动会得到负数。
              _globalVerticalDrag += event.delta.dy;
              // 一次手势累计上滑达到 180 像素才展开；普通滚动首页通常不会
              // 在单次触摸中越过这个距离，因此可以先查看下方复习卡片。
              if (!_globalSwipeHandled &&
                  _globalVerticalDrag <= -_wordLibrarySwipeDistance) {
                _globalSwipeHandled = true;
                // 词库已经展开时无需重复重建；收起状态才更新页面。
                if (!_wordLibraryExpanded) {
                  setState(() => _wordLibraryExpanded = true);
                }
              }
            },
            onPointerUp: (_) {
              // 手指离开后结束本次识别，下一次触摸会重新累计。
              _globalVerticalDrag = 0;
              _globalSwipeHandled = false;
            },
            onPointerCancel: (_) {
              // 系统取消手势时同样清理临时数据。
              _globalVerticalDrag = 0;
              _globalSwipeHandled = false;
            },
            // Stack 让底部抽屉悬浮在仪表盘之上。
            child: Stack(
              children: [
                // 上层：仪表盘（问候 + 趋势 + 打卡 + 复习模式入口）。
                HomeDashboard(
                  now: DateTime.now(),
                  wordCount: _allWords.length,
                  dailyGoal: _settings.dailyGoal,
                  reviewModeDailyGoal: reviewModeDailyGoal,
                  reviewCount: _reviewCount,
                  // 四张卡片的三态进度：待完成 / 进行中 / 已完成。
                  reviewModuleStates: _reviewModuleStates,
                  // 回刷序号：数字一变，趋势曲线与打卡日历就重查数据库。
                  refreshToken: _dashboardRefreshToken,
                  onMenuPressed: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                  // 四个入口共用同一个方法，具体开哪一局由 ReviewFlow 判断。
                  onOpenModule: (module) =>
                      unawaited(_openReviewModule(module)),
                ),
                // 下层：底部词库抽屉。
                WordLibrarySheet(
                  key: const Key('word-library-sheet'),
                  expanded: _wordLibraryExpanded,
                  onExpandedChanged: (expanded) {
                    // 子组件的点击/下拉与首页全屏上滑都汇总到同一份状态。
                    if (_wordLibraryExpanded != expanded) {
                      setState(() => _wordLibraryExpanded = expanded);
                    }
                  },
                  onSearchChanged: _handleSearchChanged,
                  groupFilterBar: GroupFilterBar(
                    mode: _mode,
                    chips: chips,
                    onModeSelected: (mode) => setState(() {
                      _mode = mode;
                      _filterKey = null;
                    }),
                    onChipSelected: (key) => setState(() => _filterKey = key),
                    onOpenManage: () {
                      if (_mode != GroupMode.custom) return;
                      unawaited(showManageGroupsSheet(context, _groups));
                    },
                  ),
                  wordSortBar: WordSortBar(
                    selectedField: _sortField,
                    directions: _sortDirections,
                    onSelected: _handleSortSelected,
                    collapseLabel: allCollapsed ? '展开' : '折叠',
                    onToggleCollapseAll: () => setState(() {
                      if (allCollapsed) {
                        for (final section in shownSections) {
                          _collapsedKeys.remove(section.key);
                        }
                      } else {
                        for (final section in shownSections) {
                          _collapsedKeys.add(section.key);
                        }
                      }
                    }),
                    selectLabel: _selectMode ? '完成' : '选择',
                    onToggleSelectMode: () => setState(() {
                      _selectMode = !_selectMode;
                      _selectedWords.clear();
                      _swipedWord = null;
                    }),
                  ),
                  selectionBar: _selectMode
                      ? WordSelectionBar(
                          selectedCount: _selectedWords.length,
                          onSelectAll: () => setState(
                            () => _selectedWords.addAll(visibleWords),
                          ),
                          onInvertSelection: () => setState(() {
                            for (final word in visibleWords) {
                              if (!_selectedWords.remove(word)) {
                                _selectedWords.add(word);
                              }
                            }
                          }),
                          onMove: () =>
                              unawaited(_pickGroupAndApply(isCopy: false)),
                          onCopy: () =>
                              unawaited(_pickGroupAndApply(isCopy: true)),
                        )
                      : const SizedBox.shrink(),
                  listContent: ColoredBox(
                    color: tokens.card,
                    child: DecoratedBox(
                      key: const Key('word-list'),
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: tokens.border, width: 1),
                        ),
                      ),
                      child: _buildListContent(
                        shownSections,
                        visibleWords.isNotEmpty,
                      ),
                    ),
                  ),
                  targetCount: targetCount,
                  hasListeningSession: hasListeningSession,
                  hasListeningMeaningSession: hasListeningMeaningSession,
                  onOpenListening: () {
                    if (learningWords.isEmpty) {
                      _showComingSoon('当前列表没有可学习单词');
                      return;
                    }
                    unawaited(_openListening(learningWords));
                  },
                  onOpenListeningMeaning: () {
                    if (learningWords.isEmpty) {
                      _showComingSoon('当前列表没有可学习单词');
                      return;
                    }
                    unawaited(_openListeningMeaning(learningWords));
                  },
                  onContinueListening: () => unawaited(
                    _continueLearning(LearningSessionType.listening),
                  ),
                  onContinueListeningMeaning: () => unawaited(
                    _continueLearning(LearningSessionType.listeningMeaning),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

///
/// 把普通分组头包装为 Flutter 原生可吸顶的 Sliver 标题。
///
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  ///
  /// 接收实际分组头；状态和点击逻辑仍由首页统一管理。
  const _SectionHeaderDelegate({required this.child});

  ///
  /// 分组行必须始终保持原型规定的 34 逻辑像素高度。
  static const double height = 34;

  ///
  /// 真正显示的分组头组件。
  final Widget child;

  ///
  /// 最小高度与最大高度相同，因此滚动时只吸顶，不会缩放或拉伸。
  @override
  double get minExtent => height;

  ///
  /// 固定最大高度，防止吸顶过程中发生尺寸跳动。
  @override
  double get maxExtent => height;

  ///
  /// Flutter 每一帧滚动时调用这里，把分组头放进 Sliver 当前计算出的区域。
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // SizedBox.expand 让浅色背景完整覆盖吸顶区域，下面的单词不会透出来。
    return SizedBox.expand(child: child);
  }

  ///
  /// 首页状态变化会创建新的 child，此时要求 Flutter 重建标题内容。
  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    // 对象发生变化即重建，确保折叠箭头、数量和选择状态立即更新。
    return oldDelegate.child != child;
  }
}

///
/// 分组区块头：34 高浅底行，含可选勾选框、名称、计数与折叠箭头。
///
class _SectionHeader extends StatelessWidget {
  ///
  /// 全部状态由首页注入。
  const _SectionHeader({
    required this.section,
    required this.isCollapsed,
    required this.selectMode,
    required this.isAllSelected,
    required this.onTap,
    required this.onToggleSelect,
  });

  ///
  /// 当前区块数据。
  final _WordSection section;

  ///
  /// 是否处于折叠状态。
  final bool isCollapsed;

  ///
  /// 首页是否处于选择模式。
  final bool selectMode;

  ///
  /// 区块内全部单词是否都被选中。
  final bool isAllSelected;

  ///
  /// 点击行切换折叠。
  final VoidCallback onTap;

  ///
  /// 点击勾选框整组选中/取消。
  final VoidCallback onToggleSelect;

  ///
  /// 输出设计稿的分组头行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // InkWell 提供整行点击反馈。
    return InkWell(
      // key 便于测试点击具体分组头。
      key: Key('section-${section.key}'),
      onTap: onTap,
      child: Container(
        // 34 高浅底与底部分隔线。
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: tokens.sub,
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Row(
          children: [
            // 选择模式下显示整组勾选框。
            if (selectMode) ...[
              GestureDetector(
                // 阻止冒泡到整行折叠点击。
                onTap: onToggleSelect,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isAllSelected ? AppTokens.accent : tokens.card,
                    border: Border.all(
                      color: isAllSelected ? AppTokens.accent : tokens.check,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: isAllSelected
                      ? const Icon(
                          TablerIcons.check,
                          color: Colors.white,
                          size: 13,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 10),
            ],
            // 分组名称。
            Text(
              section.name,
              style: TextStyle(
                color: tokens.textMedium,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            // 撑开中间空间。
            const Spacer(),
            // 区块内单词数量。
            Text(
              '${section.words.length} 词',
              style: TextStyle(color: tokens.muted, fontSize: 11.5),
            ),
            // 数量与箭头间距。
            const SizedBox(width: 10),
            // 折叠箭头：折叠 0 度，展开旋转 90 度。
            AnimatedRotation(
              turns: isCollapsed ? 0 : 0.25,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                TablerIcons.chevronRight,
                color: tokens.muted,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
