// dart:io 提供目录与文件读取能力。
import 'dart:io';

// flutter_test 提供 test、expect 等测试 API。
import 'package:flutter_test/flutter_test.dart';

///
/// 对源码执行图标规范检查，避免后续开发重新混入 Material 图标或文字型图标。
///
/// 两条规则各管一件事：
///
/// 1. **不许用别家的图标。** Flutter 内置的 `Icons.` / `CupertinoIcons.`，
///    以及拿「✓」「×」这类字符当图标显示，都不行——全站图标只能来自 Tabler。
/// 2. **不许直接点名 Tabler 的图标。** 页面里写 `AppGlyph.retry`，
///    而不是 `TablerIcons.refresh`。理由见 `lib/common/design/glyphs.dart`
///    的表头：Tabler 里表达同一个意思的图标往往有好几个，各页面各挑一个，
///    就会出现「结算页的再练一组」和「听音辨义的再试一次」用两个不同箭头
///    这种谁都没写错、但看着就是两套界面的情况。
///
void main() {
  // 这一条测试扫描 lib 目录下的全部 Dart 源码。
  test('all interface icons use Tabler instead of built-in or text icons', () {
    // Directory('lib') 是项目的源码根目录。
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

  // 这一条守着「页面只读语义名」：AppGlyph 是 Tabler 的唯一入口。
  test(
    'interface code names icons by meaning via AppGlyph, not TablerIcons',
    () {
      // 唯一允许直接点名 Tabler 图标的文件：语义表本身。
      const glyphCatalog = 'lib/common/design/glyphs.dart';
      // 违规先攒起来，最后连文件带行号一次性报出，省得改一处跑一遍。
      final violations = <String>[];
      // 只认「TablerIcons.」这个前缀；注释里提到 Tabler 这个词不算。
      final rawIconPattern = RegExp(r'\bTablerIcons\s*\.');

      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        // 统一成正斜杠，Windows 上跑测试时路径才对得上。
        final relativePath = file.path.replaceAll(r'\', '/');
        if (relativePath == glyphCatalog) continue;

        final lines = file.readAsStringSync().split('\n');
        // 逐行去掉双斜线之后的内容：注释里举例说明「原来写的是 TablerIcons.refresh」
        // 是说明文字，不该算违规。
        for (var index = 0; index < lines.length; index += 1) {
          final code = lines[index].split('//').first;
          if (!rawIconPattern.hasMatch(code)) continue;
          violations.add('  $relativePath:${index + 1}  ${code.trim()}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '发现 ${violations.length} 处直接点名 Tabler 图标的写法，'
            '请改用 lib/common/design/glyphs.dart 里的 AppGlyph 语义名'
            '（表里没有的图标，先在表里起一个名字）：\n${violations.join('\n')}',
      );
    },
  );
}
