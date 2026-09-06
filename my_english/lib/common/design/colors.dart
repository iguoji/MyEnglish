// material.dart 提供 Color、BuildContext 与 Theme。
import 'package:flutter/material.dart';

///
/// 全 App 的颜色令牌集合。
///
/// 这是六张总表里唯一**跟随明暗模式变化**的一张，所以它必须通过
/// [AppTokens.of] 从 context 里取；间距、字号、圆角、图标、时长都是编译期常量，
/// 不需要 context。
///
/// 两组实例 [light] / [dark] 一一对应，字段名与设计稿的 CSS 变量同名
/// （cPage / cCard / cTx …），改配色时两边一起改，不会漏。
///
/// 另有一组**不随明暗变化**的语义色（[primary] / [danger] / [success] /
/// [warning]）挂在静态成员上：品牌蓝和红绿橙在两套主题里是同一个值，
/// 分开写只会让两处慢慢跑偏。
///
class AppTokens {
  ///
  /// 私有构造器；只允许使用下方两个预设实例。
  const AppTokens._({
    required this.page,
    required this.card,
    required this.sub,
    required this.expand,
    required this.capsule,
    required this.inner,
    required this.innerBorder,
    required this.badgeBorder,
    required this.definition,
    required this.border,
    required this.rowBorder,
    required this.text,
    required this.textSecondary,
    required this.textMedium,
    required this.inputBorder,
    required this.muted,
    required this.check,
    required this.listDate,
    required this.listDateEmpty,
    required this.checkinLevel0,
    required this.checkinLevel1,
    required this.checkinLevel2,
    required this.checkinLevel4,
    required this.cardShadow,
    required this.scrollThumb,
    required this.badgeAzureBg,
    required this.badgeAzureText,
    required this.keyPanel,
    required this.keyFace,
    required this.keyInk,
    required this.keyPressFace,
    required this.keyDeleteFace,
    required this.keyDeleteInk,
    required this.keyDeletePressFace,
    required this.keyShadow,
  });

  ///
  /// 全 App 统一的页面背景（cPage）。
  ///
  /// 首页、随身听、听音辨义、拼写巩固、看义选词、词义连连六个页面的 Scaffold
  /// 都读这一个值，所以「换掉页面底色」只需要改下面 [light] / [dark] 两处。
  ///
  /// 取值与 `ThemeData.scaffoldBackgroundColor` 同源，因此没写 `backgroundColor`
  /// 的页面也落在同一个底色上，不会出现两种「白」。
  ///
  /// 注意：这个令牌只表示「页面最底层的那张纸」。想给某个控件一块浅灰底，
  /// 请用 [sub] 或 [capsule]，不要借用 page。
  final Color page;

  ///
  /// 卡片与列表表面（cCard）。
  ///
  /// 用在：六个页面里所有白卡——听音辨义题目卡、拼写巩固正文白卡、
  /// 看义选词白卡、词义连连棋盘上的候选卡、四个模块结算页的统计卡。
  final Color card;

  ///
  /// 次级底色，如分组头与开关轨道（cSub）。
  ///
  /// 用在：四个模块顶栏下方进度条的底槽、候选卡左侧 A/B/C/D 序号方块的底色。
  final Color sub;

  ///
  /// 展开释义区域底色（cExp）。
  final Color expand;

  ///
  /// 播音胶囊的胶囊底色。
  ///
  /// 数值与 [page] 相同，但刻意单独列一个令牌：胶囊永远躺在白卡上，它需要的是
  /// 「比卡片略深一点的浅灰」，和「页面底色」是两件事。分开之后，以后调整页面
  /// 底色不会顺手把胶囊也调没了。
  ///
  /// 用在：听音辨义 / 拼写巩固 → 正文中央的播音胶囊外框。
  final Color capsule;

  ///
  /// 白卡内部的「内层卡面」（原型 `#FAFBFC` 淡蓝灰）。
  ///
  /// 用在：词性及含义面板 → 每张含义卡的底色（拼写巩固与听音辨义共用）。
  final Color inner;

  ///
  /// 内层卡面的边框，同时也是面板标题右侧那条横线（原型 `#F1F5F9`）。
  ///
  /// 用在：词性及含义面板 → 含义卡描边、标题「词性及含义」右侧的横线。
  final Color innerBorder;

