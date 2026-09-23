import 'dart:math';

/// 把配对分散到各轮：先保证同轮单词和含义都不同，实在凑不齐才复用单词。
/// 每轮都先安排尚未练到的内容，补位只影响排列，不会漏掉任何原始配对。
///
/// 轮次张数的约定：除最后一轮外，每轮都应排满（默认 5 张）；最后一轮剩几张
/// 算几张。编排时就避开歧义（同轮两张卡不能互相认领对方的释义），排完再由
/// [_rebalance] 把偶尔没排满的轮从后面借卡补齐，短轮统一放到最后。
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
    // 每个单词收录的全部释义文本：编排每一轮时就据此避开「同轮两张卡互相
    // 认领对方释义」的歧义，而不是排完再拆——拆出来的零散轮很难重新排满。
    final definitions = <String, Set<String>>{
      for (final entry in byWord.entries)
        entry.key: entry.value.map((pair) => pair.definition).toSet(),
    };
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
      final fresh = _match(newEdges, words, rowCount, definitions);
      var selected = fresh;
      if (fresh.length < rowCount && fresh.length < pending.length) {
        // 先锁定一道新题，再检查所有单词的其他含义，寻找不重复单词的补位。
        // 锁定新题保证每轮都有实际进展，不能为了满五行反复练旧题而不往前走。
        final anchors = <_Pair>{...fresh, ...pending};
        var bestFresh = fresh.length;
        for (final anchor in anchors) {
          final candidate = _match(
            allEdges,
            words,
            rowCount,
            definitions,
            anchor: anchor,
          );
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
          // 补位同样不能带来歧义，否则排完还得拆，等于白补。
          if (usedDefinitions.contains(pair.definition)) continue;
          if (!selected.every(
            (other) => _compatible(pair, other, definitions),
          )) {
            continue;
          }
          usedDefinitions.add(pair.definition);
          selected.add(pair);
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
    return _separateAmbiguousRounds(rounds, definitions, rowCount);
  }

  /// 不同单词不能抢同轮另一张卡的含义：例如 big→重要、large→大，
  /// 若 big 也收录了“大”，用户无法从题面知道“大”预先分配给了谁。
  /// 在完整编排后按已收录的含义文本精确检查，冲突的配对分轮展示。
  /// 同拼写的卡片仍可互换；只拆轮次，不增加、删除或改写任何配对。
  ///
  /// 编排阶段（[_match] 与补位）已经按同一规则避开歧义，这里只是兜底复查：
  /// 正常情况下每轮原样通过。万一拆出短轮（典型例子：同一轮里同时出现
  /// touch→触摸 与 feel→触觉，而这两个词各自都还收录了对方的释义），
  /// 交给 [_rebalance] 从后面借卡补齐，用户不会碰到“这一大题只有几张”的怪题。
  static List<List<Map<String, Object?>>> _separateAmbiguousRounds(
    List<List<_Pair>> rounds,
    Map<String, Set<String>> definitions,
    int rowCount,
  ) {
    final separated = <List<_Pair>>[];
    for (final round in rounds) {
      final parts = <List<_Pair>>[];
      for (final pair in round) {
        final target = parts
            .where(
              (part) =>
                  part.every((other) => _compatible(pair, other, definitions)),
            )
            .firstOrNull;
        if (target == null) {
          parts.add(<_Pair>[pair]);
        } else {
          target.add(pair);
        }
      }
      separated.addAll(parts);
    }
    return _rebalance(
      separated,
      definitions,
      rowCount,
    ).map((part) => part.map((pair) => pair.question).toList()).toList();
  }

  /// 两张卡能否放进同一轮：同拼写可以并存，否则双方的含义集合都不能包含
  /// 对方这张卡上的释义——否则用户看到释义卡时无法判断它属于哪个单词。
  static bool _compatible(
    _Pair a,
    _Pair b,
    Map<String, Set<String>> definitions,
  ) =>
      a.word == b.word ||
      (!definitions[a.word]!.contains(b.definition) &&
          !definitions[b.word]!.contains(a.definition));

  /// 把没排满的轮重新排布，让「除最后一轮外每轮一样多」尽量成立。
  ///
  /// 编排阶段已经避开歧义，但补位补不齐、或拆分兜底拆过之后，中间仍可能留下
  /// 只有三四张（甚至一张）的轮。这里从前往后逐轮检查，凡是没排满的轮：
  /// 一、先从后面的轮直接借兼容的配对（越靠后越先借，空缺就被一步步挤到末尾）；
  /// 二、直接借不到，就找一个满轮换：满轮里挑一张能进缺卡轮的，后面的配对再
  ///     填进满轮让出的位置。
  /// 每搬一次都有配对往前挪，所以循环一定会结束。任何一步都只在不产生歧义
  /// 时才动手；实在搬不动就原样保留——宁可留着短轮，也不为凑满而制造歧义。
  static List<List<_Pair>> _rebalance(
    List<List<_Pair>> groups,
    Map<String, Set<String>> definitions,
    int rowCount,
  ) {
    bool fits(_Pair pair, Iterable<_Pair> group) =>
        group.every((other) => _compatible(pair, other, definitions));

    var current = <List<_Pair>>[
      for (final group in groups)
        if (group.isNotEmpty) List<_Pair>.of(group),
    ];
    var progress = true;
    while (progress) {
      progress = false;
      // 最后一轮本来就允许不满，所以只检查它前面的轮。
      for (var i = 0; i < current.length - 1 && !progress; i++) {
        final target = current[i];
        if (target.length >= rowCount) continue;
        // 一、从后面的轮直接借。
        for (var j = current.length - 1; j > i && !progress; j--) {
          for (var k = 0; k < current[j].length; k++) {
            final pair = current[j][k];
            if (!fits(pair, target)) continue;
            target.add(pair);
            current[j].removeAt(k);
            progress = true;
            break;
          }
        }
        if (progress) break;
        // 二、借不到就找满轮换一张。
        for (var j = current.length - 1; j > i && !progress; j--) {
          for (var k = 0; k < current[j].length && !progress; k++) {
            final pair = current[j][k];
            for (var donor = 0; donor < current.length && !progress; donor++) {
              if (donor == i || donor == j) continue;
              if (current[donor].length < rowCount) continue;
              for (var pick = 0; pick < current[donor].length; pick++) {
                final lent = current[donor][pick];
                if (!fits(lent, target)) continue;
                final rest = <_Pair>[
                  for (var x = 0; x < current[donor].length; x++)
                    if (x != pick) current[donor][x],
                ];
                if (!fits(pair, rest)) continue;
                target.add(lent);
                current[donor] = <_Pair>[...rest, pair];
                current[j].removeAt(k);
                progress = true;
                break;
              }
            }
          }
        }
      }
      // 被借空的轮直接收掉；每成功一次总张数往前挪，循环必然收敛。
      current = <List<_Pair>>[
        for (final group in current)
          if (group.isNotEmpty) group,
      ];
    }
    // 搬动会打乱轮内顺序，统一按原始配对顺序重排：同一份试卷每次生成结果一致，
    // 也保持与拆分前相同的「按单词先后排列」观感。
    for (final group in current) {
      group.sort((a, b) => a.order.compareTo(b.order));
    }
    // 配对总数不一定能被每轮数量整除，回填完仍会剩没排满的轮（极端情况下也
    // 可能有搬不动的短轮）。把它们统一挪到最后、越短越靠后：用户看到的就是
    // 「前面每轮一样多，只有最后一题少几张」，而不是中间突然冒出一个短题。
    final full = <List<_Pair>>[];
    final partial = <List<_Pair>>[];
    for (final group in current) {
      (group.length == rowCount ? full : partial).add(group);
    }
    partial.sort((a, b) => b.length.compareTo(a.length));
    return <List<_Pair>>[...full, ...partial];
  }

  /// 同时寻找尽可能多组“单词不同、含义也不同、彼此没有歧义”的配对。
  /// 前面的单词可以换一个含义，让出后面单词唯一可用的位置，避免贪心选法误判无解。
  /// 每放一张卡都先核对它与已选卡片是否兼容（见 [_compatible]），
  /// 被顶替的那张不算在内，因为它马上会换别的位置。
  static List<_Pair> _match(
    Map<String, List<_Pair>> edges,
    List<String> words,
    int limit,
    Map<String, Set<String>> definitions, {
    _Pair? anchor,
  }) {
    final byDefinition = <String, _Pair>{};
    if (anchor != null) {
      byDefinition[anchor.definition] = anchor;
    }
    bool fits(_Pair pair, _Pair? displaced) => byDefinition.values.every(
      (other) =>
          identical(other, displaced) || _compatible(pair, other, definitions),
    );
    bool place(String word, Set<String> visited) {
      for (final pair in edges[word].orEmpty) {
        if (pair.definition == anchor?.definition ||
            !visited.add(pair.definition)) {
          continue;
        }
        final previous = byDefinition[pair.definition];
        if (!fits(pair, previous)) continue;
        // 先把这张卡放进去再给被顶替的词找位置，它换到的新位置也要与这张卡兼容。
        byDefinition[pair.definition] = pair;
        if (previous == null || place(previous.word, visited)) return true;
        byDefinition[pair.definition] = previous;
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
