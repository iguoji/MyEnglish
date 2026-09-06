// dart:async 提供 Timer，用于每秒倒数；也提供 Future.delayed 做“一组完成后停顿”。
import 'dart:async';
// dart:math 提供 sin/pi（抖动与呼吸动画）与 Random（确定性出题，保证续玩时棋盘一致）。
import 'dart:math';
// material.dart 提供全屏页面、进度条、卡片与对话框。
import 'package:flutter/material.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。

// 引入全局设计令牌（颜色变量，随亮色/深色主题自动切换）。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角倒计时不足一小时 mm:ss，满一小时 hh:mm:ss。
import '../../common/date.dart';
// 引入单词数据模型，首页会把当天固定词单传进来。
import '../../models/word.dart';
// 引入复习会话模型：模块标识、主线/巩固类型与状态。
// 引入全局设置 Store，读取与修改词义连连倒计时。
import '../../store/settings.dart';
// 引入发音服务，选中单词卡时播放读音。
import '../../services/word_audio.dart';
// 引入统一的进度出口：写进度、记每次点击、结算难度都走它。
import '../review/services/session_progress.dart';
// 引入集中管理的页面布局尺寸。
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
import 'widgets/meaning_match_layout.dart';

///
/// 补充稿 `--spring-ease: cubic-bezier(0.16, 1, 0.3, 1)` 的等价缓动曲线。
///
/// 生活化解释：这是一条“先冲得很快、临到终点急刹车”的运动曲线，
/// 卡片放大、缩小、变淡都用它，动作看起来才有弹性而不是匀速拖拽。
const Cubic _kSpringEase = Cubic(0.16, 1, 0.3, 1);

///
/// 状态底色的兑色比例：主色按这个比例兑进卡片底色。
///
/// 生活化解释：相当于往一整桶白漆里滴几滴蓝色，得到补充稿里 #f0f7ff 那种
/// “乍看还是白的，细看有点蓝”的淡底。写成比例而不是写死颜色，深色主题下
/// 兑出来的就是“黑里透蓝”，不会突然冒出一块刺眼的白。
///
/// 收敛前这里写 0.06，现在与其他三处「最淡状态底」一起读总表同一档。
const double _kStateBackgroundAlpha = AppAlpha.a8;

///
/// 连对卡片描边的兑色比例（补充稿 `.is-matched { border-color: #bbf7d0 }`）。
///
/// 收敛前写 0.35，现在读总表的偶数台阶。
const double _kMatchedBorderAlpha = AppAlpha.a36;

///
/// 连错卡片描边的兑色比例（补充稿 `.is-error { border-color: #fca5a5 }`）。
///
/// 收敛前写 0.45，现在读总表的偶数台阶。
const double _kErrorBorderAlpha = AppAlpha.a44;

///
/// 连错抖动的旋转关键帧倍数，对应补充稿 `errorJolt` 的六个时间点。
///
/// 补充稿只在 20% 与 40% 两帧写了 `rotate(∓0.5deg)`，其余帧不旋转，
/// 因此这里是 [0, -1, 1, 0, 0, 0]，再乘以 shakeRotationDegrees 得到实际角度。
const List<double> _kShakeRotationFrames = <double>[0, -1, 1, 0, 0, 0];

///
/// 棋盘上的一对候选：左侧英文拼写 + 右侧中文含义。
///
/// 生活化解释：相当于连连看里“一个词”和它的“一张释义卡片”，左右各放一边等待连。
///
class MatchPair {
  ///
  /// 创建一对候选。
  const MatchPair({
    required this.wordId,
    required this.spelling,
    required this.definition,
    required this.meaningId,
  });

  ///
  /// 单词主键。
  final int? wordId;

  ///
  /// 这一对用的是这个单词的哪一条释义；写记录时要带上它。
  final int? meaningId;

  ///
  /// 左侧英文拼写。
  final String spelling;

  ///
  /// 右侧中文含义。
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
  const MeaningMatchProgress({
    required this.totalPairs,
    required this.bestMatchedPairs,
    required this.completed,
  });

  ///
  /// 本局固定总配对数。
  final int totalPairs;

  ///
  /// 目前已匹配的对数（即首页百分比的分子）。
  final int bestMatchedPairs;

  ///
  /// 本局是否已完成（完成后首页显示 100%「已完成」，与听音辨义口径一致）。
  final bool completed;

  ///
  /// 完成度比例（0～1），作为首页进度条填充。
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
/// 倒计时的三个阶段，只影响右上角时间文字的颜色。
///
/// 生活化解释：把一局的时间想成一瓶水——喝掉三分之一之前是“正常”，
/// 剩三分之二时开始提醒你“该抓紧了”，只剩三分之一时就进入“危险”了。
enum _CountdownStage {
  ///
  /// 剩余时间还多于三分之二：用和其他模块一致的默认灰。
  normal,

  ///
  /// 剩余时间不足三分之二：转成 Tabler 警告橙。
  warning,

