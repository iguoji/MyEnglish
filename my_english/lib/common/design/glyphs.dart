// widgets.dart 只为了 IconData 这个类型；本表不碰任何界面组件，所以不引 material。
import 'package:flutter/widgets.dart';

// tabler_icons_plus 是项目唯一允许的界面图标来源，本表是它的唯一入口。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

///
/// 全 App 的**图标语义表**：界面上每一个图标画的是什么。
///
/// 和 `AppIcon` 的分工，一句话说清：
///
/// - `AppIcon` 说的是「**多大**」——16 还是 20；
/// - `AppGlyph` 说的是「**画什么**」——是一把放大镜还是一个叉。
///
/// 为什么需要这张表：Tabler 里表达同一个意思的图标往往有好几个。
/// 「重来」可以是 `refresh`，也可以是 `rotateClockwise`；「扬声器」有 `volume`、
/// `volume2`、`volume3`。收进这张表之前，本项目就已经出现了这个问题——结算页的
/// 「再练一组」用 `rotateClockwise`，听音辨义的「再试一次」用 `refresh`，
/// 两个按钮做的是同一件事，图标却是两个。谁也没写错，只是各自选了一个。
///
/// 所以规矩是：**页面里不再出现 `TablerIcons.` 这个前缀**，一律写语义名。
/// 想换某个图标，只改本表这一处；想新增一个图标，先在本表起个名字。
/// `test/icon_policy_test.dart` 会守着这条规矩。
///
/// 命名方式是**按用途**，不是按图形。所以会出现「同一个图形，两个名字」：
/// [dismiss] 和 [wrong] 都是那个叉。这不是冗余——「关闭」和「答错」是两件事，
/// 以后想把答错的叉换成一个红色感叹号，不该顺手把所有关闭按钮也换掉。
///
abstract final class AppGlyph {
  // ===== 通用命令 =====

  ///
  /// 关闭 / 取消 / 收起。
  ///
  /// 用在：对话框的取消按钮、底部面板右上角的关闭、首页学习菜单的「收起」。
  static const IconData dismiss = TablerIcons.x;

  ///
  /// 答错 / 失误。
  ///
  /// 和 [dismiss] 是同一个叉，但含义完全不同：这个叉出现在「拼写有误」这类
  /// 反馈文字旁边，以及结算页「答错 N 次」那张统计卡上。
  static const IconData wrong = TablerIcons.x;

  ///
  /// 删掉列表里的一小项（释义标签上那个小叉）。
  ///
  /// 又是同一个叉。单独起名是因为它既不是「关闭」也不是「答错」，
  /// 而是「把这一条去掉」。
  static const IconData removeTag = TablerIcons.x;

  ///
  /// 答对了。
  ///
  /// 用在：拼写正确的反馈文字旁、配对成功的词汇卡、整轮练完那个大绿勾。
  static const IconData correct = TablerIcons.check;

  ///
  /// 已选中。
  ///
  /// 和 [correct] 是同一个勾，但说的是「你挑了这一项」而不是「你答对了」。
  /// 用在：多选模式下每行行首的勾选框、分组标题条上的整组全选、
  /// 下拉菜单里标记当前选项。
  ///
  /// 分开起名是为了留出余地：以后想把答对的勾换成一个绿色圆勾，
  /// 不该把首页那一排勾选框也跟着换掉。
  static const IconData selected = TablerIcons.check;

  ///
  /// 做完最后一题的「完成」按钮。
  ///
  /// 还是那个勾。它和 [correct] 的区别是：这个勾出现在按钮上、代表
  /// 「点下去就收工」，而不是对某一题的评判。
  static const IconData finish = TablerIcons.check;

  ///
  /// 全对 / 一气呵成（带圆圈的勾，比裸勾更有「盖章」感）。
  static const IconData allCorrect = TablerIcons.circleCheck;

  ///
  /// 新增一条（新增单词、再加一组词性与含义）。
  static const IconData add = TablerIcons.plus;

  ///
  /// 删除某一条（表单里删掉一组词性与含义）。
  static const IconData delete = TablerIcons.trash;

  ///
  /// 清空全部数据。
  ///
  /// 和 [delete] 是同一个垃圾桶。分开起名是因为后果差着量级：一个删一行，
  /// 一个删全部；以后想给「清空全部」换一个更吓人的图标，不该连带改掉前者。
  static const IconData clearAll = TablerIcons.trash;

  ///
  /// 加减控件的「加」。
  ///
  /// 和 [add] 是同一个加号，但那是「新增一条记录」，这是「把数字调大一档」。
  static const IconData stepUp = TablerIcons.plus;

  ///
  /// 加减控件的「减」。
  static const IconData stepDown = TablerIcons.minus;

  ///
  /// 重来：刷新候选词、再试一次、再练一组，全部用这一个。
  ///
  /// 收敛前结算页用的是 `rotateClockwise`、听音辨义用的是 `refresh`，
  /// 同一件事两个图标。现在只有这一档。
  static const IconData retry = TablerIcons.refresh;

  ///
  /// 键盘上的退格。
  static const IconData backspace = TablerIcons.backspace;

  // ===== 导航与方向 =====

  ///
  /// 返回上一屏（各模块左上角那个「<」）。
  static const IconData back = TablerIcons.chevronLeft;

  ///
  /// 前进到下一题。
  static const IconData nextQuestion = TablerIcons.arrowRight;

  ///
  /// 打卡日历翻到上一个月。
  ///
  /// 和 [back] 是同一个「<」。分开起名是因为一个是「离开这一屏」、
  /// 一个是「在这一屏里换一页」，将来完全可能换成不同的箭头。
  static const IconData previousMonth = TablerIcons.chevronLeft;

