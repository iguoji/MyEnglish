// material.dart 提供点击反馈、动画、布局、文字、图标和边框组件。
import 'package:flutter/material.dart';

// 公共日期 helper 负责今年与非今年的显示规则。
import '../../../common/date.dart';
// 公共主题保留 Tabler 浅色与深色分隔线常量。
import '../../../common/theme.dart';
// Meaning 和 Word 来自全局 models，其他页面也可复用。
import '../../../models/meaning.dart';
import '../../../models/word.dart';

/// 可点击展开的单词列表项：标题行固定 40，高度以下按 Meaning 数量自然增加。
class WordListTile extends StatelessWidget {
  /// 创建列表项；onPlay 为空时仍可用于只测试布局的简单场景。
  const WordListTile({
    required this.item,
    required this.dateReference,
    required this.isExpanded,
    required this.onTap,
    this.isPlaying = false,
    this.onPlay,
    super.key,
  });

  /// 收起状态下单词标题行固定为 40 像素。
  static const double headerHeight = 40;

  /// 当前 Word 数据。
  final Word item;

  /// 日期格式化参考时间。
  final DateTime dateReference;

  /// 是否显示 Meaning 区域。
  final bool isExpanded;

  /// 当前行是否正在下载或播放音频。
  final bool isPlaying;

  /// 点击标题行非单词文字区域时切换展开状态。
  final VoidCallback onTap;

  /// 点击单词文字时播放；null 表示禁用播放手势。
  final VoidCallback? onPlay;

