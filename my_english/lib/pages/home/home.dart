// dart:async 提供 Timer 和 Future，分别对应 JS 定时器和 PHP 异步结果概念。
import 'dart:async';
// dart:collection 提供按对象身份保存原始下标的 HashMap。
import 'dart:collection';

// material.dart 提供页面、布局、加载指示器和按钮等 Flutter UI 组件。
import 'package:flutter/material.dart';

// 引入公共主题颜色。
import '../../common/theme.dart';
// Word 是全应用共享模型，不属于首页私有文件。
import '../../models/word.dart';
// 音频服务位于页面之外，未来循环播放页可以直接复用。
import '../../services/word_audio.dart';
// 设置 Store 提供持久化口音与主题。
import '../../store/settings.dart';
// Store 同样放在页面目录之外，循环播放页等页面可以直接复用。
import '../../store/word.dart';
// 引入首页顶部问候和时间组件。
import 'widgets/home_header.dart';
// 引入底部设置面板。
import 'widgets/settings_sheet.dart';
// 引入可点击展开的单词行组件。
import 'widgets/word_list_tile.dart';
// 引入固定 40 高搜索框组件。
import 'widgets/word_search_field.dart';
// 引入搜索框下方的排序工具栏。
import 'widgets/word_sort_bar.dart';

/// 首页组件，结构类似小程序一个 page 目录下的 Page 实例。
class HomePage extends StatefulWidget {
  /// store 允许测试注入假实现；真实 App 不传时使用“JSON 优先、SQLite 回退”Store。
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

/// 下划线表示状态类仅当前文件可见；Observer 接收 App Show/Hide 等状态。
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// 只有 HomeHeader 订阅该时间，列表不会每秒刷新。
  final ValueNotifier<DateTime> _now = ValueNotifier<DateTime>(DateTime.now());

  /// Scrollbar 和 ListView 必须共享同一个控制器，滑块才可以被直接拖动。
  final ScrollController _scrollController = ScrollController();

  /// 顶部完整日期时间使用的每秒定时器。
  Timer? _clockTimer;

  /// 搜索防抖定时器；上万条数据时避免每按一个键立即重复过滤。
  Timer? _searchDebounce;

  /// 页面最终使用的单词 Store，在 initState 中完成一次赋值。
  late final WordStore _store;

  /// 首页和设置面板共享的设置 Store。
  late final SettingsStore _settings;

  /// true 表示首页为了测试自行创建了内存设置，dispose 时需要释放。
  late final bool _ownsSettings;

  /// 真正执行缓存和播放的音频接口。
  late final WordAudioPlayer _audioPlayer;

  /// Store 一次加载的全部未删除单词；ListView 仍然只惰性构建可见行。
  List<Word> _allWords = const <Word>[];

  /// 保存已展开的 Word 对象；spelling 可重复，所以不能再把拼写当作行身份。
  final Set<Word> _expandedWords = <Word>{};

  /// 当前处于下载或播放状态的具体 Word 对象；重复 spelling 仍彼此独立。
  Word? _playingWord;

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

