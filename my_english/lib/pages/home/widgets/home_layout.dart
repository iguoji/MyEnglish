///
/// 首页的布局尺寸表。
///
/// 首页是全 App 唯一一屏「什么都有」的界面：顶部问候、搜索、分组筛选、单词列表、
/// 左侧抽屉、右下角学习按钮、两个从底部升起的面板（新增单词表单、词库），再加上
/// 一整块数据面板。所以这张表按**用户看到的区域**分成若干个小表，每个小表只管
/// 自己那一片，改哪一片就只看那一段，不用在上千行界面代码里翻宽高。
///
/// | 小表 | 管哪一片 |
/// |---|---|
/// | [HomeLayout] | 页面骨架、分组标题条、删除/清空确认弹窗 |
/// | [HomeHeaderLayout] | 顶部问候语与右上角菜单按钮 |
/// | [WordSearchFieldLayout] | 搜索框 |
/// | [WordListTileLayout] | 单词行（含左滑操作区、难度徽标、声纹图标） |
/// | [LearningFabLayout] | 右下角学习悬浮按钮及展开面板 |
/// | [HomeDrawerLayout] | 左侧抽屉（含各类设置控件） |
/// | [WordFormLayout] | 新增 / 编辑单词表单 |
/// | [WordLibraryLayout] | 词库抽屉 |
/// | [HomeDashboardLayout] | 数据面板（打卡热力图、复习模式卡、复习趋势） |
/// | [TrendChartLayout] | 数据面板里那张折线图 |
///
/// 表里有一部分数值是直接写的字面量而不是引用总表台阶，这是刻意的：按总表
/// `sizes.dart` 表头定下的规矩，只有**两个以上地方必须保持一致**的方寸才收进总表。
/// 比如首页有十来处高度都是 40，但「右上角菜单按钮」「搜索框」「学习面板里的一行」
/// 只是数字撞了，并不是同一个设计决定——真并成一档，以后想把菜单按钮点击区调大，
/// 搜索框会莫名跟着变高。所以它们各自留在本表里,只在本页范围内共享。
///
/// 不收进本表的是三类东西：
/// - **动画参数**：滑入的位移比例、旋转圈数、抖动曲线，那是运动而不是造型；
/// - **图标自绘的路径坐标**：单词行那个手绘声纹的弧心与半径，改一个数字整个图形就变形，
///   它们是一张图的组成部分，拆开命名反而看不懂；
/// - **交互阈值**：左滑多远才算划开、点击命中半径多大，那是手感而不是样式。
///
library;

// 引入设计令牌总表：本表只负责给首页里的元素起业务名字，
// 具体数值凡是总表有台阶的一律引用台阶（相当于页面专属 CSS 继承基础 CSS）。
import '../../../common/design/design.dart';

///
/// 首页骨架：页面留白、分组标题条、两个确认弹窗与加载态。
///
abstract final class HomeLayout {
  ///
  /// 页面左右统一留白。
  ///
  /// 首页所有横向内容都按这条线对齐：问候语、搜索框、单词行、数据面板卡片。
  static const double pageInset = AppSpace.pBase;

  ///
  /// 分组标题条的行高。
  ///
  /// 这个值出现在两个地方且**必须完全一致**：滚动吸顶委托拿它算吸顶高度，
  /// 标题条本身拿它写死高度。收敛前两处各写了一遍 34，改一处另一处就会错位，
  /// 表现为吸顶时标题条上下抖一下。
  static const double sectionHeaderHeight = 34;

  ///
  /// 分组标题条上「整组勾选框」的边长。
  ///
  /// 指到总表那一档：它和单词列表每一行行首的勾选框是同一个控件，多选模式下
  /// 两者同屏出现，大小必须一致。
  static const double sectionCheckboxSize = AppSize.checkbox;

  ///
  /// 数据还没读回来时，屏幕中央那个小转圈的直径。
  static const double loadingIndicatorSize = 20;

  // 「确认弹窗底部两个按钮的高度」这一档已经删除：删除单词、清空数据两个弹窗
  // 都换成了公共组件 `AppConfirmDialog`，按钮高度跟着搬进
  // `AppConfirmDialogLayout.buttonHeight`，并从 38 抬到了 44——原来那个值比
  // 全站「可以点的东西不该矮于 44」的下限还矮，而这两颗按钮点错的代价最大。
}

