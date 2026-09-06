// material.dart 提供 Widget、Wrap、Stack 等基础绘制能力。
import 'package:flutter/material.dart';

// 引入设计令牌，卡片、徽标和文字颜色都从这里取当前明暗对应的值。
import '../common/theme.dart';
// 引入释义分组模型，只读模式可以直接吃模型层整理好的结果。
import '../models/meaning.dart';
// 引入统一的闪烁光标，揭示模式下提示「下一条含义填在这里」。
import 'blinking_caret.dart';

///
/// 「词性及含义」面板的尺寸表。
///
/// 数值全部沿用 `ui/听音拼写2.html` 原型，原先住在
/// `lib/pages/spelling_reinforcement/widgets/spelling_layout.dart` 的
/// `meaning*` 一族常量，现在跟着组件搬到这里（值一个没改）。
/// 参照 `lib/widgets/qwerty_keyboard.dart` 的做法：公共组件自己维护尺寸。
///
abstract final class PosMeaningPanelLayout {
  // 「标题字距压平为 0」这一档已经删除：全站默认早就不加字距了，这里再写一遍 0
  // 等于把「什么都不做」写成一条规定。

  ///
  /// 标题文字与右侧横线之间的距离，对应原型的 `gap-3`。
  static const double headingGap = AppSpace.p3;

  ///
  /// 标题右侧那条横线的粗细，取全站最细的描边档。
  static const double headingRuleHeight = AppStroke.thin;

  ///
  /// 标题与下方第一张卡片的距离，对应原型的 `mb-3`。
  static const double headingBottom = AppSpace.p3;

  ///
  /// 相邻两张含义卡片之间的距离，对应原型列表的 `space-y-2.5`。
  static const double cardGap = AppSpace.p2;

  ///
  /// 含义卡片圆角，对应原型的 `rounded-xl`。
  ///
  /// 全站三种「卡」各有一档：正文白卡 8、候选卡 10、含义卡 12。它们本来就不该
  /// 一样——白卡是一整屏的底、候选卡是一排按钮、含义卡是嵌在白卡里的小块，
  /// 层层向内圆角依次放大才有嵌套感。名字带 `meaning` 前缀就是为了防止哪天
  /// 有人看见三处都叫 `cardRadius` 就顺手统一掉。
  static const double meaningCardRadius = AppRadius.roundedXl;

  ///
  /// 含义卡片边框宽度；原型使用极淡的 `border-slate-100`。
  static const double cardBorderWidth = AppStroke.thin;

  ///
  /// 含义卡片左右内边距，对应原型的 `px-3.5`。
  static const double meaningCardPaddingHorizontal = AppSpace.p3;

  ///
  /// 含义卡片上下内边距，对应原型的 `py-2.5`。
  static const double meaningCardPaddingVertical = AppSpace.p2;

  ///
  /// 词性徽标圆角，对应原型的 `rounded-md`。
  static const double badgeRadius = AppRadius.rounded;

  ///
  /// 词性徽标左右内边距，对应原型的 `px-1.5`。
  static const double badgePaddingHorizontal = AppSpace.p2;

  ///
  /// 词性徽标上下内边距，对应原型的 `py-0.5`。
  static const double badgePaddingVertical = AppSpace.p1;

  ///
  /// 词性徽标与右侧含义之间的水平间距，对应原型的 `gap-3`。
  static const double badgeTextGap = AppSpace.p3;

  ///
  /// 含义正文字号，对应原型的 `text-[14.5px]`。
  static const double textSize = AppFont.fs5;

  ///
  /// 待填含义下方那条下划线的粗细。
  ///
  /// 这个值必须与 `LetterSlotLayout.underlineHeight` 保持一致：
  /// 拼写巩固填字母、这里填含义，两处是同一种「填空」观感，粗细一旦不同
  /// 用户会立刻看出是两套东西。改动时请同步另一处。
  static const double underlineHeight = AppStroke.mark;