  /// 类似 PHP getFilteredWords()：根据 query 返回当前应该显示的数据。
  List<Word> get _visibleWords {
    // 没有搜索词时先引用完整列表，有搜索词时创建过滤结果。
    final filteredWords = _query.isEmpty
        ? _allWords
        : _allWords
              // where 类似 PHP array_filter，只检查 spelling 字段。
              .where((word) => word.spelling.toLowerCase().contains(_query))
              // 排序前允许生成可变副本。
              .toList(growable: true);
    // 默认排序直接保留 Store/JSON 原始顺序和对象集合。
    if (_sortField == WordSortField.original) return filteredWords;

    // HashMap.identity 用对象身份记录原始下标，相同 spelling 或 id 为空也不会冲突。
    final originalIndexes = HashMap<Word, int>.identity();
    // 一次线性循环建立稳定排序的最终兜底顺序。
    for (var index = 0; index < _allWords.length; index += 1) {
      // 每个 Word 对象对应它在原数据中的位置。
      originalIndexes[_allWords[index]] = index;
    }
    // 即使 query 为空也创建副本，绝不原地改变 Store 返回列表。
    final sortedWords = List<Word>.of(filteredWords);
    // 读取当前字段方向；非默认字段一定存在，缺失时仍安全采用升序。
    final isAscending = _sortDirections[_sortField] ?? true;
    // Dart sort 类似 PHP usort，比较器返回负数、0 或正数。
    sortedWords.sort((first, second) {
      // 先比较真正业务字段。
      final fieldResult = _compareWords(first, second, isAscending);
      // 字段不相等时直接使用比较结果。
      if (fieldResult != 0) return fieldResult;
      // 相等时回到原始下标，保证重复项顺序稳定、不随机跳动。
      return (originalIndexes[first] ?? 0).compareTo(
        originalIndexes[second] ?? 0,
      );
    });
    // 返回当前 build 使用的排序副本。
    return sortedWords;
  }

  /// 对应小程序 onLoad，只在首页首次创建时执行一次。
  @override
  void initState() {
    // 保留 StatefulWidget 父类初始化流程。
    super.initState();
    // 同一初始时刻供顶部时钟和列表年份判断使用。
    final initialTime = DateTime.now();
    // 有测试 Store 就使用注入值，否则使用全局本地 Store 自动选择 JSON 或 SQLite。
    _store = widget.store ?? LocalWordStore.instance;
    // 记录设置 Store 是否由首页临时创建。
    _ownsSettings = widget.settings == null;
    // 生产环境使用 MainApp 注入值，独立 Widget 测试使用默认内存设置。
    _settings = widget.settings ?? SettingsStore.inMemory();
    // 生产环境默认走 Android 原生服务，测试可以注入立即完成的假播放器。
    _audioPlayer = widget.audioPlayer ?? const NativeWordAudioPlayer();
    // 初始化顶部时间。
    _now.value = initialTime;
    // 初始化列表年份参考。
    _dateReference = initialTime;
    // 注册 App 前后台观察者。
    WidgetsBinding.instance.addObserver(this);
    // 启动顶部时钟。
    _startClock(initialTime);
    // 异步加载全部 Word/Meaning；方法内部完成 setState。
    unawaited(_loadWords());
  }

  /// 比较两个 Word 的当前排序字段；null 难度或日期无论方向都固定放在末尾。
  int _compareWords(Word first, Word second, bool isAscending) {
    // switch 根据当前选中字段选择比较规则。
    return switch (_sortField) {
      // 默认字段不会真正进入排序，这里返回相等作为完整兜底。
      WordSortField.original => 0,
      // 字母忽略大小写比较，并根据方向翻转正负号。
      WordSortField.alphabet => _applyDirection(
        first.spelling.toLowerCase().compareTo(second.spelling.toLowerCase()),
        isAscending,
      ),
      // 难度使用可空比较，null 始终在末尾。
      WordSortField.difficulty => _compareNullable<int>(
        first.difficulty,
        second.difficulty,
        (firstValue, secondValue) => firstValue.compareTo(secondValue),
        isAscending,
      ),
      // 日期统一使用模型的 updatedAt ?? createdAt。
      WordSortField.date => _compareNullable<DateTime>(
        first.effectiveDate,
        second.effectiveDate,
        (firstValue, secondValue) => firstValue.compareTo(secondValue),
        isAscending,
      ),
    };
  }

