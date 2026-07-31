// dart:io 提供目录与文件读取能力，作用类似 PHP 的 DirectoryIterator 和 file_get_contents。
import 'dart:io';

// flutter_test 提供 test、expect 等测试 API。
import 'package:flutter_test/flutter_test.dart';

///
/// 对源码执行图标规范检查，避免后续开发重新混入 Material 图标或文字型图标。
///
/// @return void
///
void main() {
  // 这一条测试扫描 lib 目录下的全部 Dart 源码。
  test('all interface icons use Tabler instead of built-in or text icons', () {
    // Directory('lib') 对应小程序项目中的源码根目录。
    final sourceDirectory = Directory('lib');
    // 递归取出所有文件，再只保留 .dart 文件。
    final dartFiles = sourceDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    // 该正则用于发现 Flutter Material Icons 和 CupertinoIcons 的静态调用。
    final builtInIconPattern = RegExp(r'\b(?:Icons|CupertinoIcons)\.');
    // 这些字符过去曾被当成勾选、方向、关闭或加减图标直接显示。
    const forbiddenTextIcons = <String>[
      '✓',
      '✔',
      '↑',
      '↓',
      '↕',
      '▼',
      '▲',
      '❯',
      '×',
      '✕',
      '＋',
      '−',
      '⋮',
      '⋯',
      '▶',
      '◀',
      '★',
      '☆',
    ];

    // 逐个检查源码文件，失败信息会精确指出文件路径。
    for (final file in dartFiles) {
      // readAsStringSync 相当于同步读取当前源码文本。
      final source = file.readAsStringSync();
      // 去掉每行双斜线后的注释，避免注释里的示例文字被误判为界面代码。
      final executableSource = source
          .split('\n')
          .map((line) => line.split('//').first)
          .join('\n');
      // 任何 Flutter 内置图标调用都应使测试失败。
      expect(
        builtInIconPattern.hasMatch(executableSource),
        isFalse,
        reason: '${file.path} 仍在使用 Flutter 内置图标，请改用 TablerIcons。',
      );
      // 任何直接写入源码字符串的图标字符也应使测试失败。
      for (final forbiddenIcon in forbiddenTextIcons) {
        // 单引号和双引号两种字符串写法都需要覆盖。
        final singleQuotedIcon = "'$forbiddenIcon'";
        final doubleQuotedIcon = '"$forbiddenIcon"';
        // 只有字符作为完整字符串时才视为文字型图标，普通业务文案不受影响。
        final containsTextIcon =
            executableSource.contains(singleQuotedIcon) ||
            executableSource.contains(doubleQuotedIcon);
        // 发现违规字符时给出明确的替换建议。
        expect(
          containsTextIcon,
          isFalse,
          reason: '${file.path} 仍把“$forbiddenIcon”作为文字图标，请改用 TablerIcons。',
        );
      }
    }
  });
}
