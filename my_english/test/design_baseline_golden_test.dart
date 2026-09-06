// material.dart 提供 MaterialApp 等应用级组件。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 设计基准：六个页面都用同一套主题渲染。
import 'package:my_english/common/theme.dart';

// 六个页面的样本清单与样本数据。
import 'support/sample_pages.dart';

///
/// 设计基线快照。
///
/// 这组 golden 是「设计令牌化」重构的判据：搬家阶段（把散落的字号/间距收进
/// `lib/common/design/`）要求这些图**逐像素不变**；收敛阶段（把奇数与 0.5px
/// 并成偶数台阶）则要求每一处差异都能说清是哪条收敛造成的。
///
/// 更新方式：`flutter test test/design_baseline_golden_test.dart --update-goldens`
///
/// 注意：Widget 测试用的是内置测试字体，文字会渲染成方块——这组图看的是
/// 版式、间距、圆角与配色，不是字形。
///
/// 页面清单与样本词表放在 `support/sample_pages.dart`，与「1.3 倍字号耐压
/// 测试」共用同一份，避免两边的「六个页面」慢慢变成不同的六个页面。
void main() {
  ///
  /// 统一的拍照流程：390×844 逻辑像素、关掉 DEBUG 角标、固定推进两帧。
  ///
  /// 固定的推进时长很重要：页面里有闪烁光标与卡片淡入，随机时间点会拍出
  /// 不同的中间帧，golden 就不稳定了。
  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    required bool dark,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: page,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
    // 卸载页面，让页面内的计时器全部清理，避免测试结束时挂起。
    await tester.pumpWidget(const SizedBox());
  }

  for (final dark in <bool>[false, true]) {
    final suffix = dark ? 'dark' : 'light';

    for (final page in samplePages()) {
      testWidgets('${page.title} · $suffix', (tester) async {
        await shoot(tester, '${page.slug}_$suffix', page.build(), dark: dark);
      });
    }
  }
}
