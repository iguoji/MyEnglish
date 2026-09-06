// =============================================================================
// lib/widgets/qwerty_keyboard.dart
//
// 通用 26 键 QWERTY 键盘组件（复刻 ui/听音拼写1.html 的键盘区）。
//
// ─────────────────────────────────────────────────────────────────────────
// 一、键盘长什么样（结构）
// ─────────────────────────────────────────────────────────────────────────
//  第一行  q w e r t y u i o p            （10 颗字母键）
//  第二行   a s d f g h j k l             （9 颗字母键）
//  第三行   z x c v b n m  ⌫              （7 颗字母键 + 1 颗删除键）
//
//  三行从上到下纵向排成一列，每一行都水平居中；
//  第三行的删除键紧跟在字母 m 之后，比字母键宽一点（默认 1.45 倍）。
//
//  整个组件是一个「灰蓝色背景的面板」：全套配色都从设计令牌 AppTokens 取
//  （keyPanel / keyFace / keyInk / keyDelete* / keyShadow），浅色主题的面板底
//  复刻原型的 `--tblr-keybg`（#E9EDF2）；字母键是纯白圆角键帽、删除键是稍深的
//  灰蓝，键帽下方带一条 1px 投影，按下时整颗键轻微缩小（0.96 倍）并变灰，
//  与原型 `.key:active` 的手感一致。深色主题下整套颜色由令牌自动换成暗色调。
//
// ─────────────────────────────────────────────────────────────────────────
// 二、布局细节（为什么这么排）
// ─────────────────────────────────────────────────────────────────────────
//  - 先用第一行 10 颗字母键计算出统一键宽，第二、三行完全沿用这个键宽，
//    因此所有字母键的宽高一致；只有删除键在第三行按比例稍微加宽。
//  - 第一行会根据键盘内部可用宽度自适应，三行整体居中排列，左右留白由面板
//    内边距统一负责，不设任何「绝对定位 / 悬浮」。
//
// ─────────────────────────────────────────────────────────────────────────
// 三、对外事件（尽量通用）
// ─────────────────────────────────────────────────────────────────────────
//  [onLetterTap]  点任意一颗字母键（回调参数为小写字母 a~z）。
//  [onDeleteTap]  单击删除键。
//  [onDeleteRepeat] 长按删除键时按固定周期反复触发（默认每 90ms 一次，
//                  长按 420ms 后开始）。不传则长按自动重复调用 [onDeleteTap]。
//  [enabled]      可选：false 时整块键盘不响应任何点击。
//
//  组件只负责「发出按键消息」，不关心业务：什么时候允许输入、答对了怎么
//  处理，全由使用页面自己决定，因此任何拼写 / 听写类页面都能直接复用。
//
// ─────────────────────────────────────────────────────────────────────────
// 四、使用示例
// ─────────────────────────────────────────────────────────────────────────
//  QwertyKeyboard(
//    onLetterTap: (letter) => _appendLetter(letter),   // 拼进当前单词
//    onDeleteTap: _undoLastLetter,                     // 退一格
//  )
//
// 常见的放置方式（放在屏幕底部，由页面自己排版）：
//  Column(children: [ ...题目区..., Align(
//    alignment: Alignment.bottomCenter, child: QwertyKeyboard(...))])
// =============================================================================

// dart:async 提供 Timer：删除键长按后要按周期连续发「退格」消息。
import 'dart:async';

// material.dart 提供指针事件、容器、动画与主题。
import 'package:flutter/material.dart';

// 所有可见图标统一来自 Tabler；删除键默认用 backspace 图标。

// 引入设计令牌：键帽的全套配色取自 AppTokens，图标尺寸取自 AppIcon 台阶，
// 键帽字号取自 AppFont 台阶——键盘自己不再私藏任何颜色或尺寸数字。
import '../common/theme.dart';

// ---------------------------------------------------------------------------
// 以下是键帽 / 面板的固定尺寸与默认手感参数，集中在此便于统一调整。
// 数值来源：ui/听音拼写1.html 的 .key / #keyboard 样式。
// ---------------------------------------------------------------------------