  ///
  /// 词性徽标的边框（原型 `#E2E8F0`）。
  ///
  /// 用在：词性及含义面板 → 含义卡左侧 `n.` / `adj.` 徽标的描边。
  final Color badgeBorder;

  ///
  /// 含义正文的文字色（原型 `#334155`）。
  ///
  /// 比正文主色 [text] 略淡一档：含义是被解释的内容，不该比单词本身更抢眼。
  ///
  /// 用在：词性及含义面板 → 含义卡右侧的中文释义。
  final Color definition;

  ///
  /// 分组与区域分隔线（cBd）。
  final Color border;

  ///
  /// 列表行分隔线（cRb）。
  final Color rowBorder;

  ///
  /// 主要文字（cTx）。
  final Color text;

  ///
  /// 次要文字（cTs）。
  final Color textSecondary;

  ///
  /// 中等强调文字（cTm）。
  ///
  /// 用在：四个模块顶栏的返回图标与右上角计时。
  final Color textMedium;

  ///
  /// 输入框与按钮边框（cIb）。
  ///
  /// 用在：听音辨义候选卡、词义连连棋盘卡的描边。
  final Color inputBorder;

  ///
  /// 弱化文字，如计数与占位（cMut）。
  final Color muted;

  ///
  /// 未选中复选框边框与开关轨道（chk）。
  ///
  /// 用在：字母格里「还没轮到」的下划线、词义连连的锚点圆点与中央虚线。
  final Color check;

  ///
  /// 列表右侧日期的极淡灰：刻意比 textSecondary 更弱，让辅助信息不抢眼。
  final Color listDate;

  ///
  /// 列表右侧无日期占位"00.00"的更淡灰：比 listDate 还弱。
  final Color listDateEmpty;

  /// 打卡梯度色：第 0 档（未复习）。对应原型 --level-0。
  final Color checkinLevel0;

  /// 打卡梯度色：第 1 档（少量/未达标）。对应原型 --level-1。
  final Color checkinLevel1;

  /// 打卡梯度色：第 2 档（刚好达标）。对应原型 --level-2。
  final Color checkinLevel2;

  /// 打卡梯度色：最高档（超额完成）。对应原型 --level-4。
  final Color checkinLevel4;

  /// 卡片轻阴影色，对应原型 box-shadow 的投影。
  final Color cardShadow;

  ///
  /// 滚动条滑块颜色。
  ///
  /// 深色下比浅色更亮一点，保证真机上找得到、拖得动。
  ///
  /// 用在：首页词库长列表、各页面正文的滚动条。
  final Color scrollThumb;

  ///
  /// Azure 徽章的底色（首页抽屉顶部与添加单词表单里的「Azure」小标签）。
  ///
  /// 收进令牌之前，抽屉与表单各自写了一遍「浅色 10% 透明、深色 20% 透明」的
  /// 判断，两处都要自己去问一次当前亮度。现在亮度判断由 [AppTokens.of] 一次
  /// 完成，两个页面直接取值。
  final Color badgeAzureBg;

  ///
  /// Azure 徽章的文字色：浅色底用加深的 azure，深色底用标准 azure。
  final Color badgeAzureText;

  ///
  /// 拼写键盘的面板底色（原型 `--tblr-keybg` 的灰蓝 `#E9EDF2`）。
  ///
  /// 拼写巩固页把系统手势导航区也染成这个色，键盘下方才不会露出一条白缝。
  final Color keyPanel;

  ///
  /// 字母键的键帽底色（浅色下是纯白）。
  final Color keyFace;

  ///
  /// 键帽上字母的颜色。
  final Color keyInk;

  ///
  /// 字母键按下瞬间的键帽底色（原型 `.key:active`）。
  final Color keyPressFace;

  ///
  /// 删除键的键帽底色：比字母键深一档，一眼能认出这颗不是字母。
  final Color keyDeleteFace;

  ///
  /// 删除键里退格图标的颜色。
  final Color keyDeleteInk;

  ///
  /// 删除键按下瞬间的键帽底色：比它自己的常态再深一档。
  final Color keyDeletePressFace;

  ///
  /// 键帽下方那道 1 像素投影的颜色（原型 `0 1px 0 rgba(24,36,51,0.18)`）。
  final Color keyShadow;

