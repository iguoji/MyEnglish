/// 单词分组数据模型；对应 README 的 group 表，可由 SQLite 持久化。
class WordGroup {
  /// 创建分组；id 与 name 必填，sortOrder 决定显示顺序（缺省 0）。
  const WordGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
  });

  /// 分组主键；对应 SQLite group 表自增 id。
  final int id;

  /// 分组名称；允许用户在分组管理面板中随时修改。
  final String name;

  /// 显示排序值；数值越小越靠前，由 GroupStore 在移动分组时维护。
  final int sortOrder;

  /// 返回替换名称或顺序后的新对象，模型本身保持不可变。
  WordGroup copyWith({String? name, int? sortOrder}) {
    // 未提供的字段沿用当前值，写法类似 PHP 的 $val ?? $this->val。
    return WordGroup(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