  /// 给非空字段比较结果应用升序或降序。
  int _applyDirection(int comparison, bool isAscending) {
    // 升序保留原比较结果，降序翻转正负。
    return isAscending ? comparison : -comparison;
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

  /// 从 Store 一次读取全部本地单词。
  Future<void> _loadWords() async {
    // 重试时立即切回加载状态并清空旧错误。
    setState(() {
      // 显示进度指示器。
      _isLoading = true;
      // 清除上次 PlatformException。
      _loadError = null;
    });

    try {
      // await 类似等待 PHP Store 查询完成后取得结果。
      final words = await _store.getAll();
      // 页面可能在查询期间被关闭；mounted=false 时不能再 setState。
      if (!mounted) return;
      // 一次写入全部数据并结束加载状态。
      setState(() {
        // 保存 JSON 内存模式或 SQLite 模式返回的 Word/Meaning。
        _allWords = words;
        // 数据重载后清除已经不存在的展开项。
        _expandedWords.removeWhere((word) => !words.contains(word));
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
    }
  }

  /// App 生命周期变化，对应小程序 App Show/App Hide。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed 表示 App 回到前台。
    if (state == AppLifecycleState.resumed) {
      // 获取恢复时真实时间。
      final resumedAt = DateTime.now();
      // 跨年后重新构建静态列表日期。
      _refreshDateReference(resumedAt);
      // 校准并恢复顶部时钟。
      _startClock(resumedAt);
      // 防止继续执行下面停止逻辑。
      return;
    }
    // 任何非前台状态都停止秒级 Timer。
    _stopClock();
    // 离开前台时停止发音，避免 App 隐藏后继续播。
    unawaited(_stopAudio());
  }

  /// 启动或重启顶部时钟。
  void _startClock([DateTime? currentTime]) {
    // 有旧 Timer 时先取消，确保始终只有一个。
    _clockTimer?.cancel();
    // 没有传入校准值时读取 DateTime.now。
    _now.value = currentTime ?? DateTime.now();
    // 每秒只修改 ValueNotifier，不调用页面 setState。
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // 下划线参数表示不使用 Timer 回调次数。
      _now.value = DateTime.now();
    });
  }

  /// 停止顶部 Timer。
  void _stopClock() {
    // null-safe 取消。
    _clockTimer?.cancel();
    // 明确清空引用。
    _clockTimer = null;
  }

