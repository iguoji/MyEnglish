// dart:async 提供 Completer，用于在测试中控制音频何时播放完成。
import 'dart:async';

// material.dart 提供测试需要识别的页面、边框和输入框类型。
import 'package:flutter/material.dart';
// services.dart 提供 MethodChannel，用于为分组 Store 注册测试桩。
import 'package:flutter/services.dart';
// flutter_test 提供 Widget 测试驱动，作用类似 PHPUnit 加小程序自动化工具。
import 'package:flutter_test/flutter_test.dart';
// 引入 Tabler 图标，用于按图标断言页脚图标项存在。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
// 引入被测试的首页。
import 'package:my_english/pages/home/home.dart';
// 引入全局 Meaning 与 Word 模型。
import 'package:my_english/models/learning_session.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入两个学习页，核对它们收到的单词快照与首页完全一致。
import 'package:my_english/pages/dictation/dictation_page.dart';
import 'package:my_english/pages/listening/listening_page.dart';
// 引入单词行，检查高度、徽章与展开内容。
import 'package:my_english/pages/home/widgets/word_list_tile.dart';
// 引入音频接口，测试使用不会访问真实网络的受控实现。
import 'package:my_english/services/word_audio.dart';
// 引入离线语音缓存服务，验证清空与 100% 提示逻辑。
import 'package:my_english/services/word_audio_cache.dart';
// 引入口音与设置 Store，验证播放参数和设置面板。
import 'package:my_english/store/settings.dart';
// 引入 Store 接口，测试会提供不依赖 Android 的内存实现。
import 'package:my_english/store/learning_session.dart';
import 'package:my_english/store/word.dart';

import '../../support/memory_learning_session_store.dart';

