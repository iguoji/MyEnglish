// dart:async 提供 Timer，用于每秒倒数；也提供 Future.delayed 做“一组完成后停顿”。
import 'dart:async';
// dart:math 提供 sin/pi（抖动与呼吸动画）与 Random（确定性出题，保证续玩时棋盘一致）。
import 'dart:math';
// material.dart 提供全屏页面、进度条、卡片与对话框。
import 'package:flutter/material.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入全局设计令牌（颜色变量，随亮色/深色主题自动切换）。
import '../../common/theme.dart';
// 引入单词数据模型，首页会把当天固定词单传进来。
import '../../models/word.dart';
// 引入可恢复的学习会话模型（progress 的 JSON 载体）。
import '../../models/learning_session.dart';
// 引入全局设置 Store，读取与修改词义连连倒计时。
import '../../store/settings.dart';
// 引入学习会话 Store 与持久化门面，进度冻结/续玩都走它。
import '../../store/learning_session.dart';
// 引入集中管理的页面布局尺寸。
import 'widgets/meaning_match_layout.dart';

///
/// Tabler 成功绿（`--tblr-success`），用于连线、已连卡片与结算页“完成词汇”。
///
/// @var Color
///
const Color _kSuccess = Color(0xFF2FB344);

///
/// Tabler 橙色（`--tblr-orange`），用于结算页“最高连对”。
///
/// @var Color
///
const Color _kOrange = Color(0xFFF76707);

///
/// 补充稿 `--spring-ease: cubic-bezier(0.16, 1, 0.3, 1)` 的等价缓动曲线。
///
/// 生活化解释：这是一条“先冲得很快、临到终点急刹车”的运动曲线，
/// 卡片放大、缩小、变淡都用它，动作看起来才有弹性而不是匀速拖拽。
///
/// @var Cubic
///
const Cubic _kSpringEase = Cubic(0.16, 1, 0.3, 1);

///
/// 状态底色的兑色比例：主色按这个比例兑进卡片底色。
///
/// 生活化解释：相当于往一整桶白漆里滴 6% 的蓝色，得到补充稿里 #f0f7ff 那种
/// “乍看还是白的，细看有点蓝”的淡底。写成比例而不是写死颜色，深色主题下
/// 兑出来的就是“黑里透蓝”，不会突然冒出一块刺眼的白。
///
/// @var double
///
const double _kStateBackgroundAlpha = 0.06;

///
/// 连对卡片描边的兑色比例（补充稿 `.is-matched { border-color: #bbf7d0 }`）。
///
/// @var double
///
const double _kMatchedBorderAlpha = 0.35;

///
/// 连错卡片描边的兑色比例（补充稿 `.is-error { border-color: #fca5a5 }`）。
///
/// @var double
///
const double _kErrorBorderAlpha = 0.45;

///
/// 连错抖动的旋转关键帧倍数，对应补充稿 `errorJolt` 的六个时间点。
///
/// 补充稿只在 20% 与 40% 两帧写了 `rotate(∓0.5deg)`，其余帧不旋转，
/// 因此这里是 [0, -1, 1, 0, 0, 0]，再乘以 shakeRotationDegrees 得到实际角度。
///
/// @var `List<double>`
///
const List<double> _kShakeRotationFrames = <double>[0, -1, 1, 0, 0, 0];

///
/// 棋盘上的一对候选：左侧英文拼写 + 右侧中文含义。
///
/// 生活化解释：相当于连连看里“一个词”和它的“一张释义卡片”，左右各放一边等待连。
///
class MatchPair {
  ///
  /// 创建一对候选。
  ///
  /// @param  int?  wordId 单词主键，仅用于日志与去重参考。
  /// @param  String  spelling 左侧显示的英文单词（如 apple）。
  /// @param  String  definition 右侧显示的中文含义（从单词多条含义中随机挑的一条）。
  ///
  const MatchPair({
    required this.wordId,
    required this.spelling,
    required this.definition,
  });

  ///
  /// 单词主键。
  ///
  /// @var int?
  ///
  final int? wordId;

  ///
  /// 左侧英文拼写。
  ///
  /// @var String
  ///
  final String spelling;

  ///
  /// 右侧中文含义。
  ///
  /// @var String
  ///
  final String definition;
}

///
/// 首页仪表盘需要展示的“词义连连”进度。
///
/// 词义连连的错误不写复习记录，所以首页百分比不能像听音辨义那样读
/// reviewCountsByModule，而必须来自本局保存的会话状态。该类把“总配对数 / 已匹配数 /
/// 是否完成”打包，供首页卡片直接展示百分比与“已完成”徽章。
///
class MeaningMatchProgress {
  ///
  /// 创建进度快照。
  ///
  /// @param  int  totalPairs 本局固定总配对数（= 组数 × 5）。
  /// @param  int  bestMatchedPairs 目前已匹配的对数（单调不减，即“本局最高进度”）。
  /// @param  bool  completed 本局是否已经全部连完。
  ///
  const MeaningMatchProgress({
    required this.totalPairs,
    required this.bestMatchedPairs,
    required this.completed,
  });

  ///
  /// 本局固定总配对数。
  ///
  /// @var int
  ///
  final int totalPairs;

  ///
  /// 目前已匹配的对数（即首页百分比的分子）。
  ///
  /// @var int
  ///
  final int bestMatchedPairs;

  ///
  /// 本局是否已完成（完成后首页显示 100%「已完成」，与听音辨义口径一致）。
  ///
  /// @var bool
  ///
  final bool completed;

  ///
  /// 完成度比例（0～1），作为首页进度条填充。
  ///
  /// @return double 已匹配对数 / 总配对数，除零时归 0。
  ///
  double get ratio =>
      totalPairs > 0 ? (bestMatchedPairs / totalPairs).clamp(0.0, 1.0) : 0.0;
}

///
/// 卡片所在的一侧：左列（单词）或右列（含义）。
///
enum _CardSide {
  ///
  /// 左侧单词列。
  ///
  left,

  ///
  /// 右侧含义列。
  ///
  right,
}

///
/// 一张候选卡当前的视觉状态，决定边框色、底色与文字色。
///
/// 生活化解释：相当于 HTML 原型里 `.pair-btn` 上挂的那几个 class
/// （默认 / selected / matched / error），这里用枚举一次表达清楚。
///
enum _CardVisualState {
  ///
  /// 默认未选中。
  ///
  idle,

  ///
  /// 已点选、等待与另一侧配对（原型 `.selected`）。
  ///
  selected,

  ///
  /// 已成功连上（原型 `.matched`）。
  ///
  matched,

  ///
  /// 刚刚连错，正在红框抖动（原型 `.error`）。
  ///
  error,
}

///
/// 词义连连页面。
///
/// 玩法：左右两列各有 5 张卡片，左列是英文单词、右列是它的一条中文含义（随机选取）；
/// 点一张左卡再点一张右卡，若二者对应即连成绿线，全部连完进入下一组；连错则红框抖动。
/// 顶部有倒计时，点一下 +30 秒并同步写入全局设置；进度在离场时冻结，仅当天可续玩。
///
/// 界面复刻 `ui/词义连连.html` 原型，只有「左上返回图标」与「中间数字进度」
/// 沿用听音辨义的样式，让两个复习模块看起来是同一套产品。
///
class MeaningMatchPage extends StatefulWidget {
  ///
  /// 创建词义连连页面。
  ///
  /// @param  `List<Word>`  words 当天公共复习词单（固定顺序，出题与续玩基准）。
  /// @param  String  title 页面顶栏显示的模块名称，如“词义连连”。
  /// @param  LearningSession?  initialSession 需要恢复的历史会话；null 表示开始一轮新游戏。
  /// @param  LearningSessionStore?  sessionStore 可替换的学习会话 Store（测试注入内存实现）。
  /// @param  SettingsStore?  settings 可替换的全局设置 Store（测试注入内存实现）。
  ///
  /// @param  Key?  key
  ///
  const MeaningMatchPage({
    required this.words,
    required this.title,
    this.initialSession,
    this.sessionStore,
    this.settings,
    super.key,
  }) : assert(words.length > 0, '词义连连至少需要一个单词');

  ///
  /// 首页按“已勾选优先，否则当前可见”规则传入的学习列表。
  ///
  /// @var `List<Word>`
  ///
  final List<Word> words;

  ///
  /// 当前复习模块名称；顶栏中央改为显示数字进度，此处仅作语义标识与埋点。
  ///
  /// @var String
  ///
  final String title;

  ///
  /// 从首页“继续”入口传入的历史会话；null 表示开始一轮新游戏。
  ///
  /// @var LearningSession?
  ///
  final LearningSession? initialSession;

  ///
  /// 学习会话存储；正式环境使用 SQLite，测试可注入内存实现。
  ///
  /// @var LearningSessionStore?
  ///
  final LearningSessionStore? sessionStore;

  ///
  /// 全局设置 Store；正式环境使用 Android 持久化，测试可注入内存实现。
  ///
  /// @var SettingsStore?
  ///
  final SettingsStore? settings;

  ///
  /// 创建词义连连页面状态。
  ///
  /// @return `State<MeaningMatchPage>` 管理棋盘、倒计时与匹配流程的状态对象。
  ///
  @override
  State<MeaningMatchPage> createState() => _MeaningMatchPageState();
}

