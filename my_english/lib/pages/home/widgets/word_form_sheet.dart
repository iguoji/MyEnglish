// material.dart 提供底部面板、输入框、标签与按钮。
import 'package:flutter/material.dart';
// tabler_icons_plus 统一提供表单内的选择、添加和删除图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 分组模型与 Store 提供表单里的分组选择。
import '../../../models/group.dart';
// Meaning 与 Word 是表单产出的数据模型。
import '../../../models/meaning.dart';
import '../../../models/word.dart';
// 分组 Store 提供当前分组列表。
import '../../../store/group.dart';

///
/// 词性选项列表。
///
/// 前七个为高频词性固定顺序：n. / v. / adj. / adv. / vi. / vt. / vi. vt.，
/// 其余按词库使用频率降序排列。不含 '*'（'*' 表示未选，由取消选择产生）。
/// 该列表作为词性单选区域的固定数据源，UI 横向滑动展示。
///
/// @var `List<String>`
///
const List<String> _kPosOptions = <String>[
  'n.',
  'v.',
  'adj.',
  'adv.',
  'vi.',
  'vt.',
  'vi. vt.',
  'prep.',
  'num.',
  'pron.',
  'conj.',
  'aux.',
  'vlink.',
  'int.',
  'art.',
  'det.',
];

///
/// 词性、含义标签与含义输入框之间的统一纵向距离。
///
/// @var double
///
const double _kMeaningContentGap = 10;

///
/// 表单提交结果：首页据此调用 WordStore 创建或更新。
///
class WordFormResult {
  ///
  /// 创建结果对象。
  ///
  /// @param  String  spelling
  /// @param  `List<Meaning>`  meanings
  /// @param  int?  groupId
  /// @param  bool  continueAdding
  ///
  const WordFormResult({
    required this.spelling,
    required this.meanings,
    required this.groupId,
    required this.continueAdding,
  });

  ///
  /// 整理后的拼写（已去除首尾空格）。
  ///
  /// @var String
  ///
  final String spelling;

  ///
  /// 整理后的 Meaning 列表，index 已按显示顺序编好。
  ///
  /// @var `List<Meaning>`
  ///
  final List<Meaning> meanings;

  ///
  /// 目标分组；null 表示"未分组"。
  ///
  /// @var int?
  ///
  final int? groupId;

  ///
  /// true 表示"提交并继续添加"，面板保持打开。
  ///
  /// @var bool
  ///
  final bool continueAdding;
}

///
/// 弹出全屏添加/编辑单词表单；onSubmit 由首页执行真正的 Store 操作。
///
/// @param  BuildContext  context
/// @param  GroupStore  groups
/// @param  `Future<void> Function(WordFormResult result)`  onSubmit
/// @param  Word?  editing
/// @return `Future<void>`
///
Future<void> showWordFormSheet(
  BuildContext context, {
  required GroupStore groups,
  required Future<void> Function(WordFormResult result) onSubmit,
  Word? editing,
}) {
  // 继续使用 BottomSheet 路由，保留从底部进入及向下拖动关闭的交互。
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // SafeArea 让整屏内容从状态栏、刘海下方开始，与首页顶部位置一致。
    useSafeArea: true,
    // 用户确认保留向下拖动关闭；顶部、取消和系统返回也仍可关闭。
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) =>
        _WordFormSheet(groups: groups, onSubmit: onSubmit, editing: editing),
  );
}

///
/// 表单内部状态：拼写、分组与若干"词性+释义"编辑块。
///
class _WordFormSheet extends StatefulWidget {
  ///
  /// 接收分组 Store、提交回调与可选的被编辑单词。
  ///
  /// @param  GroupStore  groups
  /// @param  `Future<void> Function(WordFormResult result)`  onSubmit
  /// @param  Word?  editing
  ///
  const _WordFormSheet({
    required this.groups,
    required this.onSubmit,
    required this.editing,
  });

  ///
  /// 分组来源。
  ///
  /// @var GroupStore
  ///
  final GroupStore groups;