/// 注册首页 Widget 测试。
void main() {
  // 验证顶部问候、收录统计副标题与汉堡按钮。
  testWidgets('header shows greeting, subline and hamburger menu', (
    tester,
  ) async {
    // 使用内存 Store 渲染首页。
    await _pumpHome(tester);

    // 副标题包含收录数量与默认每日目标。
    expect(find.text('已收录 2 个单词 · 今日复习 0/100'), findsOneWidget);
    // 右上角汉堡按钮存在。
    expect(find.byKey(const Key('open-menu')), findsOneWidget);
    // 顶部不再显示秒级时间，也没有任何 DateTime 监听器。
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ValueListenableBuilder<DateTime>,
      ),
      findsNothing,
    );

    // 卸载页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证汉堡按钮打开右侧抽屉，抽屉包含四个入口与仓库信息。
  testWidgets('hamburger opens the end drawer with menu entries', (
    tester,
  ) async {
    // 打开首页。
    await _pumpHome(tester);

    // 点击汉堡按钮。
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();
    // 入口与内嵌设置全部出现：原"设置"项已被可直接操作的内嵌设置取代。
    expect(find.text('添加单词'), findsOneWidget);
    expect(find.text('口语发音'), findsOneWidget);
    expect(find.text('单词分隔'), findsOneWidget);
    expect(find.text('每日复习'), findsOneWidget);
    expect(find.text('数据导出'), findsOneWidget);
    // 页脚只显示 Github 与邮箱两个图标，不再有文字。
    expect(find.text('Github'), findsNothing);
    expect(find.text('asgeg@qq.com'), findsNothing);
    // 两个图标可点击项存在。
    expect(find.byIcon(TablerIcons.brandGithub), findsOneWidget);
    expect(find.byIcon(TablerIcons.mail), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证点击作者邮箱会自动复制并弹出提示。
  testWidgets('tapping author email copies it and shows a snackbar', (
    tester,
  ) async {
    // 测试环境无真实系统剪贴板，这里注入一个内存实现，既能验证复制内容，
    // 也避免 Clipboard.setData 因缺少平台 handler 而抛异常。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? stored;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        stored = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': stored};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    // 打开首页。
    await _pumpHome(tester);
    // 打开右侧抽屉。
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();

    // 点击页脚邮箱图标（页脚已改为仅图标）。
    await tester.tap(find.byIcon(TablerIcons.mail));
    // Toast 基于 Overlay + Future.delayed，pump 一帧让 Overlay 插入，
    // 再 pump 进场动画完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // 应弹出复制成功提示（Toast 文字居中对齐）。
    expect(find.text('已复制作者邮箱：asgeg@qq.com'), findsOneWidget);
    // 剪贴板中应已写入该邮箱。
    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'asgeg@qq.com');

    // 等待 Toast 定时器到期并完成退场动画，避免 pending timer。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证抽屉内直接内嵌的四项设置全部可用（不再弹出独立窗口）。
  testWidgets(
    'settings embedded in drawer update accent, separator, theme and goal',
    (tester) async {
      // 首页持有这份可观察内存设置。
      final settings = SettingsStore.inMemory();
      // 注入首页。
      await _pumpHome(tester, settings: settings);

      // 打开抽屉，设置项已直接内嵌在抽屉内，无需再开独立窗口。
      await tester.tap(find.byKey(const Key('open-menu')));
      await tester.pumpAndSettle();
      // 三项设置标题都存在（黑暗模式开关已移至顶部图标按钮）。
      expect(find.text('口语发音'), findsOneWidget);
      expect(find.text('单词分隔'), findsOneWidget);
      expect(find.text('每日复习'), findsOneWidget);
      // 默认值：美式、顿号、Light、100。
      expect(settings.accent, PronunciationAccent.american);
      expect(
        settings.definitionSeparator,
        DefinitionSeparator.ideographicComma,
      );
      expect(settings.theme, AppThemePreference.light);
      expect(settings.dailyGoal, 100);

      // 切换到英式。
      await tester.tap(find.byKey(const Key('accent-british')));
      await tester.pump();
      expect(settings.accent, PronunciationAccent.british);
      // 切换为中文全角逗号。
      await tester.tap(
        find.byKey(const Key('definition-separator-full_width_comma')),
      );
      await tester.pump();
      expect(settings.definitionSeparator, DefinitionSeparator.fullWidthComma);
      // 点击顶部主题切换图标，从 Light 切到 Dark。
      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(settings.theme, AppThemePreference.dark);
      // 每日复习 +5（卡片内步进器，先滚动确保可见再点击）。
      await tester.ensureVisible(find.byKey(const Key('goal-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal-plus')));
      await tester.pumpAndSettle();
      expect(settings.dailyGoal, 105);

      // 设置项内嵌在抽屉中，没有独立的"完成"按钮，直接收尾清理。
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    },
  );

  // 验证抽屉"离线语音"入口显示初始百分比，点击安全启动后台预缓存。
  testWidgets('offline speech entry shows percentage and starts caching', (
    tester,
  ) async {
    // 打开首页（默认注入静音播放器，缓存服务通道异常时安全回退 0%）。
    await _pumpHome(tester);
    // 打开右侧抽屉。
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();

    // "离线语音"入口出现，且初始未缓存任何音频时显示 0%。
    expect(find.text('离线语音'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    // 入口位于"数据导入"上方（抽屉顺序：离线语音 → 数据导入）。
    final offline = tester.getTopLeft(find.text('离线语音')).dy;
    final import = tester.getTopLeft(find.text('数据导入')).dy;
    expect(offline, lessThan(import));

    // 点击启动后台批量预缓存；测试无原生实现，应安全忽略异常而不崩溃。
    await tester.tap(find.byKey(const Key('offline-speech')));
    await tester.pumpAndSettle();
    // 入口仍然存在，未因后台任务异常而消失。
    expect(find.text('离线语音'), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证"离线语音"百分比能反映真实已缓存数量，且 Dart 端把拼写包装成 Map 传入。
  testWidgets('offline speech percentage reflects real cache progress', (
    tester,
  ) async {
    // 拦截音频通道：校验 getCacheProgress 收到的是 Map{spellings:...} 而非裸 List，
    // 并返回 3/4 的缓存进度（词库 2 词 → 总数 4，已缓存 3 → 75%）。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('my_english/word_audio'),
      (call) async {
        if (call.method == 'getCacheProgress') {
          // 若参数不是带 'spellings' 键的 Map（即旧 bug：裸 List），返回 0 让测试失败。
          final args = call.arguments;
          if (args is! Map || !args.containsKey('spellings')) {
            return <String, Object?>{'cached': 0, 'total': 0};
          }
          return <String, Object?>{'cached': 3, 'total': 4};
        }
        return null;
      },
    );
    // 测试结束注销桩。
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('my_english/word_audio'),
        null,
      ),
    );

    // 打开首页并展开抽屉。
    await _pumpHome(tester);
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();

    // 抽屉应显示真实缓存比例 75%，而不是旧 bug 的 0%。
    expect(find.text('离线语音'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证已 100% 缓存时点击"离线语音"只提示、不重复触发预缓存。
  testWidgets('offline speech at 100% only prompts instead of re-caching', (
    tester,
  ) async {
    // 拦截音频通道：让 getCacheProgress 返回已缓存=总数，使入口显示 100%。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 记录是否真的触发了 precache（预期不应触发）。
    var precacheCalled = false;
    messenger.setMockMethodCallHandler(
      const MethodChannel('my_english/word_audio'),
      (call) async {
        if (call.method == 'getCacheProgress') {
          if (call.arguments is! Map ||
              !call.arguments.containsKey('spellings')) {
            return <String, Object?>{'cached': 0, 'total': 0};
          }
          // 已缓存 4 = 总数 4 → 100%。
          return <String, Object?>{'cached': 4, 'total': 4};
        }
        if (call.method == 'precache') {
          precacheCalled = true;
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('my_english/word_audio'),
        null,
      ),
    );

    // 打开首页并展开抽屉。
    await _pumpHome(tester);
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();

    // 入口显示 100%。
    expect(find.text('离线语音'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    // 点击入口：应给提示且不再发起预缓存。
    await tester.tap(find.byKey(const Key('offline-speech')));
    // Toast 基于 Overlay + Future.delayed，pump 一帧让 Overlay 插入，
    // 再 pump 进场动画完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(precacheCalled, isFalse);
    // 提示文案出现（Toast 文字居中对齐）。
    expect(find.text('离线语音已缓存完整'), findsOneWidget);

    // 等待 Toast 定时器到期并完成退场动画，避免 pending timer。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证 clearCacheFiles 调用原生 clearAudioCache 并把进度重置为 0。
  testWidgets('clear data also clears offline audio cache', (tester) async {
    // 拦截音频通道，记录 clearAudioCache 是否被调用与参数是否合法。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var clearCalled = false;
    messenger.setMockMethodCallHandler(
      const MethodChannel('my_english/word_audio'),
      (call) async {
        if (call.method == 'clearAudioCache') {
          clearCalled = true;
          return null;
        }
        if (call.method == 'getCacheProgress') {
          return <String, Object?>{'cached': 0, 'total': 0};
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('my_english/word_audio'),
        null,
      ),
    );

    // 注入两个单词，让缓存服务记录一份词表（getCacheProgress 在桩里回退 0）。
    await WordAudioCache.instance.setWordList(<String>['apple', 'banana']);
    // 触发清空缓存文件（同时应重置本地进度为 0）。
    await WordAudioCache.instance.clearCacheFiles();

    // 原生 clearAudioCache 被调用。
    expect(clearCalled, isTrue);
    // 本地进度被重置为 0/0。
    expect(WordAudioCache.instance.percent, 0);
    expect(WordAudioCache.instance.total, 0);
    expect(WordAudioCache.instance.isCaching, isFalse);

    // 清理页面。
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
    // 顶部线必须最后绘制，否则列表白色背景可能在真机上把它盖住。
    expect(listBox.position, DecorationPosition.foreground);
    // 生产代码明确使用 BoxDecoration。
    final decoration = listBox.decoration as BoxDecoration;
    // 前景装饰只能画边框，不能再带白色背景，否则会遮住列表中的所有内容。
    expect(decoration.color, isNull);
    // 生产代码明确使用 Border。
    final border = decoration.border! as Border;
    // 顶部是实线。
    expect(border.top.style, BorderStyle.solid);
    // 使用完整的 1 个逻辑像素，保证高分辨率真机仍清晰可见。
    expect(border.top.width, 1);
    // 列表顶部统一使用 Tabler 表格边框色 #E6E7E9。
    expect(border.top.color, const Color(0xFFE6E7E9));
    // 左右和底部不属于列表外框。
    expect(border.left.style, BorderStyle.none);
    expect(border.right.style, BorderStyle.none);
    expect(border.bottom.style, BorderStyle.none);
    // 列表白底由外层 ColoredBox 在内容之前绘制。
    final background = tester.widget<ColoredBox>(
      find.ancestor(of: listFinder, matching: find.byType(ColoredBox)).first,
    );
    expect(background.color, Colors.white);
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

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证滚动条始终显示、支持拖动，并与吸顶列表使用同一控制器。
  testWidgets('word list has an interactive draggable scrollbar', (
    tester,
  ) async {
    // 打开首页。
    await _pumpHome(tester);

    // 页面只需要一个垂直 Scrollbar（chips 横向列表没有 Scrollbar）。
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    // 真机首次打开时滑块已经可见。
    expect(scrollbar.thumbVisibility, isTrue);
    // 用户可以直接按住滑块拖动。
    expect(scrollbar.interactive, isTrue);
    // 读取首页真正承载分组和单词的 CustomScrollView。
    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const Key('word-list-scroll-view')),
    );
    // 两者必须共享同一个控制器，拖动才会真正改变列表位置。
    expect(scrollbar.controller, same(scrollView.controller));
    // 最后一段 SliverPadding 继续为悬浮学习按钮保留 116 像素空间。
    final bottomPadding = scrollView.slivers.last as SliverPadding;
    expect(bottomPadding.padding, const EdgeInsets.only(bottom: 116));

    // 清理页面。
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
    // 页面按设计稿显示无匹配状态。
    expect(find.text('未找到相关单词'), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证搜索框固定 40 高、图标 20，并保持文字垂直居中。
  testWidgets('search field is 40 pixels high with centered content', (
    tester,
  ) async {
    // 渲染首页。
    await _pumpHome(tester);
    // 读取搜索输入框实例配置（页面此时只有这一个 TextField）。
    final textField = tester.widget<TextField>(find.byType(TextField));
    // 实际布局高度必须为 40 逻辑像素。
    expect(tester.getSize(find.byType(TextField)).height, 40);
    // 输入文字按垂直中心对齐。
    expect(textField.textAlignVertical, TextAlignVertical.center);
    // 输入文字和 placeholder 使用一致行高。
    expect(textField.style?.height, 1.2);
    expect(textField.decoration!.hintStyle?.height, 1.2);
    // 左侧搜索图标为 20 像素。
    final searchIcon = textField.decoration!.prefixIcon! as Icon;
    expect(searchIcon.size, 20);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证点击单词行同时播放发音并展开释义（设计稿行为）。
  testWidgets('tapping a row plays audio and expands meanings together', (
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

    // 收起时第一行高度为设计稿的 36 像素标题行。
    expect(
      tester.getSize(find.byType(WordListTile).first).height,
      WordListTile.headerHeight,
    );

    // 点击 ability 行；喇叭动画持续循环，因此用固定时长 pump 而非 pumpAndSettle。
    await tester.tap(find.text('ability'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // 只发出一次播放请求。
    expect(audioPlayer.playCount, 1);
    // 参数保留真实 spelling。
    expect(audioPlayer.lastSpelling, 'ability');
    // 参数使用设置中的英式口音。
    expect(audioPlayer.lastAccent, PronunciationAccent.british);
    // 播放期间左侧出现“实心喇叭 + 三道弧线”的自绘动画。
    expect(find.byKey(const Key('playing-speaker-icon')), findsOneWidget);
    // 释义同步展开：两个 Meaning 各自显示为一行。
    expect(find.text('能力、才能'), findsOneWidget);
    expect(find.text('能干的'), findsOneWidget);
    // 展开后整项高度大于标题行。
    expect(
      tester.getSize(find.byType(WordListTile).first).height,
      greaterThan(WordListTile.headerHeight),
    );

    // 播放尚未结束时重复点击同一行：不重新请求，只切换展开。
    await tester.tap(find.text('ability'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(audioPlayer.playCount, 1);
    // 释义已被收起。
    expect(find.text('能力、才能'), findsNothing);

    // 手动模拟原生播放自然结束。
    audioPlayer.complete();
    await tester.pump();
    // Future 完成后喇叭消失。
    expect(find.byKey(const Key('playing-speaker-icon')), findsNothing);

    // 释放 SettingsStore 和页面资源。
    settings.dispose();
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
    // 注入包含重复 spelling 的测试数据。
    await _pumpHome(tester, words: words);

    // 列表必须显示两行相同文本。
    expect(find.text('same'), findsNWidgets(2));
    // 只点击第一行。
    await tester.tap(find.text('same').first);
    // 等待展开动画完成。
    await tester.pumpAndSettle();
    // 第一行 Meaning 已显示。
    expect(find.text('第一条'), findsOneWidget);
    // 第二行没有被相同 spelling 连带展开。
    expect(find.text('第二条'), findsNothing);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证字母、难度、日期都有双向排序；null 难度按 0 参与，null 日期随方向落在边界。
  testWidgets('sort bar toggles all fields with the agreed null rules', (
    tester,
  ) async {
    // 第一个单词复习时间最早，但难度最低。
    final words = <Word>[
      Word(
        id: 21,
        spelling: 'zebra',
        difficulty: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 7, 1),
        reviewedAt: DateTime(2026, 1, 1),
      ),
      // 第二个单词没有更新时间，复习时间较新。
      Word(
        id: 22,
        spelling: 'apple',
        difficulty: 3,
        createdAt: DateTime(2026, 6, 1),
        reviewedAt: DateTime(2026, 6, 1),
      ),
      // 第三个单词故意没有难度和日期，难度层按 0 参与比较。
      const Word(id: 23, spelling: 'middle'),
    ];
    // 使用稳定测试数据打开首页。
    await _pumpHome(tester, words: words);

    // 排序项本身使用纯 GestureDetector，不允许被 InkWell 包裹后产生点击背景色。
    final alphabetSort = find.byKey(const Key('word-sort-alphabet'));
    // key 直接落在 GestureDetector 上，点击区域仍然完整可用。
    expect(tester.widget(alphabetSort), isA<GestureDetector>());
    // 向父级查找不到 InkWell，代表按下时不会出现 Material 水波纹或背景块。
    expect(
      find.ancestor(of: alphabetSort, matching: find.byType(InkWell)),
      findsNothing,
    );

    // 默认排序：编号升序 → 字母升序 → 难度降序 → 日期降序。
    // 三个词 id 依次递增，编号升序即保持 Store 返回顺序。
    _expectTextsInVerticalOrder(tester, <String>['zebra', 'apple', 'middle']);
    // 第一次点字母是升序。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['apple', 'middle', 'zebra']);
    // 再点字母切到降序。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['zebra', 'middle', 'apple']);

    // 第一次点难度默认高到低，null 难度按 0 落在最后。
    await tester.tap(find.byKey(const Key('word-sort-difficulty')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['apple', 'zebra', 'middle']);
    // 再点难度切到升序，从 0/null 开始，然后是 1、3。
    await tester.tap(find.byKey(const Key('word-sort-difficulty')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['middle', 'zebra', 'apple']);

    // 第一次点日期默认最近到最早；默认模式下日期取 reviewedAt：
    // apple(6/1) 排在 zebra(1/1) 前，middle 无复习时间固定末尾（降序 null 在后）。
    await tester.tap(find.byKey(const Key('word-sort-date')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['apple', 'zebra', 'middle']);
    // 再点日期从早到晚，空日期排最前（升序 null 在前，与难度升序一致）。
    await tester.tap(find.byKey(const Key('word-sort-date')));
    await tester.pump();
    _expectTextsInVerticalOrder(tester, <String>['middle', 'zebra', 'apple']);

    // 清理页面资源。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证每种排序都执行约定的多级次序，保底编号升序。
  testWidgets('sorting applies the agreed multi-level tie-breakers', (
    tester,
  ) async {
    // 四个单词难度完全相同，用来检验难度排序的后续层级。
    final sameDifficultyWords = <Word>[
      // 复习时间第二新，应排第二。
      Word(
        id: 31,
        spelling: 'delta',
        difficulty: 5,
        createdAt: DateTime(2026, 3, 1),
        reviewedAt: DateTime(2026, 3, 1),
      ),
      // 复习时间最新，应排第一。
      Word(
        id: 32,
        spelling: 'alpha',
        difficulty: 5,
        createdAt: DateTime(2026, 5, 1),
        reviewedAt: DateTime(2026, 5, 1),
      ),
      // 无复习时间，与 bravo 同组后比拼写。
      const Word(id: 33, spelling: 'echo', difficulty: 5),
      // 无复习时间，拼写字母序在 echo 之前。
      const Word(id: 34, spelling: 'bravo', difficulty: 5),
    ];
    // 打开首页。
    await _pumpHome(tester, words: sameDifficultyWords);
    // 点击难度排序；所有难度相同，顺序完全由后续层级决定。
    await tester.tap(find.byKey(const Key('word-sort-difficulty')));
    await tester.pump();
    // 先日期降序，无日期组固定在后并按拼写升序。
    _expectTextsInVerticalOrder(tester, <String>[
      'alpha',
      'delta',
      'bravo',
      'echo',
    ]);

    // 三个重复拼写单词用来检验字母排序的难度、日期层级。
    final sameSpellingWords = <Word>[
      // 难度最低，应排最后。
      Word(
        id: 41,
        spelling: 'same',
        difficulty: 1,
        createdAt: DateTime(2026, 7, 1),
        reviewedAt: DateTime(2026, 7, 1),
      ),
      // 难度最高但复习时间较旧，应排第二。
      Word(
        id: 42,
        spelling: 'same',
        difficulty: 9,
        createdAt: DateTime(2026, 1, 1),
        reviewedAt: DateTime(2026, 1, 1),
      ),
      // 难度同为最高且复习时间更新，应排第一。
      Word(
        id: 43,
        spelling: 'same',
        difficulty: 9,
        createdAt: DateTime(2026, 6, 1),
        reviewedAt: DateTime(2026, 6, 1),
      ),
    ];
    // 重新打开首页。
    await _pumpHome(tester, words: sameSpellingWords);
    // 点击字母排序；拼写完全相同，顺序由难度降序和日期降序决定。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    // 文字相同无法用文本定位，改为逐行读取列表项的 Word 主键。
    expect(_visibleWordIds(tester), <int>[43, 42, 41]);

    // 两个字段完全相同的单词只剩编号可比，Store 顺序故意倒置。
    final twinWords = <Word>[
      // 编号大的排在 Store 前面。
      Word(
        id: 52,
        spelling: 'twin',
        difficulty: 2,
        createdAt: DateTime(2026, 4, 1),
      ),
      // 编号小的应在排序后排到前面。
      Word(
        id: 51,
        spelling: 'twin',
        difficulty: 2,
        createdAt: DateTime(2026, 4, 1),
      ),
    ];
    // 重新打开首页。
    await _pumpHome(tester, words: twinWords);
    // 点击字母排序触发完整比较链。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    // 前三级全部打平后按编号升序。
    expect(_visibleWordIds(tester), <int>[51, 52]);

    // 清理页面资源。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证分组视角切换：难度视角生成"难度 N"与"无难度"分组头。
  testWidgets('difficulty mode groups words by difficulty value', (
    tester,
  ) async {
    // 打开首页（ability 难度 3，abandon 无难度）。
    await _pumpHome(tester);

    // 打开模式菜单。
    await tester.tap(find.byKey(const Key('group-mode-button')));
    await tester.pumpAndSettle();
    // 选择难度视角。
    await tester.tap(find.byKey(const Key('group-mode-difficulty')));
    await tester.pumpAndSettle();
    // 出现两个难度分组头。
    expect(find.text('难度 3'), findsWidgets);
    expect(find.text('无难度'), findsWidgets);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证长分组滚动时，当前分组行固定在列表顶部，并由下一组自然接替。
  testWidgets('section header stays pinned while its words scroll', (
    tester,
  ) async {
    // 第一组准备足够多的单词，保证只滚动组内内容时还不会到达下一分组。
    final words = <Word>[
      for (var index = 0; index < 24; index++)
        Word(
          id: index + 1,
          spelling: 'word${index.toString().padLeft(2, '0')}',
          difficulty: 3,
        ),
      // 第二个难度值用于确认页面确实生成了多个独立吸顶区块。
      const Word(id: 100, spelling: 'lower', difficulty: 2),
    ];
    // 用长列表打开首页。
    await _pumpHome(tester, words: words);
    // 切换到按难度分组，得到“难度 3”和“难度 2”两个区块。
    await tester.tap(find.byKey(const Key('group-mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-mode-difficulty')));
    await tester.pumpAndSettle();

    // 从滚动组件配置中读取全部 Sliver；屏幕外分组尚未挂载，也仍应存在于配置列表。
    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const Key('word-list-scroll-view')),
    );
    // 每个分组都使用独立的主轴组，避免多个 pinned 标题永久堆叠。
    final sectionGroups = scrollView.slivers
        .whereType<SliverMainAxisGroup>()
        .toList(growable: false);
    expect(sectionGroups, hasLength(2));
    // 每个主轴组的第一个 Sliver 都是对应分组的吸顶标题。
    final stickyHeaders = sectionGroups
        .map((group) => group.children.first as SliverPersistentHeader)
        .toList(growable: false);
    expect(stickyHeaders, hasLength(2));
    expect(stickyHeaders.every((header) => header.pinned), isTrue);

    // 记录第一组标题刚出现时的位置，也就是列表内容区顶部。
    final firstHeader = find.byKey(const Key('section-d3'));
    final initialTop = tester.getTopLeft(firstHeader).dy;
    // 只滚动第一组内部的若干单词，不触及下一分组。
    await tester.drag(
      find.byKey(const Key('word-list-scroll-view')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    // 单词已经滚动，但“难度 3”仍停留在原来的列表顶部。
    expect(tester.getTopLeft(firstHeader).dy, closeTo(initialTop, 0.1));

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证分组头点击可折叠该组单词，"折叠/展开"按钮可整体切换。
  testWidgets('section headers collapse and expand rows', (tester) async {
    // 打开首页；默认全部单词在"未分组"。
    await _pumpHome(tester);

    // 初始两行单词都可见。
    expect(find.text('ability'), findsOneWidget);
    // 点击"未分组"分组头折叠。
    await tester.tap(find.byKey(const Key('section-c0')));
    await tester.pumpAndSettle();
    // 折叠后行消失。
    expect(find.text('ability'), findsNothing);
    // 顶部按钮此时显示"展开"。
    await tester.tap(find.byKey(const Key('toggle-collapse-all')));
    await tester.pumpAndSettle();
    // 全部展开后行回来了。
    expect(find.text('ability'), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证选择模式：勾选、全选、反选与复制到自定义分组。
  testWidgets('select mode supports selecting and copying words', (
    tester,
  ) async {
    // 首页的 _groups 是真实 GroupStore，会走 MethodChannel；测试环境没有
    // 原生实现，这里注册最小桩只处理分组相关方法（单词仍走注入的 Memory Store）。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('my_english/word_store'),
      (call) async {
        // 加载分组返回空列表。
        if (call.method == 'getAllGroups') return <Object?>[];
        // 新建分组固定返回 id=1，便于断言分组区块 key 为 c1。
        if (call.method == 'createGroup') return 1;
        // 其余分组操作返回 Future<void>。
        return null;
      },
    );
    // 测试结束后注销桩，避免影响其他用例。
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('my_english/word_store'),
        null,
      ),
    );

    // 打开首页。
    await _pumpHome(tester);

    // 进入选择模式。
    await tester.tap(find.byKey(const Key('toggle-select-mode')));
    await tester.pump();
    // 出现选择工具行。
    expect(find.text('已选 0'), findsOneWidget);
    // 首页全部纯文字动作都必须关闭按压背景和水波纹。
    for (final key in <String>[
      'toggle-collapse-all',
      'toggle-select-mode',
      'select-all',
      'invert-selection',
      'move-selected',
      'copy-selected',
    ]) {
      // 从带 key 的动作组件内部取得真正响应点击的 InkWell。
      final inkWell = tester.widget<InkWell>(
        find
            .descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(InkWell),
            )
            .first,
      );
      // 按下时覆盖层仍应透明。
      expect(
        inkWell.overlayColor!.resolve(const <WidgetState>{WidgetState.pressed}),
        Colors.transparent,
      );
      // 同时禁用水波纹，确保真机不会闪出背景色。
      expect(inkWell.splashFactory, NoSplash.splashFactory);
    }
    // 点击 ability 行改为切换勾选而不是播放。
    await tester.tap(find.text('ability'));
    await tester.pump();
    expect(find.text('已选 1'), findsOneWidget);
    // 全选两条。
    await tester.tap(find.byKey(const Key('select-all')));
    await tester.pump();
    expect(find.text('已选 2'), findsOneWidget);
    // 反选后回到 0。
    await tester.tap(find.byKey(const Key('invert-selection')));
    await tester.pump();
    expect(find.text('已选 0'), findsOneWidget);

    // 复制目标只能是自定义分组，先通过管理面板建一个（桩返回 id=1）。
    await tester.tap(find.byKey(const Key('open-manage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-group')));
    await tester.pumpAndSettle();
    // 关闭管理面板。
    await tester.tap(find.byKey(const Key('manage-done')));
    await tester.pumpAndSettle();
    // 新建分组区块已出现。
    expect(find.byKey(const Key('section-c1')), findsOneWidget);

    // 勾选 abandon 并执行复制。
    await tester.tap(find.text('abandon'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-selected')));
    await tester.pumpAndSettle();
    // 复制面板只列出自定义分组（不含「未分组」），选择「新分组 1」(id=1)。
    await tester.tap(find.byKey(const Key('pick-group-1')));
    await tester.pumpAndSettle();
    // abandon 被加入分组 1，因此只在 c1 区块出现一次（不再是未分组成员）。
    expect(find.text('abandon'), findsOneWidget);
    // 复制后该单词确实归属分组 1 的区块。
    expect(find.byKey(const Key('section-c1')), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证左滑露出"修改/删除"，删除需二次确认后生效。
  testWidgets('swipe left reveals actions and delete needs confirmation', (
    tester,
  ) async {
    // 打开首页。
    await _pumpHome(tester);

    // 在 ability 行上向左拖动超过阈值。
    await tester.drag(find.text('ability'), const Offset(-80, 0));
    await tester.pumpAndSettle();
    // 点击删除操作（每行都有同名 key，取第一行 ability 的那个）。
    await tester.tap(find.byKey(const Key('swipe-delete')).first);
    await tester.pumpAndSettle();
    // 出现确认对话框。
    expect(find.text('删除单词'), findsOneWidget);
    expect(find.textContaining('ability'), findsWidgets);
    // 先取消：单词仍在。
    await tester.tap(find.byKey(const Key('delete-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('ability'), findsOneWidget);

    // 再来一次并确认删除。
    await tester.drag(find.text('ability'), const Offset(-80, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('swipe-delete')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    // 单词已被删除。
    expect(find.text('ability'), findsNothing);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证抽屉"添加单词"表单可以创建新单词。
  testWidgets('add word form creates a new word', (tester) async {
    // 打开首页。
    await _pumpHome(tester);

    // 抽屉 → 添加单词。
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-add-word')));
    await tester.pumpAndSettle();
    // 表单标题为"添加单词"。
    expect(find.text('添加单词'), findsOneWidget);
    // 输入拼写。
    await tester.enterText(find.byKey(const Key('form-spelling')), 'brandnew');
    await tester.pump();
    // 提交表单。
    await tester.tap(find.byKey(const Key('form-submit')));
    await tester.pumpAndSettle();
    // 新单词出现在列表。
    expect(find.text('brandnew'), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证新版“学习”主按钮可以展开两个入口并显示目标数量。
  testWidgets('learning fab expands actions with target word count', (
    tester,
  ) async {
    // 打开首页（两个单词）。
    await _pumpHome(tester);

    // 默认只显示一个“学习”主按钮，具体入口尚未占用列表空间。
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('随身听 · 2'), findsNothing);
    expect(find.text('默写 · 2'), findsNothing);

    // 点击主按钮后向上展开两个新版入口。
    await tester.tap(find.byKey(const Key('toggle-learning-menu')));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('随身听 · 2'), findsOneWidget);
    expect(find.text('默写 · 2'), findsOneWidget);
    // 没有本地未完成会话时，右侧不能预留空的继续按钮或间距。
    expect(find.byKey(const Key('continue-player')), findsNothing);
    expect(find.byKey(const Key('continue-dictation')), findsNothing);

    // 点击遮罩应收起菜单。
    await tester.tap(find.byKey(const Key('learning-menu-backdrop')));
    await tester.pumpAndSettle();
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('随身听 · 2'), findsNothing);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('learning fab shows spaced resume buttons and restores history', (
    tester,
  ) async {
    // 两种学习方式都准备一条未完成记录；随身听列表故意使用与首页相反的顺序。
    final sessionStore = MemoryLearningSessionStore(<LearningSession>[
      const LearningSession(
        type: LearningSessionType.listening,
        wordIds: <int>[2, 1],
        state: <String, Object?>{
          'index': 1,
          'isPlaying': false,
          'repeat': 2,
          'interval': 2,
          'loop': true,
        },
      ),
      const LearningSession(
        type: LearningSessionType.dictation,
        wordIds: <int>[1, 2],
        state: <String, Object?>{'wordIndex': 0, 'stage': 'word'},
      ),
    ]);
    await _pumpHome(tester, sessionStore: sessionStore);

    // 展开菜单后，两行右侧都动画显示继续按钮。
    await tester.tap(find.byKey(const Key('toggle-learning-menu')));
    await tester.pumpAndSettle();
    final playerAction = tester.getRect(find.byKey(const Key('open-player')));
    final playerContinue = tester.getRect(
      find.byKey(const Key('continue-player')),
    );
    expect(find.byKey(const Key('continue-dictation')), findsOneWidget);
    // 继续按钮严格位于主入口右侧，并保留至少 8 像素防误触间距。
    expect(playerContinue.left - playerAction.right, greaterThanOrEqualTo(8));

    // 点击随身听继续后，恢复列表必须使用历史顺序，而非首页当前顺序。
    await tester.tap(find.byKey(const Key('continue-player')));
    await tester.pumpAndSettle();
    final listeningPage = tester.widget<ListeningPage>(
      find.byType(ListeningPage),
    );
    expect(
      listeningPage.words.map((word) => word.id).toList(growable: false),
      <int?>[2, 1],
    );
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证未勾选时，随身听和默写都接收首页当前完整列表顺序。
  testWidgets('learning pages receive the same full ordered snapshot', (
    tester,
  ) async {
    // 故意使用与字母升序不同的原始顺序，避免测试仅因默认数据巧合通过。
    const words = <Word>[
      Word(id: 21, spelling: 'zebra'),
      Word(id: 22, spelling: 'apple'),
      Word(id: 23, spelling: 'middle'),
    ];
    // 渲染首页。
    await _pumpHome(tester, words: words);
    // 切换为字母升序，当前首页列表应变为 apple、middle、zebra。
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    expect(_visibleWordIds(tester), <int?>[22, 23, 21]);

    // 展开学习菜单并进入随身听。
    await tester.tap(find.byKey(const Key('toggle-learning-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    // 直接读取随身听 Widget 接收的 Word 对象顺序。
    final listeningPage = tester.widget<ListeningPage>(
      find.byType(ListeningPage),
    );
    expect(
      listeningPage.words.map((word) => word.id).toList(growable: false),
      <int?>[22, 23, 21],
    );
    // 返回首页。
    await tester.tap(find.byKey(const Key('close-listening')));
    await tester.pumpAndSettle();

    // 再次展开同一菜单并进入默写。
    await tester.tap(find.byKey(const Key('toggle-learning-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-dict')));
    await tester.pumpAndSettle();
    // 默写的真正学习列表必须与刚才的随身听完全相同。
    final dictationPage = tester.widget<DictationPage>(
      find.byType(DictationPage),
    );
    expect(
      dictationPage.words.map((word) => word.id).toList(growable: false),
      <int?>[22, 23, 21],
    );
    // 销毁学习页并停止测试音频。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证用户以任意点击顺序勾选时，学习页仍按首页列表顺序过滤。
  testWidgets('selected learning snapshot preserves visible list order', (
    tester,
  ) async {
    // 原数据与上一用例一致。
    const words = <Word>[
      Word(id: 21, spelling: 'zebra'),
      Word(id: 22, spelling: 'apple'),
      Word(id: 23, spelling: 'middle'),
    ];
    // 打开首页并切换到字母升序。
    await _pumpHome(tester, words: words);
    await tester.tap(find.byKey(const Key('word-sort-alphabet')));
    await tester.pump();
    // 进入选择模式。
    await tester.tap(find.byKey(const Key('toggle-select-mode')));
    await tester.pump();
    // 故意先勾选列表底部 zebra，再勾选中间 middle。
    await tester.tap(find.text('zebra'));
    await tester.pump();
    await tester.tap(find.text('middle'));
    await tester.pump();
    expect(find.text('已选 2'), findsOneWidget);

    // 打开随身听。
    await tester.tap(find.byKey(const Key('toggle-learning-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-player')));
    await tester.pumpAndSettle();
    // 不能使用点击顺序 zebra、middle，而必须使用首页顺序 middle、zebra。
    final listeningPage = tester.widget<ListeningPage>(
      find.byType(ListeningPage),
    );
    expect(
      listeningPage.words.map((word) => word.id).toList(growable: false),
      <int?>[23, 21],
    );
    // 返回首页。
    await tester.tap(find.byKey(const Key('close-listening')));
    await tester.pumpAndSettle();

    // 打开默写。
    await tester.tap(find.byKey(const Key('toggle-learning-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-dict')));
    await tester.pumpAndSettle();
    // 默写收到的学习列表必须与随身听一致。
    final dictationPage = tester.widget<DictationPage>(
      find.byType(DictationPage),
    );
    expect(
      dictationPage.words.map((word) => word.id).toList(growable: false),
      <int?>[23, 21],
    );
    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证加载失败不仅显示标题，也输出真实异常内容。
  testWidgets('load error details are visible and selectable', (tester) async {
    // 本用例故意注入抛错 Store；首页的 debugPrint/debugPrintStack 属于预期内
    // 诊断日志，这里临时静音避免污染测试输出。
    final originalDebugPrint = debugPrint;
    // 空实现丢弃日志。
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      // 使用固定抛错 Store 模拟 JSON 解析失败。
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            store: const _ThrowingWordStore(),
            audioPlayer: _SilentAudioPlayer(),
          ),
        ),
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

      // 清理页面。
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      // Widget 测试会在 tearDown 前检查全局调试变量，因此必须在测试主体结束前恢复。
      debugPrint = originalDebugPrint;
    }
  });

  // 验证窄屏大字体不会让首页布局溢出。
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
    // 使用 Sliver 的高性能业务列表仍然存在。
    expect(find.byKey(const Key('word-list-scroll-view')), findsOneWidget);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 验证后台/前台切换不会产生异常。
  testWidgets('lifecycle changes are handled safely', (tester) async {
    // 打开首页。
    await _pumpHome(tester);
    // 模拟 App 失焦进入后台；新版 Flutter 校验状态机，paused 不能直接跳回
    // resumed，因此用 inactive 表示离开前台（首页对任何非前台状态处理一致）。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // 虚拟推进两秒。
    await tester.pump(const Duration(seconds: 2));
    // 后台阶段无异常。
    expect(tester.takeException(), isNull);
    // 模拟 App 回到前台；inactive → resumed 是合法状态转移。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // 处理恢复更新。
    await tester.pump();
    // 恢复阶段无异常。
    expect(tester.takeException(), isNull);

    // 清理页面。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// 用内存 Store 渲染首页，并推进一帧等待异步 Future 完成。
Future<void> _pumpHome(
  WidgetTester tester, {
  List<Word>? words,
  SettingsStore? settings,
  WordAudioPlayer? audioPlayer,
  LearningSessionStore? sessionStore,
}) async {
  // MaterialApp 提供 TextField 等组件所需的 Material 环境。
  await tester.pumpWidget(
    MaterialApp(
      // HomePage 通过构造器注入测试 Store 与静音播放器。
      home: HomePage(
        // UniqueKey 强制每次 pump 创建全新 State；否则同一用例内换数据重
        // 新渲染时，Flutter 会复用旧 State 并保留旧 Store 与旧单词列表。
        key: UniqueKey(),
        store: _MemoryWordStore(words ?? _sampleWords()),
        settings: settings,
        // 默认注入静音播放器，避免点击行时访问不存在的原生通道。
        audioPlayer: audioPlayer ?? _SilentAudioPlayer(),
        // 默认使用空内存会话，避免 Widget 测试依赖 Android MethodChannel。
        sessionStore: sessionStore ?? MemoryLearningSessionStore(),
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

/// 从上到下读取当前列表每一行对应的 Word 主键。
List<int?> _visibleWordIds(WidgetTester tester) {
  // widgetList 按组件树顺序返回，与各分组 SliverList 从上到下的显示顺序一致。
  return tester
      .widgetList<WordListTile>(find.byType(WordListTile))
      .map((tile) => tile.item.id)
      .toList(growable: false);
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

/// 支持增删改的内存 Store，让选择/复制/删除/表单用例真实生效。
class _MemoryWordStore implements WordStore {
  /// 接收初始 fixture，并复制为内部可变列表。
  _MemoryWordStore(List<Word> initial) : _words = List<Word>.of(initial);

  /// 内存中的单词集合。
  final List<Word> _words;

  /// 异步返回全部数据副本。
  @override
  Future<List<Word>> getAll() async => List<Word>.unmodifiable(_words);

  /// 只回刷测试中用到的指定 id 单词。
  @override
  Future<List<Word>> getByIds(List<int> ids) async {
    // 按 id 过滤内存单词，保持与原生一致的语义。
    final idSet = ids.toSet();
    return List<Word>.unmodifiable(
      _words
          .where((word) => word.id != null && idSet.contains(word.id))
          .toList(),
    );
  }

  /// 生成新的自增主键并追加。
  @override
  Future<int> create(Word word) async {
    // 计算当前最大主键。
    var maxId = 0;
    for (final item in _words) {
      final id = item.id;
      if (id != null && id > maxId) maxId = id;
    }
    // 新主键。
    final newId = maxId + 1;
    // 带主键落入内存；分组直接沿用传入的 groupIds 列表。
    _words.add(
      Word(
        id: newId,
        spelling: word.spelling,
        meanings: word.meanings,
        difficulty: word.difficulty,
        groupIds: word.groupIds,
        reviewedAt: word.reviewedAt,
        createdAt: word.createdAt ?? DateTime.now(),
        updatedAt: word.updatedAt ?? DateTime.now(),
      ),
    );
    // 返回主键。
    return newId;
  }

  /// 按主键替换。
  @override
  Future<void> update(Word word) async {
    // 定位目标下标。
    final index = _words.indexWhere((item) => item.id == word.id);
    // 找不到时抛出与生产实现一致的错误。
    if (index < 0) throw StateError('找不到要更新的内存单词 id=${word.id}');
    // 替换对象。
    _words[index] = word;
  }

  /// 按主键移除。
  @override
  Future<void> delete(int id) async {
    // 直接过滤目标。
    _words.removeWhere((item) => item.id == id);
  }

  /// 整库替换写入：先清空旧数据再装入导入列表。
  @override
  Future<void> importWords(List<Word> words) async {
    // 清空后追加导入副本。
    _words
      ..clear()
      ..addAll(words);
  }

  /// 整库替换（含分组/成员）写入：内存 Store 只重建单词，分组由 UI 层负责。
  @override
  Future<void> importData(Map<String, Object?> data) async {
    // 顶层 words 才是单词数组；groups/members 在 UI 测试中不参与。
    final rawWords = data['words'];
    // 结构不符时保持现状，避免测试误清空。
    if (rawWords is! List) return;
    // 逐条解析为模型。
    final parsed = <Word>[];
    for (final raw in rawWords) {
      // 非对象项直接跳过。
      if (raw is! Map) continue;
      // Map.from 收窄动态键值后交给模型构造器。
      parsed.add(Word.fromMap(Map<Object?, Object?>.from(raw)));
    }
    // 清空后装入导入副本。
    _words
      ..clear()
      ..addAll(parsed);
  }

  /// 清空全部内存单词。
  @override
  Future<void> clearAll() async {
    // 清空内部列表。
    _words.clear();
  }
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
  Future<List<Word>> getByIds(List<int> ids) async =>
      throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<int> create(Word word) async => throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> update(Word word) async => throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> delete(int id) async => throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> importWords(List<Word> words) async =>
      throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> importData(Map<String, Object?> data) async =>
      throw UnimplementedError();

  /// 其余接口不属于本测试流程。
  @override
  Future<void> clearAll() async => throw UnimplementedError();
}

/// 立即完成的静音播放器；默认注入避免测试访问原生通道。
class _SilentAudioPlayer implements WordAudioPlayer {
  /// 播放立即成功。
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  /// 停止同样立即成功。
  @override
  Future<void> stop() async {}
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