  ///
  /// 剩余时间不足三分之一：转成危险红。
  danger,
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
/// 玩法：左右两列各有若干张卡片（整组最多 5 张，词太少时有多少显示多少），
/// 左列是英文单词、右列是它的一条中文含义（随机选取）；
/// 点一张左卡再点一张右卡，若二者对应即连成绿线，全部连完进入下一组；连错则红框抖动。
/// 顶部有倒计时，点一下 +30 秒并同步写入全局设置；进度在离场时冻结，仅当天可续玩。
///
/// 界面复刻 `ui/词义连连.html` 原型，只有「左上返回图标」与「中间数字进度」
/// 沿用听音辨义的样式，让两个复习模块看起来是同一套产品。
///
class MeaningMatchPage extends StatefulWidget {
  ///
  /// 创建词义连连页面。
  const MeaningMatchPage({
    required this.words,
    required this.title,
    required this.progress,
    this.settings,
    this.audioPlayer,
    this.accent = PronunciationAccent.american,
    super.key,
  }) : assert(words.length > 0, '词义连连至少需要一个单词');

  ///
  /// 首页按“已勾选优先，否则当前可见”规则传入的学习列表。
  final List<Word> words;

  ///
  /// 当前复习模块名称；顶栏中央改为显示数字进度，此处仅作语义标识与埋点。
  final String title;

  ///
  /// 本局的进度出口，由首页的 ReviewFlow 判定后传入。
  ///
  /// 它同时决定三件事：进度存到哪一局、每次点击记到哪一局，
  /// 以及答题要不要推进单词的复习时间（巩固局不推进）。
  final SessionProgress progress;

  ///
  /// 全局设置 Store；正式环境使用 Android 持久化，测试可注入内存实现。
  final SettingsStore? settings;

  ///
  /// 与首页、随身听共用的发音服务；选中单词卡时播放读音。
  /// 正式环境由首页注入，测试可不传（选中时不发声，不影响连线逻辑）。
  final WordAudioPlayer? audioPlayer;

  ///
  /// 当前发音口音；默认美式，与首页一致。
  final PronunciationAccent accent;

  ///
  /// 创建词义连连页面状态。
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
  /// 棋盘每组最多几对：数据列表按它切组，最后一组不足上限就**有多少显示多少**，
  /// 不再补位凑数（词太少时补位会造出重复卡，恢复现场会认错格子）。
  static const int _groupSize = 5;

  ///
  /// 所有分组（每组不超过 5 对；只有最后一组可能不足），确定性生成后不会再变。
  late final List<List<MatchPair>> _groups;

  ///
  /// 每组右列的真实配对顺序（排列），长度与该组的实际对数一致；
  /// 右列第 k 张显示 pairs[order[k]]。
  late final List<List<int>> _rightOrders;

  ///
  /// 本局总配对数 = 全部配对的实际数量（不足一组的尾巴也照算）。
  late final int _totalPairs;

  ///
  /// 当前所在分组下标（0 起）。
  int _groupIndex = 0;

  ///
  /// 当前组已经成功连上的“左卡下标”集合。
  final Set<int> _matchedLeft = <int>{};

  ///
  /// 当前组已经成功连上的“右卡位置”集合。
  final Set<int> _matchedRight = <int>{};

  ///
  /// 已连成的连线（左卡下标, 右卡位置），用于绘制贝塞尔曲线。
  final List<(int, int)> _matchedConnections = <(int, int)>[];

  ///
  /// 正在播放“连线动画”的那条连线；动画结束后置空。
  (int, int)? _activeConnection;

  ///
  /// 当前选中的卡片：哪一侧、哪个下标；非 null 表示等待再点另一侧来配对。
  _CardSide? _selectedSide;

  ///
  /// 当前选中的卡片下标（-1 表示无）。
  int _selectedIndex = -1;

  ///
  /// 剩余毫秒数；归零即超时。
  int _remainingMs = 0;

  ///
  /// 本局的总时长毫秒数，即顶部时间进度条的分母（原型 `TOTAL_TIME`）。
  ///
  /// 点击倒计时 +30 秒时分子分母一起加，进度条因此只会变长不会溢出。
  int _totalMs = 0;

  ///
  /// 本局连错次数，只在结算页副标题里露个面（不影响单词难度，也不写记录）。
  int _errors = 0;

  ///
  /// 本局是否全部连完。
  bool _completed = false;

  ///
  /// 本局是否因时间耗尽而结束。
  bool _timedOut = false;

  ///
  /// 倒计时计时器；页面不在前台时取消，回到前台再启动。
  Timer? _timer;

  ///
  /// 连错反馈期间的输入锁（补充稿的 `isProcessing`）。
  ///
  /// 生活化解释：连错后两张卡要红着脸抖 0.4 秒，这段时间里如果还能点别的卡，
  /// 红色会被下一次点击立刻打断，用户根本看不清自己错在哪。上了锁就必须
  /// 让这 0.4 秒播完，反馈才算真正“看得见”。
  bool _inputLocked = false;

  ///
  /// 连错输入锁的解锁定时器；页面销毁或重开时必须取消，避免定时器泄漏。
  Timer? _unlockTimer;

  ///
  /// 连线绘制动画控制器：每次成功配对都从 0 重新播到 1。
  late final AnimationController _connectController;

  ///
  /// 整块棋盘的淡入控制器：切到下一组或重开时从 0 播到 1（原型 `.fade-switch`）。
  late final AnimationController _fadeController;

  ///
  /// 倒计时呼吸控制器：剩余不足 10 秒时循环播放（原型 `.pulse-danger`）。
  late final AnimationController _pulseController;

  ///
  /// 棋盘容器全局键，用于把卡片坐标换算成相对棋盘的本地坐标。
  final GlobalKey _boardKey = GlobalKey();

