// dart:io 提供目录遍历与文件读取能力。
import 'dart:io';

// flutter_test 提供 test、expect 等测试 API。
import 'package:flutter_test/flutter_test.dart';

///
/// 设计令牌「上锁」测试：防止刚整理好的样式表被新代码重新写乱。
///
/// 生活化解释：前面几轮把全站的颜色、字号、间距、圆角、造型尺寸、图标尺寸、
/// 透明度、动画时长、投影都收进了 `lib/common/design/` 下面的九张总表，
/// 各个页面和跨页面组件又各有一张自己的专属尺寸表（继承总表的台阶），
/// 好处是「改一处、全站跟着变」。
/// 但这种整理有个通病——过一段时间新写的界面又随手写上 `fontSize: 15`，
/// 表就慢慢失效了。这个测试就是那把锁：谁再往界面代码里写裸数字，
/// 跑测试时立刻报出文件和行号，并告诉他应该改用哪张表。
///
/// 现在锁住的是全部十五类：字号、字重、色值、圆角、间距、描边、时长，
/// 加上这一轮补上的宽高与行高、透明度、字距、悬浮高度、投影几何、投影偏移、
/// `Size(...)` 与贴边定位。造型尺寸（宽高）以前锁不了，是因为首页那一片界面
/// 还没有自己的尺寸表；现在六个模块加五个跨页面组件都有表了，这个借口没了。
///
/// 除此之外还多一条**「出处」规则**（第二个 `test`）：颜色不许绕过 [AppTokens]
/// 去读 Material 自己的 `colorScheme`。前十五条管的是「别写裸数字」，这一条管的是
/// 「别走另一条路」——同一个蓝色，从 `colorScheme.primary` 拿和从 `AppTokens.primary`
/// 拿，深色模式下会得到两个不同的蓝，而页面作者根本看不出自己拿错了。
///
/// 四条设计原则：
///
///   1. **只看代码，不看注释。** 注释里经常要引用原型的原始数值
///      （例如「原型 `.card-label { font-size: 0.8125rem }`」），
///      那是说明文字，不该被当成违规。所以扫描前先把每行 `//` 之后的内容删掉。
///   2. **只管界面代码，不管总表自己。** `lib/common/design/` 是台阶的定义处，
///      那里天生要写字面量，整个目录跳过。
///   3. **例外要写清理由。** 少数数字长得像样式，其实不是（圆弧半径、
///      防抖时长）。它们记在 [_allowlist] 里，连原因一起写下来，
///      而不是把整条规则关掉。
///   4. **「0」通常是开关，不是尺寸。** `left: 0 / right: 0` 是「左右两边都贴满」，
///      `Size(0, 高度)` 是「不设最小宽度」。这两种 0 都不是可以调的数值，
///      而是一句「不要」，所以规则里直接放行，不必逐处登记例外。
///      唯一的反例是内外边距——`EdgeInsets` 里连 0 也要写成 `AppSpace.p0`，
///      因为「这里刻意不留缝」是一个需要被看见的设计决定。
///   5. **看不出来的差别不算样式。** 不到一个像素的字距、0.5 的偏移这类参数，
///      屏幕上分辨不出来，留着只会让人以为「这里有讲究」。它们不进令牌表，
///      也不该出现在页面里；全站唯一一处真的调字距是拼写巩固的播音状态标签
///      （`SpellingLayout.playbackLabelLetterSpacing` = 1.2），那一档一眼就看得出。
///
void main() {
  test('界面代码不再出现样式裸数字（颜色/字号/字重/间距/圆角/描边/时长/宽高/透明度/投影）', () {
    // 收集所有违规，最后一次性报出来；否则改一处跑一次，太慢。
    final violations = <String>[];

    for (final file in _sourceFiles()) {
      final rel = file.path.replaceAll(r'\', '/');
      // 原始文本按行切开，报错时要用原行内容（含注释）方便定位。
      final lines = file.readAsStringSync().split('\n');
      // 去掉注释后的「纯代码」文本，行号与 lines 一一对应。
      final code = lines.map((line) => line.split('//').first).join('\n');

      for (final rule in _rules) {
        for (final match in rule.pattern.allMatches(code)) {
          _record(violations, rel, lines, code, match.start, rule.hint);
        }
      }
      // 内边距要分两步找：先框出 EdgeInsets 的括号，再看括号里有没有裸数字。
      for (final match in _edgeInsets.allMatches(code)) {
        for (final _ in _bareNumber.allMatches(match.group(2)!)) {
          _record(violations, rel, lines, code, match.start, _edgeHint);
        }
      }
      // `Size(宽, 高)` 同样分两步：0 表示「不设这一边的下限」，予以放行，
      // 其余任何数字都得来自尺寸表。
      for (final match in _sizeCall.allMatches(code)) {
        for (final _ in _bareNonZero.allMatches(match.group(1)!)) {
          _record(violations, rel, lines, code, match.start, _sizeHint);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '发现 ${violations.length} 处样式裸数字：\n${violations.join('\n')}',
    );
  });

  test('界面代码只从 AppTokens 取色，不再走 Material 的 colorScheme', () {
    // 同样先收集再一次性报出。
    final violations = <String>[];

    for (final file in _sourceFiles()) {
      final rel = file.path.replaceAll(r'\', '/');
      // 唯一放行的文件：主题桥。它的职责就是把 AppTokens 接进 Material，
      // 不提 colorScheme 这套主题根本装不上去。
      if (rel == _themeBridge) continue;

      final lines = file.readAsStringSync().split('\n');
      final code = lines.map((line) => line.split('//').first).join('\n');
      for (final match in _colorScheme.allMatches(code)) {
        _record(violations, rel, lines, code, match.start, _colorSchemeHint);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '发现 ${violations.length} 处绕开 AppTokens 的取色：\n${violations.join('\n')}',
    );
  });
}

///
/// 唯一允许出现 `colorScheme` 的文件：全站主题的装配处。
const String _themeBridge = 'lib/common/theme.dart';

///
/// 读取 Material 配色方案的写法。
///
/// 只认单词边界内的 `colorScheme`，所以 `ColorScheme.fromSeed(...)` 这种
/// 「构造一套配色」的写法不在此列——那件事只在主题桥里做，而主题桥已经放行。
final RegExp _colorScheme = RegExp(r'\bcolorScheme\b');

///
/// 绕开 AppTokens 取色的整改建议。
const String _colorSchemeHint =
    '颜色请改用 AppTokens（`AppTokens.of(context)` 取跟随明暗的那一档，'
    '或直接用 AppTokens.primary 这类固定色）；'
    'Material 的 colorScheme 只是主题桥接的中转站，'
    '它在深色模式下给出的值和 AppTokens 并不完全一致';

///
/// 数字字面量的通用写法：整数或小数。
const String _number = r'[0-9]+(?:\.[0-9]+)?';

///
/// 一条检查规则：一个正则 + 一句「该改用什么」的提示。
class _Rule {
  ///
  /// 创建一条规则。
  const _Rule(this.pattern, this.hint);

  ///
  /// 用来在纯代码文本里找违规写法的正则。
  final RegExp pattern;

  ///
  /// 报错时附带的整改建议。
  final String hint;
}

///
/// 全部检查规则。
///
/// 每条都只认「后面紧跟数字」的写法，所以已经改成 `AppFont.fs5`、
/// `AppSpace.p3` 这类具名写法的地方不会被误伤。
///
/// 这一轮新加的那几条末尾都多了一个 `\s*[,)]`，意思是「数字后面必须立刻收尾」。
/// 生活化解释：`opacity: 1 - _controller.value` 这种算式，开头也是
/// `opacity:` 加一个数字，但那个数字是算式的一部分，不是可以搬进尺寸表的常量。
/// 要求「数字后面紧跟逗号或右括号」就能把算式放过、只抓真正写死的值。
final List<_Rule> _rules = <_Rule>[
  _Rule(RegExp('fontSize:\\s*$_number'), '字号请改用 AppFont 或本页 Layout 表里的字号常量'),
  _Rule(RegExp(r'FontWeight\.(?:w[0-9]00|bold|normal)\b'), '字重请改用 AppWeight'),
  _Rule(RegExp(r'Color\(0x'), '颜色请改用 AppTokens（深浅色各一套，别写死色值）'),
  _Rule(
    RegExp('BorderRadius\\.circular\\(\\s*$_number'),
    '圆角请改用 AppRadius 或本页 Layout 表里的圆角常量',
  ),
  _Rule(
    RegExp('(?<!Border)Radius\\.circular\\(\\s*$_number'),
    '圆角请改用 AppRadius；如果这是圆弧半径而不是圆角，请加进 _allowlist 并写明原因',
  ),
  _Rule(RegExp('\\b(?:run)?[Ss]pacing:\\s*$_number'), '间距请改用 AppSpace'),
  _Rule(RegExp('strokeWidth:\\s*$_number'), '线宽请改用 AppStroke'),
  _Rule(RegExp('BorderSide\\([^)]*width:\\s*$_number'), '描边宽度请改用 AppStroke'),
  _Rule(
    RegExp('milliseconds:\\s*$_number'),
    '动画时长请改用 AppDuration；如果这是业务计时（防抖、超时、停留），'
    '请加进 _allowlist 并写明原因',
  ),
  // ↓↓↓ 以下八条是这一轮新上锁的类别 ↓↓↓
  _Rule(
    RegExp(
      '(?<![\\w.])(?:width|height|minWidth|maxWidth|minHeight|maxHeight):'
      '\\s*-?$_number\\s*[,)]',
    ),
    '宽高请改用本页（或本组件）Layout 表里的尺寸常量；'
    '只有两个以上地方必须保持一致的方寸才收进 AppSize。'
    '文字样式里的 height 是「行高倍数」，同样请起个名字放进 Layout 表',
  ),
  _Rule(
    RegExp('alpha:\\s*-?$_number\\s*[,)]'),
    '透明度请改用 AppAlpha（`withValues(alpha: AppAlpha.a30)`）',
  ),
  _Rule(
    RegExp('(?<![\\w.])opacity:\\s*-?$_number\\s*[,)]'),
    '透明度请改用 AppAlpha；如果它是动画算出来的值，请让算式而不是常量出现在这里',
  ),
  _Rule(
    RegExp('letterSpacing:\\s*-?$_number\\s*[,)]'),
    '字距请写进本页 Layout 表再引用。全站默认不加字距，'
    '也不要再写 `letterSpacing: 0`——那等于把「什么都不做」写成一行代码',
  ),
  _Rule(
    RegExp('elevation:\\s*-?$_number\\s*[,)]'),
    '悬浮高度请改用本页 Layout 表里的常量（它决定影子有多远，属于这一颗按钮的造型）',
  ),
  _Rule(
    RegExp('(?:blurRadius|spreadRadius):\\s*-?$_number\\s*[,)]'),
    '投影的晕开与扩散请改用 AppShadow 或本页 Layout 表；'
    '连 0 也写成 AppShadow.none，表示「这道影子刻意不晕开」',
  ),
  _Rule(
    RegExp(
      'offset:\\s*(?:const\\s*)?Offset\\(\\s*-?$_number\\s*,\\s*-?$_number\\s*\\)',
    ),
    '投影往下沉多少请改用 AppShadow.cardOffsetY 或本页 Layout 表；'
    '这条只管 `offset:`，画布坐标和动画位移用的 Offset 不受影响',
  ),
  _Rule(
    RegExp(
      '(?<![\\w.])(?:top|bottom|left|right):\\s*(?!0\\s*[,)])-?$_number\\s*[,)]',
    ),
    '定位偏移请改用 AppSpace 或本页 Layout 表；'
    '唯独 0 放行——`left: 0, right: 0` 的意思是「这一边贴满」，不是一个可调的数值',
  ),
];

///
/// EdgeInsets 的四种写法；第二个捕获组是括号里的全部参数。
///
/// 用 dotAll 是因为 dart format 会把长参数拆成多行：
/// `EdgeInsets.symmetric(` 单独一行、`horizontal: 16,` 又是一行，
/// 逐行匹配两边都对不上，裸数字就漏过去了。
final RegExp _edgeInsets = RegExp(
  r'EdgeInsets\.(all|symmetric|only|fromLTRB)\(([^()]*)\)',
  dotAll: true,
);

///
/// 括号里的裸数字：前后都不能紧跟字母、下划线或点，
/// 这样 `AppSpace.p3` 里的 3 不会被当成裸数字。
final RegExp _bareNumber = RegExp('(?<![\\w.])$_number(?![\\w.])');

///
/// EdgeInsets 违规的整改建议。
const String _edgeHint =
    '内外边距请改用 AppSpace（连 0 也写成 AppSpace.p0，'
    '表示「这里刻意不留缝」）';

///
/// `Size(宽, 高)` 的调用；捕获组是括号里的两个参数。
///
/// 和 EdgeInsets 一样用 dotAll：dart format 会把它拆成三行，
/// 逐行匹配对不上。`Size.fromHeight(...)`、`Size.square(...)` 这些带点的写法
/// 不在此列——`\bSize\(` 要求括号紧跟在 Size 后面。
final RegExp _sizeCall = RegExp(r'\bSize\(([^()]*)\)', dotAll: true);

///
/// 括号里的「非零」裸数字。
///
/// 和 [_bareNumber] 的唯一区别是放过单独的 0：按钮的 `minimumSize: Size(0, 高度)`
/// 里那个 0 是在说「宽度不设下限，让外层决定」，它不是一个尺寸。
/// 写成 `0.5` 这类小数仍然会被抓住——只有孤零零的 0 才是那句「不要」。
final RegExp _bareNonZero = RegExp(
  '(?<![\\w.])(?!0(?![0-9.]))$_number(?![\\w.])',
);

///
/// `Size(...)` 违规的整改建议。
const String _sizeHint =
    '宽高请改用本页（或本组件）Layout 表里的尺寸常量；'
    '`Size(0, 高度)` 里的 0 是「不设最小宽度」的开关，刻意放行';

///
/// 允许保留裸数字的例外：外层键是文件相对路径，
/// 内层键是该行代码里必须出现的片段，值是允许它存在的原因。
///
/// 用「代码片段」而不是行号来对号，是因为行号会随着上下文增删而漂移，
/// 片段则一直跟着那句代码走。
const Map<String, Map<String, String>> _allowlist =
    <String, Map<String, String>>{
      'lib/widgets/audio_speaker_button.dart': <String, String>{
        'Radius.circular(5)':
            '这是播音图标里近处那道声波「圆弧的半径」，不是圆角。'
            '数值抄自原型 SVG 的 `M15 8a5 5 0 0 1 0 8`，改一个数弧线就走形。',
        'Radius.circular(9)': '同上，远处那道声波的圆弧半径，抄自 `M17.7 5a9 9 0 0 1 0 14`。',
      },
      'lib/pages/home/home.dart': <String, String>{
        'milliseconds: 120':
            '搜索框防抖：决定「停手多久才去查数据库」，属于业务计时而非动画时长。'
            '混进 AppDuration 的后果是哪天想让动画快一点，顺手把它也改了。',
      },
    };

///
/// 列出参与检查的源码文件。
///
/// 跳过 `lib/common/design/`：那里是台阶的定义处，天然要写字面量。
Iterable<File> _sourceFiles() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where(
        (file) =>
            !file.path.replaceAll(r'\', '/').startsWith('lib/common/design/'),
      );
}

///
/// 把一处命中登记为违规；命中在例外清单里则原样放过。
///
/// [offset] 是命中在「纯代码」文本里的位置，用它反算行号，
/// 这样报错信息里的 `文件:行号` 在编辑器里能直接点开。
void _record(
  List<String> violations,
  String rel,
  List<String> lines,
  String code,
  int offset,
  String hint,
) {
  // 数一下命中位置前面有几个换行，就知道是第几行（行号从 1 开始）。
  final lineNo = code.substring(0, offset).split('\n').length;
  // 取原始行（含注释），并把连续空白压成一个空格，方便和例外片段比对。
  final line = lines[lineNo - 1].replaceAll(RegExp(r'\s+'), ' ').trim();

  // 这个文件登记过的例外里，只要有一条片段出现在本行，就说明是已知情况。
  for (final snippet in (_allowlist[rel] ?? const <String, String>{}).keys) {
    if (line.contains(snippet)) return;
  }

  violations.add('  $rel:$lineNo  $line\n      → $hint');
}