  ///
  /// 提交回调。
  ///
  /// @var `Future<void> Function(WordFormResult result)`
  ///
  final Future<void> Function(WordFormResult result) onSubmit;

  ///
  /// 非空表示"修改单词"模式。
  ///
  /// @var Word?
  ///
  final Word? editing;

  ///
  /// 创建状态。
  ///
  /// @return `State<_WordFormSheet>`
  ///
  @override
  State<_WordFormSheet> createState() => _WordFormSheetState();
}

///
/// 单个"词性+释义"编辑块的临时数据。
///
class _MeaningDraft {
  ///
  /// 创建编辑块。
  ///
  /// @param  String  pos
  /// @param  `List<String>?`  defs
  ///
  _MeaningDraft({this.pos = 'n.', List<String>? defs})
    : defs = defs ?? <String>[];

  ///
  /// 词性文字。
  ///
  /// @var String
  ///
  String pos;

  ///
  /// 已确认的释义标签。
  ///
  /// @var `List<String>`
  ///
  final List<String> defs;

  ///
  /// 输入框中尚未确认的释义草稿。
  ///
  /// @var String
  ///
  String draft = '';
}

///
/// 表单状态实现。
///
class _WordFormSheetState extends State<_WordFormSheet> {
  ///
  /// 拼写输入控制器；编辑模式带入原拼写。
  ///
  /// @var TextEditingController
  ///
  late final TextEditingController _spelling;

  ///
  /// 当前选择的分组；null 表示"未分组"。
  ///
  /// @var int?
  ///
  int? _groupId;

  ///
  /// 全部"词性+释义"编辑块。
  ///
  /// @var `List<_MeaningDraft>`
  ///
  late final List<_MeaningDraft> _meanings;

  ///
  /// 每个编辑块的释义草稿输入控制器，与 _meanings 一一对应。
  ///
  /// @var `List<TextEditingController>`
  ///
  final List<TextEditingController> _draftControllers =
      <TextEditingController>[];

  ///
  /// 初始化：编辑模式回填数据，新增模式给一个空块。
  ///
  /// @return void
  ///
  @override
  void initState() {
    // 保留父类初始化。
    super.initState();
    // 读取可能存在的被编辑单词。
    final editing = widget.editing;
    // 拼写回填。
    _spelling = TextEditingController(text: editing?.spelling ?? '');
    // 分组回填；方案 A 下单词可能跨多组，但表单只展示首个分组（编辑时取其第一个）。
    // 新增默认"未分组"（_groupId 为 null）。
    _groupId = editing?.groupIds.firstOrNull;
    // Meaning 回填：把模型转换为可编辑草稿。
    _meanings = editing != null && editing.meanings.isNotEmpty
        ? editing.meanings
              .map(
                (meaning) => _MeaningDraft(
                  pos: meaning.pos,
                  defs: List<String>.of(meaning.definitions),
                ),
              )
              .toList()
        : <_MeaningDraft>[_MeaningDraft()];
    // 为每个编辑块准备草稿控制器。
    for (var index = 0; index < _meanings.length; index += 1) {
      _draftControllers.add(TextEditingController());
    }
  }

  ///
  /// 释放全部输入控制器。
  ///
  /// @return void
  ///
  @override
  void dispose() {
    // 拼写控制器。
    _spelling.dispose();
    // 每个草稿控制器。
    for (final controller in _draftControllers) {
      controller.dispose();
    }
    // 父类清理。
    super.dispose();
  }

  ///
  /// 把第 index 块草稿转正为释义标签。
  ///
  /// @param  int  index
  /// @return void
  ///
  void _commitDraft(int index) {
    // 去除首尾空格。
    final value = _meanings[index].draft.trim();
    // 空草稿忽略。
    if (value.isEmpty) return;
    // setState 更新标签与清空输入框。
    setState(() {
      _meanings[index].defs.add(value);
      _meanings[index].draft = '';
      _draftControllers[index].clear();
    });
  }

