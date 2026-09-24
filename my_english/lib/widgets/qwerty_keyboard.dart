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
//  - 每颗键在键盘里的位置由 [_KeyboardGeometry] 按同一套算法算出来：
//    画按键气泡、判断「手指滑到了哪颗键」都用这一份，两边永远对得上。
//
// ─────────────────────────────────────────────────────────────────────────
// 三、按键手感（触感、气泡、按错了滑过去改）
// ─────────────────────────────────────────────────────────────────────────
//  每颗键（字母键和删除键）都在「手指按下」的那一刻震一下，用的是与候选词
//  点击同一档的轻震动（HapticFeedback.lightImpact）——触屏没有键程，只能靠
//  震动补上「我按到了」这件事；强度与全站其它「点一下」保持同一档，不会出现
//  键盘震得比候选词更重的手感断层。
//
//  字母键按下时弹出 iPhone 键盘那种「一体气泡」：气泡的下半截正好盖住按下的
//  那颗键，往上用两段平滑的弧线放宽成一个圆角的「头」，头里是放大的字母。
//  整个气泡是一笔画出的一圈轮廓、一层阴影，看起来像按键自己长高了，而不是在
//  键上叠了一块矩形再粘一个三角。贴着屏幕左右边缘的键（Q、P 等），气泡的头
//  会自动往里偏，「脖子」仍然对准按键，不会被屏幕切掉。
//
//  按错了可以不松手，直接滑到正确的键上：手指滑到哪颗字母键，气泡就跟到哪颗
//  键，松手时输入的是手指最后停留的那颗键。滑到键盘外面、或者滑到删除键上
//  再松手，这一下作废、什么都不输入。气泡只负责「给人看」，不拦截任何触摸，
//  所以它盖住上一排的按键时，也不会挡住手指滑过去。
//
//  删除键不弹气泡：按下时照旧缩小变灰；按下后滑出一小段距离就算取消本次删除，
//  避免手指划过键盘时误删。长按删除键进入连发后，每删掉一格再震一次，作为
//  「已经删了几个」的节奏反馈。
//
// ─────────────────────────────────────────────────────────────────────────
// 四、对外事件（尽量通用）
// ─────────────────────────────────────────────────────────────────────────
//  [onLetterTap]  输入一颗字母（回调参数为小写字母 a~z）：手指从字母键上松开时
//                 发出，字母是手指松开那一刻所在的键。
//  [onDeleteTap]  单击删除键。
//  [onDeleteRepeat] 长按删除键时按固定周期反复触发（默认每 90ms 一次，
//                  长按 420ms 后开始）。不传则长按自动重复调用 [onDeleteTap]。
//  [enabled]      可选：false 时整块键盘不响应任何点击。
//
//  组件只负责「发出按键消息」，不关心业务：什么时候允许输入、答对了怎么
//  处理，全由使用页面自己决定，因此任何拼写 / 听写类页面都能直接复用。
//
// ─────────────────────────────────────────────────────────────────────────
// 五、使用示例
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

// dart:math 提供 max / min：计算气泡的左右边界和手指离按键的距离。
import 'dart:math' as math;

// material.dart 提供指针事件、容器、动画与主题。
import 'package:flutter/material.dart';

// services.dart 提供 HapticFeedback：按下键帽时给一次轻震动。
import 'package:flutter/services.dart';

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

/// 松手后保留按下画面（含气泡）的最短时间。
///
/// 手机快速点击时，按下和抬起事件可能在同一帧里连续到达；如果立即清掉
/// 按下状态，屏幕还没来得及绘制就已经恢复原样，用户就会感觉「完全没反馈」。
/// 这里让按下画面至少留在屏幕上一小段时间，保证短按也能看见反馈。
const int _kPressMinimumVisibleMs = AppDuration.ms100;

/// 删除键按下后手指滑出多远就算「取消本次删除」。
///
/// 生活化解释：手指按下时轻微抖动是正常的（就算一次点击），但滑出一段距离
/// 就说明手指是「划走」而不是「点一下」——这时松手不该删字。字母键不用这条：
/// 字母键滑到哪颗键就算哪颗键，见文件头「按错了滑过去改」。
const double _kSlipThreshold = 14;

