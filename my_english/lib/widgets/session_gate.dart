import 'dart:async';

import 'package:flutter/material.dart';

import '../common/theme.dart';
import '../services/study_open_timing.dart';
import 'module_scaffold.dart';

///
/// 「这一局还没准备好」时的过渡屏。
///
/// 生活化解释：从词库底部随手开一局，如果不勾选任何单词，等于把整个词库
/// （上千个词、几千条含义）拿去做一整局试卷、再写进数据库，这段活要一秒多。
/// 以前是**先做完才跳页**，用户点完按钮只能对着不动的首页发呆；现在点下去
/// 立刻跳到这一屏，转圈等它做完，做完直接换成真正的答题页。
///
/// 等待时间没有变短，变清楚的是「点下去有反应了」和「现在到底在等什么」。
///
/// 用法（一局还在现开时）：
/// ```dart
/// MaterialPageRoute<dynamic>(
///   builder: (_) => SessionGate<SessionProgress>(
///     pending: _openAdHocSession(module, words),
///     builder: (progress) => ListeningMeaningPage(progress: progress, ...),
///   ),
/// )
/// ```
///
/// 已经是现成的一局（继续上次、首页复习卡片）时直接传值，不传 Future，
/// 这样第一帧就是真正的页面，不会白闪一下过渡屏。
class SessionGate<T extends Object> extends StatefulWidget {
  ///
  /// 创建这一局的入口。
  const SessionGate({
    required this.pending,
    required this.builder,
    this.onDiscard,
    super.key,
  });

  ///
  /// 这一局的准备过程：要么是一个还没完成的 Future，要么是一个现成的值。
  final FutureOr<T?> pending;

  ///
  /// 准备好之后真正要显示的页面。
  final Widget Function(T value) builder;

  /// 准备期间退出时释放迟到结果的监听器，避免后台继续持有整局数据。
  final ValueChanged<T>? onDiscard;

  @override
  State<SessionGate<T>> createState() => _SessionGateState<T>();
}

///
/// 管理「还在等 / 已经好了 / 开不出来」三种状态。
class _SessionGateState<T extends Object> extends State<SessionGate<T>> {
  ///
  /// 已经准备好的一局；为空表示还在准备。
  T? _value;

  /// 真正的页面接手后由页面负责释放，避免同一份资源被重复清理。
  bool _delivered = false;

  ///
  /// 这一局开不出来（没有可学单词、数据库报错等）时置位。
  ///
  /// 单独记一个标记，是为了不把「还在准备」和「准备失败」混成一件事——
  /// 混在一起就会留下一个永远转不完的圈。
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final pending = widget.pending;
    if (pending is Future<T?>) {
      // 还在现开：先显示过渡屏，等它回来再换成真正的页面。
      unawaited(
        pending.then(
          _settle,
          onError: (Object error, StackTrace stack) {
            // 失败的提示由发起方（首页）负责，这里只把过渡屏收掉。
            debugPrint('准备这一局失败：$error');
            _settle(null);
          },
        ),
      );
      return;
    }
    // 已经拿在手上的一局：直接上，不闪加载态。
    _value = pending;
  }

  ///
  /// 接住准备结果；[value] 为空表示这一局没开出来。
  void _settle(T? value) {
    if (!mounted) {
      StudyOpenTiming.of(value)?.cancel('gate_closed');
      if (value != null) widget.onDiscard?.call(value);
      return;
    }
    setState(() {
      _value = value;
      _failed = value == null;
    });
  }

  @override
  void dispose() {
    final value = _value;
    StudyOpenTiming.of(value)?.cancel('gate_closed');
    // 结果刚到、下一帧尚未显示便退出时，也要清掉无人接手的监听器。
    if (!_delivered && value != null) widget.onDiscard?.call(value);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value != null) _delivered = true;
    // 准备完成时短暂淡入答题页，等待和内容使用同一块页面区域。
    if (_failed) {
      // 开不出来就退回上一页。放在这一帧之后执行：在 build 里直接 pop 会踩到
      // 导航栈「正在构建时不能改动」的断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    return AnimatedSwitcher(
      // 保留默认淡入，只观察动画何时真正完成，避免把透明首帧报成可操作。
      transitionBuilder: (child, animation) {
        if (child.key == const ValueKey('prepared-session')) {
          StudyOpenTiming.of(value)?.watchVisibility(animation);
        }
        return AnimatedSwitcher.defaultTransitionBuilder(child, animation);
      },
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: AppDuration.ms160),
      child: value == null
          ? const _PreparingView()
          : KeyedSubtree(
              key: const ValueKey('prepared-session'),
              child: widget.builder(value),
            ),
    );
  }
}

///
/// 过渡屏本体：与答题页同一套骨架，只把正文换成一个转圈。
///
/// 顶栏留着、进度条留一条空的，都是为了让真正的答题页换上来的那一刻**顶栏不跳**
/// ——两边的高度、左右留白、返回键位置完全一样，用户只会觉得「正文出来了」。
class _PreparingView extends StatelessWidget {
  ///
  /// 创建过渡屏；没有可传的参数，文案与骨架都固定。
  const _PreparingView();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ModuleScaffold(
      header: ModuleHeader(
        // 中间不报「第几个 / 总数」：这一局有几题要等试卷建好才知道，
        // 先只说清楚在做什么，不编一个假的进度。
        title: Text(
          '正在准备',
          style: textTheme.fs4Semibold.copyWith(color: tokens.textMedium),
        ),
        // 空进度条：只为了让顶栏高度与答题页一致，换页时整页不会上下跳一下。
        progress: 0,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: AppSize.loadingIndicator,
              height: AppSize.loadingIndicator,
              child: CircularProgressIndicator(strokeWidth: AppStroke.ring),
            ),
            const SizedBox(height: AppSpace.p3),
            Text(
              '正在准备这一局…',
              style: textTheme.fs5.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
