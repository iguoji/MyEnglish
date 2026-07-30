// dart:async 提供 unawaited，让设置按钮的回调启动异步保存而不丢失错误处理。
import 'dart:async';

// material.dart 提供 Drawer、ListTile 风格布局与 ChangeNotifier 监听所需组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 统一提供应用内图标，避免使用 Flutter Material 内置图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 设置 Store 与口音/分隔符/主题枚举；抽屉内直接复用全局设置。
import '../../../store/settings.dart';
// 离线语音缓存进度服务：抽屉内的"离线语音"入口实时读取与驱动后台预缓存。
import '../../../services/word_audio_cache.dart';

/// 右侧抽屉菜单：App 信息、内嵌的设置项、数据与关于入口、页脚联系方式。
class HomeDrawer extends StatelessWidget {
  /// 各入口的动作全部由首页注入，抽屉自身不包含业务逻辑。
  const HomeDrawer({
    required this.onAddWord,
    required this.settings,
    required this.cache,
    required this.onImport,
    required this.onExport,
    required this.onClearData,
    required this.onAbout,
    required this.onOpenGithub,
    required this.onCopyEmail,
    super.key,
  });

  /// 点击"添加单词"后由首页打开单词表单。
  final VoidCallback onAddWord;

  /// 全局设置 Store；抽屉内直接内嵌设置控件并实时反映修改。
  final SettingsStore settings;

  /// 离线语音缓存进度服务；"离线语音"入口读取百分比并触发后台预缓存。
  final WordAudioCache cache;

  /// 点击"数据导入"后由首页弹出文件选择器读取 JSON。
  final VoidCallback onImport;

  /// 点击"数据导出"后由首页把本地数据写出为 JSON 文件。
  final VoidCallback onExport;

  /// 点击"清空数据"后由首页弹出二次确认，确认后清空全部本地数据。
  final VoidCallback onClearData;

  /// 点击"关于"后的动作；本轮为占位提示。
  final VoidCallback onAbout;

  /// 点击页脚仓库地址后的动作：用默认浏览器打开 GitHub。
  final VoidCallback onOpenGithub;

  /// 点击页脚作者邮箱后的动作：复制邮箱并提示。
  final VoidCallback onCopyEmail;

  /// 输出与设计稿一致的 252 宽抽屉内容。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);

