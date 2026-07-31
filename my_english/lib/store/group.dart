// foundation.dart 提供 ChangeNotifier，让页面像监听小程序全局 data 一样监听分组。
import 'package:flutter/foundation.dart';
// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SQLite 的分组表。
import 'package:flutter/services.dart';

// 分组模型位于全局 models 目录，任何页面都可以复用。
import '../models/group.dart';
import '../models/model_value_parser.dart';

///
/// 分组 Store：分组列表与顺序持久化在 Android 原生 SQLite 的 group 表。
///
/// 每个分组的内存副本都由原生 group 表支撑，App 重启后通过 [load] 重新加载，
/// 因此 group_id 引用在全生命周期内保持稳定，单词的 groupMember 关系不会错乱。
///
class GroupStore extends ChangeNotifier {
  ///
  /// 允许测试注入原生通道；正式 App 使用默认值。
  ///
  /// @param  MethodChannel?  channel 测试专用通道；为空时使用正式通道。
  ///
  GroupStore({MethodChannel? channel})
    // 没有注入通道时使用 Android MainActivity 注册的固定名称。
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用同一个实例。
  ///
  /// @var GroupStore
  ///
  static final GroupStore instance = GroupStore();

  ///
  /// 通道名必须与 Android MainActivity 完全一致。
  ///
  /// @var MethodChannel
  ///
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 分组读写走的原生通道。
  ///
  /// @var MethodChannel
  ///
  final MethodChannel _channel;

  ///
  /// 内置"未分组"的虚拟 id；Word.groupIds 为空时归入这里。
  ///
  /// @var int
  ///
  static const int ungroupedId = 0;

  ///
  /// 内置"未分组"的固定显示名称。
  ///
  /// @var String
  ///
  static const String ungroupedName = '未分组';

  ///
  /// 当前全部自定义分组，列表顺序就是界面显示顺序（与 sort_order 一致）。
  ///
  /// @var `List<WordGroup>`
  ///
  final List<WordGroup> _groups = <WordGroup>[];

  ///
  /// 下一个分组主键，作用类似内存版 AUTO_INCREMENT。
  ///
  /// @var int
  ///
  int _nextId = 1;

  ///
  /// 页面只读访问分组列表；返回不可变视图防止外部绕过 Store 修改。
  ///
  /// @return `List<WordGroup>` 当前分组的不可变视图。
  ///
  List<WordGroup> get groups => List<WordGroup>.unmodifiable(_groups);

  ///
  /// 按 id 查找分组；找不到（含 null 和虚拟"未分组"）时返回 null。
  ///
  /// @param  int?  id 需要查找的分组主键。
  /// @return WordGroup? 匹配的分组；不存在时返回 null。
  ///
  WordGroup? byId(int? id) {
    // 逐个比对主键，列表很小所以线性查找足够。
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    // 没有命中任何自定义分组。
    return null;
  }

  ///
  /// 启动时从原生 group 表加载全部未删除分组，并复位内存自增主键。
  ///
  /// @return `Future<void>` 原生读取和内存状态刷新完成后的异步结果。
  ///
  Future<void> load() async {
    // 读取分组列表；原生 null 属于接口错误，但容错为不加载。
    final rawGroups = await _channel.invokeListMethod<Object?>('getAllGroups');
    // 没有返回时不改动内存，避免空数据清空已有分组。
    if (rawGroups == null) return;
    // 临时收集解析结果。
    final loaded = <WordGroup>[];
    // 记录最大主键，用于复位 _nextId。
    var maxId = 0;
    for (final rawGroup in rawGroups) {
      // 每个元素必须是 Map 结构。
      if (rawGroup is! Map) continue;
      // Map.from 收窄动态键值类型。
      final map = Map<Object?, Object?>.from(rawGroup);
      // 主键与名称必填。
      final id = readOptionalInt(map['id'], 'Group.id') ?? 0;
      final name = map['name']?.toString() ?? '未命名';
      // 排序值缺省 0。
      final sortOrder =
          readOptionalInt(map['sort_order'], 'Group.sort_order') ?? 0;
      // 组装并追加。
      loaded.add(WordGroup(id: id, name: name, sortOrder: sortOrder));
      // 更新最大主键。
      if (id > maxId) maxId = id;
    }
    // 用加载结果替换内存列表。
    _groups
      ..clear()
      ..addAll(loaded);
    // 下一个自增主键接着最大 id。
    _nextId = maxId + 1;
    // 通知分组管理面板和首页刷新。
    notifyListeners();
  }