  ///
  /// 左列卡片各自的全局键，用于取锚点坐标画连线。
  ///
  /// 只用来量“这张卡片画在屏幕的哪个位置”，不承担任何状态调用职责——
  /// 卡片的选中/连对/连错都由下面的下标字段驱动，父级传属性给子卡即可。
  /// 预置 5 把（一组最多 5 张），实际只把前面「当前组张数」张挂上组件，
  /// 多余的键不挂任何组件，没有副作用。
  final List<GlobalKey> _leftKeys = List<GlobalKey>.generate(
    5,
    (_) => GlobalKey(),
  );

  ///
  /// 右列卡片各自的全局键，约定同 [_leftKeys]。
  final List<GlobalKey> _rightKeys = List<GlobalKey>.generate(
    5,
    (_) => GlobalKey(),
  );

  ///
  /// 正在播放连错反馈的左卡下标；-1 表示当前没有连错。
  int _errorLeftIndex = -1;

  ///
  /// 正在播放连错反馈的右卡位置；-1 表示当前没有连错。
  int _errorRightIndex = -1;

  ///
  /// 正式页面复用全局设置实例，测试可注入内存实现。
  ///
  /// 必须是 late final 字段而不是 getter：写成 getter 时每次读取都会新建一个
  /// 内存 Store，导致“+30 秒”永远从默认值重新累加。
  late final SettingsStore _settings =
      widget.settings ?? SettingsStore.inMemory();

  ///
  /// 本局进度的落盘出口。
  SessionProgress get _progress => widget.progress;

  ///
  /// 当前组内每张左卡累计连错的次数。
  ///
  /// 生活化解释：连错一次时，「谁错了」其实说不清——可能是左边这个单词选错了，
  /// 也可能是右边那条释义点歪了。这里统一算在**左卡**头上，因为左卡是用户
  /// 正在安置的那个单词。等这张左卡最终连对时，把累计的错误次数一起写进
  /// 复习记录，难度和连对次数就都有依据了。
  ///
  /// 换组时清空：下一组是全新的 5 张卡，下标含义完全不同。
  final Map<int, int> _wrongByLeftIndex = <int, int>{};

  ///
  /// 已经写过复习记录的左卡，键是「第几组:第几张」。
  ///
  /// 换组后左卡下标会从 0 重新开始，所以必须带上组号才能唯一标识一张卡。
  /// 有了它，退出后再续玩、或者同一张卡被重复触发时都不会写出两条记录。
  final Set<String> _recordedLefts = <String>{};

  ///
  /// 当前分组的配对列表。
  List<MatchPair> get _currentPairs => _groups[_groupIndex];

  ///
  /// 当前分组的右列顺序。
  List<int> get _currentOrder => _rightOrders[_groupIndex];

  ///
  /// 已匹配总对数 = 前面整组完成的对数 + 当前组已连数（单调不减）。
  int get _matchedPairs => _donePairsBefore(_groupIndex) + _matchedLeft.length;

  ///
  /// 第 [group] 组**之前**所有整组完成的对数。
  ///
  /// 组的大小是「每 5 对切一组、最后一组可能不足 5」，不能再用「组数 × 5」
  /// 一笔算完，这里按每组实际张数逐组累加。
  int _donePairsBefore(int group) {
    var done = 0;
    for (var g = 0; g < group; g += 1) {
      done += _groups[g].length;
    }
    return done;
  }

  ///
  /// 是否展示结算页（完成或超时后）。
  bool get _showSummary => _completed || _timedOut;

  ///
  /// 剩余秒数（向上取整，与倒计时文本口径一致）。
  int get _remainingSeconds => ((_remainingMs / 1000).ceil()).clamp(0, 1 << 30);

  ///
  /// 倒计时是否进入“最后冲刺”（剩余不足 10 秒）。
  ///
  /// 原型在这一刻让文字开始呼吸，同时把顶部进度条改成红色。
  /// 它只管“最后十秒的紧张感”，文字颜色分档请看 [_countdownStage]。
  bool get _isTimeDanger =>
      !_showSummary &&
      _remainingMs > 0 &&
      _remainingSeconds <= MeaningMatchLayout.countdownDangerSeconds;

  ///
  /// 倒计时文字当前处在哪个阶段：按剩余时间占总时长的比例分三档。
  ///
  /// - 剩余 > 三分之二：[_CountdownStage.normal]，用默认灰；
  /// - 剩余 ≤ 三分之二：[_CountdownStage.warning]，用警告橙；
  /// - 剩余 ≤ 三分之一：[_CountdownStage.danger]，用危险红。
  ///
  /// 结算页和“还没开始计时”的边界情况一律按 normal 处理，不闪红。
  _CountdownStage get _countdownStage {
    // 分母不可用或已经结算时，没有“剩余比例”可言，直接算正常。
    if (_showSummary || _totalMs <= 0) return _CountdownStage.normal;
    // 剩余比例 = 剩余毫秒 / 本局总毫秒，范围 0~1。
    final ratio = _remainingMs / _totalMs;
    if (ratio <= 1 / 3) return _CountdownStage.danger;
    if (ratio <= 2 / 3) return _CountdownStage.warning;
    return _CountdownStage.normal;
  }

  ///
  /// 顶部时间进度条的填充比例（原型 `timeLeft / TOTAL_TIME`）。
  double get _timeRatio =>
      _totalMs > 0 ? (_remainingMs / _totalMs).clamp(0.0, 1.0) : 0.0;

