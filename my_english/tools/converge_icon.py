"""把散落的图标尺寸字面量收敛到 AppIcon 的 6 级台阶。

用法：python3 tools/converge_icon.py [--dry]

为什么是「逐点位」而不是「全局正则替换」：
`size:` 这个词在 Flutter 里到处都是——按钮直径、画布尺寸、字号注释里都有。
上一轮圆角收敛就踩过一次（`Radius.circular(5)` 其实是 SVG 弧半径）。
所以这里把每一处要改的 (文件, 行号, 旧值, 新台阶) 全部写死，
脚本改之前先自检「这一行真的含这个旧值、而且附近真的出现了 Icon」，
对不上就报错退出，绝不猜。

台阶归并依据 `~/.claude/plans/radiant-honking-brooks.md` 第 3 步：
13→14、15/17/18→16、19/21→20、34→32，14/16/20/24/32 原地换成令牌。
"""

import pathlib
import re
import sys

# ---------------------------------------------------------------------------
# 一、内联 `size:` 点位表
#
# 结构：新台阶 -> [(相对路径, 行号, 旧值字符串), ...]
# 行号取自收敛开始前的文件状态；脚本只做等长的「值 -> 令牌」替换，不增删行，
# 所以整批改完行号仍然对得上。
# ---------------------------------------------------------------------------
SITES = {
    'AppIcon.i14': [
        # 13 → 14：结算页统计卡标签左侧小图标、列表行内小标记、排序箭头。
        ('lib/pages/home/home.dart', 2372, '13'),
        ('lib/pages/home/widgets/word_list_tile.dart', 439, '13'),
        ('lib/pages/home/widgets/word_sort_bar.dart', 232, '13'),
        ('lib/pages/meaning_match/meaning_match_page.dart', 1577, '13'),
        # 14 → 14：本来就在台阶上，只是换成令牌。
        ('lib/pages/home/home.dart', 2404, '14'),
        ('lib/pages/home/widgets/dashboard/checkin_heatmap_card.dart', 367, '14'),
        ('lib/pages/home/widgets/group_filter_bar.dart', 144, '14'),
        ('lib/pages/home/widgets/group_filter_bar.dart', 182, '14'),
        ('lib/pages/home/widgets/word_form_sheet.dart', 728, '14'),
        ('lib/pages/listening/listening_page.dart', 1019, '14'),
        ('lib/pages/listening/widgets/listening_controls.dart', 311, '14'),
        ('lib/pages/spelling_reinforcement/spelling_reinforcement_page.dart', 1324, '14'),
        ('lib/pages/spelling_reinforcement/spelling_reinforcement_page.dart', 1346, '14'),
    ],
    'AppIcon.i16': [
        # 15 → 16：抽屉菜单每一项左侧图标、悬浮菜单「继续」小三角、随身听控制条。
        ('lib/pages/home/widgets/home_drawer.dart', 1012, '15'),
        ('lib/pages/home/widgets/home_drawer.dart', 1045, '15'),
        ('lib/pages/home/widgets/home_drawer.dart', 1151, '15'),
        ('lib/pages/home/widgets/home_drawer.dart', 1184, '15'),
        ('lib/pages/home/widgets/learning_fab.dart', 482, '15'),
        ('lib/pages/listening/widgets/listening_controls.dart', 201, '15'),
        # 16 → 16：本来就在台阶上。
        ('lib/pages/home/widgets/learning_fab.dart', 421, '16'),
        ('lib/pages/listening/widgets/listening_controls.dart', 60, '16'),
        ('lib/pages/listening/widgets/listening_controls.dart', 369, '16'),
        ('lib/pages/listening/widgets/listening_controls.dart', 377, '16'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 842, '16'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 859, '16'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 1431, '16'),
        # 17 → 16：抽屉分组标题、表单删除键、词库抽屉行、听音辨义底部按钮。
        ('lib/pages/home/widgets/home_drawer.dart', 471, '17'),
        ('lib/pages/home/widgets/home_drawer.dart', 576, '17'),
        ('lib/pages/home/widgets/word_form_sheet.dart', 514, '17'),
        ('lib/pages/home/widgets/word_form_sheet.dart', 564, '17'),
        ('lib/pages/home/widgets/word_library_sheet.dart', 394, '17'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 1567, '17'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 1601, '17'),
        # 18 → 16：打卡卡片翻月箭头、抽屉明暗开关 / 添加单词 / 页脚双图标、
        # 学习悬浮按钮的书本与叉叉、三个模块结算页「再来一组」旋转箭头。
        ('lib/pages/home/widgets/dashboard/checkin_heatmap_card.dart', 703, '18'),
        ('lib/pages/home/widgets/home_drawer.dart', 334, '18'),
        ('lib/pages/home/widgets/home_drawer.dart', 392, '18'),
        ('lib/pages/home/widgets/home_drawer.dart', 1298, '18'),
        ('lib/pages/home/widgets/home_drawer.dart', 1313, '18'),
        ('lib/pages/home/widgets/learning_fab.dart', 206, '18'),
        ('lib/pages/home/widgets/learning_fab.dart', 217, '18'),
        ('lib/pages/meaning_match/meaning_match_page.dart', 1481, '18'),
        ('lib/pages/meaning_word_choice/meaning_word_choice_page.dart', 1256, '18'),
        ('lib/pages/spelling_reinforcement/spelling_reinforcement_page.dart', 1594, '18'),
    ],
    'AppIcon.i20': [
        # 19 → 20：词库抽屉每行左侧的圆形图标。
        ('lib/pages/home/widgets/word_library_sheet.dart', 359, '19'),
        # 20 → 20：本来就在台阶上。
        ('lib/pages/home/widgets/dashboard/review_mode_grid.dart', 244, '20'),
        ('lib/pages/home/widgets/home_header.dart', 120, '20'),
        ('lib/pages/home/widgets/word_form_sheet.dart', 410, '20'),
        ('lib/pages/home/widgets/word_search_field.dart', 79, '20'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 810, '20'),
        ('lib/pages/meaning_word_choice/meaning_word_choice_page.dart', 1337, '20'),
        # 21 → 20：随身听 / 听音辨义顶栏图标按钮、键盘删除键。
        ('lib/pages/listening/widgets/listening_controls.dart', 261, '21'),
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 1734, '21'),
        ('lib/widgets/qwerty_keyboard.dart', 560, '21'),
    ],
    'AppIcon.i24': [
        # 24 → 24：本来就在台阶上。
        ('lib/pages/listening/listening_page.dart', 1149, '24'),
    ],
    'AppIcon.i32': [
        # 32 → 32：本来就在台阶上。
        ('lib/pages/listening_meaning/listening_meaning_page.dart', 1650, '32'),
    ],
}

