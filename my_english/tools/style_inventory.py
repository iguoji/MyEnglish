"""盘点 lib/ 里还没进设计令牌总表的样式字面量。

用法：python3 tools/style_inventory.py [类别]
类别可选 font / weight / space / motion / color / shape，缺省全列。

只做统计与定位，不改任何文件。收敛脚本按它的输出决定要改哪些点位。
"""

import collections
import pathlib
import re
import sys

# design/ 目录本身就是台阶的定义处，天然要写字面量，不参与盘点。
SKIP = ('lib/common/design/',)

PATTERNS = {
    # 字号：`fontSize: 13.5`
    'font': re.compile(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)'),
    # 字重：`FontWeight.w600` / `FontWeight.bold`
    'weight': re.compile(r'FontWeight\.(w[0-9]00|bold|normal)'),
    # 间距：EdgeInsets 家族、SizedBox 单边、Wrap 的两种间距
    'space': re.compile(
        r'(?:EdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^;]*?\)'
        r'|SizedBox\((?:width|height):\s*[0-9]+(?:\.[0-9]+)?\)'
        r'|(?:^|\s)(?:spacing|runSpacing):\s*[0-9]+(?:\.[0-9]+)?)'
    ),
    # 时长：常量名以 Ms 结尾，或直接写 Duration
    'motion': re.compile(
        r'(?:\w+Ms\s*=\s*[0-9]+'
        r'|Duration\((?:milliseconds|seconds):\s*[0-9]+\))'
    ),
    # 颜色：写死的 ARGB
    'color': re.compile(r'Color\(0x[0-9A-Fa-f]{8}\)'),
    # 造型尺寸：宽高直径这类「不是间距」的固定尺寸常量
    'shape': re.compile(
        r'static const double (\w*(?:Size|Width|Height|Diameter))\s*=\s*'
        r'([0-9]+(?:\.[0-9]+)?);'
    ),
}


def sources():
    """按路径排序列出参与盘点的 Dart 文件。"""
    for path in sorted(pathlib.Path('lib').rglob('*.dart')):
        rel = path.as_posix()
        if any(rel.startswith(prefix) for prefix in SKIP):
            continue
        yield rel, path.read_text(encoding='utf-8')


def main() -> None:
    wanted = sys.argv[1:] or list(PATTERNS)
    for kind in wanted:
        pattern = PATTERNS[kind]
        hits = collections.defaultdict(list)
        for rel, text in sources():
            for line_no, raw in enumerate(text.splitlines(), start=1):
                for match in pattern.finditer(raw):
                    hits[match.group(0).strip()].append(f'{rel}:{line_no}')
        total = sum(len(v) for v in hits.values())
        print(f'\n########## {kind}：{len(hits)} 种写法 / {total} 处 ##########')
        for token in sorted(hits, key=lambda k: (-len(hits[k]), k)):
            where = hits[token]
            print(f'\n  {token}   × {len(where)}')
            for line in where:
                print(f'      {line}')


main()
