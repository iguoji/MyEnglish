"""把散落的字号与字重字面量收敛到 AppFont / AppWeight 的台阶。

用法：python3 tools/converge_font.py [--apply]

────────────────────────────────────────────────────────────────────────
为什么字号可以「按关键字全局替换」
────────────────────────────────────────────────────────────────────────
`fontSize:` 在 Flutter 里语义唯一——它后面那个数只可能是字号，不像 `size:`
那样一词多义（按钮直径、画布宽高都叫 size）。所以这里不必像图标那一轮
逐点位写死，直接按关键字扫全仓即可，风险已经被关键字本身挡掉了。

字重同理：`FontWeight.w600` 这种写法不可能是别的东西。

────────────────────────────────────────────────────────────────────────
w500 为什么不是一刀切并进 w600
────────────────────────────────────────────────────────────────────────
`AppWeight` 只有三档（w400 正文 / w600 半粗 / w700 粗），w500 得选一边。
绝大多数 w500 是「标签、按钮、键帽」这类需要比正文重一点的文字，归 w600。

但有两类必须归 w400，否则会把信息层级抹平，它们列在 W500_TO_TEXT 里：

  1. `isXxx ? w600 : w500` 这种三元——两边都变成 w600 就分不出
     「选中 / 未选中」「本周 / 上周」了。同仓已有 `w600 : w400` 的先例
     （首页分组筛选栏），照它统一。
  2. 四个模块顶栏右上角的计时——词义连连那一处早就写了注释说
     「不加粗：倒计时是次要信息，弱于中间的主进度数字」，另外三个模块
     写成 w500 属于历史不一致，这次一起归位。
"""

import collections
import pathlib
import re
import sys

# design/ 是台阶的定义处，天然要写字面量。
SKIP_DIRS = ('lib/common/design/',)

# ---------------------------------------------------------------------------
# 一、字号台阶：数值 -> 令牌名（依据计划「刻度」一节的并入列表）
# ---------------------------------------------------------------------------
FONT = {
    '10': 'AppFont.tiny',
    '11': 'AppFont.small', '11.5': 'AppFont.small',
    '12': 'AppFont.small', '12.5': 'AppFont.small',
    '13': 'AppFont.base', '13.5': 'AppFont.base',
    '14': 'AppFont.base', '14.5': 'AppFont.base',
    '15': 'AppFont.large', '15.5': 'AppFont.large', '16': 'AppFont.large',
    '17': 'AppFont.title', '18': 'AppFont.title',
    '20': 'AppFont.head', '22': 'AppFont.head', '24': 'AppFont.head',
    '28': 'AppFont.hero', '30': 'AppFont.hero',
    '38': 'AppFont.giant', '40': 'AppFont.giant',
}

# ---------------------------------------------------------------------------
# 二、字重台阶
# ---------------------------------------------------------------------------
WEIGHT = {
    'w400': 'AppWeight.text',
    'normal': 'AppWeight.text',
    'w500': 'AppWeight.mark',   # 默认归半粗，例外见下表
    'w600': 'AppWeight.mark',
    'w700': 'AppWeight.bold',
    'bold': 'AppWeight.bold',
}

# 必须归 w400 的 w500 点位：(相对路径, 行号) -> 原因。
W500_TO_TEXT = {
    ('lib/pages/home/widgets/dashboard/review_trend_chart.dart', 333):
        '「本周 / 上周」切换：选中 w600、未选中若也变 w600 就分不出选了哪个。',
    ('lib/pages/home/widgets/word_sort_bar.dart', 226):
        '排序按钮的选中态靠字重区分，未选中必须比选中轻。',
    ('lib/pages/meaning_match/meaning_match_page.dart', 1957):
        '棋盘左右两列的标题，右列刻意比左列轻一档。',
    ('lib/pages/listening_meaning/listening_meaning_page.dart', 1295):
        '顶栏计时：与词义连连统一，倒计时是次要信息，不与中间主进度争视线。',
    ('lib/pages/meaning_word_choice/meaning_word_choice_page.dart', 613):
        '同上，顶栏计时归正文字重。',
    ('lib/pages/spelling_reinforcement/spelling_reinforcement_page.dart', 1006):
        '同上，顶栏计时归正文字重。',
}

# ---------------------------------------------------------------------------
# 三、页面尺寸表里仍写着字面量的字号常量：整行替换
# ---------------------------------------------------------------------------
LAYOUT_CONSTANTS = [
    ('lib/widgets/pos_meaning_panel.dart',
     'static const double headingTextSize = 11;',
     'static const double headingTextSize = AppFont.small;'),
    ('lib/widgets/pos_meaning_panel.dart',
     'static const double badgeTextSize = 11;',
     'static const double badgeTextSize = AppFont.small;'),
    ('lib/widgets/pos_meaning_panel.dart',
     'static const double textSize = 14.5;',
     'static const double textSize = AppFont.base;'),
    ('lib/pages/listening_meaning/widgets/listening_meaning_layout.dart',
     'static const double headerTimerTextSize = 15;',
     'static const double headerTimerTextSize = AppFont.large;'),
    ('lib/pages/listening_meaning/widgets/listening_meaning_layout.dart',
     'static const double wordLetterFontSize = 30;',
     'static const double wordLetterFontSize = AppFont.hero;'),
    ('lib/pages/spelling_reinforcement/widgets/spelling_layout.dart',
     'static const double headerTimerTextSize = 15;',
     'static const double headerTimerTextSize = AppFont.large;'),
    ('lib/pages/meaning_match/widgets/meaning_match_layout.dart',
     'static const double countdownTextSize = 15;',
     'static const double countdownTextSize = AppFont.large;'),
    ('lib/pages/meaning_match/widgets/meaning_match_layout.dart',
     'static const double cardLabelSize = 13;',
     'static const double cardLabelSize = AppFont.base;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double headerTimerTextSize = 15;',
     'static const double headerTimerTextSize = AppFont.large;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double posLineTextSize = 13;',
     'static const double posLineTextSize = AppFont.base;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double hintTextSize = 11.5;',
     'static const double hintTextSize = AppFont.small;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double candidateTextSize = 15;',
     'static const double candidateTextSize = AppFont.large;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double summaryTitleSize = 20;',
     'static const double summaryTitleSize = AppFont.head;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double summaryStatLabelSize = 13;',
     'static const double summaryStatLabelSize = AppFont.small;'),
    ('lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
     'static const double weakChipTextSize = 13;',
     'static const double weakChipTextSize = AppFont.small;'),
]

