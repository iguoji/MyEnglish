# my_english

A new Flutter project.

## 数据结构

### word

> 无需音标，音频按拼写从远程或本地获取

|字段|类型|说明|
|---|---|---|
|id|number|自增主键|
|spelling|string|区分大小写|
|meanings|含义对象[]|
|difficulty|number|最小0，最大无限制|
|reviewed_at|number|复习时间，可统计复习量|
|created_at|number|可按时间统计词汇量
|updated_at|number|仅创建及编辑时更新|
|deleted_at|number|非空可用|

### meaning

|字段|类型|说明|
|---|---|---|
|id|number|自增主键|
|word_id|number|逻辑外键|
|index|number|于单词中的排列顺序，越大越前|
|pos|string|词性，可重复|
|definitions|string[]|释义列表|
|created_at|number|
|updated_at|number|
|deleted_at|number|非空可用|

### group

|字段|类型|说明|
|---|---|---|
|id|number|自增主键
|name|string|分组名，区分大小写
|created_at|number|
|updated_at|number|
|deleted_at|number|非空可用|

### groupMember

|字段|类型|说明|
|---|---|---|
|group_id|number|逻辑外键，同下联合唯一
|word_id|number|逻辑外键，同上联合唯一

### record

> 只有单词默写模块才有记录产生，才会影响单词的难度

|字段|类型|说明|
|---|---|---|
|id|number|自增主键
|module|string|暂时只有单词默写|
|word_id|number|单词逻辑外键
|is_correct|boolean|全对则true|
|wrong_count|number|本次具体错误次数|
|hint_count|number|本次使用提示次数|
|difficulty_before|number|之前错误次数|
|difficulty_after|number|之后错误次数|
|created_at|number|

## 单词数据来源

`words.json` 已复制到 Flutter 工程内的 `assets/data/words.json`，并通过 `pubspec.yaml`
登记整个 `assets/data/` 目录。因此 Debug、Profile、Release 及真机安装包都会包含该文件，
真机预览不依赖电脑外层的原始 JSON。

App 第一次访问 WordStore 时只选择一次数据源：

1. 如果安装包中存在 `assets/data/words.json`，只从 JSON 读取 Word 和 Meaning。
2. JSON 数据只放在当前 App 进程内存中，不导入 SQLite，也不改写 JSON 文件。
3. JSON 模式下的新增、编辑和删除只改变内存；彻底关闭 App 后这些临时修改会消失。
4. 只有安装包中确实没有该 JSON 时，才从 Android 私有 SQLite 读取；该模式下后续 CRUD
   才会持久化。
5. JSON 已经读到但内容损坏时会直接报错，不会退回 SQLite 掩盖文件问题；首页同时显示
   可选择复制的具体异常。

`spelling` 不是唯一字段。JSON 或 SQLite 中出现相同拼写时，每条 Word 都按自己的 id、
Meaning、difficulty 和时间字段独立保留；新增和编辑同样允许重复 spelling。Meaning 在每个
Word 内按 index 从大到小排列。已有版本 1 SQLite 会在启动时自动迁移到版本 2，并保留原有
Word、Meaning 及主外键关系。

## 公共代码目录

Word 与 Meaning 位于 `lib/models/`，WordStore 位于 `lib/store/word.dart`。它们不属于
首页私有代码，未来的循环播放页、默写页和编辑页都可以直接导入并调用同一个 Store。
`lib/pages/home/` 只保留 `home.dart` 及其私有 widgets，目录职责与小程序 page 目录一致。
公共主题与日期代码分别位于 `lib/common/theme.dart`、`lib/common/date.dart`。

首页仍然使用 `ListView.builder` 惰性创建屏幕附近的列表项。点击一个单词时只展开该项，
并在单词下方按固定词性列宽逐行展示 Meaning。

## 网络音频

首页点击单词文字会按当前口音播放，点击同一行其他区域仍负责展开 Meaning。播放期间同一
单词的重复点击不会重新开始，并在单词左侧显示动态喇叭。音频首先读取 Android App 私有
缓存 `cacheDir/word_audio/american|british`，美式和英式互不覆盖；缓存不存在时依次尝试
不背单词、有道，两个来源都失败才在首页显示错误。缓存只接受有效 MP3 文件头，网络中断
留下的临时文件不会成为正式缓存。

- 不背单词

    美式: https://audio.beingfine.cn/speeches/US/US-speech/{spelling}.mp3

    英式: https://audio.beingfine.cn/speeches/UK/UK-speech/{spelling}.mp3

- 有道

    美式：https://dict.youdao.com/dictvoice?audio=\(spelling)&type=2

    英式：https://dict.youdao.com/dictvoice?audio=\(spelling)&type=1

## 首页设置与排序

应用已完整启用 Material 3，并分别定义 Light 与 Dark 颜色。启动时会在 `runApp` 之前从
Android `SharedPreferences` 读取发音口音和主题，默认分别为美式与 Light，设置成功后会
立即应用并在下次启动继续使用。

搜索栏下方从左到右提供默认、字母、难度、日期排序。字母初始升序，难度和日期初始降序，
再次点击当前字段会切换方向；空难度和空日期在两个方向中都固定排在末尾。列表日期与日期
排序统一优先使用 `updatedAt`，为空时才回退 `createdAt`。列表右侧滚动条始终显示并允许
直接拖动，以便快速移动到大量单词的任意位置。
