"""把动画时长收敛到 AppDuration 的六档台阶。

用法：python3 tools/converge_motion.py [--apply]

────────────────────────────────────────────────────────────────────────
为什么这一轮必须逐点位写死，不能按关键字全局替换
────────────────────────────────────────────────────────────────────────
`Duration` 在代码里有两种完全不同的身份，字面上却一模一样：

  1. 动画时长——「这个动作演多久」。它属于设计，全站必须一致，
     所以要收进台阶：卡片淡入 250ms、抖动 350ms、停顿 1200ms。
  2. 功能计时——「等多久再干正事」。它属于业务逻辑，跟好看不好看无关：
     搜索防抖 120ms、加载超时 8 秒、倒计时每秒跳一次、提示条停留 2 秒。

把第 2 类也塞进台阶，等于哪天想让动画快一点，顺手把加载超时也改了。
所以这里列了一张明细表，一行一个点位，改之前逐行核对原文，
对不上就整体停下，绝不猜。表外的 Duration 一律不动。

────────────────────────────────────────────────────────────────────────
刻意保留的功能计时（不是漏了）
────────────────────────────────────────────────────────────────────────
  · `Duration(seconds: 1)` × 5      四个学习模块 + 随身听的每秒一跳
  · `toast.dart` 的 `seconds: 2`     提示条停留时长
  · `home.dart` 的 `seconds: 8`      原生通道加载超时
  · `home.dart` 的 `milliseconds: 120`  搜索框防抖
  · 键盘 `_kDeleteHoldDelayMs 420`   长按多久才算长按（原型 holdT）
  · 键盘 `_kDeleteRepeatMs 90`       连发退格的间隔（原型 holdI）
"""

import pathlib
import sys

