# MyEnglish 应用图标

原创标识，纯图形无文字。

## 设计说明

**方案 A「声波成文」（已采用）**

上半部四根高低起伏的圆头竖条代表**听到的声音**，下半部两根圆头横条代表**写下的文字**——
自上而下的视觉流对应 App 的核心动作：听 → 写 → 记（听写 / 发音 / 复习）。

- 全部图形由基础矩形构成，统一圆角（半径 = 条宽的一半，形成全圆头端点）。
- 条宽统一 11 单位、间距 7 单位（100×100 设计网格），共用同一条基线节奏。
- 标识占画布 65%，符合 iOS / Android 图标视觉重心规范。
- 48×48 最小尺寸下四根声波条与两行文字条仍完整分离，无糊成一团的风险。

**配色**：Tabler 靛蓝 `#4263EB` → 亮蓝 `#206BC4` 45° 线性渐变，图形纯白。

## 备选方案

`_concepts/` 内保留另外两个原创方案，可随时替换：

- **方案 B「词卡堆叠」** — 三张扇形展开的圆角卡片，对应背单词的卡片式记忆。
- **方案 C「双页展开」** — 两片对称的锥形页面，对应词典 / 书本的开卷意象。

## 目录说明

| 目录 | 内容 |
|---|---|
| `ios/` | iOS 应用图标全尺寸，命名 `AppIcon-<pt>x<pt>@<scale>x.png` |
| `android/mipmap-*/` | Android 传统启动器图标（mdpi ~ xxxhdpi）+ 自适应图标背景 / 前景 |
| `android/adaptive/` | Android 自适应图标原始素材（1080×1080） |
| `app_store/` | App Store 上架图（1024×1024，无 Alpha） |
| `play_store/` | Google Play 商店图（512×512，无 Alpha） |
| `_source/` | 设计稿导出的三张主图，脚本的输入源 |
| `_concepts/` | 三个方案的对比预览图 |
| `generate_icons.py` | 从 `_source/` 重新切出全部尺寸的脚本 |

## 主要尺寸速查

| 平台 | 尺寸 | 文件 |
|---|---|---|
| iOS App Store | 1024×1024 | `app_store/AppIcon-1024x1024.png` |
| iPhone | 180×180 (60@3x) | `ios/AppIcon-60x60@3x.png` |
| iPad Pro | 167×167 (83.5@2x) | `ios/AppIcon-83.5x83.5@2x.png` |
| Android xxxhdpi | 192×192 | `android/mipmap-xxxhdpi/ic_launcher.png` |
| Play Store | 512×512 | `play_store/ic_launcher-playstore.png` |

## 重新生成

替换 `_source/` 下的三张主图后执行：

```bash
python generate_icons.py
```

## 尚未接入应用

当前图标仅存放在本目录，**尚未拷贝到 `my_english/android/` 与 `my_english/ios/`**。
需要正式生效时再执行接入（并同步更新 `pubspec.yaml` 版本号）。
