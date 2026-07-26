// dart:async 提供 unawaited，让按钮回调启动异步保存而不丢失错误处理。
import 'dart:async';

// material.dart 提供底部面板、分段按钮和主题颜色。
import 'package:flutter/material.dart';

// 设置 Store 位于页面目录之外，其他页面可以直接复用。
import '../../../store/settings.dart';

/// 从当前页面底部弹出设置面板。
Future<void> showAppSettingsSheet(
  BuildContext context,
  SettingsStore settings,
) {
  // showModalBottomSheet 提供 Material 3 标准底部进入动画和背景遮罩。
  return showModalBottomSheet<void>(
    // 使用当前首页 Navigator。
    context: context,
    // 顶部显示 Material 3 拖动把手。
    showDragHandle: true,
    // 避开左右与底部系统手势区域。
    useSafeArea: true,
    // 内容高度由两项设置自然决定。
    isScrollControlled: false,
    // builder 创建真正设置内容。
    builder: (sheetContext) => _SettingsSheet(settings: settings),
  );
}

/// 设置面板需要保存“正在写入”状态，所以使用 StatefulWidget。
class _SettingsSheet extends StatefulWidget {
  /// 接收全局唯一设置 Store。
  const _SettingsSheet({required this.settings});

  /// 所有修改直接写入该 Store 并持久化。
  final SettingsStore settings;

  /// 创建局部状态。
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

/// 控制保存期间禁用重复操作。
class _SettingsSheetState extends State<_SettingsSheet> {
  /// true 表示某项设置正在等待 Android 磁盘确认。
  bool _isSaving = false;

  /// 保存口音并把失败原因显示在当前页面。
  Future<void> _setAccent(PronunciationAccent value) async {
    // 已经保存中时忽略新的并发点击。
    if (_isSaving) return;
    // 先禁用两个分段控件。
    setState(() => _isSaving = true);
    try {
      // 等待 SharedPreferences commit 完成。
      await widget.settings.setAccent(value);
    } catch (error) {
      // 页面仍存在时显示具体错误。
      if (mounted) _showSaveError(error);
    } finally {
      // 面板可能已被用户下滑关闭，只有 mounted 时才恢复 UI。
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 保存主题；成功后 MaterialApp 会立即重建为新主题。
  Future<void> _setTheme(AppThemePreference value) async {
    // 阻止重复磁盘写入。
    if (_isSaving) return;
    // 进入保存状态。
    setState(() => _isSaving = true);
    try {
      // 等待原生确认持久化。
      await widget.settings.setTheme(value);
    } catch (error) {
      // 失败时保留原主题并通知用户。
      if (mounted) _showSaveError(error);
    } finally {
      // 恢复两个控件。
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 统一显示设置保存错误。
  void _showSaveError(Object error) {
    // 先移除上一条提示，避免快速失败时叠加队列。
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // SnackBar 不打断用户当前设置操作。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('设置保存失败：$error')));
  }

  /// 输出标题和两行分段设置。
  @override
  Widget build(BuildContext context) {
    // ListenableBuilder 让 Store 成功修改后只刷新面板内容。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: widget.settings,
      // 根据最新口音和主题重新构建。
      builder: (context, child) {
        // Padding 给底部内容稳定边距。
        return Padding(
          // 底部额外 24 像素，避免贴近系统手势区。
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          // Column 只占实际高度。
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题行包含设置名称和关闭图标。
              Row(
                children: [
                  // 标题占据剩余宽度。
                  Expanded(
                    child: Text(
                      '设置',
                      // 使用 Material 3 页面标题样式。
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  // 熟悉的关闭图标比文字按钮更紧凑。
                  IconButton(
                    // 关闭当前 BottomSheet 路由。
                    onPressed: () => Navigator.of(context).pop(),
                    // 使用标准关闭符号。
                    icon: const Icon(Icons.close_rounded),
                    // 长按或鼠标悬停时说明用途。
                    tooltip: '关闭',
                  ),
                ],
              ),
              // 标题和第一项之间留白。
              const SizedBox(height: 12),
              // 发音口音一行。
              _SettingRow(
                label: '发音',
                control: SegmentedButton<PronunciationAccent>(
                  // 两个互斥选项。
                  segments: PronunciationAccent.values
                      .map(
                        (accent) => ButtonSegment<PronunciationAccent>(
                          value: accent,
                          label: Text(accent.label),
                        ),
                      )
                      .toList(growable: false),
                  // Set 只有当前一个选中值。
                  selected: <PronunciationAccent>{widget.settings.accent},
                  // 保存期间传 null 会禁用控件。
                  onSelectionChanged: _isSaving
                      ? null
                      : (selection) => unawaited(_setAccent(selection.first)),
                  // 不允许取消全部选项。
                  emptySelectionAllowed: false,
                  // 只有两个值，不允许多选。
                  multiSelectionEnabled: false,
                ),
              ),
              // 两项之间使用主题分隔线，不嵌套卡片。
              const Divider(height: 32),
              // 主题一行。
              _SettingRow(
                label: '主题',
                control: SegmentedButton<AppThemePreference>(
                  // Light 与 Dark 两个互斥选项。
                  segments: AppThemePreference.values
                      .map(
                        (theme) => ButtonSegment<AppThemePreference>(
                          value: theme,
                          label: Text(theme.label),
                        ),
                      )
                      .toList(growable: false),
                  // 当前持久化主题。
                  selected: <AppThemePreference>{widget.settings.theme},
                  // 保存期间禁用。
                  onSelectionChanged: _isSaving
                      ? null
                      : (selection) => unawaited(_setTheme(selection.first)),
                  // 始终保留一个主题。
                  emptySelectionAllowed: false,
                  // 不允许同时选择两种主题。
                  multiSelectionEnabled: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 设置标签和右侧控件的通用一行布局。
class _SettingRow extends StatelessWidget {
  /// label 是左侧字段名，control 是具体分段按钮。
  const _SettingRow({required this.label, required this.control});

  /// 设置项名称。
  final String label;

  /// 右侧可操作控件。
  final Widget control;

  /// 输出可在窄屏换行的响应式布局。
  @override
  Widget build(BuildContext context) {
    // LayoutBuilder 读取面板可用宽度。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 极窄屏把控件放到标签下一行，避免文字重叠。
        if (constraints.maxWidth < 330) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧标签改为顶部标签。
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              // 标签与控件间距。
              const SizedBox(height: 10),
              // 控件左对齐。
              Align(alignment: Alignment.centerLeft, child: control),
            ],
          );
        }
        // 普通手机横向显示标签和控件。
        return Row(
          children: [
            // 标签占满控件以外空间。
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            // 分段按钮按自身宽度显示。
            control,
          ],
        );
      },
    );
  }
}
