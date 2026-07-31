///
/// 单词分组数据模型；对应 README 的 group 表，可由 SQLite 持久化。
///
/// @property int id SQLite 自增主键。
/// @property String name 用户可见的分组名称。
/// @property int sortOrder 界面显示顺序。
///
class WordGroup {
  ///
  /// 创建分组；id 与 name 必填，sortOrder 决定显示顺序（缺省 0）。
  ///
  /// @param  int  id SQLite 自增主键。
  /// @param  String  name 用户可见的分组名称。
  /// @param  int  sortOrder 界面显示顺序。
  ///
  const WordGroup({required this.id, required this.name, this.sortOrder = 0});

  ///
  /// 分组主键；对应 SQLite group 表自增 id。
  ///
  /// @var int
  ///
  final int id;

  ///
  /// 分组名称；允许用户在分组管理面板中随时修改。
  ///
  /// @var String
  ///
  final String name;

  ///
  /// 显示排序值；数值越小越靠前，由 GroupStore 在移动分组时维护。
  ///
  /// @var int
  ///
  final int sortOrder;

  ///
  /// 返回替换名称或顺序后的新对象，模型本身保持不可变。
  ///
  /// @param  String?  name 新分组名称；为空时沿用当前名称。
  /// @param  int?  sortOrder 新排序值；为空时沿用当前排序。
  /// @return WordGroup 替换指定字段后的新模型。
  ///
  WordGroup copyWith({String? name, int? sortOrder}) {
    // copyWith 类似 Laravel 模型复制后 fill，只覆盖调用方明确传入的字段。
    return WordGroup(
      // 主键代表同一条数据库记录，复制时始终保持不变。
      id: id,
      // null 表示调用方没有要求修改名称。
      name: name ?? this.name,
      // null 表示调用方没有要求修改排序值。
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
