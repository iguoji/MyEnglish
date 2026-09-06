// dart:async 提供 unawaited，让设置按钮的回调启动异步保存而不丢失错误处理。
import 'dart:async';

// material.dart 提供 Drawer、ListTile 风格布局与 ChangeNotifier 监听所需组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

// 首页专属尺寸表：本组件的宽高从这里取名字，数值继承设计令牌总表。
import 'home_layout.dart';
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
/// 16. 页脚：Github 图标 + 邮箱图标 + 日志导出图标（居左、有间隔）
///
class HomeDrawer extends StatelessWidget {
  ///
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
    required this.onExportLog,
    super.key,
  });

  ///
  /// 点击“添加单词”后由首页打开单词表单。
  final VoidCallback onAddWord;

  ///
  /// 全局设置 Store；抽屉内直接内嵌设置控件并实时反映修改。
  final SettingsStore settings;

  ///
  /// 离线语音缓存进度服务；“离线语音”入口读取百分比并触发后台预缓存。
  final WordAudioCache cache;

  ///
  /// 点击“数据导入”后由首页弹出文件选择器读取 JSON。
  final VoidCallback onImport;

  ///
  /// 点击“数据导出”后由首页把本地数据写出为 JSON 文件。
  final VoidCallback onExport;

  ///
  /// 点击“清空数据”后由首页弹出二次确认，确认后清空全部本地数据。
  final VoidCallback onClearData;

  ///
  /// 点击页脚仓库地址后的动作：用默认浏览器打开 GitHub。
  final VoidCallback onOpenGithub;

  ///
  /// 点击页脚作者邮箱后的动作：复制邮箱并提示。
  final VoidCallback onCopyEmail;

  ///
  /// 点击页脚日志图标后的动作：由首页直接弹系统保存框导出单日日志。
  final VoidCallback onExportLog;

  ///
  /// 输出与设计稿一致的 252 宽抽屉内容。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);

    // Drawer 是 Material 标准侧边面板；宽度固定为设计稿的 252。
    return Drawer(
      width: HomeDrawerLayout.width,
      // 表面使用卡片色。
      backgroundColor: tokens.card,
      // 抽屉自带圆角在右侧展开时不需要，设为直角贴边。
      shape: const RoundedRectangleBorder(),
      // IconTheme 给整个抽屉定下**默认图标尺寸**，就像 CSS 里在父元素上写一次
      // `font-size`、子元素不用再各写一遍。
      //
      // 抽屉里有 10 个图标（菜单项、设置项、页脚……），原来每一个都自己写
      // `size: AppIcon.i16`：想整体调大一档得改 10 处，漏一处就有一个图标
      // 比别人小。现在只有这一处；确实要与众不同的图标仍可在自己那一行写
      // `size:` 覆盖，写法和 CSS 的就近覆盖一模一样。
      //
      // 颜色没有一起提上来：抽屉里的图标颜色本来就分好几种角色（普通项灰、
      // 危险项红、选中项白），提上来反而要在多数地方再写一遍覆盖。
      child: IconTheme.merge(
        data: const IconThemeData(size: AppIcon.i16),
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
                      Divider(
                        height: HomeDrawerLayout.dividerHeight,
                        color: tokens.rowBorder,
                      ),
                      // 3. Primary 添加单词按钮（主色实底）。
                      _AddWordButton(onTap: onAddWord),
                      // 4. 分隔线。
                      Divider(
                        height: HomeDrawerLayout.dividerHeight,
                        color: tokens.rowBorder,
                      ),
                      // 5. 离线语音入口：右侧实时显示缓存百分比，缓存中下方出现圆角进度条。
                      _DrawerOfflineSpeech(cache: cache),
                      // 6. 数据导入。
                      _DrawerItem(
                        key: const Key('drawer-import'),
                        icon: AppGlyph.importFile,
                        label: '数据导入',
                        onTap: onImport,
                      ),
                      // 7. 数据导出。
                      _DrawerItem(
                        key: const Key('drawer-export'),
                        icon: AppGlyph.exportFile,
                        label: '数据导出',
                        onTap: onExport,
                      ),
                      // 8. 清空数据：红色危险样式，作为本区块末项补一档下边距（`pBase`）。
                      _DrawerItem(
                        key: const Key('drawer-clear'),
                        icon: AppGlyph.clearAll,
                        label: '清空数据',
                        onTap: onClearData,
                        isDanger: true,
                        bottomPadding: AppSpace.pBase,
                      ),
                      // 9. 分隔线。
                      Divider(
                        height: HomeDrawerLayout.dividerHeight,
                        color: tokens.rowBorder,
                      ),
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
              Divider(
                height: HomeDrawerLayout.dividerHeight,
                color: tokens.rowBorder,
              ),
              // 16. 页脚：Github + 邮箱 + 日志导出，水平排列、居左、有间隔。
              _DrawerFooter(
                onOpenGithub: onOpenGithub,
                onCopyEmail: onCopyEmail,
                onExportLog: onExportLog,
              ),
            ],
          ),
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
  const _DrawerHeader({required this.settings});

  ///
  /// 全局设置 Store。
  final SettingsStore settings;

  ///
  /// 创建局部状态，管理主题切换的异步保存。
  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

