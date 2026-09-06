// material.dart 提供 Widget 类型。
import 'package:flutter/material.dart';

// 数据模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/word.dart';
// 六个被整体检查的页面。
import 'package:my_english/pages/home/home.dart';
import 'package:my_english/pages/listening/listening_page.dart';
import 'package:my_english/pages/listening_meaning/listening_meaning_page.dart';
import 'package:my_english/pages/meaning_match/meaning_match_page.dart';
import 'package:my_english/pages/meaning_word_choice/meaning_word_choice_page.dart';
import 'package:my_english/pages/review/services/session_progress.dart';
import 'package:my_english/pages/spelling_reinforcement/spelling_reinforcement_page.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';
// 顶栏行高来自模块页面模板，四个练习页读的是同一档。
import 'package:my_english/widgets/module_scaffold.dart';

// 内存 Store，避免 Widget 测试触碰原生通道。
import 'memory_session_store.dart';
import 'memory_word_store.dart';

///
/// 「整页级」检查共用的样本页面清单。
///
/// 有两组测试需要把六个页面各渲染一遍：
///
///   - `design_baseline_golden_test.dart`：明暗两套各拍一张基准截图；
///   - `font_scale_pressure_test.dart`：三档字号各渲染一遍，抓文字溢出。
///
/// 两边如果各自准备一份样本词表，迟早会走样——一边加了长单词、另一边没加，
/// 于是「截图里没问题」和「耐压测试里没问题」说的其实是两个不同的页面。
/// 所以样本数据与页面构造只在这里写一份。
///

///
/// 一个样本页面：名字 + 怎么造出来。
///
/// [build] 必须是「每次调用都造一个新实例」的函数而不是现成的 Widget：
/// 页面内部持有会话进度和计时器，复用同一个实例会让上一条用例的状态
/// 漏进下一条。
class SamplePage {
  ///
  /// 声明一个样本页面。
  const SamplePage({
    required this.slug,
    required this.title,
    required this.build,
    this.headerLabelKey,
    this.headerRowHeight,
  });

  ///
  /// 文件名安全的英文短名，用于 golden 图片名（如 `home_light.png`）。
  final String slug;

  ///
  /// 中文页面名，用于测试用例标题。
  final String title;

  ///
  /// 现造一个页面实例。
  final Widget Function() build;

  ///
  /// 顶栏正中那个「第几个 / 总数」的 key；没有顶栏的页面留空。
  ///
  /// 四个练习页的顶栏是一行写死高度的容器（`headerButtonSize`，34），
  /// 里面放着返回按钮、进度数字和计时。字号放大后数字会变高，一旦超过这个
  /// 行高就会被裁掉半截——耐压测试用这两个字段把余量量出来，而不是靠人眼。
  final String? headerLabelKey;

  ///
  /// 上面那行的固定高度；与 [headerLabelKey] 成对出现。
  final double? headerRowHeight;
}

///
/// 样本页面共用的「现在」：2026 年 9 月 5 日上午 10 点半。
///
/// 为什么要钉死一个时刻：首页有好几处会看日历——顶部的问候语（按小时变）、
/// 单词列表按天分组的「今天 / 昨天」、打卡日历里今天那一格、趋势曲线横轴上的
/// 日期。只要这些地方去问系统「现在几点」，基准截图就会跟着日子走：
/// 昨天拍的图和今天跑出来的图，打卡日历必然差一格，于是每过一天测试就红一次，
/// 还得重拍一遍才能变绿——真正的样式改动反倒被这种「假失败」盖住了。
///
/// 挑这个时刻的理由：与下面 [sampleProgress] 里那局会话的日期
/// （`2026-09-05`）是同一天，样本数据前后对得上；上午 10 点半落在
/// 「早上好」那一档；9 月 5 日在月中，打卡日历上过去与未来的格子都有，
/// 两种状态都能被截图覆盖到。
///
/// 写成 `final` 而不是 `const`：`DateTime` 的普通构造不是常量构造，
/// 这里只是一个「造好一次、全程复用」的固定值。
final DateTime sampleNow = DateTime(2026, 9, 5, 10, 30);

