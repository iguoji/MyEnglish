# my_english

A new Flutter project.

## 数据结构

### word

> 单词模型，音频按拼写从远程或本地获取

|字段|类型|说明|
|---|---|---|
|id|number|自增主键|
|spelling|string|区分大小写|
|meanings|Meaning[]|含义对象数组
|difficulty|number|最小0，最大无限制|
|phonetic_uk|string|英式音标，可空|
|phonetic_us|string|美式音标，可空|
|plural|string|复数，可空|
|third_person_singular|string|第三人称单数，可空|
|gerund|string|现在分词，可空|
|past_tense|string|过去式，可空|
|past_participle|string|过去分词，可空|
|comparative|string|比较级，可空|
|superlative|string|最高级，可空|
|reviewed_at|number|复习时间，可统计复习量|
|created_at|number|可按时间统计词汇量
|updated_at|number|仅创建及编辑时更新|
|deleted_at|number|非空可用|

### meaning

> 含义模型

|字段|类型|说明|
|---|---|---|
|id|number|自增主键|
|word_id|number|逻辑外键|
|index|number|于单词中的排列顺序，越大越前|
|pos|string|词性|
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
|difficulty_before|number|之前难度|
|difficulty_after|number|之后难度|
|created_at|number|
|created_date|string|插入日期YYYY-MM-DD|

## 网络音频

- 不背单词

    美式: https://audio.beingfine.cn/speeches/US/US-speech/{spelling}.mp3

    英式: https://audio.beingfine.cn/speeches/UK/UK-speech/{spelling}.mp3

- 有道

    美式：https://dict.youdao.com/dictvoice?audio=\(spelling)&type=2

    英式：https://dict.youdao.com/dictvoice?audio=\(spelling)&type=1

