// flutter_test 提供 test、expect 与排序结果匹配器。
import 'package:flutter_test/flutter_test.dart';
// Meaning 用来构造含义数量和字符数不同的测试单词。
import 'package:my_english/models/meaning.dart';
// Word 是每日选词器接收的业务模型。
import 'package:my_english/models/word.dart';
// DailyReviewSelector 是本文件直接验证的固定排序服务。
import 'package:my_english/pages/home/services/daily_review_selector.dart';

///
/// 注册每日公共复习词单的排序规则测试。
///
/// @return void
///
void main() {
  // 未复习是最高优先级，即使已复习单词的含义更简单也不能越过它。
  test('puts every unreviewed word before reviewed words', () {
    // 已复习单词只有一个短释义，故意制造其他字段更有优势的情况。
    final reviewed = Word(
      id: 1,
      spelling: 'reviewed',
      reviewedAt: DateTime(2025, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['已']),
      ],
    );
    // 未复习单词有两个释义，但 reviewedAt 为空，所以仍必须排在最前。
    final unreviewed = Word(
      id: 2,
      spelling: 'unreviewed',
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['未', '复习']),
      ],
    );

    // 反向输入，证明结果来自业务比较器而不是原列表顺序。
    final selected = DailyReviewSelector.select(<Word>[
      reviewed,
      unreviewed,
    ], limit: 2);

    // 未复习单词必须位于已复习单词之前。
    expect(selected.map((word) => word.id), <int?>[2, 1]);
  });

  // 用户报告的真实冲突：较老的多释义词不能压过较新的单释义词。
  test('compares meaning count before the fallback date', () {
    // 三释义单词的更新时间更早；旧实现会因为先比较日期而错误地把它排在前面。
    final olderManyMeanings = Word(
      id: 1,
      spelling: 'older',
      updatedAt: DateTime(2020, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['甲', '乙', '丙']),
      ],
    );
    // 单释义单词虽然更新时间更晚，但含义更简单，按需求必须优先。
    final newerSingleMeaning = Word(
      id: 2,
      spelling: 'newer',
      updatedAt: DateTime(2026, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['甲']),
      ],
    );

    // 选择完整列表，便于直接核对两个单词的先后关系。
    final selected = DailyReviewSelector.select(<Word>[
      olderManyMeanings,
      newerSingleMeaning,
    ], limit: 2);

    // 单释义单词必须排在三释义单词之前，日期只能作为更后的条件。
    expect(selected.map((word) => word.id), <int?>[2, 1]);
  });

  // 含义数量相同后，先比较字符数；仍相同后才轮到难度和时间。
  test('uses character count then difficulty then date', () {
    // 长释义即使难度很高，也必须排在同数量的短释义之后。
    final longMeaning = Word(
      id: 1,
      spelling: 'long',
      difficulty: 9,
      updatedAt: DateTime(2020, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['完成某件事情的能力']),
      ],
    );
    // 两个短释义单词拥有相同含义数量和字符数，接下来应由难度区分。
    final easyShort = Word(
      id: 2,
      spelling: 'easy',
      difficulty: 1,
      updatedAt: DateTime(2019, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['力']),
      ],
    );
    // 高难度短释义即使日期更新，也应先于低难度短释义。
    final hardShortNewer = Word(
      id: 3,
      spelling: 'hard-newer',
      difficulty: 5,
      updatedAt: DateTime(2022, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['能']),
      ],
    );
    // 与上一词所有前置字段相同，只有时间更早，因此它应排在上一词之前。
    final hardShortOlder = Word(
      id: 4,
      spelling: 'hard-older',
      difficulty: 5,
      updatedAt: DateTime(2021, 1, 1),
      meanings: const <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['会']),
      ],
    );

    // 故意打乱输入顺序，完整验证四层优先级。
    final selected = DailyReviewSelector.select(<Word>[
      longMeaning,
      easyShort,
      hardShortNewer,
      hardShortOlder,
    ], limit: 4);

    // 短释义先；短释义内部难度高先；难度相同则日期早先；长释义最后。
    expect(selected.map((word) => word.id), <int?>[4, 3, 2, 1]);
  });
}