  ///
  /// 汇总当前表单为提交结果；拼写为空时返回 null。
  ///
  /// @param  bool  continueAdding
  /// @return WordFormResult?
  ///
  WordFormResult? _buildResult(bool continueAdding) {
    // 拼写必填。
    final spelling = _spelling.text.trim();
    if (spelling.isEmpty) return null;
    // 逐块转换成 Meaning；未确认草稿一并计入，与设计稿一致。
    final drafts = <_MeaningDraft>[];
    for (final meaning in _meanings) {
      // 复制并附加草稿。
      final defs = <String>[
        ...meaning.defs.map((d) => d.trim()),
        meaning.draft.trim(),
      ].where((d) => d.isNotEmpty).toList();
      // 词性和释义都为空的块直接丢弃。
      if (meaning.pos.trim().isEmpty && defs.isEmpty) continue;
      drafts.add(_MeaningDraft(pos: meaning.pos.trim(), defs: defs));
    }
    // 模型按 index 从大到小显示；第一块给最大 index 保证顺序不变。
    final meanings = <Meaning>[
      for (var index = 0; index < drafts.length; index += 1)
        Meaning(
          index: drafts.length - index,
          pos: drafts[index].pos,
          definitions: drafts[index].defs,
        ),
    ];
    // 汇总提交结果；表单只选一个分组，这里把单值转成单元素列表（null 表示未分组）。
    // 方案 A 的 groupMember 多对多允许跨组，但表单提交语义是"整体归属到某一组"。
    return WordFormResult(
      spelling: spelling,
      meanings: meanings,
      groupId: _groupId,
      continueAdding: continueAdding,
    );
  }

  ///
  /// 执行提交；continueAdding 为 true 时清空表单继续添加。
  ///
  /// @param  bool  continueAdding
  /// @return `Future<void>`
  ///
  Future<void> _submit(bool continueAdding) async {
    // 组装结果；拼写为空时静默忽略（按钮也已用透明度提示）。
    final result = _buildResult(continueAdding);
    if (result == null) return;
    // 交给首页执行 Store 操作。
    await widget.onSubmit(result);
    // 提交期间面板可能已被关闭。
    if (!mounted) return;
    // 提交并继续：清空拼写与释义，保留分组选择。
    if (continueAdding && widget.editing == null) {
      setState(() {
        _spelling.clear();
        _meanings
          ..clear()
          ..add(_MeaningDraft());
        for (final controller in _draftControllers) {
          controller.dispose();
        }
        _draftControllers
          ..clear()
          ..add(TextEditingController());
      });
      return;
    }
    // 普通提交：关闭面板。
    Navigator.of(context).pop();
  }

  ///
  /// 输出完整表单面板。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 是否处于编辑模式。
    final isEditing = widget.editing != null;
    // 拼写为空时提交按钮半透明。
    final canSubmit = _spelling.text.trim().isNotEmpty;

