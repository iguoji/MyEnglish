/// 单词分组数据模型；未来落地 SQLite group 表和其他页面时可以直接复用。
class WordGroup {
  /// 创建分组；id 与 name 都是必填字段。
  const WordGroup({required this.id, required this.name});

  /// 分组主键；本轮由内存 GroupStore 自增生成，未来对应 SQLite 自增主键。
  final int id;

  /// 分组名称；允许用户在分组管理面板中随时修改。
  final String name;

  /// 返回替换名称后的新对象，模型本身保持不可变。
  WordGroup copyWith({String? name}) {
    // 未提供新名称时沿用当前值，写法类似 PHP 的 $name ?? $this->name。
    return WordGroup(id: id, name: name ?? this.name);
  }
}
