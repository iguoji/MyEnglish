import 'package:my_english/store/syllable.dart';

/// 内存版音节划分存储，仅用于测试和命令行自测，不落盘。
///
/// 本质上就是一个进程内的全局 Map；App 正式版使用 [LocalSyllableStore]
/// 走 Android 原生 SQLite，服务层代码一行都不用改。
class InMemorySyllableStore implements SyllableStore {
  final Map<String, SyllableRow> _m = {};

  @override
  Future<SyllableRow?> getDivision(String word) async => _m[word];

  @override
  Future<void> saveDivision(
    String word,
    List<String> parts,
    String source,
  ) async {
    // 复制一份，避免外部后续修改数组影响到已存结果。
    _m[word] = SyllableRow(List<String>.from(parts), source);
  }
}
