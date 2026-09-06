"""比对两组 golden：逐图报告差异像素数与差异区域的包围盒。

用法：python3 tools/golden_diff.py <旧目录> <新目录>

为什么不直接看图：12 张图 × 4 轮收敛 = 48 张，逐张肉眼过一遍代价太大。
先用这个脚本把「哪张图、差了多少像素、差在哪个矩形区域」量出来，
只有数字和预期不符的那几张才需要真的打开看。
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops


def diff_one(old, new):
    """返回（差异像素数, 差异包围盒, 最大单通道差值）。"""
    a = Image.open(old).convert('RGB')
    b = Image.open(new).convert('RGB')
    if a.size != b.size:
        return -1, None, -1
    d = ImageChops.difference(a, b)
    box = d.getbbox()
    if box is None:
        return 0, None, 0
    # 逐像素统计：只要三通道任一不同就算一处差异。
    count = sum(1 for px in d.getdata() if px != (0, 0, 0))
    peak = max(max(px) for px in d.getdata())
    return count, box, peak


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    old_dir, new_dir = Path(sys.argv[1]), Path(sys.argv[2])
    names = sorted(p.name for p in new_dir.glob('*.png'))
    total_changed = 0
    print(f"{'图':34} {'差异像素':>10}  {'占比':>7}  包围盒 (l,t,r,b)")
    print('-' * 86)
    for name in names:
        old, new = old_dir / name, new_dir / name
        if not old.exists():
            print(f"{name:34} {'新增':>10}")
            continue
        count, box, peak = diff_one(old, new)
        if count == -1:
            print(f"{name:34} {'尺寸不同':>10}")
            total_changed += 1
            continue
        if count == 0:
            print(f"{name:34} {0:>10}  {'—':>7}  逐像素一致")
            continue
        w, h = Image.open(new).size
        pct = count / (w * h) * 100
        print(f"{name:34} {count:>10}  {pct:6.2f}%  {box}  峰值Δ={peak}")
        total_changed += 1
    print('-' * 86)
    print(f"合计 {len(names)} 张，其中 {total_changed} 张有差异")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