# ---------------------------------------------------------------------------
# 二、`iconSize:` 点位表
#
# 与 `size:` 分开，因为关键字不同，自检的正则也不同。
# ---------------------------------------------------------------------------
ICON_SIZE_SITES = {
    'AppIcon.i32': [
        # 34 → 32：听音辨义听音阶段中央 88 圆盘里的扬声器。
        ('lib/pages/listening_meaning/widgets/listening_meaning_question_content.dart', 319, '34'),
    ],
}

# ---------------------------------------------------------------------------
# 二之二、构造器默认值
#
# `this.iconSize = 20` 这种写法没有 `iconSize:` 的冒号形式，单独整行替换。
# ---------------------------------------------------------------------------
DEFAULT_ARGS = [
    (
        'lib/widgets/audio_speaker_button.dart',
        'this.iconSize = 20,',
        'this.iconSize = AppIcon.i20,',
    ),
]

# ---------------------------------------------------------------------------
# 三、页面尺寸表里的图标常量
#
# 结构：(相对路径, 行号, 旧的整行片段, 新的整行片段)
# ---------------------------------------------------------------------------
LAYOUT_CONSTANTS = [
    (
        'lib/pages/spelling_reinforcement/widgets/spelling_layout.dart',
        'static const double headerIconSize = 21;',
        'static const double headerIconSize = AppIcon.i20;',
    ),
    (
        'lib/pages/meaning_match/widgets/meaning_match_layout.dart',
        'static const double headerIconSize = 21;',
        'static const double headerIconSize = AppIcon.i20;',
    ),
    (
        'lib/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart',
        'static const double headerIconSize = 21;',
        'static const double headerIconSize = AppIcon.i20;',
    ),
    (
        'lib/pages/spelling_reinforcement/widgets/spelling_layout.dart',
        'static const double summaryStatIconSize = 13;',
        'static const double summaryStatIconSize = AppIcon.i14;',
    ),
]

