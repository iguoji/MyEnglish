"""把散落的间距字面量收敛到 AppSpace 的 11 级台阶。

用法：python3 tools/converge_space.py [--apply] [--report]

  --report  只列出「不在台阶上」的值和它们的位置，不改任何文件
  --apply   真正写盘；不加就只统计能改多少处

────────────────────────────────────────────────────────────────────────
为什么这次可以用「按构造子解析」而不是逐点位写死
────────────────────────────────────────────────────────────────────────
图标那一轮之所以要把每个点位写死，是因为 `size:` 这个词在 Flutter 里
一词多义（按钮直径、画布尺寸都叫 size）。间距不一样：

  EdgeInsets.all / symmetric / only / fromLTRB  → 括号里每个数都是内外边距
  Wrap / Row / Column 的 spacing / runSpacing   → 一定是「两个孩子之间的缝」
  SizedBox(width: N) 只写单边                    → 绝大多数是「占位的缝」

前两类语义唯一，脚本直接换。第三类有例外（例如骨架屏用 SizedBox 画一根
灰条，那是形状不是间距），所以单独维护一张 SKIP_SIZEDBOX 白名单，
名单里的位置原样保留并在报告里说明原因。

台阶与归并依据 `~/.claude/plans/radiant-honking-brooks.md` 第 3 步：
3→4、5→6、7→6、9→10、13→12、14→16、22→24、26→24、28→24，
其余在台阶上的原地换令牌。

────────────────────────────────────────────────────────────────────────
踩过的坑：必须整篇匹配，不能逐行匹配
────────────────────────────────────────────────────────────────────────
第一版是「一行一行地看」，结果漏掉了所有被 dart format 拆成多行的写法：

    padding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),

逐行看时，`EdgeInsets.symmetric(` 这一行里没有数字，`horizontal: 16,`
这一行里又没有 `EdgeInsets`，两边都不匹配，于是 26 个裸数字安然无恙地留了下来。
现在改成把整个文件当一段文本来匹配（`re.S`），行号由匹配位置反算，
报告里照样能定位。
"""

import collections
import pathlib
import re
import sys

# ---------------------------------------------------------------------------
# 一、台阶表：数值 -> 令牌名
#
# 键既包含「本来就在台阶上」的值，也包含要归并的孤值（3/5/7/9/14/26/28）。
# 0 单独给一个 zero：写 0 的地方是「这里刻意不留缝」，也算一种设计决定，
# 让它显式指向令牌比留个裸 0 更能表达意图。
# ---------------------------------------------------------------------------
LADDER = {
    0: 'AppSpace.zero',
    2: 'AppSpace.s2',
    3: 'AppSpace.s4',
    4: 'AppSpace.s4',
    5: 'AppSpace.s6',
    6: 'AppSpace.s6',
    7: 'AppSpace.s6',
    8: 'AppSpace.s8',
    9: 'AppSpace.s10',
    10: 'AppSpace.s10',
    12: 'AppSpace.s12',
    13: 'AppSpace.s12',
    14: 'AppSpace.s16',
    16: 'AppSpace.s16',
    18: 'AppSpace.s18',
    20: 'AppSpace.s20',
    22: 'AppSpace.s24',
    24: 'AppSpace.s24',
    26: 'AppSpace.s24',
    28: 'AppSpace.s24',
    32: 'AppSpace.s32',
}

# design/ 是台阶的定义处，天然要写字面量。
SKIP_DIRS = ('lib/common/design/',)

# ---------------------------------------------------------------------------
# 二、不参与收敛的 SizedBox 白名单
#
# 结构：(相对路径, 行号) -> 原因。这些 SizedBox 是在「画一个形状」而不是
# 「留一道缝」，换成间距令牌会把造型尺寸和间距混为一谈。
# ---------------------------------------------------------------------------
SKIP_SIZEDBOX = {}

