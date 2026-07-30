# 句子生成顺序与安全失败规则（任务23 + 任务25）

> 本文档是生成器实现的**规范**：任何实现（Python 原型、Dart 正式版）都必须
> 按此顺序执行，且在任何一步失败时按«安全失败»规则拒绝，绝不输出病句。

## 一、数据来源与优先级

| 层 | 来源 | 职责 |
|---|---|---|
| 词条层 | `patch/*.json`（系统基线）+ 用户词库 | 拼写、词性、变形字段（plural/past_tense/…） |
| 知识层 | `patch/sentence/annotations/` | number_behavior / stative / gradability / person 策略 |
| 用法层 | `patch/sentence/lexicon/` | 名词用法、动词框架、形容词/副词用法、a-an 特例 |
| 范式层 | `patch/sentence/paradigms/` | 代词、be/do/have/情态、限定词规则（封闭类） |
| 契约层 | `patch/sentence/formulas/` | 公式槽位契约 + 选项兼容矩阵 |

词条身份规则：存储层用 `source+id`，造句层用 `spelling+pos` 联接知识；
**用户词与系统词同拼写同词性时，展示释义取用户条目，语法知识取知识层**。

## 二、生成顺序（九步流水线）

每一步的输入是上一步的产物；任何一步返回拒绝码即整体失败（fail-fast）。

1. **选项合法化**（compatibility_matrix.json）
   - 用户/系统选定的 (pattern, tense, voice, polarity, question) 组合先过
     `kind=forbid` 规则；命中即拒绝，返回 rule_id 作为拒绝码。
2. **公式匹配**（core_formulas.json）
   - 找到 pattern 对应的 formula；核对 tense ∈ allowed_tenses、
     voice/polarity/question 开关。失败码：`tense_not_supported` 等。
3. **动词候选**（verb_frames.json）
   - 按 formula 要求的框架筛动词（如 SVOO 只留 dative 动词）。
   - 应用 forbid 规则的动词维度：stative × 进行时、allows_passive × 被动。
   - 候选为空 → `no_candidate_verb`。
4. **主语构造**（pronouns.json + noun_usage.json）
   - 满足动词 `subject_restriction`（person/animate/expletive_it）。
   - 集体名词记下 `verb_agreement` 供第 7 步用。
5. **宾语/表语/补语构造**（noun_usage.json + adjective_usage.json）
   - 满足 `object_restriction`（edible/drinkable/…）与补语类型。
   - 名词短语构造顺序：determiner → (adjective) → noun：
     a) 由 number_behavior 决定可否复数、可否计数、是否 a pair of；
     b) 由 determiner_rules.json 决定限定词与可数性搭配；
     c) 不定冠词 a/an 用 article_phonetics.json 特例表 → prefix 规则 → 默认元音字母规则；
     d) 形容词须 attributive=yes 才能进定语位。
6. **副词插入**（adverb_usage.json）
   - 只使用 positions 里合法的位置；默认取 default_position。
   - degree 副词只贴 adj/adv；带否定义副词与 not 互斥。
7. **一致性与变位**（auxiliaries.json + 词条变形字段）
   - 主谓一致：主语人称/数 + 第 4 步记录的 verb_agreement 决定动词形。
   - 需要的变形（third_person_singular/past_tense/gerund/past_participle）
     从词条读取；**字段缺失即拒绝**（不做拼写规则现推），码 `missing_form`。
   - 多合法形（learned/learnt）取数组首项；随机模式可任取。
8. **否定/疑问改写**（auxiliaries.json）
   - be/情态：直接加 not / 倒装。
   - 实义动词一般现在/过去：do-support（do/does/did + 原形）。
9. **表层修饰**
   - 首字母大写、缩写选项（isn't/don't）、标点（陈述句 . / 疑问句 ?）。
   - front 位评注副词补逗号。

## 三、安全失败规则（任务25）

1. **缺数据 = 拒绝，不是猜测**。任何一步需要的��段缺失（如动词无
   past_participle、名词不在 noun_usage 且无法从 number_behavior 推导），
   立即返回机器可读拒绝码，绝不用拼写规则临时补形。
2. **unknown = 排除**。任何属性值为 `unknown` 的词条不进入该维度的候选池
   （unknown 可数性不当可数用、unknown 框架不参与造句）。
3. **白名单制**。合法性来自"契约允许 + 词条属性满足"双重确认；
   兼容矩阵未禁止 ≠ 合法。sentence.html 的组合维度仅是 UI 参考。
4. **拒绝码可诊断**。所有拒绝返回 `formula.rejection_reasons` 或
   `matrix.rule_id` 中登记的代码，UI 可映射为人类可读提示；
   禁止静默回退到另一个句型。
5. **系统独立**。整条流水线在 words.json 缺失、用户库为空时必须可运行
   （所有校验器与后续黄金句测试均不加载 words.json）。

## 四、第一版明确不做（延期项）

- SVOC 的被动改写（He is made to cry）
- There be 进行时/并列主语一致
- 祈使句被动（Be seated）
- 情态动词组合（can/must/should…）——范式已备，公式后续版本接入
- 从句类（宾语从句/定语从句/状语从句）与虚拟语气
- 比较级句型（这批 lexicon 已存好数据，公式后续版本接入）

延期理由：以上均需额外的改写规则或跨槽位一致性推理，先保证
四大基础句型 + There be + 祈使句在六时态×肯否疑下 100% 无病句。
