"""第 3 步之一：把全 lib 的圆角 / 线宽字面量收敛到 AppRadius / AppStroke 台阶。

用法：python3 tools/converge_radius.py [--apply]
不加 --apply 只打印将要发生的改动。

为什么要脚本：圆角字面量有 110 处、散在 24 个文件里，手改必漏。
按「值 → 台阶」统一映射，再用 EXCLUDE / OVERRIDE 两张小表处理特例，
改完的每一处都能在报告里对上号。

收敛规则（与 lib/common/design/radii.dart 的注释一致）：
  1 / 2 / 3        → r2    进度条、细长分布条、虚线段
  4 / 5 / 6        → r6    徽标、勾选框、小标签、热力图方格
  7 / 8            → r8    卡片与主按钮
  10               → r10   候选卡、统计卡
  14 / 15          → r14   弹窗与底部面板
  20 / 23          → r20   悬浮按钮与大面板
  999              → pill  胶囊
"""

import re
import sys
from pathlib import Path

RADIUS_MAP = {
    '1': 'r2', '2': 'r2', '3': 'r2',
    '4': 'r6', '5': 'r6', '6': 'r6',
    '7': 'r8', '8': 'r8',
    '10': 'r10',
    '14': 'r14', '15': 'r14',
    '20': 'r20', '23': 'r20',
    '999': 'pill',
}

# 这些 Radius.circular 不是圆角，是 SVG 弧线的半径（照抄原型的 `a5 5` / `a9 9`），
# 换成造型台阶会画错喇叭图标的弧。
EXCLUDE = {
    ('lib/widgets/audio_speaker_button.dart', 279),
    ('lib/widgets/audio_speaker_button.dart', 288),
}

# 40×5 的底部抽屉拖拽条：半径 5 已经等于高度的一半，Flutter 会自动夹到 2.5
# 画成胶囊。写 pill 与现状逐像素相同，且语义正确。
OVERRIDE = {
    ('lib/pages/home/widgets/word_library_sheet.dart', 430): 'pill',
}

# 线宽：只有 3 处裸数字，逐处点名，避免误伤 width 同名的其它属性。
STROKE_SITES = {
    ('lib/pages/home/home.dart', 2364): ('1.5', 'AppStroke.bold'),
    ('lib/pages/home/widgets/word_list_tile.dart', 433): ('1.5', 'AppStroke.bold'),
    ('lib/pages/home/widgets/word_library_sheet.dart', 382): ('1', 'AppStroke.thin'),
}

# 没有 import theme.dart 的文件，改完要补一行 import。
NEEDS_IMPORT = {
    'lib/common/toast.dart': "import '../common/theme.dart';",
    'lib/pages/home/widgets/word_search_field.dart': "import '../../../common/theme.dart';",
}

CIRCULAR = re.compile(r'\bcircular\((\d+(?:\.\d+)?)\)')


def main() -> int:
    apply = '--apply' in sys.argv
    root = Path('.')
    changed_files = 0
    changed_sites = 0
    kept_sites = 0

    targets = sorted({p for p in root.glob('lib/**/*.dart')})
    for path in targets:
        rel = path.as_posix()
        if rel.startswith('lib/common/design/'):
            continue
        lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
        edits = []

        for index, line in enumerate(lines):
            lineno = index + 1
            key = (rel, lineno)
            new_line = line

            if key in STROKE_SITES:
                raw, token = STROKE_SITES[key]
                new_line = new_line.replace(f'width: {raw},', f'width: {token},')

            if CIRCULAR.search(new_line):
                if key in EXCLUDE:
                    kept_sites += 1
                else:
                    def repl(match: re.Match) -> str:
                        raw = match.group(1)
                        step = OVERRIDE.get(key) or RADIUS_MAP.get(raw)
                        if step is None:
                            return match.group(0)
                        return f'circular(AppRadius.{step})'

                    new_line = CIRCULAR.sub(repl, new_line)

            if new_line != line:
                edits.append((lineno, line.rstrip('\n'), new_line.rstrip('\n')))
                lines[index] = new_line
                changed_sites += 1

        if not edits:
            continue
        changed_files += 1
        print(f'\n=== {rel} ===')
        for lineno, old, new in edits:
            print(f'  {lineno}: {old.strip()}')
            print(f'   → {new.strip()}')

        if apply:
            text = ''.join(lines)
            extra = NEEDS_IMPORT.get(rel)
            if extra and extra not in text:
                # 插在最后一条 import 之后，保持现有分组不乱。
                body = text.splitlines(keepends=True)
                last = max(i for i, l in enumerate(body) if l.startswith('import '))
                body.insert(last + 1, '\n// 设计令牌：圆角台阶。\n' + extra + '\n')
                text = ''.join(body)
                print(f'  + 补 import：{extra}')
            path.write_text(text, encoding='utf-8')

    print(f'\n合计：{changed_files} 个文件、{changed_sites} 处改动，'
          f'跳过 {kept_sites} 处弧线半径'
          f'{"（已写入）" if apply else "（未写入，加 --apply 才落盘）"}')
    return 0


raise SystemExit(main())
