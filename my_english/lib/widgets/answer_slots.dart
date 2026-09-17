// dart:async 提供 Timer（入场动画的递增延迟）和 scheduleMicrotask（完成回调）。
import 'dart:async';

// material.dart 提供 Wrap、Stack、AnimationController 等基础绘制与动画能力。
import 'package:flutter/material.dart';

// 引入设计令牌：下划线、光标、文字与动画时长全部从总表取值。
import '../common/theme.dart';
// 引入统一的闪烁光标：光标节奏与前后台停表由它自己管理。
import 'blinking_caret.dart';

///
/// 「答案槽位」的尺寸与动画表。
///
/// 字母格的数值沿用 `ui/听音拼写1.html` 原型（原 `LetterSlotLayout`，值一个
/// 没改）；含义空位的下划线、光标数值沿用原 `PosMeaningPanelLayout`。两处
/// 现在真的是同一张表，不再靠注释互相提醒「改动请同步」。
///
abstract final class AnswerSlotsLayout {
  ///
  /// 单个字母格的宽度；下划线和字母都在这个宽度内对齐。
  static const double letterWidth = 24;

  ///
  /// 单个字母格高度，包含字母、下划线与闪烁光标。
  static const double letterHeight = 40;

  ///
  /// 相邻字母格之间的水平间距，对应 HTML 的 `column-gap: 7px`。
  static const double letterGap = AppSpace.p2;

  ///
  /// 多行字母格之间的垂直间距，对应 HTML 的 `row-gap: 10px`。
  static const double letterRunGap = AppSpace.p2;

  ///
  /// 字母字号，对应原型短词的视觉大小。
  static const double letterTextSize = AppFont.fs1;

  ///
  /// 固定宽度模式下，空格这种「静态字符」占字母格宽度的比例。
  ///
  /// 空格不画任何东西，只留一段比字母窄的空隙，让 `ice cream` 一眼能看出
  /// 是两个词。
  static const double staticSpaceWidthFactor = 0.55;

  ///
  /// 固定宽度模式下，撇号、连字符这类「静态字符」占字母格宽度的比例。
  ///
  /// 这些符号本身很窄，按整格宽度摆会在两侧留出明显空洞。
  static const double staticGlyphWidthFactor = 0.65;

  ///
  /// 下划线粗细。字母格与含义空位共用这一个值——用户眼里两处是同一种「填空」。
  static const double underlineHeight = AppStroke.mark;

  ///
  /// 当前待填下划线外围的淡蓝色焦点边框宽度。
  ///
  /// 作用是让用户一眼看出下一笔应该落在哪一条下划线上。
  /// 取值来由（为什么不是 2、也不是 4）见总表 [AppSize.underlineGlow]。
  static const double underlineFocusSpread = AppSize.underlineGlow;

  ///
  /// 当前待填下划线焦点边框的透明度。
  static const double underlineFocusAlpha = AppAlpha.a10;

  ///
  /// 光标粗细。
  static const double caretWidth = AppSize.caretWidth;

  ///
  /// 光标高度（固定宽度模式下取满，自动宽度模式下按可用高度封顶）。
  ///
  /// 总表值是字母字号（[letterTextSize]）的 2/3，光标只到字母三分之二高，
  /// 不再顶到字母顶部、也不会盖住 g / y 这类带尾巴字母的笔画。
  static const double caretHeight = AppSize.caretHeight;

  ///
  /// 文字底边、光标底边与下划线之间留出的距离，避免笔画压在横线上。
  static const double caretGap = AppSpace.p1;

  ///
  /// 单个文字入场动画的完整时长。
  ///
  /// 动画分成「放大并显现」和「回落到正常大小」两段，使用较短时长，
  /// 让连续输入时字母能紧跟用户的按键节奏。
  static const int entryDurationMs = AppDuration.ms100;

  ///
  /// 入场动画第一段的放大终点。
  static const double entryOvershootScale = 1.2;

  ///
  /// 入场动画第一段所占的比例，剩余部分用于回落到正常大小。
  static const double entryOvershootPortion = 0.7;

  ///
  /// 同一批填入的多个槽位之间，入场动画依次错开的时间。
  ///
  /// 看义选词答对后整词一次填入：第一个字母立刻弹出，后面每个晚这么多
  /// 毫秒，像一串珠子依次落下。拼写巩固逐字敲键盘时一批只有一个字母，
  /// 延迟自然是 0，不会让用户觉得字母慢半拍。
  static const int entryStaggerMs = 30;

