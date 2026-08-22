// material.dart 提供测试页面、滚动容器与尺寸类型。
import 'package:flutter/material.dart';
// flutter_test 提供组件渲染、点击和断言能力。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的首页复习模式网格。
import 'package:my_english/pages/home/widgets/dashboard/review_mode_grid.dart';
// 复习模式稳定键用于构造四份互相独立的测试进度。
import 'package:my_english/store/record.dart';
// 词义连连首页进度模型（不写复习记录，百分比来自本局会话）。
import 'package:my_english/pages/meaning_match/meaning_match_page.dart';

///
/// 注册首页复习模式入口的展示与点击测试。
///
/// @return void
///
void main() {
  testWidgets('展示四种约定模式且听音辨义与词义连连进入现有流程', (tester) async {
    // 使用常见窄屏宽度，确认两列卡片在手机上能够完整容纳文案。
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 分别记录已开放入口与未开放入口的点击次数。
    var listeningMeaningOpenCount = 0;
    var meaningMatchOpenCount = 0;
    var spellingOpenCount = 0;
    var meaningWordOpenCount = 0;

    // 在可滚动页面中复刻首页卡片的真实水平留白。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ReviewModeGrid(
              reviewCountsByModule: const <String, int>{
                // 听音辨义达到每日目标 100 -> 显示「已完成」徽章。
                ReviewModule.listeningMeaning: 100,
                // 词义连连不写复习记录，此值被忽略，真实百分比来自下方进度。
                ReviewModule.meaningMatch: 35,
                ReviewModule.spellingReinforcement: 100,
                ReviewModule.meaningWordChoice: 7,
              },
              // 词义连连首页百分比来自本局会话（已匹配/总配对），与复习记录无关。
              meaningMatchProgress: MeaningMatchProgress(
                totalPairs: 100,
                bestMatchedPairs: 35,
                completed: false,
              ),
              dailyGoal: 100,
              onOpenListeningMeaning: () => listeningMeaningOpenCount++,
              onOpenMeaningMatch: () => meaningMatchOpenCount++,
              onOpenSpellingReinforcement: () => spellingOpenCount++,
              onOpenMeaningWordChoice: () => meaningWordOpenCount++,
            ),
          ),
        ),
      ),
    );

    // 新的四个入口全部存在，旧的卡片速记与真题例句不再显示。
    expect(find.text('听音辨义'), findsOneWidget);
    expect(find.text('词义连连'), findsOneWidget);
    expect(find.text('拼写巩固'), findsOneWidget);
    expect(find.text('看义选词'), findsOneWidget);
    expect(find.text('卡片速记'), findsNothing);
    expect(find.text('真题例句'), findsNothing);
    // 词义连连采用更短的单行描述，不再在两列卡片里换行。
    final matchingDescription = tester.widget<Text>(find.text('释义配对 · 连续匹配'));
    expect(matchingDescription.maxLines, 1);
    // 听音辨义达标显示「已完成」；词义连连按本局会话显示 35%；
    // 两张未开放模块统一显示「即将开放」（不看各自 reviewCount）。
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('即将开放'), findsNWidgets(2));
    expect(find.text('暂未开放'), findsNothing);

    // 听音辨义只调用现有学习流程，不触发未开放提示。
    await tester.tap(find.text('听音辨义'));
    await tester.pump();
    expect(listeningMeaningOpenCount, 1);
    expect(meaningMatchOpenCount, 0);
    expect(spellingOpenCount, 0);
    expect(meaningWordOpenCount, 0);

    // 依次点击其余三张卡片，它们全部只触发统一的未开放提示。
    await tester.tap(find.text('词义连连'));
    await tester.tap(find.text('拼写巩固'));
    await tester.tap(find.text('看义选词'));
    await tester.pump();
    expect(listeningMeaningOpenCount, 1);
    expect(meaningMatchOpenCount, 1);
    expect(spellingOpenCount, 1);
    expect(meaningWordOpenCount, 1);
    // 整个窄屏布局没有出现文字或卡片溢出异常。
    expect(tester.takeException(), isNull);
  });
}
