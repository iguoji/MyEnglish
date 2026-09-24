import '../../services/self_test_policy.dart';
import 'widgets/word_library_learning_bar.dart';
// dart:async 提供 Timer 和 unawaited，分别用于搜索防抖和触发异步任务。
import 'dart:async';
// convert 提供 jsonDecode / JsonEncoder，用于解析导入 JSON 与生成导出 JSON。
import 'dart:convert';

// material.dart 提供页面、布局、加载指示器和按钮等 Flutter UI 组件。
import 'package:flutter/material.dart';
// kDebugMode：用来判断当前是不是 debug 构建，让「开始复习」的临时入口只在调试包里可点。
import 'package:flutter/foundation.dart';
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
// 引入复习词库模型。
import '../../models/word_set.dart';
// 复习会话模型提供模块标识、主线/巩固类型与三态进度。
import '../../models/session.dart';
// 音频服务由首页、随身听和听音辨义共同复用。
import '../../services/word_audio.dart';
// 离线语音缓存进度服务：首页加载词库后把单词列表交给它，供抽屉"离线语音"使用。
import '../../services/word_audio_cache.dart';
// 原生 SAF 文件读写服务：导入选 JSON、导出写文件，不依赖第三方 file_picker。
import '../../services/file_io.dart';
// 运行日志：导入导出清空等数据操作留痕，方便日后复查时间线。
import '../../services/app_log.dart';
import '../../services/study_open_timing.dart';
// 全屏听音辨义页。
import '../listening_meaning/listening_meaning_page.dart';
// 全屏随身听页。
import '../listening/listening_page.dart';
// 词义连连骨架页（顶部框架已就位，候选词区域待接入）。
import '../meaning_match/meaning_match_page.dart';
// 拼写巩固页：听发音、看释义，用 26 键键盘拼出单词。
import '../spelling_reinforcement/spelling_reinforcement_page.dart';
// 看义选词页：看中文含义，从候选词里选出匹配的英文单词。
import '../meaning_word_choice/meaning_word_choice_page.dart';
// 组件演示页（demo）：复用复习模块框架的空壳，用来预览各类 UI 组件。
import '../demo/demo_page.dart';
// 结算状态页公共组件：demo 首页「开始复习」当前演示的就是它。
import '../../widgets/settlement_summary.dart';
// 设置 Store 提供持久化口音、主题与每日复习目标。
import '../../store/settings.dart';
// 单词 Store 同样放在页面目录之外，其他页面可以直接复用。
import '../../store/word.dart';
// 引入会话 Store：词库、会话、记录与统计都走它。
import '../../store/session.dart';
// 复习流程服务把「备词库 → 开会话」这两步收敛到一处。
import '../review/services/review_flow.dart';
// 引入答题进度出口：写进度、记每次点击、结算难度都走它。
import '../review/services/session_progress.dart';
// 引入全站统一的二次确认对话框：删除单词、清空数据都弹它。
import '../../widgets/app_confirm_dialog.dart';
// 一局还没准备好时的过渡屏：词库底部随手开一局要等一秒多，先跳页再等它。
import '../../widgets/session_gate.dart';
// 右侧抽屉菜单。
import 'widgets/home_drawer.dart';
// 添加/修改单词表单。
import 'widgets/word_form_sheet.dart';
// 设计稿风格的单词行。
import 'widgets/word_list_tile.dart';
// 排序行与选择模式工具行。
import 'widgets/word_sort_bar.dart';
// 纯排序服务负责搜索过滤和多级稳定排序，页面只提供当前交互参数。
import 'services/home_word_sorter.dart';