  ///
  /// 当前待填下划线外围的淡蓝焦点扩散宽度。
  ///
  /// 与字母格共用总表同一档 [AppSize.underlineGlow]，不再需要人工同步。
  static const double underlineFocusSpread = AppSize.underlineGlow;

  ///
  /// 当前待填下划线焦点扩散的透明度。
  ///
  /// 与字母格共用总表同一档 [AppAlpha.a10]，不再需要人工同步。
  static const double underlineFocusAlpha = AppAlpha.a10;

  ///
  /// 光标粗细。
  ///
  /// 与字母格共用总表同一档 [AppSize.caretWidth]，不再需要人工同步。
  static const double caretWidth = AppSize.caretWidth;

  ///
  /// 光标高度上限。
  ///
  /// 含义行只有一行文字那么高（[textSize] × [AppLine.lhBase]），塞不下字母格
  /// 那样的满高光标，所以实际高度会按可用空间收缩，这里只封顶。封顶值取总表
  /// [AppSize.caretHeight]，与字母格的光标同源同一档，高度随总表一起变。
  static const double caretMaxHeight = AppSize.caretHeight;

  ///
  /// 光标底部与下划线之间留出的空隙，避免竖线压在横线上。
  static const double caretGap = AppSpace.p1;
}

///
/// 面板的两种模式。
///
enum PosMeaningPanelMode {
  ///
  /// 只读：含义直接显示出来，谁都不用作答。拼写巩固用这一种。
  readOnly,

  ///
  /// 揭示：含义先被盖住只剩一条下划线，用户答对一条就原地揭开一条。
  ///
  /// 关键点：被盖住的时候，底下垫的就是那条真实含义本身，所以下划线宽度
  /// 天生等于含义宽度——答对时只是把遮盖撤掉，页面一个像素都不会动。
  /// 听音辨义用这一种。
  reveal,
}

///
/// 面板里的一行：一个词性 + 它下面的若干条含义。
///
/// 例如 `hello` 的 `n. 招呼、问候` 就是一行，`pos = 'n.'`，
/// `definitions = ['招呼', '问候']`。
///
class PosMeaningRow {
  ///
  /// 创建一行「词性 + 含义」。
  const PosMeaningRow({required this.pos, required this.definitions});

  ///
  /// 展示用词性，如 `n.` / `vt.` / `vi. vt.`；没有词性时是 `*`。
  final String pos;

  ///
  /// 这个词性下的全部含义，顺序即展示顺序。
  ///
  /// 揭示模式下也要把还没答对的含义传进来：它们要垫在底层当尺子，
  /// 用来撑出和答对后完全一致的宽度。组件不会把它们画出来。
  final List<String> definitions;

  ///
  /// 由模型层整理好的词性分组直接构造一行。
  factory PosMeaningRow.fromGroup(MeaningGroup group) => PosMeaningRow(
    pos: group.pos,
    definitions: List<String>.unmodifiable(
      group.meanings.map((meaning) => meaning.definition),
    ),
  );

  ///
  /// 由 `Word.meaningGroups` 整批构造，供只读展示直接使用。
  static List<PosMeaningRow> fromGroups(Iterable<MeaningGroup> groups) =>
      List<PosMeaningRow>.unmodifiable(groups.map(PosMeaningRow.fromGroup));
}

