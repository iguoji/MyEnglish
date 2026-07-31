// material.dart 提供 Overlay、OverlayEntry 和动画组件。
import 'package:flutter/material.dart';

/// 全局 Toast 工具：基于根 Navigator 的 Overlay 显示提示。
///
/// 解决 ScaffoldMessenger/SnackBar 被 Drawer、BottomSheet、Dialog 等
/// modal route 遮挡的问题——Overlay 层级高于一切 modal route，
/// 因此 Toast 始终显示在最顶层。
///
/// 全系统统一调用 `Toast.show(context, '消息')`，
/// 替代各处分散的 `ScaffoldMessenger.of(context).showSnackBar()`。
abstract final class Toast {
  /// 当前正在显示的 OverlayEntry；同一时间只保留一条 Toast。
  static OverlayEntry? _currentEntry;

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

/// Toast 的视觉实现：底部居中的圆角深色卡片，文字居中。
class _ToastView extends StatefulWidget {
  /// 创建 Toast 视图。
  const _ToastView({
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  /// 提示文案。
  final String message;

  /// 显示时长。
  final Duration duration;

  /// 定时器到期后的回调，用于移除 OverlayEntry。
  final VoidCallback onDismiss;

  /// 创建状态。
  @override
  State<_ToastView> createState() => _ToastViewState();
}

/// 管理 Toast 的进场/退场动画与定时器。
class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  /// 进场/退场动画控制器。
  late final AnimationController _controller;

  /// 动画曲线，0→1 进场、1→0 退场。
  late final Animation<double> _animation;

  /// 定时器到期后自动移除。
  @override
  void initState() {
    // 保留父类初始化。
    super.initState();
    // 动画时长 200ms。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Curves.easeOut 让进场自然减速。
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
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

  /// 释放动画控制器。
  @override
  void dispose() {
    // 释放控制器资源。
    _controller.dispose();
    // 父类清理。
    super.dispose();
  }

  /// 输出底部居中的 Toast 视觉。
  @override
  Widget build(BuildContext context) {
    // SafeArea 避开导航栏和状态栏。
    return Positioned(
      // 底部偏移 32，与 SnackBar 默认位置接近。
      bottom: 32,
      // 左右撑开，让内部居中。
      left: 0,
      right: 0,
      child: SafeArea(
        // Minimum 避免被系统手势区域遮挡。
        minimum: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: FadeTransition(
            // 进出场淡入淡出。
            opacity: _animation,
            child: Material(
              // 透明背景，让圆角卡片自身承载底色。
              color: Colors.transparent,
              child: Container(
                // 限制最大宽度，避免横屏时过宽。
                constraints: const BoxConstraints(maxWidth: 320),
                // 横向 16 纵向 12 内边距。
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  // 深色底，浅色文字，与 SnackBar 视觉一致。
                  color: const Color(0xFF182433),
                  // 8 像素圆角。
                  borderRadius: BorderRadius.circular(8),
                  // 轻微阴影提升层次感。
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                // 文字居中对齐。
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