  ///
  /// 打卡日历翻到下一个月。
  static const IconData nextMonth = TablerIcons.chevronRight;

  ///
  /// 展开 / 收起单词行的释义（行尾那个会转 90 度的箭头）。
  static const IconData expandRow = TablerIcons.chevronRight;

  ///
  /// 下拉选择器的收起箭头（朝下的「v」）。
  static const IconData dropdown = TablerIcons.chevronDown;

  ///
  /// 随身听列表「跳到上一个」。
  static const IconData scrollUp = TablerIcons.arrowUp;

  ///
  /// 随身听列表「跳到下一个」。
  static const IconData scrollDown = TablerIcons.arrowDown;

  ///
  /// 排序入口（上下两个交错的箭头）。
  static const IconData sort = TablerIcons.arrowsSort;

  ///
  /// 当前按升序排（小的在前）。
  static const IconData sortAscending = TablerIcons.arrowUp;

  ///
  /// 当前按降序排（大的在前）。
  static const IconData sortDescending = TablerIcons.arrowDown;

  // ===== 四个练习模块的门牌图标 =====
  //
  // 这四档是**同一枚图标在三处露脸**：首页学习菜单、词库面板的模式行、
  // 数据面板的复习模式卡。收进本表之前，三处各自写了一遍图标名——
  // 只要有一处漏改，用户就会觉得「首页那个耳机和词库里那个不是一个东西」。

  ///
  /// 学习总入口（一本书）。
  static const IconData study = TablerIcons.book;

  ///
  /// 听音默写模块（耳机）。
  static const IconData moduleListening = TablerIcons.headphones;

  ///
  /// 听音辨义模块（铅笔）。
  static const IconData moduleListeningMeaning = TablerIcons.pencil;

  ///
  /// 词义连连模块（一节链条，取「把词和义连起来」的意思）。
  static const IconData moduleMeaningMatch = TablerIcons.link;

  ///
  /// 看义选词模块（带勾的清单）。
  static const IconData moduleMeaningWordChoice = TablerIcons.listCheck;

  // ===== 播放与朗读 =====

  ///
  /// 开始播放（实心三角）。
  static const IconData play = TablerIcons.playerPlay;

  ///
  /// 暂停播放（两根竖条）。
  static const IconData pause = TablerIcons.playerPause;

  ///
  /// 上一个单词。
  static const IconData previousTrack = TablerIcons.playerTrackPrev;

  ///
  /// 下一个单词。
  static const IconData nextTrack = TablerIcons.playerTrackNext;

  ///
  /// 「点这里读一遍」的喇叭（公共组件 `AudioSpeakerButton` 上那个）。
  ///
  /// Tabler 里喇叭有 `volume`（带两道音波）、`volume2`（带一道）、
  /// `volume3`（静音）三个。这一档固定用两道音波那个：它最像「按下会响」。
  static const IconData speaker = TablerIcons.volume;

  ///
  /// 「这个词正在读」的状态指示（音波少一道的喇叭）。
  ///
  /// 刻意和 [speaker] 用不同的图形：一个是可以按的按钮，一个只是状态标记，
  /// 同屏出现时用户能分得出哪个能点。
  static const IconData nowPlaying = TablerIcons.volume2;

  ///
  /// 答案已揭晓（睁开的眼睛）。
  static const IconData revealed = TablerIcons.eye;

  ///
  /// 答案已遮住（划掉的眼睛）。
  static const IconData hidden = TablerIcons.eyeOff;

  // ===== 结算页与提示 =====

  ///
  /// 提醒 / 差一点（三角形里一个感叹号）。
  static const IconData warning = TablerIcons.alertTriangle;

  ///
  /// 值得庆祝（彩带）。
  static const IconData celebrate = TablerIcons.confetti;

  ///
  /// 赢了（奖杯）。
  static const IconData win = TablerIcons.trophy;

  ///
  /// 时间到了（划掉的闹钟）。
  static const IconData timeUp = TablerIcons.alarmOff;

  ///
  /// 连续做对 / 连续打卡（火苗）。
  static const IconData streak = TablerIcons.flame;

  ///
  /// 用时统计（钟表）。
  static const IconData time = TablerIcons.clock;

  ///
  /// 薄弱点提示（灯泡）。
  static const IconData weakSpot = TablerIcons.bulb;

  // ===== 工具与设置 =====

  ///
  /// 搜索（放大镜）。
  static const IconData search = TablerIcons.search;

  ///
  /// 打开左侧抽屉（汉堡菜单）。
  ///
  /// Tabler 里 `menu` 是三道等长横线、`menu2` 是三道对齐得更规整的横线。
  /// 固定用后者：它在小尺寸下更清楚。
  static const IconData menu = TablerIcons.menu2;

  ///
  /// 设置（齿轮）。
  static const IconData settings = TablerIcons.settings;

  ///
  /// 从文件导入单词。
  static const IconData importFile = TablerIcons.fileImport;

  ///
  /// 把单词导出成文件。
  static const IconData exportFile = TablerIcons.fileExport;

  ///
  /// 导出运行日志（带竖线的文档，代表纯文本日志文件）。
  static const IconData logExport = TablerIcons.fileText;

  ///
  /// 下载离线语音包（带下箭头的云）。
  static const IconData download = TablerIcons.cloudDownload;

  ///
  /// 项目仓库链接。
  static const IconData github = TablerIcons.brandGithub;

  ///
  /// 联系邮箱。
  static const IconData mail = TablerIcons.mail;

  ///
  /// 浅色模式（太阳）。
  static const IconData lightMode = TablerIcons.sun;

  ///
  /// 深色模式（月亮）。
  static const IconData darkMode = TablerIcons.moon;
}