///
/// 管理词义连连的棋盘、倒计时与匹配状态。
///
/// 这里同时驱动三条动画：连线生长、整块棋盘淡入、倒计时最后 10 秒呼吸，
/// 因此使用可挂多个 Ticker 的 TickerProviderStateMixin（复数版）。
///
class _MeaningMatchPageState extends State<MeaningMatchPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  ///
  /// 确定性随机种子：同一份词单 + 同一种子，出题结果完全一致，
  /// 这样离场再回来时“续玩”能还原完全一样的棋盘（含右列顺序）。
  ///
  /// @var int
  ///
  static const int _seed = 0x4D65616E; // 'Mean'

  ///
  /// 所有分组（每组 5 对），确定性生成后不会再变。
  ///
  /// @var `List<List<MatchPair>>`
  ///
  late final List<List<MatchPair>> _groups;

  ///
  /// 每组右列的真实配对顺序（排列），长度固定 5；右列第 k 张显示 pairs[order[k]]。
  ///
  /// @var `List<List<int>>`
  ///
  late final List<List<int>> _rightOrders;

  ///
  /// 本局总配对数 = 组数 × 5。
  ///
  /// @var int
  ///
  late final int _totalPairs;

  ///
  /// 当前所在分组下标（0 起）。
  ///
  /// @var int
  ///
  int _groupIndex = 0;

  ///
  /// 当前组已经成功连上的“左卡下标”集合。
  ///
  /// @var `Set<int>`
  ///
  final Set<int> _matchedLeft = <int>{};

  ///
  /// 当前组已经成功连上的“右卡位置”集合。
  ///
  /// @var `Set<int>`
  ///
  final Set<int> _matchedRight = <int>{};

  ///
  /// 已连成的连线（左卡下标, 右卡位置），用于绘制贝塞尔曲线。
  ///
  /// @var `List<(int, int)>`
  ///
  final List<(int, int)> _matchedConnections = <(int, int)>[];

  ///
  /// 正在播放“连线动画”的那条连线；动画结束后置空。
  ///
  /// @var `(int, int)?`
  ///
  (int, int)? _activeConnection;

  ///
  /// 当前选中的卡片：哪一侧、哪个下标；非 null 表示等待再点另一侧来配对。
  ///
  /// @var `_CardSide?`
  ///
  _CardSide? _selectedSide;

  ///
  /// 当前选中的卡片下标（-1 表示无）。
  ///
  /// @var int
  ///
  int _selectedIndex = -1;

  ///
  /// 剩余毫秒数；归零即超时。
  ///
  /// @var int
  ///
  int _remainingMs = 0;

  ///
  /// 本局的总时长毫秒数，即顶部时间进度条的分母（原型 `TOTAL_TIME`）。
  ///
  /// 点击倒计时 +30 秒时分子分母一起加，进度条因此只会变长不会溢出。
  ///
  /// @var int
  ///
  int _totalMs = 0;

  ///
  /// 当前连续配对成功的数量（连错清零）。
  ///
  /// @var int
  ///
  int _streak = 0;

  ///
  /// 本局连对最高纪录，用于结算页展示。
  ///
  /// @var int
  ///
  int _bestStreak = 0;

  ///
  /// 本局连错次数，用于结算页展示（不影响单词难度，也不写记录）。
  ///
  /// @var int
  ///
  int _errors = 0;

  ///
  /// 本局是否全部连完。
  ///
  /// @var bool
  ///
  bool _completed = false;

  ///
  /// 本局是否因时间耗尽而结束。
  ///
  /// @var bool
  ///
  bool _timedOut = false;

  ///
  /// 倒计时计时器；页面不在前台时取消，回到前台再启动。
  ///
  /// @var Timer?
  ///
  Timer? _timer;

  ///
  /// 连错反馈期间的输入锁（补充稿的 `isProcessing`）。
  ///
  /// 生活化解释：连错后两张卡要红着脸抖 0.4 秒，这段时间里如果还能点别的卡，
  /// 红色会被下一次点击立刻打断，用户根本看不清自己错在哪。上了锁就必须
  /// 让这 0.4 秒播完，反馈才算真正“看得见”。
  ///
  /// @var bool
  ///
  bool _inputLocked = false;

  ///
  /// 连错输入锁的解锁定时器；页面销毁或重开时必须取消，避免定时器泄漏。
  ///
  /// @var Timer?
  ///
  Timer? _unlockTimer;

  ///
  /// 连线绘制动画控制器：每次成功配对都从 0 重新播到 1。
  ///
  /// @var AnimationController
  ///
  late final AnimationController _connectController;

  ///
  /// 整块棋盘的淡入控制器：切到下一组或重开时从 0 播到 1（原型 `.fade-switch`）。
  ///
  /// @var AnimationController
  ///
  late final AnimationController _fadeController;

  ///
  /// 倒计时呼吸控制器：剩余不足 10 秒时循环播放（原型 `.pulse-danger`）。
  ///
  /// @var AnimationController
  ///
  late final AnimationController _pulseController;

  ///
  /// 棋盘容器全局键，用于把卡片坐标换算成相对棋盘的本地坐标。
  ///
  /// @var GlobalKey
  ///
  final GlobalKey _boardKey = GlobalKey();

  ///
  /// 左列 5 张卡片各自的全局键，用于取锚点坐标画连线。
  ///
  /// 只用来量“这张卡片画在屏幕的哪个位置”，不承担任何状态调用职责——
  /// 卡片的选中/连对/连错都由下面的下标字段驱动，父级传属性给子卡即可。
  ///
  /// @var `List<GlobalKey>`
  ///
  final List<GlobalKey> _leftKeys = List<GlobalKey>.generate(
    5,
    (_) => GlobalKey(),
  );

  ///
  /// 右列 5 张卡片各自的全局键。
  ///
  /// @var `List<GlobalKey>`
  ///
  final List<GlobalKey> _rightKeys = List<GlobalKey>.generate(
    5,
    (_) => GlobalKey(),
  );

  ///
  /// 正在播放连错反馈的左卡下标；-1 表示当前没有连错。
  ///
  /// @var int
  ///
  int _errorLeftIndex = -1;

  ///
  /// 正在播放连错反馈的右卡位置；-1 表示当前没有连错。
  ///
  /// @var int
  ///
  int _errorRightIndex = -1;

  ///
  /// 正式页面复用全局设置实例，测试可注入内存实现。
  ///
  /// 必须是 late final 字段而不是 getter：写成 getter 时每次读取都会新建一个
  /// 内存 Store，导致“+30 秒”永远从默认值重新累加。
  ///
  /// @var SettingsStore
  ///
  late final SettingsStore _settings =
      widget.settings ?? SettingsStore.inMemory();

  ///
  /// 正式页面复用 SQLite 单例，Widget 测试可传入内存 Store。
  ///
  /// @return LearningSessionStore 当前页面实际使用的学习会话 Store。
  ///
  LearningSessionStore get _sessionStore =>
      widget.sessionStore ?? LocalLearningSessionStore.instance;

  ///
  /// 当前页面的会话持久化入口（已绑定词义连连类型）。
  ///
  /// @return LearningSessionPersistence 写/删本模块进度快照的门面。
  ///
  LearningSessionPersistence get _sessionPersistence =>
      LearningSessionPersistence(
        store: _sessionStore,
        type: LearningSessionType.meaningMatch,
      );

  ///
  /// 当前分组的配对列表。
  ///
  /// @return `List<MatchPair>` 当前棋盘左列（也是右列数据来源）的 5 对候选。
  ///
  List<MatchPair> get _currentPairs => _groups[_groupIndex];

  ///
  /// 当前分组的右列顺序。
  ///
  /// @return `List<int>` 右列第 k 张对应左列下标 order[k]。
  ///
  List<int> get _currentOrder => _rightOrders[_groupIndex];

  ///
  /// 已匹配总对数 = 已完成整组数 × 5 + 当前组已连数（单调不减）。
  ///
  /// @return int 首页百分比的分子。
  ///
  int get _matchedPairs => _groupIndex * 5 + _matchedLeft.length;

  ///
  /// 是否展示结算页（完成或超时后）。
  ///
  /// @return bool 完成或超时都切到结算页。
  ///
  bool get _showSummary => _completed || _timedOut;

  ///
  /// 剩余秒数（向上取整，与倒计时文本口径一致）。
  ///
  /// @return int 顶栏显示的剩余秒。
  ///
  int get _remainingSeconds => (_remainingMs / 1000).ceil();

  ///
  /// 倒计时是否进入“危险区”（剩余不足 10 秒）。
  ///
  /// 原型在这一刻把倒计时文字与进度条同时改成红色，并让文字开始呼吸。
  ///
  /// @return bool true 表示需要红色与呼吸动画。
  ///
  bool get _isTimeDanger =>
      !_showSummary &&
      _remainingMs > 0 &&
      _remainingSeconds <= MeaningMatchLayout.countdownDangerSeconds;

  ///
  /// 顶部时间进度条的填充比例（原型 `timeLeft / TOTAL_TIME`）。
  ///
  /// @return double 剩余时间占本局总时长的比例，钳制在 0～1。
  ///
  double get _timeRatio =>
      _totalMs > 0 ? (_remainingMs / _totalMs).clamp(0.0, 1.0) : 0.0;

  ///
  /// 初始化页面：先确定性出题，再决定是否从会话续玩，最后启动倒计时。
  ///
  /// @return void
  ///
  @override
  void initState() {
    super.initState();
    // 监听前后台变化：退到后台暂停计时，回到前台再续，等价于“返回即暂停”。
    WidgetsBinding.instance.addObserver(this);
    // 连线动画控制器：每次成功连线都用它从 0 播到 1。
    _connectController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: MeaningMatchLayout.connectDurationMs),
    );
    // 棋盘淡入控制器：初值直接给 1（首帧就是完整不透明），只在换组/重开时重播。
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: MeaningMatchLayout.fadeDurationMs),
      value: 1,
    );
    // 倒计时呼吸控制器：只有剩余不足 10 秒时才 repeat，平时完全静止。
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: MeaningMatchLayout.pulseDurationMs),
    );
    // 第一步：确定性生成全部棋盘（与词单顺序、种子都固定）。
    _buildGroups();
    // 第二步：若有可续玩的历史会话则恢复，否则开启新一局。
    _restoreOrStart();
    // 第三步：未结束则启动每秒倒计时，并按剩余时间决定要不要呼吸。
    if (!_showSummary) _startTimer();
    _syncPulse();
    // 首帧结束后强制重绘一次：连线要等卡片完成布局才能拿到锚点坐标，
    // 否则“续玩”恢复的已连线在第一帧会因为坐标为空而画不出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _matchedConnections.isNotEmpty) setState(() {});
    });
  }

  ///
  /// 按固定种子与词单顺序生成所有分组（每组 5 对）。
  ///
  /// 末组不足 5 个时，从前面单词里随机补齐（同一组内不重复，避免左右出现
  /// 同一单词造成歧义）；每个单词的含义从其“含义列表”中随机挑一条。
  ///
  /// @return void
  ///
  void _buildGroups() {
    // 只保留至少含一条释义的单词，没有释义的单词无法出题，直接跳过。
    final playable = widget.words
        .where((word) => word.meanings.any((m) => m.definitions.isNotEmpty))
        .toList(growable: false);
    // 极端情况下词单全无释义，退化为用原始词单，保证页面不空（不会崩溃）。
    final source = playable.isNotEmpty ? playable : widget.words;

    // 固定种子保证“续玩”时重新生成完全相同的棋盘与右列顺序。
    final rnd = Random(_seed);
    final groups = <List<MatchPair>>[];
    final rightOrders = <List<int>>[];

    // 每 5 个词切一组；最后一组不足 5 个时补满。
    for (var i = 0; i < source.length; i += 5) {
      // chunk 收集本组要用的单词（原始顺序）。
      final chunk = <Word>[
        for (var j = i; j < min(i + 5, source.length); j += 1) source[j],
      ];
      // 末组补满：从打乱后的词单里挑尚未在本组出现的词，避免同组左右重复。
      if (chunk.length < 5) {
        final pool = List<Word>.from(source)..shuffle(rnd);
        var p = 0;
        while (chunk.length < 5 && p < pool.length) {
          final candidate = pool[p];
          p += 1;
          if (!chunk.contains(candidate)) chunk.add(candidate);
        }
        // 词单数本身就不足 5 时允许重复兜底，保证每组仍是 5 张。
        while (chunk.length < 5) {
          chunk.add(source[rnd.nextInt(source.length)]);
        }
      }

      // 为组内每个单词随机挑一条含义，组成 5 对候选。
      final pairs = <MatchPair>[
        for (final word in chunk)
          MatchPair(
            wordId: word.id,
            spelling: word.spelling,
            definition: _pickDefinition(word, rnd),
          ),
      ];
      groups.add(List<MatchPair>.unmodifiable(pairs));

      // 右列顺序：把 0..4 洗牌，右列第 k 张显示 pairs[order[k]]。
      final order = [0, 1, 2, 3, 4]..shuffle(rnd);
      rightOrders.add(List<int>.unmodifiable(order));
    }

    _groups = List<List<MatchPair>>.unmodifiable(groups);
    _rightOrders = List<List<int>>.unmodifiable(rightOrders);
    // 总局数 = 组数 × 5（每组固定 5 行）。
    _totalPairs = _groups.length * 5;
  }

  ///
  /// 从单词的含义列表中随机挑一条中文释义。
  ///
  /// @param  Word  word 当前单词。
  /// @param  Random  rnd 固定种子的随机源。
  /// @return String 选中的一条释义文本。
  ///
  String _pickDefinition(Word word, Random rnd) {
    // 只保留有释义的词性与条目，避免选中空释义。
    final meanings = word.meanings
        .where((meaning) => meaning.definitions.isNotEmpty)
        .toList(growable: false);
    // 理论上 buildGroups 已过滤，这里仍兜底：没有可用释义就返回空串。
    if (meanings.isEmpty) return '';
    final meaning = meanings[rnd.nextInt(meanings.length)];
    return meaning.definitions[rnd.nextInt(meaning.definitions.length)];
  }

  ///
  /// 从会话恢复或开启新一局。
  ///
  /// 恢复条件：会话未标记完成，且剩余时间 > 0（超时或已完成的历史都视为新一局，
  /// 因为超时后时间归零无法继续、完成后按“完成后重置”也应重开）。
  ///
  /// @return void
  ///
  void _restoreOrStart() {
    final session = widget.initialSession;
    // 直接把条件写进 if：Dart 会在此分支内把 session 收窄为非空，免去 `!`。
    // 恢复条件：会话未标记完成，且剩余时间 > 0（超时/已完成的历史都视为新一局）。
    if (session != null &&
        session.type == LearningSessionType.meaningMatch &&
        session.state['completed'] != true &&
        readLearningSessionInt(session.state['remainingMs'], fallback: 0) > 0) {
      final state = session.state;
      // 恢复分组下标（夹在合法范围内，防止旧快照越界）。
      _groupIndex = readLearningSessionInt(
        state['groupIndex'],
        fallback: 0,
      ).clamp(0, _groups.length - 1);
      // 恢复已连上的左右下标（保存在内存的 Set 里，绘制连线时用）。
      _matchedLeft.addAll(_readIntList(state['matchedLeft']));
      _matchedRight.addAll(_readIntList(state['matchedRight']));
      // 由左右下标并行还原连线列表，供贝塞尔曲线绘制。
      final lefts = _readIntList(state['matchedLeft']);
      final rights = _readIntList(state['matchedRight']);
      for (var k = 0; k < lefts.length && k < rights.length; k += 1) {
        _matchedConnections.add((lefts[k], rights[k]));
      }
      // 恢复剩余时间与统计。
      _remainingMs = readLearningSessionInt(state['remainingMs'], fallback: 0);
      _bestStreak = max(
        0,
        readLearningSessionInt(state['bestStreak'], fallback: 0),
      );
      _errors = max(0, readLearningSessionInt(state['errors'], fallback: 0));
      // 恢复进度条分母；旧快照没存过 totalMs 时，用“剩余时间”和“全局设置”里较大的一个兜底。
      _totalMs = readLearningSessionInt(state['totalMs'], fallback: 0);
      if (_totalMs < _remainingMs) {
        _totalMs = max(_remainingMs, _settings.meaningMatchDuration * 1000);
      }
      // 已完成/超时标志保持初始 false（能走到这里说明都未触发）。
    } else {
      // 新一局：剩余时间直接取自全局设置（秒 × 1000），进度条分母同值。
      _remainingMs = _settings.meaningMatchDuration * 1000;
      _totalMs = _remainingMs;
    }
  }

  ///
  /// 从 JSON 状态读取一个整数列表（越界或坏值统一忽略）。
  ///
  /// @param  Object?  value JSON 状态中的动态字段。
  /// @return `List<int>` 经过范围校验的下标列表。
  ///
  List<int> _readIntList(Object? value) {
    if (value is! List) return const <int>[];
    final result = <int>[];
    for (final item in value) {
      if (item is num) {
        final v = item.toInt();
        // 下标必须落在当前组 0..4 内，超出说明快照损坏，丢弃该条。
        if (v >= 0 && v < 5) result.add(v);
      }
    }
    return result;
  }

  ///
  /// 启动每秒倒数；归零即触发超时结算。
  ///
  /// @return void
  ///
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // 已在别处停掉计时器则不再继续扣时间。
      if (_remainingMs <= 0) return;
      setState(() => _remainingMs -= 1000);
      // 每一秒都检查是否跨过 10 秒红线，跨过就开始/停止呼吸动画。
      _syncPulse();
      if (_remainingMs <= 0) {
        _onTimeout();
      }
    });
  }

  ///
  /// 按当前剩余时间开启或停止倒计时呼吸动画。
  ///
  /// 生活化解释：只有最后 10 秒才让数字“一鼓一鼓”地跳，平时完全不动，
  /// 既省电也避免测试里出现永不停止的动画。
  ///
  /// @return void
  ///
  void _syncPulse() {
    if (_isTimeDanger) {
      // 已经在播就不要重复 repeat，否则动画会从头跳一下。
      if (!_pulseController.isAnimating) _pulseController.repeat();
      return;
    }
    // 离开危险区：停表并复位到“不放大、不透明”的初始帧。
    if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  ///
  /// 时间耗尽：停止计时、标记超时并保存快照（首页据此显示“本局最高进度”）。
  ///
  /// @return void
  ///
  void _onTimeout() {
    if (_completed) return;
    _timer?.cancel();
    setState(() => _timedOut = true);
    // 结算页不需要呼吸动画。
    _syncPulse();
    unawaited(_persist());
  }

  ///
  /// 点击卡片：管理选中态并尝试配对。
  ///
  /// [side] 被点的卡片在左列还是右列；[index] 在各自列中的下标。
  ///
  /// @return void
  ///
  void _onCardTap(_CardSide side, int index) {
    // 结算页、连错反馈播放期间或已匹配的卡片都不再响应点击。
    if (_showSummary || _inputLocked) return;
    if (side == _CardSide.left && _matchedLeft.contains(index)) return;
    if (side == _CardSide.right && _matchedRight.contains(index)) return;

    // 还没选中任何卡：把这张设为选中。
    if (_selectedSide == null) {
      setState(() {
        _selectedSide = side;
        _selectedIndex = index;
      });
      return;
    }
    // 点的还是同一侧：再点一次同一张则取消选中，点别的则改选（与原型一致）。
    if (_selectedSide == side) {
      setState(() {
        if (_selectedIndex == index) {
          _selectedSide = null;
          _selectedIndex = -1;
        } else {
          _selectedIndex = index;
        }
      });
      return;
    }
    // 点的是另一侧：尝试把“已选的那张”与“这张”配对。
    final leftIndex = side == _CardSide.left ? index : _selectedIndex;
    final rightIndex = side == _CardSide.left ? _selectedIndex : index;
    _attemptMatch(leftIndex, rightIndex);
  }

  ///
  /// 判定一次配对是否成功。
  ///
  /// [leftIndex] 左列下标；[rightIndex] 右列位置（0..4）。
  /// 成功条件：右列该位置对应的左卡下标，正好等于 leftIndex。
  ///
  /// @return void
  ///
  void _attemptMatch(int leftIndex, int rightIndex) {
    // 右列第 rightIndex 张显示的是 pairs[_currentOrder[rightIndex]]。
    final correctLeft = _currentOrder[rightIndex];
    // 一次性清空选中态并（若成功）记录连线与计数。
    setState(() {
      _selectedSide = null;
      _selectedIndex = -1;
      if (correctLeft == leftIndex) {
        // 配对成功：记录连线、刷新计数并播放连线动画。
        _matchedLeft.add(leftIndex);
        _matchedRight.add(rightIndex);
        _matchedConnections.add((leftIndex, rightIndex));
        _activeConnection = (leftIndex, rightIndex);
        _connectController.reset();
        _connectController.forward();
        _streak += 1;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        // 配对失败：连错数 +1、连对清零（不影响难度/记录）。
        _errors += 1;
        _streak = 0;
        // 记下是哪两张卡连错，两张子卡看到属性变化就会自己红框抖动。
        // 以前这里改用 GlobalKey 去调子卡的 shake()，但那个键实际挂在卡片内层的
        // 普通容器上，currentState 永远取不到子卡状态，连错反馈从来没真正播放过。
        _errorLeftIndex = leftIndex;
        _errorRightIndex = rightIndex;
      }
    });
    unawaited(_persist());
    if (correctLeft == leftIndex) {
      // 当前组 5 张全连完：进入下一组或整局完成。
      if (_matchedLeft.length >= 5) _onGroupComplete();
    } else {
      // 抖动播完之前锁住点击，保证这段红色反馈完整可见（补充稿 isProcessing）。
      _lockInputForShake();
    }
  }

  ///
  /// 锁住棋盘点击，等连错抖动播完再解锁并撤掉红色。
  ///
  /// @return void
  ///
  void _lockInputForShake() {
    // 输入锁本身不影响画面，不需要 setState。
    _inputLocked = true;
    _unlockTimer?.cancel();
    _unlockTimer = Timer(
      Duration(milliseconds: MeaningMatchLayout.shakeDurationMs),
      () {
        _inputLocked = false;
        // 抖动结束的同时收掉红色，两张卡回到默认态。
        if (!mounted) return;
        setState(() {
          _errorLeftIndex = -1;
          _errorRightIndex = -1;
        });
      },
    );
  }

  ///
  /// 当前组全部连完后的推进：还有下一组则停顿后切组，否则整局完成。
  ///
  /// @return void
  ///
  void _onGroupComplete() {
    if (_groupIndex + 1 < _groups.length) {
      // 停顿 groupAdvanceDelayMs 毫秒，让用户看清最后一条绿线再翻页。
      Timer(Duration(milliseconds: MeaningMatchLayout.groupAdvanceDelayMs), () {
        if (!mounted) return;
        setState(() {
          _groupIndex += 1;
          _matchedLeft.clear();
          _matchedRight.clear();
          _matchedConnections.clear();
          _activeConnection = null;
          _selectedSide = null;
          _selectedIndex = -1;
          // 换组后卡片内容全变了，上一组残留的连错红色必须一并清掉。
          _errorLeftIndex = -1;
          _errorRightIndex = -1;
        });
        // 新一组整块淡入上移，对应原型的 fade-switch。
        _fadeController.forward(from: 0);
        unawaited(_persist());
      });
    } else {
      // 最后一组也连完：整局完成，保留会话（首页显示 100%「已完成」）。
      setState(() => _completed = true);
      _syncPulse();
      unawaited(_persist());
    }
  }

  ///
  /// 再挑战一次：清掉本局所有状态，按全局设置重置倒计时，重新开局。
  ///
  /// @return void
  ///
  void _restart() {
    _timer?.cancel();
    // 上一局如果正好停在连错反馈中，这里要一并解锁，否则新一局点不动。
    _unlockTimer?.cancel();
    _inputLocked = false;
    setState(() {
      _groupIndex = 0;
      _matchedLeft.clear();
      _matchedRight.clear();
      _matchedConnections.clear();
      _activeConnection = null;
      _selectedSide = null;
      _selectedIndex = -1;
      // 上一局残留的连错红色不能带进新一局。
      _errorLeftIndex = -1;
      _errorRightIndex = -1;
      _completed = false;
      _timedOut = false;
      _remainingMs = _settings.meaningMatchDuration * 1000;
      // 进度条分母跟着重置，重开后时间条必然是满格。
      _totalMs = _remainingMs;
      _streak = 0;
      _bestStreak = 0;
      _errors = 0;
    });
    // 重开也走一次淡入，视觉上明确“换了一局”。
    _fadeController.forward(from: 0);
    _syncPulse();
    unawaited(_persist());
    _startTimer();
  }

  ///
  /// 点击右上角倒计时：本次剩余 +30 秒，并同步把全局设置倒计时 +30 秒。
  ///
  /// 全局设置里的倒计时也要 +30，使“下次进入”默认就多 30 秒。
  ///
  /// @return `Future<void>` 全局设置写入完成。
  ///
  Future<void> _addThirtySeconds() async {
    setState(() {
      _remainingMs += 30000;
      // 分子分母一起加，时间条不会因为加时而溢出到 100% 以上。
      _totalMs += 30000;
    });
    // 加完时间通常就脱离最后 10 秒，停掉呼吸动画。
    _syncPulse();
    try {
      await _settings.setMeaningMatchDuration(
        _settings.meaningMatchDuration + 30,
      );
    } catch (error) {
      // 全局设置写入失败只记录，不阻断游戏（当前剩余时间已 +30）。
      debugPrint('词义连连倒计时写入全局设置失败：$error');
    }
    unawaited(_persist());
  }

  ///
  /// 把当前进度写入 SQLite；页面交互先完成，持久化失败不阻断游戏。
  ///
  /// @return `Future<void>` 会话保存完成后的异步结果。
  ///
  Future<void> _persist() => _sessionPersistence.save(
    // 只保存主键，恢复时首页会用最新词库重新组装 Word。
    wordIds: widget.words.map((word) => word.id),
    // 词义连连不写复习记录，completed 时也保留会话供首页显示 100%。
    enabled: true,
    state: <String, Object?>{
      // 当前分组下标。
      'groupIndex': _groupIndex,
      // 已连上的左卡下标（与右列位置一一对应）。
      'matchedLeft': _matchedLeft.toList(growable: false),
      // 已连上的右卡位置。
      'matchedRight': _matchedRight.toList(growable: false),
      // 剩余毫秒，续玩时据此恢复倒计时。
      'remainingMs': _remainingMs,
      // 本局总时长毫秒，续玩时据此还原时间进度条比例。
      'totalMs': _totalMs,
      // 已匹配总对数（首页百分比分子）。
      'matchedPairs': _matchedPairs,
      // 本局总配对数（首页百分比分母）。
      'totalPairs': _totalPairs,
      // 是否已全部连完。
      'completed': _completed,
      // 是否超时结束。
      'timedOut': _timedOut,
      // 连对最高纪录，结算页展示用。
      'bestStreak': _bestStreak,
      // 连错次数，结算页展示用。
      'errors': _errors,
    },
  );

  ///
  /// App 前后台切换：退后台暂停计时并保存，回前台再恢复（等价于返回即暂停）。
  ///
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed 之外都视为“离开前台”，暂停倒计时避免后台偷偷扣时间。
    if (state == AppLifecycleState.resumed) {
      if (!_showSummary) _startTimer();
      _syncPulse();
      return;
    }
    _timer?.cancel();
    // 退到后台时停掉呼吸动画，避免无谓的重绘。
    if (_pulseController.isAnimating) _pulseController.stop();
    if (!_showSummary) unawaited(_persist());
  }

  ///
  /// 页面被移出导航栈（返回/退出）时立即冻结进度并停表。
  ///
  /// @return void
  ///
  @override
  void deactivate() {
    // 转场一开始就把计时器停掉，把主线程让给返回动画，避免卡顿。
    _timer?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    // 注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    // 停表并保存当前进度；completed/timedOut 也会在此落盘（首页据此显示状态）。
    _timer?.cancel();
    // 连错解锁定时器也要取消，避免页面销毁后回调仍在排队。
    _unlockTimer?.cancel();
    _connectController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    unawaited(_persist());
    super.dispose();
  }

  ///
  /// 构建词义连连页面。
  ///
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 游戏棋盘或结算页。
  ///
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.card,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏与时间进度条：返回键与数字进度沿用听音辨义，倒计时与时间条复刻原型。
            _buildHeader(tokens),
            // 结算页或棋盘二选一。
            if (_showSummary)
              Expanded(child: _buildSummary(tokens))
            else
              Expanded(child: _buildBoard(tokens)),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建顶栏与时间进度条。
  ///
  /// 左：返回键（与听音辨义完全相同的 34×34 画布 + 21 像素 Tabler 图标）；
  /// 中：已配对 / 总数（与听音辨义题号相同的 16 像素等宽数字）；
  /// 右：可点击的倒计时纯文本（点一下 +30 秒），最后 10 秒转红并呼吸。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 顶栏一行加下方时间进度条。
  ///
  Widget _buildHeader(AppTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MeaningMatchLayout.pageInset,
            MeaningMatchLayout.headerTop,
            MeaningMatchLayout.pageInset,
            0,
          ),
          // 用 Stack 而不是 Row：左侧返回键 34 像素、右侧倒计时约 50 像素宽度不等，
          // 若用 Row + Expanded，中间数字会被挤得偏左几像素；Stack 能保证它绝对居中。
          child: SizedBox(
            height: MeaningMatchLayout.headerButtonSize,
            child: Stack(
              children: [
                // 中间：已配对 / 总数，样式与听音辨义题号一致。
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$_matchedPairs / $_totalPairs',
                      key: const Key('meaning-match-progress-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: MeaningMatchLayout.headerProgressTextSize,
                        fontWeight: FontWeight.w600,
                        // 等宽数字让计数变化时视觉中心不抖动。
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // 左侧：返回键，34 像素点击画布直接贴齐页面边距。
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: MeaningMatchLayout.headerButtonSize,
                    height: MeaningMatchLayout.headerButtonSize,
                    child: InkWell(
                      key: const Key('close-meaning-match'),
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(
                        MeaningMatchLayout.headerButtonSize / 2,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          TablerIcons.chevronLeft,
                          size: MeaningMatchLayout.headerIconSize,
                          color: tokens.textMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                // 右侧：纯文本倒计时（原型没有图标），点一下 +30 秒。
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildCountdown(tokens),
                ),
              ],
            ),
          ),
        ),
        // 时间进度条：原型里它表示“剩余时间占比”，会随倒数一点点变短。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MeaningMatchLayout.pageInset,
            MeaningMatchLayout.progressTop,
            MeaningMatchLayout.pageInset,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              MeaningMatchLayout.progressRadius,
            ),
            child: LinearProgressIndicator(
              key: const Key('meaning-match-progress'),
              value: _timeRatio,
              minHeight: MeaningMatchLayout.progressHeight,
              backgroundColor: tokens.sub,
              // 最后 10 秒整条变红，与倒计时文字同步告警。
              color: _isTimeDanger ? AppTokens.danger : AppTokens.accent,
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建右上角可点击的倒计时文本。
  ///
  /// 平时是次要灰色；剩余不足 10 秒时转为危险红，并循环播放
  /// “放大到 1.06 倍、淡到 0.8 透明度再回来”的呼吸动画（原型 pulse-danger）。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 倒计时文本按钮。
  ///
  Widget _buildCountdown(AppTokens tokens) {
    final isDanger = _isTimeDanger;
    return InkWell(
      key: const Key('meaning-match-countdown'),
      // 结算页不再允许加时。
      onTap: _showSummary ? null : () => unawaited(_addThirtySeconds()),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            // sin 曲线让 0→0.5→1 的进度对应“原始 → 最大 → 原始”，与 CSS 关键帧一致。
            final wave = isDanger ? sin(_pulseController.value * pi) : 0.0;
            return Transform.scale(
              scale: 1 + (MeaningMatchLayout.pulseMaxScale - 1) * wave,
              child: Opacity(
                opacity: 1 - (1 - MeaningMatchLayout.pulseMinOpacity) * wave,
                child: child,
              ),
            );
          },
          child: Text(
            _formatRemaining(),
            style: TextStyle(
              color: isDanger ? AppTokens.danger : tokens.textSecondary,
              fontSize: MeaningMatchLayout.countdownTextSize,
              // 不加粗：倒计时是次要信息，弱于中间的主进度数字。
              fontWeight: FontWeight.w400,
              // 等宽数字替代原型的 font-monospace：既不跳动，又与全站字体保持一致。
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  ///
  /// 把剩余毫秒格式化为 mm:ss。
  ///
  /// @return String 形如 02:30 的倒计时文本。
  ///
  String _formatRemaining() {
    final totalSeconds = max(0, _remainingSeconds);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    // 补零保证两位，视觉上不会因秒数变化而宽度抖动。
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  ///
  /// 构建左右两列棋盘，并在下层铺一张“连线画布”。
  ///
  /// 层次与原型一致：最底下是连线画布（含正中那条竖直虚线），上面才是卡片，
  /// 所以绿色连线会从卡片边缘的小圆点出发，穿过中间 40 像素的空档。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 含卡片与连线的棋盘。
  ///
  Widget _buildBoard(AppTokens tokens) {
    // 左列 5 张：英文单词。
    final leftCards = <Widget>[
      for (var i = 0; i < 5; i += 1)
        _MatchCard(
          key: Key('mm-left-$i'),
          cardKey: _leftKeys[i],
          label: _currentPairs[i].spelling,
          isLeftSide: true,
          isSelected: _selectedSide == _CardSide.left && _selectedIndex == i,
          isMatched: _matchedLeft.contains(i),
          isWrong: _errorLeftIndex == i,
          onTap: () => _onCardTap(_CardSide.left, i),
        ),
    ];
    // 右列 5 张：按 _currentOrder 取对应含义。
    final rightCards = <Widget>[
      for (var k = 0; k < 5; k += 1)
        _MatchCard(
          key: Key('mm-right-$k'),
          cardKey: _rightKeys[k],
          label: _currentPairs[_currentOrder[k]].definition,
          isLeftSide: false,
          isSelected: _selectedSide == _CardSide.right && _selectedIndex == k,
          isMatched: _matchedRight.contains(k),
          isWrong: _errorRightIndex == k,
          onTap: () => _onCardTap(_CardSide.right, k),
        ),
    ];

    // 两列等宽、中间留 40 像素空档给连线穿过（原型 .matching-grid）。
    final grid = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _withGaps(leftCards),
          ),
        ),
        const SizedBox(width: MeaningMatchLayout.boardGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _withGaps(rightCards),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MeaningMatchLayout.pageInset,
        vertical: MeaningMatchLayout.boardVerticalInset,
      ),
      child: Stack(
        key: _boardKey,
        // expand 让画布铺满整块可用区域，正中的竖直虚线因此能贯穿上下。
        fit: StackFit.expand,
        children: [
          // 第一层：连线画布。IgnorePointer 让它完全透传点击，只负责画图。
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _connectController,
              builder: (_, _) => CustomPaint(
                painter: _MatchConnectionPainter(
                  boardKey: _boardKey,
                  leftKeys: _leftKeys,
                  rightKeys: _rightKeys,
                  connections: _matchedConnections,
                  activeConnection: _activeConnection,
                  activeProgress: _connectController.value,
                  lineColor: _kSuccess,
                  dividerColor: tokens.check,
                ),
              ),
            ),
          ),
          // 第二层：卡片。整块随换组淡入上移（原型 .fade-switch）。
          AnimatedBuilder(
            animation: _fadeController,
            builder: (_, child) => Opacity(
              opacity: _fadeController.value,
              child: Transform.translate(
                offset: Offset(
                  0,
                  (1 - _fadeController.value) *
                      MeaningMatchLayout.fadeSlideOffset,
                ),
                child: child,
              ),
            ),
            // 内容不随动画变化，交给 child 复用，避免每帧重建 10 张卡片。
            child: LayoutBuilder(
              // 空间够就垂直居中；万一屏幕很矮或系统字体极大，则退化为可滚动，
              // 不会出现 Flutter 的黄黑条溢出警告。
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(child: grid),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 给一列卡片之间插入固定间距（首尾不加）。
  ///
  /// @param  `List<Widget>`  cards 5 张卡片。
  /// @return `List<Widget>` 带间距的卡片列表。
  ///
  List<Widget> _withGaps(List<Widget> cards) {
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i += 1) {
      children.add(cards[i]);
      if (i < cards.length - 1) {
        children.add(const SizedBox(height: MeaningMatchLayout.sectionGap));
      }
    }
    return children;
  }

  ///
  /// 构建结算页（完成或超时），版式完全复刻原型的「倒计时结束状态页」。
  ///
  /// 从上到下：圆形图标底盘 → 主标题 → 副标题 → 2×2 统计卡 → 再挑战按钮。
  ///
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @return Widget 结算内容。
  ///
  Widget _buildSummary(AppTokens tokens) {
    final isWin = _completed;
    // 胜负决定主色：赢了用成功绿奖杯，超时用危险红闹钟。
    final accentColor = isWin ? _kSuccess : AppTokens.danger;

    return LayoutBuilder(
      // 内容高度可能超过矮屏幕，用可滚动容器兜底，同时保持“空间够就垂直居中”。
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: MeaningMatchLayout.summaryInset,
          vertical: MeaningMatchLayout.summarySectionGap,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.maxHeight -
                MeaningMatchLayout.summarySectionGap * 2,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 圆形图标底盘：直径 64，底色是主色的 10% 淡版。
              Center(
                child: Container(
                  width: MeaningMatchLayout.summaryAvatarSize,
                  height: MeaningMatchLayout.summaryAvatarSize,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: tokens.cardShadow,
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isWin ? TablerIcons.trophy : TablerIcons.alarmOff,
                    size: MeaningMatchLayout.summaryAvatarIconSize,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 主标题。
              Text(
                isWin ? '大获全胜！' : '挑战结束',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MeaningMatchLayout.summaryTitleSize,
                  fontWeight: FontWeight.bold,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 4),
              // 副标题。
              Text(
                isWin
                    ? '太棒了！你在规定时间内完成了全部 $_totalPairs 个单词配对！'
                    : '倒计时已结束，已为你结算本次训练战绩！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MeaningMatchLayout.summarySubtitleSize,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: MeaningMatchLayout.summarySectionGap),
              // 2×2 统计卡矩阵：上排“最高连对 / 配对失误”，下排“剩余时间 / 完成词汇”。
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SummaryStatCard(
                        icon: TablerIcons.flame,
                        label: '最高连对',
                        value: '$_bestStreak',
                        unit: '次',
                        color: _kOrange,
                        tokens: tokens,
                      ),
                    ),
                    const SizedBox(width: MeaningMatchLayout.summaryStatGap),
                    Expanded(
                      child: _SummaryStatCard(
                        icon: TablerIcons.x,
                        label: '配对失误',
                        value: '$_errors',
                        unit: '次',
                        color: AppTokens.danger,
                        tokens: tokens,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MeaningMatchLayout.summaryStatGap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SummaryStatCard(
                        icon: TablerIcons.clock,
                        label: '剩余时间',
                        // 超时结算时剩余固定是 00:00。
                        value: isWin ? _formatRemaining() : '00:00',
                        unit: '限时 ${_totalMs ~/ 1000} 秒',
                        color: AppTokens.accent,
                        tokens: tokens,
                        isTimeValue: true,
                      ),
                    ),
                    const SizedBox(width: MeaningMatchLayout.summaryStatGap),
                    Expanded(
                      child: _SummaryStatCard(
                        icon: TablerIcons.check,
                        label: '完成词汇',
                        value: '$_matchedPairs',
                        unit: '总词量 $_totalPairs',
                        color: _kSuccess,
                        tokens: tokens,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MeaningMatchLayout.summarySectionGap),
              // 底部主按钮：重置本局重新开局。
              SizedBox(
                height: MeaningMatchLayout.summaryButtonHeight,
                child: FilledButton.icon(
                  key: const Key('meaning-match-restart'),
                  onPressed: _restart,
                  icon: const Icon(TablerIcons.rotateClockwise, size: 18),
                  label: const Text('再挑战一次'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: MeaningMatchLayout.countdownTextSize,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        MeaningMatchLayout.cardRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

///
/// 结算页 2×2 矩阵中的一张统计卡。
///
/// 版式对应原型 `.card.card-sm.bg-light-subtle.text-center.py-3.border`：
/// 顶部是「小图标 + 灰色标题」，中间是大号彩色数值，底部是更小的灰色单位说明。
///
class _SummaryStatCard extends StatelessWidget {
  ///
  /// 创建一张统计卡。
  ///
  /// @param  IconData  icon 标题左侧的 Tabler 图标。
  /// @param  String  label 灰色小标题，如“最高连对”。
  /// @param  String  value 中间的大号数值，如“12”或“01:30”。
  /// @param  String  unit 底部单位说明，如“次”“总词量 50”。
  /// @param  Color  color 图标与数值共用的强调色。
  /// @param  AppTokens  tokens 当前主题设计令牌。
  /// @param  bool  isTimeValue true 表示数值是 mm:ss，需要用较小字号避免撑破卡片。
  ///
  const _SummaryStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.tokens,
    this.isTimeValue = false,
  });

  ///
  /// 标题左侧的 Tabler 图标。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 灰色小标题。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 中间的大号数值。
  ///
  /// @var String
  ///
  final String value;

  ///
  /// 底部单位说明。
  ///
  /// @var String
  ///
  final String unit;

  ///
  /// 图标与数值共用的强调色。
  ///
  /// @var Color
  ///
  final Color color;

  ///
  /// 当前主题设计令牌。
  ///
  /// @var AppTokens
  ///
  final AppTokens tokens;

  ///
  /// 数值是否是 mm:ss 时间格式。
  ///
  /// @var bool
  ///
  final bool isTimeValue;

  ///
  /// 输出一张居中排版的统计卡。
  ///
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 统计卡。
  ///
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: MeaningMatchLayout.summaryStatPaddingVertical,
        horizontal: 6,
      ),
      decoration: BoxDecoration(
        // bg-light-subtle：比卡片本体更淡一层的底色。
        color: tokens.expand,
        borderRadius: BorderRadius.circular(MeaningMatchLayout.cardRadius),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 第一行：小图标 + 灰色标题。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: MeaningMatchLayout.summaryStatLabelSize,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第二行：大号彩色数值。FittedBox 保证极端窄屏或超大数字也不会溢出。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isTimeValue
                    ? MeaningMatchLayout.summaryStatTimeSize
                    : MeaningMatchLayout.summaryStatValueSize,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          // 第三行：更小的灰色单位说明。
          Text(
            unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: MeaningMatchLayout.summaryStatUnitSize,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

///
/// 一张可点击的候选卡，自带“连错抖动 + 红框闪烁”。
///
/// 样式复刻原型 `.pair-btn`：52～62 高、10 圆角、1 像素淡边框、极轻投影；
/// 文字 13 像素最多两行；卡片内侧边线上骑着一个 8 像素小圆点（锚点），
/// 连线就是从这个圆点的圆心出发的。
///
class _MatchCard extends StatefulWidget {
  ///
  /// 创建一张候选卡。
  ///
  /// @param  GlobalKey  cardKey 供连线层取锚点坐标的全局键。
  /// @param  String  label 卡片显示文本。
  /// @param  bool  isLeftSide 是否属于左列。
  /// @param  bool  isSelected 是否被选中。
  /// @param  bool  isMatched 是否已成功连上。
  /// @param  bool  isWrong 是否正在播放连错反馈。
  /// @param  VoidCallback  onTap 点击回调。
  ///
  /// @param  Key?  key
  ///
  const _MatchCard({
    required this.cardKey,
    required this.label,
    required this.isLeftSide,
    required this.isSelected,
    required this.isMatched,
    required this.isWrong,
    required this.onTap,
    super.key,
  });

  ///
  /// 该卡片的全局键，供连线层取锚点坐标。
  ///
  /// @var GlobalKey
  ///
  final GlobalKey cardKey;

  ///
  /// 卡片显示文本（左列英文 / 右列中文）。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 是否属于左列（决定锚点圆点画在哪一侧、文字往哪边对齐）。
  ///
  /// @var bool
  ///
  final bool isLeftSide;

  ///
  /// 是否被选中（等待配对）。
  ///
  /// @var bool
  ///
  final bool isSelected;

  ///
  /// 是否已成功连上（锁定为绿色并划掉文字）。
  ///
  /// @var bool
  ///
  final bool isMatched;

  ///
  /// 是否正在播放连错反馈（红框 + 左右甩动）。
  ///
  /// 由父级在配对失败时置为 true，抖动播完后再置回 false。
  ///
  /// @var bool
  ///
  final bool isWrong;

  ///
  /// 点击回调。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 创建候选卡状态。
  ///
  /// @return `State<_MatchCard>` 管理抖动动画的状态对象。
  ///
  @override
  State<_MatchCard> createState() => _MatchCardState();
}

///
/// 候选卡状态：用自带 AnimationController 驱动连错时的左右抖动。
///
class _MatchCardState extends State<_MatchCard>
    with SingleTickerProviderStateMixin {
  ///
  /// 抖动控制器：时长取布局常量 shakeDurationMs（补充稿 0.4 秒）。
  ///
  /// @var AnimationController
  ///
  late final AnimationController _shakeController;

  ///
  /// 当前抖动水平偏移（像素），由动画进度推算。
  ///
  /// @var double
  ///
  double _shakeOffset = 0;

  ///
  /// 当前抖动旋转角度（弧度），由动画进度推算。
  ///
  /// 生活化解释：补充稿的抖动不只是左右平移，前两下还带一点点歪头，
  /// 这样看起来更像“摇头说不对”，而不是机械地平移。
  ///
  /// @var double
  ///
  double _shakeAngle = 0;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: MeaningMatchLayout.shakeDurationMs),
    );
    // 每帧把 0..1 进度映射到关键帧之间的线性插值，完全复刻 CSS 的抖动节奏。
    _shakeController.addListener(() {
      setState(() {
        _shakeOffset = _interpolate(
          MeaningMatchLayout.shakeKeyframes,
          _shakeController.value,
        );
        // 度换算成弧度：Flutter 的 Transform.rotate 只认弧度。
        _shakeAngle =
            _interpolate(_kShakeRotationFrames, _shakeController.value) *
            MeaningMatchLayout.shakeRotationDegrees *
            pi /
            180;
      });
    });
    // 动画结束：复位偏移与角度，卡片停回原来的位置。
    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _shakeOffset = 0;
          _shakeAngle = 0;
        });
      }
    });
    // 极端情况下（如刚重建就处于连错态）首帧直接补播一次抖动。
    if (widget.isWrong) _shakeController.forward(from: 0);
  }

  ///
  /// 父级把 isWrong 从 false 改成 true 时开播抖动，改回 false 时立即复位。
  ///
  /// 生活化解释：这张卡自己不判断对错，只盯着父级递过来的这个开关；
  /// 开关一拨到「错」就摇头，拨回去就站直。
  ///
  /// @param  _MatchCard  oldWidget 上一次的配置。
  /// @return void
  ///
  @override
  void didUpdateWidget(covariant _MatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isWrong && !oldWidget.isWrong) {
      _shakeController.forward(from: 0);
      return;
    }
    if (!widget.isWrong && oldWidget.isWrong) {
      _shakeController.stop();
      setState(() {
        _shakeOffset = 0;
        _shakeAngle = 0;
      });
    }
  }

  ///
  /// 按 CSS 关键帧计算某一时刻的取值。
  ///
  /// 生活化解释：关键帧只规定了 6 个时间点的位置，两点之间匀速移动，
  /// 这个方法就是在算“现在走到两个关键帧之间的哪个位置了”。
  ///
  /// @param  `List<double>`  frames 6 个等间隔关键帧的取值。
  /// @param  double  t 动画进度（0～1）。
  /// @return double 当前时刻应该取的值。
  ///
  double _interpolate(List<double> frames, double t) {
    // 6 个关键帧把动画切成 5 段，先算出落在第几段、段内进度多少。
    final scaled = (t * (frames.length - 1)).clamp(
      0.0,
      (frames.length - 1).toDouble(),
    );
    final index = scaled.floor().clamp(0, frames.length - 2);
    final fraction = scaled - index;
    // 段内线性插值。
    return frames[index] + (frames[index + 1] - frames[index]) * fraction;
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  ///
  /// 计算当前卡片处于哪一种视觉状态（优先级：连错 > 已连 > 选中 > 默认）。
  ///
  /// @return _CardVisualState 当前视觉状态。
  ///
  _CardVisualState get _visualState {
    if (widget.isWrong) return _CardVisualState.error;
    if (widget.isMatched) return _CardVisualState.matched;
    if (widget.isSelected) return _CardVisualState.selected;
    return _CardVisualState.idle;
  }

  ///
  /// 输出一张带锚点圆点的候选卡。
  ///
  /// 四种状态的配色与投影严格对照补充稿 `ui/词义连连_部分效果.html`：
  /// - 默认：白底 + 极淡描边 + 一点点投影；
  /// - 选中：蓝色描边 + 淡蓝底 + 蓝字，整卡放大 1.02 并向下打一束蓝光；
  /// - 连对：淡绿描边 + 极淡绿底 + 绿字划线，整卡缩到 0.97 并淡到 45%；
  /// - 连错：淡红描边 + 极淡红底 + 红字，并左右甩动一下。
  ///
  /// @param  BuildContext  context 当前 Widget 树上下文。
  /// @return Widget 候选卡。
  ///
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final state = _visualState;
    // 三种状态各有一个主色，默认态没有主色（用中性描边与文字色）。
    final stateColor = switch (state) {
      _CardVisualState.error => AppTokens.danger,
      _CardVisualState.matched => _kSuccess,
      _CardVisualState.selected => AppTokens.accent,
      _CardVisualState.idle => null,
    };

    // 描边色：选中用饱和主色（对应补充稿的 primary 实线边），连对/连错则用
    // 主色兑到卡片底色上的“淡色边”（对应 #bbf7d0 与 #fca5a5），不再喧宾夺主。
    final borderColor = switch (state) {
      _CardVisualState.selected => AppTokens.accent,
      _CardVisualState.matched => Color.alphaBlend(
        _kSuccess.withValues(alpha: _kMatchedBorderAlpha),
        tokens.card,
      ),
      _CardVisualState.error => Color.alphaBlend(
        AppTokens.danger.withValues(alpha: _kErrorBorderAlpha),
        tokens.card,
      ),
      _CardVisualState.idle => tokens.border,
    };

    // 底色：把主色按极低比例兑进卡片底色，得到补充稿里 #f0f7ff / #fef2f2 那种
    // “几乎还是白的，但能看出色调”的淡底；深色主题下同样成立，不会突然发白。
    final background = stateColor == null
        ? tokens.card
        : Color.alphaBlend(
            stateColor.withValues(alpha: _kStateBackgroundAlpha),
            tokens.card,
          );

    // 文字色：默认态下左列是主文字、右列是次要灰（原型 #626976）。
    final labelColor =
        stateColor ?? (widget.isLeftSide ? tokens.text : tokens.textSecondary);

    // 投影：连对的卡片彻底去掉投影（补充稿 box-shadow: none）“沉”下去；
    // 选中的卡片额外加一圈实心描边光 + 一束向下的柔光，做出被提起来的手感。
    final shadows = switch (state) {
      _CardVisualState.matched => const <BoxShadow>[],
      _CardVisualState.selected => <BoxShadow>[
        // 第一层：紧贴边框再描一圈，视觉上等于把 1 像素蓝边加粗成 2 像素。
        BoxShadow(color: AppTokens.accent, spreadRadius: 1),
        // 第二层：向下 8 像素、模糊 20 像素的蓝色柔光，卡片像浮在纸面上。
        BoxShadow(
          color: AppTokens.accent.withValues(alpha: 0.2),
          offset: const Offset(0, MeaningMatchLayout.selectedGlowOffsetY),
          blurRadius: MeaningMatchLayout.selectedGlowBlur,
          spreadRadius: MeaningMatchLayout.selectedGlowSpread,
        ),
      ],
      _ => <BoxShadow>[
        BoxShadow(
          color: tokens.cardShadow,
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ],
    };

    // 锚点外圈光晕：选中时最亮最大，连错时是一圈红色薄雾，其余只是一道细描边。
    final anchorHalo = switch (state) {
      _CardVisualState.selected => BoxShadow(
        color: AppTokens.accent.withValues(alpha: 0.3),
        spreadRadius: MeaningMatchLayout.anchorSelectedHalo,
      ),
      _CardVisualState.error => BoxShadow(
        color: AppTokens.danger.withValues(alpha: 0.25),
        spreadRadius: MeaningMatchLayout.anchorErrorHalo,
      ),
      _CardVisualState.matched => const BoxShadow(
        color: _kSuccess,
        spreadRadius: 1,
      ),
      _CardVisualState.idle => BoxShadow(
        color: tokens.border,
        spreadRadius: 1,
      ),
    };

    // 锚点圆点：外圈一圈白边 + 再外面一圈光晕，做出“实心小圆点”的质感；
    // 选中时整颗放大 1.3 倍，成为连线即将出发的“充能点”。
    final anchor = IgnorePointer(
      child: AnimatedScale(
        scale: state == _CardVisualState.selected
            ? MeaningMatchLayout.anchorSelectedScale
            : 1,
        duration: const Duration(
          milliseconds: MeaningMatchLayout.cardTransformTransitionMs,
        ),
        curve: _kSpringEase,
        child: AnimatedContainer(
          duration: const Duration(
            milliseconds: MeaningMatchLayout.cardColorTransitionMs,
          ),
          width: MeaningMatchLayout.anchorSize,
          height: MeaningMatchLayout.anchorSize,
          decoration: BoxDecoration(
            color: stateColor ?? tokens.check,
            shape: BoxShape.circle,
            border: Border.all(
              color: tokens.card,
              width: MeaningMatchLayout.anchorRingWidth,
            ),
            boxShadow: [anchorHalo],
          ),
        ),
      ),
    );

    // 卡片本体：固定 52～62 高，内边距 6/12，1 像素描边加状态投影。
    final card = InkWell(
      // 已连上的卡不再响应点击（补充稿 pointer-events: none）。
      onTap: widget.isMatched ? null : widget.onTap,
      borderRadius: BorderRadius.circular(MeaningMatchLayout.cardRadius),
      child: AnimatedContainer(
        // 变色走 0.25 秒，和补充稿的 border-color / background-color 过渡一致。
        duration: const Duration(
          milliseconds: MeaningMatchLayout.cardColorTransitionMs,
        ),
        curve: Curves.easeOut,
        // cardKey 挂在这里：连线层按“这张卡片的边缘中点”定位锚点圆心。
        key: widget.cardKey,
        constraints: const BoxConstraints(
          minHeight: MeaningMatchLayout.cardMinHeight,
          maxHeight: MeaningMatchLayout.cardMaxHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MeaningMatchLayout.cardPaddingHorizontal,
          vertical: MeaningMatchLayout.cardPaddingVertical,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(MeaningMatchLayout.cardRadius),
          border: Border.all(color: borderColor),
          boxShadow: shadows,
        ),
        // heightFactor: 1 让这层只占文字自身的高度，再由外层 52～62 的约束把它
        // 撑到最小 52——如果这里改用普通 Center 或给 Container 设 alignment，
        // 卡片会被强行拉到最大的 62，和原型对不上。
        child: Center(
          heightFactor: 1,
          child: AnimatedDefaultTextStyle(
            // 文字换色同样是渐变过去，不会和底色变化脱节。
            duration: const Duration(
              milliseconds: MeaningMatchLayout.cardColorTransitionMs,
            ),
            curve: Curves.easeOut,
            style: TextStyle(
              color: labelColor,
              fontSize: MeaningMatchLayout.cardLabelSize,
              height: MeaningMatchLayout.cardLabelLineHeight,
              // 左列单词更重，右列释义稍轻，形成主次关系。
              fontWeight: widget.isLeftSide ? FontWeight.w600 : FontWeight.w500,
              // 连上的卡片把文字划掉，表示这一对已经消除。
              decoration: widget.isMatched ? TextDecoration.lineThrough : null,
              decorationColor: labelColor,
            ),
            child: Text(
              widget.label,
              maxLines: MeaningMatchLayout.cardLabelMaxLines,
              overflow: TextOverflow.ellipsis,
              // 左列英文靠左，右列中文靠右，中间空档留给连线。
              textAlign: widget.isLeftSide ? TextAlign.left : TextAlign.right,
            ),
          ),
        ),
      ),
    );

    // 整卡缩放：选中轻微提起 1.02，连对缩到 0.97，其余保持原尺寸。
    // 连错时不参与缩放，把变形完全让给抖动动画（补充稿的 animation 会覆盖 transform）。
    final scale = switch (state) {
      _CardVisualState.selected => MeaningMatchLayout.selectedScale,
      _CardVisualState.matched => MeaningMatchLayout.matchedScale,
      _ => 1.0,
    };

    return Transform.rotate(
      // 抖动时的歪头角度；不抖动时恒为 0，不产生任何额外开销。
      angle: _shakeAngle,
      child: Transform.translate(
        offset: Offset(_shakeOffset, 0),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(
            milliseconds: MeaningMatchLayout.cardTransformTransitionMs,
          ),
          curve: _kSpringEase,
          // 已连上的整张卡淡到 45%，视觉上“退居二线”（补充稿 opacity: 0.45）。
          child: AnimatedOpacity(
            opacity: widget.isMatched
                ? MeaningMatchLayout.matchedOpacity
                : 1.0,
            duration: const Duration(
              milliseconds: MeaningMatchLayout.cardTransformTransitionMs,
            ),
            curve: _kSpringEase,
            child: Stack(
              // 锚点要露出卡片边线之外，必须关掉裁剪。
              clipBehavior: Clip.none,
              children: [
                card,
                // 锚点骑在内侧边线上：左列在右边缘，右列在左边缘。
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: widget.isLeftSide
                      ? null
                      : -MeaningMatchLayout.anchorOverhang,
                  right: widget.isLeftSide
                      ? -MeaningMatchLayout.anchorOverhang
                      : null,
                  child: Center(child: anchor),
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
/// 连线画布：先画正中那条竖直虚线，再把已连成的左右卡片用绿色曲线连起来。
///
class _MatchConnectionPainter extends CustomPainter {
  ///
  /// 创建画布。
  ///
  /// @param  GlobalKey  boardKey 棋盘容器键，用于坐标换算。
  /// @param  `List<GlobalKey>`  leftKeys 左列卡片键。
  /// @param  `List<GlobalKey>`  rightKeys 右列卡片键。
  /// @param  `List<(int, int)>`  connections 已连成的连线。
  /// @param  `(int, int)?`  activeConnection 正在播放生长动画的连线。
  /// @param  double  activeProgress 生长动画进度（0～1）。
  /// @param  Color  lineColor 连线颜色。
  /// @param  Color  dividerColor 正中竖直虚线颜色。
  ///
  const _MatchConnectionPainter({
    required this.boardKey,
    required this.leftKeys,
    required this.rightKeys,
    required this.connections,
    required this.activeConnection,
    required this.activeProgress,
    required this.lineColor,
    required this.dividerColor,
  });

  /// 棋盘容器键，用于把卡片的全局坐标换算成画布本地坐标。
  final GlobalKey boardKey;

  /// 左列 5 张卡片的全局键。
  final List<GlobalKey> leftKeys;

  /// 右列 5 张卡片的全局键。
  final List<GlobalKey> rightKeys;

  /// 已连成的连线（左卡下标, 右卡位置）。
  final List<(int, int)> connections;

  /// 正在播放生长动画的那条连线。
  final (int, int)? activeConnection;

  /// 生长动画进度（0～1）。
  final double activeProgress;

  /// 连线颜色。
  final Color lineColor;

  /// 正中竖直虚线颜色。
  final Color dividerColor;

  ///
  /// 依次绘制中间虚线与全部连线。
  ///
  /// @param  Canvas  canvas 画布。
  /// @param  Size  size 画布尺寸。
  /// @return void
  ///
  @override
  void paint(Canvas canvas, Size size) {
    _drawDivider(canvas, size);
    for (final (leftIndex, rightIndex) in connections) {
      // 正在绘制的那条连线用动画进度，其余已完成的画满。
      final progress = activeConnection == (leftIndex, rightIndex)
          ? activeProgress
          : 1.0;
      _drawConnection(canvas, leftIndex, rightIndex, progress);
    }
  }

  ///
  /// 画正中那条上下贯穿的竖直虚线（原型的 8 实 8 虚）。
  ///
  /// @param  Canvas  canvas 画布。
  /// @param  Size  size 画布尺寸。
  /// @return void
  ///
  void _drawDivider(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dividerColor
      ..strokeWidth = MeaningMatchLayout.dividerWidth
      ..style = PaintingStyle.stroke;
    // 虚线画在画布水平正中，也就是左右两列之间 40 像素空档的中线。
    final centerX = size.width / 2;
    var y = 0.0;
    while (y < size.height) {
      // 每一段实线画 8 像素，然后跳过 8 像素空白，如此往复。
      final end = min(y + MeaningMatchLayout.dividerDashLength, size.height);
      canvas.drawLine(Offset(centerX, y), Offset(centerX, end), paint);
      y = end + MeaningMatchLayout.dividerDashGap;
    }
  }

  ///
  /// 画一条从左侧卡片右缘到右侧卡片左缘的平滑 S 曲线。
  ///
  /// @param  Canvas  canvas 画布。
  /// @param  int  leftIndex 左卡下标。
  /// @param  int  rightIndex 右卡位置。
  /// @param  double  progress 绘制比例（0~1，用于连线生长动画）。
  /// @return void
  ///
  void _drawConnection(
    Canvas canvas,
    int leftIndex,
    int rightIndex,
    double progress,
  ) {
    final start = _anchor(leftKeys[leftIndex], isRightColumn: false);
    final end = _anchor(rightKeys[rightIndex], isRightColumn: true);
    // 任一张卡片还没布局好（坐标为空）就跳过，避免画到 (0,0)。
    if (start == null || end == null) return;
    // 进度为 0 时没有任何可见线段，直接返回省掉一次路径计算。
    if (progress <= 0) return;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = MeaningMatchLayout.connectionLineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 三次贝塞尔：两个控制点都落在左右锚点的水平中线上，形成平滑 S 形。
    final midX = (start.dx + end.dx) / 2;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);

    // 进度满了就整条画完，省去按长度截取的开销。
    if (progress >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    // 未满则按路径长度截取前 progress 段，等价于原型用 stroke-dashoffset
    // 做的“沿着曲线一点点长出来”效果（曲线形状始终不变）。
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  ///
  /// 取卡片锚点（内侧边缘中点）相对棋盘的本地坐标。
  ///
  /// [key] 卡片全局键；[isRightColumn] true 表示右列（取左边缘），false 表示左列（取右边缘）。
  ///
  /// @return Offset? 相对棋盘的锚点坐标；卡片未布局时返回 null。
  ///
  Offset? _anchor(GlobalKey key, {required bool isRightColumn}) {
    final ctx = key.currentContext;
    final boardCtx = boardKey.currentContext;
    if (ctx == null || boardCtx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    final boardBox = boardCtx.findRenderObject() as RenderBox?;
    if (box == null || boardBox == null) return null;
    // 卡片左上角相对棋盘左上角的偏移。
    final topLeft =
        box.localToGlobal(Offset.zero) - boardBox.localToGlobal(Offset.zero);
    final rect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
    // 左列取右缘中点，右列取左缘中点——正好是锚点圆点的圆心。
    return Offset(isRightColumn ? rect.left : rect.right, rect.center.dy);
  }

  ///
  /// 连线集合或动画进度变化时才重绘。
  ///
  /// @param  _MatchConnectionPainter  old 上一次的画布配置。
  /// @return bool true 表示需要重绘。
  ///
  @override
  bool shouldRepaint(covariant _MatchConnectionPainter old) =>
      old.connections != connections ||
      old.activeConnection != activeConnection ||
      old.activeProgress != activeProgress ||
      old.dividerColor != dividerColor;
}