  ///
  /// 初始化页面：先确定性出题，再决定是否从会话续玩，最后启动倒计时。
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
    // 第一步：按会话的数据列表还原棋盘（配对在开局时就已经定好并落库）。
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
  /// 按会话的数据列表还原棋盘，并生成所有分组。
  ///
  /// 「哪个单词配哪条释义」在开局时就已经定好并写进了数据列表，页面只负责
  /// 把它切成每组最多 5 行、再决定右列的显示顺序。右列顺序由会话 id 派生
  /// 的固定种子打乱，所以同一局每次进来棋盘与顺序完全一样——中途退出再进，
  /// 不需要依赖任何内存状态就能还原同一张棋盘。
  void _buildGroups() {
    // 数据列表的元素是 [单词id, 含义id]；单词与释义都从会话带来的词表里查。
    final wordsById = <int, Word>{
      for (final word in widget.words)
        if (word.id != null) word.id!: word,
    };
    final pairs = <MatchPair>[];
    for (final item in _progress.session.pairItems) {
      final word = wordsById[item.wordId];
      // 单词被删了就跳过这一对；开局时已经校验过，这里只是兜底。
      if (word == null) continue;
      // 按含义主键找那条释义；找不到（被编辑掉了）时退化用第一条。
      final meaning = word.allMeanings
          .where((candidate) => candidate.id == item.meaningId)
          .followedBy(word.allMeanings)
          .firstOrNull;
      if (meaning == null) continue;
      pairs.add(
        MatchPair(
          wordId: word.id,
          spelling: word.spelling,
          definition: meaning.definition,
          meaningId: meaning.id,
        ),
      );
    }

    // 右列顺序仍按会话 id 派生的固定种子打乱：同一局每次进来顺序一致，
    // 不同局之间又不会重样。
    final random = Random(_progress.session.id);
    final groups = <List<MatchPair>>[];
    final rightOrders = <List<int>>[];
    // 数据列表有多少对就切多少：每 5 对一组，最后一组不足 5 对就少显示
    // （不补位凑数），棋盘两侧各铺几张、整块仍然垂直居中。
    for (var i = 0; i < pairs.length; i += _groupSize) {
      final end = min(i + _groupSize, pairs.length);
      groups.add(List<MatchPair>.unmodifiable(pairs.sublist(i, end)));
      final order = List<int>.generate(end - i, (index) => index)
        ..shuffle(random);
      rightOrders.add(List<int>.unmodifiable(order));
    }

    _groups = List<List<MatchPair>>.unmodifiable(groups);
    _rightOrders = List<List<int>>.unmodifiable(rightOrders);
    // 总局数 = 全部配对的实际数量（不足一组的尾巴也照算）。
    _totalPairs = pairs.length;
  }

  ///
  /// 从会话恢复或开启新一局。
  ///
  /// 2.0 起不再靠一份页面快照还原现场，而是**回放这一局的点击记录**：
  /// 每连对一次都写了一条记录，把它们按「第几对」摊回棋盘即可。
  /// 剩余时间由会话里的「所用时间」反推，比存一个随时会过期的剩余毫秒更稳。
  void _restoreOrStart() {
    // 分母：本局总时长永远取自全局设置（点 +30s 加时也会同步抬高这个设置）。
    _totalMs = _settings.meaningMatchDuration * 1000;
    // 已用时间来自会话字段，单位是秒。
    final elapsedMs = _progress.session.elapsed * 1000;
    _remainingMs = (_totalMs - elapsedMs).clamp(0, _totalMs);

    // 累计连错数直接由记录数出来：中途退出再进来必须接着数，
    // 否则错完就退、退完再进，随手能刷出一局「全对」。
    _errors = _progress.wrongCount;

    // 已连对的配对：按 (单词, 含义) 建索引，再对照棋盘还原到具体格子。
    final matched = <String>{
      for (final record in _progress.allRecords)
        if (record.isCorrect && record.meaningId != null)
          '${record.wordId}:${record.meaningId}',
    };
    // 一对都没连过就是全新一局。
    if (matched.isEmpty) return;

    // 从第一组往后扫，整组连完就跳下一组；碰到没连完的那组就停在那里。
    for (var group = 0; group < _groups.length; group += 1) {
      final pairs = _groups[group];
      final doneInGroup = <int>[];
      for (var index = 0; index < pairs.length; index += 1) {
        final pair = pairs[index];
        if (matched.contains('${pair.wordId}:${pair.meaningId}')) {
          doneInGroup.add(index);
        }
      }
      // 整组都连完了，继续看下一组。
      if (doneInGroup.length == pairs.length && group + 1 < _groups.length) {
        continue;
      }
      _groupIndex = group;
      // 把这一组已经连对的格子摊回棋盘：左卡下标 → 右列位置。
      final order = _rightOrders[group];
      for (final leftIndex in doneInGroup) {
        final rightIndex = order.indexOf(leftIndex);
        if (rightIndex < 0) continue;
        _matchedLeft.add(leftIndex);
        _matchedRight.add(rightIndex);
        _matchedConnections.add((leftIndex, rightIndex));
        // 已经连对过的卡不再重复写记录、重复结算。
        _recordedLefts.add('$group:$leftIndex');
      }
      break;
    }
  }