  ///
  /// 新建分组并写入原生；名称自动使用"新分组 N"。
  ///
  /// @return `Future<void>` 原生写入和界面通知完成后的异步结果。
  ///
  Future<void> add() async {
    // 用当前自增值同时生成主键和默认名称。
    final next = _nextId;
    final name = '新分组 $next';
    // 写入原生并返回自增主键。
    final id = await _channel.invokeMethod<int>(
      'createGroup',
      <String, Object?>{'name': name, 'sortOrder': _groups.length},
    );
    // 追加到列表末尾；优先使用原生返回的真实主键。
    _groups.add(
      WordGroup(id: id ?? next, name: name, sortOrder: _groups.length),
    );
    // 主键消耗后向前推进。
    _nextId += 1;
    // 通知界面刷新。
    notifyListeners();
  }

  ///
  /// 重命名指定分组；名称原样保存，是否为空由界面自行约束。
  ///
  /// @param  int  id 目标分组主键。
  /// @param  String  name 需要保存的新名称。
  /// @return `Future<void>` 原生写入和内存刷新完成后的异步结果。
  ///
  Future<void> rename(int id, String name) async {
    // 先写入原生，保证持久化。
    await _channel.invokeMethod<void>('renameGroup', <String, Object?>{
      'id': id,
      'name': name,
    });
    // 找到目标位置。
    final index = _groups.indexWhere((group) => group.id == id);
    // 目标不存在时静默忽略，避免竞态点击造成异常。
    if (index < 0) return;
    // 用新名称替换旧对象。
    _groups[index] = _groups[index].copyWith(name: name);
    // 通知界面刷新。
    notifyListeners();
  }

  ///
  /// 上移一个位置；已在顶部时忽略。
  ///
  /// @param  int  id 需要上移的分组主键。
  /// @return `Future<void>` 排序持久化完成后的异步结果。
  ///
  Future<void> moveUp(int id) async {
    // 定位目标下标。
    final index = _groups.indexWhere((group) => group.id == id);
    // 不存在或已是第一个时不动。
    if (index <= 0) return;
    // 与上一项交换，写法对应 PHP 中借助临时变量交换数组元素。
    final previous = _groups[index - 1];
    _groups[index - 1] = _groups[index];
    _groups[index] = previous;
    // 把新的列表顺序写回原生。
    await _persistOrder();
    // 通知界面刷新顺序。
    notifyListeners();
  }

  ///
  /// 下移一个位置；已在底部时忽略。
  ///
  /// @param  int  id 需要下移的分组主键。
  /// @return `Future<void>` 排序持久化完成后的异步结果。
  ///
  Future<void> moveDown(int id) async {
    // 定位目标下标。
    final index = _groups.indexWhere((group) => group.id == id);
    // 不存在或已是最后一个时不动。
    if (index < 0 || index >= _groups.length - 1) return;
    // 与下一项交换。
    final next = _groups[index + 1];
    _groups[index + 1] = _groups[index];
    _groups[index] = next;
    // 把新的列表顺序写回原生。
    await _persistOrder();
    // 通知界面刷新顺序。
    notifyListeners();
  }

  ///
  /// 删除分组；原生会同时清理其全部成员关联。
  ///
  /// @param  int  id 需要删除的分组主键。
  /// @return `Future<void>` 原生删除和内存刷新完成后的异步结果。
  ///
  Future<void> remove(int id) async {
    // 先删除原生记录，SQLite 外键会级联清理全部成员关联。
    await _channel.invokeMethod<void>('deleteGroup', <String, Object?>{
      'id': id,
    });
    // 过滤掉目标分组。
    _groups.removeWhere((group) => group.id == id);
    // 确实删除时才通知，避免无意义重建。
    notifyListeners();
  }

  ///
  /// 把当前列表顺序逐个写回原生 group 表的 sort_order。
  ///
  /// @return `Future<void>` 全部分组排序写入完成后的异步结果。
  ///
  Future<void> _persistOrder() async {
    // 列表下标即排序值；顺序遍历保证稳定。
    for (var index = 0; index < _groups.length; index += 1) {
      await _channel.invokeMethod<void>('setGroupOrder', <String, Object?>{
        'id': _groups[index].id,
        'sortOrder': index,
      });
    }
  }

  ///
  /// 清空全部自定义分组内存；原生四表由 WordStore.clearAll 负责。
  ///
  /// 清空数据入口会先调 WordStore.clearAll（清 group 表），这里只保证
  /// 本次会话立刻回到初始状态。
  ///
  /// @return void
  ///
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
