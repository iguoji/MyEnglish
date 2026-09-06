// material.dart 提供 Overlay、OverlayEntry 和动画组件。
import 'package:flutter/material.dart';

// 设计令牌总表：本文件顶部那张小表只负责给 Toast 的方寸起业务名字，
// 数值凡是总表有台阶的一律引用台阶（相当于组件专属 CSS 继承基础 CSS）。
import '../common/theme.dart';

///
/// Toast 的布局尺寸表。
///
/// Toast 是跨页面共用的组件，所以它的样式表就写在自己文件的开头——和键盘、
/// 字母格、词性及含义面板一样。这张表只有五档，全部只服务于屏幕底部那一个
/// 黑色小胶囊。
///
abstract final class ToastLayout {
  ///
  /// 胶囊距离屏幕底部的高度。
  ///
  /// 抬这么高是为了躲开系统手势导航条：贴着底边显示的话，用户想把它划走时
  /// 很容易先触发系统返回。
  ///
  /// 名字里的 `screen` 用来和听音辨义的 `bottomActionInset` 区分：那一档说的是
  /// 「底部操作区在安全区之上再留多少」，这一档说的是「浮层离屏幕底边多远」。
  static const double screenBottomInset = AppSpace.p5;

  ///
  /// 胶囊的最大宽度。
  ///
  /// 用最大宽度而不是写死宽度：短消息按文字自然收窄成一颗小胶囊，长消息才撑到
  /// 这个上限并换行。横屏时如果不限宽，一句话会拉成横贯整个屏幕的一条，很难读。
  static const double maxWidth = 320;

  ///
  /// 胶囊投影的扩散范围。
  ///
  /// 比全站卡片那一档（`AppShadow.cardBlur`）散得多：卡片是「贴在页面上的一张
  /// 纸」，Toast 是「盖在所有界面之上的一层浮层」，影子散开才有那种悬空感。
  /// 但也远不到词库面板那一档（`WordLibraryLayout.panelShadowBlur`，24）——
  /// 那是盖满整屏的大面板，这只是一颗小胶囊。
  static const double capsuleShadowBlur = 8;

  ///
  /// 胶囊投影往下偏移的距离。
  ///
  /// 同样比卡片那一档沉得多，理由和 [capsuleShadowBlur] 一样。
  static const double capsuleShadowOffsetY = 2;
}

///
/// 全局 Toast 工具：基于根 Navigator 的 Overlay 显示提示。
///
/// 解决 ScaffoldMessenger/SnackBar 被 Drawer、BottomSheet、Dialog 等
/// modal route 遮挡的问题——Overlay 层级高于一切 modal route，
/// 因此 Toast 始终显示在最顶层。
///
/// 全系统统一调用 `Toast.show(context, '消息')`，
/// 替代各处分散的 `ScaffoldMessenger.of(context).showSnackBar()`。
///
abstract final class Toast {
  ///
  /// 当前正在显示的 OverlayEntry；同一时间只保留一条 Toast。
  static OverlayEntry? _currentEntry;

  ///
  /// 显示一条 Toast 消息，默认 2 秒后自动消失。
  ///
  /// [context] 用于获取根 Navigator 的 Overlay；传入任意 BuildContext 即可。
  /// [message] 是提示文案。
  /// [duration] 控制显示时长，默认 2 秒。
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    // 获取根 Navigator 的 Overlay，确保层级高于 Drawer/BottomSheet/Dialog。
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    // 极端情况（测试环境无 Overlay）静默忽略，不崩溃。
    if (overlay == null) return;

    // 移除上一条 Toast（如果有），避免堆叠。
    _currentEntry?.remove();
    _currentEntry = null;

    // 创建新的 OverlayEntry，构建 Toast 视觉。
    // late 让 onDismiss 闭包能引用 entry 自身（Dart 闭包捕获延迟求值）。
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastView(
        message: message,
        duration: duration,
        onDismiss: () {
          // 定时器到期后移除自身。
          entry.remove();
          // 如果仍是当前条目，清空引用。
          if (_currentEntry == entry) {
            _currentEntry = null;
          }
        },
      ),
    );

    // 记录当前条目，供下一次 show 移除。
    _currentEntry = entry;
    // 插入到根 Overlay，显示在最顶层。
    overlay.insert(entry);
  }
}

