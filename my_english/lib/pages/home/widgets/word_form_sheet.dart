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
/// 弹出添加/修改单词表单；onSubmit 由首页执行真正的 Store 操作。
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
  // isScrollControlled 让面板可随键盘上移并占据更大高度。
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
  _MeaningDraft({this.pos = '', List<String>? defs})
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

    // Padding 让面板跟随键盘上移。
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // 顶部圆角卡片容器。
      child: Container(
        constraints: BoxConstraints(
          // 最高占屏 84% 与设计稿一致。
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 面板标题。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                isEditing ? '修改单词' : '添加单词',
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 表单主体可滚动。
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 分组选择 + 拼写输入的组合输入行。
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: tokens.inputBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        // 纵向拉伸让左侧分组块与右侧输入框贴满整行高度。
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 左侧分组选择块，点击弹出分组菜单。
                          PopupMenuButton<int>(
                            key: const Key('form-group-button'),
                            position: PopupMenuPosition.under,
                            offset: const Offset(0, 4),
                            tooltip: '选择分组',
                            // 选中后更新表单分组；0 代表"未分组"。
                            onSelected: (value) => setState(() {
                              _groupId = value == GroupStore.ungroupedId
                                  ? null
                                  : value;
                            }),
                            // 未分组 + 全部自定义分组。
                            itemBuilder: (context) {
                              // 当前生效的分组 id（未分组用 0 表示）。
                              final current =
                                  _groupId ?? GroupStore.ungroupedId;
                              // 组装菜单项。
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
                                    height: 38,
                                    child: Row(
                                      children: [
                                        // 分组名称；当前项主色加粗。
                                        Text(
                                          option.name,
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
                                        const Spacer(),
                                        // 当前项显示 Tabler 勾选图标。
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
                            // 常驻外观：分组名 + Tabler 下拉图标，浅色底与右侧竖线分隔。
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.sub,
                                border: Border(
                                  right: BorderSide(color: tokens.inputBorder),
                                ),
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(7),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 当前分组名称。
                                  Text(
                                    widget.groups.byId(_groupId)?.name ??
                                        GroupStore.ungroupedName,
                                    style: TextStyle(
                                      color: tokens.textMedium,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // 使用 Tabler 下拉箭头，不再显示文字三角符号。
                                  Icon(
                                    TablerIcons.chevronDown,
                                    size: 14,
                                    color: tokens.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 拼写输入占剩余宽度。
                          Expanded(
                            child: TextField(
                              key: const Key('form-spelling'),
                              controller: _spelling,
                              // 输入变化刷新提交按钮透明度。
                              onChanged: (value) => setState(() {}),
                              // expands 让输入框撑满父容器（Row 纵向拉伸出的 40 高），
                              // 否则输入框只会取自身内容高度，文字被压在顶部且边框错位。
                              expands: true,
                              // expands 为 true 时 maxLines/minLines 必须为 null，
                              // 输入框改为撑满父高度（仍为单行输入）。
                              maxLines: null,
                              // 文字在撑满的高度内垂直居中。
                              textAlignVertical: TextAlignVertical.center,
                              style: TextStyle(
                                color: tokens.text,
                                fontSize: 15,
                                // 1.2 行高让字形在输入框内视觉居中。
                                height: 1.2,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '输入单词拼写',
                                hintStyle: TextStyle(
                                  color: tokens.muted,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                                border: InputBorder.none,
                                // 清空默认垂直内边距，居中完全交给固定高度
                                // 与 textAlignVertical，避免文字被压到偏上。
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 与释义区域的间距。
                    const SizedBox(height: 14),
                    // 释义区域小标题。
                    Text(
                      '词性与含义',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 逐块渲染"词性+释义"编辑卡。
                    for (
                      var index = 0;
                      index < _meanings.length;
                      index += 1
                    ) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _buildMeaningCard(tokens, index),
                    ],
                    const SizedBox(height: 8),
                    // 添加词性虚线按钮。
                    InkWell(
                      key: const Key('add-meaning'),
                      onTap: () => setState(() {
                        _meanings.add(_MeaningDraft());
                        _draftControllers.add(TextEditingController());
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.check),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              TablerIcons.plus,
                              size: 15,
                              color: tokens.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '添加词性',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部按钮行。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  // 取消按钮。
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
                  // 添加/保存主按钮。
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
                  // 编辑模式没有"提交并继续添加"。
                  if (!isEditing) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      // 设计稿此按钮更宽。
                      flex: 2,
                      child: Opacity(
                        opacity: canSubmit ? 1 : 0.45,
                        child: _FormButton(
                          key: const Key('form-submit-continue'),
                          label: '提交并继续添加',
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
    // 圆角描边卡片。
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.rowBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：词性单选横向滑动区 + 删除块按钮。
          Row(
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
              // 只剩一个块时不显示删除。
              if (_meanings.length > 1)
                IconButton(
                  onPressed: () => setState(() {
                    _meanings.removeAt(index);
                    _draftControllers.removeAt(index).dispose();
                  }),
                  icon: Icon(TablerIcons.x, size: 16, color: tokens.muted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  tooltip: '删除词性',
                ),
            ],
          ),
          // 已确认释义标签区域。
          if (meaning.defs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (
                  var defIndex = 0;
                  defIndex < meaning.defs.length;
                  defIndex += 1
                )
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 9, 5),
                    decoration: BoxDecoration(
                      color: tokens.sub,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 释义文字。
                        Text(
                          meaning.defs[defIndex],
                          style: TextStyle(
                            color: tokens.textMedium,
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
                            color: tokens.muted,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // 释义草稿输入 + 添加按钮的组合行。
          Container(
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
/// 选中项使用主色描边+主色文字，未选中项使用普通边框+次要文字。
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
  /// 输出 23 高的可横向滑动词性 Chip 列表（原 34 缩小三分之一）。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView +横向滚动 让词性列表超出宽度时可滑动。
    return SizedBox(
      // 高度从 34 缩小三分之一到 23。
      height: 23,
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
    // InkWell 提供点击反馈。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        // 横向 8 纵向 0 内边距，高度由外层 23 控制。
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 选中项用浅主色背景，未选中用透明。
          color: isSelected ? const Color(0x1A206BC4) : Colors.transparent,
          // 选中项用主色描边，未选中用输入框边框色。
          border: Border.all(
            color: isSelected ? AppTokens.accent : tokens.inputBorder,
          ),
          // 圆角缩小到 6 匹配更小的高度。
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          // 词性统一使用小写显示；即使旧选项数据含大写，也在展示层归一化。
          label.toLowerCase(),
          style: TextStyle(
            // 选中项主色加粗，未选中次要色常规。
            color: isSelected ? AppTokens.accent : tokens.textSecondary,
            // 字号从 13 缩小到 11.5 匹配 23 高度。
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
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
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
