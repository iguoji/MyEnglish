// material.dart 提供测试页面需要的 MaterialApp 与 Scaffold。
import 'package:flutter/material.dart';
// services.dart 提供 MethodChannel，用内存桩代替 Android 数据库查询。
import 'package:flutter/services.dart';
// flutter_test 提供组件渲染、点击和断言能力。
import 'package:flutter_test/flutter_test.dart';
// 引入被测试的首页复习总数卡片。
import 'package:my_english/pages/home/widgets/dashboard/checkin_heatmap_card.dart';

///
/// 注册复习总数月历的交互测试。
void main() {
  // 正式 RecordStore 使用的通道名；测试在此截获每日统计查询。
  const recordChannel = MethodChannel('my_english/word_store');

  testWidgets('点击日期后只在该日期旁显示当天复习数量', (tester) async {
    // 固定为常见窄屏手机宽度，确保七列月历在真实空间内也不会溢出。
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 使用今天可以保证测试无论哪天运行，目标日期都在默认展示的本月内。
    final now = DateTime.now();
    final dateKey = _dateKey(now);
    // 使用三位数验证日期旁数字空间不足时也能自动缩小，而不是横向溢出。
    const reviewCount = 137;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // 模拟 Android 返回“今天不论对错练了 137 个不同单词”。
    // 热力图口径是「复习总数」，走的是 getDailyTotalCounts。
    messenger.setMockMethodCallHandler(recordChannel, (call) async {
      if (call.method == 'getDailyTotalCounts') {
        return <Map<String, Object?>>[
          <String, Object?>{'date': dateKey, 'count': reviewCount},
        ];
      }
      return null;
    });
    // 每个测试结束都移除通道桩，避免影响其他测试文件。
    addTearDown(() => messenger.setMockMethodCallHandler(recordChannel, null));

    // 在真实 Material 页面结构中渲染卡片并等待异步统计刷新一帧。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          // 首页会在复习总数卡片外再留 20 像素，此处复刻真实布局宽度。
          body: Padding(
            padding: EdgeInsets.all(20),
            // refreshToken 是首页发给卡片的“数据变了”通知单号；
            // 单测里只渲染一次，固定给 0 即可。
            child: CheckinHeatmapCard(dailyGoal: 100, refreshToken: 0),
          ),
        ),
      ),
    );
    await tester.pump();

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
}

///
/// 把日期格式化成组件测试使用的 yyyy-MM-dd 键。
String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
