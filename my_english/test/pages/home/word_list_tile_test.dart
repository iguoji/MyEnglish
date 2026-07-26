// material.dart 提供测试所需的组件类型。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动。
import 'package:flutter_test/flutter_test.dart';
// 引入全局模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入被测试的单词行。
import 'package:my_english/pages/home/widgets/word_list_tile.dart';

/// 注册单词行组件测试。
void main() {
  // 固定日期参考，保证格式化结果稳定。
  final reference = DateTime(2026, 7, 26);

  // 构造带难度、日期与两条 Meaning 的样例单词。
  final sample = Word(
    id: 1,
    spelling: 'ability',
    difficulty: 3,
    createdAt: DateTime(2026, 1, 5),
    meanings: const <Meaning>[
      Meaning(index: 2, pos: 'n.', definitions: <String>['能力', '才能']),
      Meaning(index: 1, pos: 'adj.', definitions: <String>['能干的']),
    ],
  );

  /// 用最小 Material 环境渲染一行。
  Future<void> pumpTile(
    WidgetTester tester, {
    required Word item,
    bool isExpanded = false,
    bool selectMode = false,
    bool isSelected = false,
    bool isSwipedOpen = false,
    ValueChanged<bool>? onSwipeChanged,
    VoidCallback? onToggleSelect,
  }) {
    // Scaffold 提供 InkWell 需要的 Material 祖先。
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordListTile(
            item: item,
            dateReference: reference,
            isExpanded: isExpanded,
            selectMode: selectMode,
            isSelected: isSelected,
            isSwipedOpen: isSwipedOpen,
            onTap: () {},
            onSwipeChanged: onSwipeChanged,
            onToggleSelect: onToggleSelect,
          ),
        ),
      ),
    );
  }

  // 收起状态：36 高标题行、红色难度徽章与右对齐日期。
  testWidgets('collapsed row shows badge, date and 36px header', (
    tester,
  ) async {
    // 渲染收起行。
    await pumpTile(tester, item: sample);

    // 标题行高度为设计稿的 36。
    expect(
      tester.getSize(find.byType(WordListTile)).height,
      WordListTile.headerHeight,
    );
    // 单词文字可见。
    expect(find.text('ability'), findsOneWidget);
    // 难度徽章显示数值 3。
    expect(find.text('3'), findsOneWidget);
    // 同年日期按 MM.dd 显示。
    expect(find.text('01.05'), findsOneWidget);
    // 收起时不显示释义。
    expect(find.text('能力；才能'), findsNothing);
  });

  // 展开状态：按 index 降序显示两条 Meaning，释义用中文分号连接。
  testWidgets('expanded row lists meanings with pos column', (tester) async {
    // 渲染展开行。
    await pumpTile(tester, item: sample, isExpanded: true);
    // 等待展开动画。
    await tester.pumpAndSettle();

    // 两条 Meaning 全部可见。
    expect(find.text('n.'), findsOneWidget);
    expect(find.text('能力；才能'), findsOneWidget);
    expect(find.text('adj.'), findsOneWidget);
    expect(find.text('能干的'), findsOneWidget);
    // 展开后整体高度超过标题行。
    expect(
      tester.getSize(find.byType(WordListTile)).height,
      greaterThan(WordListTile.headerHeight),
    );
  });

  // 选择模式：显示勾选框，点击触发回调；选中时出现对勾。
  testWidgets('select mode shows a toggleable checkbox', (tester) async {
    // 记录回调次数。
    var toggled = 0;
    // 渲染未选中状态。
    await pumpTile(
      tester,
      item: sample,
      selectMode: true,
      onToggleSelect: () => toggled += 1,
    );
    // 未选中时没有对勾。
    expect(find.text('✓'), findsNothing);
    // 点击勾选框（单词左侧 18×18 区域）。
    await tester.tapAt(
      tester.getTopLeft(find.text('ability')) + const Offset(-18, 8),
    );
    // 回调被触发一次。
    expect(toggled, 1);

    // 渲染选中状态。
    await pumpTile(
      tester,
      item: sample,
      selectMode: true,
      isSelected: true,
    );
    // 选中后出现白色对勾。
    expect(find.text('✓'), findsOneWidget);
  });

  // 左滑打开操作区、右滑关闭，回调收到正确方向。
  testWidgets('horizontal drags report swipe open and close', (tester) async {
    // 记录最近一次回调值。
    bool? lastChange;
    // 渲染可滑动行。
    await pumpTile(
      tester,
      item: sample,
      onSwipeChanged: (open) => lastChange = open,
    );

    // 向左拖动超过 30 像素阈值。
    await tester.drag(find.text('ability'), const Offset(-80, 0));
    await tester.pumpAndSettle();
    // 收到"打开"回调。
    expect(lastChange, isTrue);

    // 向右拖动关闭。
    await tester.drag(find.text('ability'), const Offset(80, 0));
    await tester.pumpAndSettle();
    // 收到"关闭"回调。
    expect(lastChange, isFalse);
  });

  // 滑开状态下"修改/删除"操作按钮可见且可点击区域露出。
  testWidgets('swiped-open row translates to reveal actions', (tester) async {
    // 渲染滑开状态。
    await pumpTile(tester, item: sample, isSwipedOpen: true);
    await tester.pumpAndSettle();

    // 两个操作文字都在组件树中。
    expect(find.text('修改'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    // 标题行平移了操作区宽度。
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    // transform 的 x 平移等于 -128。
    expect(
      container.transform!.getTranslation().x,
      -WordListTile.actionWidth,
    );
  });
}
