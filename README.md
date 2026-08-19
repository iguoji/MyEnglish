# MyEnglish

MyEnglish 是一款面向个人长期使用的 Android 英语单词学习应用。词库、分组、复习记录和学习进度主要保存在手机本地，不需要注册账号。

当前版本：`v0.22.10`（构建号 `10`）

> 当前只提供 Android 版本，暂不支持 iPhone 和 iPad。

## 下载与安装

前往 [GitHub Releases](https://github.com/iguoji/MyEnglish/releases) 下载最新 APK，在 Android 手机上打开并安装。

如果系统阻止安装，需要在手机设置中允许当前浏览器或文件管理器“安装未知应用”。这是 Android 对非应用商店 APK 的常规保护设置。

## 第一次使用

应用不会附带或自动导入任何默认词库。首次打开时词库为空，你可以：

- 打开右上角菜单，点击“添加单词”逐个录入。
- 点击“数据导入”，选择自己的 JSON 词库或之前由 MyEnglish 导出的备份。

导入会替换当前词库。已有数据时，建议先使用“数据导出”保存一份备份。

## 首页

首页集中显示当前学习状态：

- 复习趋势：查看最近 7 天或 30 天每天复习的单词数量。
- 复习质量：按日期显示复习情况，点击具体日期可在旁边查看当天复习数量。
- 今日复习：四种复习模式分别显示今日完成百分比；未完成时显示红色进度，达到目标后显示绿色“已完成”。
- 词库入口：点击底部上滑图标，或在首页进行较长距离的上滑手势，可以打开完整词库。

词库展开后，可以点击顶部手柄或使用 Android 返回手势将其收起。

## 词库管理

词库支持以下操作：

- 搜索单词，点击单词播放发音并展开释义。
- 新增、编辑和删除单词，维护音标、词性、释义、难度及常见词形变化。
- 创建、重命名、排序和删除自定义分组。
- 按分组、难度、复习时间、更新时间或加入时间查看词库。
- 按字母、含义复杂度、难度或日期排序。
- 批量选择单词，并移动或复制到其他分组。

“含义”排序会先比较释义数量；数量相同时，再比较全部释义文字的字符总数。

## 随身听与默写

词库底部提供两个普通学习入口。没有勾选单词时使用当前可见列表；勾选后只使用已选单词。

### 随身听

- 自动播放固定列表中的单词。
- 支持上一词、下一词、暂停和继续。
- 支持搜索跳转、显示或隐藏答案。
- 支持设置重复次数、播放间隔和列表循环。
- 支持锁屏、通知栏和蓝牙耳机媒体控制。
- 退出后保存进度，可从词库底部继续。

### 默写

- 先根据发音选择正确的英文单词。
- 再依次选择对应的中文释义。
- 记录错误次数、提示次数和答题结果。
- 错误会提高单词难度；连续正确达到规则要求后会降低难度。
- 候选项和未完成进度会保存在本地，可在当天之外继续普通默写。

## 今日复习

首页提供四种复习模式：

| 模式 | 当前状态 | 说明 |
|---|---|---|
| 听音辨义 | 可用 | 复用成熟的默写流程，完成量单独计入该模式 |
| 词义连连 | 暂未开放 | 当前进入独立占位页 |
| 拼写巩固 | 暂未开放 | 当前进入独立占位页 |
| 看义选词 | 暂未开放 | 当前进入独立占位页 |

四种模式每天共用同一批单词，但各自保存独立进度。每日数量取自右上角菜单中的“每日复习”设置；当天词单创建后，数量会固定到第二天。

今日词单按以下顺序挑选：

```text
未复习优先
→ 释义数量少的优先
→ 释义字符少的优先
→ 难度高的优先
→ 综合时间早的优先
→ 字母升序
→ 编号升序
```

其中综合时间优先使用最近复习时间；未复习单词使用更新时间，更新时间缺失时再使用加入时间。四个复习模块的页面进度只在当天有效。

## 发音与离线语音

可以在右上角菜单切换美式或英式发音。播放顺序如下：

```text
本地 MP3 缓存
→ 不背单词网络音频
→ 有道网络音频
→ Android 系统离线英语 TTS
```

TTS 是手机系统提供的文字转语音功能。应用只选择系统标记为可离线使用的英语声音；如果手机没有离线英语语音包，需要先在系统设置中安装。

菜单中的“离线语音”可以缓存当前词库的发音，并显示缓存进度。网络音频连续失败后，应用会在 5 分钟内优先使用系统 TTS，减少重复等待。

## 数据导入、导出与清空

- 数据导入：支持单词数组，或包含 `words`、`groups`、`members` 的 MyEnglish 备份对象。
- 数据导出：保存单词、释义、分组和分组关系，文件名类似 `MyEnglish-2026-08-19.json`。
- 清空数据：经过二次确认后，清空词库、分组、候选缓存、学习进度、今日词单、设置和离线 MP3。

当前导出文件不包含复习历史记录；当前“清空数据”也不会删除 `record` 表中的历史记录。请不要把导出文件理解为整个应用的完整镜像。

## 数据与隐私

- 单词、释义、分组、设置和学习记录保存在 Android 应用私有目录。
- 应用不提供账号系统，也不会把整份词库上传到项目服务器。
- 播放或缓存网络发音时，会把当前单词拼写发送给对应的公开音频服务。
- Android 卸载应用后，系统会删除应用私有目录中的本地数据。

---

# 开发者文档

## 当前技术状态

| 项目 | 当前值 |
|---|---|
| Flutter | GitHub Actions 使用 `3.44.8 stable` |
| Dart SDK 约束 | `^3.12.2` |
| Java | `17` |
| Gradle | `9.1.0` |
| 应用版本 | `0.22.10+10` |
| SQLite 结构版本 | `11` |
| Android applicationId | `com.example.my_english` |

`0.22.10+10` 中，加号前是用户看到的版本名，加号后是 Android 构建号。代码改动不会让版本号自动变化，发布前需要手动更新 `pubspec.yaml`。

## 技术架构

```text
Flutter 页面
├── HomePage：首页仪表盘、词库抽屉与数据管理
├── ListeningPage：随身听
├── DictationPage：普通默写与听音辨义
└── ReviewUnavailablePage：三个未开放复习模式的占位页
      │
      ├── Dart models：业务数据模型
      ├── Dart stores：状态持久化接口与 MethodChannel 封装
      └── Dart services：音频、文件和纯业务服务
                  │
                  └── Android Kotlin
                      ├── MainActivity：MethodChannel 路由与文件选择/保存
                      ├── WordsDatabase：SQLite 与复习数据
                      ├── WordAudioPlayer：MP3、网络音频、TTS 与媒体控制
                      └── AppSettingsStore：SharedPreferences 设置
```

主要目录：

| 目录 | 作用 |
|---|---|
| `my_english/lib/pages/` | 按页面划分的界面、组件和页面服务 |
| `my_english/lib/models/` | 单词、释义、分组、记录、会话和每日计划模型 |
| `my_english/lib/store/` | Dart Store 接口与 Android MethodChannel 调用 |
| `my_english/lib/services/` | 音频、缓存、文件等跨页面服务 |
| `my_english/android/app/src/main/kotlin/` | Android SQLite、设置、文件和音频实现 |
| `my_english/test/` | Dart 单元测试和 Flutter Widget 测试 |
| `my_english/android/app/src/test/` | Android JVM 单元测试 |
| `my_english/android/app/src/androidTest/` | Android 真机或模拟器仪器测试 |
| `my_english/tools/` | 版本信息同步等构建辅助脚本 |
| `.github/workflows/` | Android Release 自动构建与发布流程 |

项目不再包含 `assets/data/words.json`，启动流程也不再执行默认词库初始化。首次启动直接进入空词库，数据只能由用户添加或主动导入。

## 本地数据结构

业务数据保存在 `my_english.db`，位于 Android 应用私有数据库目录。主要表：

| 表 | 用途 |
|---|---|
| `words` | 单词主体、难度、音标、词形和时间字段 |
| `meanings` | 词性与释义数组 |
| `groups` | 自定义分组 |
| `group_positions` | 分组在界面中的顺序 |
| `group_members` | 单词与分组的多对多关系 |
| `record` | 每次默写结果、模块、错误、提示与难度变化 |
| `dictation_option_cache` | 每道默写题的候选项和正确答案位置 |
| `learning_sessions` | 随身听、普通默写和四种复习模块的进度 |
| `daily_review_plans` | 当天四种复习模块共用的单词主键顺序 |

数据库版本 11 为 `daily_review_plans` 增加 `selection_version`。选词规则变化时递增 Dart 侧 `DailyReviewSelector.selectionVersion`，旧计划会保留当天目标数量并按新规则重建一次。

## 导入与导出格式

导入支持两种 JSON 顶层结构：

```json
[
  {
    "spelling": "example",
    "meanings": [
      {
        "index": 0,
        "pos": "n.",
        "definitions": ["例子"]
      }
    ]
  }
]
```

或者使用完整备份结构：

```json
{
  "words": [],
  "groups": [],
  "members": []
}
```

Android 导入层通过 SQLite `PRAGMA table_info` 读取真实字段作为白名单：存在的字段按数据库类型写入，未知字段忽略。导入是整库替换，不是追加；完整备份可以恢复分组和成员关系，但不包含 `record`、候选缓存和学习会话。

## 每日复习实现

`DailyReviewSelector` 只接收完整词库和目标数量，不依赖首页当前搜索、分组或排序按钮。固定比较链为：

```text
reviewedAt 是否为空
→ meaningCount ASC
→ meaningCharacterCount ASC
→ difficulty DESC
→ reviewedAt ?? updatedAt ?? createdAt ASC
→ spelling ASC（忽略大小写）
→ id ASC
```

当天首次打开任意复习模块时生成 `daily_review_plans`；此后四个模块复用相同 `word_ids` 顺序。每个模式通过独立的 `LearningSessionType` 保存进度，通过独立的 `record.module` 统计完成量。

## 音频实现

Flutter 通过 `my_english/word_audio` MethodChannel 调用 `WordAudioPlayer`。Android 侧负责：

- 读取和写入 App 私有目录中的 MP3 缓存。
- 依次尝试不背单词与有道网络音源。
- 检查网络状态，并为连续失败保存 5 分钟冷却时间。
- 使用 Android `TextToSpeech` 作为离线兜底。
- 通过 `MediaSessionCompat` 和 MediaStyle 通知提供系统媒体控制。

网络音频来源：

- 不背单词美式：`https://audio.beingfine.cn/speeches/US/US-speech/{spelling}.mp3`
- 不背单词英式：`https://audio.beingfine.cn/speeches/UK/UK-speech/{spelling}.mp3`
- 有道美式：`https://dict.youdao.com/dictvoice?audio={spelling}&type=2`
- 有道英式：`https://dict.youdao.com/dictvoice?audio={spelling}&type=1`

## 开发环境

需要安装：

- Flutter SDK，并满足 `pubspec.yaml` 中的 Dart SDK 约束。
- Android SDK。
- JDK 17。

获取依赖：

```bash
cd my_english
flutter pub get
```

项目使用仓库内的 `third_party/tabler_icons_plus`，界面图标不依赖在线安装该包。

## 本地运行与构建

运行 Debug：

```bash
cd my_english
flutter run
```

构建 Release APK：

```bash
cd my_english
flutter build apk --release
```

当前 Debug 和 Release 都使用正式签名，因此本地构建前需要创建 `my_english/android/key.properties`：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=你的别名
storeFile=/绝对路径/your-upload-keystore.jks
```

`key.properties` 和 keystore 都包含敏感信息，不得提交到 Git。Release APK 默认生成在：

```text
my_english/build/app/outputs/flutter-apk/app-release.apk
```

## 版本号与发布

`my_english/pubspec.yaml` 是应用版本号的唯一手工数据源：

```yaml
version: 0.22.10+10
```

修改后同步应用内展示信息：

```bash
cd my_english
dart run tools/sync_app_info.dart
```

GitHub Actions 支持两种标签触发：

- `vX.Y.Z`：正式版本标签，必须与 `pubspec.yaml` 加号前的版本完全一致。
- `latest`：兼容标签，仍使用 `pubspec.yaml` 中的实际版本命名 APK。

工作流会校验版本、恢复 GitHub Secrets 中的正式签名、构建 APK，并发布到对应 GitHub Release。所需 Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## 检查与测试

```bash
cd my_english

# Dart 与 Flutter 静态检查
flutter analyze

# Dart 单元测试和 Flutter Widget 测试
flutter test

# Android JVM 单元测试
cd android
./gradlew :app:testDebugUnitTest

# Android Kotlin 编译检查
./gradlew :app:compileDebugKotlin

# 连接真机或模拟器后运行 Android 仪器测试
./gradlew :app:connectedDebugAndroidTest
```

## 当前限制

- 仅保留 Android 工程，尚未支持 iOS。
- 词义连连、拼写巩固和看义选词目前只有入口与占位页。
- TTS 的声音质量和离线能力由手机安装的语音引擎决定。
- 数据导出暂不包含复习历史、候选缓存、学习会话和设置。
- “清空数据”当前不删除 `record` 历史记录。

## 代码约定

- 页面采用目录式组织，页面专属组件与服务放在对应页面目录。
- 所有界面图标统一使用 Tabler 图标。
- Dart 和 Kotlin 保留中文注释，解释关键数据流、参数和返回值。
- SQLite 的批量导入、清空、答题记录和难度更新使用事务保证一致性。
- 网络音频先写临时文件，校验 MP3 文件头后再替换正式缓存。
