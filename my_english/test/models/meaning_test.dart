import 'package:flutter_test/flutter_test.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';

///
/// 按「展示词性 + 释义文本」快速造一批释义。
///
/// 排序值按传入顺序倒着发，模拟数据库里「数字越大越靠前」的存法。
List<Meaning> _meanings(List<(String pos, String definition)> rows) {
  var id = 0;
  return <Meaning>[
    for (final row in rows)
      for (final variant in splitPos(row.$1))
        Meaning(
          id: ++id,
          pos: variant.pos,
          subPos: variant.subPos,
          definition: row.$2,
          sort: rows.length - rows.indexOf(row),
        ),
  ];
}

///
/// 把分组结果压成 `词性: 含义;含义` 的字符串，方便一眼比对。
Map<String, String> _flatten(Word word) => <String, String>{
  for (final group in word.meaningGroups) group.pos: group.joinedDefinitions('；'),
};

void main() {
  group('单词含义按词性分组', () {
    test('同一词性即使在库里不连续也并成一组', () {
      // stream 的真实数据顺序就是 n. → vi. → n.，最后那条 n. 要并回前面那组。
      final word = Word(
        spelling: 'stream',
        meanings: _meanings(const <(String, String)>[
          ('n.', '小溪'),
          ('vi.', '流动'),
          ('n.', '流媒体播放'),
        ]),
      );
      expect(_flatten(word), <String, String>{
        'n.': '小溪；流媒体播放',
        'vi.': '流动',
      });
    });

    test('同一词性下重复的中文只留一条', () {
      // rub 的 vt. 里「擦 / 搓」各录了两遍，显示两遍毫无意义。
      final word = Word(
        spelling: 'rub',
        meanings: _meanings(const <(String, String)>[
          ('vt.', '擦'),
          ('vt.', '搓'),
          ('vt.', '擦'),
          ('vt.', '搓'),
        ]),
      );
      expect(_flatten(word), <String, String>{'vt.': '擦；搓'});
    });
  });

  group('动词合并', () {
    test('例一：vi. 与 vt. 的交集并成 vi. vt.，两边各自留下独有的', () {
      final word = Word(
        spelling: 'demo',
        meanings: _meanings(const <(String, String)>[
          ('vi.', '你好'),
          ('vi.', '我好'),
          ('vi.', '他好'),
          ('vt.', '你好'),
          ('vt.', '她好'),
          ('vt.', '我好'),
          ('vt.', '它好'),
        ]),
      );
      expect(_flatten(word), <String, String>{
        'vi.': '他好',
        'vt.': '她好；它好',
        'vi. vt.': '你好；我好',
      });
    });

    test('例二：两边完全相同时，vi. 与 vt. 双双消失', () {
      final word = Word(
        spelling: 'demo',
        meanings: _meanings(const <(String, String)>[
          ('vt.', '谁好'),
          ('vi.', '谁好'),
        ]),
      );
      expect(_flatten(word), <String, String>{'vi. vt.': '谁好'});
    });

    test('例三：被掏空的那一边整组消失，另一边保留独有的', () {
      final word = Word(
        spelling: 'demo',
        meanings: _meanings(const <(String, String)>[
          ('vi.', '真好'),
          ('vi.', '呵呵'),
          ('vt.', '真好'),
          ('vt.', '呵呵'),
          ('vt.', '你看'),
          ('vt.', '你敲'),
        ]),
      );
      expect(_flatten(word), <String, String>{
        'vt.': '你看；你敲',
        'vi. vt.': '真好；呵呵',
      });
    });

    test('光杆 v. 里与更精确动词重复的含义被去掉', () {
      // kick 的真实数据：v. 和 vi./vt. 都有「踢」，更精确的那个赢。
      final word = Word(
        spelling: 'kick',
        meanings: _meanings(const <(String, String)>[
          ('v.', '踢'),
          ('v.', '踹'),
          ('vi.', '踢'),
          ('vt.', '踢'),
        ]),
      );
      expect(_flatten(word), <String, String>{
        'v.': '踹',
        'vi. vt.': '踢',
      });
    });

    test('vlink. 不与 vi./vt. 合并，自成一组', () {
      final word = Word(
        spelling: 'demo',
        meanings: _meanings(const <(String, String)>[
          ('vlink.', '看起来'),
          ('vi.', '出现'),
          ('vt.', '出现'),
        ]),
      );
      expect(_flatten(word), <String, String>{
        'vlink.': '看起来',
        'vi. vt.': '出现',
      });
    });

    test('合并组排在 vi./vt. 里靠后的那个之后', () {
      // catch 的真实顺序是 vt. → vi.，所以 vi. vt. 落在 vi. 后面、n. 前面。
      final word = Word(
        spelling: 'catch',
        meanings: _meanings(const <(String, String)>[
          ('vt.', '接住'),
          ('vt.', '扣件'),
          ('vi.', '被绊住'),
          ('vi.', '扣件'),
          ('n.', '陷阱'),
        ]),
      );
      expect(word.meanings.keys.toList(), <String>[
        'vt.',
        'vi.',
        'vi. vt.',
        'n.',
      ]);
    });
  });

  group('模型接口', () {
    final word = Word(
      spelling: 'hello',
      meanings: _meanings(const <(String, String)>[
        ('*', '还没整理的含义'),
        ('n.', '你好'),
        ('n.', '你好1'),
        ('vt.', '你好5'),
      ]),
    );

    test('getPosMeanings 按展示词性取，取不到返回空列表', () {
      expect(
        word.getPosMeanings('n.').map((m) => m.definition).toList(),
        <String>['你好', '你好1'],
      );
      expect(word.getPosMeanings('adj.'), isEmpty);
    });

    test('未选词性显示成星号', () {
      expect(word.getPosMeanings('*').single.definition, '还没整理的含义');
    });

    test('allMeanings 摊平后仍是分组顺序', () {
      expect(word.allMeanings.map((m) => m.definition).toList(), <String>[
        '还没整理的含义',
        '你好',
        '你好1',
        '你好5',
      ]);
      expect(word.meaningCount, 4);
    });

    test('toMap 摊平回数据库形态，toArray 保留分组', () {
      // toMap 交给 MethodChannel，形状必须和数据库一样是一维的。
      final rows = word.toMap()['meanings']! as List<Object?>;
      expect(rows, hasLength(4));
      // toArray 给人看，按词性分好组。
      final grouped = word.toArray()['meanings']! as Map<String, Object?>;
      expect(grouped.keys, <String>['*', 'n.', 'vt.']);
      expect((grouped['n.']! as List<Object?>), hasLength(2));
    });
  });

  group('展示词性拆回数据库形态', () {
    test('vi. vt. 拆成两条真实记录', () {
      expect(splitPos('vi. vt.'), <({String pos, String? subPos})>[
        (pos: 'v.', subPos: 'vi.'),
        (pos: 'v.', subPos: 'vt.'),
      ]);
    });

    test('及物/不及物/系动词都归到主词性 v. 之下', () {
      expect(splitPos('vt.').single, (pos: 'v.', subPos: 'vt.'));
      expect(splitPos('vi.').single, (pos: 'v.', subPos: 'vi.'));
      expect(splitPos('vlink.').single, (pos: 'v.', subPos: 'vlink.'));
    });

    test('星号与空串都表示未选词性', () {
      expect(splitPos('*').single, (pos: '', subPos: null));
      expect(splitPos('  ').single, (pos: '', subPos: null));
    });

    test('其余词性原样作为主词性', () {
      expect(splitPos('n.').single, (pos: 'n.', subPos: null));
      expect(splitPos('adj.').single, (pos: 'adj.', subPos: null));
    });
  });
}
