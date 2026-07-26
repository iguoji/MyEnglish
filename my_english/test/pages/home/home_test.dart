// dart:async 提供 Completer，用于在测试中控制音频何时播放完成。
import 'dart:async';

// material.dart 提供测试需要识别的页面、边框和输入框类型。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动，作用类似 PHPUnit 加小程序自动化工具。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的首页。
import 'package:my_english/pages/home/home.dart';
// 引入全局 Meaning 与 Word 模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入单词行，以检查展开后的动态高度。
import 'package:my_english/pages/home/widgets/word_list_tile.dart';
// 引入音频接口，测试使用不会访问真实网络的受控实现。
import 'package:my_english/services/word_audio.dart';
// 引入口音与设置 Store，验证播放参数和设置面板。
import 'package:my_english/store/settings.dart';
// 引入 Store 接口，测试会提供不依赖 Android 的内存实现。
import 'package:my_english/store/word.dart';

/// 注册首页 Widget 测试。
void main() {
  // 验证顶部完整时间与唯一秒级监听器。
  testWidgets('home page uses a plain header and one clock listener', (
    tester,
  ) async {
    // 使用内存 Store 渲染首页，避免测试依赖 Android MethodChannel。
    await _pumpHome(tester);

    // 顶部不能出现 Card。
    expect(find.byType(Card), findsNothing);
    // 日期时间必须符合“年月日 时分秒”。
    expect(
      find.byWidgetPredicate(
        // 正则只校验格式，不绑定测试运行时的具体秒数。
        (widget) =>
            widget is Text &&
            RegExp(
              r'^\d{4}年\d{2}月\d{2}日 \d{2}:\d{2}:\d{2}$',
            ).hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
    // 整页只有 HomeHeader 中一个 DateTime ValueListenableBuilder。
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ValueListenableBuilder<DateTime>,
      ),
      findsOneWidget,
    );
    // 单词行内部没有秒级监听器。
    expect(
      find.descendant(
        of: find.byType(WordListTile),
        matching: find.byWidgetPredicate(
          (widget) => widget is ValueListenableBuilder<DateTime>,
        ),
      ),
      findsNothing,
    );

    // 卸载页面并释放 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证列表贴屏、占满底部且外层只有顶部边框。
  testWidgets('word list is edge-to-edge with only a top border', (
    tester,
  ) async {
    // 渲染带两条数据的首页。
    await _pumpHome(tester);

    // 通过 HomePage 设置的 key 找到列表外层。
    final listFinder = find.byKey(const Key('word-list'));
    // 外层只能出现一次。
    expect(listFinder, findsOneWidget);
    // 读取 DecoratedBox 配置。
    final listBox = tester.widget<DecoratedBox>(listFinder);
    // 生产代码明确使用 BoxDecoration。
    final decoration = listBox.decoration as BoxDecoration;
    // 生产代码明确使用 Border。
    final border = decoration.border! as Border;
    // 顶部是实线。
    expect(border.top.style, BorderStyle.solid);
    // 列表顶部与各行统一使用 Tabler 表格边框色 #E6E7E9。
    expect(border.top.color, const Color(0xFFE6E7E9));
    // 左右和底部不属于列表外框。
    expect(border.left.style, BorderStyle.none);
    expect(border.right.style, BorderStyle.none);
    expect(border.bottom.style, BorderStyle.none);
    // 左边缘紧贴逻辑屏幕 0 坐标。
    expect(tester.getTopLeft(listFinder).dx, 0);
    // 物理像素换算成 Flutter 使用的逻辑宽度。
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    // 列表宽度覆盖整个逻辑屏幕。
    expect(tester.getSize(listFinder).width, logicalWidth);
    // 物理高度同样换算成逻辑高度。
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // Expanded 让列表底部到达屏幕底部。
    expect(tester.getBottomRight(listFinder).dy, logicalHeight);

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证滚动条始终显示、支持拖动，并与 ListView 使用同一控制器。
  testWidgets('word list has an interactive draggable scrollbar', (
    tester,
  ) async {
    // 打开首页。
    await _pumpHome(tester);

    // 页面只需要一个垂直 Scrollbar。
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    // 真机首次打开时滑块已经可见。
    expect(scrollbar.thumbVisibility, isTrue);
    // 用户可以直接按住滑块拖动。
    expect(scrollbar.interactive, isTrue);
    // 读取业务列表。
    final listView = tester.widget<ListView>(find.byType(ListView));
    // 两者必须共享同一个控制器，拖动才会真正改变列表位置。
    expect(scrollbar.controller, same(listView.controller));

    // 清理页面 Timer 和 ScrollController。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证搜索防抖后仍忽略大小写及首尾空格。
  testWidgets('search ignores case and surrounding whitespace', (tester) async {
    // 打开首页。
    await _pumpHome(tester);
    // 输入带空格的大写关键词。
    await tester.enterText(find.byType(TextField), '  ABILITY  ');
    // 推进超过 120ms，使防抖 Timer 真正更新 query。
    await tester.pump(const Duration(milliseconds: 121));

    // ability 被保留。
    expect(find.text('ability'), findsOneWidget);
    // abandon 被过滤。
    expect(find.text('abandon'), findsNothing);

    // 输入不存在的单词。
    await tester.enterText(find.byType(TextField), 'not-a-real-word');
    // 再推进一次防抖时间。
    await tester.pump(const Duration(milliseconds: 121));
    // 页面显示无匹配状态。
    expect(find.text('未找到匹配的单词'), findsOneWidget);

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证搜索框固定 40 高、图标 24，并保持文字垂直居中。
  testWidgets('search field is 40 pixels high with centered content', (
    tester,
  ) async {
    // 渲染首页。
    await _pumpHome(tester);
    // 读取 TextField 实例配置。
    final textField = tester.widget<TextField>(find.byType(TextField));
    // 实际布局高度必须为 40 逻辑像素。
    expect(tester.getSize(find.byType(TextField)).height, 40);
    // 输入文字按垂直中心对齐。
    expect(textField.textAlignVertical, TextAlignVertical.center);
    // 输入文字和 placeholder 使用一致行高。
    expect(textField.style?.height, 1.2);
    expect(textField.decoration!.hintStyle?.height, 1.2);
    // 左侧搜索图标保持清晰的 24 像素。
    final searchIcon = textField.decoration!.prefixIcon! as Icon;
    expect(searchIcon.size, 24);

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证列表惰性创建可变高度行，并能展开 Meaning。
  testWidgets('list lazily builds rows and expands meanings', (tester) async {
    // 打开首页并等待内存数据加载。
    await _pumpHome(tester);
    // 首页只有一个业务 ListView。
    final listView = tester.widget<ListView>(find.byType(ListView));
    // 可展开内容高度不同，所以不能再使用固定 itemExtent。
    expect(listView.itemExtent, isNull);
    // 收起时第一行使用当前要求的 40 像素标题高度。
    expect(
      tester.getSize(find.byType(WordListTile).first).height,
      WordListTile.headerHeight,
    );

    // 点击 ability 行右侧展开箭头；单词文字现在专门负责播放。
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
    // 等待 160ms 展开动画结束。
    await tester.pumpAndSettle();
    // 两个 Meaning 各自显示为一行。
    expect(find.text('能力；才能'), findsOneWidget);
    expect(find.text('能干的'), findsOneWidget);
    // 展开后整项高度必须大于标题行。
    expect(
      tester.getSize(find.byType(WordListTile).first).height,
      greaterThan(WordListTile.headerHeight),
    );

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证相同 spelling 的两行拥有彼此独立的展开状态。
  testWidgets('duplicate spelling rows expand independently', (tester) async {
    // 两个 Word 故意使用相同 spelling，但主键和 Meaning 不同。
    final words = <Word>[
      const Word(
        id: 11,
        spelling: 'same',
        meanings: <Meaning>[
          Meaning(index: 1, pos: 'n.', definitions: <String>['第一条']),
        ],
      ),
      const Word(
        id: 12,
        spelling: 'same',
        meanings: <Meaning>[
          Meaning(index: 1, pos: 'v.', definitions: <String>['第二条']),
        ],
      ),
    ];
    // 注入包含重复 spelling 的测试 Store。
    await tester.pumpWidget(
      MaterialApp(home: HomePage(store: _MemoryWordStore(words))),
    );
    // 等待异步 getAll 完成。
    await tester.pump();

    // 列表必须显示两行相同文本。
    expect(find.text('same'), findsNWidgets(2));
    // 只点击第一行的展开箭头。
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
    // 等待展开动画完成。
    await tester.pumpAndSettle();
    // 第一行 Meaning 已显示。
    expect(find.text('第一条'), findsOneWidget);
    // 第二行没有被相同 spelling 连带展开。
    expect(find.text('第二条'), findsNothing);

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证字母、难度、日期都有双向排序，且 null 难度/日期始终在末尾。
  testWidgets('sort bar toggles all fields and keeps null values last', (
    tester,
  ) async {
    // 第一个单词更新时间最新，但难度最低。
    final words = <Word>[
      Word(
        id: 21,
        spelling: 'zebra',
        difficulty: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 7, 1),
      ),
      // 第二个单词没有更新时间，日期应回退到 createdAt。
      Word(
        id: 22,
        spelling: 'apple',
        difficulty: 3,
        createdAt: DateTime(2026, 6, 1),
      ),
      // 第三个单词故意没有难度和日期。
      const Word(id: 23, spelling: 'middle'),
    ];
    // 使用稳定测试数据打开首页。
    await _pumpHome(tester, words: words);

    // 默认顺序严格保持 Store 返回顺序。
    _expectTextsInVerticalOrder(tester, <String>['zebra', 'apple', 'middle']);
    // 第一次点字母是升序。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['apple', 'middle', 'zebra']);
    // 再点字母切到降序。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['zebra', 'middle', 'apple']);

    // 第一次点难度默认高到低，null 在末尾。
    await tester.tap(find.byKey(const Key('word-sort-difficulty')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['apple', 'zebra', 'middle']);
    // 再点难度低到高，null 仍在末尾。
    await tester.tap(find.byKey(const Key('word-sort-difficulty')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['zebra', 'apple', 'middle']);

    // 第一次点日期默认最近到最早；zebra 使用 updatedAt 排在 apple 前。
    await tester.tap(find.byKey(const Key('word-sort-date')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['zebra', 'apple', 'middle']);
    // 再点日期从早到晚，null 仍然固定在末尾。
    await tester.tap(find.byKey(const Key('word-sort-date')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['apple', 'zebra', 'middle']);

    // 清理页面资源。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证播放状态立即显示喇叭，同一单词播放中重复 tap 不会重新请求。
  testWidgets('word tap plays once and shows speaker until completion', (
    tester,
  ) async {
    // 使用可手动结束的假播放器。
    final audioPlayer = _ControlledAudioPlayer();
    // 明确设置英式，确认首页读取当前持久化设置而非写死美式。
    final settings = SettingsStore.inMemory(
      accent: PronunciationAccent.british,
    );
    // 注入设置与播放器。
    await _pumpHome(tester, settings: settings, audioPlayer: audioPlayer);

    // tap 单词文字只播放，不展开 Meaning。
    await tester.tap(find.text('ability'));
    await tester.pump();
    // 只发出一次播放请求。
    expect(audioPlayer.playCount, 1);
    // 参数保留真实 spelling。
    expect(audioPlayer.lastSpelling, 'ability');
    // 参数使用设置中的英式口音。
    expect(audioPlayer.lastAccent, PronunciationAccent.british);
    // 播放期间左侧出现动画喇叭。
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    // 播放动作不会展开释义。
    expect(find.text('能力；才能'), findsNothing);

    // 播放尚未结束时重复 tap 同一文字。
    await tester.tap(find.text('ability'));
    await tester.pump();
    // 请求次数保持 1。
    expect(audioPlayer.playCount, 1);

    // 手动模拟原生播放自然结束。
    audioPlayer.complete();
    await tester.pump();
    // Future 完成后喇叭消失。
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

    // 释放 SettingsStore 和页面资源。
    settings.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证右上角设置图标打开底部面板，选择结果写回同一 Store。
  testWidgets('settings button opens sheet and updates both preferences', (
    tester,
  ) async {
    // 首页持有这份可观察内存设置。
    final settings = SettingsStore.inMemory();
    // 注入首页。
    await _pumpHome(tester, settings: settings);

    // 点击右上角齿轮。
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    // BottomSheet 显示两项设置。
    expect(find.text('发音'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    // 首次默认值是美式和 Light。
    expect(settings.accent, PronunciationAccent.american);
    expect(settings.theme, AppThemePreference.light);

    // 切换到英式。
    await tester.tap(find.text('英式'));
    await tester.pump();
    expect(settings.accent, PronunciationAccent.british);
    // 切换到 Dark。
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(settings.theme, AppThemePreference.dark);

    // 关闭面板并清理。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });

  // 验证加载失败不仅显示标题，也输出真实异常内容。
  testWidgets('load error details are visible and selectable', (tester) async {
    // 使用固定抛错 Store 模拟 JSON 解析失败。
    await tester.pumpWidget(
      const MaterialApp(home: HomePage(store: _ThrowingWordStore())),
    );
    // 等待异步 getAll 进入 catch 并刷新页面。
    await tester.pump();

    // 保留用户可理解的错误标题。
    expect(find.text('单词数据加载失败'), findsOneWidget);
    // 详情使用可长按选择的 SelectableText。
    final detailsFinder = find.byKey(const Key('word-load-error-details'));
    // 错误详情控件只出现一次。
    expect(detailsFinder, findsOneWidget);
    // 读取 SelectableText 本身，确认具体错误不只输出在控制台。
    final details = tester.widget<SelectableText>(detailsFinder);
    // data 保存构造 SelectableText 时传入的原始错误文本。
    expect(details.data, contains('broken-json-at-word-3'));

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证窄屏大字体不会让左右 flex 布局溢出。
  testWidgets('home page does not overflow on a narrow large-text screen', (
    tester,
  ) async {
    // 模拟 320×480 小屏幕。
    tester.view.physicalSize = const Size(320, 480);
    // 物理与逻辑像素一比一。
    tester.view.devicePixelRatio = 1;
    // 字体放大两倍。
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    // 测试结束后恢复尺寸。
    addTearDown(tester.view.resetPhysicalSize);
    // 恢复像素比。
    addTearDown(tester.view.resetDevicePixelRatio);
    // 恢复文字缩放。
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 在该环境打开首页。
    await _pumpHome(tester);
    // 不应出现 RenderFlex overflow。
    expect(tester.takeException(), isNull);
    // 搜索框仍然可见。
    expect(find.text('搜索单词'), findsOneWidget);
    // 高性能列表仍然存在。
    expect(find.byType(ListView), findsOneWidget);

    // 清理页面 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证后台停止、前台恢复 Timer 不会产生异常。
  testWidgets('lifecycle changes stop and restart the clock safely', (
    tester,
  ) async {
    // 打开首页。
    await _pumpHome(tester);
    // 模拟小程序 App Hide。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // 虚拟推进两秒。
    await tester.pump(const Duration(seconds: 2));
    // 后台阶段无异常。
    expect(tester.takeException(), isNull);
    // 模拟小程序 App Show。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // 处理恢复更新。
    await tester.pump();
    // 恢复阶段无异常。
    expect(tester.takeException(), isNull);

    // 清理恢复后的 Timer。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// 用内存 Store 渲染首页，并推进一帧等待异步 Future 完成。
Future<void> _pumpHome(
  WidgetTester tester, {
  List<Word>? words,
  SettingsStore? settings,
  WordAudioPlayer? audioPlayer,
}) async {
  // MaterialApp 提供 TextField 等组件所需的 Material 环境。
  await tester.pumpWidget(
    MaterialApp(
      // HomePage 通过构造器注入测试 Store。
      home: HomePage(
        store: _MemoryWordStore(words ?? _sampleWords()),
        settings: settings,
        audioPlayer: audioPlayer,
      ),
    ),
  );
  // 内存 Future 在微任务队列完成，额外 pump 让 setState 生效。
  await tester.pump();
}

/// 断言多个文字从上到下按给定顺序显示。
void _expectTextsInVerticalOrder(WidgetTester tester, List<String> texts) {
  // 保存上一项 y 坐标，第一项之前使用负无穷。
  var previousTop = double.negativeInfinity;
  // 逐项读取文字左上角。
  for (final text in texts) {
    // 当前文字必须只出现一次。
    final finder = find.text(text);
    // 先给出清晰数量断言。
    expect(finder, findsOneWidget);
    // 读取当前纵坐标。
    final currentTop = tester.getTopLeft(finder).dy;
    // 当前项必须严格位于上一项下方。
    expect(currentTop, greaterThan(previousTop));
    // 保存给下一轮比较。
    previousTop = currentTop;
  }
}

/// 构造两条稳定测试数据，作用类似 PHPUnit fixture。
List<Word> _sampleWords() {
  // 返回 ability 和 abandon，供搜索用例区分匹配结果。
  return <Word>[
    // 第一条带难度。
    Word(
      id: 1,
      spelling: 'ability',
      difficulty: 3,
      createdAt: DateTime(2025, 7, 26),
      meanings: const <Meaning>[
        // index 较大的名词 Meaning 显示在前。
        Meaning(index: 2, pos: 'n.', definitions: <String>['能力', '才能']),
        // 第二个 Meaning 独占下一行。
        Meaning(index: 1, pos: 'adj.', definitions: <String>['能干的']),
      ],
    ),
    // 第二条没有难度。
    Word(id: 2, spelling: 'abandon', createdAt: DateTime(2026, 7, 26)),
  ];
}

/// 不依赖 Android SQLite 的测试 Store，类似小程序测试中的假 Store。
class _MemoryWordStore implements WordStore {
  /// 接收固定 fixture。
  const _MemoryWordStore(this.words);

  /// 内存中的单词集合。
  final List<Word> words;

  /// 异步返回全部测试数据。
  @override
  Future<List<Word>> getAll() async => words;

  /// 当前首页测试不使用创建；实现接口以保持 Fake 完整。
  @override
  Future<int> create(Word word) async => word.id ?? 1;

  /// 当前首页测试不需要实际更新内存集合。
  @override
  Future<void> update(Word word) async {}

  /// 当前首页测试不需要实际删除内存集合。
  @override
  Future<void> delete(int id) async {}
}

/// 固定抛错 Store 用于检查首页错误输出区域。
class _ThrowingWordStore implements WordStore {
  /// const 构造器便于直接放进 const HomePage。
  const _ThrowingWordStore();

  /// 模拟 JSON 第三条数据损坏。
  @override
  Future<List<Word>> getAll() {
    // Future.error 对应异步 Store 抛出 FormatException。
    return Future<List<Word>>.error(
      const FormatException('broken-json-at-word-3'),
    );
  }

  /// 其余接口不属于本测试流程。
  @override
  Future<int> create(Word word) async => throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> update(Word word) async => throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> delete(int id) async => throw UnimplementedError();
}

/// 可控制完成时机的假音频播放器，避免 Widget 测试访问网络或 Android。
class _ControlledAudioPlayer implements WordAudioPlayer {
  /// 当前播放 Future 的完成器。
  Completer<void>? _completer;

  /// 累计真正进入 play 的次数。
  int playCount = 0;

  /// 最近一次拼写参数。
  String? lastSpelling;

  /// 最近一次口音参数。
  PronunciationAccent? lastAccent;

  /// 保存参数并返回尚未完成的 Future。
  @override
  Future<void> play(String spelling, PronunciationAccent accent) {
    // 记录调用次数。
    playCount += 1;
    // 记录拼写。
    lastSpelling = spelling;
    // 记录口音。
    lastAccent = accent;
    // 每次真正播放创建独立完成器。
    _completer = Completer<void>();
    // 首页会等待该 Future 决定何时隐藏喇叭。
    return _completer!.future;
  }

  /// 模拟音频自然播放完成。
  void complete() {
    // 只在尚未结束时完成一次。
    if (!(_completer?.isCompleted ?? true)) _completer!.complete();
  }

  /// 模拟页面主动停止。
  @override
  Future<void> stop() async {
    // stop 也结束当前 Future。
    complete();
  }
}
