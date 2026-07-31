///
/// 将完整日期时间格式化为首页标题等位置可复用的中文格式。
///
/// 输出 `yyyy年MM月dd日 HH:mm:ss`，对应 PHP 的 `date('Y年m月d日 H:i:s')`。
///
/// @param  DateTime  dateTime
/// @return String
///
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
  // 字符串插值对应 PHP 双引号字符串内嵌变量。
  return '$year年$month月$day日 $hour:$minute:$second';
}

///
/// 将单词日期格式化为紧凑列表日期，作用类似 PHP 项目里的日期 helper 函数。
///
/// 今年显示 `MM.dd`，其他年份显示 `yyyy.MM.dd`；列表日期不包含秒，所以无需定时更新。
///
/// @param  DateTime  date
/// @param  DateTime  now
/// @return String
///
String formatWordDate(DateTime date, DateTime now) {
  // toLocal 把数据转换为设备本地时间，类似 PHP 先设置并使用当前时区。
  final localDate = date.toLocal();
  // 当前时间也转换为同一时区，避免一个 UTC、一个本地时间导致年份比较错误。
  final localNow = now.toLocal();
  // 月份不足两位时左侧补 0，对应 PHP date('m')。
  final month = localDate.month.toString().padLeft(2, '0');
  // 日期不足两位时左侧补 0，对应 PHP date('d')。
  final day = localDate.day.toString().padLeft(2, '0');

  // 只比较本地年份，不用相差多少小时推算，避免时区边界问题。
  if (localDate.year == localNow.year) {
    // `$month` 是 Dart 字符串插值，对应 PHP 双引号字符串内嵌变量。
    return '$month.$day';
  }
  // `${表达式}` 用于插入属性或计算结果；非今年时把四位年份放在最前面。
  return '${localDate.year}.$month.$day';
}