  ///
  /// 递增延迟的封顶步数：第 9 个及以后的槽位与第 8 个同时出现。
  ///
  /// `internationalization` 这种二十个字母的长词，不封顶要拖半秒多才能
  /// 全部亮出来，比页面切到下一题还慢。
  static const int entryStaggerMaxSteps = 8;

  ///
  /// 整排颜色状态（答对绿 / 答错红 / 常态）切换的过渡时长。
  static const int toneDurationMs = AppDuration.ms160;

  ///
  /// 一次「整词填入 + 变色」最长要多久才能全部播完。
  ///
  /// 等 [AnswerSlots.onSettled] 的页面可以拿它兜底：万一通知没来（例如
  /// 这一排在动画中途被移出画面），最多等这么久也往下走，不会卡死。
  static const int maxSettleMs =
      entryDurationMs + entryStaggerMaxSteps * entryStaggerMs + toneDurationMs;
}

///
/// 下划线在槽位被填充后的去留。
///
enum AnswerSlotLine {
  ///
  /// 一直显示：字母模式。填入后下划线不消失，只从蓝色变成浅灰。
  always,

  ///
  /// 填充即隐：含义模式。含义揭开后整块就是普通文字，不再画下划线。
  hideWhenFilled,
}

///
/// 整排槽位的颜色状态，由外部页面根据答题结果决定，单格不自己判断。
///
enum AnswerSlotTone {
  ///
  /// 常态：已填浅灰线、当前格蓝线、未到的格浅灰线，文字取正文色。
  neutral,

  ///
  /// 答对：下划线与文字一起转绿。
  correct,

  ///
  /// 答错：下划线与文字一起转红。
  wrong,
}

///
/// 一个槽位的数据。
///
/// 对应伪代码里的 `<answer>`：`text` 是永远垫在底下的真实答案（透明、只当
/// 尺子），`shown` 是填入后真正显示的文字，`filled` 决定它现在是不是已填。
///
class AnswerSlotCell {
  ///
  /// 创建一个需要用户作答的槽位。
  const AnswerSlotCell({
    required this.text,
    this.shown,
    this.filled = false,
    this.entryToken,
    this.suffix = '',
    this.key,
  }) : isStatic = false;

  ///
  /// 创建一个「静态字符」槽位：撇号、连字符、空格这类不需要作答的字符。
  ///
  /// 它从一开始就显示、不画下划线、光标永远跳过它。三个模块以前各自处理
  /// 这类字符，听音辨义干脆把它过滤掉了，`o'clock` 的撇号在那里就不见了；
  /// 现在统一走这一种。
  const AnswerSlotCell.static(this.text, {this.key})
    : shown = null,
      filled = true,
      entryToken = null,
      suffix = '',
      isStatic = true;

  ///
  /// 真实答案。自动宽度模式下它决定槽位的宽高；固定宽度模式下只是备份，
  /// [shown] 为空时显示它。
  final String text;

  ///
  /// 填入后显示的文字；为空时显示 [text]。
  ///
  /// 拼写巩固里用户可能敲错字母：显示的是用户敲的，撑宽度的仍是正确答案。
  final String? shown;

  ///
  /// 这一格现在是否已填。静态字符恒为 true。
  final bool filled;

  ///
  /// 这次填入对应的唯一编号；为 null 表示不播入场动画（例如恢复现场）。
  ///
  /// 该编号用于区分「同一个位置的新内容」和「之前已经显示过的内容」：
  /// 编号一变就重新播一次入场动画，不依赖整排销毁重建。
  final int? entryToken;

  ///
  /// 跟在这一格后面、始终显示的静态后缀，例如多条含义之间的分隔符。
  ///
  /// 它和本格拼成一个整体排队换行，分隔符永远不会被挤到下一行行首。
  final String suffix;

  ///
  /// 这一格的 Widget key，供测试与外部定位。
  final Key? key;

  ///
  /// 是否是静态字符。
  final bool isStatic;

  ///
  /// 是否是还没填的作答格；光标只会落在这种格子上。
  bool get isBlank => !isStatic && !filled;
}