/// 手指落在两颗键之间的缝里时，离最近那颗键不超过这个距离，就仍算按在它上面。
///
/// 取一道键缝的宽度：键缝里的任何位置都归到左右（或上下）最近的键，手指从
/// 一颗键滑向另一颗键时气泡不会在缝里闪没；再往外就算滑出了键盘。
const double _kSlideSlop = _kKeyGap;

/// 气泡的「头」比键帽左右各宽出多少。
const double _kPopupSideExtra = 12;

/// 气泡「头」的高度：放大字母就画在这一块里。
const double _kPopupHeadHeight = 54;

/// 头部两侧收窄成键帽宽度的那段弧线有多高；越高，收腰越平缓。
const double _kPopupShoulderHeight = 14;

/// 气泡头部的圆角。
const double _kPopupHeadRadius = AppRadius.roundedXl;

/// 贴边的键，气泡的头最多伸进面板左右留白多少。
///
/// 面板左右留白是 8 像素，这里最多用掉 6 像素，离屏幕边缘始终留 2 像素。
const double _kPopupEdgeAllowance = 6;

/// 气泡投影的悬浮高度：比键帽那道 1 像素实边更浮一些，一眼看出它在最上层。
const double _kPopupElevation = 4;

/// 收腰弧线的控制点位置（占弧线高度的比例）。
///
/// 两端的切线都是竖直的：上接头部的竖边、下接键帽的竖边，接缝处没有折角。
/// 0.55 让弧线的中段走得最顺，既不像直线斜切，也不会鼓成一个包。
const double _kPopupCurve = 0.55;

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
  /// 输入一颗字母；参数是小写字母 a~z，即手指松开时所在的那颗键。
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
/// 一根手指从按下到松开的状态。
///
/// 两只手快速交替打字时，前一根手指还没松开、后一根已经按下，是很常见的事，
/// 所以每根手指各记各的，互不覆盖。
class _KeyTouch {
  _KeyTouch({required this.onDelete, required this.key, required this.origin});

  /// 这根手指是不是从删除键上按下去的：删除键和字母键走两套规则。
  final bool onDelete;

  /// 手指此刻所在的键：字母、[_kDeleteKeyLabel]，或 null（已经滑出键盘）。
  ///
  /// 字母键这一项会跟着手指变；删除键始终是删除键，只用 [slidOut] 判断取消。
  String? key;

  /// 手指按下时的屏幕坐标：删除键用它判断手指滑出了多远。
  final Offset origin;

  /// 删除键专用：手指是否已经滑出「算一次点击」的距离。
  bool slidOut = false;
}

///
/// 键盘内部（去掉面板留白之后）每颗键的位置，按可用宽度现算。
///
/// 和真实排版用的是同一套算法：第一行 10 颗键决定键宽，每行水平居中，
/// 第三行末尾接一颗 1.45 倍宽的删除键。画气泡、判断手指滑到了哪颗键都靠它。
class _KeyboardGeometry {
  const _KeyboardGeometry._({
    required this.width,
    required this.keyWidth,
    required this.deleteWidth,
    required this.rects,
  });

  /// 按键盘内部可用宽度算出每颗键的位置。
  factory _KeyboardGeometry(double width) {
    // 第一行有 10 颗键和 9 道键缝，剩余宽度平均分给 10 颗字母键。
    final keyWidth =
        (width - _kKeyGap * (_kRows.first.length - 1)) / _kRows.first.length;
    // 删除键只比字母键宽一点；它仍然使用同一套高度和视觉样式。
    final deleteWidth = keyWidth * _kDeleteKeyRatio;
    final rects = <String, Rect>{};
    for (var row = 0; row < _kRows.length; row += 1) {
      final letters = _kRows[row];
      final isLastRow = row == _kRows.length - 1;
      final rowWidth =
          keyWidth * letters.length +
          _kKeyGap * (letters.length - 1) +
          (isLastRow ? _kKeyGap + deleteWidth : 0.0);
      final top = (_kKeyHeight + _kRowGap) * row;
      var left = (width - rowWidth) / 2;
      for (final letter in letters.split('')) {
        rects[letter] = Rect.fromLTWH(left, top, keyWidth, _kKeyHeight);
        left += keyWidth + _kKeyGap;
      }
      if (isLastRow) {
        rects[_kDeleteKeyLabel] = Rect.fromLTWH(
          left,
          top,
          deleteWidth,
          _kKeyHeight,
        );
      }
    }
    return _KeyboardGeometry._(
      width: width,
      keyWidth: keyWidth,
      deleteWidth: deleteWidth,
      rects: rects,
    );
  }