# ---------------------------------------------------------------------------
# 三、正则
#
# 全部带 re.S：dart format 会把长参数拆成多行，逐行匹配一定漏（见文件头「踩过的坑」）。
# ---------------------------------------------------------------------------
# EdgeInsets 的四种写法；只匹配一层括号，够用且不会吃到相邻代码。
RE_EDGE = re.compile(
    r'EdgeInsets\.(all|symmetric|only|fromLTRB)\(([^()]*)\)', re.S
)
# Wrap / Row / Column 的两种间距参数。
RE_SPACING = re.compile(r'\b(spacing|runSpacing):\s*([0-9]+(?:\.[0-9]+)?)')
# 只写单边的 SizedBox（写了两边的是在定形状，不在这里处理）；容许换行与尾随逗号。
RE_SIZEDBOX = re.compile(
    r'SizedBox\(\s*(width|height):\s*([0-9]+(?:\.[0-9]+)?)\s*,?\s*\)', re.S
)
# 括号里的裸数字（EdgeInsets 参数里的值）。
RE_NUMBER = re.compile(r'(?<![\w.])([0-9]+(?:\.[0-9]+)?)(?![\w.])')


def token_for(raw: str):
    """数值字符串 -> 令牌名；不在台阶上返回 None。"""
    value = float(raw)
    if value != int(value):
        return None
    return LADDER.get(int(value))


def sources():
    """列出参与收敛的 Dart 文件。"""
    for path in sorted(pathlib.Path('lib').rglob('*.dart')):
        rel = path.as_posix()
        if any(rel.startswith(prefix) for prefix in SKIP_DIRS):
            continue
        yield rel, path


def convert(rel, text):
    """把整篇里所有可换的间距字面量换成令牌，返回（新文本, 换了几处, 留下的）。"""
    changed = 0
    kept = []

    def line_of(offset):
        """由字符偏移反算行号，报告里才能点得开。"""
        return text[:offset].count('\n') + 1

    def sub_edge(match):
        nonlocal changed
        head, body = match.group(1), match.group(2)
        line_no = line_of(match.start())

        def sub_num(num):
            nonlocal changed
            token = token_for(num.group(1))
            if token is None:
                kept.append(f'{rel}:{line_no} EdgeInsets.{head} {num.group(1)}')
                return num.group(1)
            changed += 1
            return token

        return f'EdgeInsets.{head}({RE_NUMBER.sub(sub_num, body)})'

    def sub_spacing(match):
        nonlocal changed
        name, num = match.group(1), match.group(2)
        token = token_for(num)
        if token is None:
            kept.append(f'{rel}:{line_of(match.start())} {name} {num}')
            return match.group(0)
        changed += 1
        return f'{name}: {token}'

    def sub_sizedbox(match):
        nonlocal changed
        axis, num = match.group(1), match.group(2)
        line_no = line_of(match.start())
        if (rel, line_no) in SKIP_SIZEDBOX:
            return match.group(0)
        token = token_for(num)
        if token is None:
            kept.append(f'{rel}:{line_no} SizedBox.{axis} {num}')
            return match.group(0)
        changed += 1
        return f'SizedBox({axis}: {token})'

    out = RE_EDGE.sub(sub_edge, text)
    out = RE_SPACING.sub(sub_spacing, out)
    out = RE_SIZEDBOX.sub(sub_sizedbox, out)
    return out, changed, kept


def main() -> int:
    apply = '--apply' in sys.argv
    report_only = '--report' in sys.argv

    total_changed = 0
    all_kept = []
    touched = []

    for rel, path in sources():
        text = path.read_text(encoding='utf-8')
        new_text, file_changed, kept = convert(rel, text)
        all_kept += kept
        if file_changed:
            touched.append((rel, file_changed))
            total_changed += file_changed
            if apply and not report_only:
                path.write_text(new_text, encoding='utf-8')

    if not report_only:
        print(f'可收敛 {total_changed} 处，涉及 {len(touched)} 个文件'
              f'{"（已写入）" if apply else "（未写入，加 --apply 落盘）"}')
        for rel, n in sorted(touched, key=lambda x: -x[1]):
            print(f'  {n:>4}  {rel}')

    buckets = collections.Counter(k.rsplit(' ', 1)[-1] for k in all_kept)
    print(f'\n不在台阶上、原样保留 {len(all_kept)} 处，共 {len(buckets)} 种值：')
    for value, count in sorted(buckets.items(), key=lambda x: (-x[1], x[0])):
        print(f'\n  {value}  × {count}')
        for line in all_kept:
            if line.rsplit(' ', 1)[-1] == value:
                print(f'      {line}')

    if SKIP_SIZEDBOX:
        print(f'\n白名单跳过 {len(SKIP_SIZEDBOX)} 处（是形状不是间距）：')
        for (rel, line_no), why in SKIP_SIZEDBOX.items():
            print(f'  {rel}:{line_no}  {why}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