///
/// 全App统一的「词性及含义」面板。
///
/// 版面复刻 `ui/听音拼写2.html`：一行标题 + 一条横线，下面每个词性一张
/// 圆角淡蓝灰卡片，卡片里左边是白底细边框的词性徽标，右边是这个词性下的
/// 全部含义，含义之间用用户设置里的分隔符连接。
///
/// 抽成公共组件的目的：让所有出现「词性及含义」的地方长得一模一样。
/// 在此之前拼写巩固和听音辨义各写了一份，卡片结构和分隔符样式已经跑偏。
///
/// 组件**不管自己放在哪**：外层的居中、最大宽度、上下留白仍由各页面决定
/// （拼写巩固限宽 720，听音辨义限宽 300），面板只负责横向铺满给它的宽度。
///
class PosMeaningPanel extends StatelessWidget {
  ///
  /// 只读模式（默认）：把含义直接显示出来。
  const PosMeaningPanel({
    required this.rows,
    required this.separator,
    this.heading = defaultHeading,
    this.emptyText = defaultEmptyText,
    this.keyPrefix = defaultKeyPrefix,
    super.key,
  }) : mode = PosMeaningPanelMode.readOnly,
       revealedCount = 0,
       activeIndex = null;

  ///
  /// 揭示模式：前 [revealedCount] 条含义已答对并公开，[activeIndex] 那条正在作答。
  ///
  /// 两个下标都是「把所有词性的含义摊平后」的序号，与听音辨义页里的
  /// `_meaningIndex` 完全同一个口径：`n.` 有两条、`adj.` 有一条时，
  /// 三条含义的序号依次是 0、1、2。
  const PosMeaningPanel.reveal({
    required this.rows,
    required this.separator,
    required this.revealedCount,
    this.activeIndex,
    this.heading = defaultHeading,
    this.emptyText = defaultEmptyText,
    this.keyPrefix = defaultKeyPrefix,
    super.key,
  }) : mode = PosMeaningPanelMode.reveal;

  ///
  /// 默认标题文案。
  static const String defaultHeading = '词性及含义';

  ///
  /// 单词一条含义都没有时显示的说明。
  static const String defaultEmptyText = '（这个词还没有中文释义）';

  ///
  /// 默认的测试 key 前缀。
  static const String defaultKeyPrefix = 'pos-meaning';

  ///
  /// 要显示的全部「词性 + 含义」行。
  final List<PosMeaningRow> rows;

  ///
  /// 同词性多条含义之间的分隔符。
  ///
  /// 必须由外部传入：它是用户可改的设置项（顿号 / 逗号 / 分号，默认全角分号），
  /// 见 `lib/store/settings.dart`。组件自己写死会绕过用户设置。
  final String separator;

  ///
  /// 当前模式。
  final PosMeaningPanelMode mode;

  ///
  /// 揭示模式下已答对并公开的含义条数（摊平计数）。只读模式恒为 0 且不参与判断。
  final int revealedCount;

  ///
  /// 揭示模式下正在作答的那条含义的摊平下标；没有正在作答的（例如本词已完成）传 null。
  final int? activeIndex;

  ///
  /// 标题文案。
  final String heading;

  ///
  /// 无含义时的占位说明。
  final String emptyText;

  ///
  /// 测试 key 前缀，让两个模块各自保留原来的 key 命名。
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 文字样式表在 build 取一次，再逐层递给下面几个普通方法：
    // 它们都不是组件，没有自己的 context。
    final textTheme = Theme.of(context).textTheme;

    final children = <Widget>[
      _buildHeading(tokens, textTheme),
      const SizedBox(height: PosMeaningPanelLayout.headingBottom),
    ];