  ///
  /// 品牌主色（Tabler `$primary` = `$blue` = `#206BC4`）。
  ///
  /// 名字就叫 [primary]，和 Tabler 的 SCSS 变量、以及它那一族
  /// `.text-primary` / `.bg-primary` / `.btn-primary` class 完全对得上。
  ///
  /// 用在：进度条、选中态、词性徽标文字、播音按钮、结算页主按钮、
  /// 看义选词的「选择对应的单词」标签。
  static const Color primary = Color(0xFF206BC4);

  ///
  /// 深色模式下提亮的品牌蓝（`#6EA8E5`）。
  ///
  /// 只给 Material 自己的 ColorScheme.primary 和 SnackBar 按钮用；页面里的
  /// 品牌蓝一律用 [primary]，明暗两套保持同一个蓝。
  static const Color primaryBright = Color(0xFF6EA8E5);

  ///
  /// 危险色（Tabler red `#d63939`）。
  ///
  /// 用在：答错反馈（红框 + 抖动）、结算页「失误次数」、删除类操作、
  /// 词义连连倒计时最后三分之一。
  static const Color danger = Color(0xFFD63939);

  ///
  /// 深色模式下提亮的危险色（`#FF6B6B`），同样只给 ColorScheme 用。
  static const Color dangerBright = Color(0xFFFF6B6B);

  ///
  /// 成功色（Tabler green `#2fb344`）。
  ///
  /// 收进令牌之前，这个值在拼写巩固、看义选词、词义连连三个页面里各写了一遍
  /// （`_kSuccess`），改一处另外两处不会跟着变。
  ///
  /// 用在：拼写巩固答对的字母与提示、看义选词答对的候选与已填字母、
  /// 词义连连连对的卡片与绿色连线、结算页「完成词汇 / 一次拼对」。
  static const Color success = Color(0xFF2FB344);

  ///
  /// 警告色（Tabler orange `#f76707`）。
  ///
  /// 收进令牌之前，拼写巩固与词义连连各写了一遍 `_kOrange`，而这里早就有同值。
  ///
  /// 用在：结算页「需加强 / 最高连对」、拼写巩固结算页只错过一两次的词条、
  /// 词义连连倒计时进入后三分之二的中段提示。
  static const Color warning = Color(0xFFF76707);

  ///
  /// 成功色的 13% 淡底（`#2FB344` 加 0x22 透明度）。
  ///
  /// 用在：听音辨义 → 完成态 → 打勾图标外面那圈淡绿圆盘。
  static const Color successSoft = Color(0x222FB344);

  ///
  /// 更深一档的橙（Tabler orange-7 `#e8590c`）。
  ///
  /// 和 [warning] 是同一族的两档：warning 用于文字与徽章，这一档专门给
  /// 需要「烧起来」的图标，压在浅色底上比 warning 更沉、不发飘。
  ///
  /// 用在：首页 → 打卡热力图卡片 → 右上角「连续 N 天」前面的火焰图标。
  static const Color warningDeep = Color(0xFFE8590C);

  ///
  /// Toast 气泡的底色（深色 `#182433`）。
  ///
  /// 刻意不随明暗模式变化：Toast 是浮在页面之上的一层「黑板」，
  /// 浅色主题下靠深底压住页面，深色主题下靠它与卡片区分，两套用同一个值。
  static const Color toastSurface = Color(0xFF182433);

  ///
  /// Toast 气泡的投影（20% 黑）。与 [toastSurface] 同理，不随明暗变化。
  static const Color toastShadow = Color(0x33000000);

  ///
  /// 键盘面板顶边那条细线（原型 `border-black/[0.06]`，即 6% 黑）。
  ///
  /// 两套主题同一个值：它是一层黑纱，浅色下是浅灰线，深色下自然隐形——
  /// 这正是想要的效果，深色面板本身已经和上方正文分开了。
  static const Color keyPanelBorder = Color(0x0F000000);