// 首页专属尺寸表：本页的行高、弹窗按钮高度等都从这里取名字。
import 'widgets/home_layout.dart';

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
    this.clock = DateTime.now,
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

  /// 会话接口允许测试注入内存实现；正式 App 使用 SQLite。
  ///
  /// 复习词库、会话、点击记录与全部统计都由它一个负责。
  final SessionStore? sessionStore;

  ///
  /// 「现在几点」的取法，首页这一整屏的时间感都从这里来。
  ///
  /// 生活化解释：首页有好几处会看日历——顶部的「早上好 / 晚上好」、单词列表
  /// 按天分组的「今天 / 昨天」、打卡日历里今天那一格、趋势曲线横轴上的日期。
  /// 以前这几处各自去问一次系统「现在几点」，平时没问题，但基准截图
  /// （`test/goldens/`）就跟着日子走了：昨天拍的图和今天跑出来的图，
  /// 打卡日历必然差一格，于是每过一天测试就红一次，还得重拍一遍才能变绿——
  /// 真正的样式改动反倒被这种「假失败」盖住了。
  ///
  /// 所以时间也当成一个可注入的依赖：默认就是去问系统（`DateTime.now`），
  /// 正式 App 什么都不用传、行为和以前完全一样；测试传一个固定时刻进来，
  /// 整屏就定在那一天，截图从此不会自己变。
  final DateTime Function() clock;

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
  /// 每次重新加载都领取一个编号，迟到的旧请求不能覆盖新请求的数据。
  int _wordLoadGeneration = 0;

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

  ///
  /// 原生 SAF 文件读写服务：导入选 JSON、导出写文件。
  /// 默认走 Android 原生通道；测试可注入假通道避免真正弹出系统选择器。
  late final LocalFileIo _fileIo;

  ///
  /// 复习词库、会话、点击记录与统计的持久化接口。
  late final SessionStore _sessionStore;

  ///
  /// 复习流程服务：备今天的词库、决定这一局开主线还是开巩固。
  late final ReviewFlow _reviewFlow;

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

  /// 今天已经生成的复习词库；null 表示今天尚未点击过任何复习模块。
  WordSet? _dailyWordSet;

  ///
  /// 上一次已知的每日复习数量，用来发现用户在抽屉里改了设置。
  ///
  /// 数量变化后调整计划；已经开始的练习继续使用原试卷。
  int? _lastKnownDailyGoal;

  ///
  /// 保存已展开的 Word 对象；spelling 可重复，所以不能把拼写当作行身份。
  final Set<Word> _expandedWords = <Word>{};

  ///
  /// 勾选状态只记录单词编号；返回刷新、更新混淆词后仍认得同一个单词。
  final Set<int> _selectedWordIds = <int>{};

  ///
  /// 今天还挂着「进行中」的四种自测会话，用来显示词库底部的「继续」。
  ///
  /// 只看今天：会话表按日期组织，昨天没练完的局启动时已经默默结算或中断。
  var _resumableSessions = const <ReviewModule, Session>{};
  ReviewModule _libraryModule = ReviewModule.listening;
  bool _learningActionBusy = false;

  ///
  /// 四个答题页共用的路由名。
  ///
  /// 生活化解释：跨天回到 App 时，首页要把还停在答题页的那一层收掉——那一局
  /// 已经在后台默默结算完，留在上面继续答只会一路报「保存失败」。带上这个名字，
  /// 收尾时就能精确地只收答题页，不会顺手把随身听等其它页面一起弹掉。
  static const String _reviewRouteName = 'review-session';

  ///
  /// 当前处于下载或播放状态的具体 Word 对象。
  Word? _playingWord;

  ///
  /// 当前左滑露出操作区的行；同一时刻最多一行。
  Word? _swipedWord;

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
    // 同一初始时刻供问候语和列表年份判断使用；时间统一从注入的 clock 取。
    final initialTime = widget.clock();
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
    // 生产环境复用 SQLite 单例，测试可用内存 Store 精确控制「继续」入口。
    _sessionStore = widget.sessionStore ?? LocalSessionStore.instance;
    // 复习流程只依赖两个 Store，测试注入内存实现即可完整验证选词与开局。
    _reviewFlow = ReviewFlow(wordStore: _store, sessionStore: _sessionStore);
    // 记下启动时的每日复习量，之后靠它发现用户在抽屉里改过设置。
    _lastKnownDailyGoal = _settings.dailyGoal;
    // 初始化列表年份参考。
    _dateReference = initialTime;
    // 注册 App 前后台观察者。
    WidgetsBinding.instance.addObserver(this);
    // 监听设置变化，让副标题的复习目标即时刷新。
    _settings.addListener(_handleExternalChange);
    // 异步加载全部 Word/Meaning；方法内部完成 setState。
    unawaited(_loadInitialData());
    // 读取今日复习数量，让副标题的「今日复习 X/目标」显示真实数据而非写死的 0。

    // 若今天已经建过词库，先恢复它供首页展示。

    // 独立读取未完成会话，不让辅助数据阻塞首页单词列表首屏。

    // 跨天后昨天没打完的局挂着没有意义，启动时统一收成「中断」。
  }

  ///
  /// 首屏数据加载：先收尾跨天会话，再并行读取词库、进度、今日计划和未完成会话。
  Future<void> _loadInitialData() async {
    // 启动时没有页面栈，收尾结果只用于保持数据库整洁，不需要送回首页。
    await _closeStaleReviewSessions(recoverSettlements: true);
    if (!mounted) return;
    await Future.wait<void>(<Future<void>>[
      _loadWords(),
      _loadReviewProgress(),
      _loadDailyWordSet(),
      _loadResumableSessions(),
    ]);
  }

  ///
  /// 跨天收尾：把昨天及更早还挂在「进行中」的会话收掉。
  ///
  /// 生活化解释：昨天做到一半退出去了，今天再打开 App，那一局已经没有意义
  /// ——今天有今天的词库。收尾分两种走法：答过题的按已答情况当场结算并落实难度
  /// （不弹结算页、不让用户调难度），一条答案都没答过的直接中断。
  /// 先落实上次已完成但没提交的结算，再读取词库和计划，避免首屏读到旧难度和旧统计。
  ///
  /// 返回本次收尾掉的会话数量；调用方据此判断要不要把用户从答题页送回首页。
  Future<int> _closeStaleReviewSessions({
    bool recoverSettlements = false,
  }) async {
    try {
      // 进程被系统直接回收时，结算页没有机会点击“返回首页”；启动先把
      // 仍挂着的草稿应用掉，避免用户看到完成状态却一直没有更新难度。
      // 普通恢复前台时，结算页可能仍在编辑，不能提前替用户确认。
      if (recoverSettlements) await _sessionStore.recoverPendingSettlements();
      // 会话表按日期组织；开局时会拿今天的日期查，昨天那些查不到也就不会被续上。
      // 这里把它们统一收尾，免得数据库里攒下一堆永远不会结束的局。
      return await _sessionStore.settleStaleSessions(todayKey());
    } catch (error) {
      // 收尾属于后台维护动作，失败只写日志，绝不影响首页展示。
      debugPrint('收尾过期复习会话失败：$error');
      return 0;
    }
  }

  Future<void> _refreshAfterResume() async {
    final closed = await _closeStaleReviewSessions();
    if (!mounted) return;
    // 有会话被收尾，说明用户很可能还停在昨天那一局的答题页上：
    // 把他送回首页，避免他继续答一份已经结算掉的试卷。
    if (closed > 0) _leaveStaleReviewPage();
    await _refreshReviewDashboard();
  }

  ///
  /// 跨天收尾后，把还停在答题页的用户送回首页。
  ///
  /// 只收答题页那一层：用户可能正在看别的页面（比如随身听），不能一并弹掉。
  /// 这一局已经在后台结算完，留在页面上继续答只会一路报「保存失败」。
  void _leaveStaleReviewPage() {
    final navigator = Navigator.of(context);
    // 栈顶不是答题页时不会弹任何东西，等于什么都没发生。
    var popped = false;
    navigator.popUntil((route) {
      if (route.isFirst || route.settings.name != _reviewRouteName) return true;
      popped = true;
      return false;
    });
    // 只有真的把用户从答题页里请出来才提示；启动时静默收尾不打扰用户。
    if (popped) Toast.show(context, '上次没答完的练习已按已答情况结算');
  }

  ///
  /// 设置或分组内容变化时触发整页重建。
  void _handleExternalChange() {
    // 页面已卸载时不再处理任何状态。
    if (!mounted) return;
    // 每日数量变化只维护计划，已经开始的会话继续使用快照。
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
  /// 当天计划按新数量补足或缩减，正在进行的试卷与已完成标记都保留。
  Future<void> _handleDailyGoalChanged() async {
    if (!mounted) return;
    // 内存里缓存的旧词库数量已经不对，清掉让下次开局重新读取。
    setState(() => _dailyWordSet = null);
    // 四张卡片的三态、头部数字与曲线一起重算。
    await _refreshReviewDashboard();
  }

  ///
  /// 按当前页面状态创建纯排序服务；服务不持有 Widget，可独立测试。
  HomeWordSorter get _wordSorter => HomeWordSorter(
    // 当前排序入口由工具栏维护。
    field: _sortField,
    // 各字段保留自己的升降序。
    directions: _sortDirections,
    // 搜索防抖完成后保存的小写查询词。
    query: _query,
  );

  ///
  /// 返回列表行应展示的日期（固定为最近一次复习时间）。
  DateTime? _listDateOf(Word word) => _wordSorter.dateOf(word);

  ///
  /// 对一个区块执行搜索过滤与稳定排序。
  List<Word> _filterAndSort(List<Word> source) {
    // 业务比较规则集中在独立服务，页面只负责提供当前交互状态。
    return _wordSorter.filterAndSort(source);
  }

  ///
  /// 按当前分组视角把全部单词组织成区块列表。
  ///
  /// 词库固定按难度分组：难度数值从高到低排列，「无难度」固定在最后，
  /// 不再有「按复习时间 / 未复习」等其他分组视角。
  List<_WordSection> _buildSections() {
    // 汇总结果。
    final sections = <_WordSection>[];
    // 难度视角：数值从高到低，"无难度"固定在最后。
    // 业务约定：难度 0 与"无难度"(null) 是同一概念，内部必须合并成同一个组，
    // 不能像以前那样把 0 显示成"难度 0"、把 null 显示成"无难度"分成两个区块。
    // 因此先把每个单词的难度按 null→0 归一成 int，再收集去重。
    final values = <int>{for (final word in _allWords) word.difficulty}.toList()
      ..sort((a, b) => b.compareTo(a));
    // 逐个难度生成区块；分区筛选与单词归属都用 (difficulty ?? 0) 比较。
    for (final value in values) {
      sections.add(
        _WordSection(
          // 合并后 0 与 null 共用 key 'd0'，不再出现 'dx'。
          key: 'd$value',
          // 值为 0 表示"无难度"（含原 null 单词），其余显示具体难度。
          name: value == 0 ? '无难度' : '难度 $value',
          words: _filterAndSort(
            _allWords.where((word) => word.difficulty == value).toList(),
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
    final generation = ++_wordLoadGeneration;
    final watch = Stopwatch()..start();
    var reportedSlow = false;
    // 重试时立即切回加载状态并清空旧错误。
    setState(() {
      // 显示进度指示器。
      _isLoading = true;
      // 清除上次 PlatformException。
      _loadError = null;
    });

    // 成功处理挂在原始请求上；外层 timeout 只限制调用方等待，不能抛弃迟到数据。
    // Future.sync 同时接住 Store 同步抛错和异步失败，保持一个错误出口。
    final operation = Future<List<Word>>.sync(_store.getAll)
        .then<void>((words) {
          if (!mounted || generation != _wordLoadGeneration) return;
          // 一次写入全部数据并结束加载状态。
          setState(() {
            // 保存本地 SQLite 持久化返回的 Word/Meaning（App 仅此一种数据来源）。
            _allWords = words;
            // 数据重载后清除已经不存在的展开、选中与滑动状态。
            _expandedWords.removeWhere((word) => !words.contains(word));
            _selectedWordIds.retainAll(words.map((word) => word.id));
            if (_swipedWord != null && !words.contains(_swipedWord)) {
              _swipedWord = null;
            }
            // 隐藏加载指示器。
            _isLoading = false;
            _loadError = null;
          });
          if (reportedSlow || StudyOpenTiming.enabled) {
            AppLog.i(
              'word_load',
              '${reportedSlow ? '较慢请求已自动完成' : '词库已载入'} words=${words.length} elapsed=${watch.elapsedMilliseconds}ms',
            );
          }
          // 把最新词库告知离线语音缓存服务，用于计算总数与初始已缓存百分比。
          // 通道不可用（如单元测试无原生实现）时服务内部会安全回退为 0。
          unawaited(
            WordAudioCache.instance.setWordList(
              words.map((word) => word.spelling).toList(),
            ),
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!mounted || generation != _wordLoadGeneration) return;
          // 调试控制台保留完整错误和调用堆栈，真机日志也能直接查到根因。
          debugPrint('单词数据加载失败：$error');
          // stackTrace 记录完整调用堆栈，帮助定位具体代码行。
          debugPrintStack(stackTrace: stackTrace);
          AppLog.e('word_load', '读取词库失败：$error');
          // 保存错误并结束加载状态，界面会显示重试按钮。
          setState(() {
            // 记录原始异常供调试。
            _loadError = error;
            // 隐藏加载动画。
            _isLoading = false;
          });
        })
        .whenComplete(watch.stop);

    await operation.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        if (!mounted || generation != _wordLoadGeneration) return;
        reportedSlow = true;
        setState(() {
          _isLoading = false;
          _loadError = TimeoutException('读取较慢，结果返回后会自动显示，也可以重新加载。');
        });
        AppLog.i('word_load', '读取超过8秒，继续接收当前请求的结果');
      },
    );
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
      _selectedWordIds.retainAll(words.map((word) => word.id));
      if (_swipedWord != null && !words.contains(_swipedWord)) {
        _swipedWord = null;
      }
      // 词库里的单词被删除时只释放内存缓存，不直接丢掉数据库中的其余顺序。
      // 下次进入任意复习模块时，ReviewFlow 会读取原词库、保留仍有效的 id，
      // 再按同一套排序规则补足缺口。
      final wordSet = _dailyWordSet;
      if (wordSet != null &&
          wordSet.todayWordIds.any((id) => !existingWordIds.contains(id))) {
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
    await _loadResumableSessions();
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
        _sessionStore.getTodayReviewedWordCount(todayKey()),
        _sessionStore.getTodayModuleStates(todayKey()),
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
      // 复习结算会在离开结算页后才正式改写 words 表；这里重新读词库，
      // 让难度分组和搜索结果立即反映刚刚结算的最终值。
      _refreshWords(),
    ]);
    // 页面可能在等待期间被关闭。
    if (!mounted) return;
    // 序号变化会让两张自管数据的卡片在 didUpdateWidget 里重新查询。
    setState(() => _dashboardRefreshToken += 1);
  }

  ///
  /// 获取今日计划并及时补缺，新增单词不需要等到第二天。
  Future<void> _loadDailyWordSet() async {
    try {
      // null 表示今天还没有点开过任何复习模块。
      final wordSet = await _sessionStore.resolvePlan(
        date: todayKey(),
        dailyGoal: _settings.dailyGoal,
      );
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
  /// 开局规则由 [ReviewFlow.openModule] 处理；入口锁覆盖开局与整个页面，
  /// 这里负责刷新计划并把读取错误转成用户提示。
  Future<ReviewEntry?> _openReviewSession(ReviewModule module) async {
    try {
      final entry = await _reviewFlow.openModule(
        module,
        dailyGoal: _settings.dailyGoal,
        libraryCount: _allWords.length,
        date: todayKey(),
        // 选择题的混淆项从全局词库里挑；首页手上已有整库，不必再读一遍。
        corpusWords: _allWords,
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
  /// 读取今天有实际作答的四种自测会话，决定胶囊里的继续按钮是否启用。
  ///
  /// 失败时禁用继续按钮，不影响首页主体；每日复习的状态由首页卡片独立展示。
  Future<void> _loadResumableSessions() async {
    try {
      final date = todayKey();
      final found = <ReviewModule, Session>{};
      // 四个自测分别续接；随身听的清单和进度由设置独立维护。
      for (final module in ReviewModule.reviewCards) {
        final session = await _sessionStore.getActiveSession(
          module,
          date,
          selfTest: true,
          headerOnly: true,
        );
        if (session != null && session.isActive) found[module] = session;
      }
      if (!mounted) return;
      setState(() => _resumableSessions = found);
    } catch (error, stackTrace) {
      // 辅助能力异常只写调试日志，不能让首页进入整页错误状态。
      debugPrint('读取学习进度失败：$error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _resumableSessions = const <ReviewModule, Session>{});
    }
  }

  ///
  /// 从词库底部按明确选词创建一局自测。
  ///
  /// 用户当场挑的这批词不属于今天的词库，所以固定按「巩固」算：
  /// 答题照常记录、照常调难度，但不推进复习时间。
  Future<SessionProgress?> _openAdHocSession(
    ReviewModule module,
    List<Word> words,
  ) async {
    final timing = StudyOpenTiming.start(module.storageKey, words.length);
    Future<SessionProgress?> open() async {
      // 先让出当前这一帧再动手。
      //
      // 生活化解释：把整库（上千个词）编排成一整张试卷是一段**同步**计算，几千道
      // 小题就在这一瞬间算完。如果抢在按钮回调里做，跳页动画得等它算完才动，用户
      // 反而觉得更卡。等这一帧画完再开始，跳页先跑起来、页面上的转圈先转起来，
      // 重活随后在后台做——`endOfFrame` 在没有帧排队时会自己排一帧，不会卡死。
      await WidgetsBinding.instance.endOfFrame;
      timing?.mark('frame_yielded');
      try {
        final entry = await _reviewFlow.openAdHoc(
          module,
          wordIds: <int>[
            for (final word in words)
              if (word.id != null) word.id!,
          ],
          date: todayKey(),
          // 这批单词对象首页手上就有，直接带过去，别再按编号把整库读一遍。
          preloaded: words,
          corpusWords: _allWords,
        );
        if (!mounted || entry == null) {
          timing?.cancel('entry_unavailable');
          return null;
        }
        final progress = SessionProgress(
          store: _sessionStore,
          session: entry.session,
          records: entry.records,
          corpusWords: _allWords,
        );
        timing?.attach(progress);
        timing?.mark('controller_ready');
        return progress;
      } catch (error, stackTrace) {
        timing?.cancel('entry_failed');
        debugPrint('打开${module.label}失败：$error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) Toast.show(context, '打开${module.label}失败，请重试');
        return null;
      }
    }

    return timing == null ? open() : timing.run(open);
  }

  /// 首页卡片和词库入口共用一把锁，直到学习页面返回才释放。
  /// 只合并开局请求仍会重复跳页，因此锁必须覆盖导航及“再来一次”。
  Future<void> _runLearningAction(Future<void> Function() action) async {
    if (_learningActionBusy) return;
    setState(() => _learningActionBusy = true);
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('打开学习页面失败：$error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) Toast.show(context, '打开失败，请重试：$error');
    } finally {
      if (mounted) setState(() => _learningActionBusy = false);
    }
  }

  /// 新清单只保存编号及初始位置，直接复用词库里已经读取的单词对象进入页面。
  Future<void> _startListening(List<Word> words) =>
      _runLearningAction(() async {
        final valid = [
          for (final word in words)
            if (word.id != null) word,
        ];
        if (valid.isEmpty) return;
        await _settings.startListening(valid.map((word) => word.id!));
        if (!mounted) return;
        await _showListening(valid);
      });

  /// 续播按保存的编号重建顺序；删除项自动跳过，当前位置跟随原来的单词。
  Future<void> _continueListening() => _runLearningAction(() async {
    final saved = _settings.listeningPlayback;
    if (!saved.hasWords) return;
    final currentWords = await _store.getByIds(saved.wordIds);
    if (!mounted) return;
    final byId = {for (final word in currentWords) word.id!: word};
    final available = saved.retainExisting(
      byId.keys.toSet(),
      loop: _settings.listeningLoop,
    );
    await _settings.saveListeningPlayback(available);
    if (!mounted) return;
    if (!available.hasWords) {
      Toast.show(context, '播放列表中的单词已全部删除，请重新选择');
      return;
    }
    await _showListening([for (final id in available.wordIds) byId[id]!]);
  });

  Future<void> _showListening(List<Word> words) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListeningPage(
          words: words,
          audioPlayer: _audioPlayer,
          settings: _settings,
          wordStore: _store,
        ),
      ),
    );
    // 随身听不修改复习数据，只刷新清单的继续入口，不再重算整张仪表盘。
    if (mounted) setState(() {});
  }

  Future<void> _startSelfTest(ReviewModule module, List<Word> words) =>
      _runLearningAction(() async {
        final reason = SelfTestPolicy.unavailableReason(words.length);
        if (reason != null) {
          Toast.show(context, reason);
          return;
        }
        await _openStudyPage(module, _openAdHocSession(module, words));
      });

  /// 首页练习和词库自测共用页面路由，只有开局来源不同。
  Future<void> _openReviewModule(ReviewModule module) =>
      _runLearningAction(() => _showDailyStudyPage(module));

  /// “再来一次”仍由同一个入口锁保护，只重开试卷，不再次争用锁。
  Future<void> _showDailyStudyPage(ReviewModule module) async {
    if (!module.isReviewCard) return;
    final entry = await _openReviewSession(module);
    if (!mounted || entry == null) return;
    await _openStudyPage(
      module,
      SessionProgress(
        store: _sessionStore,
        session: entry.session,
        records: entry.records,
        corpusWords: _allWords,
      ),
    );
  }

  Future<void> _openStudyPage(
    ReviewModule module,
    FutureOr<SessionProgress?> pending,
  ) async {
    SessionProgress? opened;
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<dynamic>(
        // 带上固定路由名：跨天收尾时首页据此精确地把答题页收掉（见 [_reviewRouteName]）。
        settings: const RouteSettings(name: _reviewRouteName),
        builder: (_) => SessionGate<SessionProgress>(
          pending: pending,
          onDiscard: (progress) => progress.detach(),
          builder: (progress) {
            opened = progress;
            final words = _orderedSessionWords(progress.session);
            return switch (module) {
              ReviewModule.listening => throw StateError('随身听使用独立播放清单'),
              ReviewModule.listeningMeaning => ListeningMeaningPage(
                words: words,
                corpusWords: _allWords,
                audioPlayer: _audioPlayer,
                accent: _settings.accent,
                definitionSeparator: _settings.definitionSeparator.symbol,
                progress: progress,
                wordStore: _store,
              ),
              ReviewModule.meaningMatch => MeaningMatchPage(
                words: words,
                title: module.label,
                progress: progress,
                audioPlayer: _audioPlayer,
                accent: _settings.accent,
              ),
              ReviewModule.spellingReinforcement => SpellingReinforcementPage(
                words: words,
                title: module.label,
                progress: progress,
                audioPlayer: _audioPlayer,
                accent: _settings.accent,
                definitionSeparator: _settings.definitionSeparator.symbol,
              ),
              ReviewModule.meaningWordChoice => MeaningWordChoicePage(
                words: words,
                title: module.label,
                progress: progress,
                audioPlayer: _audioPlayer,
                accent: _settings.accent,
              ),
            };
          },
        ),
      ),
    );
    if (!mounted) return;
    if (result is List<int>) await _mergeReviewedWords(result);
    await _refreshReviewDashboard();
    if (!mounted || result != true || opened == null) return;
    if (opened!.session.kind == SessionKind.selfTest) {
      // 自测的“再来一次”沿用原选词，绝不能误开成首页的每日复习。
      final words = _orderedSessionWords(opened!.session);
      final reason = SelfTestPolicy.unavailableReason(words.length);
      if (reason != null) {
        Toast.show(context, reason);
        return;
      }
      await _openStudyPage(module, _openAdHocSession(module, words));
    } else {
      await _showDailyStudyPage(module);
    }
  }

  ///
  /// 打开组件演示页（demo）。
  ///
  /// 临时入口挂在首页「开始复习」标题上：点一下整段字就进到和复习模块同款
  /// 框架的空白演示页，将来各类 UI 组件（比如结算状态页公共组件）就往里放。
  /// 这是给开发预览用的，不是正式功能，将来会换成正式路由或调试菜单。
  Future<void> _openDemoPage() async {
    // 演示页顶栏是正式复习模块的默认形态（返回键 + 数字进度 + 停留时间 +
    // 底部进度条）；正文区塞入「结算状态页公共组件」的示例数据，方便直接看样式。
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DemoPage(body: SettlementSummary.demo()),
      ),
    );
  }

  ///
  /// 把一局会话涉及的单词按数据列表顺序排好。
  ///
  /// 看义选词的数据列表是含义主键，没有天然的单词顺序，直接给全部单词即可——
  /// 它本来就要在整个候选池里挑词。
  List<Word> _orderedSessionWords(Session session) {
    final byId = {for (final word in session.snapshotWords) word.id!: word};
    final ids = <int>{
      for (final question in session.questions) ...question.wordIds,
    };
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 继续旧自测使用原选词，入口的 5–100 词限制只约束新建，保留已有进度。
  Future<void> _continueSelfTest(ReviewModule module) => _runLearningAction(
    () async {
      final entry = await _reviewFlow.resumeSelf(module, todayKey());
      if (!mounted) return;
      if (entry == null) {
        // 进度可能已经失效；清掉旧的可恢复标记，让按钮状态与恢复结果一致。
        setState(() {
          _resumableSessions = Map<ReviewModule, Session>.of(_resumableSessions)
            ..remove(module);
        });
        Toast.show(context, '当前模块没有可继续的自测进度');
        return;
      }
      await _openStudyPage(
        module,
        SessionProgress(
          store: _sessionStore,
          session: entry.session,
          records: entry.records,
          corpusWords: _allWords,
        ),
      );
    },
  );

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
      final resumedAt = widget.clock();
      // 跨年后重新构建静态列表日期；问候语也顺带刷新。
      setState(() {
        _dateReference = resumedAt;
        // 日期已经变化时先同步清空旧词库，避免原生异步读取完成前误用昨天那批词。
        if (_dailyWordSet?.date != _localDateKey(resumedAt)) {
          _dailyWordSet = null;
        }
      });
      // 后台待了一夜再回来，昨天没打完的局要先收尾（按已答情况结算），
      // 否则今天点开模块会续上昨天那一局；用户还停在答题页时会被送回首页。
      unawaited(_refreshAfterResume());
      // 回到前台时把仪表盘的进度整体重算：今日复习数、每日词库、未完成会话，
      // 以及趋势曲线与打卡日历（跨天或后台产生过记录时保持准确）。

      // 防止继续执行下面停止逻辑。
      return;
    }
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
      final wasSelected = _selectedWordIds.remove(word.id);
      if (!wasSelected && word.id != null) _selectedWordIds.add(word.id!);
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
      // 原生智能轮转：同一词连点会按 不背单词→百度→有道→本地TTS 顺序轮流点名；
      // 切换单词或离开页面后账本自动作废，重新从最高优先级开始。
      await _audioPlayer.play(word.spelling, accent);
      // 播音不附带任何提示：网络渠道静默失败、TTS 正常发声都不打扰用户，
      // 只有 TTS 引擎本身不可用（走下方专用异常）才需要说明。
    } on WordAudioTtsUnavailableException catch (error) {
      // 设备没有可用的离线英语 TTS（且网络发音未能成功兜住）时给出明确提示，
      // 不带“播放失败”前缀，直接展示原因，方便用户去装语音包或联网。
      if (mounted && identical(_playingWord, word)) {
        Toast.show(context, error.toString());
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
        editing: editing,
        onSubmit: (result) => _submitWordForm(result, editing: editing),
      ),
    );
  }

  ///
  /// 执行表单提交：新增走 create，编辑走 update。
  Future<void> _submitWordForm(WordFormResult result, {Word? editing}) async {
    try {
      // 编辑模式：在原对象基础上替换拼写与释义。
      if (editing != null) {
        await _store.update(
          editing.edited(spelling: result.spelling, meanings: result.meanings),
        );
      } else {
        // 新增模式：交给 Store 生成主键与时间。
        await _store.create(
          Word(spelling: result.spelling, meanings: result.meanings),
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
  ///
  /// 骨架交给公共组件 [AppConfirmDialog]，这里只填这一处特有的文案。
  /// 确认按钮刻意用危险红：删掉的单词连释义一起没了，颜色要先把后果说出来。
  void _confirmDelete(Word word) {
    // 先收起滑动操作区。
    setState(() => _swipedWord = null);
    unawaited(
      AppConfirmDialog.show(
        context,
        AppConfirmDialog(
          title: '删除单词',
          message: '确定要删除「${word.spelling}」吗？此操作无法撤销。',
          cancelKey: const Key('delete-cancel'),
          confirmKey: const Key('delete-confirm'),
          confirmLabel: '删除',
          confirmColor: AppTokens.danger,
        ),
      ).then((confirmed) {
        // 对话框自己关好了，这里只管确认之后的事。
        if (confirmed) unawaited(_deleteWord(word));
      }),
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
    var imported = false;
    try {
      // 打开系统文件选择器，只列出 JSON；用户取消时返回 null，不做任何改动。
      final jsonText = await _fileIo.pickJsonText();
      // 取消选择或读到空文本都直接返回。
      if (jsonText == null || jsonText.isEmpty) return;
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map ||
          decoded['version'] != 3 ||
          decoded['words'] is! List) {
        throw const FormatException('请选择 version=3 的完整备份，旧数据需先转换为新格式');
      }
      final payload = Map<String, Object?>.from(decoded);
      // 原生先验证十一张表和关联；整份文件要么全部恢复，要么保留原数据。
      await _store.importData(payload);
      imported = true;
      final importedCount = (payload['words'] as List)
          .where((row) => row is Map && row['deleted_at'] == null)
          .length;
      await _settings.reload();
      // 文件操作期间首页可能已退出，后续不能再更新页面状态或发起页面刷新。
      if (!mounted) return;
      // 全部数据已被备份替换，先清掉旧缓存，再读取备份中的计划和继续进度。
      setState(() {
        _resumableSessions = const <ReviewModule, Session>{};
        // 这些缓存属于导入前的数据，不能和新词库混用。
        _dailyWordSet = null;
        _reviewModuleStates = const <ReviewModule, ReviewModuleState>{};
        _reviewCount = 0;
      });
      // 整库数据已替换：重载单词列表，并重算今日词库/复习进度/继续入口，
      // 让首页在导入「另一台设备的完整备份」后立即反映还原结果。
      await _loadWords();
      await _refreshReviewDashboard();
      if (!mounted) return;
      // 数据操作留痕：整库导入成功，记录单词数量。
      AppLog.i('data', '数据导入完成 words=$importedCount');
      _showSnackBar('已恢复 $importedCount 个单词及全部计划、会话和设置');
    } on FormatException catch (error) {
      // JSON 结构或字段错误，显示具体原因便于修正文件。
      _showSnackBar(
        imported
            ? '备份已导入，但界面刷新失败，请重新打开应用：${error.message}'
            : '导入失败：${error.message}',
      );
    } catch (error) {
      // 数据库替换成功后的刷新错误不能再说成“导入失败”，以免用户误判数据状态。
      _showSnackBar(
        imported
            ? '备份已导入，但界面刷新失败，请重新打开应用：${_describeLoadError(error)}'
            : '导入失败：${_describeLoadError(error)}',
      );
    }
  }

  ///
  /// 完整导出十一张业务表，包含词库、设置、计划、题目、答案、结算及软删除历史。
  /// 文件格式为 version=3；离线音频和运行日志不在这份备份中。
  Future<void> _exportData() async {
    // 先关闭抽屉，避免遮挡系统保存框。
    Navigator.of(context).pop();
    try {
      // 原生层读取 SQLite 全部业务字段并并入设置，生成完整备份对象。
      final payload = await _store.exportData();
      // 缩进格式，便于人读与二次编辑。
      final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
      // 文件名：App 名 + 当前日期，例如 MyEnglish-2026-07-28.json。
      final fileName =
          'MyEnglish-${widget.clock().toIso8601String().substring(0, 10)}.json';
      // 通过系统保存框写出；由原生 SAF 把文本落盘到用户选择的位置。
      final savedUri = await _fileIo.writeExportJson(
        fileName: fileName,
        jsonText: jsonText,
      );
      // 用户取消保存不提示。
      if (savedUri == null) return;
      if (!mounted) return;
      // 数据操作留痕：导出成功写入日志，复查时能对齐到具体时间点。
      AppLog.i('data', '数据导出完成，保存位置=$savedUri');
      _showSnackBar('已导出全部数据（词库/设置/会话/复习等）');
    } catch (error) {
      // 读取或保存异常，显示可读详情。
      _showSnackBar('导出失败：${_describeLoadError(error)}');
    }
  }

  ///
  /// 导出运行日志：直接调起系统保存框，把单日日志文件拷贝到用户选择的位置。
  ///
  /// 与数据导出不同，日志文件已在原生侧维护（单文件、只留当天），这里只负责
  /// 起一个默认文件名并打开系统保存框；用户确认后由原生流式拷贝，无多余步骤。
  Future<void> _exportLog() async {
    // 先收起抽屉，避免遮挡系统保存框。
    _scaffoldKey.currentState?.closeEndDrawer();
    try {
      // 文件名：App 名 + 日志 + 当前日期，例如 MyEnglish-日志-2026-09-06.txt。
      final fileName =
          'MyEnglish-日志-${widget.clock().toIso8601String().substring(0, 10)}.txt';
      // 通过系统保存框导出；用户选择位置并确认后返回真实 Uri。
      final savedUri = await _fileIo.exportLogFile(fileName: fileName);
      // 用户取消保存不提示。
      if (savedUri == null) return;
      if (!mounted) return;
      AppLog.i('file', '用户从抽屉导出日志 $fileName');
      _showSnackBar('日志已导出');
    } catch (error) {
      // 读取或保存异常，显示可读详情。
      if (!mounted) return;
      _showSnackBar('日志导出失败：${_describeLoadError(error)}');
    }
  }

  ///
  /// 清空数据：二次确认后清空词库、全部会话与复习记录、候选/音节缓存、设置
  /// 与离线语音缓存，恢复到首次安装状态。
  Future<void> _clearData() async {
    // 先关闭抽屉，避免遮挡确认弹窗。
    Navigator.of(context).pop();
    // 危险操作必须二次确认，避免误触。
    final confirmed = await _showClearConfirmDialog();
    // 用户取消则什么都不做。
    if (!confirmed || !mounted) return;
    try {
      // 清空新版数据库的全部业务表；旧版数据库文件保持原样。
      await _store.clearAll();
      // 重置数据库中的偏好，并同步恢复内存默认值。
      await _settings.clearAll();
      // 一并清空离线语音缓存文件（word_audio 目录下全部 mp3），并重置进度。
      await WordAudioCache.instance.clearCacheFiles();
      // 多项原生清理完成前用户可能已经离开首页。
      if (!mounted) return;
      // 与原生删除保持同步，让继续入口无需等待下一次读取就立即消失。
      setState(() {
        _resumableSessions = const <ReviewModule, Session>{};
        // 原生已清空复习词库与全部复习数据，避免卡片继续显示旧状态。
        _dailyWordSet = null;
        _reviewModuleStates = const <ReviewModule, ReviewModuleState>{};
        _reviewCount = 0;
      });
      // 重新加载空列表，并刷新今日词库/复习进度/继续入口，让卡片立即归零。
      unawaited(_loadWords());
      unawaited(_refreshReviewDashboard());
      // 数据操作留痕：清空是破坏性动作，务必留下时间点。
      AppLog.i('data', '已清空全部本地数据');
      // 提示已清空。
      _showSnackBar('已清空全部本地数据');
    } catch (error) {
      // 清空异常，显示可读详情。
      _showSnackBar('清空失败：${_describeLoadError(error)}');
    }
  }

  ///
  /// 清空数据的二次确认弹窗，返回 true 表示用户确认清空。
  ///
  /// 骨架交给公共组件 [AppConfirmDialog]，这里只填这一处特有的文案。
  Future<bool> _showClearConfirmDialog() {
    return AppConfirmDialog.show(
      context,
      const AppConfirmDialog(
        title: '清空数据',
        // 明确告知后果，不可恢复。
        message: '将删除全部单词（含释义）、所有设置与已下载的离线语音音频，此操作不可恢复。',
        cancelKey: Key('clear-cancel'),
        confirmKey: Key('clear-confirm'),
        confirmLabel: '确认清空',
      ),
    );
  }

  ///
  /// 将任意异常转换成用户可见的详情，不再只显示笼统失败文案。
  String _describeLoadError(Object error) {
    if (error is TimeoutException) return error.message ?? '词库仍在准备，请稍候。';
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
    // 页面关闭后，正在进行的读数与超时提醒都不能再修改界面。
    _wordLoadGeneration++;
    // 移除设置监听。
    _settings.removeListener(_handleExternalChange);
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
          width: HomeLayout.loadingIndicatorSize,
          height: HomeLayout.loadingIndicatorSize,
          // CircularProgressIndicator 显示加载中的旋转指示圈。
          child: CircularProgressIndicator(strokeWidth: AppStroke.ring),
        ),
      );
    }

    // Store 抛错时同时显示可恢复操作与实际异常详情。
    if (_loadError != null) {
      // SingleChildScrollView 防止较长错误在小屏幕发生纵向溢出。
      return Center(
        child: SingleChildScrollView(
          // 错误区与屏幕边缘保持足够距离。
          padding: const EdgeInsets.all(AppSpace.pBase),
          child: Column(
            // mainAxisSize.min 让内容不强制撑满整个滚动区域。
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用户首先看到简短结论。
              Text(
                _loadError is TimeoutException ? '词库仍在准备' : '单词数据加载失败',
                style: const TextStyle(fontWeight: AppWeight.semibold),
              ),
              // 标题与详情之间留白。
              const SizedBox(height: AppSpace.p2),
              // SelectableText 允许长按选择并复制真机上的具体错误。
              SelectableText(
                // key 让测试能确认具体错误确实已经输出到页面。
                key: const Key('word-load-error-details'),
                // 输出原始 FormatException 或 PlatformException 内容。
                _describeLoadError(_loadError!),
                // 错误详情居中阅读。
                textAlign: TextAlign.center,
                // 使用次要颜色与较小字号，不抢过错误标题。
                style: Theme.of(context).textTheme.fs6.copyWith(
                  color: AppTokens.of(context).textSecondary,
                ),
              ),
              // 详情与按钮间距。
              const SizedBox(height: AppSpace.p2),
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
          style: Theme.of(
            context,
          ).textTheme.fs5.copyWith(color: AppTokens.of(context).textSecondary),
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
          // 悬浮入口覆盖在列表上方，只给最后一行留出可滚到胶囊上方的余量。
          SliverPadding(
            padding: EdgeInsets.only(
              bottom:
                  WordLibraryLayout.learningOverlayExtent +
                  MediaQuery.paddingOf(context).bottom,
            ),
          ),
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
        section.words.every((word) => _selectedWordIds.contains(word.id));
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
          _selectedWordIds.removeAll(section.words.map((word) => word.id));
        } else {
          _selectedWordIds.addAll(
            section.words.map((word) => word.id).whereType<int>(),
          );
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
      isSelected: _selectedWordIds.contains(word.id),
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
    // 词库不再提供"只看某个难度"的筛选胶囊（4.4.1 起删除），所有区块平铺显示；
    // 搜索时隐藏没有匹配的分组。
    var shownSections = sections;
    if (_query.isNotEmpty) {
      shownSections = sections
          .where((section) => section.words.isNotEmpty)
          .toList();
    }
    // 当前可见（参与全选与随身听默认列表）的全部单词。
    final visibleWords = <Word>[
      for (final section in shownSections) ...section.words,
    ];
    // 把首页当前顺序冻结成只读快照，页面跳转后不受后续重建中的临时列表影响。
    final visibleWordSnapshot = List<Word>.unmodifiable(visibleWords);
    // 已勾选的词不因搜索暂时隐藏而丢失，数量与上方选择栏保持一致。
    // 依旧按当前“难度分区 + 分区内排序”排队，不使用用户点击勾选的先后顺序。
    final selectedGroups = <int, List<Word>>{};
    for (final word in _allWords) {
      if (_selectedWordIds.contains(word.id)) {
        selectedGroups.putIfAbsent(word.difficulty, () => []).add(word);
      }
    }
    final selectedLevels = selectedGroups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final selectionSorter = HomeWordSorter(
      field: _sortField,
      directions: _sortDirections,
      query: '',
    );
    final selfTestWords = List<Word>.unmodifiable([
      for (final level in selectedLevels)
        ...selectionSorter.filterAndSort(selectedGroups[level]!),
    ]);
    final learningWords = selfTestWords.isNotEmpty
        ? selfTestWords
        : visibleWordSnapshot;
    final targetCount = learningWords.length;
    // 回调与当前显示共用这份模块值，切换后的首帧不会调用上一种玩法。
    final libraryModule = _libraryModule;
    final hasResume = libraryModule == ReviewModule.listening
        ? _settings.listeningPlayback.hasWords
        : _resumableSessions.containsKey(libraryModule);
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
      backgroundColor: AppTokens.of(context).page,
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
        // 导出运行日志：直接弹系统保存框，把单日日志拷到用户选的位置。
        onExportLog: () => unawaited(_exportLog()),
      ),
      // SafeArea 只避让顶部状态栏与刘海；底部不避让，避免在屏幕底部留出
      // 一块固定色块。手势导航区的呼吸空间由各内容区域自行留 padding。
      body: PopScope<void>(
        // 词库展开时，系统返回手势先执行“收起词库”；收起后才允许离开首页。
        canPop: !_wordLibraryExpanded,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !_wordLibraryExpanded) return;
          setState(() => _wordLibraryExpanded = false);
        },
        child: SafeArea(
          bottom: false,
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
                  clock: widget.clock,
                  wordCount: _allWords.length,
                  dailyGoal: _settings.dailyGoal,
                  reviewModeDailyGoal: reviewModeDailyGoal,
                  reviewCount: _reviewCount,
                  // 四张卡片的三态进度：待完成 / 进行中 / 已完成。
                  reviewModuleStates: _reviewModuleStates,
                  // 回刷序号：数字一变，趋势曲线与打卡日历就重查数据库。
                  refreshToken: _dashboardRefreshToken,
                  // 仪表盘那两块统计走同一个会话库口子：正式 App 用原生库，
                  // 测试注入内存库后曲线与日历看到的是同一份数据。
                  sessionStore: _sessionStore,
                  onMenuPressed: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                  // 四个入口共用同一个方法，具体开哪一局由 ReviewFlow 判断。
                  onOpenModule: (module) =>
                      unawaited(_openReviewModule(module)),
                  // 「开始复习」标题的临时入口：只在 debug 构建里可点，跳到组件演示页（demo）；
                  // release 包里传 null，使这块标题恢复成纯文字、点不动，避免误触正式功能之外的内容。
                  onStartReviewTap: kDebugMode
                      ? () => unawaited(_openDemoPage())
                      : null,
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
                      _selectedWordIds.clear();
                      _swipedWord = null;
                    }),
                  ),
                  selectionBar: _selectMode
                      ? WordSelectionBar(
                          selectedCount: _selectedWordIds.length,
                          onSelectAll: () => setState(
                            () => _selectedWordIds.addAll(
                              visibleWords
                                  .map((word) => word.id)
                                  .whereType<int>(),
                            ),
                          ),
                          onInvertSelection: () => setState(() {
                            for (final word in visibleWords) {
                              if (!_selectedWordIds.remove(word.id) &&
                                  word.id != null) {
                                _selectedWordIds.add(word.id!);
                              }
                            }
                          }),
                        )
                      : const SizedBox.shrink(),
                  listContent: ColoredBox(
                    color: tokens.card,
                    child: DecoratedBox(
                      key: const Key('word-list'),
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: tokens.border,
                            width: AppStroke.thin,
                          ),
                        ),
                      ),
                      child: _buildListContent(
                        shownSections,
                        visibleWords.isNotEmpty,
                      ),
                    ),
                  ),
                  learningBar: WordLibraryLearningBar(
                    listeningCount: targetCount,
                    // 自测的「可选词数」只算勾选的单词：没勾选就是 0，
                    // 于是被选词下限挡住、开始按钮保持禁用。这是有意为之——
                    // 自测必须先明确圈定要测的词，不能悄悄用整库开局。
                    selectedCount: selfTestWords.length,
                    selectedModule: libraryModule,
                    hasResume: hasResume,
                    busy: _learningActionBusy,
                    onModuleChanged: (module) =>
                        setState(() => _libraryModule = module),
                    onStart: () => unawaited(
                      // 随身听沿用「勾选了用勾选、没勾选用全部可见单词」；
                      // 四个自测模块则只认勾选，没勾选不开局。
                      libraryModule == ReviewModule.listening
                          ? _startListening(learningWords)
                          : _startSelfTest(libraryModule, selfTestWords),
                    ),
                    onContinue: () => unawaited(
                      libraryModule == ReviewModule.listening
                          ? _continueListening()
                          : _continueSelfTest(libraryModule),
                    ),
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
  static const double height = HomeLayout.sectionHeaderHeight;

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
    final textTheme = Theme.of(context).textTheme;
    // InkWell 提供整行点击反馈。
    return InkWell(
      // key 便于测试点击具体分组头。
      key: Key('section-${section.key}'),
      onTap: onTap,
      child: Container(
        // 34 高浅底与底部分隔线。
        height: HomeLayout.sectionHeaderHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pBase),
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
                  width: HomeLayout.sectionCheckboxSize,
                  height: HomeLayout.sectionCheckboxSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isAllSelected ? AppTokens.primary : tokens.card,
                    border: Border.all(
                      color: isAllSelected ? AppTokens.primary : tokens.check,
                      width: AppStroke.bold,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                  ),
                  child: isAllSelected
                      ? const Icon(
                          AppGlyph.selected,
                          color: Colors.white,
                          size: AppIcon.i14,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: AppSpace.p2),
            ],
            // 分组名称。
            Text(
              section.name,
              style: textTheme.fs6Semibold.copyWith(color: tokens.textMedium),
            ),
            // 撑开中间空间。
            const Spacer(),
            // 区块内单词数量。
            Text(
              '${section.words.length} 词',
              style: textTheme.fs6.copyWith(color: tokens.muted),
            ),
            // 数量与箭头间距。
            const SizedBox(width: AppSpace.p2),
            // 折叠箭头：折叠 0 度，展开旋转 90 度。
            AnimatedRotation(
              turns: isCollapsed ? 0 : 0.25,
              duration: const Duration(milliseconds: AppDuration.ms160),
              child: Icon(
                AppGlyph.expandRow,
                color: tokens.muted,
                size: AppIcon.i14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