    if (rows.isEmpty) {
      children.add(
        Text(emptyText, style: textTheme.fs5.copyWith(color: tokens.muted)),
      );
    } else {
      // 摊平下标跨词性连续累加：第二个词性的第一条含义不是 0，而是接着上一组数。
      var flatIndex = 0;
      for (var index = 0; index < rows.length; index += 1) {
        if (index > 0) {
          children.add(const SizedBox(height: PosMeaningPanelLayout.cardGap));
        }
        children.add(
          _buildCard(tokens, textTheme, rows[index], index, flatIndex),
        );
        flatIndex += rows[index].definitions.length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  ///
  /// 构建「词性及含义 + 横线」这一行标题。
  ///
  /// 横线用 Expanded（自动占满剩余宽度），小屏幕上也不会溢出。
  Widget _buildHeading(AppTokens tokens, TextTheme textTheme) {
    return Row(
      children: [
        Text(
          heading,
          key: Key('$keyPrefix-heading'),
          // 标签统一取 12 号半粗那一档。
          style: textTheme.fs6Semibold.copyWith(color: tokens.muted),
        ),
        const SizedBox(width: PosMeaningPanelLayout.headingGap),
        Expanded(
          child: Container(
            height: PosMeaningPanelLayout.headingRuleHeight,
            color: tokens.innerBorder,
          ),
        ),
      ],
    );
  }

  ///
  /// 构建一张同词性含义卡片，对应原型的 `senseList > li`。
  ///
  /// 词性徽标按文字自然占宽，不用固定列宽，短词性不会在左侧留下空洞。
  Widget _buildCard(
    AppTokens tokens,
    TextTheme textTheme,
    PosMeaningRow row,
    int rowIndex,
    int firstFlatIndex,
  ) {
    return Container(
      key: Key('$keyPrefix-meaning-$rowIndex'),
      padding: const EdgeInsets.symmetric(
        horizontal: PosMeaningPanelLayout.meaningCardPaddingHorizontal,
        vertical: PosMeaningPanelLayout.meaningCardPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: tokens.inner,
        borderRadius: BorderRadius.circular(
          PosMeaningPanelLayout.meaningCardRadius,
        ),
        border: Border.all(
          color: tokens.innerBorder,
          width: PosMeaningPanelLayout.cardBorderWidth,
        ),
      ),
      child: Row(
        // 词性徽标与含义都相对本卡垂直居中：整行用 center 让两边共享同一根
        // 垂直中线，含义块内再套一层 Column 把文字在剩余高度里居中（见下方
        // Expanded）。不再用顶部对齐 + 徽标下移的老做法。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            key: Key('$keyPrefix-pos-$rowIndex'),
            padding: const EdgeInsets.symmetric(
              horizontal: PosMeaningPanelLayout.badgePaddingHorizontal,
              vertical: PosMeaningPanelLayout.badgePaddingVertical,
            ),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(
                PosMeaningPanelLayout.badgeRadius,
              ),
              border: Border.all(color: tokens.badgeBorder),
            ),
            child: Text(
              row.pos,
              style: textTheme.fs6Semibold.copyWith(
                color: AppTokens.primary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: PosMeaningPanelLayout.badgeTextGap),
          Expanded(
            // 含义块外面套一层 Column：卡内空间高于含义块时，把它在垂直方向
            // 居中。crossAxisAlignment 用 stretch 让含义仍然横向铺满、换行
            // 位置不变——只用 mainAxisAlignment.center 解决「含义只有一行时
            // 被顶在上方、底下空一截」的问题。
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDefinitions(tokens, textTheme, row, firstFlatIndex),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 构建卡片右侧的含义列表。
  ///
  /// 用 Wrap 而不是一整段文字，是因为揭示模式必须能单独盖住其中某一条。
  /// 为了让换行位置和一整段文字一致，分隔符不作为独立元素排队，而是跟在
  /// 它前面那条含义后面一起走——这样分隔符永远不会被挤到下一行的行首。
  Widget _buildDefinitions(
    AppTokens tokens,
    TextTheme textTheme,
    PosMeaningRow row,
    int firstFlatIndex,
  ) {
    // 释义是多行中文，行距用正文那一档自带的 1.43（单词行、随身听的释义读的是
    // 同一档，三个地方切换时不会有一处显得比另一处挤）。
    // 收敛前这里另写过「24 像素 ÷ 字号」，是全站唯一按像素写的行高；并档之后
    // 它和正文档正好相等，于是这一行删掉，交回主题继承。
    final style = textTheme.fs5.copyWith(color: tokens.definition);

    final children = <Widget>[];
    for (var index = 0; index < row.definitions.length; index += 1) {
      final definition = row.definitions[index];
      final flatIndex = firstFlatIndex + index;
      // 最后一条后面不跟分隔符。
      final tail = index == row.definitions.length - 1 ? '' : separator;
      // 只读模式全部公开；揭示模式只公开已经答对的那几条。
      final isRevealed =
          mode == PosMeaningPanelMode.readOnly || flatIndex < revealedCount;

      if (isRevealed) {
        // 已公开：含义和它后面的分隔符合成一段文字，读起来就是普通句子。
        children.add(
          Text(
            '$definition$tail',
            key: Key('$keyPrefix-definition-$flatIndex'),
            style: style,
          ),
        );
        continue;
      }

      final blank = _DefinitionBlank(
        key: Key('$keyPrefix-blank-$flatIndex'),
        definition: definition,
        style: style,
        isActive: flatIndex == activeIndex,
        lineColor: flatIndex == activeIndex ? AppTokens.primary : tokens.check,
      );
      // 未公开：遮盖只盖含义本身，分隔符照常显示，所以两者要拼成一个整体，
      // 总宽度才与公开后的「含义 + 分隔符」完全相等。
      children.add(
        tail.isEmpty
            ? blank
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(child: blank),
                  Text(tail, style: style),
                ],
              ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: children,
    );
  }
}

///
/// 一条还没答对的含义：只露出一条下划线，当前那条再加一个闪烁光标。
///
/// 核心技巧：**真实含义就垫在底层**，只是被设成完全透明不绘制。
/// 它照常参与排版，所以这块空白的宽高与答对后一模一样；答对时组件换成
/// 普通文字，尺寸不变，用户看到的就是含义「无声无息地填了进去」。
///
/// 这里不用「和卡片同色的实心遮罩」去盖文字：那样一旦卡片底色变成半透明
/// 或渐变，答案就会透出来提前泄题。透明度为 0 不依赖任何颜色，更安全。
///
class _DefinitionBlank extends StatelessWidget {
  ///
  /// 创建一条待填含义的空位。
  const _DefinitionBlank({
    required this.definition,
    required this.style,
    required this.isActive,
    required this.lineColor,
    super.key,
  });

  ///
  /// 真实含义；只用来撑出宽高，不会显示也不会被朗读。
  final String definition;

  ///
  /// 与已公开含义完全相同的文字样式，宽度才能对得上。
  final TextStyle style;

  ///
  /// 是否是用户当前正在作答的那一条。
  final bool isActive;

  ///
  /// 下划线颜色：当前条用品牌蓝，后面还没轮到的用浅灰。
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // 焦点扩散会画到边界外一点，不能裁掉。
      clipBehavior: Clip.none,
      children: [
        // 不带 Positioned 的这一个孩子决定 Stack 的尺寸，也就是「尺子」。
        ExcludeSemantics(
          child: Opacity(
            opacity: AppAlpha.none,
            child: Text(definition, style: style),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: PosMeaningPanelLayout.underlineHeight,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: BorderRadius.circular(AppRadius.roundedPill),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppTokens.primary.withValues(
                          alpha: PosMeaningPanelLayout.underlineFocusAlpha,
                        ),
                        // blurRadius 为 0 + spreadRadius，等价于 CSS 的
                        // `box-shadow: 0 0 0 3px`：一圈实心淡蓝描边而不是模糊光晕。
                        blurRadius: AppShadow.none,
                        spreadRadius:
                            PosMeaningPanelLayout.underlineFocusSpread,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        if (isActive)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom:
                PosMeaningPanelLayout.underlineHeight +
                PosMeaningPanelLayout.caretGap,
            // 光标高度跟随这条含义的实际可用高度，不给空位强行套一个固定高度。
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.bottomCenter,
                child: BlinkingCaret(
                  width: PosMeaningPanelLayout.caretWidth,
                  height: constraints.maxHeight
                      .clamp(1.0, PosMeaningPanelLayout.caretMaxHeight)
                      .toDouble(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
