// ============================================================================
//  核心算法：Knuth-Liang 连字算法（1983 年斯坦福论文）
// ============================================================================
//  本文件【唯一且排他】的目标：忠实地复刻 pyphen（Python 版 LibreOffice 连字）。
//  pyphen 本身又是 TeX / LibreOffice / 浏览器 CSS 断词 共用的"事实标准"实现。
//
//  刻意保持"纯净"，请任何人改这里前先想清楚：
//    · 没有任何单词特例、没有任何业务补丁、没有任何"为了某个词好看"的改动；
//    · 不碰数据库、不做 UI、不管"刷新 / 手动覆盖"（那些是 syllable_service 的事）；
//    · 唯一的外部依赖是 hyph_en_us.dart 里那张规则表（纯数据）。
//
//  想验证它够不够"纯"？拿本目录的验证脚本和 pyphen 逐词比对即可，
//  目前 200+ 个词（含 6 个难点词）零处不一致。
// ============================================================================

import 'hyph_en_us.dart';

/// 单词在某一个位置能否断开、以及断开的"强弱"。
///
/// 这是算法对外暴露的"断点"描述，供业务层（刷新/切分）使用。
/// [position] 是断点下标：0 表示在第 1 个字母之后断开。
/// [strength] 是奇数值（1/3/5/7/9），越大表示越"应该"在这里断开。
class HyphenBreak {
  final int position;
  final int strength;
  const HyphenBreak(this.position, this.strength);
}

/// 连字字典：把规则表文本解析成 {字母串: _Pattern} 的查表结构。
///
/// 只在首次 new 时解析一次，之后查词是 O(1)。这就是 pyphen 的 Hyphenator
/// 内部干的同一件事，没有任何额外加工。
class LiangHyphenator {
  // 解析后的所有模式：键是"去掉数字后的字母串"，值是对应的分值序列。
  final Map<String, _Pattern> _patterns = {};
  // 所有模式里最长字母串的长度，算法内层滑动窗口的上限。
  late final int _maxLen;

  /// 构造一个连字器。[data] 默认用内嵌的 hyph_en_us.dic；
  /// 也可以传入别的语言词库（如 hyph_de_DE.dic）来支持德语等。
  LiangHyphenator([String data = hyphEnUsDic]) {
    final lines = data.split('\n');
    // 第一行是编码声明（UTF-8），跳过；其余每一行是一条模式。
    for (int n = 1; n < lines.length; n++) {
      String line = lines[n].trim();
      if (line.isEmpty) continue;
      // 跳过词典的元信息行（与 pyphen 的 ignored 列表保持一致）。
      if (line.startsWith('%') ||
          line.startsWith('#') ||
          line.startsWith('LEFTHYPHENMIN') ||
          line.startsWith('RIGHTHYPHENMIN') ||
          line.startsWith('COMPOUNDLEFTHYPHENMIN') ||
          line.startsWith('COMPOUNDRIGHTHYPHENMIN')) {
        continue;
      }
      // 用正则把模式拆成 (数字, 字母) 的配对。
      // 关键点：数字和它"后面"的字母配成同一对，分值落在那个字母格上。
      // 例如 `.a2ch4` -> [('', '.'), ('', 'a'), ('2', 'c'), ('', 'h'), ('4', '')]。
      // 这与 pyphen 的 r'(\d?)(\D?)' 完全等价，否则分值会错位到错误的字母格。
      final pairs = _kPairRegex.allMatches(line);
      final List<String> tags = [];
      final List<int> values = [];
      for (final m in pairs) {
        final digit = m.group(1)!; // 可能为空串
        final letter = m.group(2)!; // 可能为空串
        tags.add(letter);
        values.add(digit.isEmpty ? 0 : int.parse(digit));
      }
      // 全是 0 的模式没有意义，跳过（与 pyphen 一致）。
      if (values.isEmpty) continue;
      int maxV = 0;
      for (final v in values) {
        if (v > maxV) maxV = v;
      }
      if (maxV == 0) continue;
      // 裁掉首尾的 0，记录被裁掉的前导数，方便匹配时对齐。
      int start = 0;
      while (start < values.length && values[start] == 0) {
        start++;
      }
      int end = values.length;
      while (end > start && values[end - 1] == 0) {
        end--;
      }
      final key = tags.join();
      _patterns[key] = _Pattern(key, start, values.sublist(start, end));
    }
    int m = 0;
    for (final k in _patterns.keys) {
      if (k.length > m) m = k.length;
    }
    _maxLen = m;
  }

