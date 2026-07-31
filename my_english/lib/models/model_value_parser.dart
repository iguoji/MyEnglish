/// 读取可空整数。
///
/// JSON 数字和 MethodChannel 返回的整型都实现 [num]。其他类型视为数据源
/// 格式错误，不进行字符串到数字的隐式转换。
int? readOptionalInt(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is num) return value.toInt();

  throw FormatException('$fieldName 必须是数字，实际值为：$value');
}

/// 读取整数列表。
///
/// 缺失字段返回空列表；列表中的非数字元素会携带字段名抛出格式异常。
List<int> readIntList(Object? value, String fieldName) {
  if (value == null) return const <int>[];
  if (value is! List) throw FormatException('$fieldName 必须是数组');

  return <int>[
    for (final item in value)
      if (item is num)
        item.toInt()
      else
        throw FormatException('$fieldName 的元素必须是数字，实际为：$item'),
  ];
}

/// 读取可空日期。
///
/// SQLite 毫秒时间戳、数字文本、`yyyy-MM-dd` 和完整 ISO 8601 文本均可解析。
DateTime? readOptionalDate(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());

  if (value is String) {
    final normalizedValue = value.trim();
    final milliseconds = int.tryParse(normalizedValue);
    if (milliseconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }

    final parsedDate = DateTime.tryParse(normalizedValue);
    if (parsedDate != null) return parsedDate;
  }

  throw FormatException('$fieldName 不是有效日期，实际值为：$value');
}
