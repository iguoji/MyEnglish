// material.dart 提供 Widget、Border、Row 和颜色类型。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动。
import 'package:flutter_test/flutter_test.dart';
// 引入全局 Meaning 与 Word 模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入被测试的可展开单词行。
import 'package:my_english/pages/home/widgets/word_list_tile.dart';

/// 注册 WordListTile 收起布局、展开对齐和 badge 测试。
void main() {
  // 验证收起标题行保持 40 高、Tabler 下边框和原 flex 布局。
  testWidgets('collapsed word row keeps the compact flex layout', (
    tester,
  ) async {
    // 使用没有 Meaning 的普通单词。
    await _pumpTile(
      tester,
      Word(id: 1, spelling: 'ability', createdAt: DateTime(2025, 7, 26)),
    );

    // 没有展开内容时整项高度严格等于标题高度。
    expect(
      tester.getSize(find.byType(WordListTile)).height,
      WordListTile.headerHeight,
    );
    // 根 DecoratedBox 绘制每项下边框。
    final rootBox = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(WordListTile),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    // 读取边框配置。
    final border = (rootBox.decoration as BoxDecoration).border! as Border;
    // 下边框可见，其他方向不存在。
    expect(border.bottom.style, BorderStyle.solid);
    // Tabler 常用表格分隔色固定为 #E6E7E9，不能回退到更深的旧颜色。
    expect(border.bottom.color, const Color(0xFFE6E7E9));
    expect(border.top.style, BorderStyle.none);
    expect(border.left.style, BorderStyle.none);
    expect(border.right.style, BorderStyle.none);

    // WordListTile 内第一个 Row 是标题 flex 容器。
    final rows = tester
        .widgetList<Row>(
          find.descendant(
            of: find.byType(WordListTile),
            matching: find.byType(Row),
          ),
        )
        .toList();
    // 左侧第一个 child 必须是 Expanded，自动占大部分宽度。
    expect(rows.first.children.first, isA<Expanded>());
    // 右侧最后一个 child 按自身宽度布局。
    final metadataRow = rows.first.children.last as Row;
    expect(metadataRow.mainAxisSize, MainAxisSize.min);
    // 静态日期按非今年格式显示。
    expect(find.text('2025.07.26'), findsOneWidget);
    // 行内没有秒级 DateTime 监听器。
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ValueListenableBuilder<DateTime>,
      ),
      findsNothing,
    );
  });

  // 验证展开时一个 Meaning 一行，并让 definitions 起点完全对齐。
  testWidgets('expanded meanings use one aligned row per meaning', (
    tester,
  ) async {
    // 构造两个不同词性的 Meaning。
    const word = Word(
      id: 2,
      spelling: 'become',
      meanings: <Meaning>[
        Meaning(index: 2, pos: 'vlink.', definitions: <String>['成为', '变得']),
        Meaning(index: 1, pos: 'vt.', definitions: <String>['适合', '相称']),
      ],
    );
    // 直接以展开状态渲染，准确检查最终布局。
    await _pumpTile(tester, word, isExpanded: true);
    // 等待 AnimatedSize 完成首帧布局。
    await tester.pumpAndSettle();

    // 每个 Meaning 的 definitions 只出现一次。
    final firstDefinition = find.text('成为；变得');
    final secondDefinition = find.text('适合；相称');
    expect(firstDefinition, findsOneWidget);
    expect(secondDefinition, findsOneWidget);
    // 第二个 Meaning 位于第一个 Meaning 下方。
    expect(
      tester.getTopLeft(secondDefinition).dy,
      greaterThan(tester.getTopLeft(firstDefinition).dy),
    );
    // 固定词性列宽保证两条释义从同一 x 坐标开始。
    expect(
      tester.getTopLeft(firstDefinition).dx,
      tester.getTopLeft(secondDefinition).dx,
    );
    // 展开后的项目高度大于 40 像素标题行。
    expect(
      tester.getSize(find.byType(WordListTile)).height,
      greaterThan(WordListTile.headerHeight),
    );
  });

  // 验证任何非空难度都显示同一个红色 badge。
  testWidgets('non-null difficulty always uses the red badge', (tester) async {
    // 使用大于旧上限 5 的难度，确认 UI 不限制范围。
    await _pumpTile(
      tester,
      Word(
        id: 3,
        spelling: 'animal',
        difficulty: 10,
        createdAt: DateTime(2026, 7, 26),
      ),
    );

    // badge 显示真实数值 10。
    final badgeText = tester.widget<Text>(find.text('10'));
    // 所有难度只使用统一红色。
    expect(badgeText.style?.color, const Color(0xFFD63939));
  });

  // 验证 null 难度完全不创建 badge 空位。
  testWidgets('null difficulty does not reserve badge space', (tester) async {
    // 构造无 difficulty、无 Meaning 的 Word。
    await _pumpTile(
      tester,
      Word(id: 4, spelling: 'boy', createdAt: DateTime(2026, 7, 26)),
    );

    // 右侧 metadata Row 只有日期一个 child。
    final rows = tester
        .widgetList<Row>(
          find.descendant(
            of: find.byType(WordListTile),
            matching: find.byType(Row),
          ),
        )
        .toList();
    // 读取标题行最后一个 Row。
    final metadataRow = rows.first.children.last as Row;
    // 没有空 badge、空间距或展开图标。
    expect(metadataRow.children, hasLength(1));
  });

  // 验证列表日期优先使用 updatedAt，没有时才回退 createdAt。
  testWidgets('date display prefers updated date over created date', (
    tester,
  ) async {
    // 创建日期属于去年，更新日期属于当前测试年份。
    await _pumpTile(
      tester,
      Word(
        id: 5,
        spelling: 'change',
        createdAt: DateTime(2025, 1, 2),
        updatedAt: DateTime(2026, 7, 25),
      ),
    );

    // 显示当前年份更新日期的 MM.dd。
    expect(find.text('07.25'), findsOneWidget);
    // 旧创建日期不能出现在列表。
    expect(find.text('2025.01.02'), findsNothing);
  });

  // 验证播放喇叭使用固定占位，出现后标题行仍保持 40 高。
  testWidgets('playing speaker does not change the compact row size', (
    tester,
  ) async {
    // 直接渲染播放状态。
    await _pumpTile(
      tester,
      const Word(id: 6, spelling: 'sound'),
      isPlaying: true,
    );

    // 播放图标可见。
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    // 动画只缩放绘制，不改变 40 像素布局。
    expect(
      tester.getSize(find.byType(WordListTile)).height,
      WordListTile.headerHeight,
    );
  });
}

/// 在最小 Material 页面中渲染一条 WordListTile。
Future<void> _pumpTile(
  WidgetTester tester,
  Word word, {
  bool isExpanded = false,
  bool isPlaying = false,
}) async {
  // MaterialApp/Scaffold 提供正常布局和主题上下文。
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WordListTile(
          // 传入测试 Word。
          item: word,
          // 固定 2026 年作为日期参考。
          dateReference: DateTime(2026, 7, 26),
          // 由当前测试决定是否展开。
          isExpanded: isExpanded,
          // 由当前测试决定是否显示播放喇叭。
          isPlaying: isPlaying,
          // 本文件只检查布局，点击行为由 HomePage 测试覆盖。
          onTap: () {},
        ),
      ),
    ),
  );
}
