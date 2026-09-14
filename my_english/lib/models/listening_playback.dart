import 'dart:convert';

/// 随身听唯一的播放清单与续播位置。只保存单词编号，正文始终从词库读取。
/// 列表和游标放在同一个设置值里，一次写入，避免退出时出现新列表配旧进度。
class ListeningPlayback {
  const ListeningPlayback({
    required this.revision,
    required this.wordIds,
    this.cursor = 0,
    this.elapsedSeconds = 0,
    this.completedRepeats = 0,
    this.remainingSeconds = 0,
    this.waitingInterval = false,
    this.isPlaying = false,
    this.isFinished = false,
  });

  static const empty = ListeningPlayback(revision: 'empty', wordIds: <int>[]);

  /// 每次主动换清单产生新编号，旧页面迟到的保存不能覆盖新清单。
  final String revision;
  final List<int> wordIds;
  final int cursor;
  final int elapsedSeconds;
  final int completedRepeats;
  final int remainingSeconds;
  final bool waitingInterval;
  final bool isPlaying;
  final bool isFinished;

  bool get hasWords => wordIds.isNotEmpty;

  factory ListeningPlayback.start(Iterable<int> ids) {
    final ordered = ids.where((id) => id > 0).toSet().toList(growable: false);
    return ListeningPlayback(
      revision: DateTime.now().microsecondsSinceEpoch.toString(),
      wordIds: List<int>.unmodifiable(ordered),
      isPlaying: ordered.isNotEmpty,
    );
  }

  factory ListeningPlayback.fromJson(String? source) {
    if (source == null || source.isEmpty) return empty;
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('随身听播放状态必须是对象');
    final rawIds = decoded['word_ids'];
    if (rawIds is! List) throw const FormatException('随身听缺少单词编号列表');
    final ids = <int>[];
    for (final value in rawIds) {
      if (value is! int || value <= 0) {
        throw const FormatException('随身听单词编号必须是正整数');
      }
      ids.add(value);
    }
    if (ids.toSet().length != ids.length) {
      throw const FormatException('随身听单词编号不能重复');
    }
    int number(String key) {
      final value = decoded[key];
      return value is num ? value.toInt().clamp(0, 1 << 31) : 0;
    }

    final finished = decoded['is_finished'] == true && ids.isNotEmpty;
    return ListeningPlayback(
      revision: decoded['revision']?.toString() ?? 'restored',
      wordIds: List<int>.unmodifiable(ids),
      cursor: ids.isEmpty ? 0 : number('cursor').clamp(0, ids.length - 1),
      elapsedSeconds: number('elapsed_seconds'),
      completedRepeats: number('completed_repeats'),
      remainingSeconds: number('remaining_seconds'),
      waitingInterval: decoded['waiting_interval'] == true,
      isPlaying: ids.isNotEmpty && !finished && decoded['is_playing'] == true,
      isFinished: finished,
    );
  }

  /// 恢复时剔除已经不存在的词，按原位置找下一个，而不是从清单头部重新开始。
  ListeningPlayback retainExisting(Set<int> existing, {required bool loop}) {
    final kept = wordIds.where(existing.contains).toList(growable: false);
    if (kept.length == wordIds.length) return this;
    if (kept.isEmpty) {
      return copyWith(
        wordIds: const <int>[],
        cursor: 0,
        completedRepeats: 0,
        remainingSeconds: 0,
        waitingInterval: false,
        isPlaying: false,
        isFinished: false,
      );
    }
    final next = wordIds.take(cursor).where(existing.contains).length;
    final currentRemoved = !existing.contains(wordIds[cursor]);
    final atEnd = next >= kept.length;
    return copyWith(
      wordIds: kept,
      cursor: atEnd ? (loop ? 0 : kept.length - 1) : next,
      completedRepeats: currentRemoved ? 0 : completedRepeats,
      remainingSeconds: currentRemoved ? 0 : remainingSeconds,
      waitingInterval: currentRemoved ? false : waitingInterval,
      isPlaying: isPlaying && !(atEnd && !loop),
      isFinished: isFinished || (atEnd && !loop),
    );
  }

  ListeningPlayback copyWith({
    List<int>? wordIds,
    int? cursor,
    int? elapsedSeconds,
    int? completedRepeats,
    int? remainingSeconds,
    bool? waitingInterval,
    bool? isPlaying,
    bool? isFinished,
  }) => ListeningPlayback(
    revision: revision,
    wordIds: wordIds == null ? this.wordIds : List<int>.unmodifiable(wordIds),
    cursor: cursor ?? this.cursor,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    completedRepeats: completedRepeats ?? this.completedRepeats,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    waitingInterval: waitingInterval ?? this.waitingInterval,
    isPlaying: isPlaying ?? this.isPlaying,
    isFinished: isFinished ?? this.isFinished,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'revision': revision,
    'word_ids': wordIds,
    'cursor': cursor,
    'elapsed_seconds': elapsedSeconds,
    'completed_repeats': completedRepeats,
    'remaining_seconds': remainingSeconds,
    'waiting_interval': waitingInterval,
    'is_playing': isPlaying,
    'is_finished': isFinished,
  };
}