# ---------------------------------------------------------------------------
# 明细表：(相对路径, 行号, 原文片段, 新文片段, 这么归档的理由)
#
# 归档口径来自计划的「刻度」一节：180→160、200/210/220/250/300→250、
# 400→350、600→800、84→100、1000→1200。
# ---------------------------------------------------------------------------
SITES = [
    # ===== 一、首页与公共组件 =====
    ('lib/pages/home/widgets/learning_fab.dart', 93,
     'const Duration(milliseconds: 300)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '学习悬浮菜单展开 / 收起：与其它「换面板」类过渡统一到 250。'),
    ('lib/pages/home/widgets/learning_fab.dart', 335,
     'const Duration(milliseconds: 220)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '最近学习记录淡入横向展开：同上归 250。'),
    ('lib/pages/home/widgets/learning_fab.dart', 336,
     'const Duration(milliseconds: 180)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '同一处的收起动画：收起一向比展开快一档，归 160。'),
    ('lib/pages/home/widgets/word_form_sheet.dart', 299,
     'const Duration(milliseconds: 180)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '键盘弹出时表单让位：归 160。'),
    ('lib/pages/home/widgets/word_list_tile.dart', 177,
     'const Duration(milliseconds: 180)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '单词行左滑露出操作区：归 160。'),
    ('lib/pages/home/widgets/word_list_tile.dart', 315,
     'const Duration(milliseconds: 160)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '展开释义的高度过渡：原本就是 160，只是换成台阶名。'),
    ('lib/pages/home/widgets/word_list_tile.dart', 482,
     'const Duration(milliseconds: 1000)',
     'const Duration(seconds: 1)',
     '播放声纹的一秒循环周期：它对齐的是原型 @keyframes wave 的「一秒」，'
     '不是过渡时长，所以直接写成 seconds: 1，别人一看就知道不该动它。'),
    ('lib/pages/home/home.dart', 2400,
     'const Duration(milliseconds: 150)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '分组标题的折叠箭头旋转：归 160。'),
    ('lib/pages/home/widgets/word_library_sheet.dart', 126,
     'const Duration(milliseconds: 300)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '词库面板从屏幕下方滑出：归 250。'),
    ('lib/pages/home/widgets/dashboard/review_trend_chart.dart', 72,
     'Duration(milliseconds: 600)',
     'Duration(milliseconds: AppDuration.ms800)',
     '进页面后延迟多久才让曲线滑上来：这是刻意排出的出场节奏，归 800。'),
    ('lib/pages/home/widgets/dashboard/trend_chart.dart', 54,
     'const Duration(milliseconds: 600)',
     'const Duration(milliseconds: AppDuration.ms800)',
     '折线图节点生长的默认时长：与上面那处同一条曲线，一起归 800。'),
    ('lib/common/toast.dart', 119,
     'const Duration(milliseconds: 200)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '提示条进出场动画（注意不是它停留的 2 秒）：归 160。'),
    ('lib/widgets/audio_speaker_button.dart', 86,
     'const Duration(milliseconds: 100)',
     'const Duration(milliseconds: AppDuration.ms100)',
     '喇叭声纹换帧的节奏：原本就是 100，只是换成台阶名。'),
    ('lib/widgets/audio_speaker_button.dart', 99,
     'const Duration(milliseconds: 250)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '喇叭外圈弧线的亮灭节奏：原本就是 250，只是换成台阶名。'),

    # ===== 二、四个学习模块 =====
    ('lib/pages/listening/listening_page.dart', 967,
     'const Duration(milliseconds: 220)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '随身听列表自动滚到当前行：归 250。'),
    ('lib/pages/listening_meaning/widgets/listening_meaning_question_content.dart', 611,
     'const Duration(milliseconds: 180)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '播音胶囊下方文字换字：归 160。'),
    ('lib/pages/listening_meaning/listening_meaning_page.dart', 1504,
     'const Duration(milliseconds: 210)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '整组候选淡出淡入：归 250，与看义选词换题同一档。'),
    ('lib/pages/listening_meaning/listening_meaning_page.dart', 1813,
     'const Duration(milliseconds: 300)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '答错抖动：归 250。词义连连的抖动归 350（幅度更大），两者角色不同。'),
    ('lib/pages/meaning_word_choice/meaning_word_choice_page.dart', 672,
     'const Duration(milliseconds: 250)',
     'const Duration(milliseconds: AppDuration.ms250)',
     '换题时整张白卡淡入上移：原本就是 250，只是换成台阶名。'),
    ('lib/pages/spelling_reinforcement/spelling_reinforcement_page.dart', 1187,
     'const Duration(milliseconds: 180)',
     'const Duration(milliseconds: AppDuration.ms160)',
     '播音胶囊下方文字换字：与听音辨义同一处角色，归 160。'),

    # ===== 三、页面尺寸表里的时长常量 =====
    ('lib/pages/spelling_reinforcement/widgets/spelling_layout.dart', 148,
     'static const int waveTickMs = 84;',
     'static const int waveTickMs = AppDuration.ms100;',
     '声纹换帧：84 归 100，每秒十帧照样看得出在动。'),
    ('lib/pages/spelling_reinforcement/widgets/spelling_layout.dart', 206,
     'static const int wrongFeedbackDurationMs = 1000;',
     'static const int wrongFeedbackDurationMs = AppDuration.ms1200;',
     '答错后红色提示停留多久：归 1200，与看义选词「看清答案」同一档。'),
    ('lib/pages/meaning_match/widgets/meaning_match_layout.dart', 215,
     'static const int shakeDurationMs = 400;',
     'static const int shakeDurationMs = AppDuration.ms350;',
     '连错时卡片抖动：归 350。'),
    ('lib/pages/meaning_match/widgets/meaning_match_layout.dart', 234,
     'static const int groupAdvanceDelayMs = 600;',
     'static const int groupAdvanceDelayMs = AppDuration.ms800;',
     '一组五对连完后停顿多久再换下一组：归 800。'),
    ('lib/widgets/qwerty_keyboard.dart', 95,
     'const int _kPressMs = 80;',
     'const int _kPressMs = AppDuration.ms100;',
     '键帽按下缩小回弹：80 归 100。'),
    ('lib/widgets/qwerty_keyboard.dart', 98,
     'const int _kPressColorMs = 120;',
     'const int _kPressColorMs = AppDuration.ms100;',
     '键帽变灰过渡：120 归 100，从此与缩放同时收尾，不再一前一后。'),
    ('lib/widgets/qwerty_keyboard.dart', 111,
     'const int _kPressMinimumVisibleMs = 90;',
     'const int _kPressMinimumVisibleMs = AppDuration.ms100;',
     '快速点击时按下画面至少停留多久：归 100，正好等于一次按下反馈的长度。'),
]


def main() -> int:
    apply = '--apply' in sys.argv

    # 先整表核对再动手：任何一行对不上就全表放弃，避免改了一半留下烂摊子。
    texts, bad = {}, []
    for rel, line_no, old, _new, _why in SITES:
        if rel not in texts:
            texts[rel] = pathlib.Path(rel).read_text(encoding='utf-8').splitlines(keepends=True)
        lines = texts[rel]
        if line_no > len(lines):
            bad.append(f'{rel}:{line_no} 文件只有 {len(lines)} 行')
        elif lines[line_no - 1].count(old) != 1:
            bad.append(f'{rel}:{line_no} 期望恰好出现一次 `{old}`，实际 '
                       f'{lines[line_no - 1].count(old)} 次')
    if bad:
        print(f'⚠️  明细表与代码对不上 {len(bad)} 处，已停止（未改任何文件）：')
        for line in bad:
            print(f'  {line}')
        return 1

    for rel, line_no, old, new, _why in SITES:
        lines = texts[rel]
        lines[line_no - 1] = lines[line_no - 1].replace(old, new, 1)

    if apply:
        for rel, lines in texts.items():
            pathlib.Path(rel).write_text(''.join(lines), encoding='utf-8')

    tail = '（已写入）' if apply else '（未写入，加 --apply 落盘）'
    print(f'时长收敛 {len(SITES)} 处，涉及 {len(texts)} 个文件{tail}\n')
    for rel, line_no, old, new, why in SITES:
        print(f'  {rel}:{line_no}')
        print(f'    {old}  →  {new}')
        print(f'    {why}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