  /// 键盘内部可用宽度。
  final double width;

  /// 统一的字母键宽度。
  final double keyWidth;

  /// 删除键宽度。
  final double deleteWidth;

  /// 每颗键（字母与删除键）在键盘内部坐标系里的矩形。
  final Map<String, Rect> rects;

  /// 找出 [point] 落在哪颗键上。
  ///
  /// 正好在键上就是这颗键；落在键缝里就归最近的那颗键；离所有键都超过
  /// [_kSlideSlop] 说明手指已经滑出键盘，返回 null。
  String? keyAt(Offset point) {
    String? nearest;
    var nearestDistance = double.infinity;
    for (final entry in rects.entries) {
      final rect = entry.value;
      if (rect.contains(point)) return entry.key;
      final dx = math.max(
        0.0,
        math.max(rect.left - point.dx, point.dx - rect.right),
      );
      final dy = math.max(
        0.0,
        math.max(rect.top - point.dy, point.dy - rect.bottom),
      );
      final distance = math.max(dx, dy);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = entry.key;
      }
    }
    return nearestDistance <= _kSlideSlop ? nearest : null;
  }
}

///
/// 键盘的可变状态：每根手指按在哪颗键上、删除键的长按定时器，以及松手后
/// 短暂保留的按下画面。
///
class _QwertyKeyboardState extends State<QwertyKeyboard> {
  ///
  /// 正按在键盘上的手指，键是系统给每根手指的编号。
  ///
  /// 用 Map 的插入顺序区分先后：越靠后越是最近按下的手指，气泡跟着它走。
  final Map<int, _KeyTouch> _touches = <int, _KeyTouch>{};

  ///
  /// 刚松手、还要多保留一会儿按下画面的键（字母或 [_kDeleteKeyLabel]）。
  String? _lingerKey;

  /// 清除 [_lingerKey] 的定时器。
  Timer? _lingerTimer;

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

  /// 三行按键所在区域：把手指的屏幕坐标换算成键盘内部坐标时要用到它。
  final GlobalKey _keyAreaKey = GlobalKey();

