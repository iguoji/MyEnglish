// dart:async 提供 Timer 和 unawaited，分别用于搜索防抖和触发异步任务。
import 'dart:async';

// material.dart 提供页面、布局、加载指示器和按钮等 Flutter UI 组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供分组头的勾选和折叠方向图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入公共主题与设计令牌。
import '../../common/theme.dart';
// 日期 helper 负责列表与分组标题的日期格式。
import '../../common/date.dart';
// Word 是全应用共享模型，不属于首页私有文件。
import '../../models/word.dart';
// 音频服务由首页、随身听和默写共同复用。
import '../../services/word_audio.dart';
// 新版原型中的全屏默写页。
import '../dictation/dictation_page.dart';
// 新版原型中的全屏随身听页。
import '../listening/listening_page.dart';
// 分组 Store 提供自定义分组数据（本轮为内存实现）。
import '../../store/group.dart';
// 设置 Store 提供持久化口音、主题与每日复习目标。
import '../../store/settings.dart';
// 单词 Store 同样放在页面目录之外，其他页面可以直接复用。
import '../../store/word.dart';
// 分组行：模式切换、筛选 chips 与分组管理入口。
import 'widgets/group_filter_bar.dart';
// 右侧抽屉菜单。
import 'widgets/home_drawer.dart';
// 顶部问候与汉堡按钮。
import 'widgets/home_header.dart';
// 右下角可展开的新版学习入口。
import 'widgets/learning_fab.dart';
// 分组管理面板。
import 'widgets/manage_groups_sheet.dart';
// 移动/复制目标选择面板。
import 'widgets/group_picker_sheet.dart';
// 设置面板。
import 'widgets/settings_sheet.dart';
// 添加/修改单词表单。
import 'widgets/word_form_sheet.dart';
// 设计稿风格的单词行。
import 'widgets/word_list_tile.dart';
// 固定 40 高搜索框组件。
import 'widgets/word_search_field.dart';
// 排序行与选择模式工具行。
import 'widgets/word_sort_bar.dart';

/// 首页组件，结构类似小程序一个 page 目录下的 Page 实例。
class HomePage extends StatefulWidget {
  /// store 允许测试注入假实现；真实 App 不传时使用"JSON 优先、SQLite 回退"Store。
  const HomePage({super.key, this.store, this.settings, this.audioPlayer});

  /// 接口类型类似 PHP 构造器依赖注入，页面不关心数据具体来自 SQLite 还是测试内存。
  final WordStore? store;

  /// 全局设置由 MainApp 注入；独立测试不传时使用纯内存默认值。
  final SettingsStore? settings;

  /// 音频接口允许测试注入，不依赖真实网络和 Android MediaPlayer。
  final WordAudioPlayer? audioPlayer;

  /// 为页面创建保存 data 和生命周期的 State。
  @override
  State<HomePage> createState() => _HomePageState();
}

/// 一个分组区块：标题信息与其中经过搜索、排序后的单词。
class _WordSection {
  /// 创建区块。
  const _WordSection({
    required this.key,
    required this.name,
    required this.words,
  });

  /// 稳定标识，用于折叠与筛选（如 c1、d5、u20260726）。
  final String key;

  /// 分组标题文字。
  final String name;

  /// 区块内经过搜索过滤与排序的单词。
  final List<Word> words;
}

/// 扁平化列表条目：要么是分组头，要么是一行单词。
class _ListEntry {
  /// 分组头条目。
  const _ListEntry.header(this.section) : word = null;

  /// 单词行条目。
  const _ListEntry.row(this.section, this.word);

  /// 条目所属区块。
  final _WordSection section;

  /// 单词数据；null 表示这是分组头。
  final Word? word;
}