# ---------------------------------------------------------------------------
# 四、不参与收敛的 `size:`（照抄圆角那一轮的 EXCLUDE 思路，写清原因）
# ---------------------------------------------------------------------------
EXCLUDE_NOTES = {
    ('lib/pages/listening_meaning/widgets/listening_meaning_question_content.dart', 318):
        '88 是圆形按钮的直径（原型 `.speaker`），不是图标尺寸；只有它旁边的 iconSize 参与收敛。',
    ('lib/widgets/audio_speaker_button.dart', 18):
        'size = 40 同样是按钮直径，属于造型尺寸，跟着间距那一步走。',
    ('lib/pages/meaning_match/widgets/meaning_match_layout.dart', 118):
        '这行是 cardLabelSize 的文档注释里提到的 `font-size: 0.8125rem`，是字号不是图标。',
}

# 缺 theme 导入的文件：换成 AppIcon 之后必须补上，否则编译不过。
NEEDS_IMPORT = {
    'lib/widgets/qwerty_keyboard.dart': (
        "import 'package:tabler_icons_plus/tabler_icons_plus.dart';",
        "import 'package:tabler_icons_plus/tabler_icons_plus.dart';\n"
        "\n"
        "// 引入设计令牌，键帽上的删除图标从 AppIcon 台阶取尺寸。\n"
        "import '../common/theme.dart';",
    ),
}

ICON_HINT = re.compile(r'Icon\(|TablerIcons|Icons\.|AudioSpeakerButton|iconSize')


def apply_value_sites(table, keyword, dry):
    """把 `keyword: 旧值` 换成 `keyword: 新令牌`，替换前逐行自检。"""
    changed, problems = 0, []
    for token, sites in table.items():
        for rel, line_no, old in sites:
            path = pathlib.Path(rel)
            lines = path.read_text().splitlines(keepends=True)
            if line_no > len(lines):
                problems.append(f'{rel}:{line_no} 超出文件行数 {len(lines)}')
                continue
            raw = lines[line_no - 1]
            needle = f'{keyword}: {old}'
            if needle not in raw:
                problems.append(f'{rel}:{line_no} 找不到 `{needle}`，实际是：{raw.strip()[:70]}')
                continue
            # 自检：这一行前后 4 行里必须出现 Icon 相关的字样。
            window = ''.join(lines[max(0, line_no - 8):line_no + 2])
            if not ICON_HINT.search(window):
                problems.append(f'{rel}:{line_no} 附近没有 Icon 字样，疑似误判')
                continue
            if not dry:
                lines[line_no - 1] = raw.replace(needle, f'{keyword}: {token}', 1)
                path.write_text(''.join(lines))
            changed += 1
    return changed, problems


def apply_layout_constants(dry):
    """整行替换页面尺寸表里的图标常量与构造器默认值。"""
    changed, problems = 0, []
    for rel, old, new in LAYOUT_CONSTANTS + DEFAULT_ARGS:
        path = pathlib.Path(rel)
        text = path.read_text()
        if old not in text:
            problems.append(f'{rel} 找不到 `{old}`')
            continue
        if not dry:
            path.write_text(text.replace(old, new, 1))
        changed += 1
    return changed, problems


def apply_imports(dry):
    """给缺 theme 导入的文件补上。"""
    changed, problems = 0, []
    for rel, (anchor, replacement) in NEEDS_IMPORT.items():
        path = pathlib.Path(rel)
        text = path.read_text()
        if "common/theme.dart" in text:
            continue
        if anchor not in text:
            problems.append(f'{rel} 找不到导入锚点')
            continue
        if not dry:
            path.write_text(text.replace(anchor, replacement, 1))
        changed += 1
    return changed, problems


def main() -> int:
    dry = '--dry' in sys.argv
    total, all_problems = 0, []

    for label, fn in (
        ('内联 size:', lambda: apply_value_sites(SITES, 'size', dry)),
        ('内联 iconSize:', lambda: apply_value_sites(ICON_SIZE_SITES, 'iconSize', dry)),
        ('尺寸表常量', lambda: apply_layout_constants(dry)),        ('补 theme 导入', lambda: apply_imports(dry)),
    ):
        n, problems = fn()
        total += n
        all_problems += problems
        print(f'{label:16} {n:>3} 处')

    print(f'\n跳过（非图标）{len(EXCLUDE_NOTES)} 处：')
    for (rel, line_no), why in EXCLUDE_NOTES.items():
        print(f'  {rel}:{line_no}  {why}')

    if all_problems:
        print(f'\n⚠️  {len(all_problems)} 处自检不通过，这些点位没有改：')
        for p in all_problems:
            print(f'  {p}')
        return 1

    print(f'\n{"（演练）" if dry else ""}合计 {total} 处，自检全部通过')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
