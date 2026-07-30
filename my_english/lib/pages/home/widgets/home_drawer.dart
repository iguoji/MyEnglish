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
// 离线语音缓存进度服务：抽屉内的“离线语音”入口实时读取与驱动后台预缓存。
import '../../../services/word_audio_cache.dart';

/// 右侧抽屉菜单：顶部品牌区 + Primary 添加按钮 + 数据入口 + 内嵌设置卡片 + 页脚联系。
///
/// 整体布局自上而下：
/// 1. 顶部三栏（logo / Azure 徽章 / 主题切换图标）
/// 2. 分割线
/// 3. Primary 添加单词按钮
/// 4. 分割线
/// 5. 离线语音入口 + 百分比（缓存中下方出现圆角进度条）
/// 6. 数据导入
/// 7. 数据导出
/// 8. 清空数据（红色危险样式）
/// 9. 分割线
/// 10. “学习设置”分区标题（字号小 2px）
/// 11~15. 卡片包裹：口语发音 + 单词分隔 + 每日复习
/// 16. 页脚：Github + 邮箱（水平排列、居左、有间隔）
class HomeDrawer extends StatelessWidget {
  /// 各入口的动作全部由首页注入，抽屉自身不包含业务逻辑。
  const HomeDrawer({
    required this.onAddWord,
    required this.settings,
    required this.cache,
    required this.onImport,
    required this.onExport,
    required this.onClearData,
    required this.onOpenGithub,
    required this.onCopyEmail,
    super.key,
  });

  /// 点击“添加单词”后由首页打开单词表单。
  final VoidCallback onAddWord;

  /// 全局设置 Store；抽屉内直接内嵌设置控件并实时反映修改。
  final SettingsStore settings;

  /// 离线语音缓存进度服务；“离线语音”入口读取百分比并触发后台预缓存。
  final WordAudioCache cache;

  /// 点击“数据导入”后由首页弹出文件选择器读取 JSON。
  final VoidCallback onImport;

  /// 点击“数据导出”后由首页把本地数据写出为 JSON 文件。
  final VoidCallback onExport;

