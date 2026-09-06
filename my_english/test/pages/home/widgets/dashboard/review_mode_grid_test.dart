// material.dart 提供测试页面、滚动容器与尺寸类型。
import 'package:flutter/material.dart';
// flutter_test 提供组件渲染、点击和断言能力。
import 'package:flutter_test/flutter_test.dart';

// AppTheme 提供全站统一的字号、字重与颜色槽位。
import 'package:my_english/common/theme.dart';
// 复习模块标识与三态进度模型（v2.0 起统一收敛到会话模型文件）。
import 'package:my_english/models/session.dart';
// 引入被测试的首页复习模式网格。
import 'package:my_english/pages/home/widgets/dashboard/review_mode_grid.dart';

///
/// 注册首页复习模式入口的展示与点击测试。
void main() {
  testWidgets('四张卡片按三态展示，点击回传对应模块', (tester) async {
    // 使用常见窄屏宽度，确认两列卡片在手机上能够完整容纳文案。
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 记录每次点击回传的模块，验证四张卡片各自绑定正确。
    final tapped = <ReviewModule>[];

    // 在可滚动页面中复刻首页卡片的真实水平留白。
    await tester.pumpWidget(
      MaterialApp(
        // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
        // 槽位取，缺了它读到的会是 Material 自带的默认字号。
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.pBase),
            child: ReviewModeGrid(
              moduleStates: const <ReviewModule, ReviewModuleState>{
                // 听音辨义今天的主线已经过关。
                ReviewModule.listeningMeaning: ReviewModuleState(
                  progress: ReviewModuleProgress.completed,
                ),
                // 词义连连正做到一半退了出来。
                ReviewModule.meaningMatch: ReviewModuleState(
                  progress: ReviewModuleProgress.active,
                ),
                // 拼写巩固也已开放，今天同样过关了。
                ReviewModule.spellingReinforcement: ReviewModuleState(
                  progress: ReviewModuleProgress.completed,
                ),
              },
              dailyGoal: 50,
              onOpenModule: tapped.add,
            ),
          ),
        ),
      ),
    );

    // 四个入口全部存在，旧的卡片速记与真题例句不再显示。
    expect(find.text('听音辨义'), findsOneWidget);
    expect(find.text('词义连连'), findsOneWidget);
    expect(find.text('拼写巩固'), findsOneWidget);
    expect(find.text('看义选词'), findsOneWidget);
    expect(find.text('卡片速记'), findsNothing);
    expect(find.text('真题例句'), findsNothing);
    // 标题右侧显示今天的真实题量。
    expect(find.text('今日目标 50 个'), findsOneWidget);
    // 词义连连采用更短的单行描述，不再在两列卡片里换行。
    final matchingDescription = tester.widget<Text>(find.text('释义配对 · 连续匹配'));
    expect(matchingDescription.maxLines, 1);
    // 徽章三态：听音辨义与拼写巩固已完成，词义连连进行中；
    // 看义选词没给状态，回落到「待完成」（2.0 起四个模块全部开放，不再有「即将开放」）。
    // 徽章永远是一个短词：已完成未巩固就是「已完成」（巩固态的两个短词见下方用例）。
    expect(find.text('已完成'), findsNWidgets(2));
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('待完成'), findsOneWidget);
    // 百分比彻底下线，任何一张卡片都不该再出现「%」。
    expect(find.textContaining('%'), findsNothing);

    // 四张卡片依次点击，回调必须带回各自的模块标识。
    await tester.tap(find.text('听音辨义'));
    await tester.tap(find.text('词义连连'));
    await tester.tap(find.text('拼写巩固'));
    await tester.tap(find.text('看义选词'));
    await tester.pump();
    expect(tapped, <ReviewModule>[
      ReviewModule.listeningMeaning,
      ReviewModule.meaningMatch,
      ReviewModule.spellingReinforcement,
      ReviewModule.meaningWordChoice,
    ]);
    // 整个窄屏布局没有出现文字或卡片溢出异常。
    expect(tester.takeException(), isNull);
  });

  testWidgets('今天还没开过局时四张卡片都显示待完成', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
        // 槽位取，缺了它读到的会是 Material 自带的默认字号。
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.pBase),
            child: ReviewModeGrid(
              // 空 Map 表示今天一个模块都没点开过。
              moduleStates: const <ReviewModule, ReviewModuleState>{},
              dailyGoal: 50,
              onOpenModule: (_) {},
            ),
          ),
        ),
      ),
    );

    // 四个模块都开放：一个都没点开过时全部显示待完成。
    expect(find.text('待完成'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('主线过关后巩固进行中，徽章只显示「巩固中」', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
        // 槽位取，缺了它读到的会是 Material 自带的默认字号。
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.pBase),
            child: ReviewModeGrid(
              moduleStates: const <ReviewModule, ReviewModuleState>{
                ReviewModule.listeningMeaning: ReviewModuleState(
                  progress: ReviewModuleProgress.completed,
                  isReinforcing: true,
                  // 与原生 fromMap 的产出保持一致：巩固进行中时
                  // barPhase 必为 reinforceActive。
                  barPhase: ReviewBarPhase.reinforceActive,
                ),
              },
              dailyGoal: 50,
              onOpenModule: (_) {},
            ),
          ),
        ),
      ),
    );

    // 已完成之后还在加练，用户一眼能看出自己现在做的是巩固；
    // 徽章不再带「已完成 ·」前缀，只显示巩固状态这一个短词。
    expect(find.text('巩固中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主线过关且巩固局也打完，徽章显示「已巩固」', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.pBase),
            child: ReviewModeGrid(
              moduleStates: const <ReviewModule, ReviewModuleState>{
                // 主线过关后连巩固局也完整打完：barPhase 由原生层精确合成
                // 为 reinforceDone，徽章要显示「已巩固」而不是「已完成」。
                ReviewModule.listeningMeaning: ReviewModuleState(
                  progress: ReviewModuleProgress.completed,
                  barPhase: ReviewBarPhase.reinforceDone,
                ),
              },
              dailyGoal: 50,
              onOpenModule: (_) {},
            ),
          ),
        ),
      ),
    );

    // 巩固已完成与已完成未巩固是两回事，短词必须区分开。
    expect(find.text('已巩固'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
    expect(find.text('巩固中'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
