// foundation.dart 提供 ChangeNotifier，让页面像监听小程序全局 data 一样监听分组。
import 'package:flutter/foundation.dart';

// 分组模型位于全局 models 目录，任何页面都可以复用。
import '../models/group.dart';

/// 分组 Store：本轮按约定使用纯内存实现，App 重启后回到初始状态。
///
/// README 中的 SQLite group 表尚未落地，因此没有分组的单词一律归入内置"未分组"；
/// 未来切换到持久化实现时，页面代码无需改动，只替换本 Store 内部即可。
class GroupStore extends ChangeNotifier {
  /// 初始没有任何自定义分组，首页只显示内置"未分组"。
  GroupStore();

  /// 内置"未分组"的虚拟 id；Word.groupId 为 null 时归入这里。
  static const int ungroupedId = 0;

  /// 内置"未分组"的固定显示名称。
  static const String ungroupedName = '未分组';

  /// 当前全部自定义分组，列表顺序就是界面显示顺序。
  final List<WordGroup> _groups = <WordGroup>[];

  /// 下一个分组主键，作用类似内存版 AUTO_INCREMENT。
  int _nextId = 1;

  /// 页面只读访问分组列表；返回不可变视图防止外部绕过 Store 修改。
  List<WordGroup> get groups => List<WordGroup>.unmodifiable(_groups);

  /// 按 id 查找分组；找不到（含 null 和虚拟"未分组"）时返回 null。
  WordGroup? byId(int? id) {
    // 逐个比对主键，列表很小所以线性查找足够。
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    // 没有命中任何自定义分组。
    return null;
  }

  /// 新建分组并返回它；名称自动使用"新分组 N"。
  WordGroup add() {
    // 用当前自增值同时生成主键和默认名称。
    final group = WordGroup(id: _nextId, name: '新分组 $_nextId');
    // 主键消耗后向前推进。
    _nextId += 1;
    // 新分组追加到列表末尾。
    _groups.add(group);
    // 通知分组管理面板和首页刷新。
    notifyListeners();
    // 返回给调用方，便于表单等场景立即选中。
    return group;
  }

  /// 重命名指定分组；名称原样保存，是否为空由界面自行约束。
  void rename(int id, String name) {
    // 找到目标位置。
    final index = _groups.indexWhere((group) => group.id == id);
    // 目标不存在时静默忽略，避免竞态点击造成异常。
    if (index < 0) return;
    // 用新名称替换旧对象。
    _groups[index] = _groups[index].copyWith(name: name);
    // 通知界面刷新。
    notifyListeners();
  }

  /// 上移一个位置；已在顶部时忽略。
  void moveUp(int id) {
    // 定位目标下标。
    final index = _groups.indexWhere((group) => group.id == id);
    // 不存在或已是第一个时不动。
    if (index <= 0) return;
    // 与上一项交换，写法对应 PHP 中借助临时变量交换数组元素。
    final previous = _groups[index - 1];
    _groups[index - 1] = _groups[index];
    _groups[index] = previous;
    // 通知界面刷新顺序。
    notifyListeners();
  }

  /// 下移一个位置；已在底部时忽略。
  void moveDown(int id) {
    // 定位目标下标。
    final index = _groups.indexWhere((group) => group.id == id);
    // 不存在或已是最后一个时不动。
    if (index < 0 || index >= _groups.length - 1) return;
    // 与下一项交换。
    final next = _groups[index + 1];
    _groups[index + 1] = _groups[index];
    _groups[index] = next;
    // 通知界面刷新顺序。
    notifyListeners();
  }

  /// 删除分组；其中单词由页面负责移回"未分组"。
  void remove(int id) {
    // 记录删除前数量，便于判断是否真的删掉了。
    final before = _groups.length;
    // 过滤掉目标分组。
    _groups.removeWhere((group) => group.id == id);
    // 确实删除时才通知，避免无意义重建。
    if (_groups.length != before) notifyListeners();
  }

  /// 清空全部自定义分组并重置自增主键，对应首页「清空数据」入口。
  ///
  /// 分组当前为纯内存实现（App 重启本就会重置），这里只保证本次会话立刻回到初始状态。
  void clear() {
    // 列表为空则无需任何动作。
    if (_groups.isEmpty) return;
    // 移除所有自定义分组。
    _groups.clear();
    // 自增主键回到 1，下一次 add 仍是「新分组 1」。
    _nextId = 1;
    // 通知分组管理面板与首页刷新。
    notifyListeners();
  }
}