  ///
  /// 浅色令牌，与设计稿浅色 CSS 变量一致。
  static const AppTokens light = AppTokens._(
    page: Color(0xFFF6F8FB),
    card: Color(0xFFFFFFFF),
    sub: Color(0xFFF1F4F7),
    expand: Color(0xFFF8FAFC),
    // 与 page 同值：胶囊在白卡上就是这个浅灰，只是两者从此各管各的。
    capsule: Color(0xFFF6F8FB),
    inner: Color(0xFFFAFBFC),
    innerBorder: Color(0xFFF1F5F9),
    badgeBorder: Color(0xFFE2E8F0),
    definition: Color(0xFF334155),
    border: Color(0xFFE6E7E9),
    rowBorder: Color(0xFFEEF0F3),
    text: Color(0xFF182433),
    textSecondary: Color(0xFF667382),
    textMedium: Color(0xFF3F4A58),
    inputBorder: Color(0xFFDCE1E7),
    muted: Color(0xFF9AA3AF),
    check: Color(0xFFC6CCD3),
    // 比 muted 更浅，确保日期在白色卡片上几乎只是淡淡的水印感。
    listDate: Color(0xFF7E868F),
    // 无日期占位"00.00"比有日期更淡，接近背景几乎不可见。
    listDateEmpty: Color(0xFFE0E4E9),
    checkinLevel0: Color(0xFFEBEDF0),
    checkinLevel1: Color(0xFFC6E4FF),
    checkinLevel2: Color(0xFF73B3F3),
    checkinLevel4: Color(0xFF0066CC),
    cardShadow: Color(0x0A000000),
    scrollThumb: Color(0xFF9AA6B2),
    badgeAzureBg: Color(0x1A45AAF2),
    badgeAzureText: Color(0xFF2B94D4),
    keyPanel: Color(0xFFE9EDF2),
    keyFace: Color(0xFFFFFFFF),
    keyInk: Color(0xFF182433),
    keyPressFace: Color(0xFFD7DEE7),
    keyDeleteFace: Color(0xFFCCD4DE),
    keyDeleteInk: Color(0xFF4A5468),
    keyDeletePressFace: Color(0xFFB9C3CF),
    keyShadow: Color(0x2E182433),
  );

  ///
  /// 深色令牌，字段含义与浅色完全一致，只替换取值。
  static const AppTokens dark = AppTokens._(
    page: Color(0xFF141A22),
    card: Color(0xFF1B232E),
    sub: Color(0xFF212B37),
    expand: Color(0xFF1F2833),
    // 深色下胶囊同样比卡片深一档，与 page 取值一致。
    capsule: Color(0xFF141A22),
    // 深色里「内层卡面」比白卡更亮一点才浮得起来，取 expand 同值。
    inner: Color(0xFF1F2833),
    innerBorder: Color(0xFF2B3644),
    badgeBorder: Color(0xFF364250),
    // 深色下含义正文直接用主文字色，再压暗就看不清了。
    definition: Color(0xFFE6EBF1),
    border: Color(0xFF2B3644),
    rowBorder: Color(0xFF26303C),
    text: Color(0xFFE6EBF1),
    textSecondary: Color(0xFF93A0AF),
    textMedium: Color(0xFFC3CCD6),
    inputBorder: Color(0xFF364250),
    muted: Color(0xFF71808F),
    check: Color(0xFF4A5866),
    listDate: Color(0xFF98A4B2),
    listDateEmpty: Color(0xFF3A4350),
    checkinLevel0: Color(0xFF2A323D),
    checkinLevel1: Color(0xFF1E3A5F),
    checkinLevel2: Color(0xFF2F6FB0),
    checkinLevel4: Color(0xFF6EA8E5),
    cardShadow: Color(0x33000000),
    scrollThumb: Color(0xFF7B8794),
    badgeAzureBg: Color(0x3345AAF2),
    badgeAzureText: Color(0xFF45AAF2),
    keyPanel: Color(0xFF1C2530),
    keyFace: Color(0xFF2A3644),
    keyInk: Color(0xFFE6EBF1),
    keyPressFace: Color(0xFF232F3C),
    keyDeleteFace: Color(0xFF39485A),
    keyDeleteInk: Color(0xFFC3CCD6),
    keyDeletePressFace: Color(0xFF2C3A4A),
    keyShadow: Color(0x55000000),
  );

  ///
  /// 按当前主题亮度返回对应令牌集合。
  static AppTokens of(BuildContext context) {
    // 深色主题返回深色令牌，其余返回浅色令牌。
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}
