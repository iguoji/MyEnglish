import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_log.dart';

/// 只在显式开启时测量「词库点击 → 内容完全显示且可以操作」。
///
/// 使用 --dart-define=PROFILE_STUDY_OPEN=true 开启；普通构建不创建计时器。
/// 所有节点先留在内存，结束时只写一条日志，避免每走一步写文件干扰测量。
/// 时间来自同一单调时钟，不受修改手机时间影响；日志不包含单词和答案正文。
class StudyOpenTiming {
  StudyOpenTiming._(this.module, this.wordCount)
    : id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      _started = Timeline.now {
    _marks['tap'] = 0;
    WidgetsBinding.instance.addTimingsCallback(_receiveFrames);
    // 诊断构建在模拟器或后台低速环境也要能采齐；该时限只控制日志观察，
    // 不会延长业务请求的等待，也不会延迟用户退出。
    _timeout = Timer(const Duration(minutes: 3), () => cancel('timeout'));
  }

  static const enabled = bool.fromEnvironment('PROFILE_STUDY_OPEN');
  static final Object _zoneKey = Object();
  static final Expando<StudyOpenTiming> _owners = Expando();
  static int _sequence = 0;

  /// 一次点击一个编号；同时打开不同模块也不会把两次计时混到一起。
  static StudyOpenTiming? start(String module, int wordCount) =>
      enabled ? StudyOpenTiming._(module, wordCount) : null;

  /// 异步开局链通过 Zone 携带计时对象，不给业务接口增加必填参数。
  static StudyOpenTiming? get current =>
      Zone.current[_zoneKey] as StudyOpenTiming?;

  /// 页面通过已有会话对象取回计时器，不把诊断字段写进数据库模型。
  static StudyOpenTiming? of(Object? owner) =>
      owner == null ? null : _owners[owner];

  final String id;
  final String module;
  final int wordCount;
  final int _started;
  final Map<String, int> _marks = {};
  final Map<String, Object?> _details = {};
  final Map<String, int> _frameTargets = {};
  final Map<String, Map<String, int>> _frames = {};
  final List<FrameTiming> _recentFrames = [];
  final List<VoidCallback> _removeListeners = [];
  Timer? _timeout;
  bool _done = false;
  bool _ready = false;
  bool _visible = false;
  bool _routeVisible = false;
  bool _finishing = false;
  int? _firstQuestion;

  T run<T>(T Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void attach(Object owner) => _owners[owner] = this;

  /// 同名节点只取第一次，后续预取下一题不会覆盖首题的数据。
  void mark(String name) {
    if (!_done) _marks.putIfAbsent(name, () => Timeline.now - _started);
  }

  void detail(String name, Object? value) {
    if (!_done) _details[name] = value;
  }

  bool tracksQuestion(int id) {
    if (_done || _ready) return false;
    _firstQuestion ??= id;
    return _firstQuestion == id;
  }

  /// 等待过渡屏的真实淡入动画结束；不能把透明度为零的首帧算成已显示。
  void watchVisibility(Animation<double> animation) {
    _watchAnimation(animation, () {
      _visible = true;
      mark('content_visible');
      _tryFinish();
    });
  }

  void _watchAnimation(Animation<double>? animation, VoidCallback complete) {
    if (_done) return;
    if (animation == null || animation.status == AnimationStatus.completed) {
      complete();
      return;
    }
    late AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listener);
      if (!_done) complete();
    };
    animation.addStatusListener(listener);
    _removeListeners.add(() => animation.removeStatusListener(listener));
  }

  /// 在页面首帧结束时调用，同时等待导航动画，短会话也不会提早报完成。
  void pageFrame(BuildContext context) {
    if (_done || _frameTargets.containsKey('page')) return;
    mark('page_framework_frame');
    _recordFrameTarget('page');
    _watchAnimation(ModalRoute.of(context)?.animation, () {
      _routeVisible = true;
      mark('route_visible');
      _tryFinish();
    });
  }

  /// 随身听在首帧就绪；听音辨义必须等首题候选保存并解除点击保护。
  void controlsReady() {
    if (_done || _ready) return;
    _ready = true;
    mark('controls_ready');
    _tryFinish();
  }

  void _tryFinish() {
    if (_done || _finishing || !_ready || !_visible || !_routeVisible) return;
    _finishing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_done) return;
      mark('interactive_framework_frame');
      _recordFrameTarget('interactive');
      _timeout?.cancel();
      // 引擎批量回传绘制耗时；等回传不计入用户等待，只使用帧本身的时间戳。
      _timeout = Timer(const Duration(seconds: 2), () {
        _write('framework_ready_raster_unavailable');
      });
      _matchFrames();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _recordFrameTarget(String name) {
    _frameTargets[name] =
        WidgetsBinding.instance.platformDispatcher.frameData.frameNumber;
  }

  void _receiveFrames(List<FrameTiming> timings) {
    if (_done) return;
    _recentFrames.addAll(timings);
    if (_recentFrames.length > 240) {
      _recentFrames.removeRange(0, _recentFrames.length - 240);
    }
    _matchFrames();
  }

  void _matchFrames() {
    for (final target in _frameTargets.entries) {
      if (_frames.containsKey(target.key)) continue;
      for (final frame in _recentFrames) {
        // 用引擎的帧编号配对，避开计划刷新时间与实际开始绘制时间的差异。
        if (frame.frameNumber != target.value) continue;
        _frames[target.key] = {
          'raster_finish_us':
              frame.timestampInMicroseconds(FramePhase.rasterFinish) - _started,
          'build_us': frame.buildDuration.inMicroseconds,
          'raster_us': frame.rasterDuration.inMicroseconds,
        };
        break;
      }
    }
    if (_frames.containsKey('interactive')) _write('ready');
  }

  void cancel(String reason) {
    if (_done) return;
    mark('cancelled');
    _write(reason);
  }

  void _write(String outcome) {
    if (_done) return;
    _done = true;
    _timeout?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_receiveFrames);
    for (final remove in _removeListeners) {
      remove();
    }
    if (outcome == 'framework_ready_raster_unavailable') {
      _details['frame_targets'] = _frameTargets;
      _details['received_frames'] = _recentFrames.length;
      _details['recent_frame_numbers'] = _recentFrames
          .map((frame) => frame.frameNumber)
          .toList();
    }
    AppLog.i(
      'study_open',
      jsonEncode({
        'trace_id': id,
        'module': module,
        'words': wordCount,
        'mode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'outcome': outcome,
        'marks_us': _marks,
        'frames': _frames,
        'details': _details,
      }),
    );
  }
}
