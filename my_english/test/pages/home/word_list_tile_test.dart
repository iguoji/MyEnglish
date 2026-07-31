// material.dart 提供测试所需的组件类型。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动。
import 'package:flutter_test/flutter_test.dart';
// 测试识别 Tabler 勾选图标，避免继续把文字字符当图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
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
            // 传入与旧 displayDate getter 等价的日期，保持测试断言不变。
            displayDate: item.reviewedAt ?? item.createdAt ?? item.updatedAt,
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

  // 收起状态：40 高标题行、红色难度徽章与右对齐日期。
  testWidgets('collapsed row shows badge, date and 40px header', (
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
    expect(find.text('能力、才能'), findsNothing);
  });

  // 行分隔线必须在内容上层绘制，避免真机渲染时被白色标题行或释义区盖住。
  testWidgets('row divider is painted in foreground with one logical pixel', (
    tester,
  ) async {
    // 渲染一条普通的收起单词行。
    await pumpTile(tester, item: sample);

    // WordListTile 根节点就是负责绘制分隔线的 DecoratedBox。
    final tileBox = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(WordListTile),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    // 前景绘制确保横线不会被内部白色组件覆盖。
    expect(tileBox.position, DecorationPosition.foreground);
    // 读取根节点的边框配置。
    final decoration = tileBox.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    // 只检查本需求关心的底部实线及其宽度。
    expect(border.bottom.style, BorderStyle.solid);
    expect(border.bottom.width, 1);
    // 浅色主题单词行延续第四轮决定：用更淡的 rowBorder（#EEF0F3），
    // 而非分组头/列表顶使用的 border（#E6E7E9）。
    expect(border.bottom.color, const Color(0xFFEEF0F3));
  });

  // 展开状态：按 index 降序显示两条 Meaning，释义默认用中文顿号连接。
  testWidgets('expanded row lists meanings with pos column', (tester) async {
    // 渲染展开行。
    await pumpTile(tester, item: sample, isExpanded: true);
    // 等待展开动画。
    await tester.pumpAndSettle();

    // 两条 Meaning 全部可见（词性大写显示）。
    expect(find.text('N.'), findsOneWidget);
    expect(find.text('能力、才能'), findsOneWidget);
    expect(find.text('ADJ.'), findsOneWidget);
    expect(find.text('能干的'), findsOneWidget);
    // 展开后整体高度超过标题行。
    expect(
      tester.getSize(find.byType(WordListTile)).height,
      greaterThan(WordListTile.headerHeight),
    );
  });

  // 自定义分隔符会替换默认顿号，验证组件没有写死任何一种标点。
  testWidgets('expanded row uses the configured definition separator', (
    tester,
  ) async {
    // 直接传入中文全角逗号模拟首页设置切换后的值。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordListTile(
            item: sample,
            dateReference: reference,
            displayDate:
                sample.reviewedAt ?? sample.createdAt ?? sample.updatedAt,
            isExpanded: true,
            definitionSeparator: '，',
            onTap: () {},
          ),
        ),
      ),
    );
    // 等待展开动画完成。
    await tester.pumpAndSettle();
    // 同一词性下两条定义使用全角逗号连成一个 Text。
    expect(find.text('能力，才能'), findsOneWidget);
    // 默认顿号文本不应同时存在。
    expect(find.text('能力、才能'), findsNothing);
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
    expect(find.byIcon(TablerIcons.check), findsNothing);
    // 点击勾选框（用稳定 key 精确命中，避免依赖脆弱坐标偏移）。
    await tester.tap(find.byKey(const Key('select-checkbox')));
    // 回调被触发一次。
    expect(toggled, 1);

    // 渲染选中状态。
    await pumpTile(tester, item: sample, selectMode: true, isSelected: true);
    // 选中后出现白色对勾。
    expect(find.byIcon(TablerIcons.check), findsOneWidget);
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
    expect(container.transform!.getTranslation().x, -WordListTile.actionWidth);
  });
}
