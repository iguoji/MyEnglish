// material.dart 提供手势、动画、布局、文字与图标组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 统一提供勾选框与发音状态图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 公共日期 helper 负责今年与非今年的显示规则。
import '../../../common/date.dart';
// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// Meaning 和 Word 来自全局 models，其他页面也可复用。
import '../../../models/meaning.dart';
import '../../../models/word.dart';

/// 设计稿风格的单词行：36 高标题行 + 可展开释义 + 左滑"修改/删除"。
class WordListTile extends StatelessWidget {
  /// 创建列表项；选择与滑动状态都由首页集中保存。
  const WordListTile({
    required this.item,
    required this.dateReference,
    required this.isExpanded,
    required this.onTap,
    this.isPlaying = false,
    this.selectMode = false,
    this.isSelected = false,
    this.isSwipedOpen = false,
    this.onToggleSelect,
    this.onSwipeChanged,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  /// 标题行固定为设计稿的 36 像素。
  static const double headerHeight = 36;

  /// 左滑露出的操作区总宽度：修改 64 + 删除 64。
  static const double actionWidth = 128;

  /// 当前 Word 数据。
  final Word item;

  /// 日期格式化参考时间。
  final DateTime dateReference;

  /// 是否显示 Meaning 区域。
  final bool isExpanded;

  /// 当前行是否正在下载或播放音频。
  final bool isPlaying;

  /// 首页是否处于选择模式。
  final bool selectMode;

  /// 选择模式下当前行是否被勾选。
  final bool isSelected;

  /// 当前行是否处于左滑展开状态。
  final bool isSwipedOpen;

  /// 点击标题行：普通模式播放并展开，选择模式切换勾选（由首页决定）。
  final VoidCallback onTap;

  /// 点击勾选框时切换选中状态。
  final VoidCallback? onToggleSelect;

  /// 左滑打开或关闭操作区时通知首页；true 表示打开。
  final ValueChanged<bool>? onSwipeChanged;

  /// 点击"修改"操作。
  final VoidCallback? onEdit;

  /// 点击"删除"操作。
  final VoidCallback? onDelete;

  /// 把 Word 和各种状态转换成一棵 Widget 树。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 日期按业务规则优先 updatedAt，没有更新日期才使用 createdAt。
    final effectiveDate = item.effectiveDate;
    // 是否真的存在可展开内容。
    final hasMeanings = item.meanings.isNotEmpty;

    // DecoratedBox 给整个列表项绘制一条行分隔线。
    return DecoratedBox(
      decoration: BoxDecoration(
        // 用 cBd（与分组头下边框同色）而非 cRb：cRb(#eef0f3) 在白底上几乎不可见，
        // 整列分隔线统一为 cBd 后，每个单词行的下边框才清晰可辨（对齐 HTML 原型观感）。
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      // Column 先放标题行（含滑动层），再放可变高度释义区。
      child: Column(
        // 只占内容实际高度，交给 ListView 纵向排列。
        mainAxisSize: MainAxisSize.min,
        children: [
          // ClipRect 裁掉滑出屏幕的部分，避免操作区在未滑开时可见。
          ClipRect(
            // Stack 底层是操作按钮，上层是可平移的标题行。
            child: Stack(
              children: [
                // 操作区固定贴右侧，只在标题行左移后露出。
                Positioned.fill(
                  child: Row(
                    children: [
                      // 左侧弹性空间把两个按钮推到最右。
                      const Spacer(),
                      // 修改按钮使用主色底。
                      _SwipeAction(
                        key: const Key('swipe-edit'),
                        label: '修改',
                        color: AppTokens.accent,
                        onTap: onEdit,
                      ),
                      // 删除按钮使用危险色底。
                      _SwipeAction(
                        key: const Key('swipe-delete'),
                        label: '删除',
                        color: AppTokens.danger,
                        onTap: onDelete,
                      ),
                    ],
                  ),
                ),
                // GestureDetector 捕获横向滑动，判定打开或关闭操作区。
                GestureDetector(
                  // 拖拽结束时按累计位移方向通知首页。
                  onHorizontalDragEnd: _handleDragEnd,
                  // 累计本次拖拽的横向位移。
                  onHorizontalDragUpdate: (details) =>
                      _dragDistance += details.delta.dx,
                  // 拖拽开始时清零累计值。
                  onHorizontalDragStart: (details) => _dragDistance = 0,
                  // AnimatedContainer 平移标题行，产生滑开动画。
                  child: AnimatedContainer(
                    // 与设计稿一致的 180ms 缓动。
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.ease,
                    // 打开时整行左移露出 128 宽操作区。
                    transform: Matrix4.translationValues(
                      isSwipedOpen ? -actionWidth : 0,
                      0,
                      0,
                    ),
                    // 标题行自身使用卡片底色盖住操作区。
                    color: tokens.card,
                    // InkWell 提供整行点击反馈。
                    child: InkWell(
                      onTap: onTap,
                      // SizedBox 固定 36 高标题行。
                      child: SizedBox(
                        height: headerHeight,
                        child: Padding(
                          // 与设计稿一致的 20 像素左右边距。
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              // 左半部分：勾选框、播放喇叭与单词。
                              Expanded(
                                child: Row(
                                  children: [
                                    // 选择模式下显示 18×18 勾选框。
                                    if (selectMode) ...[
                                      _CheckBox(
                                        isSelected: isSelected,
                                        onTap: onToggleSelect,
                                      ),
                                      // 勾选框与后续内容间距。
                                      const SizedBox(width: 10),
                                    ],
                                    // 播放中显示动画喇叭，紧贴单词左侧。
                                    if (isPlaying) ...[
                                      _PlayingSpeakerIcon(
                                        key: ValueKey<Object?>(
                                          item.id ?? item.spelling,
                                        ),
                                      ),
                                      // 喇叭与单词间距。
                                      const SizedBox(width: 10),
                                    ],
                                    // Flexible 允许极长拼写省略。
                                    Flexible(
                                      child: Text(
                                        item.spelling,
                                        // 标题始终保持一行。
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        // 设计稿的 16 号中等字重。
                                        style: TextStyle(
                                          color: tokens.text,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 左右两块之间至少 12 像素。
                              const SizedBox(width: 12),
                              // 右半部分：难度徽章与日期。
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 任何非空难度都显示红色徽章。
                                  if (item.difficulty
                                      case final difficulty?) ...[
                                    _DifficultyBadge(difficulty: difficulty),
                                    // 徽章与日期之间留白。
                                    const SizedBox(width: 10),
                                  ],
                                  // 固定 40 宽右对齐日期列，缺日期时留空占位。
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      effectiveDate == null
                                          ? ''
                                          : formatWordDate(
                                              effectiveDate,
                                              dateReference,
                                            ),
                                      // 右对齐让日期竖向成列。
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: tokens.textSecondary,
                                        fontSize: 13,
                                        // 等宽数字避免日期跳动。
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // AnimatedSize 只负责展开高度过渡，不保存业务状态。
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            // 收起时创建零高度盒子，展开时创建释义列表。
            child: isExpanded && hasMeanings
                ? _MeaningList(meanings: item.meanings)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 本次拖拽累计位移；组件是无状态的，借助静态字段在拖拽回调间传值安全，
  /// 因为同一时刻只会有一根手指拖动一行。
  static double _dragDistance = 0;

  /// 拖拽结束：左移超过 30 像素打开操作区，右移超过 30 像素关闭。
  void _handleDragEnd(DragEndDetails details) {
    // 没有注册回调时忽略。
    final notify = onSwipeChanged;
    if (notify == null) return;
    // 左滑打开；选择模式下首页会拒绝打开。
    if (_dragDistance < -30) notify(true);
    // 右滑关闭。
    if (_dragDistance > 30) notify(false);
  }
}

/// 左滑露出的单个操作按钮：64 宽全高色块。
class _SwipeAction extends StatelessWidget {
  /// 接收文案、底色与点击动作。
  const _SwipeAction({
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });

  /// 按钮文字。
  final String label;

  /// 按钮底色。
  final Color color;

  /// 点击动作。
  final VoidCallback? onTap;

  /// 输出色块按钮。
  @override
  Widget build(BuildContext context) {
    // GestureDetector 直接响应点击，不需要水波纹。
    return GestureDetector(
      onTap: onTap,
      // 64 宽色块，文字白色居中。
      child: Container(
        width: 64,
        color: color,
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 选择模式下的 18×18 勾选框。
class _CheckBox extends StatelessWidget {
  /// 接收选中状态与点击动作。
  const _CheckBox({required this.isSelected, required this.onTap});

  /// 是否被选中。
  final bool isSelected;

  /// 点击切换选中。
  final VoidCallback? onTap;

  /// 输出设计稿风格的小方框。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // GestureDetector 独立响应勾选，不触发整行点击。
    return GestureDetector(
      onTap: onTap,
      // 透明命中区域略大于视觉框。
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 选中实心主色，未选中卡片底描边。
          color: isSelected ? AppTokens.accent : tokens.card,
          border: Border.all(
            color: isSelected ? AppTokens.accent : tokens.check,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        // 选中时显示白色 Tabler 对勾，不再用文字字符模拟图标。
        child: isSelected
            ? const Icon(TablerIcons.check, color: Colors.white, size: 13)
            : null,
      ),
    );
  }
}

/// 播放期间循环轻微缩放的小喇叭。
class _PlayingSpeakerIcon extends StatefulWidget {
  /// key 在列表重排时保持动画与具体 Word 绑定。
  const _PlayingSpeakerIcon({super.key});

  /// 创建动画状态。
  @override
  State<_PlayingSpeakerIcon> createState() => _PlayingSpeakerIconState();
}

/// 管理喇叭的循环 AnimationController。
class _PlayingSpeakerIconState extends State<_PlayingSpeakerIcon>
    with SingleTickerProviderStateMixin {
  /// 控制一次放大缩小周期。
  late final AnimationController _controller;

  /// 把 0—1 控制值映射到 0.84—1.0 的轻微缩放。
  late final Animation<double> _scale;

  /// 组件加入树时创建并启动动画。
  @override
  void initState() {
    // 保留 State 父类初始化。
    super.initState();
    // 650ms 足够表达正在发声，同时不会闪烁。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    // CurvedAnimation 让缩放起止更平滑。
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    // Tween 定义最小与最大尺寸。
    _scale = Tween<double>(begin: 0.84, end: 1).animate(curved);
    // reverse=true 在放大后自动缩回并持续循环。
    _controller.repeat(reverse: true);
  }

  /// 播放结束、图标移出列表时释放 Ticker。
  @override
  void dispose() {
    // 停止并释放动画控制器。
    _controller.dispose();
    // 最后保留父类清理流程。
    super.dispose();
  }

  /// 输出缩放中的小喇叭。
  @override
  Widget build(BuildContext context) {
    // ScaleTransition 只重绘图标，不触发行布局变化。
    return ScaleTransition(
      scale: _scale,
      // volume2 是 Tabler 中用户熟悉的播放中扬声器图标。
      child: const Icon(
        TablerIcons.volume2,
        // 16 像素与设计稿喇叭一致。
        size: 16,
        // 使用品牌主色表达活动状态。
        color: AppTokens.accent,
      ),
    );
  }
}

/// 展开后的全部 Meaning；使用设计稿的浅色释义底。
class _MeaningList extends StatelessWidget {
  /// 接收当前 Word 已经按 index 降序排列的 Meaning。
  const _MeaningList({required this.meanings});

  /// 当前单词的 Meaning 集合。
  final List<Meaning> meanings;

  /// 输出对齐后的 Meaning 行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ColoredBox 铺满设计稿的浅色展开底。
    return ColoredBox(
      color: tokens.expand,
      // 撑满整行宽度，让底色贴到屏幕两侧。
      child: SizedBox(
        width: double.infinity,
        // Padding 与设计稿一致：上下 10、左右 20。
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          // Column 保证一个 Meaning 对象对应一个纵向行。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // 按模型顺序逐条生成行。
            children: [
              for (var index = 0; index < meanings.length; index += 1) ...[
                // 行与行之间 6 像素间距。
                if (index > 0) const SizedBox(height: 6),
                // 单条 Meaning 行。
                _MeaningRow(meaning: meanings[index]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单条 Meaning：36 宽右对齐斜体词性 + 释义。
class _MeaningRow extends StatelessWidget {
  /// 创建一条对齐行。
  const _MeaningRow({required this.meaning});

  /// 当前 Meaning 数据。
  final Meaning meaning;

  /// 输出词性列和释义列。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Row 让词性和释义处于同一 Meaning 行。
    return Row(
      // 顶部对齐保证释义换行时词性仍停在第一行。
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 固定 36 宽右对齐词性列，与设计稿一致。
        SizedBox(
          width: 36,
          child: Text(
            // 词性为空时仍保留列宽。
            meaning.pos,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 13.5,
              // 设计稿词性使用斜体。
              fontStyle: FontStyle.italic,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
        ),
        // 两列之间保持 12 像素距离。
        const SizedBox(width: 12),
        // Expanded 让释义使用剩余宽度并自然换行。
        Expanded(
          child: Text(
            // 一个 Meaning 的 definitions 用中文分号连接，仍占一个业务行。
            meaning.definitions.join('；'),
            style: TextStyle(
              color: tokens.text,
              fontSize: 13.5,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

/// 红色难度徽章；只在 difficulty 非空时创建。
class _DifficultyBadge extends StatelessWidget {
  /// difficulty 已由父组件分支保证非空。
  const _DifficultyBadge({required this.difficulty});

  /// 实际难度数值。
  final int difficulty;

  /// 输出设计稿的 22 高软色徽章。
  @override
  Widget build(BuildContext context) {
    // Container 同时提供尺寸、内边距和背景。
    return Container(
      // 设计稿最小 22×22。
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      // 数字位数增加时允许宽度自然增长。
      padding: const EdgeInsets.symmetric(horizontal: 5),
      // 数字水平、垂直居中。
      alignment: Alignment.center,
      // 危险色 13% 透明底和 6 像素圆角。
      decoration: BoxDecoration(
        color: AppTokens.danger.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      // 显示真实难度。
      child: Text(
        difficulty.toString(),
        style: const TextStyle(
          color: AppTokens.danger,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
