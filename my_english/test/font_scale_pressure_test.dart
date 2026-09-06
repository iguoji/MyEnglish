// material.dart 提供 MaterialApp、MediaQuery 与 TextScaler。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 全局主题：耐压测试必须用真实主题，才能连带检查 TextTheme 的字号。
import 'package:my_english/common/theme.dart';
// 字体大小档位的定义处（标准 / 大 / 特大对应 1.0 / 1.15 / 1.3）。
import 'package:my_english/store/settings.dart';

// 六个页面的样本清单，与设计基线截图共用同一份。
import 'support/sample_pages.dart';

///
/// 「老年版」字号耐压测试。
///
/// 背景：全站文字放大不是逐处改字号，而是在 App 最外层拧一个倍数
/// （见 `lib/app.dart` 的 `_textScale`）。这种做法的代价是——放大之后，
/// 那些写死高度、写死宽度的地方会先撑不住：文字长出容器，Flutter 就会在
/// 控制台画黄黑条纹并报 `RenderFlex overflowed`。
///
/// 所以每开放一个新档位，都必须把六个页面在该档位下渲染一遍。这里检查的是
/// 「有没有溢出」而不是「好不好看」：
///
///   - 溢出会以异常形式被测试框架捕获，[WidgetTester.takeException] 能取到；
///   - 文字被 `TextOverflow.ellipsis` 截成「花园…」不算溢出，那是刻意设计，
///     只能靠人眼在真机上看，测试拦不住。
///
/// 换句话说，这个测试保证的是**不会出现黄黑条纹和被裁掉半个字的布局事故**，
/// 至于放大后某一行是否还够漂亮，仍然需要真机确认。
///
/// 另外补一道「量余量」的检查。上面说过截字是无声的，四个练习页的顶栏正好是
/// 这种地方：那一行写死 34 高，里面的数字被放大到 35 也不会报错，只会被裁掉
/// 一条。所以凡是声明了顶栏高度的页面，都额外量一次数字的实际高度，逼近上限
/// 就直接判失败——把「还剩几像素」这件事交给机器每次跑，而不是靠人眼看一次。
void main() {
  ///
  /// 在指定字号倍数下把一个页面完整渲染出来，并要求它不抛任何异常。
  ///
  /// [scale] 直接传倍数而不是档位，是为了将来想临时试 1.5 倍时不用先加枚举。
  Future<void> renderAt(
    WidgetTester tester,
    SamplePage page,
    double scale,
  ) async {
    // 固定 390×844：和设计基线截图同一台参考机型，宽度偏窄，放大后压力最大。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // 这里刻意照抄 `lib/app.dart` 里 MainApp 的写法：同样在 builder 里
        // 覆盖 textScaler。测试若换一种方式放大，测到的就不是线上那条路径了。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: page.build(),
      ),
    );

    // 与截图流程一致地推进两帧：先落地首帧，再让淡入与闪烁光标走完一轮。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.takeException(),
      isNull,
      reason: '${page.title} 在 $scale 倍字号下出现了布局溢出或异常',
    );

    // 顶栏那一行的高度是写死的，装不下也不会报错，只会安静地裁掉一条，
    // 所以这里主动把数字的实际高度量出来，和行高比一比。
    final labelKey = page.headerLabelKey;
    final rowHeight = page.headerRowHeight;
    if (labelKey != null && rowHeight != null) {
      final label = find.byKey(Key(labelKey));
      expect(
        label,
        findsOneWidget,
        reason:
            '${page.title} 顶栏进度数字的 key「$labelKey」没找到，'
            '要么页面改了 key，要么样本清单写错了',
      );
      expect(
        tester.getSize(label).height,
        lessThanOrEqualTo(rowHeight),
        reason:
            '${page.title} 顶栏进度数字在 $scale 倍字号下已经比那一行写死的 '
            '$rowHeight 高了，真机上会被裁掉一条——'
            '要么把该行改成最小高度（跟着内容一起长高），要么调低字号上限',
      );
    }

    // 卸载页面，让页面内的计时器全部清理，避免测试结束时挂起。
    await tester.pumpWidget(const SizedBox());
  }

  for (final page in samplePages()) {
    for (final scale in AppFontScale.values) {
      testWidgets('${page.title} · ${scale.label}字号不溢出', (tester) async {
        await renderAt(tester, page, scale.multiplier);
      });
    }
  }
}