  /// 把 Word 和展开/播放状态转换成一棵 Widget 树。
  @override
  Widget build(BuildContext context) {
    // 日期按业务规则优先 updatedAt，没有更新日期才使用 createdAt。
    final effectiveDate = item.effectiveDate;
    // 是否真的存在可展开内容。
    final hasMeanings = item.meanings.isNotEmpty;
    // 浅色严格使用 Tabler #E6E7E9，深色使用适配后的分隔线。
    final dividerColor = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.darkTableBorderColor
        : AppTheme.tableBorderColor;
    // 读取当前 Light/Dark 的语义色。
    final colorScheme = Theme.of(context).colorScheme;

    // DecoratedBox 给整个列表项绘制一条底边线。
    return DecoratedBox(
      // 展开后边线会自然移动到全部 Meaning 的下方。
      decoration: BoxDecoration(
        border: Border(
          // 使用当前主题对应的 Tabler 表格分隔线。
          bottom: BorderSide(color: dividerColor),
        ),
      ),
      // Column 先放固定标题行，再放可变高度 Meaning 区域。
      child: Column(
        // 只占内容实际高度，交给 ListView 纵向排列。
        mainAxisSize: MainAxisSize.min,
        children: [
          // Material 为 InkWell 提供触摸水波纹绘制区域。
          Material(
            // 透明背景继承列表 surface。
            color: Colors.transparent,
            // Semantics 告诉无障碍工具标题行可展开。
            child: Semantics(
              // 整行非单词区域是可点击控件。
              button: true,
              // 只有存在 Meaning 时才报告展开状态。
              expanded: hasMeanings ? isExpanded : null,
              // InkWell 负责行展开操作。
              child: InkWell(
                // 点击单词文字以外的位置展开或收起。
                onTap: onTap,
                // SizedBox 保持收起列表尺寸稳定。
                child: SizedBox(
                  // 标题行固定为用户要求的 40 像素。
                  height: headerHeight,
                  // 左右边距与搜索框内容对齐。
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    // Row 对应 CSS display:flex。
                    child: Row(
                      // 所有标题信息纵向居中。
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Expanded 让播放区和单词使用右侧元信息之外的空间。
                        Expanded(
                          child: Row(
                            children: [
                              // 固定宽度使喇叭出现和消失时单词绝不横向跳动。
                              SizedBox(
                                width: 24,
                                // 只有当前播放行真正绘制动画图标。
                                child: isPlaying
                                    ? _PlayingSpeakerIcon(
                                        key: ValueKey<Object?>(
                                          item.id ?? item.spelling,
                                        ),
                                      )
                                    : null,
                              ),
                              // Flexible 允许极长拼写省略，同时短单词只占真实文字宽度。
                              Flexible(
                                // 单词文字自身拥有独立 tap，不会连带触发行展开。
                                child: _PlayableWordLabel(
                                  spelling: item.spelling,
                                  onPlay: onPlay,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 单词与右侧信息至少相隔 12 像素。
                        const SizedBox(width: 12),
                        // 右侧只占自身实际宽度，保持旧的 flex 结构。
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 任何非空难度都显示红色 badge。
                            if (item.difficulty case final difficulty?) ...[
                              _DifficultyBadge(difficulty: difficulty),
                              // badge 与日期或箭头之间留白。
                              const SizedBox(width: 8),
                            ],
                            // 有有效业务日期时才创建日期文字。
                            if (effectiveDate != null) ...[
                              Text(
                                // 今年显示 MM.dd，非今年显示 yyyy.MM.dd。
                                formatWordDate(effectiveDate, dateReference),
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  letterSpacing: 0,
                                ),
                              ),
                              // 日期与展开图标之间留白。
                              if (hasMeanings) const SizedBox(width: 6),
                            ],
                            // 有 Meaning 才显示展开方向图标。
                            if (hasMeanings)
                              // 固定图标区域，旋转时不会改变行布局。
                              SizedBox.square(
                                dimension: 20,
                                // 箭头从向下平滑转为向上。
                                child: AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 160),
                                  child: Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
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
          // AnimatedSize 只负责高度过渡，不保存业务状态。
          AnimatedSize(
            // 展开和收起使用短动画，避免大列表操作拖沓。
            duration: const Duration(milliseconds: 160),
            // 收起时创建零高度盒子，展开时创建 Meaning 列表。
            child: isExpanded && hasMeanings
                ? _MeaningList(meanings: item.meanings)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 单词文字的独立 tap 区域；仅它负责发音，外层行继续负责展开。
class _PlayableWordLabel extends StatelessWidget {
  /// 接收拼写和可空播放回调。
  const _PlayableWordLabel({required this.spelling, required this.onPlay});

  /// 要显示并朗读的拼写。
  final String spelling;

  /// 首页传入的播放动作。
  final VoidCallback? onPlay;

  /// 创建统一文字，按是否支持播放决定是否包裹手势。
  @override
  Widget build(BuildContext context) {
    // 当前主题的主文字色。
    final textColor = Theme.of(context).colorScheme.onSurface;
    // Text 独立保存，避免播放开关改变文字样式。
    final label = Text(
      spelling,
      // 标题始终保持一行。
      maxLines: 1,
      // 极长单词不会挤坏右侧日期。
      overflow: TextOverflow.ellipsis,
      // 主要文字样式。
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );
    // 没有回调时不注册子手势，点击会自然交给外层展开行。
    if (onPlay == null) return label;
    // Semantics 为读屏提供明确“播放”动作名称。
    return Semantics(
      button: true,
      label: '播放 $spelling',
      // GestureDetector 使用标准 tap，松手即响应且不会引入长按延迟。
      child: GestureDetector(
        // opaque 让文字行高内的空白也属于稳定点击区。
        behavior: HitTestBehavior.opaque,
        // 点击只触发播放回调。
        onTap: onPlay,
        // 保留上面创建的文字。
        child: label,
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
      // volume_up 是用户熟悉的播放中扬声器符号。
      child: Icon(
        Icons.volume_up_rounded,
        // 18 像素不会挤压固定 40 高标题行。
        size: 18,
        // 使用当前主题主色表达活动状态。
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// 展开后的全部 Meaning；每个 Meaning 独占一个纵向条目。
class _MeaningList extends StatelessWidget {
  /// 接收当前 Word 已经按 index 降序排列的 Meaning。
  const _MeaningList({required this.meanings});

  /// 当前单词的 Meaning 集合。
  final List<Meaning> meanings;

  /// 输出对齐后的 Meaning 行。
  @override
  Widget build(BuildContext context) {
    // Padding 让 Meaning 与标题左边缘一致，并在底部留出呼吸空间。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      // Column 保证一个 Meaning 对象对应一个纵向行。
      child: Column(
        // 按模型顺序逐条生成行。
        children: meanings
            .map((meaning) => _MeaningRow(meaning: meaning))
            .toList(growable: false),
      ),
    );
  }
}

/// 单条 Meaning：词性固定列宽，所有释义从同一水平位置开始。
class _MeaningRow extends StatelessWidget {
  /// 创建一条对齐行。
  const _MeaningRow({required this.meaning});

  /// 当前 Meaning 数据。
  final Meaning meaning;

  /// 输出词性列和释义列。
  @override
  Widget build(BuildContext context) {
    // 读取当前主题语义色。
    final colorScheme = Theme.of(context).colorScheme;
    // Padding 提供行间距；内容过长时高度可以自然增长。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // Row 让词性和释义处于同一 Meaning 行。
      child: Row(
        // 顶部对齐保证释义换行时词性仍停在第一行。
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 固定 56 像素词性列，使每条 definitions 起点完全一致。
          SizedBox(
            width: 56,
            child: Text(
              // 词性为空时仍保留列宽。
              meaning.pos,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
          ),
          // 两列之间保持 8 像素距离。
          const SizedBox(width: 8),
          // Expanded 让释义使用剩余宽度并自然换行。
          Expanded(
            child: Text(
              // 一个 Meaning 的 definitions 用中文分号连接，仍占一个业务行。
              meaning.definitions.join('；'),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 红色难度徽章；只在 difficulty 非空时创建。
class _DifficultyBadge extends StatelessWidget {
  /// difficulty 已由父组件分支保证非空。
  const _DifficultyBadge({required this.difficulty});

  /// 实际难度数值。
  final int difficulty;

  /// 输出紧凑红色 badge。
  @override
  Widget build(BuildContext context) {
    // Container 同时提供尺寸、内边距和背景。
    return Container(
      // 保持 20 像素高度。
      height: 20,
      // 数字位数增加时允许宽度自然增长。
      padding: const EdgeInsets.symmetric(horizontal: 6),
      // 数字水平、垂直居中。
      alignment: Alignment.center,
      // Tabler 红色语义背景和小圆角。
      decoration: BoxDecoration(
        color: const Color(0xFFD63939).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      // 显示真实难度。
      child: Text(
        difficulty.toString(),
        style: const TextStyle(
          color: Color(0xFFD63939),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
