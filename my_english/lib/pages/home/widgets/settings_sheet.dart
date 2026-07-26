// dart:async 提供 unawaited，让按钮回调启动异步保存而不丢失错误处理。
import 'dart:async';

// material.dart 提供底部面板与主题颜色。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 设置 Store 位于页面目录之外，其他页面可以直接复用。
import '../../../store/settings.dart';

/// 从当前页面底部弹出设置面板。
Future<void> showAppSettingsSheet(
  BuildContext context,
  SettingsStore settings,
) {
  // showModalBottomSheet 提供标准弹出动画和背景遮罩。
  return showModalBottomSheet<void>(
    // 使用当前首页 Navigator。
    context: context,
    // 背景由内容自绘顶部圆角卡片。
    backgroundColor: Colors.transparent,
    // builder 创建真正设置内容。
    builder: (sheetContext) => _SettingsSheet(settings: settings),
  );
}

/// 设置面板需要保存"正在写入"状态，所以使用 StatefulWidget。
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
    // 先进入保存状态。
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

  /// 切换黑暗模式开关；开=Dark、关=Light。
  Future<void> _toggleDark() async {
    // 阻止重复磁盘写入。
    if (_isSaving) return;
    // 取反当前主题。
    final next = widget.settings.theme == AppThemePreference.dark
        ? AppThemePreference.light
        : AppThemePreference.dark;
    // 进入保存状态。
    setState(() => _isSaving = true);
    try {
      // 等待原生确认持久化；成功后 MaterialApp 立即切换主题。
      await widget.settings.setTheme(next);
    } catch (error) {
      // 失败时保留原主题并通知用户。
      if (mounted) _showSaveError(error);
    } finally {
      // 恢复控件。
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

  /// 输出标题与三行设置。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让 Store 成功修改后只刷新面板内容。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: widget.settings,
      // 根据最新设置重新构建。
      builder: (context, child) {
        // 当前是否为深色主题。
        final isDark = widget.settings.theme == AppThemePreference.dark;
        // 顶部圆角卡片容器。
        return Container(
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 30),
          child: Column(
            // 高度只包住内容。
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题行：设置在左，"完成"在右。
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    // 面板标题。
                    Text(
                      '设置',
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // 撑开中间空间。
                    const Spacer(),
                    // 完成即关闭面板。
                    InkWell(
                      key: const Key('settings-done'),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          color: AppTokens.accent,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 第一行：发音口音分段选择。
              _SettingRow(
                label: '发音',
                showDivider: true,
                control: Container(
                  // 设计稿的浅底圆角轨道。
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: tokens.sub,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 逐个生成美式/英式段钮。
                      for (final accent in PronunciationAccent.values)
                        InkWell(
                          // key 供测试点击具体口音。
                          key: Key('accent-${accent.storageValue}'),
                          onTap: () => unawaited(_setAccent(accent)),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              // 当前口音使用卡片底浮起。
                              color: widget.settings.accent == accent
                                  ? tokens.card
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              accent.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                // 当前口音主色，其余次要色。
                                color: widget.settings.accent == accent
                                    ? AppTokens.accent
                                    : tokens.textSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 第二行：黑暗模式开关。
              _SettingRow(
                label: '黑暗模式',
                showDivider: true,
                control: GestureDetector(
                  // key 供测试切换主题。
                  key: const Key('dark-mode-switch'),
                  onTap: () => unawaited(_toggleDark()),
                  // 自绘 46×27 圆角开关，与设计稿一致。
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 46,
                    height: 27,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      // 开启用主色轨道，关闭用中性轨道。
                      color: isDark ? AppTokens.accent : tokens.check,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    // 白色圆钮左右滑动。
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: isDark
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x4D000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 第三行：每日复习目标步进器。
              _SettingRow(
                label: '每日复习',
                showDivider: false,
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 减 5。
                    _StepButton(
                      key: const Key('goal-minus'),
                      label: '−',
                      onTap: () => widget.settings.setDailyGoal(
                        widget.settings.dailyGoal - 5,
                      ),
                    ),
                    // 当前目标值。
                    Container(
                      constraints: const BoxConstraints(minWidth: 34),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      child: Text(
                        widget.settings.dailyGoal.toString(),
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    // 加 5。
                    _StepButton(
                      key: const Key('goal-plus'),
                      label: '＋',
                      onTap: () => widget.settings.setDailyGoal(
                        widget.settings.dailyGoal + 5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 设置项的通用一行：左标签、右控件、可选底部分隔线。
class _SettingRow extends StatelessWidget {
  /// label 是左侧字段名，control 是右侧控件。
  const _SettingRow({
    required this.label,
    required this.control,
    required this.showDivider,
  });

  /// 设置项名称。
  final String label;

  /// 右侧可操作控件。
  final Widget control;

  /// 是否绘制底部行分隔线。
  final bool showDivider;

  /// 输出 52 高的横向布局。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Container 统一高度与分隔线。
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: tokens.rowBorder))
            : null,
      ),
      child: Row(
        children: [
          // 左侧标签。
          Text(
            label,
            style: TextStyle(color: tokens.text, fontSize: 14.5),
          ),
          // 撑开中间空间。
          const Spacer(),
          // 右侧控件。
          control,
        ],
      ),
    );
  }
}

/// 每日复习目标的 28×28 步进按钮。
class _StepButton extends StatelessWidget {
  /// 接收符号与动作。
  const _StepButton({required this.label, required this.onTap, super.key});

  /// 按钮符号（− 或 ＋）。
  final String label;

  /// 点击动作。
  final VoidCallback onTap;

  /// 输出描边小方块。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // InkWell 提供点击反馈。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border.all(color: tokens.inputBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(color: tokens.textMedium, fontSize: 15, height: 1),
        ),
      ),
    );
  }
}