///
/// 全App统一的「答案槽位」：一排带下划线、闪烁光标和入场动画的格子。
///
/// 对应伪代码里的 `<answers>`。五处填空都用它：
///
/// - 听音辨义・选单词：全部空格，光标在第一个字母上；
/// - 听音辨义・选含义：含义模式，答对一条原地揭开一条；
/// - 拼写巩固・拼单词：逐字敲键盘填入，答错整排变红、答对整排变绿；
/// - 拼写巩固・词性及含义：含义模式的只读态，全部已填、不播动画；
/// - 看义选词：选中正确候选后整词一次填入，字母依次弹出。
///
/// 它只负责这一排本身：光标落在哪、每格什么颜色、动画什么时候播。
/// 「填了什么、对不对、什么时候进下一题」仍由页面决定。
///
/// 完成通知：每次入场动画或颜色过渡全部播完，会调用一次 [onSettled]。
/// 页面可以用它代替「估一个毫秒数再跳题」，不用也没关系——组件不管外部
/// 听不听，动画都会完整播完。
///
class AnswerSlots extends StatefulWidget {
  ///
  /// 创建一排答案槽位。
  ///
  /// 默认就是字母模式：固定宽度、下划线一直显示、按字母格间距排列。
  /// 含义模式传 `line: hideWhenFilled`、`cellWidth: null`（按文字自动定宽），
  /// 并给出含义用的文字样式。
  const AnswerSlots({
    required this.cells,
    this.line = AnswerSlotLine.always,
    this.tone = AnswerSlotTone.neutral,
    this.cellWidth = AnswerSlotsLayout.letterWidth,
    this.textStyle,
    this.showCaret = true,
    this.activeIndex,
    this.alignment = WrapAlignment.center,
    this.spacing = AnswerSlotsLayout.letterGap,
    this.runSpacing = AnswerSlotsLayout.letterRunGap,
    this.onSettled,
    super.key,
  });

  ///
  /// 判断一个字符是否是 ASCII 英文字母；不是字母的都当静态字符处理。
  static bool isLetter(String character) => _letterPattern.hasMatch(character);

  static final RegExp _letterPattern = RegExp(r'^[A-Za-z]$');

  ///
  /// 这一排的全部槽位，顺序即展示顺序。
  final List<AnswerSlotCell> cells;

  ///
  /// 下划线在填充后是否保留。
  final AnswerSlotLine line;

  ///
  /// 整排的颜色状态。切换时会做一次短过渡，过渡结束算作一次「完成」。
  final AnswerSlotTone tone;

  ///
  /// 每格的固定宽度；传 null 则按每格真实答案的文字宽度自动定宽。
  ///
  /// 逐字敲键盘的场景必须固定宽：敲错的字母和正确答案宽度不同，自动定宽
  /// 会让整排随输入抖动。
  final double? cellWidth;

  ///
  /// 文字样式（含常态文字色）；不传时使用字母格默认样式。
  final TextStyle? textStyle;

  ///
  /// 是否显示闪烁光标。输入被锁住、或这一排不是当前作答对象时传 false。
  final bool showCaret;

  ///
  /// 光标所在格的下标；不传时自动落在第一个还没填的作答格上。
  final int? activeIndex;

  ///
  /// 整排的水平对齐方式。
  final WrapAlignment alignment;

  ///
  /// 相邻格之间的水平间距。
  final double spacing;

  ///
  /// 多行之间的垂直间距。
  final double runSpacing;

  ///
  /// 所有正在播放的入场动画与颜色过渡都结束后调用一次。
  final VoidCallback? onSettled;

  ///
  /// 实际带光标的格子下标；没有则为 null。
  int? get effectiveActiveIndex {
    if (!showCaret) return null;
    if (activeIndex != null) return activeIndex;
    for (var index = 0; index < cells.length; index += 1) {
      if (cells[index].isBlank) return index;
    }
    return null;
  }

  @override
  State<AnswerSlots> createState() => _AnswerSlotsState();
}

