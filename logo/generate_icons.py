#!/usr/bin/env python3
"""Generate all required Android / iOS launcher icon sizes from master exports."""

from pathlib import Path
from PIL import Image

# ---------------------------------------------------------------------------
# 路径配置
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent
EXPORTS = ROOT / "_source"
OUT = ROOT

MASTER = EXPORTS / "master_1024.png"                    # 1024x1024 主图标
ADAPT_BG = EXPORTS / "adaptive_background_1080.png"     # 1080x1080 Android 自适应背景
ADAPT_FG = EXPORTS / "adaptive_foreground_1080.png"     # 1080x1080 Android 自适应前景

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
def resize(src: Path, dst: Path, size: int, rgb: bool = False):
    """将源图缩放为 size x size 并保存到 dst。"""
    with Image.open(src) as im:
        im = im.convert("RGBA")
        im = im.resize((size, size), Image.Resampling.LANCZOS)
        if rgb:
            # App Store / Play Store 要求无透明通道
            bg = Image.new("RGB", im.size, (255, 255, 255))
            bg.paste(im, mask=im.split()[3])
            im = bg
        dst.parent.mkdir(parents=True, exist_ok=True)
        im.save(dst, "PNG")

# ---------------------------------------------------------------------------
# iOS App Icon 尺寸
# ---------------------------------------------------------------------------
# 每个元组: (目录名, 基础尺寸, scale)
ios_specs = [
    ("AppIcon-20x20", 20, 1),
    ("AppIcon-20x20", 20, 2),
    ("AppIcon-20x20", 20, 3),
    ("AppIcon-29x29", 29, 1),
    ("AppIcon-29x29", 29, 2),
    ("AppIcon-29x29", 29, 3),
    ("AppIcon-40x40", 40, 1),
    ("AppIcon-40x40", 40, 2),
    ("AppIcon-40x40", 40, 3),
    ("AppIcon-60x60", 60, 2),
    ("AppIcon-60x60", 60, 3),
    ("AppIcon-76x76", 76, 1),
    ("AppIcon-76x76", 76, 2),
    ("AppIcon-83.5x83.5", 83.5, 2),    # 实际像素 167
    ("AppIcon-1024x1024", 1024, 1),    # App Store
]

ios_dir = OUT / "ios"
for name, base, scale in ios_specs:
    pixel = int(base * scale)
    filename = f"{name}@{scale}x.png"
    resize(MASTER, ios_dir / filename, pixel, rgb=(pixel == 1024))

# 兼容旧尺寸（可选，覆盖常见需求）
extra_ios = [
    ("AppIcon-57x57", 57, 1),
    ("AppIcon-57x57", 57, 2),
    ("AppIcon-72x72", 72, 1),
    ("AppIcon-72x72", 72, 2),
    ("AppIcon-50x50", 50, 1),
    ("AppIcon-50x50", 50, 2),
]
for name, base, scale in extra_ios:
    pixel = int(base * scale)
    filename = f"{name}@{scale}x.png"
    resize(MASTER, ios_dir / filename, pixel)

# ---------------------------------------------------------------------------
# Android 传统图标
# ---------------------------------------------------------------------------
android_specs = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]
for folder, size in android_specs:
    resize(MASTER, OUT / "android" / folder / "ic_launcher.png", size)

# ---------------------------------------------------------------------------
# Android 自适应图标 (API 26+)
# ---------------------------------------------------------------------------
# foreground / background 为 1080x1080 (xxxhdpi 的四倍)
resize(ADAPT_BG, OUT / "android" / "mipmap-xxxhdpi" / "ic_launcher_background.png", 288)
resize(ADAPT_FG, OUT / "android" / "mipmap-xxxhdpi" / "ic_launcher_foreground.png", 288)
resize(ADAPT_BG, OUT / "android" / "mipmap-xxhdpi" / "ic_launcher_background.png", 216)
resize(ADAPT_FG, OUT / "android" / "mipmap-xxhdpi" / "ic_launcher_foreground.png", 216)
resize(ADAPT_BG, OUT / "android" / "mipmap-xhdpi" / "ic_launcher_background.png", 144)
resize(ADAPT_FG, OUT / "android" / "mipmap-xhdpi" / "ic_launcher_foreground.png", 144)
resize(ADAPT_BG, OUT / "android" / "mipmap-hdpi" / "ic_launcher_background.png", 108)
resize(ADAPT_FG, OUT / "android" / "mipmap-hdpi" / "ic_launcher_foreground.png", 108)
resize(ADAPT_BG, OUT / "android" / "mipmap-mdpi" / "ic_launcher_background.png", 72)
resize(ADAPT_FG, OUT / "android" / "mipmap-mdpi" / "ic_launcher_foreground.png", 72)

# 自适应图标无 dpi 限制的源尺寸 (1080x1080)
resize(ADAPT_BG, OUT / "android" / "adaptive" / "ic_launcher_background.png", 1080)
resize(ADAPT_FG, OUT / "android" / "adaptive" / "ic_launcher_foreground.png", 1080)

# ---------------------------------------------------------------------------
# Play Store / App Store 大图
# ---------------------------------------------------------------------------
resize(MASTER, OUT / "play_store" / "ic_launcher-playstore.png", 512, rgb=True)
resize(MASTER, OUT / "app_store" / "AppIcon-1024x1024.png", 1024, rgb=True)

# ---------------------------------------------------------------------------
# 汇总输出
# ---------------------------------------------------------------------------
generated = sorted(OUT.rglob("*.png"))
print(f"已生成 {len(generated)} 个图标文件:")
for f in generated:
    if f.name == "generate_icons.py":
        continue
    print(f"  {f.relative_to(OUT)}")