/// 下划线表示状态类仅当前文件可见；Observer 接收 App Show/Hide 等状态。
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// Scaffold key 用于以编程方式打开右侧抽屉。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Scrollbar 和 ListView 必须共享同一个控制器，滑块才可以被直接拖动。
  final ScrollController _scrollController = ScrollController();

  /// 搜索防抖定时器；上万条数据时避免每按一个键立即重复过滤。
  Timer? _searchDebounce;

  /// 单词加载超时定时器；页面提前关闭时必须主动取消，避免留下仍在等待的任务。
  Timer? _loadTimeout;

  /// 页面最终使用的单词 Store，在 initState 中完成一次赋值。
  late final WordStore _store;

  /// 首页和设置面板共享的设置 Store。
  late final SettingsStore _settings;

  /// true 表示首页为了测试自行创建了内存设置，dispose 时需要释放。
  late final bool _ownsSettings;

  /// 真正执行缓存和播放的音频接口。
  late final WordAudioPlayer _audioPlayer;

  /// 自定义分组 Store；本轮为内存实现，重启后重置。
  final GroupStore _groups = GroupStore();

  /// Store 一次加载的全部未删除单词；ListView 仍然只惰性构建可见行。
  List<Word> _allWords = const <Word>[];

  /// 保存已展开的 Word 对象；spelling 可重复，所以不能把拼写当作行身份。
  final Set<Word> _expandedWords = <Word>{};

  /// 选择模式下被勾选的 Word 对象集合。
  final Set<Word> _selectedWords = <Word>{};

  /// 新版学习悬浮按钮是否已经展开。
  bool _learningMenuOpen = false;

  /// 当前处于下载或播放状态的具体 Word 对象。
  Word? _playingWord;

  /// 当前左滑露出操作区的行；同一时刻最多一行。
  Word? _swipedWord;

  /// 当前分组视角，默认按自定义分组。
  GroupMode _mode = GroupMode.custom;

  /// 当前筛选的分组区块 key；null 表示"全部"。
  String? _filterKey;

  /// 已折叠的分组区块 key 集合。
  final Set<String> _collapsedKeys = <String>{};

  /// 是否处于选择模式。
  bool _selectMode = false;

  /// 当前使用的排序字段，默认保持 JSON 或 SQLite 返回顺序。
  WordSortField _sortField = WordSortField.original;

  /// 每个可排序字段各自记住方向；true 升序，false 降序。
  final Map<WordSortField, bool> _sortDirections = <WordSortField, bool>{
    // 字母第一次点击从 A 到 Z。
    WordSortField.alphabet: true,
    // 难度第一次点击从高到低。
    WordSortField.difficulty: false,
    // 日期第一次点击从最近到最早。
    WordSortField.date: false,
  };

  /// 当前真正参与过滤的小写搜索词。
  String _query = '';

  /// 页面是否仍在等待 JSON 或 SQLite 查询。
  bool _isLoading = true;

  /// 数据加载异常；null 表示没有错误。
  Object? _loadError;

  /// 列表静态日期使用的年份参考值。
  late DateTime _dateReference;

  /// 对应小程序 onLoad，只在首页首次创建时执行一次。
  @override
  void initState() {
    // 保留 StatefulWidget 父类初始化流程。
    super.initState();
    // 同一初始时刻供问候语和列表年份判断使用。
    final initialTime = DateTime.now();
    // 有测试 Store 就使用注入值，否则使用全局本地 Store 自动选择 JSON 或 SQLite。
    _store = widget.store ?? LocalWordStore.instance;
    // 记录设置 Store 是否由首页临时创建。
    _ownsSettings = widget.settings == null;
    // 生产环境使用 MainApp 注入值，独立 Widget 测试使用默认内存设置。
    _settings = widget.settings ?? SettingsStore.inMemory();
    // 生产环境默认走 Android 原生服务，测试可以注入立即完成的假播放器。
    _audioPlayer = widget.audioPlayer ?? const NativeWordAudioPlayer();
    // 初始化列表年份参考。
    _dateReference = initialTime;
    // 注册 App 前后台观察者。
    WidgetsBinding.instance.addObserver(this);
    // 监听设置变化，让副标题的复习目标即时刷新。
    _settings.addListener(_handleExternalChange);
    // 监听分组变化：分组被删除时把其中单词移回"未分组"。
    _groups.addListener(_handleGroupsChanged);
    // 异步加载全部 Word/Meaning；方法内部完成 setState。
    unawaited(_loadWords());
  }

  /// 设置或分组内容变化时触发整页重建。
  void _handleExternalChange() {
    // 页面存活时才重建。
    if (mounted) setState(() {});
  }

  /// 分组列表变化：清理指向已删除分组的单词与筛选。
  void _handleGroupsChanged() {
    // 先按通用逻辑重建界面。
    _handleExternalChange();
    // 再把孤儿单词移回"未分组"。
    unawaited(_reassignOrphanWords());
  }

  /// 把 groupId 指向已删除分组的单词批量移回"未分组"。
  Future<void> _reassignOrphanWords() async {
    // 收集所有指向不存在分组的单词。
    final orphans = _allWords
        .where(
          (word) => word.groupId != null && _groups.byId(word.groupId) == null,
        )
        .toList(growable: false);
    // 没有孤儿时直接结束。
    if (orphans.isEmpty) return;
    // 逐个更新回"未分组"。
    for (final word in orphans) {
      await _store.update(word.withGroup(null));
    }
    // 更新完成后刷新列表数据。
    await _refreshWords();
  }

  /// 比较两个 Word；每种排序字段都执行固定的多级次序，最终由编号升序保底。
  ///
  /// 字母：拼写(当前方向) → 难度降序 → 日期降序 → 编号升序。
  /// 难度：难度(当前方向，null 视为 0) → 日期降序 → 拼写升序 → 编号升序。
  /// 日期：日期(当前方向，null 固定末尾) → 难度降序 → 拼写升序 → 编号升序。
  int _compareWords(Word first, Word second, bool isAscending) {
    // switch 根据当前选中字段进入对应的多级比较链。
    switch (_sortField) {
      // 默认字段不会真正进入排序，这里返回相等作为完整兜底。
      case WordSortField.original:
        return 0;

      // 字母排序链。
      case WordSortField.alphabet:
        {
          // 第一级：拼写按用户当前选择的升降序。
          final bySpelling = _compareSpelling(first, second, isAscending);
          // 拼写不同就直接得出结论。
          if (bySpelling != 0) return bySpelling;
          // 第二级：相同拼写按难度从高到低。
          final byDifficulty = _compareDifficulty(first, second, false);
          // 难度不同立即返回。
          if (byDifficulty != 0) return byDifficulty;
          // 第三级：仍然相同时按日期从新到旧。
          final byDate = _compareDate(first, second, false);
          // 日期不同立即返回。
          if (byDate != 0) return byDate;
          // 保底：编号升序。
          return _compareId(first, second);
        }

      // 难度排序链。
      case WordSortField.difficulty:
        {
          // 第一级：难度按用户当前方向；null 难度按 0 参与，因此升序从 0/null 开始。
          final byDifficulty = _compareDifficulty(first, second, isAscending);
          // 难度不同就直接得出结论。
          if (byDifficulty != 0) return byDifficulty;
          // 第二级：难度相同按日期从新到旧。
          final byDate = _compareDate(first, second, false);
          // 日期不同立即返回。
          if (byDate != 0) return byDate;
          // 第三级：再按拼写 A 到 Z。
          final bySpelling = _compareSpelling(first, second, true);
          // 拼写不同立即返回。
          if (bySpelling != 0) return bySpelling;
          // 保底：编号升序。
          return _compareId(first, second);
        }

      // 日期排序链。
      case WordSortField.date:
        {
          // 第一级：日期按用户当前方向，空日期在任何方向都排在末尾。
          final byDate = _compareDate(first, second, isAscending);
          // 日期不同就直接得出结论。
          if (byDate != 0) return byDate;
          // 第二级：日期相同按难度从高到低。
          final byDifficulty = _compareDifficulty(first, second, false);
          // 难度不同立即返回。
          if (byDifficulty != 0) return byDifficulty;
          // 第三级：再按拼写 A 到 Z。
          final bySpelling = _compareSpelling(first, second, true);
          // 拼写不同立即返回。
          if (bySpelling != 0) return bySpelling;
          // 保底：编号升序。
          return _compareId(first, second);
        }
    }
  }

  /// 给非空字段比较结果应用升序或降序。
  int _applyDirection(int comparison, bool isAscending) {
    // 升序保留原比较结果，降序翻转正负。
    return isAscending ? comparison : -comparison;
  }

  /// 拼写层：忽略大小写比较，isAscending 决定 A→Z 还是 Z→A。
  int _compareSpelling(Word first, Word second, bool isAscending) {
    // 与搜索一致，先统一转小写再比较。
    final comparison = first.spelling.toLowerCase().compareTo(
      second.spelling.toLowerCase(),
    );
    // 应用当前方向。
    return _applyDirection(comparison, isAscending);
  }

  /// 难度层：null 难度按业务约定视为 0，升序自然从 0/null 开始，降序把它们放到最后。
  int _compareDifficulty(Word first, Word second, bool isAscending) {
    // 第一个单词的参与值；?? 相当于 PHP 的 null 合并运算符。
    final firstValue = first.difficulty ?? 0;
    // 第二个单词同样把 null 归一成 0。
    final secondValue = second.difficulty ?? 0;
    // 数字比较后应用方向。
    return _applyDirection(firstValue.compareTo(secondValue), isAscending);
  }

  /// 日期层：统一使用 updatedAt ?? createdAt，空日期在两个方向中都固定在末尾。
  int _compareDate(Word first, Word second, bool isAscending) {
    // 复用可空比较，null 永远不会因为降序翻到列表顶部。
    return _compareNullable<DateTime>(
      first.effectiveDate,
      second.effectiveDate,
      (firstValue, secondValue) => firstValue.compareTo(secondValue),
      isAscending,
    );
  }

  /// 编号保底层：id 固定升序，没有 id 的数据排在有编号数据之后。
  int _compareId(Word first, Word second) {
    // 两个都缺 id 时返回 0，最终由原始下标维持稳定顺序。
    return _compareNullable<int>(
      first.id,
      second.id,
      (firstValue, secondValue) => firstValue.compareTo(secondValue),
      true,
    );
  }

  /// 比较可空值，并确保 null 不会因为降序翻到列表顶部。
  int _compareNullable<T>(
    T? first,
    T? second,
    int Function(T first, T second) compareValues,
    bool isAscending,
  ) {
    // 两边都为空时业务字段相等。
    if (first == null && second == null) return 0;
    // 只有第一个为空时固定排后。
    if (first == null) return 1;
    // 只有第二个为空时第一个固定排前。
    if (second == null) return -1;
    // 两边都有值时才应用升降序。
    return _applyDirection(compareValues(first, second), isAscending);
  }

  /// 对区块内的单词执行搜索过滤与稳定排序。
  List<Word> _filterAndSort(List<Word> source) {
    // 先按搜索词过滤 spelling。
    final filtered = _query.isEmpty
        ? List<Word>.of(source)
        : source
              .where((word) => word.spelling.toLowerCase().contains(_query))
              .toList();
    // 默认排序保持 Store/JSON 原始顺序。
    if (_sortField == WordSortField.original) return filtered;
    // 记录原始下标，作为多级比较后的最终稳定兜底。
    final originalIndexes = <Word, int>{};
    for (var index = 0; index < filtered.length; index += 1) {
      originalIndexes[filtered[index]] = index;
    }
    // 读取当前字段方向；缺失时安全采用升序。
    final isAscending = _sortDirections[_sortField] ?? true;
    // Dart sort 类似 PHP usort，比较器返回负数、0 或正数。
    filtered.sort((first, second) {
      // 先执行多级业务比较。
      final result = _compareWords(first, second, isAscending);
      // 业务字段全部打平时回到原始下标。
      if (result != 0) return result;
      return (originalIndexes[first] ?? 0).compareTo(
        originalIndexes[second] ?? 0,
      );
    });
    // 返回排序副本。
    return filtered;
  }

  /// 按当前分组视角把全部单词组织成区块列表。
  List<_WordSection> _buildSections() {
    // 汇总结果。
    final sections = <_WordSection>[];
    // 自定义分组视角。
    if (_mode == GroupMode.custom) {
      // 没有分组或分组已删除的单词全部归入"未分组"。
      final ungrouped = _allWords
          .where(
            (word) =>
                word.groupId == null || _groups.byId(word.groupId) == null,
          )
          .toList();
      // 未分组只有在确实有单词或没有任何自定义分组时才显示。
      // 它最先加入 sections，因此筛选行中的优先级固定为“全部”之后第一项。
      if (ungrouped.isNotEmpty || _groups.groups.isEmpty) {
        sections.add(
          _WordSection(
            key: 'c0',
            name: GroupStore.ungroupedName,
            words: _filterAndSort(ungrouped),
          ),
        );
      }
      // 已存在的自定义分组排在“未分组”之后，并保持用户自己的管理顺序（允许 0 词）。
      for (final group in _groups.groups) {
        sections.add(
          _WordSection(
            key: 'c${group.id}',
            name: group.name,
            words: _filterAndSort(
              _allWords.where((word) => word.groupId == group.id).toList(),
            ),
          ),
        );
      }
      return sections;
    }
    // 难度视角：数值从高到低，"无难度"固定在最后。
    if (_mode == GroupMode.difficulty) {
      // 收集出现过的难度值（含 null）。
      final values = <int?>{
        for (final word in _allWords) word.difficulty,
      }.toList()..sort((a, b) => (b ?? -1).compareTo(a ?? -1));
      // 逐个难度生成区块。
      for (final value in values) {
        sections.add(
          _WordSection(
            key: value == null ? 'dx' : 'd$value',
            name: value == null ? '无难度' : '难度 $value',
            words: _filterAndSort(
              _allWords.where((word) => word.difficulty == value).toList(),
            ),
          ),
        );
      }
      return sections;
    }
    // 时间视角：更新时间用 effectiveDate，加入时间用 createdAt。
    final useUpdated = _mode == GroupMode.updated;
    // 计算单词的分组日期。
    DateTime? dateOf(Word word) =>
        useUpdated ? word.effectiveDate : word.createdAt;
    // 收集出现过的"天"数字键（yyyyMMdd），null 单独一组。
    final dayKeys = <int>{};
    var hasNullDate = false;
    for (final word in _allWords) {
      final date = dateOf(word);
      if (date == null) {
        hasNullDate = true;
      } else {
        final local = date.toLocal();
        dayKeys.add(local.year * 10000 + local.month * 100 + local.day);
      }
    }
    // 日期从新到旧排列。
    final sortedKeys = dayKeys.toList()..sort((a, b) => b.compareTo(a));
    // 视角前缀让折叠状态在两个时间视角之间互不串扰。
    final prefix = useUpdated ? 'u' : 'a';
    // 逐天生成区块。
    for (final dayKey in sortedKeys) {
      // 还原该天日期对象用于格式化标题。
      final day = DateTime(
        dayKey ~/ 10000,
        dayKey % 10000 ~/ 100,
        dayKey % 100,
      );
      sections.add(
        _WordSection(
          key: '$prefix$dayKey',
          name: formatWordDate(day, _dateReference),
          words: _filterAndSort(
            _allWords.where((word) {
              final date = dateOf(word);
              if (date == null) return false;
              final local = date.toLocal();
              return local.year * 10000 + local.month * 100 + local.day ==
                  dayKey;
            }).toList(),
          ),
        ),
      );
    }
    // 没有日期的单词固定放在最后一组。
    if (hasNullDate) {
      sections.add(
        _WordSection(
          key: '${prefix}0',
          name: '无日期',
          words: _filterAndSort(
            _allWords.where((word) => dateOf(word) == null).toList(),
          ),
        ),
      );
    }
    return sections;
  }

  /// 点击排序项：新字段使用预设方向，再点当前字段则切换方向。
  void _handleSortSelected(WordSortField field) {
    // 默认项只恢复原始顺序，没有方向可切换。
    if (field == WordSortField.original) {
      // 已经是默认时无需重建。
      if (_sortField == field) return;
      // 切回原始顺序。
      setState(() => _sortField = field);
      return;
    }
    // setState 同时处理字段选择和当前字段方向翻转。
    setState(() {
      // 再次点击当前非默认字段时翻转升降序。
      if (_sortField == field) {
        _sortDirections[field] = !(_sortDirections[field] ?? true);
      } else {
        // 第一次切到该字段时保留它自己的默认或上次方向。
        _sortField = field;
      }
    });
  }

  /// 从 Store 一次读取全部本地单词（带加载与错误界面）。
  Future<void> _loadWords() async {
    // 重试时立即切回加载状态并清空旧错误。
    setState(() {
      // 显示进度指示器。
      _isLoading = true;
      // 清除上次 PlatformException。
      _loadError = null;
    });

    // 保存“本次请求”的 Timer；finally 只清理它，不会误伤之后可能发起的新请求。
    Timer? requestTimeout;
    try {
      // Completer 类似 PHP 中由我们自行控制成功或失败结果的 Promise 容器。
      final loadResult = Completer<List<Word>>();
      // 先取得 Store 的异步结果；它可能来自资源 JSON，也可能来自 Android 通道。
      final storeRequest = _store.getAll();
      // 如果上一次加载仍残留超时计时，先取消，保证同一页面同时只有一个超时闹钟。
      _loadTimeout?.cancel();
      // 单独保存本次 Timer，finally 才不会误取消未来另一轮加载新建的 Timer。
      final currentTimeout = Timer(const Duration(seconds: 8), () {
        // Store 已经返回时不能重复完成 Completer。
        if (loadResult.isCompleted) return;
        // 原生通道长期不回包时转成可见错误，页面会显示“重新加载”。
        loadResult.completeError(StateError('数据源读取超时（原生通道无响应）'));
      });
      // 把本次 Timer 放进局部引用，供 finally 在成功、异常两种路径统一释放。
      requestTimeout = currentTimeout;
      // 保存到字段后，dispose 就能像清理小程序页面定时器一样主动取消它。
      _loadTimeout = currentTimeout;
      // Store 成功时把单词列表转交给统一的 loadResult。
      unawaited(
        storeRequest.then(
          (words) {
            // 超时已经先发生时忽略迟到结果，避免重复完成 Future。
            if (!loadResult.isCompleted) loadResult.complete(words);
          },
          onError: (Object error, StackTrace stackTrace) {
            // Store 自身失败时保留原始异常与堆栈，方便错误界面和日志定位。
            if (!loadResult.isCompleted) {
              loadResult.completeError(error, stackTrace);
            }
          },
        ),
      );
      // await 类似等待 PHP Promise 完成，后续 UI 逻辑无需区分来源。
      final words = await loadResult.future;
      // 页面可能在查询期间被关闭；mounted=false 时不能再 setState。
      if (!mounted) return;
      // 一次写入全部数据并结束加载状态。
      setState(() {
        // 保存 JSON 内存模式或 SQLite 模式返回的 Word/Meaning。
        _allWords = words;
        // 数据重载后清除已经不存在的展开、选中与滑动状态。
        _expandedWords.removeWhere((word) => !words.contains(word));
        _selectedWords.removeWhere((word) => !words.contains(word));
        if (_swipedWord != null && !words.contains(_swipedWord)) {
          _swipedWord = null;
        }
        // 隐藏加载指示器。
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      // 调试控制台保留完整错误和调用堆栈，真机日志也能直接查到根因。
      debugPrint('单词数据加载失败：$error');
      // stackTrace 类似 PHP exception trace，帮助定位具体代码行。
      debugPrintStack(stackTrace: stackTrace);
      // 页面已销毁时不再处理错误 UI。
      if (!mounted) return;
      // 保存错误并结束加载状态，界面会显示重试按钮。
      setState(() {
        // 记录原始异常供调试。
        _loadError = error;
        // 隐藏加载动画。
        _isLoading = false;
      });
    } finally {
      // 无论成功、Store 报错还是超时，本次计时器都必须停止。
      requestTimeout?.cancel();
      // 只有字段仍指向本次 Timer 时才清空，避免覆盖后来一轮加载的引用。
      if (identical(_loadTimeout, requestTimeout)) _loadTimeout = null;
    }
  }

  /// 增删改之后的轻量刷新：重新读取数据但不显示整页加载圈。
  Future<void> _refreshWords() async {
    // 读取最新数据。
    final words = await _store.getAll();
    // 页面可能已销毁。
    if (!mounted) return;
    // 与 _loadWords 相同的状态清理。
    setState(() {
      _allWords = words;
      _expandedWords.removeWhere((word) => !words.contains(word));
      _selectedWords.removeWhere((word) => !words.contains(word));
      if (_swipedWord != null && !words.contains(_swipedWord)) {
        _swipedWord = null;
      }
    });
  }

  /// App 生命周期变化，对应小程序 App Show/App Hide。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed 表示 App 回到前台。
    if (state == AppLifecycleState.resumed) {
      // 获取恢复时真实时间。
      final resumedAt = DateTime.now();
      // 跨年后重新构建静态列表日期；问候语也顺带刷新。
      setState(() => _dateReference = resumedAt);
      // 防止继续执行下面停止逻辑。
      return;
    }
    // 离开前台时停止发音，避免 App 隐藏后继续播。
    unawaited(_stopAudio());
  }

  /// 搜索框输入回调，使用 120ms 防抖保护上万条内存过滤。
  void _handleSearchChanged(String value) {
    // 标准化大小写和首尾空格。
    final normalizedQuery = value.trim().toLowerCase();
    // 每次输入先取消上一个尚未执行的过滤任务。
    _searchDebounce?.cancel();
    // 120ms 内没有新输入才真正更新 query。
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      // 页面卸载或值未变化时不刷新。
      if (!mounted || _query == normalizedQuery) return;
      // 类似小程序 setData，触发过滤后的列表重建。
      setState(() => _query = normalizedQuery);
    });
  }

  /// 点击单词行：滑动打开时先收起；选择模式切换勾选；否则播放并展开。
  void _handleRowTap(Word word) {
    // 有行处于滑动打开状态时，本次点击只负责收起。
    if (_swipedWord != null) {
      setState(() => _swipedWord = null);
      return;
    }
    // 选择模式下点击整行等于切换勾选。
    if (_selectMode) {
      _toggleSelected(word);
      return;
    }
    // 设计稿行为：点击同时播放发音并切换释义展开。
    setState(() {
      // 有释义才有展开状态可切换。
      if (word.meanings.isNotEmpty) {
        final wasExpanded = _expandedWords.remove(word);
        if (!wasExpanded) _expandedWords.add(word);
      }
    });
    // 播放当前口音发音。
    unawaited(_playWord(word));
  }

  /// 切换某行的选中状态。
  void _toggleSelected(Word word) {
    // setState 同步刷新勾选框与计数。
    setState(() {
      final wasSelected = _selectedWords.remove(word);
      if (!wasSelected) _selectedWords.add(word);
    });
  }

  /// 行左滑打开或关闭操作区。
  void _handleSwipeChanged(Word word, bool open) {
    // 选择模式下禁止滑出操作区，与设计稿一致。
    if (open && _selectMode) return;
    // 更新当前滑动行。
    setState(() => _swipedWord = open ? word : null);
  }

  /// 点击单词文字后按当前口音播放；同一行播放中重复点击直接忽略。
  Future<void> _playWord(Word word) async {
    // 下载中和播放中都属于 active，同一个 Word 不重新开始。
    if (identical(_playingWord, word)) return;
    // 记录当前行，喇叭动画立即出现，不等待网络请求完成。
    setState(() => _playingWord = word);
    try {
      // 读取点击时的口音快照；设置变化只影响下一次播放。
      final accent = _settings.accent;
      // 原生先查口音缓存，再按不背单词、有道顺序下载并播放。
      await _audioPlayer.play(word.spelling, accent);
    } on WordAudioInterruptedException {
      // 点击其他单词或页面进入后台属于正常中断，不显示错误。
    } catch (error, stackTrace) {
      // 控制台保留完整错误便于真机排查音源、网络或解码问题。
      debugPrint('单词发音失败（${word.spelling}）：$error');
      // 同时记录 Dart 调用堆栈。
      debugPrintStack(stackTrace: stackTrace);
      // 只有当前请求仍对应这行时才提示；旧请求失败不能干扰新播放。
      if (mounted && identical(_playingWord, word)) {
        // 先移除上一条提示，避免快速点击造成 SnackBar 排队。
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // 向用户显示明确失败，并保留原生汇总的双音源原因。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法播放"${word.spelling}"：$error')),
        );
      }
    } finally {
      // 只有当前行仍是这次请求时才隐藏喇叭；旧 Future 不能清掉新行状态。
      if (mounted && identical(_playingWord, word)) {
        setState(() => _playingWord = null);
      }
    }
  }

  /// 主动停止音频并立即移除播放动画。
  Future<void> _stopAudio() async {
    // 没有下载或播放时不调用原生通道。
    if (_playingWord == null) return;
    // mounted 时立即清除动画状态。
    if (mounted) setState(() => _playingWord = null);
    try {
      // 原生会让旧 play Future 以可忽略的中断结束。
      await _audioPlayer.stop();
    } catch (error, stackTrace) {
      // 停止失败不阻断生命周期，只保留调试信息。
      debugPrint('停止单词发音失败：$error');
      // 输出调用堆栈。
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// 打开设置面板。
  void _openSettings() {
    // Future 在用户关闭面板时结束，首页无需等待其结果。
    unawaited(showAppSettingsSheet(context, _settings));
  }

  /// 打开添加/修改单词表单；editing 为 null 表示新增。
  void _openWordForm({Word? editing}) {
    // 表单提交由首页执行 Store 操作。
    unawaited(
      showWordFormSheet(
        context,
        groups: _groups,
        editing: editing,
        onSubmit: (result) => _submitWordForm(result, editing: editing),
      ),
    );
  }

  /// 执行表单提交：新增走 create，编辑走 update。
  Future<void> _submitWordForm(WordFormResult result, {Word? editing}) async {
    try {
      // 编辑模式：在原对象基础上替换拼写、释义与分组。
      if (editing != null) {
        await _store.update(
          editing.edited(
            spelling: result.spelling,
            meanings: result.meanings,
            groupId: result.groupId,
          ),
        );
      } else {
        // 新增模式：交给 Store 生成主键与时间。
        await _store.create(
          Word(
            spelling: result.spelling,
            meanings: result.meanings,
            groupId: result.groupId,
          ),
        );
      }
      // 无论新增或编辑都刷新列表。
      await _refreshWords();
    } catch (error) {
      // 失败时保留面板并提示原因。
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存单词失败：$error')));
    }
  }

  /// 弹出删除确认对话框。
  void _confirmDelete(Word word) {
    // 先收起滑动操作区。
    setState(() => _swipedWord = null);
    // showDialog 展示设计稿风格的居中确认卡。
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          // 读取当前明暗对应的设计令牌。
          final tokens = AppTokens.of(dialogContext);
          // Dialog 自绘圆角卡片。
          return Dialog(
            backgroundColor: tokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                // 高度只包住内容。
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 对话框标题。
                  Text(
                    '删除单词',
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 标题与正文间距。
                  const SizedBox(height: 8),
                  // 确认文案带上单词拼写。
                  Text(
                    '确定要删除「${word.spelling}」吗？此操作无法撤销。',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  // 正文与按钮间距。
                  const SizedBox(height: 18),
                  // 取消与删除按钮。
                  Row(
                    children: [
                      // 取消按钮：描边样式。
                      Expanded(
                        child: InkWell(
                          key: const Key('delete-cancel'),
                          onTap: () => Navigator.of(dialogContext).pop(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: tokens.inputBorder),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                color: tokens.textMedium,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 删除按钮：危险色实底。
                      Expanded(
                        child: InkWell(
                          key: const Key('delete-confirm'),
                          onTap: () {
                            // 先关闭对话框再执行删除。
                            Navigator.of(dialogContext).pop();
                            unawaited(_deleteWord(word));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTokens.danger,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '删除',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 真正执行删除并刷新列表。
  Future<void> _deleteWord(Word word) async {
    try {
      // 没有主键的数据无法定位，直接提示。
      final id = word.id;
      if (id == null) throw StateError('该单词缺少 id，无法删除');
      // JSON 模式移出内存，SQLite 模式软删除。
      await _store.delete(id);
      // 刷新列表。
      await _refreshWords();
    } catch (error) {
      // 删除失败提示原因。
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  /// 打开移动/复制目标分组选择面板。
  Future<void> _pickGroupAndApply({required bool isCopy}) async {
    // 没有选中任何单词时忽略（按钮颜色已提示不可用）。
    if (_selectedWords.isEmpty) return;
    // 组装目标列表：全部自定义分组 + 未分组。
    final targets = <GroupPickerTarget>[
      for (final group in _groups.groups)
        GroupPickerTarget(
          groupId: group.id,
          name: group.name,
          wordCount: _allWords.where((word) => word.groupId == group.id).length,
        ),
      GroupPickerTarget(
        groupId: null,
        name: GroupStore.ungroupedName,
        wordCount: _allWords
            .where(
              (word) =>
                  word.groupId == null || _groups.byId(word.groupId) == null,
            )
            .length,
      ),
    ];
    // 弹出选择面板等待用户挑选。
    final picked = await showGroupPickerSheet(
      context,
      title: '${isCopy ? '复制' : '移动'} ${_selectedWords.length} 个单词到',
      targets: targets,
    );
    // 用户直接关闭面板时不执行任何操作。
    if (picked == null || !mounted) return;
    // record 第一个位置就是目标分组 id。
    final targetGroupId = picked.$1;
    try {
      // 复制：为每个选中单词创建一份新记录。
      if (isCopy) {
        for (final word in _selectedWords) {
          await _store.create(
            Word(
              spelling: word.spelling,
              meanings: word.meanings,
              difficulty: word.difficulty,
              groupId: targetGroupId,
              reviewedAt: word.reviewedAt,
              createdAt: word.createdAt,
              updatedAt: word.updatedAt,
            ),
          );
        }
      } else {
        // 移动：仅更新分组字段。
        for (final word in _selectedWords) {
          await _store.update(word.withGroup(targetGroupId));
        }
      }
      // 操作完成后清空选择并刷新。
      _selectedWords.clear();
      await _refreshWords();
    } catch (error) {
      // 批量操作失败时提示原因。
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
    }
  }

  /// 尚未在本轮原型中定义具体页面的菜单项使用统一提示。
  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('「$feature」功能正在整理中')));
  }

  /// 将任意异常转换成用户可见的详情，不再只显示笼统失败文案。
  String _describeLoadError(Object error) {
    // toString 会保留 PlatformException code、JSON offset 和 StateError 信息。
    final details = error.toString();
    // 极少数自定义异常可能返回空文本，此时至少显示运行时类型。
    return details.trim().isEmpty ? error.runtimeType.toString() : details;
  }

  /// 页面卸载时释放 Observer、Timer 和监听器。
  @override
  void dispose() {
    // 移除 App 生命周期监听。
    WidgetsBinding.instance.removeObserver(this);
    // 取消尚未执行的搜索防抖。
    _searchDebounce?.cancel();
    // 页面关闭后不再需要加载超时提醒，主动取消可避免测试或真实页面残留计时任务。
    _loadTimeout?.cancel();
    // 移除设置与分组监听。
    _settings.removeListener(_handleExternalChange);
    _groups.removeListener(_handleGroupsChanged);
    // 释放内存分组 Store。
    _groups.dispose();
    // 只有确实正在播放时才调用 stop，避免独立 Widget 测试访问不存在的原生插件。
    if (_playingWord != null) {
      // dispose 中不能 await；服务自身会正确释放原生资源。
      unawaited(
        _audioPlayer.stop().catchError((Object error) {
          // 页面已销毁，只把停止失败写入调试控制台。
          debugPrint('首页销毁时停止发音失败：$error');
        }),
      );
    }
    // 释放可拖动滚动条和列表共用的控制器。
    _scrollController.dispose();
    // 仅释放首页自行创建的测试内存设置；MainApp 注入的全局 Store 继续存在。
    if (_ownsSettings) _settings.dispose();
    // 最后执行父类清理。
    super.dispose();
  }

  /// 根据加载状态选择进度、错误、空状态或高性能列表。
  Widget _buildListContent(List<_ListEntry> entries, bool hasVisibleRows) {
    // 数据源尚未返回时显示居中进度圈。
    if (_isLoading) {
      // SizedBox 限定小型进度圈尺寸。
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          // CircularProgressIndicator 类似小程序 loading 组件。
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // Store 抛错时同时显示可恢复操作与实际异常详情。
    if (_loadError != null) {
      // SingleChildScrollView 防止较长错误在小屏幕发生纵向溢出。
      return Center(
        child: SingleChildScrollView(
          // 错误区与屏幕边缘保持足够距离。
          padding: const EdgeInsets.all(24),
          child: Column(
            // mainAxisSize.min 让内容不强制撑满整个滚动区域。
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用户首先看到简短结论。
              const Text(
                '单词数据加载失败',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              // 标题与详情之间留白。
              const SizedBox(height: 8),
              // SelectableText 允许长按选择并复制真机上的具体错误。
              SelectableText(
                // key 让测试能确认具体错误确实已经输出到页面。
                key: const Key('word-load-error-details'),
                // 输出原始 FormatException 或 PlatformException 内容。
                _describeLoadError(_loadError!),
                // 错误详情居中阅读。
                textAlign: TextAlign.center,
                // 使用次要颜色与较小字号，不抢过错误标题。
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              // 详情与按钮间距。
              const SizedBox(height: 8),
              // TextButton 对应小程序 bindtap 重试按钮。
              TextButton(
                // 点击后重新执行 Store 查询。
                onPressed: _loadWords,
                // 按钮文字。
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    // 搜索无匹配或完全没有数据时显示空状态。
    if (!hasVisibleRows && entries.isEmpty) {
      // 空状态占据列表剩余区域中心。
      return Center(
        child: Text(
          // 有搜索词时按设计稿提示"未找到相关单词"。
          _query.isEmpty ? '暂无单词' : '未找到相关单词',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }

    // Scrollbar 提供始终可见且可直接拖动到任意位置的滑块。
    return Scrollbar(
      // 与 ListView 共用控制器，否则拖动滑块无法控制列表。
      controller: _scrollController,
      // 真机上无需先滚动一次就能看到滑块。
      thumbVisibility: true,
      // interactive=true 允许手指或鼠标按住滑块快速拖到底部。
      interactive: true,
      // ListView.builder 只创建屏幕附近的行，适合上万单词。
      child: ListView.builder(
        // 使用同一个 ScrollController。
        controller: _scrollController,
        // 底部保留 116 像素，避免最后几行被浮动按钮遮住。
        padding: const EdgeInsets.only(bottom: 116),
        // 分组头与单词行都在同一个扁平列表里。
        itemCount: entries.length,
        // builder 按需构建当前可见 index。
        itemBuilder: (context, index) {
          // 取得当前条目。
          final entry = entries[index];
          // 分组头条目。
          if (entry.word == null) {
            return _SectionHeader(
              section: entry.section,
              isCollapsed: _collapsedKeys.contains(entry.section.key),
              selectMode: _selectMode,
              isAllSelected:
                  entry.section.words.isNotEmpty &&
                  entry.section.words.every(_selectedWords.contains),
              onTap: () => setState(() {
                // 点击分组头切换折叠状态。
                if (!_collapsedKeys.remove(entry.section.key)) {
                  _collapsedKeys.add(entry.section.key);
                }
              }),
              onToggleSelect: () => setState(() {
                // 分组头勾选：全选或全不选该区块。
                final allSelected =
                    entry.section.words.isNotEmpty &&
                    entry.section.words.every(_selectedWords.contains);
                if (allSelected) {
                  _selectedWords.removeAll(entry.section.words);
                } else {
                  _selectedWords.addAll(entry.section.words);
                }
              }),
            );
          }
          // 单词行条目。
          final word = entry.word!;
          return WordListTile(
            // ObjectKey 使用对象身份，同 spelling 的多条数据不会冲突。
            key: ObjectKey(word),
            // 传入一次性加载的数据项。
            item: word,
            // 传入静态年份参考。
            dateReference: _dateReference,
            // 根据页面 Set 判断当前行是否展开。
            isExpanded: _expandedWords.contains(word),
            // 全部中文释义统一使用首页设置中选择的全角分隔符。
            definitionSeparator: _settings.definitionSeparator.symbol,
            // 只有当前具体对象显示播放动画。
            isPlaying: identical(_playingWord, word),
            // 选择模式与勾选状态。
            selectMode: _selectMode,
            isSelected: _selectedWords.contains(word),
            // 当前行是否滑开操作区。
            isSwipedOpen: identical(_swipedWord, word),
            // 点击整行：播放并展开 / 勾选 / 收起滑动。
            onTap: () => _handleRowTap(word),
            // 勾选框独立切换选中。
            onToggleSelect: () => _toggleSelected(word),
            // 滑动打开或关闭操作区。
            onSwipeChanged: (open) => _handleSwipeChanged(word, open),
            // 左滑操作：修改与删除。
            onEdit: () {
              // 先收起操作区再打开表单。
              setState(() => _swipedWord = null);
              _openWordForm(editing: word);
            },
            onDelete: () => _confirmDelete(word),
          );
        },
      ),
    );
  }

  /// build 对应小程序 WXML：把当前 State 转成界面树。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 组织全部分组区块。
    final sections = _buildSections();
    // 当前筛选 key 失效（分组被删除等）时回退到"全部"。
    final activeFilter = sections.any((section) => section.key == _filterKey)
        ? _filterKey
        : null;
    // 应用筛选后的区块。
    var shownSections = activeFilter == null
        ? sections
        : sections.where((section) => section.key == activeFilter).toList();
    // 搜索时隐藏没有匹配的分组。
    if (_query.isNotEmpty) {
      shownSections = shownSections
          .where((section) => section.words.isNotEmpty)
          .toList();
    }
    // 当前可见（参与全选与随身听/默写目标）的全部单词。
    final visibleWords = <Word>[
      for (final section in shownSections) ...section.words,
    ];
    // 扁平化为分组头 + 单词行。
    final entries = <_ListEntry>[];
    for (final section in shownSections) {
      // 分组头始终显示。
      entries.add(_ListEntry.header(section));
      // 折叠时不铺开该区块的单词行。
      if (!_collapsedKeys.contains(section.key)) {
        for (final word in section.words) {
          entries.add(_ListEntry.row(section, word));
        }
      }
    }
    // 筛选 chips 使用未过滤的区块名（含"全部"）。
    final chips = <GroupFilterChip>[
      GroupFilterChip(
        sectionKey: null,
        name: '全部',
        isActive: activeFilter == null,
      ),
      for (final section in sections)
        GroupFilterChip(
          sectionKey: section.key,
          name: section.name,
          isActive: activeFilter == section.key,
        ),
    ];
    // 随身听/默写的目标数量：有勾选用勾选数，否则用全部可见数。
    final selectedVisible = visibleWords.where(_selectedWords.contains).length;
    final targetCount = selectedVisible > 0
        ? selectedVisible
        : visibleWords.length;
    // 真正传给学习页面的数据必须保持当前列表顺序；有选择时仅保留勾选项。
    final learningWords = List<Word>.unmodifiable(
      selectedVisible > 0
          ? visibleWords.where(_selectedWords.contains)
          : visibleWords,
    );
    // 全部可见分组是否都已折叠，决定按钮文案。
    final allCollapsed =
        shownSections.isNotEmpty &&
        shownSections.every((section) => _collapsedKeys.contains(section.key));

    // Scaffold 是页面根骨架；endDrawer 提供右侧抽屉。
    return Scaffold(
      key: _scaffoldKey,
      // 右侧抽屉菜单。
      endDrawer: HomeDrawer(
        // 添加单词：先关抽屉再开表单。
        onAddWord: () {
          Navigator.of(context).pop();
          _openWordForm();
        },
        // 设置：先关抽屉再开设置面板。
        onOpenSettings: () {
          Navigator.of(context).pop();
          _openSettings();
        },
        // 数据导出：占位提示。
        onExport: () {
          Navigator.of(context).pop();
          _showComingSoon('数据导出');
        },
        // 关于：占位提示。
        onAbout: () {
          Navigator.of(context).pop();
          _showComingSoon('关于');
        },
      ),
      // SafeArea 避开状态栏、刘海和底部手势区。
      body: SafeArea(
        // Stack 让底部浮动按钮悬浮在列表之上。
        child: Stack(
          children: [
            // 主内容：上方工具区 + 下方列表。
            Column(
              children: [
                // 标题、搜索框、分组行与排序行保留左右 20 边距。
                Padding(
                  // 顶部 20、底部 10，让排序行贴近列表。
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    // 左对齐标题。
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部问候与汉堡按钮。
                      HomeHeader(
                        now: DateTime.now(),
                        wordCount: _allWords.length,
                        dailyGoal: _settings.dailyGoal,
                        // 打开右侧抽屉。
                        onMenuPressed: () =>
                            _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                      // 标题与搜索框间距。
                      const SizedBox(height: 16),
                      // 固定 40 像素搜索框。
                      WordSearchField(onChanged: _handleSearchChanged),
                      // 搜索与分组行间距。
                      const SizedBox(height: 14),
                      // 分组视角、筛选 chips 与分组管理。
                      GroupFilterBar(
                        mode: _mode,
                        chips: chips,
                        // 切换视角时清空筛选。
                        onModeSelected: (mode) => setState(() {
                          _mode = mode;
                          _filterKey = null;
                        }),
                        // 点击 chip 切换筛选。
                        onChipSelected: (key) =>
                            setState(() => _filterKey = key),
                        // 仅自定义分组模式可打开分组管理。
                        onOpenManage: () {
                          if (_mode != GroupMode.custom) return;
                          unawaited(showManageGroupsSheet(context, _groups));
                        },
                      ),
                      // 分组行与排序行间距。
                      const SizedBox(height: 12),
                      // 排序行 + 折叠/选择动作。
                      WordSortBar(
                        selectedField: _sortField,
                        directions: _sortDirections,
                        onSelected: _handleSortSelected,
                        // 全部折叠时按钮显示"展开"。
                        collapseLabel: allCollapsed ? '展开' : '折叠',
                        onToggleCollapseAll: () => setState(() {
                          if (allCollapsed) {
                            // 展开全部。
                            for (final section in shownSections) {
                              _collapsedKeys.remove(section.key);
                            }
                          } else {
                            // 折叠全部。
                            for (final section in shownSections) {
                              _collapsedKeys.add(section.key);
                            }
                          }
                        }),
                        // 选择模式切换。
                        selectLabel: _selectMode ? '完成' : '选择',
                        onToggleSelectMode: () => setState(() {
                          _selectMode = !_selectMode;
                          // 进出选择模式都清空选择与滑动状态。
                          _selectedWords.clear();
                          _swipedWord = null;
                        }),
                      ),
                      // 选择模式下追加第二行工具。
                      if (_selectMode) ...[
                        const SizedBox(height: 10),
                        WordSelectionBar(
                          selectedCount: _selectedWords.length,
                          // 全选当前可见单词。
                          onSelectAll: () => setState(
                            () => _selectedWords.addAll(visibleWords),
                          ),
                          // 反选当前可见单词。
                          onInvertSelection: () => setState(() {
                            for (final word in visibleWords) {
                              if (!_selectedWords.remove(word)) {
                                _selectedWords.add(word);
                              }
                            }
                          }),
                          // 移动与复制。
                          onMove: () =>
                              unawaited(_pickGroupAndApply(isCopy: false)),
                          onCopy: () =>
                              unawaited(_pickGroupAndApply(isCopy: true)),
                        ),
                      ],
                    ],
                  ),
                ),
                // 列表占满剩余高度并贴屏左右边缘。
                Expanded(
                  // 整个列表容器只有顶部一条外边框，颜色对齐 HTML 原型(--cBd/#e6e7e9)。
                  child: DecoratedBox(
                    // key 供 Widget 测试准确定位。
                    key: const Key('word-list'),
                    // 使用当前主题 surface 和原型顶部分隔线色（border = cBd）。
                    decoration: BoxDecoration(
                      color: tokens.card,
                      border: Border(top: BorderSide(color: tokens.border)),
                    ),
                    // 根据加载状态返回对应内容。
                    child: _buildListContent(entries, visibleWords.isNotEmpty),
                  ),
                ),
              ],
            ),
            // 展开学习菜单后增加轻量遮罩；点击空白处即可收起。
            if (_learningMenuOpen)
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('learning-menu-backdrop'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _learningMenuOpen = false),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
            // 新版原型仅常驻一个“学习”按钮，展开后向上显示两个具体入口。
            Positioned(
              right: 20,
              bottom: 32,
              child: LearningFab(
                isOpen: _learningMenuOpen,
                targetCount: targetCount,
                onToggle: () =>
                    setState(() => _learningMenuOpen = !_learningMenuOpen),
                onOpenPlayer: () {
                  // 没有可学习单词时不打开空页面。
                  if (learningWords.isEmpty) {
                    _showComingSoon('当前列表没有可学习单词');
                    return;
                  }
                  setState(() => _learningMenuOpen = false);
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ListeningPage(
                          words: learningWords,
                          audioPlayer: _audioPlayer,
                          accent: _settings.accent,
                          definitionSeparator:
                              _settings.definitionSeparator.symbol,
                        ),
                      ),
                    ),
                  );
                },
                onOpenDictation: () {
                  // 默写同样遵循“已选择优先，否则当前可见”的范围规则。
                  if (learningWords.isEmpty) {
                    _showComingSoon('当前列表没有可学习单词');
                    return;
                  }
                  setState(() => _learningMenuOpen = false);
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DictationPage(
                          words: learningWords,
                          audioPlayer: _audioPlayer,
                          accent: _settings.accent,
                          definitionSeparator:
                              _settings.definitionSeparator.symbol,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组区块头：34 高浅底行，含可选勾选框、名称、计数与折叠箭头。
class _SectionHeader extends StatelessWidget {
  /// 全部状态由首页注入。
  const _SectionHeader({
    required this.section,
    required this.isCollapsed,
    required this.selectMode,
    required this.isAllSelected,
    required this.onTap,
    required this.onToggleSelect,
  });

  /// 当前区块数据。
  final _WordSection section;

  /// 是否处于折叠状态。
  final bool isCollapsed;

  /// 首页是否处于选择模式。
  final bool selectMode;

  /// 区块内全部单词是否都被选中。
  final bool isAllSelected;

  /// 点击行切换折叠。
  final VoidCallback onTap;

  /// 点击勾选框整组选中/取消。
  final VoidCallback onToggleSelect;

  /// 输出设计稿的分组头行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // InkWell 提供整行点击反馈。
    return InkWell(
      // key 便于测试点击具体分组头。
      key: Key('section-${section.key}'),
      onTap: onTap,
      child: Container(
        // 34 高浅底与底部分隔线。
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: tokens.sub,
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Row(
          children: [
            // 选择模式下显示整组勾选框。
            if (selectMode) ...[
              GestureDetector(
                // 阻止冒泡到整行折叠点击。
                onTap: onToggleSelect,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isAllSelected ? AppTokens.accent : tokens.card,
                    border: Border.all(
                      color: isAllSelected ? AppTokens.accent : tokens.check,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: isAllSelected
                      ? const Icon(
                          TablerIcons.check,
                          color: Colors.white,
                          size: 13,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 10),
            ],
            // 分组名称。
            Text(
              section.name,
              style: TextStyle(
                color: tokens.textMedium,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            // 撑开中间空间。
            const Spacer(),
            // 区块内单词数量。
            Text(
              '${section.words.length} 词',
              style: TextStyle(color: tokens.muted, fontSize: 11.5),
            ),
            // 数量与箭头间距。
            const SizedBox(width: 10),
            // 折叠箭头：折叠 0 度，展开旋转 90 度。
            AnimatedRotation(
              turns: isCollapsed ? 0 : 0.25,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                TablerIcons.chevronRight,
                color: tokens.muted,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
