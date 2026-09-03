// 本文件是 development_page.dart 的一部分（part of），与主文件共享同一个
// library，因此可以直接使用页面内部的私有类型（下划线开头的类），不需要
// 单独 import 任何依赖。这里集中放置题目与消息的数据模型，让主文件只保留页面骨架与状态逻辑。
part of '../development_page.dart';

///
/// 开发模块演示时轮流出现的五种题型。
///
/// 题型顺序固定为「拼写选义 → 听音选词 → 听音选义 → 听音拼写 →
/// 看义选词」。每完成一题，词库下标前进一个；五种题型走完后从第一种
/// 重新开始，便于产品演示连续播放而不需要保存学习进度。
///
enum _DevelopmentQuestionKind {
  /// 先在键盘上拼写，再依次选择这个单词的全部含义。
  spellingMeaning('拼写选义'),

  /// 听发音后从四个英文单词中选出正确单词。
  listeningWord('听音选词'),

  /// 听发音后从四条中文释义中选出正确含义。
  listeningMeaning('听音选义'),

  /// 听发音后在键盘上拼出单词。
  listeningSpelling('听音拼写'),

  /// 看到中文含义后从四个英文单词中选出正确单词。
  meaningWord('看义选词');

  /// 创建题型并绑定原型中展示的中文名称。
  const _DevelopmentQuestionKind(this.label);

  /// 顶部或调试语义中使用的题型名称。
  final String label;

  /// 看义选词是文字题，其余四种题都需要播放单词发音。
  bool get usesAudio => this != _DevelopmentQuestionKind.meaningWord;
}

///
/// 当前题目处于哪一个小阶段。
///
/// 「拼写选义」会先经过 [spelling]，然后进入 [meaning]；另外四种题型
/// 只会使用 [choice] 或 [spelling]，完成后进入 [done]。
///
enum _DevelopmentQuestionStage {
  /// 正在使用键盘拼写。
  spelling,

  /// 正在依次选择中文释义。
  meaning,

  /// 正在四选一。
  choice,

  /// 题目已答对，等待进入下一题。
  done,
}

///
/// 一道演示题的可变状态。
///
/// 题目对象会被消息气泡和底部答题区共同读取。这样做的好处是：聊天记录
/// 可以保留在上方，而当前题目仍然能在原位置显示“圆点 → 字母 → 答案”的
/// 连续变化，不需要重新拼接整段聊天内容。
///
class _DevelopmentQuestion {
  /// 创建一道题目，并根据题型决定初始答题阶段。
  _DevelopmentQuestion({
    required this.kind,
    required this.word,
    required this.meanings,
    this.correctAnswer,
    this.promptText,
  }) : stage = switch (kind) {
         _DevelopmentQuestionKind.spellingMeaning ||
         _DevelopmentQuestionKind.listeningSpelling =>
           _DevelopmentQuestionStage.spelling,
         _DevelopmentQuestionKind.listeningWord ||
         _DevelopmentQuestionKind.listeningMeaning ||
         _DevelopmentQuestionKind.meaningWord =>
           _DevelopmentQuestionStage.choice,
       };

  /// 本题题型。
  final _DevelopmentQuestionKind kind;

  /// 本题对应的单词。
  final Word word;

  /// 本题使用的全部释义；没有真实释义时由页面放入一条占位释义。
  final List<Meaning> meanings;

  /// 当前四选一阶段的正确答案。
  String? correctAnswer;

  /// 看义选词阶段显示在系统气泡里的中文含义。
  final String? promptText;

  /// 题目当前所处阶段。
  _DevelopmentQuestionStage stage;

  /// 键盘已经输入的字母。
  final List<String> typedLetters = <String>[];

  /// 已经点错的候选文字；这些候选会像原型一样变红并禁用。
  final Set<String> wrongAnswers = <String>{};

  /// 当前四选一候选项，候选顺序在出题时固定，答题时不会跳动。
  List<String> options = <String>[];

  /// 拼写选义题当前正在选择第几条释义。
  int meaningIndex = 0;

  /// 拼写选义题已经回填到气泡里的释义数量。
  int solvedMeaningCount = 0;

  /// 是否已经把拼写选义题的完整单词展示出来。
  bool spellingSolved = false;

  /// 是否正在显示原型里的“正在输入”三圆点。
  bool isTyping = true;

  /// 是否正在播放这个题目的发音。
  bool isPlaying = false;

  /// 错误反馈时给题目气泡加一小段红色光晕。
  bool showWrongFlash = false;

  /// 题目切换子阶段时短暂锁住底部区域，避免连续误点。
  bool isTransitioning = false;

  /// 拼写选义题是否已经完成全部释义。
  bool get isDone => stage == _DevelopmentQuestionStage.done;

  /// 当前题目是否应显示六个装饰圆点（听音类“纯播音频”题型，没有键盘输入，
  /// 圆点就是波形占位）。注意：听音拼写（listeningSpelling）虽然也会播放音频，
  /// 但它走键盘拼写，槽位应由字母回填而不是一直显示圆点，所以不能算进来。
  bool get showDots =>
      kind == _DevelopmentQuestionKind.listeningWord ||
      kind == _DevelopmentQuestionKind.listeningMeaning;
}

///
/// 聊天列表中的一条消息。
///
/// 系统题目消息保存一个 [_DevelopmentQuestion] 引用，用户消息则只保存
/// 最终显示的文字。聊天列表只追加消息，从不把已经展示的消息写回数据库。
///
class _DevelopmentMessage {
  /// 创建系统侧的题目气泡。
  const _DevelopmentMessage.question(this.question)
    : isUser = false,
      text = null,
      isDanger = false,
      isChecked = false;

  /// 创建用户侧的回答气泡。
  const _DevelopmentMessage.user(
    this.text, {
    this.isDanger = false,
    this.isChecked = false,
  }) : question = null,
       isUser = true;

  /// 系统题目对象；用户回答消息为 null。
  final _DevelopmentQuestion? question;

  /// 用户气泡显示的回答文字。
  final String? text;

  /// true 表示消息在右侧，是用户的回答。
  final bool isUser;

  /// true 表示这是答错后留下的红色消息。
  final bool isDanger;

  /// true 表示回答气泡右侧显示白底绿色勾选。
  final bool isChecked;
}