RE_FONT = re.compile(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)')
RE_WEIGHT = re.compile(r'FontWeight\.(w[0-9]00|bold|normal)')


def sources():
    """列出参与收敛的 Dart 文件。"""
    for path in sorted(pathlib.Path('lib').rglob('*.dart')):
        rel = path.as_posix()
        if any(rel.startswith(prefix) for prefix in SKIP_DIRS):
            continue
        yield rel, path


def check_exceptions() -> list:
    """确认 W500_TO_TEXT 里记的行号确实还指着一个 w500。

    行号是上一轮人工看代码定下来的，中间又跑过间距收敛。虽然那一轮只换值
    不增删行，行号理应没动，但「理应」不能当依据：万一错位，例外会静悄悄
    失效，选中态和未选中态一起变粗，界面上看不出是哪一步弄坏的。
    所以这里先逐条核对，对不上就直接停下，不猜。
    """
    bad = []
    for (rel, line_no), why in W500_TO_TEXT.items():
        lines = pathlib.Path(rel).read_text(encoding='utf-8').splitlines()
        if line_no > len(lines) or 'FontWeight.w500' not in lines[line_no - 1]:
            bad.append(f'{rel}:{line_no} 这一行没有 FontWeight.w500（{why}）')
    return bad


def main() -> int:
    apply = '--apply' in sys.argv

    broken = check_exceptions()
    if broken:
        print('⚠️  w500 例外点位对不上，已停止（未改任何文件）：')
        for line in broken:
            print(f'  {line}')
        return 1

    font_hits = collections.Counter()
    weight_hits = collections.Counter()
    kept = []

    for rel, path in sources():
        lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
        dirty = False

        for index, raw in enumerate(lines):
            line_no = index + 1

            def sub_font(match):
                nonlocal dirty
                value = match.group(1)
                token = FONT.get(value)
                if token is None:
                    kept.append(f'{rel}:{line_no} fontSize {value}')
                    return match.group(0)
                font_hits[f'{value} → {token}'] += 1
                dirty = True
                return f'fontSize: {token}'

            def sub_weight(match):
                nonlocal dirty
                name = match.group(1)
                token = WEIGHT[name]
                # w500 的两类例外：归正文字重而不是半粗。
                if name == 'w500' and (rel, line_no) in W500_TO_TEXT:
                    token = 'AppWeight.text'
                weight_hits[f'{name} → {token}'] += 1
                dirty = True
                return token

            new = RE_WEIGHT.sub(sub_weight, RE_FONT.sub(sub_font, raw))
            if new != raw:
                lines[index] = new

        if dirty and apply:
            path.write_text(''.join(lines), encoding='utf-8')

    # 页面尺寸表里的字号常量：整行替换，找不到就报错不猜。
    layout_ok, layout_bad = 0, []
    for rel, old, new in LAYOUT_CONSTANTS:
        path = pathlib.Path(rel)
        text = path.read_text(encoding='utf-8')
        if old not in text:
            layout_bad.append(f'{rel}  找不到 `{old}`')
            continue
        if apply:
            path.write_text(text.replace(old, new, 1), encoding='utf-8')
        layout_ok += 1

    tail = '（已写入）' if apply else '（未写入，加 --apply 落盘）'
    print(f'字号内联 {sum(font_hits.values())} 处{tail}')
    for key, count in sorted(font_hits.items(), key=lambda x: -x[1]):
        print(f'  {key:34} × {count}')
    print(f'\n字重内联 {sum(weight_hits.values())} 处')
    for key, count in sorted(weight_hits.items(), key=lambda x: -x[1]):
        print(f'  {key:34} × {count}')
    print(f'\n尺寸表字号常量 {layout_ok} 条')
    for bad in layout_bad:
        print(f'  ⚠️  {bad}')

    print(f'\nw500 归正文字重的例外 {len(W500_TO_TEXT)} 处：')
    for (rel, line_no), why in W500_TO_TEXT.items():
        print(f'  {rel}:{line_no}  {why}')

    if kept:
        print(f'\n⚠️  不在台阶上、原样保留 {len(kept)} 处：')
        for line in kept:
            print(f'  {line}')
    return 1 if layout_bad else 0


if __name__ == '__main__':
    raise SystemExit(main())
