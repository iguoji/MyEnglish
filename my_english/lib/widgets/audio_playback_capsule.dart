import 'dart:async';
import 'package:flutter/material.dart';
import '../common/theme.dart';
import 'audio_speaker_button.dart';

/// 播音胶囊的固定尺寸及声纹参数，两种模块共用同一份。
abstract final class AudioCapsuleLayout {
  static const double playbackCircleSize = AppSize.speakerButton;
  static const double playbackWidth = 196;
  static const double playbackTextWidth = 108;
  static const double playbackIconSize = AppIcon.i20;
  static const double playbackCirclePadding = AppSpace.p2;
  static const double playbackVerticalPadding = AppSpace.p2;
  static const double playbackTextPaddingRight = AppSpace.p3;
  static const double playbackContentGap = AppSpace.p3;
  static const double waveHeight = 12;
  static const int waveBarCount = 21;
  static const double waveBarWidth = 2.5;
  static const int waveTickMs = AppDuration.ms100;
  static const List<double> waveIdleHeights = <double>[
    3,
    4,
    6,
    8,
    10,
    8,
    6,
    4,
    6,
    8,
    11,
    9,
    6,
    4,
    7,
    9,
    8,
    6,
    4,
    3,
    3,
  ];
  static const double waveMinHeight = 3;
  static const double waveMaxExtraHeight = 8;
  static const double playbackLabelGap = AppSpace.p1;
  static const double playbackLabelLetterSpacing = 1.2;
}

/// 扬声器、声纹与口音状态共用同一个播放状态，离场时释放动画。
class AudioPlaybackCapsule extends StatefulWidget {
  const AudioPlaybackCapsule({
    required this.isPlaying,
    required this.onTap,
    required this.accentLabel,
    super.key,
  });

  final bool isPlaying;
  final VoidCallback onTap;
  final String accentLabel;

  @override
  State<AudioPlaybackCapsule> createState() => _AudioPlaybackCapsuleState();
}

class _AudioPlaybackCapsuleState extends State<AudioPlaybackCapsule> {
  final ValueNotifier<double> _waveProgress = ValueNotifier<double>(0);
  Timer? _waveTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _startWaveTimer();
  }

  @override
  void didUpdateWidget(covariant AudioPlaybackCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying) return;
    if (widget.isPlaying) {
      _startWaveTimer();
    } else {
      _stopWaveTimer();
    }
  }

  void _startWaveTimer() {
    if (_waveTimer != null) return;
    _waveTimer = Timer.periodic(
      const Duration(milliseconds: AudioCapsuleLayout.waveTickMs),
      (_) {
        if (!mounted || !widget.isPlaying) return;
        _waveProgress.value = (_waveProgress.value + 0.12) % 1;
      },
    );
  }

  void _stopWaveTimer() {
    _waveTimer?.cancel();
    _waveTimer = null;
    _waveProgress.value = 0;
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _waveProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final statusLabel = widget.isPlaying ? '播放中' : '点击播放';
    final waveColor = widget.isPlaying ? AppTokens.primary : tokens.muted;

    return Semantics(
      button: true,
      label: '播放发音',
      child: SizedBox(
        width: AudioCapsuleLayout.playbackWidth,
        child: Material(
          // 胶囊底色用专门的 capsule 令牌，不再借用页面底色 page：
          // 两者数值相同，但页面底色以后要是变了，胶囊不该跟着变。
          color: tokens.capsule,
          borderRadius: BorderRadius.circular(AppRadius.roundedPill),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.roundedPill),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AudioCapsuleLayout.playbackCirclePadding,
                AudioCapsuleLayout.playbackVerticalPadding,
                AudioCapsuleLayout.playbackTextPaddingRight,
                AudioCapsuleLayout.playbackVerticalPadding,
              ),
              child: Row(
                children: [
                  AudioSpeakerButton(
                    isPlaying: widget.isPlaying,
                    onTap: widget.onTap,
                    size: AudioCapsuleLayout.playbackCircleSize,
                    iconSize: AudioCapsuleLayout.playbackIconSize,
                  ),
                  const SizedBox(width: AudioCapsuleLayout.playbackContentGap),
                  SizedBox(
                    width: AudioCapsuleLayout.playbackTextWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: AudioCapsuleLayout.waveHeight,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _waveProgress,
                            builder: (context, progress, _) => Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                for (
                                  var index = 0;
                                  index < AudioCapsuleLayout.waveBarCount;
                                  index += 1
                                )
                                  _PlaybackWaveBar(
                                    color: waveColor,
                                    height: _waveHeight(index, progress),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: AudioCapsuleLayout.playbackLabelGap,
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(
                            milliseconds: AppDuration.ms160,
                          ),
                          // 用 Align(centerLeft) 把状态文字钉在左侧：
                          // AnimatedSwitcher 默认 Stack alignment.center，
                          // 切换「点击播放」↔「播放中」时文字宽度变窄，
                          // 没有 Align 的话 Stack 会按最大子宽度居中叠放，
                          // 短文本看起来会向左/右跳一段。
                          // 拼写巩固的胶囊早就包了 Align，这里补上同一层
                          // 包裹，两个页面的胶囊从此行为完全一致。
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${widget.accentLabel} · $statusLabel',
                              key: ValueKey(
                                '${widget.accentLabel}-$statusLabel',
                              ),
                              maxLines: 1,
                              softWrap: false,
                              style: textTheme.fs6Semibold.copyWith(
                                color: AppTokens.primary.withValues(
                                  alpha: AppAlpha.a70,
                                ),
                                // 这一处刻意比全站字距宽得多，几个字才拉得开。
                                letterSpacing: AudioCapsuleLayout
                                    .playbackLabelLetterSpacing,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _waveHeight(int index, double progress) {
    if (!widget.isPlaying) return AudioCapsuleLayout.waveIdleHeights[index];
    final phase = (progress + index * 0.17) % 1;
    final pulse = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return AudioCapsuleLayout.waveMinHeight +
        AudioCapsuleLayout.waveMaxExtraHeight * (0.35 + pulse * 0.65);
  }
}

/// 播音胶囊中的单根声纹竖条。
class _PlaybackWaveBar extends StatelessWidget {
  const _PlaybackWaveBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AudioCapsuleLayout.waveBarWidth,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.roundedPill),
      ),
    ),
  );
}
