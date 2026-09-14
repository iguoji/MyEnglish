import 'dart:math';

/// 把配对分散到各轮：先保证同轮单词和含义都不同，实在凑不齐才复用单词。
/// 每轮都先安排尚未练到的内容，补位只影响排列，不会漏掉任何原始配对。
abstract final class MatchingRoundBuilder {
  static List<List<Map<String, Object?>>> build(
    List<Map<String, Object?>> questions,
  ) {
    if (questions.isEmpty) return const [];
    final pairs = <_Pair>[
      for (var i = 0; i < questions.length; i++) _Pair(i, questions[i]),
    ];
    final byWord = <String, List<_Pair>>{};
    final definitionTotals = <String, int>{};
    for (final pair in pairs) {
      (byWord[pair.word] ??= []).add(pair);
      definitionTotals.update(
        pair.definition,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final rowCount = min(5, definitionTotals.length);
    final estimatedRounds = <int>[
      (pairs.length / rowCount).ceil(),
      ...byWord.values.map((items) => items.length),
      ...definitionTotals.values,
    ].reduce(max);
    final pending = pairs.toSet();
    final remainingByWord = <String, int>{
      for (final entry in byWord.entries) entry.key: entry.value.length,
    };
    final completedByWord = <String, int>{};
    final completedByDefinition = <String, int>{};
    final usesByWord = <String, int>{};
    final lastWordRound = <String, int>{};
    final usesByPair = <int, int>{};
    var wordIndex = 0;
    final wordOrder = <String, int>{
      for (final word in byWord.keys) word: wordIndex++,
    };
    final rounds = <List<_Pair>>[];

    while (pending.isNotEmpty) {
      final turn = rounds.length + 1;
      // 按“到这一轮应出现多少次，实际才出现多少次”排序，让多义词提前分散。
      // 补位时再按使用次数和距上次出现的轮数轮换，避免总是复用最初的几个词。
      int compareWords(String a, String b) {
        final aPending = remainingByWord[a]! > 0;
        final bPending = remainingByWord[b]! > 0;
        if (aPending != bPending) return aPending ? -1 : 1;
        if (aPending) {
          final aDue =
              byWord[a]!.length * turn -
              (completedByWord[a] ?? 0) * estimatedRounds;
          final bDue =
              byWord[b]!.length * turn -
              (completedByWord[b] ?? 0) * estimatedRounds;
          if (aDue != bDue) return bDue.compareTo(aDue);
        }
        final usage = (usesByWord[a] ?? 0).compareTo(usesByWord[b] ?? 0);
        if (usage != 0) return usage;
        final last = (lastWordRound[a] ?? -1).compareTo(lastWordRound[b] ?? -1);
        return last != 0 ? last : wordOrder[a]!.compareTo(wordOrder[b]!);
      }

      int comparePairs(_Pair a, _Pair b) {
        final aNew = pending.contains(a);
        final bNew = pending.contains(b);
        if (aNew != bNew) return aNew ? -1 : 1;
        if (aNew) {
          final aDue =
              definitionTotals[a.definition]! * turn -
              (completedByDefinition[a.definition] ?? 0) * estimatedRounds;
          final bDue =
              definitionTotals[b.definition]! * turn -
              (completedByDefinition[b.definition] ?? 0) * estimatedRounds;
          if (aDue != bDue) return bDue.compareTo(aDue);
        }
        final used = (usesByPair[a.order] ?? 0).compareTo(
          usesByPair[b.order] ?? 0,
        );
        return used != 0 ? used : a.order.compareTo(b.order);
      }

      final words = byWord.keys.toList()..sort(compareWords);
      final allEdges = <String, List<_Pair>>{
        for (final word in words)
          word: (List<_Pair>.of(byWord[word]!)..sort(comparePairs)),
      };
      final newEdges = <String, List<_Pair>>{
        for (final word in words)
          word: allEdges[word]!.where(pending.contains).toList(),
      };
      final fresh = _match(newEdges, words, rowCount);
      var selected = fresh;
      if (fresh.length < rowCount && fresh.length < pending.length) {
        // 先锁定一道新题，再检查所有单词的其他含义，寻找不重复单词的补位。
        // 锁定新题保证每轮都有实际进展，不能为了满五行反复练旧题而不往前走。
        final anchors = <_Pair>{...fresh, ...pending};
        var bestFresh = fresh.length;
        for (final anchor in anchors) {
          final candidate = _match(allEdges, words, rowCount, anchor: anchor);
          final newCount = candidate.where(pending.contains).length;
          if (candidate.length > selected.length ||
              (candidate.length == selected.length && newCount > bestFresh)) {
            selected = candidate;
            bestFresh = newCount;
          }
          if (selected.length == rowCount && bestFresh == fresh.length) break;
        }
      }
      // 最后一轮不硬补；否则先保留不同单词的安排，最后才允许同词其他含义补位。
      final newCount = selected.where(pending.contains).length;
      if (newCount == pending.length) {
        selected = selected.where(pending.contains).toList();
      } else if (selected.length < rowCount) {
        final usedDefinitions = selected.map((pair) => pair.definition).toSet();
        final fillers = List<_Pair>.of(pairs)
          ..sort((a, b) {
            final freshOrder = (pending.contains(a) ? 0 : 1).compareTo(
              pending.contains(b) ? 0 : 1,
            );
            if (freshOrder != 0) return freshOrder;
            final word = compareWords(a.word, b.word);
            return word != 0 ? word : comparePairs(a, b);
          });
        selected = List<_Pair>.of(selected);
        for (final pair in fillers) {
          if (selected.length >= rowCount) break;
          if (usedDefinitions.add(pair.definition)) selected.add(pair);
        }
      }
      selected.sort((a, b) {
        final word = wordOrder[a.word]!.compareTo(wordOrder[b.word]!);
        return word != 0 ? word : a.order.compareTo(b.order);
      });
      for (final pair in selected) {
        if (pending.remove(pair)) {
          remainingByWord[pair.word] = remainingByWord[pair.word]! - 1;
          completedByWord.update(
            pair.word,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          completedByDefinition.update(
            pair.definition,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        usesByWord.update(pair.word, (count) => count + 1, ifAbsent: () => 1);
        usesByPair.update(pair.order, (count) => count + 1, ifAbsent: () => 1);
        lastWordRound[pair.word] = rounds.length;
      }
      rounds.add(selected);
    }
    return _separateAmbiguousRounds(rounds, byWord);
  }

  /// 不同单词不能抢同轮另一张卡的含义：例如 big→重要、large→大，
  /// 若 big 也收录了“大”，用户无法从题面知道“大”预先分配给了谁。
  /// 在完整编排后按已收录的含义文本精确检查，冲突的配对分轮展示。
  /// 同拼写的卡片仍可互换；只拆轮次，不增加、删除或改写任何配对。
  static List<List<Map<String, Object?>>> _separateAmbiguousRounds(
    List<List<_Pair>> rounds,
    Map<String, List<_Pair>> byWord,
  ) {
    final definitions = <String, Set<String>>{
      for (final entry in byWord.entries)
        entry.key: entry.value.map((pair) => pair.definition).toSet(),
    };
    final result = <List<Map<String, Object?>>>[];
    for (final round in rounds) {
      final separated = <List<_Pair>>[];
      for (final pair in round) {
        final target = separated
            .where(
              (part) => part.every(
                (other) =>
                    pair.word == other.word ||
                    (!definitions[pair.word]!.contains(other.definition) &&
                        !definitions[other.word]!.contains(pair.definition)),
              ),
            )
            .firstOrNull;
        if (target == null) {
          separated.add(<_Pair>[pair]);
        } else {
          target.add(pair);
        }
      }
      result.addAll(
        separated.map((part) => part.map((pair) => pair.question).toList()),
      );
    }
    return result;
  }

  /// 同时寻找尽可能多组“单词不同、含义也不同”的配对。
  /// 前面的单词可以换一个含义，让出后面单词唯一可用的位置，避免贪心选法误判无解。
  static List<_Pair> _match(
    Map<String, List<_Pair>> edges,
    List<String> words,
    int limit, {
    _Pair? anchor,
  }) {
    final byDefinition = <String, _Pair>{};
    if (anchor != null) {
      byDefinition[anchor.definition] = anchor;
    }
    bool place(String word, Set<String> visited) {
      for (final pair in edges[word].orEmpty) {
        if (pair.definition == anchor?.definition ||
            !visited.add(pair.definition)) {
          continue;
        }
        final previous = byDefinition[pair.definition];
        if (previous == null || place(previous.word, visited)) {
          byDefinition[pair.definition] = pair;
          return true;
        }
      }
      return false;
    }

    for (final word in words) {
      if (byDefinition.length >= limit) break;
      if (word != anchor?.word) place(word, <String>{});
    }
    return byDefinition.values.toList();
  }
}

class _Pair {
  _Pair(this.order, this.question)
    : word = (question['content']! as List<String>).first.trim().toLowerCase(),
      definition = (question['answers']! as List<String>).first.trim();
  final int order;
  final String word;
  final String definition;
  final Map<String, Object?> question;
}

extension on List<_Pair>? {
  List<_Pair> get orEmpty => this ?? const <_Pair>[];
}
