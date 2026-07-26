// foundation.dart 提供 ValueListenable；可以把它理解成小程序里可被监听的 data 字段。
import 'package:flutter/foundation.dart';
// material.dart 提供 Text、Column 等界面组件，类似小程序内置的 view、text 组件集合。
import 'package:flutter/material.dart';

// 引入应用统一颜色；作用类似 PHP 的公共配置文件或小程序的全局 WXSS 变量。
// 引入公用日期时间格式化函数，其他页面也能使用同一规则。
import '../../../common/date.dart';

/// 首页顶部的问候语和完整日期时间。
///
/// [StatelessWidget] 表示该组件自己不保存状态，类似一个只根据传入参数输出 HTML 的
/// PHP 模板，或只根据 properties 渲染的小程序组件。
class HomeHeader extends StatelessWidget {
  /// `const` 构造函数表示参数不变时 Flutter 可以复用该组件，减少重复创建对象。
  const HomeHeader({
    required this.nowListenable,
    required this.onSettingsPressed,
    super.key,
  });

  /// 父页面传入的时间监听器，作用类似小程序组件接收一个会变化的 properties 字段。
  final ValueListenable<DateTime> nowListenable;

  /// 点击右上角设置图标时由首页打开底部设置面板。
  final VoidCallback onSettingsPressed;

  /// `@override` 表示这里重写 Flutter 父类规定的 build 方法，类似实现框架约定的入口。
  @override
  Widget build(BuildContext context) {
    // 只监听时间数据；每秒仅重新执行这个 builder，不会让下面的单词列表一起刷新。
    return ValueListenableBuilder<DateTime>(
      // 指定需要监听的时间，相当于小程序针对某一项 data 做局部更新。
      valueListenable: nowListenable,
      // now 是最新时间；child 此处没有静态子节点，所以不用第三个参数。
      builder: (context, now, child) {
        // Row 让问候文字在左、设置图标在右。
        return Row(
          // 顶部对齐避免设置按钮影响两行文字的位置。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Expanded 让左侧文字占用设置按钮之外的全部宽度。
            Expanded(
              // Column 类似纵向排列的多个 view。
              child: Column(
                // 两行文字左对齐。
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行显示根据当前小时得到的问候语。
                  Text(
                    // 调用本文件私有方法生成问候语。
                    _greeting(now),
                    // 使用当前 Light/Dark 的标题颜色。
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      // 全局要求字间距固定为 0。
                      letterSpacing: 0,
                    ),
                  ),
                  // 问候语和日期之间加入 4 像素间距。
                  const SizedBox(height: 4),
                  // 第二行显示“年月日 时分秒”。
                  Text(
                    // 每秒根据最新 DateTime 生成完整日期时间字符串。
                    formatFullDateTime(now),
                    // 日期时间使用主题次要文字色。
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      // 不使用额外字距，保持全局文本规范。
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            // 与左侧标题保留 8 像素间距。
            const SizedBox(width: 8),
            // IconButton 使用熟悉的齿轮符号打开设置。
            IconButton(
              // key 供 Widget 测试准确点击。
              key: const Key('open-settings'),
              // 点击由首页弹出 BottomSheet。
              onPressed: onSettingsPressed,
              // Material 标准设置图标。
              icon: const Icon(Icons.settings_outlined),
              // 图标固定 22 像素，与工作型首页密度一致。
              iconSize: 22,
              // 按钮固定 40×40，提供稳定触控区域。
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              // 移除额外默认内边距，图标仍由 constraints 居中。
              padding: EdgeInsets.zero,
              // 长按显示用途。
              tooltip: '设置',
            ),
          ],
        );
      },
    );
  }

  /// 按小时返回问候语，写法对应 PHP 中根据 date('G') 做 if 判断。
  String _greeting(DateTime time) {
    // 从 DateTime 取 0—23 的小时数，相当于 PHP 的 (int) date('G')。
    final hour = time.hour;
    // 05:00—11:59 显示早上好；单行 return 表示命中后立即结束函数。
    if (hour >= 5 && hour < 12) return '早上好';
    // 12:00—13:59 显示中午好。
    if (hour >= 12 && hour < 14) return '中午好';
    // 14:00—17:59 显示下午好。
    if (hour >= 14 && hour < 18) return '下午好';
    // 其余时间统一显示晚上好。
    return '晚上好';
  }
}
