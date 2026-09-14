/// 四种自测共用选词范围。页面禁用按钮，开局服务再次核对，避免入口各有一套规则。
abstract final class SelfTestPolicy {
  static const int minWords = 5;
  static const int maxWords = 100;
  static const String rangeLabel = '$minWords–$maxWords 个单词';

  static bool accepts(int count) => count >= minWords && count <= maxWords;

  static String? unavailableReason(int count) {
    if (count == 0) return '请先勾选 $rangeLabel';
    if (count < minWords) return '已选 $count 个，还需选择 ${minWords - count} 个';
    if (count > maxWords) return '已选 $count 个，最多可选 $maxWords 个';
    return null;
  }
}