///
/// 顶部问候栏：左侧两行文字 + 右上角菜单按钮。
///
abstract final class HomeHeaderLayout {
  ///
  /// 右上角菜单按钮的点击方块边长。
  ///
  /// 生活化解释：这是一个 40×40 的不可见方块，里面那个 20 的汉堡图标靠右垂直居中。
  /// 方块比图标大一圈，手指落在图标附近也能点开抽屉。
  ///
  /// 指到总表 [AppSize.iconHitBox]：单词表单右上角的关闭按钮是同一个东西，
  /// 两处原本各写了一遍 40。
  static const double menuButtonSize = AppSize.iconHitBox;

  // 「问候语那一行的字距 -0.2」这一档已经删除。它抄的是设计稿里标题「收紧一点」
  // 的写法，但 0.2 像素不到一根头发丝的粗细，屏幕上根本看不出来——而设计稿当初
  // 是不是「为了调而调」也没人说得清。看不出效果的参数留在表里只会让人以为
  // 「这里有讲究」，所以直接去掉。
}

///
/// 搜索框。
///
abstract final class WordSearchFieldLayout {
  ///
  /// 输入框高度。
  static const double fieldHeight = 40;

  ///
  /// 左侧放大镜图标的占位方块，宽高都用这一个值。
  ///
  /// 和 [fieldHeight] 同高，图标才会严格落在输入框正中。
  static const double iconBoxSize = fieldHeight;
}

///
/// 单词行：列表里每一条单词。
///
/// 4.4.1 起词库顶部不再有「全部 / 难度 N / 无难度」横向筛选胶囊：整行连同
/// 它的分组筛选栏尺寸表一并移除，词库固定按难度分组、默认把全部区块平铺展示。
/// 如果以后还要给横向标签行定高，可再单独补一张小表。
///
abstract final class WordListTileLayout {
  ///
  /// 标题行（拼写 + 喇叭 + 日期）的行高。
  ///
  /// 这个值还被当成算式的分母用：拼写文字把自己的行盒锁成 `headerHeight / 字号`，
  /// 这样文字的几何中心必然落在行的中线上，换任何系统字体都不会上下漂移。
  static const double headerHeight = 40;

  ///
  /// 左滑露出的操作区总宽度：修改 + 删除两块色块。
  static const double actionWidth = actionButtonWidth * 2;

  ///
  /// 单块操作色块的宽度。
  static const double actionButtonWidth = 64;

  ///
  /// 右侧日期列的固定宽度。
  ///
  /// 写死宽度让所有行的日期右边缘对齐成一条线；三个时间全缺时显示占位的 `00.00`，
  /// 占位与真实日期一样宽，列宽不会跳。
  static const double dateColumnWidth = 40;

  ///
  /// 释义区左侧词性列的固定宽度。
  static const double posColumnWidth = 36;

  ///
  /// 选择模式下行首勾选框的边长。
  ///
  /// 与上方分组标题条的整组勾选框同指总表 [AppSize.checkbox]。
  static const double checkboxSize = AppSize.checkbox;

  ///
  /// 右侧难度徽标的高度。
  static const double difficultyBadgeHeight = 22;

  ///
  /// 右侧难度徽标的最小宽度。
  ///
  /// 用最小宽度而不是写死宽度：难度从一位数变成两位数时，徽标能自己变宽。
  static const double difficultyBadgeMinWidth = difficultyBadgeHeight;

  ///
  /// 正在朗读时那个手绘声纹图标的画布宽度。
  static const double speakerIconWidth = 18;

  ///
  /// 正在朗读时那个手绘声纹图标的画布高度。
  ///
  /// 比宽度矮 2：喇叭右侧那三道弧线要贴着画布右边缘画完，画布再高就显得空。
  static const double speakerIconHeight = 16;
}

///
/// 右下角学习悬浮按钮：主按钮 + 展开后那叠模式条。
///
abstract final class LearningFabLayout {
  ///
  /// 主按钮（收起状态那颗胶囊）的高度。
  static const double mainButtonHeight = 46;

