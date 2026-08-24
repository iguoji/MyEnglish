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
