"""把 7 张页面尺寸表里的字面量改成引用 design/ 总表的台阶。

用法：python3 tools/retoken.py [--apply]
不加 --apply 只打印报告，不改文件。

判定规则：先按常量名判角色（字号 / 圆角 / 图标 / 时长 / 间距），
再按数值查该角色的台阶表；查不到的原样保留，报告里列出来交给收敛那一步。
"""

import re
import sys
from pathlib import Path

FILES = [
    'lib/widgets/letter_slot.dart',
    'lib/widgets/pos_meaning_panel.dart',
    'lib/pages/listening/widgets/listening_layout.dart',
    'lib/pages/listening_meaning/widgets/listening_meaning_layout.dart',
    'lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
    'lib/pages/spelling_reinforcement/widgets/spelling_layout.dart',
    'lib/pages/meaning_match/widgets/meaning_match_layout.dart',
]

FONT = {10: 'AppFont.tiny', 12: 'AppFont.small', 14: 'AppFont.base',
        16: 'AppFont.large', 18: 'AppFont.title', 24: 'AppFont.head',
        28: 'AppFont.hero', 40: 'AppFont.giant'}
SPACE = {2: 'AppSpace.s2', 4: 'AppSpace.s4', 6: 'AppSpace.s6', 8: 'AppSpace.s8',
         10: 'AppSpace.s10', 12: 'AppSpace.s12', 16: 'AppSpace.s16',
         18: 'AppSpace.s18', 20: 'AppSpace.s20', 24: 'AppSpace.s24',
         32: 'AppSpace.s32'}
RADIUS = {2: 'AppRadius.r2', 6: 'AppRadius.r6', 8: 'AppRadius.r8',
          10: 'AppRadius.r10', 12: 'AppRadius.r12', 14: 'AppRadius.r14',
          20: 'AppRadius.r20', 999: 'AppRadius.pill'}
ICON = {12: 'AppIcon.i12', 14: 'AppIcon.i14', 16: 'AppIcon.i16',
        20: 'AppIcon.i20', 24: 'AppIcon.i24', 32: 'AppIcon.i32'}
MOTION = {100: 'AppDuration.ms100', 160: 'AppDuration.ms160',
          250: 'AppDuration.ms250', 350: 'AppDuration.ms350',
          800: 'AppDuration.ms800', 1200: 'AppDuration.ms1200'}
STROKE = {1: 'AppStroke.thin', 1.5: 'AppStroke.bold', 2.5: 'AppStroke.mark'}


def role(name: str) -> str:
    """按常量名判断它是哪一类设计值。"""
    if re.search(r'(TextSize|FontSize|LabelSize|TitleSize|SubtitleSize|ValueSize|UnitSize|TimeSize|ButtonTextSize|ChipTextSize)$', name):
        return 'font'
    if re.search(r'Radius$', name):
        return 'radius'
    if re.search(r'IconSize$', name):
        return 'icon'
    if re.search(r'(Ms|DurationMs|DelayMs)$', name):
        return 'motion'
    if re.search(r'(Width|Height)$', name) and re.search(r'(line|Line|border|Border|divider|Divider|stroke)', name):
        return 'stroke'
    if re.search(r'(Inset|Gap|Top|Bottom|Left|Right|Padding|PaddingHorizontal|PaddingVertical|SectionGap|StatGap|RunGap)$', name):
        return 'space'
    return 'other'


TABLES = {'font': FONT, 'space': SPACE, 'radius': RADIUS,
          'icon': ICON, 'motion': MOTION, 'stroke': STROKE}

PATTERN = re.compile(r'static const (double|int) (\w+) = ([0-9]+(?:\.[0-9]+)?);')


def main() -> None:
    apply = '--apply' in sys.argv
    changed_total = kept_total = 0
    for path in FILES:
        source = Path(path).read_text(encoding='utf-8')
        changed, kept = [], []

        def repl(match: re.Match) -> str:
            nonlocal changed, kept
            kind, name, raw = match.group(1), match.group(2), match.group(3)
            value = float(raw) if '.' in raw else int(raw)
            table = TABLES.get(role(name))
            token = table.get(value) if table else None
            if token is None:
                kept.append(f'{name} = {raw} [{role(name)}]')
                return match.group(0)
            changed.append(f'{name} = {raw} → {token}')
            return f'static const {kind} {name} = {token};'

        result = PATTERN.sub(repl, source)
        if apply and result != source:
            Path(path).write_text(result, encoding='utf-8')
        print(f'\n=== {path} ===')
        print(f'  替换 {len(changed)} 条：')
        for line in changed:
            print(f'    {line}')
        print(f'  保留 {len(kept)} 条（等收敛那一步）：')
        for line in kept:
            print(f'    {line}')
        changed_total += len(changed)
        kept_total += len(kept)
    print(f'\n合计：替换 {changed_total} 条，保留 {kept_total} 条'
          f'{"（已写入）" if apply else "（未写入，加 --apply 才落盘）"}')


main()