  ///
  /// 展开后每一条模式行的高度。
  static const double itemHeight = 40;

  ///
  /// 主按钮的投影高度。
  ///
  /// 「投影高度」是 Material 的说法：数字越大，投影越散越远，看着离页面越高。
  /// 这一叠三个数字构成层次——主按钮最高、模式行次之、「继续」最贴纸面，
  /// 用户一眼就能看出谁压在谁上面。
  static const double mainElevation = 8;

  ///
  /// 展开后每一条模式行的投影高度。
  static const double itemElevation = 6;

  ///
  /// 模式行里「继续」小按钮的投影高度。
  static const double continueElevation = 2;

  // 「主按钮文字的字距 0.5」这一档已经删除。半个像素的字距说是「白字压蓝底更清楚」，
  // 可实际上把手机举到眼前也分辨不出加没加；真正让白字清楚的是主色底的深浅和字重。
}

///
/// 左侧抽屉：应用信息、新增单词、离线语音包、各类设置。
///
abstract final class HomeDrawerLayout {
  ///
  /// 抽屉展开后的宽度。
  static const double width = 252;

  ///
  /// 抽屉顶部应用图标的边长（正方形，源图 1024×1024 缩放而来）。
  static const double logoSize = 42;

  ///
  /// 抽屉里各段之间那条分隔线所占的高度。
  ///
  /// 注意这里是 Material `Divider` 的 `height`，指**整条分隔线控件占多高**，
  /// 不是线本身多粗。给成一根线的粗细（[AppStroke.thin]）就等于说
  /// 「除了那条线本身，上下不要留任何空隙」，段与段才能紧贴。
  static const double dividerHeight = AppStroke.thin;

  ///
  /// 「新增单词」主按钮的高度。
  static const double addWordButtonHeight = 38;

  ///
  /// 离线语音包下载进度条的粗细。
  ///
  /// 明确压到 4，否则 Material 会按自己的默认值把它画得更粗。
  static const double speechCacheBarHeight = 4;

  ///
  /// 设置项右侧控件的统一宽度。
  ///
  /// 口语发音、单词分隔、每日复习、词义连连时长这几行右边的控件都用这一个宽度，
  /// 竖着看过去右边缘才是一条直线。这一档在本页内是**必须一致**的，改它会同时
  /// 影响四行——这正是想要的效果。
  static const double controlWidth = 108;

  ///
  /// 分段选择器整条轨道的高度。
  ///
  /// 由内部结构决定：上下各一档常规内边距（[AppSpace.p2] = 8）加上中间
  /// [controlSegmentHeight] 高的段钮，一共 42。
  static const double controlTrackHeight =
      AppSpace.p2 * 2 + controlSegmentHeight;

  ///
  /// 分段选择器里单个段钮、以及加减按钮的高度。
  static const double controlSegmentHeight = 26;

  ///
  /// 加减控件中间那个数值的最小宽度。
  ///
  /// 用最小宽度：数值从 5 变成 100 时能自己变宽，两侧的加减按钮不会被挤动。
  static const double stepperValueMinWidth = 34;

  ///
  /// 普通设置行的行高。
  ///
  /// 指到总表 [AppSize.settingsRow]：随身听设置面板里的每一项是同一种行，
  /// 用户会先在抽屉里改一次再进随身听改一次，行高不同会显得是两套界面。
  static const double rowHeight = AppSize.settingsRow;
}

///
/// 新增 / 编辑单词表单：从底部升起的那张面板。
///
abstract final class WordFormLayout {
  ///
  /// 右上角关闭按钮的点击方块边长。
  ///
  /// 与首页右上角的菜单按钮同指总表 [AppSize.iconHitBox]：都是「40 的方块里放
  /// 一个 20 的图标」。
  static const double closeButtonSize = AppSize.iconHitBox;

  ///
  /// 「单词」输入框的高度。
  static const double spellingFieldHeight = 44;

  ///
  /// 一条含义内部各行之间的间距。
  ///
  /// 含义块比别处密集（词性、释义、已添加的标签挤在一起），所以用比页面通用
  /// 间距更小的一档，让「同一条含义」在视觉上抱成一团。
  static const double meaningContentGap = AppSpace.p2;

