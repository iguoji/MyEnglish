///
/// 读取可空整数。
///
/// JSON 数字和 MethodChannel 返回的整型都实现 [num]。其他类型视为数据源
/// 格式错误，不进行字符串到数字的隐式转换。
int? readOptionalInt(Object? value, String fieldName) {
  // 数据库没有值时继续返回 null，交由调用方决定是否有默认值。
  if (value == null) return null;
  // JSON 数字和原生 Long 都属于 num，统一收窄为 Dart int。
  if (value is num) return value.toInt();

  // 不接受字符串数字，避免上游数据格式错误被静默掩盖。
  throw FormatException('$fieldName 必须是数字，实际值为：$value');
}

///
/// 读取整数列表。
///
/// 缺失字段返回空列表；列表中的非数字元素会携带字段名抛出格式异常。
List<int> readIntList(Object? value, String fieldName) {
  // 缺失字段视为空列表，调用方无需额外判空。
  if (value == null) return const <int>[];
  // 容器必须是数组结构，普通字符串或对象不能参与后续遍历。
  if (value is! List) throw FormatException('$fieldName 必须是数组');

  // 逐项转换为 int，同时执行严格类型校验。
  return <int>[
    for (final item in value)
      if (item is num)
        // 原生 Long、JSON int 和 JSON double 统一转换成 Dart int。
        item.toInt()
      else
        // 任一元素不合法就终止解析，避免返回一份不完整的数据。
        throw FormatException('$fieldName 的元素必须是数字，实际为：$item'),
  ];
}

///
/// 读取可空日期。
///
/// SQLite 毫秒/秒时间戳、数字文本、`yyyy-MM-dd` 和 ISO 8601 均可解析。
DateTime? readOptionalDate(Object? value, String fieldName) {
  // 空值和数据库的 0 都表示没有日期，模型中不制造 1970 年。
  if (value == null) return null;
  if (value is num) {
    final timestamp = value.toInt();
    if (timestamp == 0) return null;
    // 10 位左右的值视为秒级，13 位左右的值视为毫秒级。
    final milliseconds = timestamp.abs() < 100000000000
        ? timestamp * 1000
        : timestamp;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  // 导入文件可能使用数字文本或 ISO 日期文本，需要按顺序尝试两种格式。
  if (value is String) {
    // 先清理用户编辑 JSON 时可能留下的首尾空格。
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) return null;
    // 纯数字文本复用上方秒/毫秒识别规则。
    final timestamp = int.tryParse(normalizedValue);
    if (timestamp != null) return readOptionalDate(timestamp, fieldName);

    // 非数字文本再交给 Dart 标准 ISO 8601 解析器。
    final parsedDate = DateTime.tryParse(normalizedValue);
    if (parsedDate != null) return parsedDate;
  }

  // 用户约定错误日期按空日期处理，原生导入会将其落库为 0。
  return null;
}

///
/// 读取整数，字段缺失或类型错误时回退到调用方提供的默认值。
///
/// 与 [readOptionalInt] 的区别：这里不抛异常，适用于页面进度快照这类
/// "允许坏数据、按默认值继续运行"的场景，而不是数据库字段那种必须校验的场景。
int readIntOrFallback(Object? value, {required int fallback}) {
  return value is num ? value.toInt() : fallback;
}

///
/// 把 JSON / MethodChannel 的动态值收窄为字符串数组。
///
/// 缺失字段按空数组处理；数组里出现 null 会带上字段名抛出格式异常，
/// 避免把一个空值静默转成 "null" 这样的假释义。
List<String> readStringList(Object? value, String fieldName) {
  // 缺失字段视为空数组，调用方无需额外判空。
  if (value == null) return const <String>[];
  // 容器必须是数组结构，普通字符串或对象不能参与后续遍历。
  if (value is! List) throw FormatException('$fieldName 必须是数组');
  return List<String>.unmodifiable(
    value.map((item) {
      if (item == null) throw FormatException('$fieldName 不能包含 null');
      // 原始字符串直接保留，其他 JSON 标量使用明确文本表示。
      return item.toString();
    }),
  );
}