  ///
  /// 启动每秒倒数；归零即触发超时结算。
  void _startTimer() {
    _stopTimer();
    // 恢复会话时如果所用时间已经达到总时长，不能创建一个“归零后什么也不做”
    // 的定时器；要立即按超时收尾，否则页面会一直停在 00:00 的答题状态。
    if (_showSummary) return;
    if (_remainingMs <= 0) {
      _onTimeout();
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // 页面离开或已经结算后，定时器回调不再修改界面。
      if (!mounted || _showSummary) return;
      // 防御恢复数据在运行中变成归零的情况，直接走统一超时流程。
      if (_remainingMs <= 0) {
        _onTimeout();
        return;
      }
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
  void _onTimeout() {
    if (_completed) return;
    _stopTimer();
    setState(() => _timedOut = true);
    // 结算页不需要呼吸动画。
    _syncPulse();
    // 超时按「失败」结算：这一局没能全部连完，今天的任务还没过关。
    unawaited(_finishSession());
  }

  ///
  /// 点击卡片：管理选中态并尝试配对。
  ///
  /// [side] 被点的卡片在左列还是右列；[index] 在各自列中的下标。
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
      // 选中单词卡时播放发音，让用户听着读音去找对应释义。
      if (side == _CardSide.left) unawaited(_playLeftCardAudio(index));
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
      // 改选到另一张单词卡时也播放发音；点同一张取消选中则不重复播放。
      if (side == _CardSide.left && _selectedIndex == index) {
        unawaited(_playLeftCardAudio(index));
      }
      return;
    }
    // 点的是另一侧：尝试把“已选的那张”与“这张”配对。
    final leftIndex = side == _CardSide.left ? index : _selectedIndex;
    final rightIndex = side == _CardSide.left ? _selectedIndex : index;
    _attemptMatch(leftIndex, rightIndex);
  }

  ///
  /// 播放左卡（单词）的发音。
  ///
  /// 词义连连左卡是英文单词，选中即播放，让用户边听读音边找对应释义。
  /// 没有注入发音服务（测试场景）时静默跳过，不阻塞连线交互。
  Future<void> _playLeftCardAudio(int leftIndex) async {
    final player = widget.audioPlayer;
    if (player == null) return;
    final spelling = _currentPairs[leftIndex].spelling;
    if (spelling.trim().isEmpty) return;
    try {
      await player.playRandomChannel(spelling.trim(), widget.accent);
    } catch (error) {
      debugPrint('词义连连播放发音失败：$error');
    }
  }