  ///
  /// 词性选择行的高度，也是词性标签横向滚动区的高度。
  ///
  /// 由 34 减去上下各 2 得来：词性标签本身是普通行高，但表单里行挨得紧，
  /// 上下各收 2 才不显拥挤。
  static const double posRowHeight = 30;

  ///
  /// 删除某条含义那个小图标按钮的边长。
  static const double deleteButtonSize = posRowHeight;

  ///
  /// 释义草稿输入行的高度。
  static const double meaningInputHeight = 36;

  ///
  /// 底部「保存 / 取消」按钮的高度。
  static const double submitButtonHeight = 40;

  ///
  /// 「添加含义」那圈虚线框的圆角。
  static const double dashedBorderRadius = AppRadius.roundedLg;

  ///
  /// 虚线框每一小段实线的长度。
  ///
  /// 贴 Tabler 档之前这里是 6、步长是 10；两档并档后双双落到 8，虚线就会连成
  /// 一条实线（画 8、走 8，空白为 0）。所以实线降到最小的一档，让「画一段、
  /// 空一段」重新成立。
  static const double dashLength = AppSpace.p1;

  ///
  /// 虚线框「一段实线 + 一段空白」的完整步长。
  ///
  /// 空白长度就是步长减去实线长度（8 − 4 = 4），实线与空白正好等长。按步长而不是
  /// 按空白记，是因为画的时候是「走一步、画一段」，步长才是循环里真正用到的那个数。
  static const double dashStride = AppSpace.p2;

  ///
  /// 虚线框整体向内缩进的距离。
  ///
  /// 取线宽的一半：画笔以路径为中心线左右各画半个线宽，不内缩的话外侧那半个
  /// 线宽会落在画布外被裁掉，虚线看着就比另外三边细。
  static const double dashedBorderInset = AppStroke.thin / 2;
}

///
/// 词库抽屉：从底部升起、占屏幕大半高度的那张面板。
///
abstract final class WordLibraryLayout {
  ///
  /// 面板展开后的高度，按屏幕高度的比例算。
  ///
  /// 用比例而不是写死高度：手机屏幕高矮差很多，写死高度在小屏上会顶到状态栏。
  /// 留下 12% 的空隙是为了让下面那层页面露一点边，用户知道这是一张盖上来的面板、
  /// 往下一划就能收回去。
  static const double heightRatio = 0.88;

  ///
  /// 面板顶边投影的扩散范围。
  ///
  /// 比 Toast 那颗小胶囊（`ToastLayout.capsuleShadowBlur`，8）散得多得多：
  /// 这是一张盖满整屏的大面板，影子必须足够开阔才显得「压在页面上面」。
  /// 名字带 `panel` 就是为了不和胶囊那一档混作一谈。
  static const double panelShadowBlur = AppSpace.pBase;

  ///
  /// 面板投影的偏移量：负值表示投影往**上**打。
  ///
  /// 面板是从下往上盖过来的，光源在上方，所以影子要落在面板上边缘之外，
  /// 才像是这张纸浮在页面上面。
  static const double panelShadowOffsetY = -AppSpace.p1;

  ///
  /// 每一行复习模式的行高。
  static const double modeRowHeight = 48;

  ///
  /// 「继续」与「重新开始」之间那条竖分隔线的高度。
  ///
  /// 比行高矮一截，上下各留白，看着像一条分隔而不是把整行切成两半。
  static const double modeDividerHeight = 26;

  ///
  /// 「继续」小按钮的宽度（高度与整行齐平）。
  static const double continueButtonWidth = 40;

  ///
  /// 面板顶部那条拖拽提示条的整块占位高度。
  static const double dragBarAreaHeight = 32;

  ///
  /// 拖拽提示条本身的宽度。
  static const double dragBarWidth = 40;

  ///
  /// 拖拽提示条本身的高度。
  ///
  /// 5 是刻意的奇数：这条提示条两端是全圆角，高度就是它的直径，
  /// 5 比 4 更容易看见、比 6 更不像一个可点的按钮。
  static const double dragBarHeight = 5;
}