  /// 点击“清空数据”后由首页弹出二次确认，确认后清空全部本地数据。
  final VoidCallback onClearData;

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
                    // 1. 顶部三栏：左 logo、中 Azure 徽章（名字+版号）、右主题切换图标。
                    _DrawerHeader(settings: settings),
                    // 2. 头部下方分隔线。
                    Divider(height: 1, color: tokens.rowBorder),
                    // 3. Primary 添加单词按钮（主色实底）。
                    _AddWordButton(onTap: onAddWord),
                    // 4. 分隔线。
                    Divider(height: 1, color: tokens.rowBorder),
                    // 5. 离线语音入口：右侧实时显示缓存百分比，缓存中下方出现圆角进度条。
                    _DrawerOfflineSpeech(cache: cache),
                    // 6. 数据导入。
                    _DrawerItem(
                      key: const Key('drawer-import'),
                      icon: TablerIcons.fileImport,
                      label: '数据导入',
                      onTap: onImport,
                    ),
                    // 7. 数据导出。
                    _DrawerItem(
                      key: const Key('drawer-export'),
                      icon: TablerIcons.fileExport,
                      label: '数据导出',
                      onTap: onExport,
                    ),
                    // 8. 清空数据：红色危险样式，作为本区块末项补下边距 10。
                    _DrawerItem(
                      key: const Key('drawer-clear'),
                      icon: TablerIcons.trash,
                      label: '清空数据',
                      onTap: onClearData,
                      isDanger: true,
                      bottomPadding: 10,
                    ),
                    // 9. 分隔线。
                    Divider(height: 1, color: tokens.rowBorder),
                    // 10. “学习设置”分区标题，字号比普通菜单项小 2px。
                    const _SectionLabel('学习设置'),
                    // 11~15. 卡片包裹：口语发音 + 单词分隔 + 每日复习。
                    // 卡片有 padding、无边框、有背景色（tokens.expand）。
                    _SettingsCard(settings: settings),
                  ],
                ),
              ),
            ),
            // 页脚上方分隔线。
            Divider(height: 1, color: tokens.rowBorder),
            // 16. 页脚：Github + 邮箱，水平排列、居左、两项之间有间隔。
            _DrawerFooter(
              onOpenGithub: onOpenGithub,
              onCopyEmail: onCopyEmail,
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部三栏：左 logo、中 Azure 浅色徽章（名字+版号）、右主题切换图标。
///
/// 主题切换图标取代了原内嵌设置中的“黑暗模式”开关：
/// - 浅色模式显示月亮（暗示切到深色）
/// - 深色模式显示太阳（暗示切到浅色）
class _DrawerHeader extends StatefulWidget {
  /// 接收全局设置 Store，用于读取与切换主题。
  const _DrawerHeader({required this.settings});

  /// 全局设置 Store。
  final SettingsStore settings;

  /// 创建局部状态，管理主题切换的异步保存。
  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

/// 控制主题切换期间的禁用与错误提示。
class _DrawerHeaderState extends State<_DrawerHeader> {
  /// true 表示主题正在等待 Android 磁盘确认，期间忽略重复点击。
  bool _isSaving = false;

  /// 切换黑暗/明亮模式；与原 _DrawerSettings._toggleDark 逻辑一致。
  Future<void> _toggleTheme() async {
    // 阻止重复磁盘写入。
    if (_isSaving) return;
    // 取反当前主题：dark→light、light→dark。
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

  /// 统一显示主题切换失败。
  void _showSaveError(Object error) {
    // 先移除上一条提示，避免快速失败时叠加队列。
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // SnackBar 不打断用户当前操作。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('主题切换失败：$error')));
  }

  /// 输出三栏横向布局。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让主题变化后只刷新头部，不重绘整个抽屉。
    return ListenableBuilder(
      // 监听全局设置 Store。
      listenable: widget.settings,
      // 根据最新主题重新构建图标。
      builder: (context, child) {
        // 当前是否为深色主题，决定显示太阳还是月亮。
        final isDark = widget.settings.theme == AppThemePreference.dark;
        // 当前亮度，决定 Azure 徽章在深浅色下的具体色值。
        final isDarkBrightness = Theme.of(context).brightness == Brightness.dark;
        // Azure 徽章背景：浅色 10% 透明、深色 20% 透明（深色 surface 上更可见）。
        final badgeBg = isDarkBrightness
            ? const Color(0x3345AAF2)
            : const Color(0x1A45AAF2);
        // Azure 徽章文字：浅色用加深的 azure、深色用标准 azure。
        final badgeText = isDarkBrightness
            ? const Color(0xFF45AAF2)
            : const Color(0xFF2B94D4);
        // Row 三栏：logo / Expanded 居中徽章 / 主题图标。
        return Padding(
          // 左 20 与菜单项对齐；右 8 因为图标按钮自带 6 内边距。
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
          child: Row(
            children: [
              // 左：42×42 圆角方块 logo，内嵌 Tabler 书本图标。
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 主色填充。
                  color: AppTokens.accent,
                  // 10 像素圆角，与设计稿一致。
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  TablerIcons.book2,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              // 中：Expanded 让名称+版号在剩余空间内居中。
              Expanded(
                child: Center(
                  // 名称与版号分两行：名称普通文字、版号 Azure 浅色徽章。
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 应用名称（普通文字）。
                      Text(
                        'MyEnglish',
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // 名称与版号间距。
                      const SizedBox(height: 4),
                      // 版号 Azure 浅色徽章：圆角 4、横向 8 纵向 3 内边距。
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          // Azure 主色按透明度叠加为浅底。
                          color: badgeBg,
                          // Tabler badge 默认 4 像素圆角。
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'v0.11.1',
                          style: TextStyle(
                            // Azure 加深色文字。
                            color: badgeText,
                            // 版号字号比名称小。
                            fontSize: 11,
                            // Tabler badge 字重 600。
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 右：主题切换图标按钮。
              InkWell(
                // key 供测试点击切换主题（替代原 dark-mode-switch）。
                key: const Key('theme-toggle'),
                // 保存中禁用点击。
                onTap: _isSaving ? null : () => unawaited(_toggleTheme()),
                // 圆形点击反馈区。
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  // 6 像素内边距让点击区域约 32×32。
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    // 深色显示太阳（切回浅色）、浅色显示月亮（切到深色）。
                    isDark ? TablerIcons.sun : TablerIcons.moon,
                    // 缩小三分之一（原 20 → 14）。
                    size: 14,
                    // 次要文字色，不抢 logo 视觉。
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Primary 添加单词按钮：主色实底、白色文字、整行宽度。
///
/// 对应 Tabler 的 btn-primary 样式：圆角 6、字号 14、字重 w600。
class _AddWordButton extends StatelessWidget {
  /// 接收点击动作。
  const _AddWordButton({required this.onTap});

  /// 点击动作，由首页决定行为。
  final VoidCallback onTap;

  /// 输出 38 高的整行主色按钮。
  @override
  Widget build(BuildContext context) {
    // Padding 让按钮左右与菜单项对齐（20），上 32 拉高留白、下 12 收尾。
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
      // InkWell 提供整行点击反馈。
      child: InkWell(
        // key 供测试点击触发添加单词表单。
        key: const Key('drawer-add-word'),
        // 点击回调。
        onTap: onTap,
        // 圆角与容器一致，避免按下时方角溢出。
        borderRadius: BorderRadius.circular(6),
        child: Container(
          // 按钮高度 38，与 Tabler btn 默认尺寸接近。
          height: 38,
          // 主色实底。
          decoration: BoxDecoration(
            color: AppTokens.accent,
            borderRadius: BorderRadius.circular(6),
          ),
          // 内容居中。
          alignment: Alignment.center,
          child: const Row(
            // 主轴居中：图标 + 文字整体居中。
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // plus 图标对应“+”号。
              Icon(TablerIcons.plus, size: 18, color: Colors.white),
              // 图标与文字间距。
              SizedBox(width: 6),
              // 按钮文字。
              Text(
                '添加单词',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 抽屉里的“离线语音”入口：左侧图标+文案，右侧居右显示缓存百分比。
///
/// 点击后会在下方展开一条整行圆角进度条，并触发后台批量缓存词库全部单词的
/// 双口音音频；缓存进度由 [WordAudioCache] 单例实时推送，因此关闭抽屉回到首页
/// 后任务继续，重新打开即见最新百分比。组件只通过 ListenableBuilder 监听服务，
/// 自身不持有任何后台状态。
class _DrawerOfflineSpeech extends StatelessWidget {
  /// 接收全局缓存服务。
  const _DrawerOfflineSpeech({required this.cache});

  /// 离线语音缓存进度服务。
  final WordAudioCache cache;

  /// 输出入口行 + 点击后出现的整行圆角进度条。
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
              // 点击逻辑：已 100% 缓存则提示用户，否则启动后台批量缓存。
              onTap: () {
                // 已经全部缓存完毕时不再重复下载，直接给一句提示即可。
                if (cache.percent >= 100) {
                  // 先移除上一条提示，避免快速重复点击时堆叠。
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  // 轻提示“已完整”，不打断用户。
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('离线语音已缓存完整')),
                  );
                  return;
                }
                // 否则进入缓存（进行中时内部自动忽略重复点击）。
                cache.start();
              },
              // 与 _DrawerItem 一致的整行内边距：上 10 下 0，让项间间距=10 对等。
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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
            // 仅在进行中显示整行圆角进度条（高度 4，占据整行宽度）。
            if (isCaching)
              Padding(
                // 左右与入口行对齐，进度条占满中间宽度。
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                // ClipRRect 给方形 LinearProgressIndicator 加圆角。
                child: ClipRRect(
                  // 2 像素圆角，4 高进度条视觉更柔和。
                  borderRadius: BorderRadius.circular(2),
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
///
/// [isDanger] 为 true 时图标与文字使用红色（用于“清空数据”）。
class _DrawerItem extends StatelessWidget {
  /// 接收图标、文案、点击动作与是否危险样式。
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
    this.bottomPadding = 0,
    super.key,
  });

  /// 入口图标。
  final IconData icon;

  /// 入口文案。
  final String label;

  /// 点击动作，由首页决定行为。
  final VoidCallback onTap;

  /// 是否使用红色危险样式（清空数据）。
  final bool isDanger;

  /// 底部内边距：默认 0（项间间距由下一项的 top 10 决定），
  /// 区块最后一项传 10 让其与下方分割线间距也=10，保持全链路对等。
  final double bottomPadding;

  /// 输出上 10、下 [bottomPadding] 的入口行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // 危险样式使用红色，普通样式使用默认色。
    final color = isDanger ? AppTokens.danger : tokens.text;
    final iconColor = isDanger ? AppTokens.danger : tokens.muted;
    // InkWell 提供整行点击反馈。
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 上 10 下 bottomPadding：项间间距=10 对等，末项补下边距。
        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPadding),
        child: Row(
          children: [
            // 17 像素图标，危险样式红色、普通样式灰色。
            Icon(icon, size: 17, color: iconColor),
            // 图标与文字间距。
            const SizedBox(width: 12),
            // 入口文案，危险样式红色、普通样式主文字色。
            Text(label, style: TextStyle(color: color, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }
}

/// 分区标题（如“学习设置”）：字号比普通菜单项小 2px，muted 色。
///
/// 普通 _DrawerItem 字号 14.5，这里 12.5，对应 Tabler 的 section label 风格。
class _SectionLabel extends StatelessWidget {
  /// 接收标题文案。
  const _SectionLabel(this.text);

  /// 标题文字。
  final String text;

  /// 输出左对齐的小号标题。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Padding(
      // 上 14 与上方分隔线留白，下 8 与卡片留白。
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          // 弱化色，作为分区提示不抢主菜单视觉。
          color: tokens.muted,
          // 比普通菜单项 14.5 小 2px。
          fontSize: 12.5,
          // 字重 600 让小字仍清晰。
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 设置卡片：包裹口语发音 + 单词分隔 + 每日复习（11~15 项）。
///
/// 卡片有 padding、无边框、有背景色（tokens.expand），圆角 8。
/// 背景用 tokens.expand（比 tokens.sub 更浅），让选择器轨道 tokens.sub 可见，
/// 选中项 tokens.card 白色浮起，视觉层次清晰。
class _SettingsCard extends StatefulWidget {
  /// 接收全局设置 Store。
  const _SettingsCard({required this.settings});

  /// 所有修改直接写入该 Store 并持久化。
  final SettingsStore settings;

  /// 创建局部状态。
  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

/// 控制口音与分隔符保存期间的禁用与错误提示。
class _SettingsCardState extends State<_SettingsCard> {
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

  /// 统一显示设置保存错误。
  void _showSaveError(Object error) {
    // 先移除上一条提示，避免快速失败时叠加队列。
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // SnackBar 不打断用户当前设置操作。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('设置保存失败：$error')));
  }

  /// 输出卡片容器 + 两行设置（口语发音 / 单词分隔）。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Container 作为卡片：横向 12 边距、纵向 4 内边距、tokens.expand 背景、8 圆角、无边框。
    return Container(
      // 横向 12 边距让卡片在抽屉内可见圆角。
      margin: const EdgeInsets.symmetric(horizontal: 12),
      // 纵向 4 内边距避免设置行紧贴卡片上下边。
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        // 卡片背景用 tokens.expand（比 tokens.sub 更浅），让选择器轨道 tokens.sub 可见。
        color: tokens.expand,
        // 8 像素圆角。
        borderRadius: BorderRadius.circular(8),
        // 无边框（用户要求）。
      ),
      // ListenableBuilder 让 Store 成功修改后只刷新卡片内容。
      child: ListenableBuilder(
        // 监听同一个全局 SettingsStore。
        listenable: widget.settings,
        // 根据最新设置重新构建选择器。
        builder: (context, child) {
          return Column(
            children: [
              // 11. 口语发音 + 美/英分段选择器。
              _SettingRow(
                // 改名为“口语发音”。
                label: '口语发音',
                // 卡片内行间分隔线。
                showDivider: true,
                // 卡片内横向 16 内边距（卡片已有 12 边距）。
                horizontalPadding: 16,
                control: _AccentControl(
                  settings: widget.settings,
                  onTap: (accent) => unawaited(_setAccent(accent)),
                ),
              ),
              // 13. 单词分隔 + 、/，/；分段选择器。
              _SettingRow(
                label: '单词分隔',
                // 中间行画分隔线，与下方每日复习分隔。
                showDivider: true,
                horizontalPadding: 16,
                control: _SeparatorControl(
                  settings: widget.settings,
                  onTap: (separator) =>
                      unawaited(_setDefinitionSeparator(separator)),
                ),
              ),
              // 15. 每日复习步进器（卡片内最后一行，不画分隔线）。
              _DailyGoalRow(settings: widget.settings),
            ],
          );
        },
      ),
    );
  }
}

/// 口语发音分段选择器：美式 / 英式。
///
/// 样式与原 _DrawerSettings 内的口音选择器完全一致，抽出独立组件便于复用与阅读。
class _AccentControl extends StatelessWidget {
  /// 接收设置 Store 与选择回调。
  const _AccentControl({required this.settings, required this.onTap});

  /// 全局设置 Store，读取当前口音。
  final SettingsStore settings;

  /// 点击某个口音后的回调。
  final void Function(PronunciationAccent) onTap;

  /// 输出浅底圆角轨道 + 两个段钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Container(
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
              onTap: () => onTap(accent),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 当前口音使用卡片底浮起。
                  color: settings.accent == accent
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
                    color: settings.accent == accent
                        ? AppTokens.accent
                        : tokens.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单词分隔分段选择器：、/，/；。
///
/// 样式与原 _DrawerSettings 内的分隔符选择器完全一致。
class _SeparatorControl extends StatelessWidget {
  /// 接收设置 Store 与选择回调。
  const _SeparatorControl({required this.settings, required this.onTap});

  /// 全局设置 Store，读取当前分隔符。
  final SettingsStore settings;

  /// 点击某个分隔符后的回调。
  final void Function(DefinitionSeparator) onTap;

  /// 输出浅底圆角轨道 + 三个段钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Container(
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
              onTap: () => onTap(separator),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 34,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 当前符号使用卡片底浮起，其他符号保持透明。
                  color: settings.definitionSeparator == separator
                      ? tokens.card
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  separator.symbol,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: settings.definitionSeparator == separator
                        ? AppTokens.accent
                        : tokens.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 每日复习目标行：- 数值 +，位于卡片外（14 分隔线之后）。
///
/// 控件样式与原 _DrawerSettings 的每日复习行完全一致，setDailyGoal 是同步内存操作，
/// 不需要异步保存与错误处理。
class _DailyGoalRow extends StatelessWidget {
  /// 接收全局设置 Store。
  const _DailyGoalRow({required this.settings});

  /// 全局设置 Store，读取与修改每日复习目标。
  final SettingsStore settings;

  /// 输出 52 高的步进器行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让目标值变化后只刷新本行。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: settings,
      // 根据最新目标值重新构建。
      builder: (context, child) {
        return _SettingRow(
          label: '每日复习',
          // 卡片内最后一行，不画分隔线。
          showDivider: false,
          // 卡片内横向 16 内边距（卡片已有 12 边距）。
          horizontalPadding: 16,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 减 5。
              _StepButton(
                key: const Key('goal-minus'),
                icon: TablerIcons.minus,
                onTap: () => settings.setDailyGoal(
                  settings.dailyGoal - 5,
                ),
              ),
              // 当前目标值。
              Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                child: Text(
                  settings.dailyGoal.toString(),
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    // 等宽数字避免加减时宽度跳动。
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // 加 5。
              _StepButton(
                key: const Key('goal-plus'),
                icon: TablerIcons.plus,
                onTap: () => settings.setDailyGoal(
                  settings.dailyGoal + 5,
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
///
/// [horizontalPadding] 默认 20（卡片外菜单项对齐），卡片内传 16。
class _SettingRow extends StatelessWidget {
  /// label 是左侧字段名，control 是右侧控件。
  const _SettingRow({
    required this.label,
    required this.control,
    required this.showDivider,
    this.horizontalPadding = 20,
  });

  /// 设置项名称。
  final String label;

  /// 右侧可操作控件。
  final Widget control;

  /// 是否绘制底部行分隔线。
  final bool showDivider;

  /// 横向内边距：卡片外 20、卡片内 16。
  final double horizontalPadding;

  /// 输出 52 高的横向布局。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Container 统一高度与分隔线。
    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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

/// 页脚：Github 图标 + Github 文字 + 间隔 + 邮箱图标 + 邮箱文字。
///
/// 两项水平排列、居左、之间有 16 像素间隔。整行位于抽屉底部。
class _DrawerFooter extends StatelessWidget {
  /// 接收两个点击动作。
  const _DrawerFooter({required this.onOpenGithub, required this.onCopyEmail});

  /// 点击 Github 项后用系统默认浏览器打开仓库。
  final VoidCallback onOpenGithub;

  /// 点击邮箱项后复制邮箱并提示。
  final VoidCallback onCopyEmail;

  /// 输出水平排列的两个可点击项。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Padding(
      // 上 14 与分隔线留白，下 18 贴近抽屉底。
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        // 两项居左排列。
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Github 项：图标 + 文字（自然宽度）。
          InkWell(
            onTap: onOpenGithub,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                // min 让 Row 只占内容宽度。
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tabler 品牌图标。
                  Icon(
                    TablerIcons.brandGithub,
                    size: 16,
                    color: tokens.textSecondary,
                  ),
                  // 图标与文字间距。
                  const SizedBox(width: 6),
                  // 文字。
                  Text(
                    'Github',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 两项之间 16 像素间隔。
          const SizedBox(width: 16),
          // 邮箱项：图标 + 文字（Expanded 占剩余空间，文字过长时省略）。
          Expanded(
            child: InkWell(
              onTap: onCopyEmail,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  // min 让 Row 只占内容宽度，配合外层 Expanded 限制总宽。
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 邮件图标。
                    Icon(
                      TablerIcons.mail,
                      size: 16,
                      color: tokens.textSecondary,
                    ),
                    // 图标与文字间距。
                    const SizedBox(width: 6),
                    // 邮箱地址：Flexible 让文字在空间不足时省略而非溢出。
                    Flexible(
                      child: Text(
                        'asgeg@qq.com',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