    // Drawer 是 Material 标准侧边面板；宽度固定为设计稿的 252。
    return Drawer(
      width: 252,
      // 表面使用卡片色。
      backgroundColor: tokens.card,
      // 抽屉自带圆角在右侧展开时不需要，设为直角贴边。
      shape: const RoundedRectangleBorder(),
      // SafeArea 避开状态栏，保持顶部信息完整可见。
      child: SafeArea(
        // Column 让页脚固定在底部，中间菜单区可滚动。
        child: Column(
          children: [
            // Expanded 让菜单区在剩余空间内滚动：内嵌设置后内容变高，
            // 小屏设备也不会因超出屏幕高度而溢出。
            Expanded(
              child: SingleChildScrollView(
                // 子项默认左对齐。
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 头部：应用图标、名称与版本号。
                    Padding(
                      // 与设计稿一致的头部内边距。
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Row(
                        children: [
                          // 42×42 圆角方块内使用 Tabler 书本图标，避免把汉字当作图标。
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTokens.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              TablerIcons.book2,
                              color: Colors.white,
                              size: 23,
                            ),
                          ),
                          // 图标与文字间距。
                          const SizedBox(width: 12),
                          // 名称与版本纵向排列。
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 应用名称。
                              Text(
                                'MyEnglish',
                                style: TextStyle(
                                  color: tokens.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              // 版本号与 pubspec 保持一致。
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '版本 v0.1.0',
                                  style: TextStyle(
                                    color: tokens.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 头部下方分隔线。
                    Divider(height: 1, color: tokens.rowBorder),
                    // 菜单项区域上下留 8 像素。
                    const SizedBox(height: 8),
                    // 基础入口：添加单词。
                    _DrawerItem(
                      key: const Key('drawer-add-word'),
                      icon: TablerIcons.circlePlus,
                      label: '添加单词',
                      onTap: onAddWord,
                    ),
                    // 原"设置"菜单项已取消：在上方加一条分割线，把设置控件直接内嵌到
                    // 下方区块，点击即在当前菜单内操作，不再弹出独立窗口。
                    Divider(height: 1, color: tokens.rowBorder),
                    // 内嵌设置区：发音 / 单词分隔 / 黑暗模式 / 每日复习。
                    _DrawerSettings(settings: settings),
                    // 设置区与数据入口之间的细分隔线。
                    Divider(height: 1, color: tokens.rowBorder),
                    // 离线语音：后台批量缓存词库全部单词的双口音音频，右侧实时显示缓存百分比。
                    _DrawerOfflineSpeech(cache: cache),
                    // 数据类入口：导入、导出、清空。
                    _DrawerItem(
                      key: const Key('drawer-import'),
                      icon: TablerIcons.fileImport,
                      label: '数据导入',
                      onTap: onImport,
                    ),
                    _DrawerItem(
                      key: const Key('drawer-export'),
                      icon: TablerIcons.fileExport,
                      label: '数据导出',
                      onTap: onExport,
                    ),
                    _DrawerItem(
                      key: const Key('drawer-clear'),
                      icon: TablerIcons.trash,
                      label: '清空数据',
                      onTap: onClearData,
                    ),
                    // 数据入口与关于之间的细分隔线。
                    Divider(height: 1, color: tokens.rowBorder),
                    _DrawerItem(
                      key: const Key('drawer-about'),
                      icon: TablerIcons.infoCircle,
                      label: '关于',
                      onTap: onAbout,
                    ),
                  ],
                ),
              ),
            ),
            // 页脚上方分隔线。
            Divider(height: 1, color: tokens.rowBorder),
            // 页脚：仓库地址与作者邮箱。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GitHub 小标题。
                  Text(
                    'GitHub',
                    style: TextStyle(color: tokens.muted, fontSize: 11),
                  ),
                  // 仓库地址整行可点：点击后用系统默认浏览器打开。
                  // InkWell 提供点击反馈；brandGithub 是 Tabler 的品牌图标。
                  InkWell(
                    onTap: onOpenGithub,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            TablerIcons.brandGithub,
                            size: 14,
                            color: AppTokens.accent,
                          ),
                          SizedBox(width: 6),
                          // Expanded 让长链接在抽屉内换行，避免横向溢出。
                          Expanded(
                            child: Text(
                              'github.com/iguoji/MyEnglish',
                              style: TextStyle(
                                color: AppTokens.accent,
                                fontSize: 12.5,
                              ),
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 两条信息之间的间距。
                  const SizedBox(height: 12),
                  // 邮箱小标题。
                  Text(
                    '作者邮箱',
                    style: TextStyle(color: tokens.muted, fontSize: 11),
                  ),
                  // 邮箱整行可点：点击后自动复制并提示。
                  InkWell(
                    onTap: onCopyEmail,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            TablerIcons.mail,
                            size: 14,
                            color: AppTokens.accent,
                          ),
                          SizedBox(width: 6),
                          // Expanded 让邮箱在抽屉内换行，避免横向溢出。
                          Expanded(
                            child: Text(
                              'asgeg@qq.com',
                              style: TextStyle(
                                color: AppTokens.accent,
                                fontSize: 12.5,
                              ),
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 抽屉里的"离线语音"入口：左侧图标+文案，右侧居右显示缓存百分比。
///
/// 点击后会在下方展开一条整行低高度进度条，并触发后台批量缓存词库全部单词的
/// 双口音音频；缓存进度由 [WordAudioCache] 单例实时推送，因此关闭抽屉回到首页
/// 后任务继续，重新打开即见最新百分比。组件只通过 ListenableBuilder 监听服务，
/// 自身不持有任何后台状态。
class _DrawerOfflineSpeech extends StatelessWidget {
  /// 接收全局缓存服务。
  const _DrawerOfflineSpeech({required this.cache});

  /// 离线语音缓存进度服务。
  final WordAudioCache cache;

  /// 输出入口行 + 点击后出现的整行进度条。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让服务每次进度更新只刷新本入口，不重绘整个抽屉。
    return ListenableBuilder(
      // 监听全局缓存服务。
      listenable: cache,
      // 根据最新缓存状态重建。
      builder: (context, child) {
        // 当前已缓存百分比。
        final percent = cache.percent;
        // 是否仍在进行中。
        final isCaching = cache.isCaching;
        return Column(
          // 让进度条紧贴入口下方、占满整行宽度。
          children: <Widget>[
            // 入口行：左图标 + 文案，右对齐百分比。
            InkWell(
              // 供测试点击触发离线预缓存。
              key: const Key('offline-speech'),
              // 点击即启动后台批量缓存（进行中时内部自动忽略重复点击）。
              onTap: () => cache.start(),
              // 与 _DrawerItem 一致的整行内边距。
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  children: <Widget>[
                    // 17 像素灰色描边图标，与 _DrawerItem 视觉一致。
                    Icon(TablerIcons.cloudDownload, size: 17, color: tokens.muted),
                    // 图标与文字间距。
                    const SizedBox(width: 12),
                    // 入口文案使用主文字色。
                    Text(
                      '离线语音',
                      style: TextStyle(color: tokens.text, fontSize: 14.5),
                    ),
                    // 撑开中间空间，把百分比推到最右侧。
                    const Spacer(),
                    // 右侧居右对齐的百分比数字（默认 0%）。
                    Text(
                      '$percent%',
                      style: TextStyle(color: tokens.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            // 仅在进行中显示整行低高度进度条（高度 4，占据整行宽度）。
            if (isCaching)
              Padding(
                // 左右与入口行对齐，进度条占满中间宽度。
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: SizedBox(
                  // 低高度：4 逻辑像素，符合"高度不高"的需求。
                  height: 4,
                  // LinearProgressIndicator 类似小程序 progress 组件。
                  child: LinearProgressIndicator(
                    // 已完成比例，0~1。
                    value: cache.ratio,
                    // 轨道底色用次级面色。
                    backgroundColor: tokens.sub,
                    // 已完成部分用主色。
                    valueColor: AlwaysStoppedAnimation<Color>(AppTokens.accent),
                    // 明确压低高度，避免默认 4 之上再增高。
                    minHeight: 4,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 抽屉里单个功能入口：左图标右文字，整行可点。
class _DrawerItem extends StatelessWidget {
  /// 接收图标、文案与点击动作。
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  /// 入口图标。
  final IconData icon;

  /// 入口文案。
  final String label;

  /// 点击动作，由首页决定行为。
  final VoidCallback onTap;

  /// 输出 13 像素上下内边距的入口行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // InkWell 提供整行点击反馈。
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 与设计稿一致的行内边距。
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            // 17 像素灰色描边图标。
            Icon(icon, size: 17, color: tokens.muted),
            // 图标与文字间距。
            const SizedBox(width: 12),
            // 入口文案使用主文字色。
            Text(label, style: TextStyle(color: tokens.text, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }
}

/// 抽屉内直接内嵌的设置区：发音、单词分隔、黑暗模式、每日复习。
///
/// 点击即在当前菜单内生效，不再弹出独立窗口。它监听同一个全局 SettingsStore，
/// 因此保存成功后只刷新自身、无需重绘整个抽屉。
class _DrawerSettings extends StatefulWidget {
  /// 接收全局唯一设置 Store。
  const _DrawerSettings({required this.settings});

  /// 所有修改直接写入该 Store 并持久化。
  final SettingsStore settings;

  /// 创建局部状态。
  @override
  State<_DrawerSettings> createState() => _DrawerSettingsState();
}

/// 控制保存期间禁用重复操作。
class _DrawerSettingsState extends State<_DrawerSettings> {
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

  /// 保存中文释义分隔符，并沿用口音设置相同的失败提示流程。
  Future<void> _setDefinitionSeparator(DefinitionSeparator value) async {
    // 已有设置正在写入时忽略并发点击，避免磁盘值与界面选择交错。
    if (_isSaving) return;
    // 进入保存状态后其他持久化选项会暂时拒绝重复操作。
    setState(() => _isSaving = true);
    try {
      // 等待 Android SharedPreferences 明确返回写入成功。
      await widget.settings.setDefinitionSeparator(value);
    } catch (error) {
      // 页面仍存在时把原生错误展示给用户。
      if (mounted) _showSaveError(error);
    } finally {
      // 面板可能已关闭，因此先检查 mounted 再恢复状态。
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

  /// 输出四行设置（发音 / 单词分隔 / 黑暗模式 / 每日复习）。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让 Store 成功修改后只刷新设置区内容。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: widget.settings,
      // 根据最新设置重新构建。
      builder: (context, child) {
        // 当前是否为深色主题。
        final isDark = widget.settings.theme == AppThemePreference.dark;
        // 纵向排列四行设置。
        return Column(
          children: [
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
            // 第二行：中文释义分隔符分段选择。
            _SettingRow(
              label: '单词分隔',
              showDivider: true,
              control: Container(
                // 轨道与发音选择器使用同一套浅底圆角样式。
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: tokens.sub,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 三个选项只显示全角中文标点，避免误用英文半角符号。
                    for (final separator in DefinitionSeparator.values)
                      InkWell(
                        // key 供 Widget 测试和自动化准确选择标点。
                        key: Key(
                          'definition-separator-${separator.storageValue}',
                        ),
                        onTap: () =>
                            unawaited(_setDefinitionSeparator(separator)),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 34,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // 当前符号使用卡片底浮起，其他符号保持透明。
                            color: widget.settings.definitionSeparator ==
                                    separator
                                ? tokens.card
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            separator.symbol,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.settings.definitionSeparator ==
                                      separator
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
            // 第三行：黑暗模式开关。
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
            // 第四行：每日复习目标步进器。
            _SettingRow(
              label: '每日复习',
              showDivider: false,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 减 5。
                  _StepButton(
                    key: const Key('goal-minus'),
                    icon: TablerIcons.minus,
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
                    icon: TablerIcons.plus,
                    onTap: () => widget.settings.setDailyGoal(
                      widget.settings.dailyGoal + 5,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
          Text(label, style: TextStyle(color: tokens.text, fontSize: 14.5)),
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
  /// 接收 Tabler 图标与动作。
  const _StepButton({required this.icon, required this.onTap, super.key});

  /// 步进按钮使用的 Tabler 图标数据。
  final IconData icon;

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
        child: Icon(icon, color: tokens.textMedium, size: 15),
      ),
    );
  }
}