///
/// 数据面板：打卡热力图、复习模式卡、复习趋势三块卡片。
///
abstract final class HomeDashboardLayout {
  ///
  /// 数据面板的左右安全边界。
  ///
  /// 与 [HomeLayout.pageInset] 同源：面板里的卡片、趋势图的第一个和最后一个
  /// 节点都要落在这条线上，否则折线会贴到屏幕边上。
  static const double edgeInset = HomeLayout.pageInset;

  ///
  /// 复习模式卡的投影高度：0 表示**不投影**。
  ///
  /// 数据面板本身已经是一片浅色底，模式卡再浮起来会显得层层叠叠；这里改用描边
  /// 划出边界，整块面板看着更平整。写成一档而不是直接写 0，是为了让「这里刻意
  /// 不要投影」这句话留在表里，免得以后有人以为漏了。
  static const double cardElevation = 0;

  ///
  /// 复习模式卡底部那条进度条的粗细。
  static const double modeProgressHeight = 4;

  ///
  /// 底部「上滑提示」行左右两条分割线的固定长度。
  ///
  /// 原来是 `Expanded(Divider)`：文字越短，两条线就越长，整行被撑成
  /// 接近半屏宽的粗横线，文字反而像「——」里夹的一小段。改成 64dp
  /// 的固定宽度，让两条线保持短促、「—— 文本 ——」式提示感更强；
  /// 同时把 Row 整体居中，文字仍稳稳落在屏幕中线上。
  static const double swipeIndicatorDividerWidth = 64;

  ///
  /// 趋势卡上方「周 / 月」切换标签下那条选中横线的宽度。
  static const double rangeTabUnderlineWidth = AppSpace.pBase;

  ///
  /// 那条选中横线的粗细。
  static const double rangeTabUnderlineHeight = 3;

  ///
  /// 热力图里每个日期格子的边长。
  static const double heatmapCellSize = 20;

  ///
  /// 热力图下方图例里那几个小色块的边长。
  static const double heatmapLegendSize = AppSpace.p2;

  ///
  /// 热力图图例前那个更小的等级色点的边长。
  static const double heatmapSwatchSize = 7;

  ///
  /// 热力图与趋势图内部文字的**放大上限**。
  ///
  /// 这两张图是按格子和坐标排的，格子高度写死，字号却会跟着系统「字体大小」
  /// 一起放大——放太大就会把数字挤出格子。所以这里给字号加一道上限：系统调到
  /// 两倍字体时，图里的字最多也只放大到 1.15 倍。
  /// 这个上限量过：320 逻辑像素宽 + 两倍字体的极限用例下，格子里的数字仍然放得下。
  /// 具体余量由 `test/font_scale_pressure_test.dart` 逐档守着，这里不写死数字——
  /// 页面留白改一档，余量就跟着变。
  static const double maxTextScale = 1.15;
}

///
/// 数据面板里那张折线图。
///
/// 这张图是用画笔一笔一笔画出来的，所以下面这些数字比别处更「几何」一点：
/// 它们决定线画在哪、点画多大、文字落在哪。
///
abstract final class TrendChartLayout {
  ///
  /// 图表默认高度。
  static const double height = 140;

  ///
  /// 底部留给日期文字的高度。
  ///
  /// 折线的基准分割线就画在「图表高度减去这一档」的位置上，日期文字排在它下面。
  static const double labelSpace = AppSpace.p3;

  ///
  /// 顶部留白。
  ///
  /// 最高的那个数据点不顶到图表上边缘，而是停在这条线上，给它头顶的数字留位置。
  static const double topPadding = 30;

  ///
  /// 数据点外圈的半径。
  static const double dotOuterRadius = 4.5;

  ///
  /// 数据点中心那个「挖空」的半径。
  ///
  /// 用背景色画一个更小的圆盖在外圈上，就得到一个空心圆环——比画环省事，
  /// 而且线从点下面穿过时不会露出来。
  static const double dotCoreRadius = 2;

  ///
  /// 未被选中的数据点的半径（实心小点）。
  static const double dotPlainRadius = 3;

  ///
  /// 选中数据点上方那个数值与点之间的距离。
  static const double valueLabelGap = AppSpace.p2;

  ///
  /// 日期文字与基准分割线之间的距离。
  static const double axisLabelGap = AppSpace.p1;
}