///
/// 整排的状态：一个颜色过渡控制器，加上「还有几个动画没播完」的账本。
///
class _AnswerSlotsState extends State<AnswerSlots>
    with SingleTickerProviderStateMixin {
  ///
  /// 颜色状态过渡：值从 0 走到 1，各格在旧状态色和新状态色之间插值。
  late final AnimationController _toneController;

  ///
  /// 过渡起点对应的颜色状态。
  late AnswerSlotTone _previousTone;

  ///
  /// 每一格入场动画的起始延迟（毫秒），按「同一批」依次递增。
  final Map<int, int> _entryDelays = <int, int>{};

  ///
  /// 正在播放（含等待延迟）的入场动画个数。
  int _runningEntries = 0;

  ///
  /// 颜色过渡是否正在进行。
  bool _toneRunning = false;

  ///
  /// 是否已经排了一次「核对账本并通知」的微任务，避免重复通知。
  bool _settleScheduled = false;

  @override
  void initState() {
    super.initState();
    _previousTone = widget.tone;
    _toneController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AnswerSlotsLayout.toneDurationMs),
      // 初始就停在终点：没有过渡时各格直接显示当前状态色。
      value: 1,
    )..addStatusListener(_onToneStatus);
  }

  @override
  void didUpdateWidget(covariant AnswerSlots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tone != oldWidget.tone) {
      _previousTone = oldWidget.tone;
      _toneRunning = true;
      _toneController.forward(from: 0);
    }
    _planEntries(oldWidget.cells);
  }

  @override
  void dispose() {
    _toneController.dispose();
    super.dispose();
  }

  ///
  /// 找出这次更新里「新填入」的格子，按顺序分配递增延迟。
  ///
  /// 判定标准与单格自己的判定完全一致：作答格、已填、有编号，且编号和
  /// 上一次不同。首次构建从不播动画：恢复现场、进入新题时画面直接就位。
  void _planEntries(List<AnswerSlotCell> oldCells) {
    // 上一批的延迟已经在各格起播时读走了，这里清掉，免得旧值串到下一批。
    _entryDelays.clear();
    var step = 0;
    for (var index = 0; index < widget.cells.length; index += 1) {
      final cell = widget.cells[index];
      if (!_startsEntry(cell)) continue;
      final old = index < oldCells.length ? oldCells[index] : null;
      if (old != null && old.entryToken == cell.entryToken) continue;
      final cappedStep = step < AnswerSlotsLayout.entryStaggerMaxSteps
          ? step
          : AnswerSlotsLayout.entryStaggerMaxSteps;
      _entryDelays[index] = cappedStep * AnswerSlotsLayout.entryStaggerMs;
      step += 1;
    }
  }

  ///
  /// 这一格是否需要播入场动画。
  static bool _startsEntry(AnswerSlotCell cell) =>
      !cell.isStatic && cell.filled && cell.entryToken != null;

  ///
  /// 单格开始播入场动画时记一笔。
  void _onEntryStart() {
    _runningEntries += 1;
  }

  ///
  /// 单格播完（或被中途取消）时销一笔，账本清零就通知外部。
  void _onEntryDone() {
    if (_runningEntries > 0) _runningEntries -= 1;
    _checkSettled();
  }

  ///
  /// 颜色过渡走到终点时销账。
  void _onToneStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_toneRunning) return;
    _toneRunning = false;
    _checkSettled();
  }

  ///
  /// 所有动画都结束才通知。
  ///
  /// 通知放到下一个微任务里、并在那时再核对一次账本：一来避免在构建或
  /// 销毁过程中直接触发页面的 setState，二来同一格「先销账再重新起播」
  /// 的瞬间账本会短暂归零，等微任务时它已经重新记上了，不会误报。
  void _checkSettled() {
    if (_runningEntries > 0 || _toneRunning || _settleScheduled) return;
    if (widget.onSettled == null) return;
    _settleScheduled = true;
    scheduleMicrotask(() {
      _settleScheduled = false;
      if (!mounted || _runningEntries > 0 || _toneRunning) return;
      widget.onSettled?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.effectiveActiveIndex;
    return Wrap(
      alignment: widget.alignment,
      spacing: widget.spacing,
      runSpacing: widget.runSpacing,
      children: [
        for (var index = 0; index < widget.cells.length; index += 1)
          AnswerSlot(
            key: widget.cells[index].key,
            cell: widget.cells[index],
            line: widget.line,
            cellWidth: widget.cellWidth,
            textStyle: widget.textStyle,
            tone: widget.tone,
            previousTone: _previousTone,
            toneProgress: _toneController,
            isActive: index == activeIndex,
            entryDelayMs: _entryDelays[index] ?? 0,
            onEntryStart: _onEntryStart,
            onEntryDone: _onEntryDone,
          ),
      ],
    );
  }
}

///
/// 一个槽位：下划线 + 文字 + 光标三层。
///
/// 对应伪代码里的 `<answer>`。不画矩形边框，只保留底部下划线和当前位置的
/// 闪烁竖线，避免整排看起来像一组占位输入框。
///
/// 一般不直接使用，由 [AnswerSlots] 排成一排；对外公开是为了让测试能读到
/// 某一格的 [cell] 数据。
///
class AnswerSlot extends StatefulWidget {
  ///
  /// 创建一个槽位。
  const AnswerSlot({
    required this.cell,
    required this.line,
    required this.cellWidth,
    required this.textStyle,
    required this.tone,
    required this.previousTone,
    required this.toneProgress,
    required this.isActive,
    required this.entryDelayMs,
    required this.onEntryStart,
    required this.onEntryDone,
    super.key,
  });

  ///
  /// 这一格的数据。
  final AnswerSlotCell cell;

  ///
  /// 下划线在填充后是否保留。
  final AnswerSlotLine line;

  ///
  /// 固定宽度；null 表示按文字自动定宽。
  final double? cellWidth;

  ///
  /// 文字样式；null 表示字母格默认样式。
  final TextStyle? textStyle;

  ///
  /// 当前颜色状态。
  final AnswerSlotTone tone;

  ///
  /// 颜色过渡的起点状态。
  final AnswerSlotTone previousTone;

  ///
  /// 颜色过渡进度（0 = 全是旧状态色，1 = 全是新状态色）。
  final Animation<double> toneProgress;

  ///
  /// 是否是下一个等待填入的位置：会画焦点光晕和闪烁光标。
  final bool isActive;

  ///
  /// 入场动画开始前等待的毫秒数。
  final int entryDelayMs;

  ///
  /// 入场动画开始（含进入等待）时通知整排。
  final VoidCallback onEntryStart;

  ///
  /// 入场动画结束或被取消时通知整排。
  final VoidCallback onEntryDone;

  @override
  State<AnswerSlot> createState() => _AnswerSlotState();
}

///
/// 单格状态：只管自己的入场动画。
///
class _AnswerSlotState extends State<AnswerSlot>
    with SingleTickerProviderStateMixin {
  ///
  /// 入场动画：0 → 1.2 → 1 的弹出（拼写巩固敲键盘那一档），全部槽位共用。
  late final AnimationController _entry;

  ///
  /// 递增延迟的等待定时器。
  Timer? _delayTimer;

  ///
  /// 是否已经向整排报过「开始」、还没报「结束」。
  bool _running = false;

  ///
  /// 这一格的文字是否要套入场动画（播过或正在播）。
  /// 首次构建就已填的内容属于恢复画面，直接显示，不套动画。
  bool _animated = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AnswerSlotsLayout.entryDurationMs),
      value: 1,
    )..addStatusListener(_onEntryStatus);
    // 首次构建不播动画：有编号也直接显示，恢复现场时画面就位不闪。
  }

  @override
  void didUpdateWidget(covariant AnswerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cell = widget.cell;
    if (_shouldEnter(cell)) {
      // 编号一变就重新播：清空后再次输入也一定从第 0 帧开始。
      if (cell.entryToken != oldWidget.cell.entryToken) _start();
    } else if (_running || _animated) {
      // 退格清掉、或内容变成不需要动画的形态：停掉并恢复成静止显示。
      _cancel();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _finish();
    _entry.dispose();
    super.dispose();
  }

  ///
  /// 作答格、已填、有编号，才播入场动画。
  static bool _shouldEnter(AnswerSlotCell cell) =>
      !cell.isStatic && cell.filled && cell.entryToken != null;

  ///
  /// 开始一次入场：先把上一次没播完的销账，再按延迟起播。
  void _start() {
    _finish();
    _delayTimer?.cancel();
    _delayTimer = null;
    _running = true;
    _animated = true;
    widget.onEntryStart();
    // 等待期间停在第 0 帧：文字完全透明、缩放为 0。
    _entry.value = 0;
    if (widget.entryDelayMs <= 0) {
      _entry.forward(from: 0);
      return;
    }
    _delayTimer = Timer(Duration(milliseconds: widget.entryDelayMs), () {
      _delayTimer = null;
      if (!mounted) return;
      _entry.forward(from: 0);
    });
  }

  ///
  /// 取消入场：停表、直接跳到终点，并把账销掉。
  void _cancel() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _entry.stop();
    _entry.value = 1;
    _animated = false;
    _finish();
  }

  ///
  /// 向整排报「结束」；重复调用只报一次。
  void _finish() {
    if (!_running) return;
    _running = false;
    widget.onEntryDone();
  }

  ///
  /// 动画自然走到终点时销账。
  void _onEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  ///
  /// 这一格现在要不要画下划线：静态字符从不画；
  /// 「填充即隐」模式下已填的格子也不画。
  bool get _showLine =>
      !widget.cell.isStatic &&
      (widget.line == AnswerSlotLine.always || !widget.cell.filled);

  ///
  /// 字母格默认文字样式：24 号半粗、行高 1，与原字母格完全相同。
  TextStyle _letterStyle(AppTokens tokens) => TextStyle(
    color: tokens.text,
    fontSize: AnswerSlotsLayout.letterTextSize,
    height: AppLine.lh1,
    fontWeight: AppWeight.semibold,
  );

  ///
  /// 某个颜色状态下这一格的下划线颜色。
  Color _lineColor(AnswerSlotTone tone, AppTokens tokens) {
    switch (tone) {
      case AnswerSlotTone.wrong:
        return AppTokens.danger;
      case AnswerSlotTone.correct:
        return AppTokens.success;
      case AnswerSlotTone.neutral:
        break;
    }
    if (widget.cell.filled) return tokens.text.withValues(alpha: AppAlpha.a36);
    if (widget.isActive) return AppTokens.primary;
    return tokens.check;
  }

  ///
  /// 某个颜色状态下这一格的文字颜色。
  Color _textColor(AnswerSlotTone tone, AppTokens tokens, TextStyle base) {
    switch (tone) {
      case AnswerSlotTone.wrong:
        return AppTokens.danger;
      case AnswerSlotTone.correct:
        return AppTokens.success;
      case AnswerSlotTone.neutral:
        break;
    }
    if (widget.cell.isStatic) return tokens.textSecondary;
    return base.color ?? tokens.text;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final base = widget.textStyle ?? _letterStyle(tokens);
    return AnimatedBuilder(
      animation: widget.toneProgress,
      builder: (context, _) {
        final progress = widget.toneProgress.value;
        final lineColor = Color.lerp(
          _lineColor(widget.previousTone, tokens),
          _lineColor(widget.tone, tokens),
          progress,
        )!;
        final textColor = Color.lerp(
          _textColor(widget.previousTone, tokens, base),
          _textColor(widget.tone, tokens, base),
          progress,
        )!;
        final style = base.copyWith(color: textColor);
        final body = widget.cellWidth == null
            ? _buildAuto(style, lineColor)
            : _buildFixed(widget.cellWidth!, style, lineColor);
        if (widget.cell.suffix.isEmpty) return body;
        // 后缀（分隔符）和本格拼成一个整体排队换行，永远不会落到下一行行首。
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: body),
            Text(widget.cell.suffix, style: base),
          ],
        );
      },
    );
  }

  ///
  /// 固定宽度模式：字母格。文字底对齐在「下划线 + 间隙」之上。
  ///
  /// 这里**只固定底部**，不给文字写高度：字号 24、行高 1 的行盒是 24 高，
  /// 若压到 16 会被裁掉下半截。底部对齐后字母顶端自然向上展开，缩放动画
  /// 放大时溢出也在 Stack clip:none 下安全可见。
  Widget _buildFixed(double cellWidth, TextStyle style, Color lineColor) {
    final cell = widget.cell;
    final width = cell.isStatic
        ? cellWidth *
              (cell.text == ' '
                  ? AnswerSlotsLayout.staticSpaceWidthFactor
                  : AnswerSlotsLayout.staticGlyphWidthFactor)
        : cellWidth;
    const textBottom =
        AnswerSlotsLayout.underlineHeight + AnswerSlotsLayout.caretGap;
    // 固定宽度下空格只留空隙，不放文字节点。
    final shown = cell.isStatic && cell.text == ' ' ? null : _buildShown(style);
    return SizedBox(
      width: width,
      height: AnswerSlotsLayout.letterHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_showLine)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildLine(lineColor),
            ),
          if (shown != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: textBottom,
              child: Align(alignment: Alignment.bottomCenter, child: shown),
            ),
          if (widget.isActive)
            Positioned(
              left: (width - AnswerSlotsLayout.caretWidth) / 2,
              bottom: textBottom,
              // 光标是全 App 共用组件，自己管闪烁节奏和前后台停表；
              // 位置一移动，这里就换成新的一个，光标天然从「亮」开始。
              child: const BlinkingCaret(
                width: AnswerSlotsLayout.caretWidth,
                height: AnswerSlotsLayout.caretHeight,
              ),
            ),
        ],
      ),
    );
  }

  ///
  /// 自动宽度模式：含义空位。
  ///
  /// 核心技巧：**真实答案就垫在底层**，只是被设成完全透明不绘制。它照常
  /// 参与排版，所以这块空白的宽高与揭开后一模一样；揭开时只是把显示层
  /// 放上去，尺寸不变，用户看到的就是含义「无声无息地填了进去」。
  ///
  /// 这里不用「和卡片同色的实心遮罩」去盖文字：那样一旦卡片底色变成半透明
  /// 或渐变，答案就会透出来提前泄题。透明度为 0 不依赖任何颜色，更安全。
  Widget _buildAuto(TextStyle style, Color lineColor) {
    final cell = widget.cell;
    if (cell.isStatic) return Text(cell.text, style: style);
    final shown = _buildShown(style);
    return Stack(
      // 焦点扩散会画到边界外一点，不能裁掉。
      clipBehavior: Clip.none,
      children: [
        // 不带 Positioned 的这一个孩子决定 Stack 的尺寸，也就是「尺子」。
        // 已填时显示层自己就是尺子（缩放动画不改变排版尺寸），
        // 这样同一段文字不会同时存在「透明一份 + 显示一份」。
        shown ??
            ExcludeSemantics(
              child: Opacity(
                opacity: AppAlpha.none,
                child: Text(cell.text, style: style),
              ),
            ),
        if (_showLine)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildLine(lineColor),
          ),
        if (widget.isActive)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom:
                AnswerSlotsLayout.underlineHeight + AnswerSlotsLayout.caretGap,
            // 光标高度跟随这条含义的实际可用高度，不给空位强行套一个固定高度。
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.bottomCenter,
                child: BlinkingCaret(
                  width: AnswerSlotsLayout.caretWidth,
                  height: constraints.maxHeight
                      .clamp(1.0, AnswerSlotsLayout.caretHeight)
                      .toDouble(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  ///
  /// 底部下划线；当前待填的那条额外带一圈淡蓝色扩散边框。
  ///
  /// blurRadius 为 0 + spreadRadius，等价于 CSS 的 `box-shadow: 0 0 0 3px`：
  /// 一圈实心淡蓝描边而不是模糊光晕，只包住横线本身。
  Widget _buildLine(Color color) {
    return Container(
      height: AnswerSlotsLayout.underlineHeight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.roundedPill),
        boxShadow: widget.isActive
            ? [
                BoxShadow(
                  color: AppTokens.primary.withValues(
                    alpha: AnswerSlotsLayout.underlineFocusAlpha,
                  ),
                  blurRadius: AppShadow.none,
                  spreadRadius: AnswerSlotsLayout.underlineFocusSpread,
                ),
              ]
            : null,
      ),
    );
  }

  ///
  /// 显示层的文字；空位返回 null。已填且有编号的套入场动画。
  Widget? _buildShown(TextStyle style) {
    final cell = widget.cell;
    if (cell.isStatic) return Text(cell.text, style: style);
    if (!cell.filled) return null;
    final text = Text(cell.shown ?? cell.text, style: style);
    if (!_animated) return text;
    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) {
        final progress = _entry.value;
        final overshootPortion = AnswerSlotsLayout.entryOvershootPortion;
        final scale = progress <= overshootPortion
            ? AnswerSlotsLayout.entryOvershootScale *
                  (progress / overshootPortion)
            : AnswerSlotsLayout.entryOvershootScale +
                  (1 - AnswerSlotsLayout.entryOvershootScale) *
                      ((progress - overshootPortion) / (1 - overshootPortion));
        final opacity = progress <= overshootPortion
            ? progress / overshootPortion
            : 1.0;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            // 缩放中心固定在文字区域的底部中心，与下划线的位置关系不变。
            alignment: Alignment.bottomCenter,
            scale: scale,
            child: child,
          ),
        );
      },
      child: text,
    );
  }
}