  ///
  /// 判定一次配对是否成功。
  ///
  /// [leftIndex] 左列下标；[rightIndex] 右列位置（0..4）。
  /// 成功条件：右列该位置对应的左卡下标，正好等于 leftIndex。
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
      } else {
        // 配对失败：连错数 +1。
        _errors += 1;
        // 这一下算在左卡头上：左卡才是用户正在安置的那个单词。等它最终连对时，
        // 结算会看「本局这个词错过没有」，据此调整难度。
        _wrongByLeftIndex[leftIndex] = (_wrongByLeftIndex[leftIndex] ?? 0) + 1;
        // 记下是哪两张卡连错，两张子卡看到属性变化就会自己红框抖动。
        // 以前这里改用 GlobalKey 去调子卡的 shake()，但那个键实际挂在卡片内层的
        // 普通容器上，currentState 永远取不到子卡状态，连错反馈从来没真正播放过。
        _errorLeftIndex = leftIndex;
        _errorRightIndex = rightIndex;
      }
    });
    if (correctLeft == leftIndex) {
      // 这张左卡尘埃落定，记一次「连对」并给这个单词结算。
      unawaited(_recordLeftCard(leftIndex));
    } else {
      // 连错也要留痕：中途退出再进来时，「哪几对已经连上了」全靠回放这些记录，
      // 而且没有这条记录，结算就看不出这个词本局错过。
      unawaited(_recordWrongMatch(leftIndex, rightIndex));
    }
    unawaited(_persist());
    if (correctLeft == leftIndex) {
      // 当前组全部连完：进入下一组或整局完成。
      // 判定用「当前组实际张数」：末组不足 5 张时连满即走，不会空等。
      if (_matchedLeft.length >= _currentPairs.length) _onGroupComplete();
    } else {
      // 抖动播完之前锁住点击，保证这段红色反馈完整可见（补充稿 isProcessing）。
      _lockInputForShake();
    }
  }

  ///
  /// 连错一次时记一条记录。
  ///
  /// [input] 记的是用户**点歪的那条释义**——它才是「你当时选了什么」，
  /// 回看记录时能一眼看出是把哪两个词混淆了。
  Future<void> _recordWrongMatch(int leftIndex, int rightIndex) async {
    final pair = _currentPairs[leftIndex];
    final wordId = pair.wordId;
    // 数据列表里的每一对都来自真实单词与释义，主键缺失只可能是数据异常；
    // 防御性跳过，避免把一条没有归属的脏记录写进数据库。
    if (wordId == null) return;
    // 右列第 rightIndex 张显示的是 pairs[_currentOrder[rightIndex]] 的释义。
    final chosen = _currentPairs[_currentOrder[rightIndex]];
    try {
      await _progress.record(
        wordId: wordId,
        meaningId: pair.meaningId,
        input: chosen.definition,
        isCorrect: false,
      );
    } catch (error) {
      // 写入失败不阻断游戏，最多这一次连错没留痕。
      debugPrint('写入词义连连连错记录失败：$error');
    }
  }

  ///
  /// 一张左卡连对后，记一次点击并给这个单词结算。
  ///
  /// 时机：这张卡刚刚连对，说明用户对这个单词的判断已经尘埃落定。
  /// 结算会看「本局这个词有没有点错过」，据此更新难度与复习时间。
  ///
  /// 没连上的卡（比如超时时还剩两张）不写记录——没练到就不算数。
  Future<void> _recordLeftCard(int leftIndex) async {
    // 「第几组的第几张」才是这张卡的唯一身份，换组后下标会重复。
    final key = '$_groupIndex:$leftIndex';
    // 恢复进度后重连同一张卡不该再写一条，用集合挡住重复。
    if (!_recordedLefts.add(key)) return;
    final pair = _currentPairs[leftIndex];
    final wordId = pair.wordId;
    // 数据列表里的每一对都来自真实单词与释义，主键缺失只可能是数据异常；
    // 防御性跳过，避免把一条没有归属的脏记录写进数据库。
    if (wordId == null) return;
    try {
      // 先记这一次「连对了」；之前的每次连错在发生时就已经记过。
      await _progress.record(
        wordId: wordId,
        meaningId: pair.meaningId,
        input: pair.definition,
        isCorrect: true,
      );
      // 再结算这个词：本局它一次都没错才算这一轮答对。
      await _progress.settle(wordId);
    } catch (error) {
      // 写入失败不该打断正在进行的一局；集合里放回去，
      // 万一后面又连到这张卡还能补写一次。
      _recordedLefts.remove(key);
      debugPrint('写入词义连连记录失败：$error');
    }
  }

  ///
  /// 锁住棋盘点击，等连错抖动播完再解锁并撤掉红色。
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
          // 下标含义随换组变化，上一组的「每张卡错了几次」不能带进新一组。
          // 累计连错数 _errors 不清——它代表整局成败，必须一路累加到结算。
          _wrongByLeftIndex.clear();
        });
        // 新一组整块淡入上移，对应原型的 fade-switch。
        _fadeController.forward(from: 0);
        unawaited(_persist());
      });
    } else {
      // 最后一组也连完：全部卡片操作完一遍，整局结束并判定过关。
      // 必须先停表：结算页展示期间定时器若仍在跑，剩余时间会继续往下掉。
      _stopTimer();
      setState(() => _completed = true);
      _syncPulse();
      unawaited(_finishSession());
    }
  }

  ///
  /// 点击右上角倒计时：本次剩余 +30 秒，并同步把全局设置倒计时 +30 秒。
  ///
  /// 全局设置里的倒计时也要 +30，使“下次进入”默认就多 30 秒。
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
  /// 2.0 起只写两个数：做到第几对、已经花了多少秒。剩下的现场（哪几对连上了、
  /// 错了几次）全部由这一局的点击记录反查得出，不再维护一份会漂移的快照。
  Future<void> _persist() async {
    // 已结算的局不能再被 dispose 时的延迟保存写回「进行中」。
    if (_showSummary) return;
    await _progress.save(cursor: _matchedPairs, elapsed: _elapsedSeconds);
  }

  ///
  /// 本局已用秒数 = 总时长 − 剩余时长。
  ///
  /// 存「已用」而不是「剩余」：点 +30s 加时会把总时长一起抬高，
  /// 只有已用时间在任何加时下都单调递增，续玩时反推剩余永远算得对。
  int get _elapsedSeconds =>
      ((_totalMs - _remainingMs) ~/ 1000).clamp(0, 1 << 30);

  ///
  /// 给这一局结算。
  ///
  /// 判定规则和听音辨义一致：只要把这一局全部卡片操作完一遍（[_completed]
  /// 为 true，即全部组都连完）就算「完成」，中途连错次数只影响结算页展示
  /// 和单词个体难度，不再影响整局成败；只有倒计时耗尽、没能连完全部卡片
  /// （[_completed] 仍为 false）才算「失败」。
  Future<void> _finishSession() => _progress.finish(
    // 全部连完即算过关，不再要求零连错。
    perfect: _completed,
    cursor: _matchedPairs,
    elapsed: _elapsedSeconds,
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
    _stopTimer();
    // 退到后台时停掉呼吸动画，避免无谓的重绘。
    if (_pulseController.isAnimating) _pulseController.stop();
    if (!_showSummary) unawaited(_persist());
  }

  ///
  /// 页面被移出导航栈（返回/退出）时立即冻结进度并停表。
  @override
  void deactivate() {
    // 转场一开始就把计时器停掉，把主线程让给返回动画，避免卡顿。
    _stopTimer();
    super.deactivate();
  }

  /// 页面被重新挂回树时恢复倒计时，兼容返回手势取消等临时离场场景。
  @override
  void activate() {
    super.activate();
    if (!_showSummary) {
      _startTimer();
      _syncPulse();
    }
  }

  @override
  void dispose() {
    // 注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    // 停表并保存当前进度；completed/timedOut 也会在此落盘（首页据此显示状态）。
    _stopTimer();
    // 连错解锁定时器也要取消，避免页面销毁后回调仍在排队。
    _unlockTimer?.cancel();
    _connectController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    unawaited(_persist());
    super.dispose();
  }

  /// 停止并清空倒计时引用，避免把已取消的计时器误当成仍在运行。
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  ///
  /// 构建词义连连页面。
  ///
  /// 骨架整块交给模块模板 [ModuleScaffold]。本页是五个模块里唯一没有下段操作区的
  /// ——棋盘本身就占满中段，所以 `footer` 不传。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return ModuleScaffold(
      header: ModuleHeader(
        leading: ModuleIconButton(
          key: const Key('close-meaning-match'),
          icon: AppGlyph.back,
          alignment: Alignment.centerLeft,
          onTap: () => Navigator.pop(context),
        ),
        title: ModuleProgressLabel(
          textKey: const Key('meaning-match-progress-label'),
          current: _matchedPairs,
          total: _totalPairs,
        ),
        // 右侧不是普通时间文本，而是「点一下 +30 秒」的倒计时按钮。
        trailing: _buildCountdown(tokens),
        // 这条进度条表示**剩余时间**占比，会随倒数一点点变短；
        // 最后 10 秒整条变红，与倒计时文字同步告警。
        progress: _timeRatio,
        progressColor: _isTimeDanger ? AppTokens.danger : AppTokens.primary,
        progressBarKey: const Key('meaning-match-progress'),
      ),
      // 结算页或棋盘二选一。
      body: _showSummary ? _buildSummary() : _buildBoard(tokens),
    );
  }

  // 顶栏那一行（返回键、中间数字进度、进度条）已经整块交给模块模板的
  // ModuleHeader，本页不再自己拼一遍；右上角倒计时因为要接点击加时，
  // 仍由本页自己造，通过 trailing 插槽塞进模板。

  ///
  /// 按 [_countdownStage] 取倒计时文字的颜色。
  ///
  /// 未进入警告阶段时使用 [AppTokens.textMedium]，与听音辨义、看义选词、
  /// 拼写巩固右上角计时的默认色完全一致，四个模块切来切去不会有色差。
  Color _countdownColor(AppTokens tokens) => switch (_countdownStage) {
    _CountdownStage.normal => tokens.textMedium,
    _CountdownStage.warning => AppTokens.warning,
    _CountdownStage.danger => AppTokens.danger,
  };

  ///
  /// 构建右上角可点击的倒计时文本。
  ///
  /// 颜色随剩余时间分三档（默认灰 → 警告橙 → 危险红）；最后 10 秒另外循环播放
  /// “放大到 1.06 倍、淡到 0.8 透明度再回来”的呼吸动画（原型 pulse-danger）。
  Widget _buildCountdown(AppTokens tokens) {
    final isDanger = _isTimeDanger;
    return InkWell(
      key: const Key('meaning-match-countdown'),
      // 结算页不再允许加时。
      onTap: _showSummary ? null : () => unawaited(_addThirtySeconds()),
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.p1,
          vertical: AppSpace.p1,
        ),
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
          child: ModuleTimeLabel(
            // 与另外三个模块右上角的时间共用同一份组件：同样的档位、
            // 同样的等宽数字。本页只多传一个颜色——倒计时会随剩余时间告警，
            // 而它的默认档取的正是那三个模块用的次要文字色。
            text: _formatRemaining(),
            color: _countdownColor(tokens),
          ),
        ),
      ),
    );
  }

  ///
  /// 把剩余秒数格式化成计时文字：不足一小时 mm:ss，满一小时 hh:mm:ss。
  String _formatRemaining() => formatTimerSeconds(_remainingSeconds);

  ///
  /// 构建左右两列棋盘，并在下层铺一张“连线画布”。
  ///
  /// 层次与原型一致：最底下是连线画布（含正中那条竖直虚线），上面才是卡片，
  /// 所以绿色连线会从卡片边缘的小圆点出发，穿过中间那道空档（[MeaningMatchLayout.boardGap]）。
  Widget _buildBoard(AppTokens tokens) {
    // 左列：当前组的实际张数（英文单词）。
    final currentCount = _currentPairs.length;
    final leftCards = <Widget>[
      for (var i = 0; i < currentCount; i += 1)
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
    // 右列：按 _currentOrder 取对应含义，张数与左列一致。
    final rightCards = <Widget>[
      for (var k = 0; k < currentCount; k += 1)
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

    // 两列等宽，中间留一道空档给连线穿过（原型 .matching-grid），
    // 宽度读的是 `boardGap` 那一档，不在这里写死数字。
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
                  lineColor: AppTokens.success,
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
  /// 构建结算页（完成或超时），与其他三个模块共用同一个极简收尾模板
  /// [ModuleSummaryView]：圆形图标底盘 → 标题 → 一行说明 → 返回按钮。
  ///
  /// 统计卡与「再挑战一次」随「结算页统一走简单显示」一起下线，重开入口
  /// 收回首页，想再来一局就从首页入口重新进。
  Widget _buildSummary() {
    final isWin = _completed;
    // 胜负决定主色：赢了用成功绿奖杯，超时用危险红闹钟。
    final accentColor = isWin ? AppTokens.success : AppTokens.danger;

    // 版式整块交给结算页模板 [ModuleSummaryView]，这里只填内容与返回动作。
    return ModuleSummaryView(
      icon: isWin ? AppGlyph.win : AppGlyph.timeUp,
      color: accentColor,
      title: isWin ? '大获全胜！' : '挑战结束',
      subtitle: isWin
          ? '共 $_totalPairs 个单词配对 · 失误 $_errors 次'
          : '已完成 $_matchedPairs 个配对 · 倒计时结束',
      actionKey: const Key('finish-meaningMatch'),
      actionLabel: '返回',
      onAction: () {
        // 先停掉计时与连错解锁，避免转场期间回调还在跑；收尾页只回首页，
        // 不再带「再来一局」的信号弹回。
        _stopTimer();
        _unlockTimer?.cancel();
        _inputLocked = false;
        Navigator.of(context).pop();
      },
    );
  }
}

///
/// 结算页统计卡已抽成公共组件 [ModuleSummaryStatCard]（见
/// `lib/widgets/module_scaffold.dart`）：原来词义连连、拼写巩固、看义选词
/// 各有一个私有的 `_SummaryStatCard`，三份实现画的是同一张卡。
///
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
  final GlobalKey cardKey;

  ///
  /// 卡片显示文本（左列英文 / 右列中文）。
  final String label;

  ///
  /// 是否属于左列（决定锚点圆点画在哪一侧、文字往哪边对齐）。
  final bool isLeftSide;

  ///
  /// 是否被选中（等待配对）。
  final bool isSelected;

  ///
  /// 是否已成功连上（锁定为绿色并划掉文字）。
  final bool isMatched;

  ///
  /// 是否正在播放连错反馈（红框 + 左右甩动）。
  ///
  /// 由父级在配对失败时置为 true，抖动播完后再置回 false。
  final bool isWrong;

  ///
  /// 点击回调。
  final VoidCallback onTap;

  ///
  /// 创建候选卡状态。
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
  late final AnimationController _shakeController;

  ///
  /// 当前抖动水平偏移（像素），由动画进度推算。
  double _shakeOffset = 0;

  ///
  /// 当前抖动旋转角度（弧度），由动画进度推算。
  ///
  /// 生活化解释：补充稿的抖动不只是左右平移，前两下还带一点点歪头，
  /// 这样看起来更像“摇头说不对”，而不是机械地平移。
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
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final state = _visualState;
    // 三种状态各有一个主色，默认态没有主色（用中性描边与文字色）。
    final stateColor = switch (state) {
      _CardVisualState.error => AppTokens.danger,
      _CardVisualState.matched => AppTokens.success,
      _CardVisualState.selected => AppTokens.primary,
      _CardVisualState.idle => null,
    };

    // 描边色：选中用饱和主色（对应补充稿的 primary 实线边），连对/连错则用
    // 主色兑到卡片底色上的“淡色边”（对应 #bbf7d0 与 #fca5a5），不再喧宾夺主。
    final borderColor = switch (state) {
      _CardVisualState.selected => AppTokens.primary,
      _CardVisualState.matched => Color.alphaBlend(
        AppTokens.success.withValues(alpha: _kMatchedBorderAlpha),
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
        BoxShadow(
          color: AppTokens.primary,
          spreadRadius: MeaningMatchLayout.cardBorderSpread,
        ),
        // 第二层：向下 8 像素、模糊 20 像素的蓝色柔光，卡片像浮在纸面上。
        BoxShadow(
          color: AppTokens.primary.withValues(alpha: AppAlpha.a20),
          offset: const Offset(0, MeaningMatchLayout.selectedGlowOffsetY),
          blurRadius: MeaningMatchLayout.selectedGlowBlur,
          spreadRadius: MeaningMatchLayout.selectedGlowSpread,
        ),
      ],
      _ => <BoxShadow>[
        BoxShadow(
          color: tokens.cardShadow,
          offset: const Offset(0, AppShadow.cardOffsetY),
          blurRadius: AppShadow.cardBlur,
        ),
      ],
    };

    // 锚点外圈光晕：选中时最亮最大，连错时是一圈红色薄雾，其余只是一道细描边。
    final anchorHalo = switch (state) {
      _CardVisualState.selected => BoxShadow(
        color: AppTokens.primary.withValues(alpha: AppAlpha.a30),
        spreadRadius: MeaningMatchLayout.anchorSelectedHalo,
      ),
      _CardVisualState.error => BoxShadow(
        color: AppTokens.danger.withValues(alpha: AppAlpha.a24),
        spreadRadius: MeaningMatchLayout.anchorErrorHalo,
      ),
      _CardVisualState.matched => const BoxShadow(
        color: AppTokens.success,
        spreadRadius: MeaningMatchLayout.cardBorderSpread,
      ),
      _CardVisualState.idle => BoxShadow(
        color: tokens.border,
        spreadRadius: MeaningMatchLayout.cardBorderSpread,
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
      borderRadius: BorderRadius.circular(MeaningMatchLayout.optionCardRadius),
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
          horizontal: MeaningMatchLayout.optionCardPaddingHorizontal,
          vertical: MeaningMatchLayout.optionCardPaddingVertical,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            MeaningMatchLayout.optionCardRadius,
          ),
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
            // 左列单词更重、右列释义稍轻，形成主次关系；两档字号相同，
            // 差别只在字重，所以直接换一档字重而不是自己写 fontWeight。
            style: (widget.isLeftSide ? textTheme.fs5Semibold : textTheme.fs5)
                .copyWith(
                  color: labelColor,
                  height: AppLine.lhSm,
                  // 连上的卡片把文字划掉，表示这一对已经消除。
                  decoration: widget.isMatched
                      ? TextDecoration.lineThrough
                      : null,
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
            opacity: widget.isMatched ? MeaningMatchLayout.matchedOpacity : 1.0,
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
  void _drawDivider(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dividerColor
      ..strokeWidth = MeaningMatchLayout.dividerWidth
      ..style = PaintingStyle.stroke;
    // 虚线画在画布水平正中，也就是左右两列之间那道空档的中线。
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
  @override
  bool shouldRepaint(covariant _MatchConnectionPainter old) =>
      old.connections != connections ||
      old.activeConnection != activeConnection ||
      old.activeProgress != activeProgress ||
      old.dividerColor != dividerColor;
}