/// 字母键高度（原型 `.key` 的 h-[46px]；46 也高于 44 的最小触控标准）。
const double _kKeyHeight = 46;

/// 同一行相邻两颗键的间距（原型键行 gap-[5px]，5 并入 6 这一档）。
const double _kKeyGap = AppSpace.p2;

/// 相邻两行的纵向间距（原型键行容器 space-y-[7px]，7 并入 6 这一档）。
const double _kRowGap = AppSpace.p2;

/// 键帽圆角（原型 `.key` 的 rounded-[9px]，9 并入 10 这一档）。
const double _kKeyRadius = AppRadius.roundedLg;

/// 删除键宽度 = 字母键宽度 × 这个倍数（原型删除键 flex-[1.45]）。
const double _kDeleteKeyRatio = 1.45;

/// 整个灰蓝面板的圆角；页面想做成直角贴边可传 0。
const double _kPanelRadius = AppRadius.roundedXl;

/// 键帽下沿那道「立体感」阴影往下偏移多少。
///
/// 生活化解释：真实键盘的键帽是凸起的，底边会压出一道很窄的暗影。这里只往下挪
/// 一个像素、不做任何扩散（见 [_kKeyShadowBlur]），得到的就是一条硬边细线——
/// 键按下去时这条线会被取消，视觉上就像键帽真的沉下去了。
const double _kKeyShadowOffsetY = AppShadow.cardOffsetY;

/// 键帽阴影的扩散范围：0 表示**完全不扩散**。
///
/// 常规投影会向四周晕开一片，那是「这张纸浮在上面」的感觉；键帽要的是
/// 「这颗键是凸起的实体」，所以刻意不晕开，只留一条实边。
const double _kKeyShadowBlur = AppShadow.none;

/// 按下反馈动画时长（原型 `.key` 的 transition 0.08s，收敛到 100 毫秒这一档）。
const int _kPressMs = AppDuration.ms100;

/// 键帽底色过渡时长（原型 background-color 过渡 0.12s，同样收敛到 100 毫秒）。
///
/// 和上面的缩放动画取同一档之后，「变小」和「变灰」从此同时收尾，
/// 不再像原来那样一前一后差 40 毫秒。
const int _kPressColorMs = AppDuration.ms100;

/// 长按删除键多久后开始连发（原型 holdT 420ms）。
const int _kDeleteHoldDelayMs = 420;

/// 长按连发期间每隔多久发一次退格（原型 holdI 90ms）。
const int _kDeleteRepeatMs = 90;

/// 点击结束后保留按下画面的最短时间。
///
/// 手机快速点击时，按下和抬起事件可能在同一帧里连续到达；如果立即清掉
/// 按下状态，屏幕还没来得及绘制就已经恢复原样，用户就会感觉「完全没反馈」。
/// 这里让按下画面至少留在屏幕上一小段时间，保证短按也能看见原型效果。
const int _kPressMinimumVisibleMs = AppDuration.ms100;

/// 按下后手指滑出多远就算「取消本次按键」。
///
/// 生活化解释：手指按下时轻微抖动是正常的（就算一次点击），但滑出一段距离
/// 就说明手指是「划走」而不是「点一下」——这时松手不该触发输入，否则在键盘
/// 上快速滑动页面时会被误当成一连串按键。
const double _kSlipThreshold = 14;

