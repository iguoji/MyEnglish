// dart:async 提供 unawaited，让设置按钮的回调启动异步保存而不丢失错误处理。
import 'dart:async';

// material.dart 提供 Drawer、ListTile 风格布局与 ChangeNotifier 监听所需组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 统一提供应用内图标，避免使用 Flutter Material 内置图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';
// 引入应用元信息常量（pubspec.yaml 单一数据源同步生成的版本号与展示名）。
import '../../../common/app_info.dart';
// 引入全局 Toast 工具，层级高于 Drawer/BottomSheet。
import '../../../common/toast.dart';
// 设置 Store 与口音/分隔符/主题枚举；抽屉内直接复用全局设置。
import '../../../store/settings.dart';
// 离线语音缓存进度服务：抽屉内的"离线语音"入口实时读取与驱动后台预缓存。
import '../../../services/word_audio_cache.dart';

///
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
/// 16. 页脚：Github 图标 + 邮箱图标（居左、有间隔）
///
class HomeDrawer extends StatelessWidget {
  ///
  /// 各入口的动作全部由首页注入，抽屉自身不包含业务逻辑。
  ///
  /// @param  VoidCallback  onAddWord
  /// @param  SettingsStore  settings
  /// @param  WordAudioCache  cache
  /// @param  VoidCallback  onImport
  /// @param  VoidCallback  onExport
  /// @param  VoidCallback  onClearData
  /// @param  VoidCallback  onOpenGithub
  /// @param  VoidCallback  onCopyEmail
  /// @param  Key?  key
  ///
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

  ///
  /// 点击“添加单词”后由首页打开单词表单。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onAddWord;

  ///
  /// 全局设置 Store；抽屉内直接内嵌设置控件并实时反映修改。
  ///
  /// @var SettingsStore
  ///
  final SettingsStore settings;

  ///
  /// 离线语音缓存进度服务；“离线语音”入口读取百分比并触发后台预缓存。
  ///
  /// @var WordAudioCache
  ///
  final WordAudioCache cache;

  ///
  /// 点击“数据导入”后由首页弹出文件选择器读取 JSON。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onImport;

  ///
  /// 点击“数据导出”后由首页把本地数据写出为 JSON 文件。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onExport;

  ///
  /// 点击“清空数据”后由首页弹出二次确认，确认后清空全部本地数据。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onClearData;

  ///
  /// 点击页脚仓库地址后的动作：用默认浏览器打开 GitHub。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onOpenGithub;

  ///
  /// 点击页脚作者邮箱后的动作：复制邮箱并提示。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onCopyEmail;

  ///
  /// 输出与设计稿一致的 252 宽抽屉内容。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
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
                    // 8. 清空数据：红色危险样式，作为本区块末项补下边距 20。
                    _DrawerItem(
                      key: const Key('drawer-clear'),
                      icon: TablerIcons.trash,
                      label: '清空数据',
                      onTap: onClearData,
                      isDanger: true,
                      bottomPadding: 20,
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
            _DrawerFooter(onOpenGithub: onOpenGithub, onCopyEmail: onCopyEmail),
          ],
        ),
      ),
    );
  }
}

///
/// 顶部三栏：左 logo、中 Azure 浅色徽章（名字+版号）、右主题切换图标。
///
/// 主题切换图标取代了原内嵌设置中的“黑暗模式”开关：
/// - 浅色模式显示月亮（暗示切到深色）
/// - 深色模式显示太阳（暗示切到浅色）
///
class _DrawerHeader extends StatefulWidget {
  ///
  /// 接收全局设置 Store，用于读取与切换主题。
  ///
  /// @param  SettingsStore  settings
  ///
  const _DrawerHeader({required this.settings});

  ///
  /// 全局设置 Store。
  ///
  /// @var SettingsStore
  ///
  final SettingsStore settings;

  ///
  /// 创建局部状态，管理主题切换的异步保存。
  ///
  /// @return `State<_DrawerHeader>`
  ///
  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

///
/// 控制主题切换期间的禁用与错误提示。
///
class _DrawerHeaderState extends State<_DrawerHeader> {
  ///
  /// true 表示主题正在等待 Android 磁盘确认，期间忽略重复点击。
  ///
  /// @var bool
  ///
  bool _isSaving = false;

  ///
  /// 切换黑暗/明亮模式；与原 _DrawerSettings._toggleDark 逻辑一致。
  ///
  /// @return `Future<void>`
  ///
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

  ///
  /// 统一显示主题切换失败。
  ///
  /// @param  Object  error
  /// @return void
  ///
  void _showSaveError(Object error) {
    // Toast 基于根 Overlay，层级高于 Drawer。
    Toast.show(context, '主题切换失败：$error');
  }

