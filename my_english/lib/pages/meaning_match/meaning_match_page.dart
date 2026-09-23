import '../../common/toast.dart';
// dart:async 提供 Timer（累计用时与反馈延迟）以及 unawaited。
import 'dart:async';
// dart:math 提供 pi（抖动动画）与 Random（确定性出题，保证续玩时棋盘一致）。
import 'dart:math';
// material.dart 提供全屏页面、进度条、卡片与对话框。
import 'package:flutter/material.dart';
// 所有可见图标统一来自 Tabler，禁止使用 Flutter 内置 Icons。

// 引入全局设计令牌（颜色变量，随亮色/深色主题自动切换）。
import '../../common/theme.dart';
// 引入全局计时格式化，右上角显示累计用时。
import '../../common/date.dart';
// 引入单词数据模型，首页会把当天固定词单传进来。
import '../../models/word.dart';
import '../../models/settlement.dart';
// 引入发音口音枚举。
import '../../store/settings.dart';
// 引入发音服务，选中单词卡时播放读音。
import '../../services/word_audio.dart';
// 引入运行日志：记大题切换、每次配对与结算，事后能对着日志还原整局过程。
import '../../services/app_log.dart';
// 引入统一的进度出口：写进度、记每次点击、结算难度都走它。
import '../review/services/session_progress.dart';
// 引入集中管理的页面布局尺寸。
// 引入模块页面模板：上中下三段骨架、顶栏三个插槽与结算页共用版式。
import '../../widgets/module_scaffold.dart';
import '../../widgets/settlement_summary.dart';
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
    this.questionId,
  });

  ///
  /// 单词主键。
  final int? wordId;

  ///
  /// 这一对用的是这个单词的哪一条释义；写记录时要带上它。
  final int? meaningId;

  /// 左卡对应的实际小题编号，用于独立恢复重复配对。
  final int? questionId;

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
/// 词义连连的进度按含义配对数计算，不能直接套用按单词统计的复习记录，
/// 而必须来自本局保存的会话状态。该类把“总配对数 / 已匹配数 /
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
/// 左列是英文单词、右列是一条中文含义；会话会把所有含义都拆成独立配对，
/// 保证每条含义至少匹配一次。点一张左卡再点一张右卡，若二者对应即连成绿线，
/// 全部连完进入下一组；连错则红框抖动。没有倒计时，离场后可从已匹配的含义继续。
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
/// 管理词义连连的棋盘、累计用时与匹配状态。
///
/// 这里同时驱动两条动画：连线生长与整块棋盘淡入，
/// 因此使用可挂多个 Ticker 的 TickerProviderStateMixin（复数版）。
///
class _MeaningMatchPageState extends State<MeaningMatchPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  ///
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
  /// 本局已经过去的毫秒数；只在页面处于前台且未结算时累加。
  int _elapsedMs = 0;

  ///
  /// 本局是否全部连完。
  bool _completed = false;

  /// 结算页正在把草稿正式应用到词库时，暂时锁住返回与再来一次按钮。
  bool _isCommittingSummary = false;

  ///
  /// 累计用时计时器；页面不在前台时取消，回到前台再启动。
  Timer? _elapsedTimer;

  ///
  /// 连错反馈期间的输入锁（补充稿的 `isProcessing`）。
  ///
  /// 生活化解释：连错后两张卡要红着脸抖 0.4 秒，这段时间里如果还能点别的卡，
  /// 红色会被下一次点击立刻打断，用户根本看不清自己错在哪。上了锁就必须
  /// 让这 0.4 秒播完，反馈才算真正“看得见”。
  bool _inputLocked = false;
  bool _savingMatch = false;
  bool _roundTransitioning = false;
  Timer? _roundAdvanceTimer;

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
  /// 新会话的轮次大小在创建时已经固定，不能再用「组数 × 5」一笔算完；
  /// 这里按每轮实际张数逐组累加，旧版扁平会话才由模型按 5 对兼容切块。
  int _donePairsBefore(int group) {
    var done = 0;
    for (var g = 0; g < group; g += 1) {
      done += _groups[g].length;
    }
    return done;
  }

  ///
  /// 是否展示结算页（所有含义都已完成）。
  bool get _showSummary => _completed;

  ///
  /// 本局已经过去的秒数，供顶栏和会话恢复使用。
  int get _elapsedSeconds => (_elapsedMs ~/ 1000).clamp(0, 1 << 30);

  ///
  /// 顶部进度条的填充比例：已经匹配的含义对数 ÷ 本局全部含义对数。
  double get _progressRatio =>
      _totalPairs > 0 ? (_matchedPairs / _totalPairs).clamp(0.0, 1.0) : 0.0;

  ///
  /// 初始化页面：先确定性出题，再决定是否从会话续玩，最后启动累计用时。
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
    // 第一步：按会话的数据列表还原棋盘（配对在开局时就已经定好并落库）。
    _buildGroups();
    // 第二步：若有可续玩的历史会话则恢复，否则开启新一局。
    _restoreOrStart();
    // 第三步：未结束则启动累计用时；它只用于展示和恢复，不会触发失败。
    if (!_showSummary) _startElapsedTimer();
    // 首帧结束后强制重绘一次：连线要等卡片完成布局才能拿到锚点坐标，
    // 否则“续玩”恢复的已连线在第一帧会因为坐标为空而画不出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _matchedConnections.isNotEmpty) setState(() {});
    });
  }

  ///
  /// 按会话的数据列表还原棋盘，并生成所有分组。
  ///
  /// 「哪个单词配哪条释义」和「这一轮有几对」都在创建会话时写进了数据列表。
  /// 页面只负责读取持久化轮次，再决定右列的显示顺序；不会把动态的 2 对轮次
  /// 重新按 5 对硬切。右列顺序由会话 id 派生的固定种子打乱，所以同一局每次
  /// 进来棋盘与顺序完全一样——中途退出再进，不需要依赖任何内存状态。
  void _buildGroups() {
    final groups = <List<MatchPair>>[];
    final orders = <List<int>>[];
    for (final group in _progress.session.groups) {
      final pairs = <MatchPair>[
        for (final question in group.questions)
          MatchPair(
            questionId: question.id,
            wordId: question.details.first.wordId,
            meaningId: question.details.first.meaningId,
            spelling: question.content.first,
            definition: question.answers.first,
          ),
      ];
      groups.add(pairs);
      final order = List<int>.generate(pairs.length, (i) => i);
      // 固定整数算法保证顺序可重现，不受系统语言和随机数实现升级影响。
      var seed = (_progress.session.id * 31 + group.no) & 0x7fffffff;
      for (var i = order.length - 1; i > 0; i--) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        final other = seed % (i + 1);
        final previous = order[i];
        order[i] = order[other];
        order[other] = previous;
      }
      orders.add(order);
    }
    _groups = groups;
    _rightOrders = orders;
    _totalPairs = groups.fold(0, (sum, group) => sum + group.length);
  }

  /// 左侧小题编号加右侧含义文本足以恢复配对，不保存另一份连线位置。
  void _restoreOrStart() {
    _elapsedMs = _progress.session.elapsed * 1000;
    for (var groupIndex = 0; groupIndex < _groups.length; groupIndex++) {
      final pairs = _groups[groupIndex];
      final connections = <(int, int)>[];
      for (var left = 0; left < pairs.length; left++) {
        final records = _progress.allRecords.where(
          (record) => record.questionId == pairs[left].questionId,
        );
        final correct = records.where((record) => record.isCorrect).lastOrNull;
        if (correct == null) continue;
        final rightPair = pairs.indexWhere(
          (pair) => pair.definition.trim() == correct.input.trim(),
        );
        final right = _rightOrders[groupIndex].indexOf(rightPair);
        if (right >= 0) connections.add((left, right));
      }
      if (connections.length == pairs.length &&
          groupIndex + 1 < _groups.length) {
        continue;
      }
      _groupIndex = groupIndex;
      for (final connection in connections) {
        _matchedLeft.add(connection.$1);
        _matchedRight.add(connection.$2);
        _matchedConnections.add(connection);
      }
      for (var left = 0; left < pairs.length; left++) {
        _wrongByLeftIndex[left] = _progress.allRecords
            .where(
              (record) =>
                  record.questionId == pairs[left].questionId &&
                  !record.isCorrect,
            )
            .length;
      }
      AppLog.i(
        'meaning_match',
        '进入 会话=${_progress.session.id} 大题=${groupIndex + 1}/${_groups.length} '
            '已连=${connections.length}/${pairs.length} '
            '进度=$_matchedPairs/$_totalPairs 卡片=${_describe(pairs)}',
      );
      if (connections.length == pairs.length &&
          groupIndex + 1 == _groups.length) {
        AppLog.i('meaning_match', '恢复时发现最后一大题已连完，直接结算');
        unawaited(_completeSession());
      }
      break;
    }
  }

  /// 一轮卡片的一行文字：`feel→认为|feel→触觉|say→说`，日志里对得上截图。
  String _describe(List<MatchPair> pairs) => pairs
      .map((pair) => '${pair.spelling.trim()}→${pair.definition.trim()}')
      .join('|');

  /// 启动每秒累加用时；归零不会触发任何失败状态。
  void _startElapsedTimer() {
    if (_showSummary || _elapsedTimer != null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _showSummary) return;
      setState(() => _elapsedMs += 1000);
    });
  }

  ///
  /// 点击卡片：管理选中态并尝试配对。
  ///
  /// [side] 被点的卡片在左列还是右列；[index] 在各自列中的下标。
  void _onCardTap(_CardSide side, int index) {
    // 结算页、连错反馈播放期间或已匹配的卡片都不再响应点击。
    if (_showSummary || _inputLocked || _savingMatch || _roundTransitioning) {
      return;
    }
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
    unawaited(_attemptMatch(leftIndex, rightIndex));
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
  Future<void> _attemptMatch(int leftIndex, int rightIndex) async {
    if (_savingMatch ||
        _inputLocked ||
        _matchedLeft.contains(leftIndex) ||
        _matchedRight.contains(rightIndex)) {
      return;
    }
    final left = _currentPairs[leftIndex];
    final right = _currentPairs[_currentOrder[rightIndex]];
    final correct =
        left.spelling.trim().toLowerCase() ==
        right.spelling.trim().toLowerCase();
    _savingMatch = true;
    try {
      await _progress.record(
        wordId: left.wordId!,
        meaningId: left.meaningId,
        questionId: left.questionId,
        input: right.definition,
        isCorrect: correct,
        elapsed: _elapsedSeconds,
      );
    } catch (error) {
      AppLog.e(
        'meaning_match',
        '配对保存失败 大题=${_groupIndex + 1} ${left.spelling}→${right.definition} 原因=$error',
      );
      if (mounted) Toast.show(context, '配对保存失败：$error');
      return;
    } finally {
      _savingMatch = false;
    }
    AppLog.i(
      'meaning_match',
      '配对 大题=${_groupIndex + 1} ${left.spelling}→${right.definition} '
          '${correct ? '对' : '错'} 进度=${_matchedPairs + (correct ? 1 : 0)}/$_totalPairs',
    );
    if (!mounted) return;
    setState(() {
      _selectedSide = null;
      _selectedIndex = -1;
      if (correct) {
        _matchedLeft.add(leftIndex);
        _matchedRight.add(rightIndex);
        _matchedConnections.add((leftIndex, rightIndex));
        _activeConnection = (leftIndex, rightIndex);
        _connectController.forward(from: 0);
      } else {
        _wrongByLeftIndex[leftIndex] = (_wrongByLeftIndex[leftIndex] ?? 0) + 1;
        _errorLeftIndex = leftIndex;
        _errorRightIndex = rightIndex;
      }
    });
    try {
      await _persist();
    } catch (error) {
      // 配对答案已经保存，恢复时能据此还原；游标失败不能锁死已连完的棋盘。
      AppLog.e('meaning_match', '进度保存失败 大题=${_groupIndex + 1} 原因=$error');
      if (mounted) Toast.show(context, '进度保存失败，配对结果已保留：$error');
    }
    if (!mounted) return;
    if (correct && _matchedLeft.length >= _currentPairs.length) {
      _onGroupComplete();
    } else if (!correct) {
      _lockInputForShake();
    }
  }

  /// 保留错误反馈期间的输入锁，避免连续点按覆盖动画。
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
    if (_groupIndex + 1 >= _groups.length) {
      AppLog.i(
        'meaning_match',
        '最后一大题连完 大题=${_groupIndex + 1}/${_groups.length} '
            '进度=$_matchedPairs/$_totalPairs，进入结算',
      );
      unawaited(_completeSession());
      return;
    }
    AppLog.i(
      'meaning_match',
      '大题连完 大题=${_groupIndex + 1}/${_groups.length} 进度=$_matchedPairs/$_totalPairs',
    );
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = Timer(
      const Duration(milliseconds: MeaningMatchLayout.groupAdvanceDelayMs),
      () {
        if (mounted) unawaited(_showNextGroup());
      },
    );
  }

  /// 先让旧配对淡出再换内容，不同时挂两套带相同锚点的棋盘。
  Future<void> _showNextGroup() async {
    if (_roundTransitioning || !mounted) return;
    _roundTransitioning = true;
    try {
      if (!MediaQuery.disableAnimationsOf(context)) {
        await _fadeController
            .animateBack(
              0,
              duration: const Duration(milliseconds: AppDuration.ms100),
            )
            .orCancel;
      }
      if (!mounted) return;
      setState(() {
        _groupIndex++;
        _matchedLeft.clear();
        _matchedRight.clear();
        _matchedConnections.clear();
        _activeConnection = null;
        _selectedSide = null;
        _selectedIndex = -1;
        _errorLeftIndex = -1;
        _errorRightIndex = -1;
        _wrongByLeftIndex.clear();
      });
      AppLog.i(
        'meaning_match',
        '进入 大题=${_groupIndex + 1}/${_groups.length} 张数=${_currentPairs.length} '
            '进度=$_matchedPairs/$_totalPairs 卡片=${_describe(_currentPairs)}',
      );
      final saved = _persist();
      if (MediaQuery.disableAnimationsOf(context)) {
        _fadeController.value = 1;
        await saved;
      } else {
        await Future.wait<void>(<Future<void>>[
          saved,
          _fadeController.forward(from: 0).orCancel,
        ]);
      }
    } on TickerCanceled {
      // 返回页面时取消过渡即可，已保存的配对不受影响。
    } catch (error) {
      AppLog.e('meaning_match', '换题后进度保存失败 大题=${_groupIndex + 1} 原因=$error');
      if (mounted) Toast.show(context, '进度保存失败：$error');
    } finally {
      if (mounted) setState(() => _roundTransitioning = false);
    }
  }

  /// 等待最后一批结算草稿写入后再显示结算页，避免首帧出现空列表。
  Future<void> _completeSession() async {
    _stopElapsedTimer();
    try {
      await _finishSession();
      AppLog.i(
        'meaning_match',
        '本局完成 会话=${_progress.session.id} 大题=${_groups.length} '
            '配对=$_matchedPairs/$_totalPairs 用时=${_elapsedSeconds}s 连错=${_progress.wrongCount}',
      );
      if (mounted) setState(() => _completed = true);
    } catch (error) {
      AppLog.e('meaning_match', '结算保存失败 会话=${_progress.session.id} 原因=$error');
      if (mounted) Toast.show(context, '结算保存失败，重新进入可继续：$error');
    }
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
  /// 给这一局结算。
  ///
  /// 没有倒计时后，词义连连只有在全部含义匹配完成时进入这里；
  /// 普通返回不会把进行中的会话误判为失败。
  Future<void> _finishSession() =>
      _progress.finish(cursor: _matchedPairs, elapsed: _elapsedSeconds);

  ///
  /// App 前后台切换：退后台暂停累计用时并保存，回前台再恢复。
  ///
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_showSummary) _startElapsedTimer();
      return;
    }
    _stopElapsedTimer();
    if (!_showSummary) unawaited(_persist());
  }

  ///
  /// 页面被移出导航栈（返回/退出）时立即冻结累计用时。
  @override
  void deactivate() {
    _stopElapsedTimer();
    super.deactivate();
  }

  /// 页面被重新挂回树时恢复累计用时，兼容返回手势取消等临时离场场景。
  @override
  void activate() {
    super.activate();
    if (!_showSummary) _startElapsedTimer();
  }

  @override
  void dispose() {
    _progress.detach();
    // 注销生命周期监听，避免后台回调访问已释放页面。
    WidgetsBinding.instance.removeObserver(this);
    // 停表并保存当前进度；未完成的局仍保持 active，可从进度继续。
    _stopElapsedTimer();
    // 连错解锁定时器也要取消，避免页面销毁后回调仍在排队。
    _unlockTimer?.cancel();
    _roundAdvanceTimer?.cancel();
    _connectController.dispose();
    _fadeController.dispose();
    unawaited(_persist());
    super.dispose();
  }

  /// 停止并清空累计用时引用，避免回到前台时误以为计时器仍在运行。
  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
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
      canPop: !_showSummary,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showSummary) unawaited(_leaveSummary());
      },
      header: ModuleHeader(
        leading: ModuleIconButton(
          key: const Key('close-meaning-match'),
          icon: AppGlyph.back,
          alignment: Alignment.centerLeft,
          onTap: _leaveSummary,
        ),
        title: ModuleProgressLabel(
          textKey: const Key('meaning-match-progress-label'),
          current: _matchedPairs,
          total: _totalPairs,
        ),
        // 右侧显示累计用时，与其它不限时复习模块保持一致。
        trailing: ModuleTimeLabel(
          textKey: const Key('meaning-match-elapsed'),
          text: formatTimerSeconds(_elapsedSeconds),
        ),
        // 进度条表示已经完成的含义配对比例。
        progress: _progressRatio,
        progressBarKey: const Key('meaning-match-progress'),
      ),
      // 结算页或棋盘二选一。
      body: _showSummary ? _buildSummary() : _buildBoard(tokens),
    );
  }

  // 顶栏那一行（返回键、中间数字进度、累计用时与进度条）已经整块交给
  // ModuleHeader，本页不再自己拼一遍。

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
  /// 构建全部含义配对完成后的统一结算页。
  Widget _buildSummary() {
    final items = <SettlementWordItem>[];
    final seen = <int>{};
    for (final word in widget.words) {
      final id = word.id;
      if (id == null || !seen.add(id)) continue;
      final draft = _progress.settlementFor(id);
      // 只有全部含义完成后才会进入结算页；没有草稿的异常数据按现场错误状态兜底。
      final correct = draft?.isCorrect ?? !_progress.progressOf(id).hasAnyWrong;
      items.add(
        SettlementWordItem(
          word: word.spelling,
          isCorrect: correct,
          // 词义连连不按单词计时，结算页这一行不显示用时。
          usedTime: null,
          // 本轮开始时的难度：草稿里记着就用草稿的，拿不到就退回到单词当前的难度。
          difficultyBefore: draft?.difficultyBefore ?? word.difficulty,
          recentResults:
              draft?.recentResults ?? <bool?>[correct, null, null, null, null],
          streak: draft != null && draft.streak > 0 ? draft.streak : null,
          initialAdjust: difficultyAdjustFromDelta(
            draft?.suggestedAdjustment ?? 0,
          ),
        ),
      );
    }
    return SettlementSummary(
      key: const Key('settlement-meaningMatch'),
      items: items,
      isBusy: _isCommittingSummary,
      // 词义连连无法按单词拆分时间，所以结算页不显示用时。
      showTotalElapsed: false,
      onAdjust: (index, adjust) async {
        final id = widget.words[index].id;
        if (id != null) await _progress.adjustSettlement(id, adjust);
      },
      onRetry: () => unawaited(_leaveSummary(retry: true)),
      onConfirm: _leaveSummary,
    );
  }

  /// 提交结算结果后离开本页；再来一次由首页重新创建会话。
  Future<void> _leaveSummary({bool retry = false}) async {
    if (!_showSummary) {
      Navigator.of(context).pop();
      return;
    }
    if (_isCommittingSummary) return;
    setState(() => _isCommittingSummary = true);
    try {
      await _progress.commitSettlement();
      if (mounted) Navigator.of(context).pop(retry);
    } catch (error) {
      debugPrint('提交词义连连结算失败：$error');
      AppLog.e('meaning_match', '提交结算失败 会话=${_progress.session.id} 原因=$error');
      if (mounted) {
        setState(() => _isCommittingSummary = false);
        Toast.show(context, '保存结算失败，请重试：$error');
      }
    }
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
      // 默认态与白底卡片、候选词、描边按钮、输入框同一档控件描边。
      _CardVisualState.idle => tokens.rowBorder,
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

    // 投影：默认态不画投影，和全站白底卡片一致，只靠一圈描边立在页面上；
    // 连对的卡片彻底去掉投影（补充稿 box-shadow: none）“沉”下去；
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
      _ => const <BoxShadow>[],
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
