///
/// 将完整日期时间格式化为首页标题等位置可复用的中文格式。
///
/// 输出格式固定为 `yyyy年MM月dd日 HH:mm:ss`。
String formatFullDateTime(DateTime dateTime) {
  // 转为设备本地时间，确保真机显示用户所在时区。
  final localDateTime = dateTime.toLocal();
  // 年份直接使用四位数字。
  final year = localDateTime.year.toString();
  // 月份不足两位时在左侧补 0。
  final month = localDateTime.month.toString().padLeft(2, '0');
  // 日期同样固定为两位。
  final day = localDateTime.day.toString().padLeft(2, '0');
  // 小时使用 24 小时制并固定为两位。
  final hour = localDateTime.hour.toString().padLeft(2, '0');
  // 分钟固定为两位。
  final minute = localDateTime.minute.toString().padLeft(2, '0');
  // 秒固定为两位。
  final second = localDateTime.second.toString().padLeft(2, '0');
  return '$year年$month月$day日 $hour:$minute:$second';
}

///
/// 将单词日期格式化为紧凑列表日期。
///
/// 今年显示 `MM.dd`，其他年份显示 `yyyy.MM.dd`；列表日期不包含秒，所以无需定时更新。
String formatWordDate(DateTime date, DateTime now) {
  // 转为设备本地时间，确保按用户所在时区显示。
  final localDate = date.toLocal();
  // 当前时间也转换为同一时区，避免一个 UTC、一个本地时间导致年份比较错误。
  final localNow = now.toLocal();
  // 月份不足两位时左侧补 0。
  final month = localDate.month.toString().padLeft(2, '0');
  // 日期不足两位时左侧补 0。
  final day = localDate.day.toString().padLeft(2, '0');

  // 只比较本地年份，不用相差多少小时推算，避免时区边界问题。
  if (localDate.year == localNow.year) {
    return '$month.$day';
  }
  // `${表达式}` 用于插入属性或计算结果；非今年时把四位年份放在最前面。
  return '${localDate.year}.$month.$day';
}

///
/// 把日期格式化成数据库使用的 `yyyy-MM-dd` 键。
///
/// 全项目的「今天」都由这一个函数算出来再传给原生，不让 Kotlin 自己取
/// `now()`——两边对「今天从几点开始」的理解永远一致，测试也能注入固定日期。
String dateKey(DateTime date) {
  // 转为设备本地时间，确保跨时区时的「今天」以用户所在地为准。
  final local = date.toLocal();
  // 不足两位时左侧补 0，保证字符串排序等价于日期排序。
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${twoDigits(local.month)}-${twoDigits(local.day)}';
}

///
/// 今天的 `yyyy-MM-dd`。
String todayKey() => dateKey(DateTime.now());

///
/// 把秒数格式化成统一的计时文字。
///
/// 不足 1 小时用 `mm:ss`（如 `12:03`），满 1 小时改用 `hh:mm:ss`
/// （如 `01:02:03`），这样右上角计时器既能保持两位补零，超过一小时也不会溢出。
///
/// 听音辨义、看义选词、拼写强化、词义连连四个模块的右上角计时共用这一个函数，
/// 保证全局口径一致、只改一处即可全局生效。
String formatTimerSeconds(int totalSeconds) {
  // 秒数不可能为负；为极端情况兜底成 0，避免出现负数冒号。
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  // 先把总秒数拆成 时/分/秒 三段。
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  // 不足两位时左补 0，让每个字段始终占两位，视觉上不随数字变化抖动宽度。
  String two(int n) => n.toString().padLeft(2, '0');
  // 满 1 小时才带小时段；否则只显示分钟和秒，保持右上角不拥挤。
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}