  /// 只有年份变化时才触发整个列表重建。
  void _refreshDateReference(DateTime currentTime) {
    // 同一年直接结束。
    if (_dateReference.year == currentTime.year) return;
    // 跨年后更新参考时间。
    setState(() => _dateReference = currentTime);
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

  /// 点击单词行时切换当前行展开状态。
  void _toggleWord(Word word) {
    // 没有 Meaning 时没有可展开内容，保持列表不动。
    if (word.meanings.isEmpty) return;
    // setState 对应小程序 setData，通知当前列表重新构建。
    setState(() {
      // Set.remove 返回 true 表示这个具体 Word 原本已展开，此时点击就是收起。
      final wasExpanded = _expandedWords.remove(word);
      // 原本没有展开时把当前 Word 对象加入集合；同拼写的其他行不受影响。
      if (!wasExpanded) _expandedWords.add(word);
    });
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
          SnackBar(content: Text('无法播放“${word.spelling}”：$error')),
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

  /// 打开 Material 3 底部设置面板。
  void _openSettings() {
    // Future 在用户关闭面板时结束，首页无需等待其结果。
    unawaited(showAppSettingsSheet(context, _settings));
  }

  /// 将任意异常转换成用户可见的详情，不再只显示笼统失败文案。
  String _describeLoadError(Object error) {
    // toString 会保留 PlatformException code、JSON offset 和 StateError 信息。
    final details = error.toString();
    // 极少数自定义异常可能返回空文本，此时至少显示运行时类型。
    return details.trim().isEmpty ? error.runtimeType.toString() : details;
  }

  /// 页面卸载时释放 Observer、Timer 和 ValueNotifier。
  @override
  void dispose() {
    // 移除 App 生命周期监听。
    WidgetsBinding.instance.removeObserver(this);
    // 停止顶部秒级 Timer。
    _stopClock();
    // 取消尚未执行的搜索防抖。
    _searchDebounce?.cancel();
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
    // 释放局部监听器。
    _now.dispose();
    // 仅释放首页自行创建的测试内存设置；MainApp 注入的全局 Store 继续存在。
    if (_ownsSettings) _settings.dispose();
    // 最后执行父类清理。
    super.dispose();
  }

  /// 根据加载状态选择进度、错误、空状态或高性能列表。
  Widget _buildListContent(List<Word> words) {
    // 数据源尚未返回时显示居中进度圈。
    if (_isLoading) {
      // SizedBox 限定小型进度圈尺寸。
      return const Center(
        // 20×20 避免默认进度圈过大。
        child: SizedBox(
          // 固定宽度。
          width: 20,
          // 固定高度。
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
          // Column 纵向排列标题、详情和重试按钮。
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

    // 数据为空或搜索无匹配时显示空状态。
    if (words.isEmpty) {
      // 空状态占据列表剩余区域中心。
      return Center(
        // 当前统一使用无匹配文案。
        child: Text(
          '未找到匹配的单词',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        // 底部保留 16 像素，列表行和分隔线继续横向贴满屏幕。
        padding: const EdgeInsets.only(bottom: 16),
        // 数据可以一次加载上万条，这里只声明总数量。
        itemCount: words.length,
        // builder 按需构建当前可见 index。
        itemBuilder: (context, index) {
          // 取得当前项，后续属性都复用这个局部变量。
          final word = words[index];
          // 返回当前 Word 对应的可展开、可播放行。
          return WordListTile(
            // ObjectKey 使用对象身份，同 spelling 的多条数据不会冲突。
            key: ObjectKey(word),
            // 传入一次性加载的数据项。
            item: word,
            // 传入静态年份参考。
            dateReference: _dateReference,
            // 根据页面 Set 判断当前行是否展开。
            isExpanded: _expandedWords.contains(word),
            // 只有当前具体对象显示播放动画。
            isPlaying: identical(_playingWord, word),
            // 点击单词文字按当前设置发音。
            onPlay: () => unawaited(_playWord(word)),
            // 点击标题行其他区域切换展开状态。
            onTap: () => _toggleWord(word),
          );
        },
      ),
    );
  }

  /// build 对应小程序 WXML：把当前 State 转成界面树。
  @override
  Widget build(BuildContext context) {
    // 根据最新 query 得到显示数据。
    final words = _visibleWords;

    // 读取列表 surface 和分隔线所需的当前主题。
    final theme = Theme.of(context);

    // Scaffold 是页面根骨架。
    return Scaffold(
      // SafeArea 避开状态栏、刘海和底部手势区。
      body: SafeArea(
        // Column 上方按内容高度，下方 Expanded 占满到屏幕底部。
        child: Column(
          children: [
            // 标题、搜索框和排序栏保留左右 16 边距。
            Padding(
              // 顶部 20、底部 8，让排序栏靠近列表。
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              // 内部垂直排列。
              child: Column(
                // 左对齐标题。
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 只有标题订阅秒级时间。
                  HomeHeader(
                    nowListenable: _now,
                    onSettingsPressed: _openSettings,
                  ),
                  // 标题与搜索框间距。
                  const SizedBox(height: 16),
                  // 固定 40 像素搜索框。
                  WordSearchField(onChanged: _handleSearchChanged),
                  // 搜索与排序之间留 8 像素。
                  const SizedBox(height: 8),
                  // 默认、字母、难度、日期从左到右排列。
                  WordSortBar(
                    selectedField: _sortField,
                    directions: _sortDirections,
                    onSelected: _handleSortSelected,
                  ),
                ],
              ),
            ),
            // 列表占满剩余高度并贴屏左右边缘。
            Expanded(
              // 整个列表容器只有顶部一条外边框。
              child: DecoratedBox(
                // key 供 Widget 测试准确定位。
                key: const Key('word-list'),
                // 使用当前主题 surface 和顶部 Tabler 分隔线。
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: theme.brightness == Brightness.dark
                          ? AppTheme.darkTableBorderColor
                          : AppTheme.tableBorderColor,
                    ),
                  ),
                ),
                // 根据加载状态返回对应内容。
                child: _buildListContent(words),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