///
/// Toast 的视觉实现：底部居中的圆角深色卡片，文字居中。
///
class _ToastView extends StatefulWidget {
  ///
  /// 创建 Toast 视图。
  const _ToastView({
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  ///
  /// 提示文案。
  final String message;

  ///
  /// 显示时长。
  final Duration duration;

  ///
  /// 定时器到期后的回调，用于移除 OverlayEntry。
  final VoidCallback onDismiss;

  ///
  /// 创建状态。
  @override
  State<_ToastView> createState() => _ToastViewState();
}

///
/// 管理 Toast 的进场/退场动画与定时器。
///
class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  ///
  /// 进场/退场动画控制器。
  late final AnimationController _controller;

  ///
  /// 动画曲线，0→1 进场、1→0 退场。
  late final Animation<double> _animation;

  ///
  /// 定时器到期后自动移除。
  @override
  void initState() {
    // 保留父类初始化。
    super.initState();
    // 进出场动画时长走 AppDuration 的 160 毫秒这一档（原来写死 200）。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppDuration.ms160),
    );
    // Curves.easeOut 让进场自然减速。
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    // 开始进场动画。
    _controller.forward();
    // 显示时长到期后执行退场动画再移除。
    Future.delayed(widget.duration, () {
      // 组件可能已被移除，检查 mounted。
      if (!mounted) return;
      // 先执行退场动画。
      _controller.reverse().then((_) {
        // 退场动画完成后通知外部移除 OverlayEntry。
        widget.onDismiss();
      });
    });
  }

  ///
  /// 释放动画控制器。
  @override
  void dispose() {
    // 释放控制器资源。
    _controller.dispose();
    // 父类清理。
    super.dispose();
  }

  ///
  /// 输出底部居中的 Toast 视觉。
  @override
  Widget build(BuildContext context) {
    // Toast 挂在根 Overlay 上，仍在 MaterialApp 的主题范围内，
    // 所以这里能正常读到全站统一的文字样式表。
    final textTheme = Theme.of(context).textTheme;
    // SafeArea 避开导航栏和状态栏。
    return Positioned(
      // 抬离底边一段距离，躲开系统手势导航条。
      bottom: ToastLayout.screenBottomInset,
      // 左右撑开，让内部居中。
      left: 0,
      right: 0,
      child: SafeArea(
        // Minimum 避免被系统手势区域遮挡。
        minimum: const EdgeInsets.symmetric(horizontal: AppSpace.p3),
        child: Center(
          child: FadeTransition(
            // 进出场淡入淡出。
            opacity: _animation,
            child: Material(
              // 透明背景，让圆角卡片自身承载底色。
              color: Colors.transparent,
              child: Container(
                // 限制最大宽度，避免横屏时过宽。
                constraints: const BoxConstraints(
                  maxWidth: ToastLayout.maxWidth,
                ),
                // 横向与纵向都用基准那一档内边距（`p3`）：贴 Tabler 档之前纵向比横向小一档，
                // 现在并成同一个值，气泡略高一点、更接近方胶囊。
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.p3,
                  vertical: AppSpace.p3,
                ),
                decoration: BoxDecoration(
                  // 深色底，浅色文字，与 SnackBar 视觉一致。
                  color: AppTokens.toastSurface,
                  // 8 像素圆角。
                  borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  // 轻微阴影提升层次感。
                  boxShadow: const [
                    BoxShadow(
                      color: AppTokens.toastShadow,
                      blurRadius: ToastLayout.capsuleShadowBlur,
                      offset: Offset(0, ToastLayout.capsuleShadowOffsetY),
                    ),
                  ],
                ),
                // 文字居中对齐。
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  // 深色胶囊上的白字：读全站正文那一档（`fs5`），只换颜色。
                  // 行距不必再写——那一档自带 1.43，写一遍只是重复。
                  style: textTheme.fs5.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
