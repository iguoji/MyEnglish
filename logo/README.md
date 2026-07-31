# MyEnglish 应用图标

纯图标、无文字，采用 Tabler 主色（靛蓝 → 亮蓝渐变），中心为 Tabler `vocabulary` 图标。

## 目录说明

- `ios/` — iOS 应用图标全尺寸，命名规则 `AppIcon-<pt>x<pt>@<scale>x.png`。
- `android/mipmap-*/` — Android 传统启动器图标（mdpi ~ xxxhdpi）及自适应图标背景/前景。
- `android/adaptive/` — Android 自适应图标原始尺寸背景与前景（1080×1080）。
- `app_store/` — App Store 上架图（1024×1024，无 Alpha）。
- `play_store/` — Google Play 商店图（512×512，无 Alpha）。
- `generate_icons.py` — 从主图重新生成全部尺寸的脚本。

## 主要尺寸速查

| 平台 | 尺寸 | 文件 |
|---|---|---|
| iOS App Store | 1024×1024 | `app_store/AppIcon-1024x1024.png` |
| iPhone | 180×180 (60@3x) | `ios/AppIcon-60x60@3x.png` |
| iPad Pro | 167×167 (83.5@2x) | `ios/AppIcon-83.5x83.5@2x.png` |
| Android xxxhdpi | 192×192 | `android/mipmap-xxxhdpi/ic_launcher.png` |
| Play Store | 512×512 | `play_store/ic_launcher-playstore.png` |
