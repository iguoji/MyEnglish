import 'package:flutter/material.dart';
import '../common/theme.dart';

/// 只过渡题目内容，保留外层白卡、布局和操作区域；旧内容淡出时不再接受点击。
class QuestionContentTransition extends StatelessWidget {
  const QuestionContentTransition({
    required this.contentKey,
    required this.child,
    super.key,
  });
  final Object contentKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: AppDuration.ms160),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // 新旧内容都保留同一层包裹，并沿用过渡组件给出的身份。
        // 当前题移到淡出层时就能保留原来的字母动画状态；只给旧题临时加一层
        // IgnorePointer 会把它整棵重建，造成已填字母先消失、重播入场再淡出。
        for (final old in previous) IgnorePointer(key: old.key, child: old),
        if (current != null)
          IgnorePointer(key: current.key, ignoring: false, child: current),
      ],
    ),
    child: KeyedSubtree(key: ValueKey<Object>(contentKey), child: child),
  );
}