///
/// 控制主题切换期间的禁用与错误提示。
///
class _DrawerHeaderState extends State<_DrawerHeader> {
  ///
  /// true 表示主题正在等待 Android 磁盘确认，期间忽略重复点击。
  bool _isSaving = false;

  ///
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

  ///
  /// 统一显示主题切换失败。
  void _showSaveError(Object error) {
    // Toast 基于根 Overlay，层级高于 Drawer。
    Toast.show(context, '主题切换失败：$error');
  }

  ///
  /// 输出三栏横向布局。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // ListenableBuilder 让主题变化后只刷新头部，不重绘整个抽屉。
    return ListenableBuilder(
      // 监听全局设置 Store。
      listenable: widget.settings,
      // 根据最新主题重新构建图标。
      builder: (context, child) {
        // 当前是否为深色主题，决定显示太阳还是月亮。
        final isDark = widget.settings.theme == AppThemePreference.dark;
        // Azure 徽章的底色与文字色都收进了设计令牌：浅色 10% 透明 + 加深文字、
        // 深色 20% 透明 + 标准文字，明暗判断由 AppTokens.of 统一完成，
        // 这里不再自己问一次「现在是不是深色」。
        final badge = AppTokens.of(context);
        final badgeBg = badge.badgeAzureBg;
        final badgeText = badge.badgeAzureText;
        // Row 三栏：logo / Expanded 居中徽章 / 主题图标。
        return Padding(
          // 左侧与菜单项对齐（`pBase`）；右侧收窄一档（`p2`），因为图标按钮自带内边距。
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pBase,
            AppSpace.p3,
            AppSpace.p2,
            AppSpace.p3,
          ),
          child: Row(
            children: [
              // 左：42×42 品牌 logo（来自 assets/logo/app_logo.png，
              // 即 logo/_source/master_1024.png 的 C3 翻页书页方案）。
              // 不再使用 Tabler 的 book2 图标 占位，因为 App Logo 必须原创几何、
              // 不能搬用任何图标库现成图形（参考项目约定）。
              ClipRRect(
                // PNG 本身已含圆角，ClipRRect 仅作边缘抗锯齿兜底。
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Image.asset(
                  'assets/logo/app_logo.png',
                  width: HomeDrawerLayout.logoSize,
                  height: HomeDrawerLayout.logoSize,
                  // 强制 42×42 缩放，PNG 源 1024×1024。
                  fit: BoxFit.cover,
                ),
              ),
              // 图标与文字间距。
              const SizedBox(width: AppSpace.p3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 应用名称（从 pubspec.yaml 同步，单一数据源）。
                    Text(
                      AppInfo.displayName,
                      // 14 号粗那一档：和菜单项同字号，应用名靠字重抓眼。
                      style: textTheme.fs5Bold,
                    ),
                    // 名称与版号间距。
                    const SizedBox(height: AppSpace.p1),
                    // 版号 Azure 浅色徽章：徽标那一档圆角（`rounded`）、横向常规间隙（`p2`）、纵向最小档（`p1`）。
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.p2,
                        vertical: AppSpace.p1,
                      ),
                      decoration: BoxDecoration(
                        // Azure 主色按透明度叠加为浅底。
                        color: badgeBg,
                        // Tabler badge 走基准圆角那一档。
                        borderRadius: BorderRadius.circular(AppRadius.rounded),
                      ),
                      // 版本号前加 v 前缀，与历史样式保持一致；
                      // AppInfo.version 由 pubspec.yaml 同步生成，不再硬编码。
                      child: Text(
                        'v${AppInfo.version}',
                        // 12 号半粗那一档，正好是 Tabler badge 的规格。
                        style: textTheme.fs6Semibold.copyWith(
                          // Azure 加深色文字。
                          color: badgeText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 右：主题切换图标按钮，尺寸与页脚图标一致（图标 18 + 一档最小内边距）。
              InkWell(
                // key 供测试点击切换主题（替代原 dark-mode-switch）。
                key: const Key('theme-toggle'),
                // 保存中禁用点击。
                onTap: _isSaving ? null : () => unawaited(_toggleTheme()),
                // 圆形点击反馈区。
                borderRadius: BorderRadius.circular(AppRadius.rounded),
                child: Padding(
                  // padding 4 与页脚图标项一致。
                  padding: const EdgeInsets.all(AppSpace.p1),
                  child: Icon(
                    // 深色显示太阳（切回浅色）、浅色显示月亮（切到深色）。
                    isDark ? AppGlyph.lightMode : AppGlyph.darkMode,
                    // 尺寸继承抽屉根部的 IconTheme，这里只定颜色。
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
  const _AddWordButton({required this.onTap});

  ///
  /// 点击动作，由首页决定行为。
  final VoidCallback onTap;

  ///
  /// 输出 38 高的整行主色按钮。
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Padding 让按钮左右与菜单项对齐（`pBase`），上下用大一档（`p5`）对称留白。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pBase,
        AppSpace.p5,
        AppSpace.pBase,
        AppSpace.p5,
      ),
      // InkWell 提供整行点击反馈。
      child: InkWell(
        // key 供测试点击触发添加单词表单。
        key: const Key('drawer-add-word'),
        // 点击回调。
        onTap: onTap,
        // 圆角与容器一致，避免按下时方角溢出。
        borderRadius: BorderRadius.circular(AppRadius.rounded),
        child: Container(
          // 按钮高度 38，与 Tabler btn 默认尺寸接近。
          height: HomeDrawerLayout.addWordButtonHeight,
          // 主色实底。
          decoration: BoxDecoration(
            color: AppTokens.primary,
            borderRadius: BorderRadius.circular(AppRadius.rounded),
          ),
          // 内容居中。
          alignment: Alignment.center,
          child: Row(
            // 主轴居中：图标 + 文字整体居中。
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // plus 图标对应“+”号。尺寸继承抽屉根部的 IconTheme。
              const Icon(AppGlyph.add, color: Colors.white),
              // 图标与文字间距。
              const SizedBox(width: AppSpace.p2),
              // 按钮文字。
              Text(
                '添加单词',
                style: textTheme.fs5Semibold.copyWith(color: Colors.white),
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
  const _DrawerOfflineSpeech({required this.cache});

  ///
  /// 离线语音缓存进度服务。
  final WordAudioCache cache;

  ///
  /// 输出入口行 + 点击后出现的整行圆角进度条。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
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
              // 与 _DrawerItem 一致的整行内边距：上一档（`pBase`）下不留，让项间间距彼此相等。
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pBase,
                  AppSpace.pBase,
                  AppSpace.pBase,
                  AppSpace.p0,
                ),
                child: Row(
                  children: <Widget>[
                    // 灰色描边图标，与 _DrawerItem 视觉一致；尺寸继承 IconTheme。
                    Icon(AppGlyph.download, color: tokens.muted),
                    // 图标与文字间距。
                    const SizedBox(width: AppSpace.p3),
                    // 入口文案使用主文字色。
                    Text(
                      // 正文那一档自带主文字色，与其它菜单项完全一致。
                      '离线语音',
                      style: textTheme.fs5,
                    ),
                    // 撑开中间空间，把百分比推到最右侧。
                    const Spacer(),
                    // 右侧居右对齐的百分比数字（默认 0%）。
                    Text(
                      '$percent%',
                      style: textTheme.fs5.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
            ),
            // 仅在进行中显示整行圆角进度条（高度 4，占据整行宽度）。
            if (isCaching)
              Padding(
                // 左右与入口行对齐，进度条占满中间宽度。
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pBase,
                  AppSpace.p0,
                  AppSpace.pBase,
                  AppSpace.p2,
                ),
                // ClipRRect 给方形 LinearProgressIndicator 加圆角。
                child: ClipRRect(
                  // 2 像素圆角，4 高进度条视觉更柔和。
                  borderRadius: BorderRadius.circular(AppRadius.roundedSm),
                  child: LinearProgressIndicator(
                    // 已完成比例，0~1。
                    value: cache.ratio,
                    // 轨道底色用次级面色。
                    backgroundColor: tokens.sub,
                    // 已完成部分用主色。
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTokens.primary,
                    ),
                    // 明确压低高度，避免默认 4 之上再增高。
                    minHeight: HomeDrawerLayout.speechCacheBarHeight,
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
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
    this.bottomPadding = AppSpace.p0,
    super.key,
  });

  ///
  /// 入口图标。
  final IconData icon;

  ///
  /// 入口文案。
  final String label;

  ///
  /// 点击动作，由首页决定行为。
  final VoidCallback onTap;

  ///
  /// 是否使用红色危险样式（清空数据）。
  final bool isDanger;

  ///
  /// 底部内边距：默认不留（项间间距由下一项的上内边距决定），
  /// 区块最后一项补一档（`pBase`），让它与下方分割线的间距和项间间距相等，保持全链路对等。
  final double bottomPadding;

  ///
  /// 输出上一档（`pBase`）、下 [bottomPadding] 的入口行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // 危险样式使用红色，普通样式使用默认色。
    final color = isDanger ? AppTokens.danger : tokens.text;
    final iconColor = isDanger ? AppTokens.danger : tokens.muted;
    // InkWell 提供整行点击反馈。
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 上一档（`pBase`）下 bottomPadding：项间间距彼此相等，末项补下边距让它与下方分割线也一样。
        padding: EdgeInsets.fromLTRB(
          AppSpace.pBase,
          AppSpace.pBase,
          AppSpace.pBase,
          bottomPadding,
        ),
        child: Row(
          children: [
            // 危险样式红色、普通样式灰色；尺寸继承抽屉根部的 IconTheme。
            Icon(icon, color: iconColor),
            // 图标与文字间距。
            const SizedBox(width: AppSpace.p3),
            // 入口文案，危险样式红色、普通样式主文字色。
            Text(label, style: textTheme.fs5.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

///
/// 分区标题（如“学习设置”）：字号比普通菜单项小一档，muted 色。
///
/// 普通 _DrawerItem 用正文档（`fs5`），这里降到最小档（`fs6`），对应 Tabler 的 section label 风格。
///
class _SectionLabel extends StatelessWidget {
  ///
  /// 接收标题文案。
  const _SectionLabel(this.text);

  ///
  /// 标题文字。
  final String text;

  ///
  /// 输出左对齐的小号标题。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      // 上留一档基准间距（`p3`）与上方分隔线分开，下收到常规间隙（`p2`）贴近卡片。
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pBase,
        AppSpace.p3,
        AppSpace.pBase,
        AppSpace.p2,
      ),
      child: Text(
        text,
        // 12 号半粗那一档：比普通菜单项小一档，字重 600 让小字仍清晰。
        style: textTheme.fs6Semibold.copyWith(
          // 弱化色，作为分区提示不抢主菜单视觉。
          color: tokens.muted,
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
  const _SettingsCard({required this.settings});

  ///
  /// 所有修改直接写入该 Store 并持久化。
  final SettingsStore settings;

  ///
  /// 创建局部状态。
  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

///
/// 控制口音与分隔符保存期间的禁用与错误提示。
///
class _SettingsCardState extends State<_SettingsCard> {
  ///
  /// true 表示某项设置正在等待 Android 磁盘确认。
  bool _isSaving = false;

  ///
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

  ///
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

  ///
  /// 保存文字大小档位，流程与口音、分隔符完全一致。
  ///
  /// 这一项落盘成功后，全站文字会立刻按新倍数重排——不是只有这张卡片变，
  /// 而是首页、词库、四个练习页一起变，因为放大是挂在 App 最外层的。
  Future<void> _setFontScale(AppFontScale value) async {
    // 已有设置正在写入时忽略并发点击。
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.settings.setFontScale(value);
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  ///
  /// 统一显示设置保存错误。
  void _showSaveError(Object error) {
    // Toast 基于根 Overlay，层级高于 Drawer。
    Toast.show(context, '设置保存失败：$error');
  }

  ///
  /// 输出卡片容器 + 两行设置（口语发音 / 单词分隔）。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    // Container 作为卡片：横向常规边距、纵向最小内边距、tokens.expand 背景、卡片那一档圆角、无边框。
    return Container(
      // 横向留一档常规边距（`p2`）。
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.p2),
      // 纵向留一档最小内边距（`p1`），避免设置行紧贴卡片上下边。
      padding: const EdgeInsets.symmetric(vertical: AppSpace.p1),
      decoration: BoxDecoration(
        // 卡片背景用 tokens.expand（比 tokens.sub 更浅），让选择器轨道 tokens.sub 可见。
        color: tokens.expand,
        // 8 像素圆角。
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
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
                // 卡片内横向收到一档常规间隙（`p2`）；卡片自己已有一档 `pBase` 边距对齐标题。
                horizontalPadding: AppSpace.p2,
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
                horizontalPadding: AppSpace.p2,
                control: _SeparatorControl(
                  settings: widget.settings,
                  onTap: (separator) =>
                      unawaited(_setDefinitionSeparator(separator)),
                ),
              ),
              // 14. 字体大小 + 标准/大/特大分段选择器（俗称老年版开关）。
              _SettingRow(
                label: '字体大小',
                showDivider: true,
                horizontalPadding: AppSpace.p2,
                control: _FontScaleControl(
                  settings: widget.settings,
                  onTap: (scale) => unawaited(_setFontScale(scale)),
                ),
              ),
              // 15. 每日复习步进器（不再是最后一行，下方接词义连连）。
              _DailyGoalRow(settings: widget.settings),
              // 16. 词义连连倒计时步进器（卡片内最后一行，不画分隔线）。
              _MeaningMatchDurationRow(settings: widget.settings),
            ],
          );
        },
      ),
    );
  }
}

///
/// 三种设置控件共用的轨道宽度，让口语发音/单词分隔/每日复习视觉等宽。
/// 数值取自首页尺寸表的 [HomeDrawerLayout.controlWidth]，这里只是给本文件
/// 起一个短名字，四处引用读起来更利落。
const double _kSettingControlWidth = HomeDrawerLayout.controlWidth;

///
/// 口语发音分段选择器：美式 / 英式。
///
/// 轨道与段钮样式与单词分隔、每日复习完全一致，统一宽度 [_kSettingControlWidth]。
///
class _AccentControl extends StatelessWidget {
  ///
  /// 接收设置 Store 与选择回调。
  const _AccentControl({required this.settings, required this.onTap});

  ///
  /// 全局设置 Store，读取当前口音。
  final SettingsStore settings;

  ///
  /// 点击某个口音后的回调。
  final void Function(PronunciationAccent) onTap;

  ///
  /// 输出固定宽轨道 + 两个段钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      // 固定宽度让三种控件视觉等宽。
      width: _kSettingControlWidth,
      // 高度由内部结构算出（上下各一档 `p2` 加 26 高的段钮 = 42），与单词分隔 / 每日复习统一。
      height: HomeDrawerLayout.controlTrackHeight,
      // 四周留一档常规内边距（`p2`），让段钮间隔更舒展。
      padding: const EdgeInsets.all(AppSpace.p2),
      decoration: BoxDecoration(
        color: tokens.sub,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
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
                borderRadius: BorderRadius.circular(AppRadius.rounded),
                child: Container(
                  height: HomeDrawerLayout.controlSegmentHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // 当前口音使用卡片底浮起。
                    color: settings.accent == accent
                        ? tokens.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                  ),
                  child: Text(
                    accent.label,
                    style: textTheme.fs6Semibold.copyWith(
                      // 当前口音主色，其余次要色。
                      color: settings.accent == accent
                          ? AppTokens.primary
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
  const _SeparatorControl({required this.settings, required this.onTap});

  ///
  /// 全局设置 Store，读取当前分隔符。
  final SettingsStore settings;

  ///
  /// 点击某个分隔符后的回调。
  final void Function(DefinitionSeparator) onTap;

  ///
  /// 输出固定宽轨道 + 三个段钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      // 与口语发音等宽。
      width: _kSettingControlWidth,
      // 高度取分段轨道那一档（`controlTrackHeight`），与口语发音 / 每日复习统一。
      height: HomeDrawerLayout.controlTrackHeight,
      // 四周内边距与口语发音那一行一致（`p2`）。
      padding: const EdgeInsets.all(AppSpace.p2),
      decoration: BoxDecoration(
        color: tokens.sub,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
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
                borderRadius: BorderRadius.circular(AppRadius.rounded),
                child: Container(
                  height: HomeDrawerLayout.controlSegmentHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // 当前符号使用卡片底浮起，其他符号保持透明。
                    color: settings.definitionSeparator == separator
                        ? tokens.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                  ),
                  child: Text(
                    separator.symbol,
                    style: textTheme.fs5Semibold.copyWith(
                      color: settings.definitionSeparator == separator
                          ? AppTokens.primary
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
/// 字体大小分段选择器：标准 / 大 / 特大。
///
/// 轨道宽度与口语发音、单词分隔一致 [_kSettingControlWidth]，三个段钮均分。
///
/// 这个控件有一处和兄弟控件不同的处理：段钮里的文字包了一层 [FittedBox]。
/// 原因是它本身就是「调字号」的开关——选到特大之后，连它自己的三个段钮文字
/// 也会跟着变大，而轨道宽度是固定的。包一层之后文字最多缩着显示，
/// 不会把「特大」两个字挤掉一半。
///
class _FontScaleControl extends StatelessWidget {
  ///
  /// 接收设置 Store 与选择回调。
  const _FontScaleControl({required this.settings, required this.onTap});

  ///
  /// 全局设置 Store，读取当前档位。
  final SettingsStore settings;

  ///
  /// 点击某个档位后的回调。
  final void Function(AppFontScale) onTap;

  ///
  /// 输出固定宽轨道 + 三个段钮。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      // 与口语发音等宽。
      width: _kSettingControlWidth,
      // 高度取分段轨道那一档（`controlTrackHeight`），与其余三种控件统一。
      height: HomeDrawerLayout.controlTrackHeight,
      // 四周内边距与口语发音那一行一致（`p2`）。
      padding: const EdgeInsets.all(AppSpace.p2),
      decoration: BoxDecoration(
        color: tokens.sub,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Row(
        // 三个段钮均分轨道宽度。
        children: [
          for (final scale in AppFontScale.values)
            Expanded(child: _segment(scale, tokens, textTheme)),
        ],
      ),
    );
  }

  ///
  /// 输出一个段钮：当前档位浮起并转成品牌蓝，其余保持透明。
  ///
  /// 文字样式表由 build 取一次再递进来：本方法没有自己的 context，
  /// 三个段钮各自再取一遍反而更绕。
  Widget _segment(AppFontScale scale, AppTokens tokens, TextTheme textTheme) {
    // 是否为当前生效的档位。
    final isActive = settings.fontScale == scale;
    return InkWell(
      // key 供 Widget 测试和自动化准确选择档位。
      key: Key('font-scale-${scale.storageValue}'),
      onTap: () => onTap(scale),
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      child: Container(
        height: HomeDrawerLayout.controlSegmentHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 当前档位使用卡片底浮起。
          color: isActive ? tokens.card : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        // scaleDown 只在放不下时才缩小，正常字号下不影响观感。
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            scale.label,
            style: textTheme.fs6Semibold.copyWith(
              color: isActive ? AppTokens.primary : tokens.textSecondary,
            ),
          ),
        ),
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
  const _DailyGoalRow({required this.settings});

  ///
  /// 全局设置 Store，读取与修改每日复习目标。
  final SettingsStore settings;

  ///
  /// 创建局部状态，避免连续点击造成多个 SharedPreferences 写入交错。
  @override
  State<_DailyGoalRow> createState() => _DailyGoalRowState();
}

///
/// 管理每日目标步进按钮的异步保存状态。
///
class _DailyGoalRowState extends State<_DailyGoalRow> {
  ///
  /// true 表示正在等待 Android 确认磁盘写入。
  bool _isSaving = false;

  ///
  /// 把目标增加或减少一个步长，并统一处理保存失败。
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
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // ListenableBuilder 让目标值变化后只刷新本行。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: widget.settings,
      // 根据最新目标值重新构建。
      builder: (context, child) {
        return _SettingRow(
          label: '每日复习',
          // 下方还有“词义连连”行，这里画分隔线把两行隔开。
          showDivider: true,
          // 卡片内横向内边距与口语发音 / 单词分隔两行取同一档（`p2`），
          // 三行右侧控件的左右边缘才会对齐成一条线（早先这里误传过另一档，本行整体偏左两像素）。
          horizontalPadding: AppSpace.p2,
          // 右侧容器：与口语发音/单词分隔同样的 switch 风格轨道。
          control: Container(
            // 与口语发音/单词分隔等宽。
            width: _kSettingControlWidth,
            // 高度取分段轨道那一档（`controlTrackHeight`），与口语发音 / 单词分隔统一，避免占满整行。
            height: HomeDrawerLayout.controlTrackHeight,
            // 四周内边距与其他两个控件取同一档（`p2`）。
            padding: const EdgeInsets.all(AppSpace.p2),
            decoration: BoxDecoration(
              // 同样的背景色。
              color: tokens.sub,
              // 同样的圆角。
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Row(
              children: [
                // 减 5：去掉边框，仅图标。
                Expanded(
                  child: InkWell(
                    key: const Key('goal-minus'),
                    onTap: _isSaving ? null : () => unawaited(_changeGoal(-5)),
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                    child: Container(
                      height: HomeDrawerLayout.controlSegmentHeight,
                      alignment: Alignment.center,
                      child: Icon(AppGlyph.stepDown, color: tokens.textMedium),
                    ),
                  ),
                ),
                // 当前目标值。
                Container(
                  constraints: const BoxConstraints(
                    minWidth: HomeDrawerLayout.stepperValueMinWidth,
                  ),
                  height: HomeDrawerLayout.controlSegmentHeight,
                  alignment: Alignment.center,
                  child: Text(
                    widget.settings.dailyGoal.toString(),
                    style: textTheme.fs5Semibold.copyWith(
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
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                    child: Container(
                      height: HomeDrawerLayout.controlSegmentHeight,
                      alignment: Alignment.center,
                      child: Icon(AppGlyph.stepUp, color: tokens.textMedium),
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
/// 词义连连倒计时的步进器行：步长 30、默认 150，读写全局设置 meaningMatchDuration。
///
/// 交互与“每日复习”完全一致（减/加按钮 + 当前值），只是改动的是词义连连的倒计时秒数。
///
class _MeaningMatchDurationRow extends StatefulWidget {
  ///
  /// 接收全局设置 Store。
  const _MeaningMatchDurationRow({required this.settings});

  ///
  /// 全局设置 Store，读取与修改词义连连倒计时。
  final SettingsStore settings;

  ///
  /// 创建局部状态，避免连续点击造成多个 SharedPreferences 写入交错。
  @override
  State<_MeaningMatchDurationRow> createState() =>
      _MeaningMatchDurationRowState();
}

///
/// 管理词义连连倒计时步进按钮的异步保存状态。
///
class _MeaningMatchDurationRowState extends State<_MeaningMatchDurationRow> {
  ///
  /// true 表示正在等待 Android 确认磁盘写入。
  bool _isSaving = false;

  ///
  /// 把倒计时增加或减少一个步长（30 秒），并统一处理保存失败。
  Future<void> _change(int delta) async {
    // 保存期间忽略重复点击，避免较慢设备上发生写入顺序倒置。
    if (_isSaving) return;
    // 禁用两个按钮，直到本次写入结束。
    setState(() => _isSaving = true);
    try {
      // 基于当前已确认的秒数计算新值；Store 会把负数钳制为 0。
      await widget.settings.setMeaningMatchDuration(
        widget.settings.meaningMatchDuration + delta,
      );
    } catch (error) {
      // 写入失败时 Store 不改变内存值，并向用户说明原因。
      if (mounted) Toast.show(context, '词义连连倒计时保存失败：$error');
    } finally {
      // 抽屉仍在组件树中时恢复按钮。
      if (mounted) setState(() => _isSaving = false);
    }
  }

  ///
  /// 输出 52 高的步进器行。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // ListenableBuilder 让秒数值变化后只刷新本行。
    return ListenableBuilder(
      // 监听同一个全局 SettingsStore。
      listenable: widget.settings,
      // 根据最新秒数重新构建。
      builder: (context, child) {
        return _SettingRow(
          label: '词义连连',
          // 卡片内最后一行，不画分隔线。
          showDivider: false,
          // 右侧容器：与每日复习等宽的步进轨道。
          horizontalPadding: AppSpace.p2,
          control: Container(
            // 与每日复习等宽。
            width: _kSettingControlWidth,
            // 高度取分段轨道那一档（`controlTrackHeight`），与每日复习统一。
            height: HomeDrawerLayout.controlTrackHeight,
            padding: const EdgeInsets.all(AppSpace.p2),
            decoration: BoxDecoration(
              color: tokens.sub,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Row(
              children: [
                // 减 30：去掉边框，仅图标。
                Expanded(
                  child: InkWell(
                    key: const Key('meaning-match-minus'),
                    onTap: _isSaving ? null : () => unawaited(_change(-30)),
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                    child: Container(
                      height: HomeDrawerLayout.controlSegmentHeight,
                      alignment: Alignment.center,
                      child: Icon(AppGlyph.stepDown, color: tokens.textMedium),
                    ),
                  ),
                ),
                // 当前秒数（默认 150）。
                Container(
                  constraints: const BoxConstraints(
                    minWidth: HomeDrawerLayout.stepperValueMinWidth,
                  ),
                  height: HomeDrawerLayout.controlSegmentHeight,
                  alignment: Alignment.center,
                  child: Text(
                    widget.settings.meaningMatchDuration.toString(),
                    style: textTheme.fs5Semibold.copyWith(
                      // 等宽数字避免加减时宽度跳动。
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // 加 30：去掉边框，仅图标。
                Expanded(
                  child: InkWell(
                    key: const Key('meaning-match-plus'),
                    onTap: _isSaving ? null : () => unawaited(_change(30)),
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                    child: Container(
                      height: HomeDrawerLayout.controlSegmentHeight,
                      alignment: Alignment.center,
                      child: Icon(AppGlyph.stepUp, color: tokens.textMedium),
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
/// [horizontalPadding] 默认与菜单项同档（`pBase`，卡片外使用），卡片内统一传常规间隙那一档（`p2`）。
///
class _SettingRow extends StatelessWidget {
  ///
  /// label 是左侧字段名，control 是右侧控件。
  const _SettingRow({
    required this.label,
    required this.control,
    required this.showDivider,
    this.horizontalPadding = AppSpace.pBase,
  });

  ///
  /// 设置项名称。
  final String label;

  ///
  /// 右侧可操作控件。
  final Widget control;

  ///
  /// 是否绘制底部行分隔线。
  final bool showDivider;

  ///
  /// 横向内边距：卡片外与菜单项同档（`pBase`），卡片内收到常规间隙那一档（`p2`）。
  final double horizontalPadding;

  ///
  /// 输出 52 高的横向布局。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // Container 统一高度与分隔线。
    return Container(
      height: HomeDrawerLayout.rowHeight,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: tokens.rowBorder))
            : null,
      ),
      child: Row(
        children: [
          // 左侧标签。
          Text(
            // 正文那一档自带主文字色。
            label,
            style: textTheme.fs5,
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

///
/// 页脚：Github 图标 + 邮箱图标 + 日志导出图标，居左排列、有间隔。
///
/// 仅显示图标，不显示文字。整行位于抽屉底部。
///
class _DrawerFooter extends StatelessWidget {
  ///
  /// 接收三个点击动作。
  const _DrawerFooter({
    required this.onOpenGithub,
    required this.onCopyEmail,
    required this.onExportLog,
  });

  ///
  /// 点击 Github 项后用系统默认浏览器打开仓库。
  final VoidCallback onOpenGithub;

  ///
  /// 点击邮箱项后复制邮箱并提示。
  final VoidCallback onCopyEmail;

  ///
  /// 点击日志图标项后由首页弹系统保存框导出单日运行日志。
  final VoidCallback onExportLog;

  ///
  /// 输出水平排列的三个可点击项（Github / 邮箱 / 日志导出）。
  @override
  Widget build(BuildContext context) {
    // 读取当前明暗对应的设计令牌。
    final tokens = AppTokens.of(context);
    return Padding(
      // 上下都留一档基准间距（`p3`）：上方与分隔线分开，下方贴近抽屉底。
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pBase,
        AppSpace.p3,
        AppSpace.pBase,
        AppSpace.p3,
      ),
      child: Row(
        // 两图标居左排列。
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Github 图标项。
          InkWell(
            onTap: onOpenGithub,
            borderRadius: BorderRadius.circular(AppRadius.rounded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.p1),
              child: Icon(AppGlyph.github, color: tokens.textSecondary),
            ),
          ),
          // 两图标之间 16 像素间隔。
          const SizedBox(width: AppSpace.p3),
          // 邮箱图标项。
          InkWell(
            onTap: onCopyEmail,
            borderRadius: BorderRadius.circular(AppRadius.rounded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.p1),
              child: Icon(AppGlyph.mail, color: tokens.textSecondary),
            ),
          ),
          // 邮箱与日志图标之间 16 像素间隔。
          const SizedBox(width: AppSpace.p3),
          // 日志导出图标项：点击后由首页直接弹系统保存框，导出单日运行日志。
          InkWell(
            // key 供测试点击触发日志导出。
            key: const Key('drawer-export-log'),
            onTap: onExportLog,
            borderRadius: BorderRadius.circular(AppRadius.rounded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.p1),
              child: Icon(AppGlyph.logExport, color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
