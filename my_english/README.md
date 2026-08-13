# MyEnglish

MyEnglish 是一款基于 Flutter 开发的英语单词学习应用，面向需要长期积累、复习和默写英语词汇的用户。

当前版本：`0.22.8+8`

## 功能概览

- 首页单词列表
  - 浏览、搜索、排序和折叠单词。
  - 支持美式和英式发音设置。
  - 支持单词新增、编辑、删除和批量选择。
  - 支持自定义分组。
- 随身听
  - 按当前学习列表循环播放单词。
  - 支持重复次数、播放间隔和列表循环。
  - 支持锁屏、通知栏、蓝牙耳机媒体控制。
  - 支持保存和恢复未完成的学习进度。
- 单词默写
  - 通过听音选择单词。
  - 通过中文释义选择单词。
  - 记录错误次数、提示次数和每次默写结果。
  - 根据默写结果调整单词难度。
  - 保存候选项和未完成的默写进度。
- 本地词库
  - 首次安装自动导入内置 `words.json`。
  - 支持从 JSON 文件导入词库。
  - 支持将词库、分组和关联关系导出为 JSON 备份。
  - 用户主动清空数据后不会在下次启动时自动恢复内置词库。
- 音频播放
  - 优先播放本地 MP3 缓存。
  - 网络可用时依次尝试不背单词和有道音频。
  - 网络不可用时使用 Android 系统离线英语 TTS 兜底。
  - 支持清空全部离线音频缓存。

## 音频策略

播放一个单词时，实际执行顺序如下：

```text
本地 MP3 缓存
    ↓ 未命中
不背单词网络音频
    ↓ 失败
有道网络音频
    ↓ 失败或明确无网络
Android 系统离线英语 TTS
```

### 网络判断与失败记录

- 如果 Android 明确检测到没有活动网络，直接使用离线 TTS，不请求网络。
- 如果网络状态无法确定，会先尝试网络音频。
- 两个网络音源都失败后，会记录网络音频不可用状态 `5 分钟`。
- 记录有效期间，后续没有本地缓存的单词会直接使用 TTS，避免每个单词重复等待网络超时。
- 网络音频成功后会自动清除失败记录。
- 每个网络音源的连接和读取超时均为 `1 秒`。

网络失败记录保存在 Android App 私有存储中，不包含单词内容，也不会影响词库和学习记录。

### Android 系统 TTS

应用调用 Android 原生 `TextToSpeech` 接口。真正使用的语音引擎由用户设备决定，可以是：

- 手机厂商自带的 TTS 引擎。
- 用户安装的 Google TTS 或其他第三方 TTS 引擎。
- 其他兼容 Android TTS 接口的系统语音引擎。

应用只选择被系统标记为“不需要网络”的英语声音。若设备没有可用的离线英语声音，会提示用户联网播放或安装英语语音包。

首次成功使用 TTS 时，首页、随身听和单词默写页面会分别提示：

> 当前网络音频不可用，正在使用系统 TTS 朗读

同一页面后续单词不重复提示。应用退到后台或重新进入页面后，下一次 TTS 播放会重新提示。

## 技术架构

```text
Flutter 页面层
    ├── 首页 HomePage
    ├── 随身听 ListeningPage
    └── 单词默写 DictationPage
          │
          ├── Dart Store：页面状态与数据模型
          └── MethodChannel：Flutter 与 Android 原生通信
                    │
                    ├── Kotlin WordsDatabase：SQLite 词库与学习记录
                    ├── Kotlin WordAudioPlayer：MP3 缓存、网络音频和 TTS
                    └── Kotlin AppSettingsStore：应用设置与初始化标记
```

主要目录：

| 目录 | 作用 |
|---|---|
| `lib/pages/` | Flutter 页面和页面专属组件 |
| `lib/models/` | 单词、释义、分组、记录和学习会话模型 |
| `lib/store/` | Dart 数据存储接口和 MethodChannel 调用 |
| `lib/services/` | 音频、缓存、文件和内置词库服务 |
| `android/app/src/main/kotlin/` | Android 原生 SQLite、音频、TTS 和设置实现 |
| `assets/data/` | 随安装包发布的内置词库资源 |
| `test/` | Flutter 单元测试和 Widget 测试 |
| `android/app/src/test/` | Android JVM 单元测试 |
| `android/app/src/androidTest/` | Android 真机/模拟器仪器测试 |
| `tools/` | 构建期辅助脚本 |

## 数据存储

应用使用 Android SQLite 保存业务数据，主要数据表包括：

- `words`：单词本体和词形变化。
- `meanings`：词性和中文释义。
- `groups`：自定义分组。
- `group_members`：单词与分组的多对多关系。
- `record`：单词默写记录。
- `dictation_option_cache`：默写候选项缓存。
- `learning_sessions`：随身听和默写的未完成会话。