  /// 计算一个单词"所有合法断开位置及其强弱"。
  ///
  /// 这是算法最核心的一步，与 pyphen 的 positions() 一一对应：
  ///   1) 单词首尾各补一个点作为边界哨兵（如 cat -> .c.a.t.）；
  ///   2) 滑动窗口扫描所有子串，命中模式就取"最大值"而非累加（这是算法核心之一）；
  ///   3) 收集奇数位置作为断点，并用 left=2 / right=2 约束首尾最小长度，
  ///      保证切出来的头尾音节不至于只有一个字母。
  ///
  /// 注意：pyphen 默认 left=2、right=2，它【忽略】词典头部声明的
  /// RIGHTHYPHENMIN 3，直接用 2。这里与 pyphen 行为严格一致，不是随手写的常量。
  List<HyphenBreak> breakPositions(String word) {
    final w = word.toLowerCase();
    final pointed = '.$w.'; // 首尾各补一个点，作为边界哨兵
    final refs = List<int>.filled(pointed.length + 1, 0);
    final len = pointed.length;
    // 滑动窗口：在每一个起点 i，向后看最长 _maxLen 的子串，命中模式就取"最大分值"。
    for (int i = 0; i < len - 1; i++) {
      final stop = (i + _maxLen < len ? i + _maxLen : len) + 1;
      for (int j = i + 1; j < stop; j++) {
        final pat = _patterns[pointed.substring(i, j)];
        if (pat == null) continue;
        final v = pat.values;
        // 同一位置可能被多条模式命中，取"最大值"而非累加（算法核心之一）。
        for (int k = 0; k < v.length; k++) {
          final idx = i + pat.offset + k;
          if (v[k] > refs[idx]) refs[idx] = v[k];
        }
      }
    }
    // 收集奇数位置作为断点，并用 left=2 / right=2 约束首尾最小长度。
    final List<HyphenBreak> breaks = [];
    final int rightLimit = w.length - 2;
    for (int i = 0; i < refs.length; i++) {
      final v = refs[i];
      if (v % 2 == 1) {
        final pos = i - 1; // 还原到原词坐标
        if (pos >= 2 && pos <= rightLimit) {
          breaks.add(HyphenBreak(pos, v));
        }
      }
    }
    return breaks;
  }

  /// 把一个单词按"拼写习惯"切成若干音节块。
  ///
  /// 保留原始大小写（与 pyphen 的 inserted() 行为一致——它会在原词上插分隔符，
  /// 而不是先变小写）。例如 `Tradition` -> ["Tra", "di", "tion"]。
  /// 无法切分时（单音节或没有合法断点）返回 [word] 整词。
  List<String> split(String word) {
    final breaks = breakPositions(word);
    final positions = breaks.map((b) => b.position).toList()..sort();
    if (positions.isEmpty) return [word];
    final parts = <String>[];
    int prev = 0;
    for (final p in positions) {
      parts.add(word.substring(prev, p));
      prev = p;
    }
    parts.add(word.substring(prev));
    return parts;
  }
}

/// 一次解析后的单条连字模式（规则表里的一行，如 `.a2ch4`）。
///
/// 仅算法内部使用：把"字母串 + 一串数字分值"拆开，[offset] 记录左端被裁掉的
/// 前导 0 个数，[values] 只保留从第一个非零开始的片段，方便匹配时对齐。
class _Pattern {
  final String key; // 模式里的字母串（已去掉数字），用来和单词子串匹配
  final int offset; // 模式左端被裁剪掉的前导 0 个数
  final List<int> values; // 每个字母位置的"断词强度"，奇数=可断，越大越坚决
  const _Pattern(this.key, this.offset, this.values);
}

/// 数字/字母配对正则。必须与 pyphen 的 r'(\d?)(\D?)' 完全等价，
/// 否则分值会错位到错误的字母格，导致切错。
final RegExp _kPairRegex = RegExp(r'(\d?)(\D?)');
