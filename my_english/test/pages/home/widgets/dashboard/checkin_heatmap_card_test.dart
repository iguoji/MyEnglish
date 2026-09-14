// material.dart 提供测试页面需要的 MaterialApp 与 Scaffold。
import 'package:flutter/material.dart';
// flutter_test 提供组件渲染、点击和断言能力。
import 'package:flutter_test/flutter_test.dart';

// AppTheme 提供全站统一的字号、字重与颜色槽位。
import 'package:my_english/common/theme.dart';
// 引入被测试的首页复习总数卡片。
import 'package:my_english/pages/home/widgets/dashboard/checkin_heatmap_card.dart';

// 内存会话库：卡片要的「每天复习了多少个词」由它直接给出。
import '../../../../support/memory_session_store.dart';

///
/// 注册复习总数月历的交互测试。
///
/// 数据来源从构造器注入（`sessionStore`），不必再截获原生通道：卡片只要一份
/// 「日期 → 当天去重单词数」的聚合，内存库直接就能给。用真实实现而不是通道桩的
/// 另一个好处是——测试跑的就是正式那条取值路径，不会出现「桩写错了但测试照样绿」。
void main() {
  ///
  /// 渲染一张卡片：本月每天按 [counts] 给复习量，其余日子为 0。
  Future<void> pumpCard(
    WidgetTester tester, {
    required Map<String, int> counts,
    int dailyGoal = 100,
  }) async {
    // 固定为常见窄屏手机宽度，确保七列月历在真实空间内也不会溢出。
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
          // 首页会在复习总数卡片外再留一档页面留白，此处复刻真实布局宽度。
          body: Padding(
            padding: const EdgeInsets.all(AppSpace.pBase),
            // refreshToken 是首页发给卡片的“数据变了”通知单号；
            // 单测里只渲染一次，固定给 0 即可。
            child: CheckinHeatmapCard(
              dailyGoal: dailyGoal,
              refreshToken: 0,
              sessionStore: MemorySessionStore(initialDailyCounts: counts),
            ),
          ),
        ),
      ),
    );
    // 内存库的 Future 在微任务里完成，多推一帧让 setState 生效。
    await tester.pump();
  }

  ///
  /// 读图例里某一档的数量：先定位标签文字，再取同一行里跟在它后面的那个数字。
  int legendCount(WidgetTester tester, String label) {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    final texts = tester.widgetList<Text>(
      find.descendant(of: row, matching: find.byType(Text)),
    );
    // 行内顺序固定是「标签、数量」，所以最后一个就是数量。
    return int.parse(texts.last.data!);
  }

  testWidgets('点击日期后只在该日期旁显示当天复习数量', (tester) async {
    // 使用今天可以保证测试无论哪天运行，目标日期都在默认展示的本月内。
    final dateKey = _dateKey(DateTime.now());
    // 使用三位数验证日期旁数字空间不足时也能自动缩小，而不是横向溢出。
    const reviewCount = 137;
    await pumpCard(tester, counts: <String, int>{dateKey: reviewCount});

    // 用户点击前，月历只显示日期，不主动展示复习数量。
    expect(find.byKey(Key('checkin-count-$dateKey')), findsNothing);

    // 点击今天的日期格并刷新选中状态。
    await tester.tap(find.byKey(Key('checkin-day-$dateKey')));
    await tester.pump();

    // 日期旁只出现原始数字，不附加“个”或“单词”等文字。
    final countFinder = find.byKey(Key('checkin-count-$dateKey'));
    expect(countFinder, findsOneWidget);
    expect(tester.widget<Text>(countFinder).data, '$reviewCount');
    // 固定网格内完成布局，确保三位数不会触发 Flutter 溢出异常。
    expect(tester.takeException(), isNull);
  });

  testWidgets('复习量按每日目标的六成分档', (tester) async {
    // 目标 100，四个边界各取一天：0 未复习、59 少量、60 达标、100 达标、101 超额。
    final month = DateTime.now();
    await pumpCard(
      tester,
      counts: <String, int>{
        _dateKey(DateTime(month.year, month.month, 1)): 0,
        _dateKey(DateTime(month.year, month.month, 2)): 59,
        _dateKey(DateTime(month.year, month.month, 3)): 60,
        _dateKey(DateTime(month.year, month.month, 4)): 100,
        _dateKey(DateTime(month.year, month.month, 5)): 101,
      },
    );

    // 本月天数：达标档吃了 60 与 100 两天，其余按档各归各位。
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    expect(legendCount(tester, '超额'), 1);
    expect(legendCount(tester, '达标'), 2);
    expect(legendCount(tester, '少量'), 1);
    expect(legendCount(tester, '未复习'), dayCount - 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本月没有复习记录时整月都是未复习档', (tester) async {
    await pumpCard(tester, counts: const <String, int>{});

    final today = DateTime.now();
    final dayCount = DateTime(today.year, today.month + 1, 0).day;
    // 没数据也要把整月画满：格子一格不少，只是全部落在「未复习」档。
    expect(legendCount(tester, '未复习'), dayCount);
    expect(legendCount(tester, '超额'), 0);
    expect(legendCount(tester, '达标'), 0);
    expect(legendCount(tester, '少量'), 0);
    expect(tester.takeException(), isNull);
  });
}

///
/// 把日期格式化成组件测试使用的 yyyy-MM-dd 键。
String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