/// 三行按键的字母串；第三行的删除键在组件里单独拼接。
const List<String> _kRows = <String>['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

/// 删除键的内部标识，只用于区分按下、抬起和长按连发状态。
const String _kDeleteKeyLabel = 'delete';

// ---------------------------------------------------------------------------
// 组件本体
// ---------------------------------------------------------------------------

///
/// 通用 26 键 QWERTY 键盘。
///
/// 完整的布局细节、事件说明与使用示例见本文件头部的大段注释；
/// 这里只概括要点：
///
/// - 三行字母键（qwertyuiop / asdfghjkl / zxcvbnm）+ 第三行末尾一颗删除键，
///   每行水平居中，字母键宽高统一、删除键宽 1.45 倍；
/// - 整体是一块灰蓝色背景的普通容器（无任何悬浮 / 定位语义），
///   放在哪里由使用页面的布局决定；
/// - 对外只发声事件：点字母、删字符（含长按连删）。
class QwertyKeyboard extends StatefulWidget {
  ///
  /// 创建一个 26 键键盘。
  const QwertyKeyboard({
    super.key,
    this.enabled = true,
    this.edgeToEdge = false,
    this.onLetterTap,
    this.onDeleteTap,
    this.onDeleteRepeat,
    this.deleteRepeatDelay = const Duration(milliseconds: _kDeleteHoldDelayMs),
    this.deleteRepeatInterval = const Duration(milliseconds: _kDeleteRepeatMs),
  });

  ///
  /// false 时整块键盘不响应点击（视觉上变淡），默认 true。
  final bool enabled;

  ///
  /// 是否去掉面板的左右、底部留白和圆角，让键盘贴住父级边缘。
  ///
  /// 生活化解释：普通场景像一张悬浮键盘卡片；开启后像把键盘嵌进屏幕
  /// 底部，特别适合需要连续输入的拼写页面。
  final bool edgeToEdge;

  ///
  /// 点任意一颗字母键（含 26 颗中的全部）；参数是小写字母 a~z。
  final ValueChanged<String>? onLetterTap;

  ///
  /// 单击删除键。
  final VoidCallback? onDeleteTap;

  ///
  /// 长按删除键进入连发后，每周期调一次的回调；为空则自动重复调 [onDeleteTap]。
  final VoidCallback? onDeleteRepeat;

  ///
  /// 长按删除键多久后开始连发。
  final Duration deleteRepeatDelay;

  ///
  /// 连发期间每隔多久发一次退格。
  final Duration deleteRepeatInterval;

  /// 根据当前主题返回键盘面板颜色。
  ///
  /// 页面在系统手势导航区域也使用这个颜色，避免键盘结束后出现一条突兀的
  /// 白色或黑色空带；颜色来源和键盘面板本身保持单一，后续调整只需改一处。
  static Color panelColor(BuildContext context) {
    return AppTokens.of(context).keyPanel;
  }

  /// 创建键盘状态。
  @override
  State<QwertyKeyboard> createState() => _QwertyKeyboardState();
}

///
/// 键盘的可变状态：当前被手指按住的键和删除键的长按定时器。
///
class _QwertyKeyboardState extends State<QwertyKeyboard> {
  ///
  /// 当前被按住的键（小写字母或 [_kDeleteKeyLabel]）；null 表示没有键被按住。
  ///
  /// 同一时刻物理上只会有一根手指按住一颗键，所以用一个值就够了。
  String? _downKey;

  /// 手指按下时的屏幕坐标：用来判断之后滑了多远。
  Offset? _downPosition;

  /// 手指是否已经滑出「算一次点击」的距离；滑出后松手不触发按键。
  bool _slidOut = false;

  ///
  /// 删除键是否已经进入「长按连发」状态。
  ///
  /// 用来区分这次抬起算「单击」还是「长按结束」：还没进入连发就抬起 = 单击。
  bool _deleteHolding = false;

  ///
  /// 长按开始的延时定时器：按住 420ms 才开始连发，避免误触。
  Timer? _holdTimer;

  ///
  /// 连发周期定时器：进入连发后每 90ms 发一次退格。
  Timer? _repeatTimer;

  /// 松手后的按下画面复位定时器，避免快速点击时反馈被同一帧吞掉。
  Timer? _pressReleaseTimer;

  ///
  /// 释放长按相关定时器，页面销毁时必须清干净，避免定时器泄漏。
  void _stopDeleteTimers() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _deleteHolding = false;
  }

  /// 延迟清除按下状态，让非常快的点击也能稳定显示按下反馈。
  void _scheduleKeyRelease() {
    _pressReleaseTimer?.cancel();
    _pressReleaseTimer = Timer(
      const Duration(milliseconds: _kPressMinimumVisibleMs),
      () {
        _pressReleaseTimer = null;
        _handleKeyUp();
      },
    );
  }

  /// 页面销毁：取消定时器并释放动画控制器。
  @override
  void dispose() {
    _stopDeleteTimers();
    _pressReleaseTimer?.cancel();
    super.dispose();
  }

  // ===== 以下为指针状态机：按下 / 滑动 / 抬起 / 取消 =====

  /// 手指按下某颗键：记下起点并让这颗键进入「按下」视觉。
  void _handleKeyDown(String key, Offset position) {
    _pressReleaseTimer?.cancel();
    _pressReleaseTimer = null;
    _downPosition = position;
    _slidOut = false;
    setState(() => _downKey = key);
  }

  /// 手指移动：滑出阈值距离后标记为「划走」，松手不再算一次点击。
  void _handleKeyMove(Offset position) {
    final start = _downPosition;
    if (start == null || _slidOut) return;
    if ((position - start).distance > _kSlipThreshold) _slidOut = true;
  }

  /// 手指抬起：清除按下状态（是否触发按键由各键自己的抬起回调判断）。
  void _handleKeyUp() {
    _downPosition = null;
    setState(() => _downKey = null);
  }

  /// 指针事件被系统打断（如来电）：只清状态，不触发任何按键。
  void _handleKeyCancel() {
    _pressReleaseTimer?.cancel();
    _pressReleaseTimer = null;
    _downPosition = null;
    setState(() => _downKey = null);
  }

  // ===== 以下为三行的布局构建 =====

  ///
  /// 构建整块键盘：灰蓝面板 + 三行按键，每行水平居中。
  @override
  Widget build(BuildContext context) {
    // 按当前主题取一套键帽颜色（亮 = 复刻原型灰蓝，暗 = 暗色调）；
    // 明暗判断只在 AppTokens.of 里做一次，键盘本身不再关心当前是哪套主题。
    final tokens = AppTokens.of(context);
    // 整块键盘在禁用时整体变淡，一眼能看出「现在不能输入」。
    return Opacity(
      opacity: widget.enabled ? 1 : AppAlpha.a56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.keyPanel,
          borderRadius: widget.edgeToEdge
              ? BorderRadius.zero
              : BorderRadius.circular(_kPanelRadius),
        ),
        // 普通场景保留面板四周的呼吸空间；贴边场景把左右留白交给键盘内部，
        // 让外层底部区域可以完整铺满屏幕，同时保证按键不会贴住屏幕边缘。
        child: Padding(
          padding: widget.edgeToEdge
              ? const EdgeInsets.fromLTRB(
                  AppSpace.p2,
                  AppSpace.p2,
                  AppSpace.p2,
                  AppSpace.p0,
                )
              : const EdgeInsets.fromLTRB(
                  AppSpace.p2,
                  AppSpace.p3,
                  AppSpace.p2,
                  AppSpace.p3,
                ),
          // 只根据第一行计算一次键宽，后面两行完全复用这个结果。
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 第一行有 10 颗键和 9 道键缝，剩余宽度平均分给 10 颗字母键。
              final keyWidth =
                  (constraints.maxWidth - 9 * _kKeyGap) / _kRows.first.length;
              // 删除键只比字母键宽一点；它仍然使用同一套高度和视觉样式。
              final deleteWidth = keyWidth * _kDeleteKeyRatio;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  for (
                    var rowIndex = 0;
                    rowIndex < _kRows.length;
                    rowIndex += 1
                  ) ...[
                    if (rowIndex > 0) const SizedBox(height: _kRowGap),
                    _buildRow(_kRows[rowIndex], keyWidth, deleteWidth, tokens),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  ///
  /// 构建一行按键：字母键沿用第一行算出的统一宽度，最后一行末尾再接删除键。
  ///
  /// 生活化解释：第一行先决定珠子的大小，后面两行使用同样大小的珠子，
  /// 只是第三行最后再放一颗稍大的删除键。
  Widget _buildRow(
    String letters,
    double keyWidth,
    double deleteWidth,
    AppTokens tokens,
  ) {
    final children = <Widget>[];
    for (final letter in letters.split('')) {
      // 键缝只加在键与键之间，所有字母键都使用第一行算出的统一宽度。
      if (children.isNotEmpty) children.add(const SizedBox(width: _kKeyGap));
      children.add(_buildLetterKey(letter, keyWidth, tokens));
    }
    final isLastRow = letters == _kRows.last;
    if (isLastRow) {
      children.add(const SizedBox(width: _kKeyGap));
      children.add(_buildDeleteKey(deleteWidth, tokens));
    }
    // 行宽由按键本身决定，外层 Column 的 center 负责把第二、三行居中。
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  ///
  /// 根据当前是否按下决定键帽底色。
  ///
  /// [press] 是被按住的底色：删除键比字母键深一档（tokens.keyDeletePressFace）。
  Color _faceColor({
    required bool isDown,
    required Color normal,
    required Color press,
  }) {
    if (isDown) return press;
    return normal;
  }

  ///
  /// 构建一颗字母键。
  ///
  /// [keyWidth] 来自第一行的统一计算；所有字母键保持相同宽高。
  Widget _buildLetterKey(String letter, double keyWidth, AppTokens tokens) {
    final isDown = _downKey == letter;
    // 键帽配色：平常是白底深字，按下时变灰。
    final face = _faceColor(
      isDown: isDown,
      normal: tokens.keyFace,
      press: tokens.keyPressFace,
    );
    return _buildKeyShell(
      key: Key('qwerty-key-$letter'),
      semanticLabel: letter,
      face: face,
      ink: tokens.keyInk,
      isDown: isDown,
      width: keyWidth,
      isDeleteKey: false,
      onDown: (position) {
        if (!widget.enabled) return;
        _handleKeyDown(letter, position);
      },
      onUp: () {
        // 抬起且没有滑出才算一次点击：此时才发字母消息。
        if (widget.enabled && !_slidOut) widget.onLetterTap?.call(letter);
        _scheduleKeyRelease();
      },
    );
  }

  ///
  /// 构建删除键：支持单击退一格，长按 420ms 后每 90ms 连发。
  Widget _buildDeleteKey(double deleteWidth, AppTokens tokens) {
    final isDown = _downKey == _kDeleteKeyLabel;
    final face = _faceColor(
      isDown: isDown,
      normal: tokens.keyDeleteFace,
      press: tokens.keyDeletePressFace,
    );
    return _buildKeyShell(
      key: const Key('qwerty-key-delete'),
      semanticLabel: '删除',
      face: face,
      ink: tokens.keyDeleteInk,
      isDown: isDown,
      width: deleteWidth,
      isDeleteKey: true,
      onDown: (position) {
        if (!widget.enabled) return;
        _handleKeyDown(_kDeleteKeyLabel, position);
        // 长按连发：按住不动 420ms 后才开始，短按不受影响。
        _holdTimer = Timer(widget.deleteRepeatDelay, () {
          // 手指已经滑走或抬起就不进入连发（抬起时定时器已被取消，
          // 这里主要防「按下后滑出、仍按住不放」的误连发）。
          if (!mounted || _slidOut || _downKey != _kDeleteKeyLabel) return;
          _deleteHolding = true;
          // 进入连发的第一下立刻删一个，之后按周期继续。
          widget.onDeleteRepeat?.call();
          widget.onDeleteTap?.call();
          _repeatTimer = Timer.periodic(widget.deleteRepeatInterval, (_) {
            // 手指中途抬起 / 滑走 / 系统打断时立刻停发：防止后台一直删。
            if (!mounted || _downKey != _kDeleteKeyLabel) {
              _repeatTimer?.cancel();
              _repeatTimer = null;
              return;
            }
            widget.onDeleteRepeat?.call();
            widget.onDeleteTap?.call();
          });
        });
      },
      onUp: () {
        // 抬起前先记下是否已经进入连发：进入过就不算单击，避免多删一格。
        final wasHolding = _deleteHolding;
        _stopDeleteTimers();
        if (widget.enabled && !wasHolding && !_slidOut) {
          widget.onDeleteTap?.call();
        }
        _scheduleKeyRelease();
      },
      // 指针被系统打断：连发定时器必须停，否则会一直删下去。
      onCancel: _stopDeleteTimers,
    );
  }

  ///
  /// 键帽的公共外壳：指针事件 + 按下缩放 + 底色 + 文字 / 图标。
  ///
  /// 所有键共用这一个构建方法，字母键与删除键只差宽度、图标与事件。
  ///
  /// [onDown] 收到手指按下的坐标，用于状态机记录起点；
  /// [onCancel] 是删除键独有的「打断长按」清理，字母键不传。
  Widget _buildKeyShell({
    required Key key,
    required String semanticLabel,
    required Color face,
    required Color ink,
    required bool isDown,
    required double width,
    required bool isDeleteKey,
    required void Function(Offset position)? onDown,
    required VoidCallback onUp,
    VoidCallback? onCancel,
  }) {
    // 键帽内容：字母键放字母，删除键放 Tabler 退格图标。
    final Widget content = isDeleteKey
        ? Icon(AppGlyph.backspace, size: AppIcon.i20, color: ink)
        : Text(
            // 原型对字母做了 uppercase，键帽上统一显示大写，观感更「键盘」。
            semanticLabel.toUpperCase(),
            // 键帽字号读 18 号半粗那一档（`fs3Semibold`）：原型写的是
            // text-[17px]，17 并入 18 这一档，全站再没有第二个 17。
            style: Theme.of(context).textTheme.fs3Semibold.copyWith(color: ink),
          );
    // 键帽本体：圆角底 + 底部 1px 投影（原型 box-shadow），宽高固定统一。
    // 按下时立即去掉投影，模拟原型中「键帽压到面板上」的视觉效果。
    final Widget keyFaceWidget = AnimatedContainer(
      duration: const Duration(milliseconds: _kPressColorMs),
      curve: Curves.ease,
      width: width,
      height: _kKeyHeight,
      decoration: BoxDecoration(
        color: face,
        borderRadius: BorderRadius.circular(_kKeyRadius),
        boxShadow: isDown
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: AppTokens.of(context).keyShadow,
                  offset: const Offset(0, _kKeyShadowOffsetY),
                  blurRadius: _kKeyShadowBlur,
                ),
              ],
      ),
      child: Center(child: content),
    );
    // 完整复刻原型 `.key:active`：按下时向下 1px 并缩小到 0.96 倍，
    // 松手后在 100ms 内回弹；只改变这一颗键，不影响同一行其它键的位置。
    final Widget pressed = AnimatedContainer(
      duration: const Duration(milliseconds: _kPressMs),
      curve: Curves.ease,
      transform: isDown
          ? (Matrix4.identity()
              ..translateByDouble(0.0, 1.0, 0.0, 1.0)
              ..scaleByDouble(0.96, 0.96, 0.96, 1.0))
          : Matrix4.identity(),
      transformAlignment: Alignment.center,
      child: keyFaceWidget,
    );
    return Listener(
      key: key,
      // 无障朗读：让读屏软件把键帽读成字母 / 删除，而不是一串英文类名。
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => onDown?.call(event.position),
      // 按下后手指移动：滑出阈值即取消本次点击（见状态机说明）。
      onPointerMove: (event) => _handleKeyMove(event.position),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) {
        _handleKeyCancel();
        onCancel?.call();
      },
      child: Semantics(
        label: semanticLabel,
        button: true,
        excludeSemantics: true,
        child: pressed,
      ),
    );
  }
}
