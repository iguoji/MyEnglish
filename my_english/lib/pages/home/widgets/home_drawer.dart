// material.dart 提供 Drawer、ListTile 风格布局所需组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 统一提供应用内图标，避免使用 Flutter Material 内置图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

/// 右侧抽屉菜单：App 信息、数据与设置入口与页脚联系方式。
class HomeDrawer extends StatelessWidget {
  /// 各入口的动作全部由首页注入，抽屉自身不包含业务逻辑。
  const HomeDrawer({
    required this.onAddWord,
    required this.onOpenSettings,
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

  /// 点击"设置"后由首页打开设置面板。
  final VoidCallback onOpenSettings;

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
        // Column 从上到下排列头部、菜单项和页脚。
        child: Column(
          // 子项默认左对齐。
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
                          style: TextStyle(color: tokens.muted, fontSize: 12),
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
            // 基础入口：添加单词与设置。
            _DrawerItem(
              key: const Key('drawer-add-word'),
              icon: TablerIcons.circlePlus,
              label: '添加单词',
              onTap: onAddWord,
            ),
            _DrawerItem(
              key: const Key('drawer-settings'),
              icon: TablerIcons.adjustmentsHorizontal,
              label: '设置',
              onTap: onOpenSettings,
            ),
            // 数据与设置之间的细分隔线。
            Divider(height: 1, color: tokens.rowBorder),
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
            // Spacer 把页脚推到底部。
            const Spacer(),
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
                  // InkWell 提供点击水波纹反馈；brandGithub 是 Tabler 的品牌图标。
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

/// 抽屉里的单个功能入口：左图标右文字，整行可点。
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