数据库结构当前为第 `9` 版。版本 9 会按当前字段标准重建旧词库结构，旧词数据不会自动迁移；启动时如果数据库为空，会根据独立初始化标记导入内置词库。

数据库文件名为 `my_english.db`，存放在 Android 应用私有数据库目录中，通常类似：

```text
/data/user/0/com.example.my_english/databases/my_english.db
```

具体绝对路径由 Android 设备决定，应用不申请外部存储权限。

## 开发环境

建议使用以下工具：

- Flutter SDK，版本需要满足 `pubspec.yaml` 中的 Dart SDK 约束。
- Android Studio 或 Android SDK。
- JDK 17。
- Kotlin 和 Gradle 版本以项目 Android 配置为准。

当前应用的 Android 原生实现较多，完整功能应使用 Android 模拟器或真机验证。尤其是系统 TTS，需要在目标手机上确认是否安装了离线英语语音包。

## 获取依赖

在 Flutter 项目目录执行：

```bash
cd my_english
flutter pub get
```

项目使用本地 `third_party/tabler_icons_plus`，图标依赖不要求额外访问网络仓库。

## 运行与构建

运行 Debug 版本：

```bash
cd my_english
flutter run
```

构建 Release APK：

```bash
cd my_english
flutter build apk --release
```

正式构建前需要准备 `android/key.properties`，其中包含正式签名所需的 keystore 路径、密码和别名。该文件已被 Git 忽略，不能从仓库恢复；没有它时，Release/Debug 构建可能无法完成签名配置。

生成的 APK 默认位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

Android Release 和 Debug 构建都配置为使用 `android/key.properties` 中的正式签名。该文件包含签名敏感信息，不应提交到 Git。

## 版本号

`pubspec.yaml` 是版本号的唯一数据源：

```yaml
version: 0.22.8+8
```

修改版本号后执行同步脚本：

```bash
cd my_english
dart run tools/sync_app_info.dart
```

脚本会更新 `lib/common/app_info.dart`，应用抽屉显示的版本号和 Flutter/Android 构建版本因此保持一致。

## 测试

运行 Flutter 静态分析：

```bash
cd my_english
flutter analyze
```

运行 Flutter 测试：

```bash
cd my_english
flutter test
```

运行 Android JVM 单元测试：

```bash
cd my_english/android
./gradlew :app:testDebugUnitTest
```

运行 Android Kotlin 编译检查：

```bash
cd my_english/android
./gradlew :app:compileDebugKotlin
```

运行 Android 仪器测试需要连接 Android 真机或启动模拟器：

```bash
cd my_english/android
./gradlew :app:connectedDebugAndroidTest
```

## 清空数据与缓存

首页菜单中的“清空数据”会清理：

- SQLite 中的单词、释义、分组和成员关系。
- 候选项缓存和未完成学习会话。
- Android App 私有目录中的全部离线 MP3。
- 普通应用设置，例如口音、主题和每日目标。

清空离线音频时会先停止当前 MP3 和 TTS，再删除缓存目录。只有 Android 原生确认删除成功后，界面才会把缓存进度重置为 `0%`。

内置词库初始化标记存放在独立的 Android 私有存储中，因此用户清空数据后，下一次启动不会重新导入默认词库。

当前“清空数据”不会删除 `record` 表中的历史默写记录；如需彻底删除默写历史，需要另行扩展数据库清理逻辑。

## 音频来源

网络音频地址由当前业务配置提供：

- 不背单词美式：`https://audio.beingfine.cn/speeches/US/US-speech/{spelling}.mp3`
- 不背单词英式：`https://audio.beingfine.cn/speeches/UK/UK-speech/{spelling}.mp3`
- 有道美式：`https://dict.youdao.com/dictvoice?audio={spelling}&type=2`
- 有道英式：`https://dict.youdao.com/dictvoice?audio={spelling}&type=1`

网络音频仅用于播放和缓存，应用不会把用户词库上传到上述服务。

## 当前限制

- 当前原生 TTS 兜底实现面向 Android；不同品牌手机的 TTS 引擎、声音质量和离线语音包名称可能不同。
- 如果设备没有离线英语语音，TTS 无法在完全无网状态下朗读，需要用户安装语音包或恢复网络。
- 网络失败记录有效期暂定为 5 分钟，应用不会在有效期内主动探测网络恢复；网络音频成功时会自动恢复正常策略。
- 目前项目仓库没有 iOS 工程目录，README 中的原生 TTS 说明以 Android 为准。

## 代码规范

- Flutter 页面采用页面目录组织。
- UI 图标统一使用 Tabler 图标。
- Dart 和 Kotlin 代码保留中文注释，说明数据流和关键业务逻辑。
- 数据库写入通过事务完成，避免部分导入或清空。
- 网络下载先写临时文件，校验 MP3 文件头后再替换正式缓存。