    // 键盘弹出时缩短表单可用高度，让底部操作栏停在键盘上方而不是被遮住。
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        key: const Key('word-form-surface'),
        color: tokens.card,
        // 恢复旧版底部弹层的顶部圆角；底部贴紧屏幕，因此只处理上面两个角。
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        // 裁掉圆角之外的标题栏背景，让透明路由露出真正的圆弧。
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          // BottomSheet 路由已经避开顶部安全区，这里占满剩余全部屏幕。
          height: MediaQuery.sizeOf(context).height,
          child: Column(
            children: [
              // 固定顶部：位置、边距和首页问候语/汉堡按钮保持一致。
              _buildHeader(tokens, isEditing),
              // 中部单独滚动；页面背景使用首页顶部非列表区域的 page 颜色。
              Expanded(
                child: ColoredBox(
                  key: const Key('word-form-body'),
                  color: tokens.page,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 第一部分：分组与单词两列白色卡片。
                        _buildPrimaryCard(tokens),
                        const SizedBox(height: 18),
                        // 第二部分：词性与含义组。
                        Text(
                          '词性与含义',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 9),
                        for (
                          var index = 0;
                          index < _meanings.length;
                          index += 1
                        ) ...[
                          if (index > 0) const SizedBox(height: 10),
                          _buildMeaningCard(tokens, index),
                        ],
                        const SizedBox(height: 12),
                        // 第三部分：透明底、虚线边框的大号新增按钮。
                        _buildAddMeaningButton(tokens),
                      ],
                    ),
                  ),
                ),
              ),
              // 固定底部：按钮不随中部内容滚动。
              _buildFooter(tokens, isEditing, canSubmit),
            ],
          ),
        ),
      ),
    );
  }

  ///
  /// 构建与首页顶部左右位置一致的标题栏。
  ///
  /// @param  AppTokens  tokens
  /// @param  bool  isEditing
  /// @return Widget
  ///
  Widget _buildHeader(AppTokens tokens, bool isEditing) {
    // 白色标题栏固定在顶部，不跟随表单内容滚动。
    return Container(
      key: const Key('word-form-header'),
      color: tokens.card,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题占据关闭按钮之外的剩余宽度。
          Expanded(
            child: Text(
              isEditing ? '编辑单词' : '添加单词',
              style: TextStyle(
                color: tokens.text,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 40×40 点击区与首页汉堡按钮尺寸一致，图标靠右对齐。
          Semantics(
            button: true,
            label: '关闭单词表单',
            child: InkWell(
              key: const Key('form-close'),
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(TablerIcons.x, size: 20, color: tokens.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 构建分组与单词输入的首张白色卡片。
  ///
  /// @param  AppTokens  tokens
  /// @return Widget
  ///
  Widget _buildPrimaryCard(AppTokens tokens) {
    return Container(
      key: const Key('word-form-primary-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.rowBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分组较窄，占两份宽度。
          Expanded(flex: 2, child: _buildGroupField(tokens)),
          const SizedBox(width: 12),
          // 单词输入较宽，占三份宽度。
          Expanded(flex: 3, child: _buildSpellingField(tokens)),
        ],
      ),
    );
  }

  ///
  /// 构建带 Label 的分组下拉字段。
  ///
  /// @param  AppTokens  tokens
  /// @return Widget
  ///
  Widget _buildGroupField(AppTokens tokens) {
    return Column(
      key: const Key('form-group-field'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(text: '分组', color: tokens.textSecondary),
        const SizedBox(height: 7),
        PopupMenuButton<int>(
          key: const Key('form-group-button'),
          position: PopupMenuPosition.under,
          offset: const Offset(0, 4),
          tooltip: '选择分组',
          // 选中后更新表单分组；0 代表“未分组”。
          onSelected: (value) => setState(() {
            _groupId = value == GroupStore.ungroupedId ? null : value;
          }),
          itemBuilder: (context) {
            // 当前生效的分组 id（未分组用 0 表示）。
            final current = _groupId ?? GroupStore.ungroupedId;
            return [
              for (final option in [
                const WordGroup(
                  id: GroupStore.ungroupedId,
                  name: GroupStore.ungroupedName,
                ),
                ...widget.groups.groups,
              ])
                PopupMenuItem<int>(
                  value: option.id,
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: option.id == current
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: option.id == current
                                ? AppTokens.accent
                                : tokens.text,
                          ),
                        ),
                      ),
                      if (option.id == current)
                        const Icon(
                          TablerIcons.check,
                          size: 14,
                          color: AppTokens.accent,
                        ),
                    ],
                  ),
                ),
            ];
          },
          // 下拉字段使用卡片同色背景，不再使用原来的灰色填充。
          child: Container(
            key: const Key('form-group-input'),
            height: 44,
            // 左侧不再二次缩进，使分组值与上方 Label 共用同一条对齐线。
            padding: const EdgeInsets.only(right: 11),
            decoration: BoxDecoration(
              color: tokens.card,
              // 分组控件只保留下边线，与右侧单词输入框使用相同结构。
              border: Border(bottom: BorderSide(color: tokens.inputBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.groups.byId(_groupId)?.name ??
                        GroupStore.ungroupedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMedium,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  TablerIcons.chevronDown,
                  size: 14,
                  color: tokens.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建带 Label 的单词输入字段。
  ///
  /// @param  AppTokens  tokens
  /// @return Widget
  ///
  Widget _buildSpellingField(AppTokens tokens) {
    return Column(
      key: const Key('form-spelling-field'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(text: '单词', color: tokens.textSecondary),
        const SizedBox(height: 7),
        Container(
          key: const Key('form-spelling-input'),
          height: 44,
          decoration: BoxDecoration(
            // 与分组控件共用相同高度的外层下边线，避免 TextField 自身布局造成错位。
            border: Border(bottom: BorderSide(color: tokens.inputBorder)),
          ),
          // 左侧不再二次缩进；右侧保留输入余量，纵向位置交给 Align 精确居中。
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Align(
              key: const Key('form-spelling-alignment'),
              alignment: Alignment.center,
              child: TextField(
                key: const Key('form-spelling'),
                controller: _spelling,
                onChanged: (value) => setState(() {}),
                // 单词只能输入一行，外层容器负责统一 44 像素高度。
                maxLines: 1,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(color: tokens.text, fontSize: 15, height: 1.2),
                // collapsed 不附带 Material 输入框默认的上下留白，文字由外层垂直居中。
                decoration: InputDecoration.collapsed(
                  hintText: '输入单词拼写',
                  hintStyle: TextStyle(
                    color: tokens.muted,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建透明背景的虚线“添加一组词性与含义”按钮。
  ///
  /// @param  AppTokens  tokens
  /// @return Widget
  ///
  Widget _buildAddMeaningButton(AppTokens tokens) {
    return _DashedBorder(
      color: tokens.check,
      radius: 8,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('add-meaning'),
          onTap: () => setState(() {
            _meanings.add(_MeaningDraft());
            _draftControllers.add(TextEditingController());
          }),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              // WidgetSpan 按文字中线放置加号，避免图标盒与字体基线不同造成视觉错位。
              child: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: Icon(
                          TablerIcons.plus,
                          key: const Key('add-meaning-icon'),
                          size: 17,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    const TextSpan(text: '添加一组词性与含义'),
                  ],
                ),
                key: const Key('add-meaning-label'),
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  ///
  /// 删除指定的词性与含义组。
  ///
  /// @param  int  index
  /// @return void
  ///
  void _removeMeaning(int index) {
    setState(() {
      // 先删除对应的数据草稿。
      _meanings.removeAt(index);
      // 再释放并删除同位置的输入控制器，保持两个列表始终一一对应。
      _draftControllers.removeAt(index).dispose();
    });
  }

  ///
  /// 构建不会撑高词性行的固定尺寸删除按钮。
  ///
  /// @param  int  index
  /// @return Widget
  ///
  Widget _buildMeaningDeleteButton(int index) {
    return Tooltip(
      message: '删除词性',
      child: Semantics(
        button: true,
        label: '删除第 ${index + 1} 组词性与含义',
        child: InkWell(
          key: Key('meaning-delete-$index'),
          onTap: () => _removeMeaning(index),
          borderRadius: BorderRadius.circular(6),
          child: const SizedBox(
            width: 30,
            height: 30,
            child: Icon(TablerIcons.trash, size: 17, color: AppTokens.danger),
          ),
        ),
      ),
    );
  }

  ///
  /// 构建固定在屏幕底部的表单操作栏。
  ///
  /// @param  AppTokens  tokens
  /// @param  bool  isEditing
  /// @param  bool  canSubmit
  /// @return Widget
  ///
  Widget _buildFooter(AppTokens tokens, bool isEditing, bool canSubmit) {
    return Container(
      key: const Key('word-form-footer'),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: _FormButton(
                key: const Key('form-cancel'),
                label: '取消',
                background: Colors.transparent,
                foreground: tokens.textMedium,
                border: tokens.inputBorder,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Opacity(
                opacity: canSubmit ? 1 : 0.45,
                child: _FormButton(
                  key: const Key('form-submit'),
                  label: isEditing ? '保存' : '添加',
                  background: AppTokens.accent,
                  foreground: Colors.white,
                  onTap: () => _submit(false),
                ),
              ),
            ),
            if (!isEditing) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Opacity(
                  opacity: canSubmit ? 1 : 0.45,
                  child: _FormButton(
                    key: const Key('form-submit-continue'),
                    label: '提交并继续',
                    background: Colors.transparent,
                    foreground: AppTokens.accent,
                    border: AppTokens.accent,
                    onTap: () => _submit(true),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ///
  /// 构建第 index 个"词性+释义"编辑卡。
  ///
  /// @param  AppTokens  tokens
  /// @param  int  index
  /// @return Widget
  ///
  Widget _buildMeaningCard(AppTokens tokens, int index) {
    // 当前编辑块。
    final meaning = _meanings[index];
    // Azure 标签在深色背景上提高透明度和文字亮度，保持两个主题都清晰。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final azureBackground = isDark
        ? const Color(0x3345AAF2)
        : const Color(0x1A45AAF2);
    final azureForeground = isDark
        ? const Color(0xFF45AAF2)
        : const Color(0xFF2B94D4);
    // 圆角描边卡片。
    return Container(
      key: Key('meaning-card-$index'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.rowBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行固定为 30 高，删除图标出现与否都不会改变上下位置。
          SizedBox(
            key: Key('meaning-pos-row-$index'),
            height: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 词性单选区：占满剩余宽度，可横向滑动。
                Expanded(
                  child: _PosSelector(
                    tokens: tokens,
                    // 当前选中的词性；空字符串表示未选。
                    selected: meaning.pos,
                    // 点击词性：再次点击已选项则取消选择(置空)，否则选中。
                    onSelect: (pos) => setState(() {
                      meaning.pos = meaning.pos == pos ? '' : pos;
                    }),
                  ),
                ),
                // 只剩一个块时保留必需的基础录入区，不显示删除动作。
                if (_meanings.length > 1) ...[
                  const SizedBox(width: 8),
                  _buildMeaningDeleteButton(index),
                ],
              ],
            ),
          ),
          // 词性行与下一项始终保持统一距离。
          const SizedBox(height: _kMeaningContentGap),
          // 已确认释义标签区域。
          if (meaning.defs.isNotEmpty) ...[
            Wrap(
              key: Key('meaning-tags-$index'),
              spacing: 6,
              runSpacing: 6,
              children: [
                for (
                  var defIndex = 0;
                  defIndex < meaning.defs.length;
                  defIndex += 1
                )
                  Container(
                    key: Key('meaning-tag-$index-$defIndex'),
                    padding: const EdgeInsets.fromLTRB(10, 5, 9, 5),
                    decoration: BoxDecoration(
                      // 已确认含义统一使用 Tabler Azure 浅色徽章。
                      color: azureBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 释义文字。
                        Text(
                          meaning.defs[defIndex],
                          style: TextStyle(
                            color: azureForeground,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 删除该释义标签。
                        GestureDetector(
                          onTap: () => setState(() {
                            meaning.defs.removeAt(defIndex);
                          }),
                          child: Icon(
                            TablerIcons.x,
                            color: azureForeground,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            // 含义标签与输入框使用同一纵向距离。
            const SizedBox(height: _kMeaningContentGap),
          ],
          // 释义草稿输入 + 添加按钮的组合行。
          Container(
            key: Key('meaning-input-$index'),
            height: 36,
            decoration: BoxDecoration(
              border: Border.all(color: tokens.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              // 纵向拉伸让"添加"按钮贴满整行高度。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 草稿输入框。
                Expanded(
                  child: TextField(
                    key: Key('meaning-draft-$index'),
                    controller: _draftControllers[index],
                    onChanged: (value) => meaning.draft = value,
                    // 回车等同点击"添加"。
                    onSubmitted: (value) => _commitDraft(index),
                    // expands 撑满 36 高容器，否则文字偏上、边框错位。
                    expands: true,
                    // expands 为 true 时 maxLines 必须为 null。
                    maxLines: null,
                    // 文字在撑满的高度内垂直居中。
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 13.5,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '输入含义，回车或点添加',
                      hintStyle: TextStyle(
                        color: tokens.muted,
                        fontSize: 13.5,
                        height: 1.2,
                      ),
                      border: InputBorder.none,
                      // 清空垂直内边距，由 36 高容器 + 居中控制。
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                    ),
                  ),
                ),
                // 右侧"添加"按钮。
                InkWell(
                  key: Key('meaning-add-$index'),
                  onTap: () => _commitDraft(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.sub,
                      border: Border(
                        left: BorderSide(color: tokens.inputBorder),
                      ),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(7),
                      ),
                    ),
                    child: const Text(
                      '添加',
                      style: TextStyle(
                        color: AppTokens.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

///
/// 词性单选横向滑动区。
///
/// 按 [_kPosOptions] 顺序横向排列所有词性选项，点击即选中；
/// 选中项使用实心主题主色与高对比文字，未选中项使用普通边框与次要文字。
/// 区域可横向滑动，避免词性过多时溢出。
///
class _PosSelector extends StatelessWidget {
  ///
  /// 接收设计令牌、当前选中词性与选择回调。
  ///
  /// @param  AppTokens  tokens
  /// @param  String  selected
  /// @param  `void Function(String pos)`  onSelect
  ///
  const _PosSelector({
    required this.tokens,
    required this.selected,
    required this.onSelect,
  });

  ///
  /// 设计令牌，用于读取颜色。
  ///
  /// @var AppTokens
  ///
  final AppTokens tokens;

  ///
  /// 当前选中的词性文字；'*' 表示未选。
  ///
  /// @var String
  ///
  final String selected;

  ///
  /// 点击词性选项后的回调。
  ///
  /// @var `void Function(String pos)`
  ///
  final void Function(String pos) onSelect;

  ///
  /// 输出 30 高的可横向滑动词性胶囊列表。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView +横向滚动 让词性列表超出宽度时可滑动。
    return SizedBox(
      // 在原 34 高基础上，上下各减少 2 像素留白，最终高度为 30。
      height: 30,
      child: SingleChildScrollView(
        // 横向滚动。
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 选项之间的间距通过 Padding 包裹实现。
            for (var i = 0; i < _kPosOptions.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _PosChip(
                tokens: tokens,
                label: _kPosOptions[i],
                isSelected: _kPosOptions[i] == selected,
                onTap: () => onSelect(_kPosOptions[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

///
/// 单个词性选项 Chip。
///
class _PosChip extends StatelessWidget {
  ///
  /// 接收设计令牌、文案、是否选中与点击回调。
  ///
  /// @param  AppTokens  tokens
  /// @param  String  label
  /// @param  bool  isSelected
  /// @param  VoidCallback  onTap
  ///
  const _PosChip({
    required this.tokens,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  ///
  /// 设计令牌。
  ///
  /// @var AppTokens
  ///
  final AppTokens tokens;

  ///
  /// 词性文字。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 是否选中。
  ///
  /// @var bool
  ///
  final bool isSelected;

  ///
  /// 点击回调。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 输出圆角描边 Chip。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 从当前主题读取 primary，深色模式会自动得到对应的主色和前景色。
    final colorScheme = Theme.of(context).colorScheme;

    // InkWell 提供点击反馈。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        key: Key('pos-chip-$label'),
        // 左右在原 13 像素基础上各增加 3 像素；高度由外层 30 统一约束。
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 选中项使用实心主题主色，未选中项保持透明。
          color: isSelected ? colorScheme.primary : Colors.transparent,
          // 选中项用主色描边，未选中用输入框边框色。
          border: Border.all(
            color: isSelected ? colorScheme.primary : tokens.inputBorder,
          ),
          // 半高 15 像素圆角形成左右完整圆弧的胶囊外观。
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          // 词性统一使用小写显示；即使旧选项数据含大写，也在展示层归一化。
          label.toLowerCase(),
          style: TextStyle(
            // 实心主色上的文字使用 onPrimary，确保明暗主题中都有足够对比度。
            color: isSelected ? colorScheme.onPrimary : tokens.textSecondary,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

///
/// 表单字段上方的统一 Label。
///
class _FormLabel extends StatelessWidget {
  ///
  /// 创建字段 Label。
  ///
  /// @param  String  text
  /// @param  Color  color
  ///
  const _FormLabel({required this.text, required this.color});

  ///
  /// Label 文字。
  ///
  /// @var String
  ///
  final String text;

  ///
  /// Label 颜色。
  ///
  /// @var Color
  ///
  final Color color;

  ///
  /// 输出位于输入框上一行的小标题。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

///
/// 使用 CustomPainter 绘制圆角虚线边框，不引入额外第三方依赖。
///
class _DashedBorder extends StatelessWidget {
  ///
  /// 创建包裹任意子组件的虚线边框。
  ///
  /// @param  Widget  child
  /// @param  Color  color
  /// @param  double  radius
  ///
  const _DashedBorder({
    required this.child,
    required this.color,
    required this.radius,
  });

  ///
  /// 边框内部内容。
  ///
  /// @var Widget
  ///
  final Widget child;

  ///
  /// 虚线颜色。
  ///
  /// @var Color
  ///
  final Color color;

  ///
  /// 圆角半径。
  ///
  /// @var double
  ///
  final double radius;

  ///
  /// 把虚线绘制在子组件上层，避免点击水波纹覆盖边框。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

///
/// 沿圆角矩形路径逐段绘制虚线。
///
class _DashedBorderPainter extends CustomPainter {
  ///
  /// 创建虚线画笔。
  ///
  /// @param  Color  color
  /// @param  double  radius
  ///
  const _DashedBorderPainter({required this.color, required this.radius});

  ///
  /// 边框颜色。
  ///
  /// @var Color
  ///
  final Color color;

  ///
  /// 圆角半径。
  ///
  /// @var double
  ///
  final double radius;

  ///
  /// 在组件边缘绘制 6 像素实线和 4 像素空白交替的路径。
  ///
  /// @param  Canvas  canvas
  /// @param  Size  size
  /// @return void
  ///
  @override
  void paint(Canvas canvas, Size size) {
    // 半个线宽内缩，避免边框边缘被画布裁掉。
    final rect = (Offset.zero & size).deflate(0.5);
    // PathMetric 可以沿整个圆角矩形按距离提取短路径。
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 10;
      }
    }
  }

  ///
  /// 颜色或圆角改变时才要求 Flutter 重绘边框。
  ///
  /// @param  _DashedBorderPainter  oldDelegate
  /// @return bool
  ///
  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

///
/// 表单底部的统一按钮样式。
///
class _FormButton extends StatelessWidget {
  ///
  /// 接收文案、配色与动作。
  ///
  /// @param  String  label
  /// @param  Color  background
  /// @param  Color  foreground
  /// @param  VoidCallback  onTap
  /// @param  Color?  border
  /// @param  Key?  key
  ///
  const _FormButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
    super.key,
  });

  ///
  /// 按钮文字。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 背景色。
  ///
  /// @var Color
  ///
  final Color background;

  ///
  /// 文字颜色。
  ///
  /// @var Color
  ///
  final Color foreground;

  ///
  /// 可选边框色。
  ///
  /// @var Color?
  ///
  final Color? border;

  ///
  /// 点击动作。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 输出 40 高圆角按钮。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // InkWell 提供点击反馈。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: border == null ? null : Border.all(color: border!),
          borderRadius: BorderRadius.circular(8),
        ),
        // FittedBox 只在窄屏或大字体确实放不下时缩小，避免按钮文字越界。
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