  ///
  /// 输出三栏横向布局。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
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
        final isDarkBrightness =
            Theme.of(context).brightness == Brightness.dark;
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
              // 左：42×42 品牌 logo（来自 assets/logo/app_logo.png，
              // 即 logo/_source/master_1024.png 的 C3 翻页书页方案）。
              // 不再使用 TablerIcons.book2 占位，因为 App Logo 必须原创几何、
              // 不能搬用任何图标库现成图形（参考项目约定）。
              ClipRRect(
                // PNG 本身已含圆角，ClipRRect 仅作边缘抗锯齿兜底。
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/logo/app_logo.png',
                  width: 42,
                  height: 42,
                  // 强制 42×42 缩放，PNG 源 1024×1024。
                  fit: BoxFit.cover,
                ),
              ),
              // 图标与文字间距。
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 应用名称（从 pubspec.yaml 同步，单一数据源）。
                    Text(
                      AppInfo.displayName,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // 名称与版号间距。
                    const SizedBox(height: 4),
                    // 版号 Azure 浅色徽章：圆角 4、横向 8 纵向 2 内边距（高度减小 2px）。
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        // Azure 主色按透明度叠加为浅底。
                        color: badgeBg,
                        // Tabler badge 默认 4 像素圆角。
                        borderRadius: BorderRadius.circular(4),
                      ),
                      // 版本号前加 v 前缀，与历史样式保持一致；
                      // AppInfo.version 由 pubspec.yaml 同步生成，不再硬编码。
                      child: Text(
                        'v${AppInfo.version}',
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
              // 右：主题切换图标按钮，尺寸与页脚图标一致(图标 18 + padding 4)。
              InkWell(
                // key 供测试点击切换主题（替代原 dark-mode-switch）。
                key: const Key('theme-toggle'),
                // 保存中禁用点击。
                onTap: _isSaving ? null : () => unawaited(_toggleTheme()),
                // 圆形点击反馈区。
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  // padding 4 与页脚图标项一致。
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    // 深色显示太阳（切回浅色）、浅色显示月亮（切到深色）。
                    isDark ? TablerIcons.sun : TablerIcons.moon,
                    // 与页脚图标一致 18px。
                    size: 18,
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

///
/// Primary 添加单词按钮：主色实底、白色文字、整行宽度。
///
/// 对应 Tabler 的 btn-primary 样式：圆角 6、字号 14、字重 w600。
///
class _AddWordButton extends StatelessWidget {
  ///
  /// 接收点击动作。
  ///
  /// @param  VoidCallback  onTap
  ///
  const _AddWordButton({required this.onTap});

  ///
  /// 点击动作，由首页决定行为。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 输出 38 高的整行主色按钮。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // Padding 让按钮左右与菜单项对齐（20），上下 32 对称留白。
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
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

///
/// 抽屉里的“离线语音”入口：左侧图标+文案，右侧居右显示缓存百分比。
///
/// 点击后会在下方展开一条整行圆角进度条，并触发后台批量缓存词库全部单词的
/// 双口音音频；缓存进度由 [WordAudioCache] 单例实时推送，因此关闭抽屉回到首页
/// 后任务继续，重新打开即见最新百分比。组件只通过 ListenableBuilder 监听服务，
/// 自身不持有任何后台状态。
///
class _DrawerOfflineSpeech extends StatelessWidget {
  ///
  /// 接收全局缓存服务。
  ///
  /// @param  WordAudioCache  cache
  ///
  const _DrawerOfflineSpeech({required this.cache});

  ///
  /// 离线语音缓存进度服务。
  ///
  /// @var WordAudioCache
  ///
  final WordAudioCache cache;

  ///
  /// 输出入口行 + 点击后出现的整行圆角进度条。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
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
                  // Toast 基于根 Overlay，层级高于 Drawer，不被遮挡。
                  Toast.show(context, '离线语音已缓存完整');
                  return;
                }
                // 否则进入缓存（进行中时内部自动忽略重复点击）。
                cache.start();
              },
              // 与 _DrawerItem 一致的整行内边距：上 20 下 0，让项间间距=20 对等。
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: <Widget>[
                    // 17 像素灰色描边图标，与 _DrawerItem 视觉一致。
                    Icon(
                      TablerIcons.cloudDownload,
                      size: 17,
                      color: tokens.muted,
                    ),
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

///
/// 抽屉里单个功能入口：左图标右文字，整行可点。
///
/// [isDanger] 为 true 时图标与文字使用红色（用于“清空数据”）。
///
class _DrawerItem extends StatelessWidget {
  ///
  /// 接收图标、文案、点击动作与是否危险样式。
  ///
  /// @param  IconData  icon
  /// @param  String  label
  /// @param  VoidCallback  onTap
  /// @param  bool  isDanger
  /// @param  double  bottomPadding
  /// @param  Key?  key
  ///
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
    this.bottomPadding = 0,
    super.key,
  });

  ///
  /// 入口图标。
  ///
  /// @var IconData
  ///
  final IconData icon;

  ///
  /// 入口文案。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 点击动作，由首页决定行为。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onTap;

  ///
  /// 是否使用红色危险样式（清空数据）。
  ///
  /// @var bool
  ///
  final bool isDanger;

  ///
  /// 底部内边距：默认 0（项间间距由下一项的 top 20 决定），
  /// 区块最后一项传 20 让其与下方分割线间距也=20，保持全链路对等。
  ///
  /// @var double
  ///
  final double bottomPadding;

  ///
  /// 输出上 20、下 [bottomPadding] 的入口行。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
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
        // 上 20 下 bottomPadding：项间间距=20 对等，末项补下边距让与下方分割线也=20。
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
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

///
/// 分区标题（如“学习设置”）：字号比普通菜单项小 2px，muted 色。
///
/// 普通 _DrawerItem 字号 14.5，这里 12.5，对应 Tabler 的 section label 风格。
///
class _SectionLabel extends StatelessWidget {
  ///
  /// 接收标题文案。
  ///
  /// @param  String  text
  ///
  const _SectionLabel(this.text);

  ///
  /// 标题文字。
  ///
  /// @var String
  ///
  final String text;

  ///
  /// 输出左对齐的小号标题。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
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

///
/// 设置卡片：包裹口语发音 + 单词分隔 + 每日复习（11~15 项）。
///
/// 卡片有 padding、无边框、有背景色（tokens.expand），圆角 8。
/// 背景用 tokens.expand（比 tokens.sub 更浅），让选择器轨道 tokens.sub 可见，
/// 选中项 tokens.card 白色浮起，视觉层次清晰。
///
class _SettingsCard extends StatefulWidget {
  ///
  /// 接收全局设置 Store。
  ///
  /// @param  SettingsStore  settings
  ///
  const _SettingsCard({required this.settings});

  ///
  /// 所有修改直接写入该 Store 并持久化。
  ///
  /// @var SettingsStore
  ///
  final SettingsStore settings;

  ///
  /// 创建局部状态。
  ///
  /// @return `State<_SettingsCard>`
  ///
  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

///
/// 控制口音与分隔符保存期间的禁用与错误提示。
///
class _SettingsCardState extends State<_SettingsCard> {
  ///
  /// true 表示某项设置正在等待 Android 磁盘确认。
  ///
  /// @var bool
  ///
  bool _isSaving = false;

  ///
  /// 保存口音并把失败原因显示在当前页面。
  ///
  /// @param  PronunciationAccent  value
  /// @return `Future<void>`
  ///
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

  ///
  /// 保存中文释义分隔符，并沿用口音设置相同的失败提示流程。
  ///
  /// @param  DefinitionSeparator  value
  /// @return `Future<void>`
  ///
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

  ///
  /// 统一显示设置保存错误。
  ///
  /// @param  Object  error
  /// @return void
  ///
  void _showSaveError(Object error) {
    // Toast 基于根 Overlay，层级高于 Drawer。
    Toast.show(context, '设置保存失败：$error');
  }

  ///
  /// 输出卡片容器 + 两行设置（口语发音 / 单词分隔）。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Container 作为卡片：横向 10 边距、纵向 4 内边距、tokens.expand 背景、8 圆角、无边框。
    return Container(
      // 横向 10 边距。
      margin: const EdgeInsets.symmetric(horizontal: 10),
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
                // 卡片内横向 8 内边距（卡片已有 20 边距对齐标题）。
                horizontalPadding: 10,
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
                horizontalPadding: 10,
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

///
/// 三种设置控件共用的轨道宽度，让口语发音/单词分隔/每日复习视觉等宽。
///
/// @var double
///
const double _kSettingControlWidth = 108;

///
/// 口语发音分段选择器：美式 / 英式。
///
/// 轨道与段钮样式与单词分隔、每日复习完全一致，统一宽度 [_kSettingControlWidth]。
///
class _AccentControl extends StatelessWidget {
  ///
  /// 接收设置 Store 与选择回调。
  ///
  /// @param  SettingsStore  settings
  /// @param  `void Function(PronunciationAccent)`  onTap
  ///
  const _AccentControl({required this.settings, required this.onTap});

  ///
  /// 全局设置 Store，读取当前口音。
  ///
  /// @var SettingsStore
  ///
  final SettingsStore settings;

  ///
  /// 点击某个口音后的回调。
  ///
  /// @var `void Function(PronunciationAccent)`
  ///
  final void Function(PronunciationAccent) onTap;

  ///
  /// 输出固定宽轨道 + 两个段钮。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Container(
      // 固定宽度让三种控件视觉等宽。
      width: _kSettingControlWidth,
      // 固定高度 38（padding 6*2 + 段钮 26），与单词分隔/每日复习统一。
      height: 38,
      // padding 6（原 2 增大三倍），让段钮间隔更舒展。
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tokens.sub,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        // 两个段钮均分轨道宽度。
        children: [
          for (final accent in PronunciationAccent.values)
            Expanded(
              child: InkWell(
                // key 供测试点击具体口音。
                key: Key('accent-${accent.storageValue}'),
                onTap: () => onTap(accent),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  height: 26,
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
            ),
        ],
      ),
    );
  }
}

///
/// 单词分隔分段选择器：、/，/；。
///
/// 轨道宽度与口语发音一致 [_kSettingControlWidth]，三个段钮均分。
///
class _SeparatorControl extends StatelessWidget {
  ///
  /// 接收设置 Store 与选择回调。
  ///
  /// @param  SettingsStore  settings
  /// @param  `void Function(DefinitionSeparator)`  onTap
  ///
  const _SeparatorControl({required this.settings, required this.onTap});

  ///
  /// 全局设置 Store，读取当前分隔符。
  ///
  /// @var SettingsStore
  ///
  final SettingsStore settings;

  ///
  /// 点击某个分隔符后的回调。
  ///
  /// @var `void Function(DefinitionSeparator)`
  ///
  final void Function(DefinitionSeparator) onTap;

  ///
  /// 输出固定宽轨道 + 三个段钮。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Container(
      // 与口语发音等宽。
      width: _kSettingControlWidth,
      // 固定高度 38，与口语发音/每日复习统一。
      height: 38,
      // padding 6 与口语发音一致。
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tokens.sub,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        // 三个段钮均分轨道宽度。
        children: [
          for (final separator in DefinitionSeparator.values)
            Expanded(
              child: InkWell(
                // key 供 Widget 测试和自动化准确选择标点。
                key: Key('definition-separator-${separator.storageValue}'),
                onTap: () => onTap(separator),
                borderRadius: BorderRadius.circular(6),
                child: Container(
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
            ),
        ],
      ),
    );
  }
}

///
/// 每日复习目标行：- 数值 +，三元素放进 switch 风格容器。
///
/// 容器样式（tokens.sub 背景、8 圆角、无边框、固定宽度 [_kSettingControlWidth]）
/// 与口语发音/单词分隔完全一致；加减按钮去掉边框，仅保留图标。
///
class _DailyGoalRow extends StatefulWidget {
  ///
  /// 接收全局设置 Store。
  ///
  /// @param  SettingsStore  settings
  ///
  const _DailyGoalRow({required this.settings});

  ///
  /// 全局设置 Store，读取与修改每日复习目标。
  ///
  /// @var SettingsStore
  ///
  final SettingsStore settings;

  ///
  /// 创建局部状态，避免连续点击造成多个 SharedPreferences 写入交错。
  ///
  /// @return `State<_DailyGoalRow>`
  ///
  @override
  State<_DailyGoalRow> createState() => _DailyGoalRowState();
}

///
/// 管理每日目标步进按钮的异步保存状态。
///
class _DailyGoalRowState extends State<_DailyGoalRow> {
  ///
  /// true 表示正在等待 Android 确认磁盘写入。
  ///
  /// @var bool
  ///
  bool _isSaving = false;

  ///
  /// 把目标增加或减少一个步长，并统一处理保存失败。
  ///
  /// @param  int  delta
  /// @return `Future<void>`
  ///
  Future<void> _changeGoal(int delta) async {
    // 保存期间忽略重复点击，避免较慢设备上发生写入顺序倒置。
    if (_isSaving) return;
    // 禁用两个按钮，直到本次写入结束。
    setState(() => _isSaving = true);
    try {
      // 基于当前已确认的目标计算新值；Store 会把负数钳制为 0。
      await widget.settings.setDailyGoal(widget.settings.dailyGoal + delta);
    } catch (error) {
      // 写入失败时 Store 不改变内存值，并向用户说明原因。
      if (mounted) Toast.show(context, '每日目标保存失败：$error');
    } finally {
      // 抽屉仍在组件树中时恢复按钮。
      if (mounted) setState(() => _isSaving = false);
    }
  }

  ///
  /// 输出 52 高的步进器行。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // ListenableBuilder 让目标值变化后只刷新本行。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: widget.settings,
      // 根据最新目标值重新构建。
      builder: (context, child) {
        return _SettingRow(
          label: '每日复习',
          // 卡片内最后一行，不画分隔线。
          showDivider: false,
          // 卡片内横向 10 内边距，与口语发音/单词分隔两行完全一致，
          // 保证三行右侧控件左右边缘对齐（此前误传 8 导致本行整体偏左 2px）。
          horizontalPadding: 10,
          // 右侧容器：与口语发音/单词分隔同样的 switch 风格轨道。
          control: Container(
            // 与口语发音/单词分隔等宽。
            width: _kSettingControlWidth,
            // 固定高度 38，与口语发音/单词分隔统一，避免占满整行。
            height: 38,
            // padding 6 与其他两个控件一致。
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              // 同样的背景色。
              color: tokens.sub,
              // 同样的圆角。
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // 减 5：去掉边框，仅图标。
                Expanded(
                  child: InkWell(
                    key: const Key('goal-minus'),
                    onTap: _isSaving ? null : () => unawaited(_changeGoal(-5)),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      child: Icon(
                        TablerIcons.minus,
                        size: 15,
                        color: tokens.textMedium,
                      ),
                    ),
                  ),
                ),
                // 当前目标值。
                Container(
                  constraints: const BoxConstraints(minWidth: 34),
                  height: 26,
                  alignment: Alignment.center,
                  child: Text(
                    widget.settings.dailyGoal.toString(),
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      // 等宽数字避免加减时宽度跳动。
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // 加 5：去掉边框，仅图标。
                Expanded(
                  child: InkWell(
                    key: const Key('goal-plus'),
                    onTap: _isSaving ? null : () => unawaited(_changeGoal(5)),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      child: Icon(
                        TablerIcons.plus,
                        size: 15,
                        color: tokens.textMedium,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

///
/// 设置项的通用一行：左标签、右控件、可选底部分隔线。
///
/// [horizontalPadding] 默认 20（卡片外菜单项对齐），卡片内统一传 10。
///
class _SettingRow extends StatelessWidget {
  ///
  /// label 是左侧字段名，control 是右侧控件。
  ///
  /// @param  String  label
  /// @param  Widget  control
  /// @param  bool  showDivider
  /// @param  double  horizontalPadding
  ///
  const _SettingRow({
    required this.label,
    required this.control,
    required this.showDivider,
    this.horizontalPadding = 20,
  });

  ///
  /// 设置项名称。
  ///
  /// @var String
  ///
  final String label;

  ///
  /// 右侧可操作控件。
  ///
  /// @var Widget
  ///
  final Widget control;

  ///
  /// 是否绘制底部行分隔线。
  ///
  /// @var bool
  ///
  final bool showDivider;

  ///
  /// 横向内边距：卡片外 20、卡片内 16。
  ///
  /// @var double
  ///
  final double horizontalPadding;

  ///
  /// 输出 52 高的横向布局。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
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

///
/// 页脚：Github 图标 + 邮箱图标，两个图标居左排列、有间隔。
///
/// 仅显示图标，不显示文字。整行位于抽屉底部。
///
class _DrawerFooter extends StatelessWidget {
  ///
  /// 接收两个点击动作。
  ///
  /// @param  VoidCallback  onOpenGithub
  /// @param  VoidCallback  onCopyEmail
  ///
  const _DrawerFooter({required this.onOpenGithub, required this.onCopyEmail});

  ///
  /// 点击 Github 项后用系统默认浏览器打开仓库。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onOpenGithub;

  ///
  /// 点击邮箱项后复制邮箱并提示。
  ///
  /// @var VoidCallback
  ///
  final VoidCallback onCopyEmail;

  ///
  /// 输出水平排列的两个可点击项。
  ///
  /// @param  BuildContext  context
  /// @return Widget
  ///
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Padding(
      // 上 14 与分隔线留白，下 18 贴近抽屉底。
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        // 两图标居左排列。
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Github 图标项。
          InkWell(
            onTap: onOpenGithub,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                TablerIcons.brandGithub,
                size: 18,
                color: tokens.textSecondary,
              ),
            ),
          ),
          // 两图标之间 16 像素间隔。
          const SizedBox(width: 16),
          // 邮箱图标项。
          InkWell(
            onTap: onCopyEmail,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                TablerIcons.mail,
                size: 18,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