///
/// 六个页面的样本清单，顺序与 README 里介绍页面的顺序一致。
List<SamplePage> samplePages() => <SamplePage>[
  SamplePage(
    slug: 'home',
    title: '首页',
    build: () => HomePage(
      store: MemoryWordStore(sampleWords()),
      settings: SettingsStore.inMemory(),
      audioPlayer: SilentAudioPlayer(),
      sessionStore: MemorySessionStore(),
      // 时间也是一个注入项：钉死它，首页那两张基准截图才不会每天自己变。
      clock: () => sampleNow,
    ),
  ),
  SamplePage(
    slug: 'listening',
    title: '随身听',
    build: () => ListeningPage(
      words: sampleWords(),
      audioPlayer: SilentAudioPlayer(),
      settings: SettingsStore.inMemory(),
    ),
  ),
  SamplePage(
    slug: 'listening_meaning',
    title: '听音辨义',
    headerLabelKey: 'listening-meaning-progress-label',
    headerRowHeight: ModuleScaffoldLayout.headerButtonSize,
    build: () => ListeningMeaningPage(
      words: sampleWords(),
      progress: sampleProgress(ReviewModule.listeningMeaning, sampleWords()),
      audioPlayer: SilentAudioPlayer(),
      accent: PronunciationAccent.american,
    ),
  ),
  SamplePage(
    slug: 'spelling',
    title: '拼写巩固',
    headerLabelKey: 'spelling-progress-label',
    headerRowHeight: ModuleScaffoldLayout.headerButtonSize,
    build: () => SpellingReinforcementPage(
      words: sampleWords(),
      title: '拼写巩固',
      progress: sampleProgress(
        ReviewModule.spellingReinforcement,
        sampleWords(),
      ),
      audioPlayer: SilentAudioPlayer(),
      accent: PronunciationAccent.american,
    ),
  ),
  SamplePage(
    slug: 'meaning_word_choice',
    title: '看义选词',
    headerLabelKey: 'meaning-word-choice-progress-label',
    headerRowHeight: ModuleScaffoldLayout.headerButtonSize,
    build: () => MeaningWordChoicePage(
      // 看义选词的候选词 =「匹配词 + 随机干扰词补到 4 个」。
      // 会话里刚好放 4 个词时，四个候选就是全部单词，随机不再影响结果，
      // 快照因此稳定；用 5 个词会每次随机挑 3 个干扰词，图就飘了。
      words: sampleChoiceWords(),
      title: '看义选词',
      progress: sampleProgress(
        ReviewModule.meaningWordChoice,
        sampleChoiceWords(),
      ),
      audioPlayer: SilentAudioPlayer(),
      accent: PronunciationAccent.american,
    ),
  ),
  SamplePage(
    slug: 'meaning_match',
    title: '词义连连',
    headerLabelKey: 'meaning-match-progress-label',
    headerRowHeight: ModuleScaffoldLayout.headerButtonSize,
    build: () => MeaningMatchPage(
      words: sampleWords(),
      title: '词义连连',
      progress: sampleProgress(ReviewModule.meaningMatch, sampleWords()),
      audioPlayer: SilentAudioPlayer(),
      accent: PronunciationAccent.american,
    ),
  ),
];

///
/// 六个页面共用的样本词表。
///
/// 刻意混进长短不一的拼写与释义：`incomprehensibility` 会让字母格换行、
/// 「不可理解性；极度晦涩难懂」会让释义大字换行——收敛间距与字号、以及把
/// 字号整体放大 1.3 倍时，这些地方最先出问题，所以样本里必须有。
/// 词义连连每组最多 5 对、不足时有多少显示多少；样本正好 5 个词铺满
/// 一组，方便观察完整棋盘的观感。
List<Word> sampleWords() => <Word>[
  _word(1, 101, 'tradition', 'n.', '传统；惯例'),
  _word(2, 102, 'beautiful', 'adj.', '美丽的；漂亮的'),
  _word(3, 103, 'garden', 'n.', '花园'),
  _word(4, 104, 'incomprehensibility', 'n.', '不可理解性；极度晦涩难懂'),
  _word(5, 105, 'yield', 'v.', '产生；屈服'),
];

///
/// 看义选词专用的四词词表：候选区正好装满，随机干扰词无从下手。
List<Word> sampleChoiceWords() => sampleWords().take(4).toList(growable: false);

///
/// 造一个带单条释义的单词；[meaningId] 是看义选词与词义连连出题要用的含义主键。
Word _word(int id, int meaningId, String spelling, String pos, String def) =>
    Word(
      id: id,
      spelling: spelling,
      meanings: <Meaning>[Meaning(id: meaningId, pos: pos, definition: def)],
    );

///
/// 造一局「刚开始」的会话进度出口。
///
/// 词义连连的数据列表是 `[单词id, 含义id]` 成对，看义选词是一串含义主键，
/// 其余模块是单词主键；这里按模块分别给出，与页面真实读取的口径一致。
SessionProgress sampleProgress(ReviewModule module, List<Word> words) {
  final items = switch (module) {
    ReviewModule.meaningMatch => <List<int>>[
      for (final word in words) <int>[word.id!, word.allMeanings.single.id!],
    ],
    ReviewModule.meaningWordChoice => <int>[
      for (final word in words) word.allMeanings.single.id!,
    ],
    _ => <int>[for (final word in words) word.id!],
  };
  return SessionProgress(
    store: MemorySessionStore(),
    session: Session(
      id: 1,
      module: module,
      kind: SessionKind.daily,
      status: SessionStatus.active,
      wordSetId: 1,
      items: items,
      cursor: 0,
      elapsed: 0,
      date: '2026-09-05',
      createdAt: DateTime.utc(2026, 9, 5),
    ),
    records: const <SessionRecord>[],
  );
}

///
/// 不发声的音频实现：Widget 测试不触碰原生通道。
///
/// 必须用 extends 而不是 implements——WordAudioPlayer 是带默认实现的抽象类。
class SilentAudioPlayer extends WordAudioPlayer {
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  @override
  Future<void> stop() async {}
}