  ///
  /// 释放长按相关定时器，页面销毁时必须清干净，避免定时器泄漏。
  void _stopDeleteTimers() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _deleteHolding = false;
  }

  ///
  /// 按下键帽时给一次触感反馈。
  ///
  /// 生活化解释：触屏没有实体键程，手指按下去没有任何「咔哒」的手感，
  /// 只能靠一下轻震动补上。这里用的是与候选词点击同一档的轻震动
  /// （[HapticFeedback.lightImpact]），整个 App 的「点一下」都是同一种手感，
  /// 不会键盘震得比候选词重、听起来像两个 App。
  ///
  /// 不 await：震动只是反馈，绝不能让按键逻辑等它。桌面端、模拟器等没有
  /// 震动器的平台调用它不会报错，直接忽略即可。
  void _tapFeedback() {
    unawaited(HapticFeedback.lightImpact());
  }

  /// 这颗键此刻是否显示为按下：有手指按在它上面，或刚松手还在保留期内。
  bool _isPressed(String key) =>
      _lingerKey == key || _touches.values.any((touch) => touch.key == key);

  ///
  /// 此刻要弹气泡的字母：最近按下的那根手指所在的字母键优先；
  /// 手指都松开了，就看刚松手的那颗字母键还在不在保留期内。
  String? get _popupLetter {
    for (final touch in _touches.values.toList().reversed) {
      if (!touch.onDelete && touch.key != null) return touch.key;
    }
    final linger = _lingerKey;
    return linger == _kDeleteKeyLabel ? null : linger;
  }

  /// 页面销毁：取消全部定时器。
  @override
  void dispose() {
    _stopDeleteTimers();
    _lingerTimer?.cancel();
    super.dispose();
  }

  // ===== 以下为指针状态机：按下 / 滑动 / 抬起 / 取消 =====
  //
  // 每颗键各挂一个 Listener，但系统会把一根手指之后的滑动和抬起事件都交给
  // 它最初按下的那颗键——所以这里一律按「手指编号」找状态，不按「哪颗键
  // 收到了事件」来判断，手指滑到别的键上也不会乱。

  /// 手指按下某颗键：记下这根手指，让这颗键进入「按下」画面，并给一次震动。
  void _handlePointerDown(String key, PointerDownEvent event) {
    if (!widget.enabled) return;
    // 触感必须落在「按下」这一刻，而不是「抬起」那一刻。
    // 生活化解释：实体键盘是手指先感到键帽下沉、屏幕上才出现字；把震动放在
    // 按下瞬间，手感和键帽缩小变灰（`.key:active`）是同一个节拍，比等到抬起
    // 才震更接近真键盘，快速连打时也不会觉得震动慢了半拍。
    _tapFeedback();
    final onDelete = key == _kDeleteKeyLabel;
    setState(() {
      // 新的一次按下立刻接管画面，上一颗键不必再保留按下状态。
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _lingerKey = null;
      _touches[event.pointer] = _KeyTouch(
        onDelete: onDelete,
        key: key,
        origin: event.position,
      );
    });
    if (onDelete) _startDeleteHold(event.pointer);
  }

  /// 手指移动：字母键跟着手指换键，删除键只判断是否滑出了阈值。
  void _handlePointerMove(PointerMoveEvent event) {
    final touch = _touches[event.pointer];
    if (touch == null) return;
    if (touch.onDelete) {
      if (!touch.slidOut &&
          (event.position - touch.origin).distance > _kSlipThreshold) {
        touch.slidOut = true;
      }
      return;
    }
    // 按错了不松手滑到正确的键：手指到了哪颗字母键，这一下就算哪颗键，
    // 气泡也跟过去；滑到删除键上或键盘外面，这一下作废，气泡收起。
    final next = _letterAt(event.position);
    if (next == touch.key) return;
    setState(() => touch.key = next);
  }

  /// 手指抬起：字母键输入手指最后所在的那颗键，删除键按单击 / 连发规则收尾。
  void _handlePointerUp(PointerUpEvent event) {
    final touch = _touches[event.pointer];
    if (touch == null) return;
    if (touch.onDelete) {
      // 抬起前先记下是否已经进入连发：进入过就不算单击，避免多删一格。
      final wasHolding = _deleteHolding;
      _stopDeleteTimers();
      if (widget.enabled && !wasHolding && !touch.slidOut) {
        widget.onDeleteTap?.call();
      }
      _release(event.pointer, _kDeleteKeyLabel);
      return;
    }
    final letter = touch.key;
    if (widget.enabled && letter != null) widget.onLetterTap?.call(letter);
    _release(event.pointer, letter);
  }

  /// 指针事件被系统打断（如来电）：只清状态，不触发任何按键。
  void _handlePointerCancel(PointerCancelEvent event) {
    final touch = _touches[event.pointer];
    if (touch == null) return;
    // 指针被系统打断：连发定时器必须停，否则会一直删下去。
    if (touch.onDelete) _stopDeleteTimers();
    setState(() => _touches.remove(event.pointer));
  }

  /// 手指松开后，把 [key] 的按下画面（含气泡）再保留一小段时间。
  ///
  /// [key] 为 null 表示这一下作废了（滑出键盘后才松手），不需要保留任何画面。
  void _release(int pointer, String? key) {
    _lingerTimer?.cancel();
    _lingerTimer = null;
    setState(() {
      _touches.remove(pointer);
      _lingerKey = key;
    });
    if (key == null) return;
    _lingerTimer = Timer(
      const Duration(milliseconds: _kPressMinimumVisibleMs),
      () {
        _lingerTimer = null;
        if (!mounted) return;
        setState(() => _lingerKey = null);
      },
    );
  }

  /// 把手指的屏幕坐标换算成它此刻所在的字母键；删除键和键盘外面都算 null。
  String? _letterAt(Offset globalPosition) {
    final box = _keyAreaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final key = _KeyboardGeometry(
      box.size.width,
    ).keyAt(box.globalToLocal(globalPosition));
    return key == _kDeleteKeyLabel ? null : key;
  }

  /// 删除键按下后开始计时：按住 420ms 才进入连发，短按不受影响。
  void _startDeleteHold(int pointer) {
    _stopDeleteTimers();
    _holdTimer = Timer(widget.deleteRepeatDelay, () {
      _holdTimer = null;
      final touch = _touches[pointer];
      // 手指已经滑走或抬起就不进入连发（抬起时定时器已被取消，
      // 这里主要防「按下后滑出、仍按住不放」的误连发）。
      if (!mounted || touch == null || touch.slidOut) return;
      _deleteHolding = true;
      // 进入连发的第一下立刻删一个，之后按周期继续。
      _repeatDelete();
      _repeatTimer = Timer.periodic(widget.deleteRepeatInterval, (_) {
        // 手指中途抬起 / 系统打断时立刻停发：防止后台一直删。
        if (!mounted || !_touches.containsKey(pointer)) {
          _repeatTimer?.cancel();
          _repeatTimer = null;
          return;
        }
        _repeatDelete();
      });
    });
  }

  /// 连发期间删一格。
  ///
  /// 每一格都补一次震动：手指一直按着时，震动就是「删到第几个了」的节奏反馈，
  /// 和系统键盘按住退格的手感一致。
  void _repeatDelete() {
    _tapFeedback();
    widget.onDeleteRepeat?.call();
    widget.onDeleteTap?.call();
  }

  // ===== 以下为三行的布局构建 =====

  ///
  /// 构建整块键盘：灰蓝面板 + 三行按键，每行水平居中；按下字母键时在最上层
  /// 叠一个气泡。
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
        //
        // 底部这块单独说明一下：贴边模式（`edgeToEdge: true`）下走的是「键盘面板
        // 一直延伸到屏幕底边」的设计，外层 SafeArea 能给到的底部安全距离只取决于
        // 系统手势条——在 Android 三键导航 / 非 edge-to-edge 的设备上 `padding.bottom`
        // 恒为 0，SafeArea 拿不到任何东西，第三行 zxcvbnm 的下边框就会紧贴屏幕最底。
        // 这里给一个固定 16 像素的「兜底安全距离」：
        //   • 手势导航设备：外层 SafeArea 已经让出 24~34，系统 inset + 16 = 40~50，
        //     看着略宽但不会顶到按键；
        //   • 三键导航设备：SafeArea 让不出东西，16 像素成为唯一的留白，
        //     第三行按键终于不再贴着屏幕底缘。
        child: Padding(
          padding: widget.edgeToEdge
              ? const EdgeInsets.fromLTRB(
                  AppSpace.p2,
                  AppSpace.p2,
                  AppSpace.p2,
                  AppSpace.p3,
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
              final geometry = _KeyboardGeometry(constraints.maxWidth);
              final popup = _popupLetter;
              // 气泡要画到三行按键的上方、甚至伸出键盘顶边，所以这一层不裁切。
              return Stack(
                key: _keyAreaKey,
                clipBehavior: Clip.none,
                children: <Widget>[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      for (
                        var rowIndex = 0;
                        rowIndex < _kRows.length;
                        rowIndex += 1
                      ) ...[
                        if (rowIndex > 0) const SizedBox(height: _kRowGap),
                        _buildRow(
                          _kRows[rowIndex],
                          geometry.keyWidth,
                          geometry.deleteWidth,
                          tokens,
                        ),
                      ],
                    ],
                  ),
                  // 气泡放在最后一层，才能盖住上一排的按键。
                  if (popup != null) _buildPopup(popup, geometry, tokens),
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
    final isDown = _isPressed(letter);
    // 键帽配色：平常是白底深字，按下时变灰（按下时会被气泡整个盖住）。
    final face = _faceColor(
      isDown: isDown,
      normal: tokens.keyFace,
      press: tokens.keyPressFace,
    );
    return _buildKeyShell(
      key: Key('qwerty-key-$letter'),
      label: letter,
      semanticLabel: letter,
      face: face,
      ink: tokens.keyInk,
      isDown: isDown,
      width: keyWidth,
      isDeleteKey: false,
    );
  }

  ///
  /// 构建删除键：支持单击退一格，长按 420ms 后每 90ms 连发。
  Widget _buildDeleteKey(double deleteWidth, AppTokens tokens) {
    final isDown = _isPressed(_kDeleteKeyLabel);
    final face = _faceColor(
      isDown: isDown,
      normal: tokens.keyDeleteFace,
      press: tokens.keyDeletePressFace,
    );
    return _buildKeyShell(
      key: const Key('qwerty-key-delete'),
      label: _kDeleteKeyLabel,
      semanticLabel: '删除',
      face: face,
      ink: tokens.keyDeleteInk,
      isDown: isDown,
      width: deleteWidth,
      isDeleteKey: true,
    );
  }

  ///
  /// 键帽的公共外壳：指针事件 + 按下缩放 + 底色 + 文字 / 图标。
  ///
  /// 所有键共用这一个构建方法，字母键与删除键只差宽度、图标与标识。
  ///
  /// [label] 是这颗键的内部标识（小写字母或 [_kDeleteKeyLabel]），
  /// [semanticLabel] 是读屏软件念出来的名字。
  Widget _buildKeyShell({
    required Key key,
    required String label,
    required String semanticLabel,
    required Color face,
    required Color ink,
    required bool isDown,
    required double width,
    required bool isDeleteKey,
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
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _handlePointerDown(label, event),
      // 按下之后的滑动、抬起都按手指编号交给状态机，见「指针状态机」的说明。
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      // 无障朗读：让读屏软件把键帽读成字母 / 删除，而不是一串英文类名。
      child: Semantics(
        label: semanticLabel,
        button: true,
        excludeSemantics: true,
        child: pressed,
      ),
    );
  }

  ///
  /// 构建 [letter] 键上方的一体气泡。
  ///
  /// 气泡的下半截与这颗键的矩形完全重合（把按下的键整个盖住），往上收腰、
  /// 再放宽成圆角的头。头的左右位置以按键为中心；贴边的键把头往里挪，
  /// 最多伸进面板留白 [_kPopupEdgeAllowance]，不会被屏幕边缘切掉。
  Widget _buildPopup(
    String letter,
    _KeyboardGeometry geometry,
    AppTokens tokens,
  ) {
    final keyRect = geometry.rects[letter]!;
    final headWidth = keyRect.width + _kPopupSideExtra * 2;
    const minLeft = -_kPopupEdgeAllowance;
    final maxLeft = math.max(
      minLeft,
      geometry.width + _kPopupEdgeAllowance - headWidth,
    );
    final headLeft = (keyRect.center.dx - headWidth / 2).clamp(
      minLeft,
      maxLeft,
    );
    // 气泡整体占用的区域：左右取头部与按键的并集，上到头顶、下到按键底边。
    final bounds = Rect.fromLTRB(
      math.min(headLeft, keyRect.left),
      keyRect.top - _kPopupShoulderHeight - _kPopupHeadHeight,
      math.max(headLeft + headWidth, keyRect.right),
      keyRect.bottom,
    );
    // 以下两个矩形换算到气泡自己的坐标系里（左上角为原点）。
    final headRect = Rect.fromLTWH(
      headLeft - bounds.left,
      0,
      headWidth,
      _kPopupHeadHeight,
    );
    final baseRect = keyRect.shift(-bounds.topLeft);
    return Positioned.fromRect(
      rect: bounds,
      // 气泡只给人看：不接收任何触摸，手指可以照常滑到它下面的按键上；
      // 读屏也不必再念一遍，按键本身已经念过这个字母。
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: CustomPaint(
            key: Key('qwerty-popup-$letter'),
            painter: _KeyPopupPainter(
              headRect: headRect,
              baseRect: baseRect,
              color: tokens.keyFace,
              shadowColor: tokens.keyShadow,
              borderColor: AppTokens.keyPanelBorder,
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fromRect(
                  rect: headRect,
                  child: Center(
                    // 系统字号放大到很大时，字母等比缩小留在头部里，不会溢出。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        letter.toUpperCase(),
                        // 40 号（display6）大约是键帽 18 号字母的两倍；字重与键帽
                        // 同为半粗，看起来就是同一颗字母被放大了。
                        style: Theme.of(context).textTheme.display6.copyWith(
                          color: tokens.keyInk,
                          fontWeight: AppWeight.semibold,
                        ),
                      ),
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
/// 一体气泡的画笔：一笔画出「圆角头部 → 平滑收腰 → 与按键等宽的底座」
/// 这一整圈轮廓，填色、投影、描边都作用在同一个轮廓上。
///
/// 以前是「圆角矩形 + 三角形」两块拼起来，交接处是硬折角，像叠积木；
/// 现在整圈只有一条连续的边，头部与底座之间靠两段竖直切线的弧线过渡。
class _KeyPopupPainter extends CustomPainter {
  const _KeyPopupPainter({
    required this.headRect,
    required this.baseRect,
    required this.color,
    required this.shadowColor,
    required this.borderColor,
  });

  /// 放大字母所在的圆角头部。
  final Rect headRect;

  /// 与按下那颗键完全重合的底座。
  final Rect baseRect;

  /// 气泡底色（与字母键键帽同色）。
  final Color color;

  /// 气泡投影颜色。
  final Color shadowColor;

  /// 气泡外缘那圈细描边的颜色。
  final Color borderColor;

  /// 沿顺时针方向画出整圈轮廓：从底座左下角出发，上左边、过头顶、下右边、
  /// 回到底座底边。
  Path _outline() {
    // 头部底边与底座顶边之间，就是左右两段收腰弧线。
    final shoulderTop = headRect.bottom;
    final shoulderBottom = baseRect.top;
    final pull = (shoulderBottom - shoulderTop) * _kPopupCurve;
    const headCorner = Radius.circular(_kPopupHeadRadius);
    const baseCorner = Radius.circular(_kKeyRadius);
    return Path()
      ..moveTo(baseRect.left, baseRect.bottom - _kKeyRadius)
      // 底座左边竖直往上，到收腰处。
      ..lineTo(baseRect.left, shoulderBottom)
      // 左侧收腰：两端切线都竖直，和上下两条竖边无缝相接。
      ..cubicTo(
        baseRect.left,
        shoulderBottom - pull,
        headRect.left,
        shoulderTop + pull,
        headRect.left,
        shoulderTop,
      )
      ..lineTo(headRect.left, headRect.top + _kPopupHeadRadius)
      ..arcToPoint(
        Offset(headRect.left + _kPopupHeadRadius, headRect.top),
        radius: headCorner,
      )
      ..lineTo(headRect.right - _kPopupHeadRadius, headRect.top)
      ..arcToPoint(
        Offset(headRect.right, headRect.top + _kPopupHeadRadius),
        radius: headCorner,
      )
      ..lineTo(headRect.right, shoulderTop)
      // 右侧收腰，与左侧对称。
      ..cubicTo(
        headRect.right,
        shoulderTop + pull,
        baseRect.right,
        shoulderBottom - pull,
        baseRect.right,
        shoulderBottom,
      )
      ..lineTo(baseRect.right, baseRect.bottom - _kKeyRadius)
      // 底座下方两个圆角与键帽一致，盖在键上时边缘严丝合缝。
      ..arcToPoint(
        Offset(baseRect.right - _kKeyRadius, baseRect.bottom),
        radius: baseCorner,
      )
      ..lineTo(baseRect.left + _kKeyRadius, baseRect.bottom)
      ..arcToPoint(
        Offset(baseRect.left, baseRect.bottom - _kKeyRadius),
        radius: baseCorner,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outline = _outline();
    canvas.drawShadow(outline, shadowColor, _kPopupElevation, false);
    canvas.drawPath(outline, Paint()..color = color);
    // 一圈极细的描边：浅色键盘上白色气泡的轮廓更清楚；深色下自然隐形。
    canvas.drawPath(
      outline,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppStroke.thin,
    );
  }

  @override
  bool shouldRepaint(covariant _KeyPopupPainter oldDelegate) =>
      oldDelegate.headRect != headRect ||
      oldDelegate.baseRect != baseRect ||
      oldDelegate.color != color ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.borderColor != borderColor;
}
