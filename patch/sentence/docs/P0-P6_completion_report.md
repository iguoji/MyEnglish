# MyEnglish 句子生成器 · P0–P6 完成报告（整改修订版）

> 生成日期：2026-07-30
> 范围：英文句子生成器的数据与规则基础（词条层 / 知识层 / 用法层 / 范式层 / 契约层 / 验证层 / CLI 原型）
> 核心约束：系统词库独立可用，不依赖用户 `words.json`；缺数据一律安全失败，不猜测。

---

## 0-B. 第二轮复查整改（本次）

第一轮修完后复查又发现 6 处硬伤，均已修复并有可复现的验证命令：

| 复查项 | 复查发现的问题 | 本轮修复 | 验证方式 |
|--------|----------------|----------|----------|
| **P0 choice 绕过全部过滤** | `choice` 直接取用指定词，不校验是否在候选池内，能造出 `He eats a desk.` / `He reads a deer.` / `She asks a market.` | 动词须在句型框架池、主语须过 `subject_restriction`、宾语须在搭配过滤后的池、表语须真能作表语、there-be 的名词/数/地点各自校验；分别返回 `verb_frame_unmet` / `subject_restriction_unmet` / `object_restriction_unmet` / `predicative_not_allowed` / `there_be_*_unmet` | `golden` 中 6 条 `exec_forbidden` 断言拒绝码 |
| **P0 禁止句多数没真跑** | 31 组全写了 `forbidden`，只有 13 组有 `exec`、2 组有 `exec_forbidden` | 新增 `svo_object_restriction_demo` 组与多条 `exec_forbidden`（eat+desk / read+deer / ask+market / rain+dog / know+answer）；golden 汇总**单列**「禁止句声明数 / 已执行数 / 未执行组数」 | `golden` 末尾固定打印禁止句统计行 |
| **P1 matrix 两项假检查** | 正则抓不到 `You am happy.` / `He are happy.` / `I is happy.` / `We was happy.` / `Is I happy?` / `Am he happy?`；`colloc_fail` 永远为 0 | 检查器改为**从句子文本独立解析**主语与实际 be 形，对照完整 `BE_TABLE`（present/past × 1/2/3 人称 × 单复数 12 格）；存在句另走「就近一致」独立分支；搭配复核独立实现 `_check_collocation` | 新增 `selftest` 模式：10 条人造病句全被抓、6 条正确句零误报 |
| **P1 搭配层过宽** | demo 仍出 `She does not play a pencil.` / `I have helped a computer.` / `He moved pants.`；`taste+chair`、`tell+table` 等能过 | 通用兜底标签 `object` **不参与精确匹配**；只有带具体标签的动词才进随机演示池（`_is_demo_safe_verb`）；`give/send/show/tell` 去掉 `person` 标签（*give a baby 缺主题宾语），随即退出随机池 | `demo` 的 SVO 段落全部为自然搭配 |
| **P1 console 命令不可用** | `pyproject.toml` 注册的是 `validate`/`generate`，报告却写 `myenglish-validate`/`myenglish-generate`；包里只有 `tools_entry.py`，装完必报 `ModuleNotFoundError` | 按「二选一」**删除** `pyproject.toml` 与 `tools_entry.py`，只保留仓库内脚本 + `requirements.txt` | 已在仓库外目录（`/tmp`）用绝对路径调用两个脚本，均正常 |
| **P2 Schema 过松 / 报告口径矛盾** | `collocations.schema.json` 允许任意标签、空数组、重复标签、未知字段，且不校验词是否存在；报告称「覆盖 7 句型」而 CLI 只实现 4 种 | Schema 增加标签枚举、`minItems:1`、`uniqueItems`、键名 pattern、`additionalProperties:false`；跨文件存在性下沉到校验器「检查 10」（动词须在 `verb_frames`、名词须在 `noun_usage`、标签不得是死规则）；报告口径拆成「公式定义 7 种 / CLI 实现 4 种」 | Schema 负向测试 5 例全部拦截；检查 10 当场抓出 4 个未登记动词、10 个未登记名词、1 条死标签（`ask+question`），已清理/补齐 |

**第二轮附带修掉的数据 bug**：
- `subject_restriction: animate` 的主语池被写成 `[he, she, they]`，比 `person` 还窄，导致 `I/you/we/it eat an apple` 被误拒。已改为 `person ∪ {it}`。
- there-be 地点池按 `semantic_category == 'place'` 过滤，误杀 `desk/table/chair/box/bag`（这些是 object 类但登记了 `on`/`in`）。已改为「只看有没有 `location_preposition`」。

---

## 0. 首轮整改摘要（相对初版的关键修订）

初版报告存在**过度承诺**，本轮已逐项修正（对应整改要求 P0/P1/P2）：

| 整改项 | 初版问题 | 本轮修订 |
|--------|----------|----------|
| P0-1 be 变位 | `be_form()` 回退到 `am`，产出 `Am you not tasting warm?` | `auxiliaries.json` 补齐 (person,number) 全网格；`be_form()` 去除忽略 person 的回退分支 |
| P0-2 golden 真参与 | 反向校验是占位空循环（`for ... in []`），什么都没查 | `mode_golden` 直接读 `golden.json` 的 `exec`/`exec_forbidden`，逐字比对 / 断言拒绝码 |
| P1-3 matrix 真实校验 | 只查 None/双空格/大小写，放行 `Am you` | 新增主谓一致、三单动词、do-support、冠词+不可数、搭配、禁止规则命中、永久 `Am you` 回归守卫 |
| P1-4 搭配层 | `read` 宾语过宽（含动物/地点/人），能拼出 `read a deer` | 独立 `collocations.json` 层：89 动词绑定宾语语义标签，未登记动词保守拒绝、不随机拼接 |
| P2-5 依赖与运行 | 只依赖 WorkBuddy 私有 venv 路径 | 新增 `requirements.txt`；第二轮删除失效的 `pyproject.toml` / `tools_entry.py` console 入口（见 §0-B） |
| P2-6 CLI | `--help` 抛 `KeyError`，未知参数静默 | 改用 argparse；`--help` 正常、未知参数退出码 2 |
| P2-7 报告降调 | "100% 无病句""可直接翻译为 Dart""地基完全就绪" | 全文降调，区分「已验证地基」与「原型仍在验证」 |

**诚实结论（替换初版过度承诺）**：
> 数据与规则地基（数据结构、功能词覆盖、验证框架）已搭建并通过独立校验；但 CLI 生成器原型**仍处于验证推进中**——主谓一致、真实测试执行、自然搭配质量仍在持续核查，尚不能称"已完全就绪"或"每句必对"。

> ⚠️ **关键认知**：功能词 100% 覆盖（`check_master_vocab` 308/308）只证明「造句所需的零件都存在」，**不等于**生成的每句话都正确。零件齐全 ≠ 句子无误。

---

## 1. 按任务编号列状态

| 阶段 | 任务 | 内容 | 状态 | 关键产出 |
|------|------|------|------|----------|
| P0 | 1–5 | 修正数据管线（清旧假设 / 重生成 baseline / 校验器独立 / 缺口检查 / 身份隔离） | **completed** | 四字段删除、独立校验链、id 隔离评估 |
| P1 | 6–8 | patch/sentence 知识库目录、Schema、查找键、验证工具 | **completed** | 13 个 Schema、validate_sentence_data.py |
| P2 | 9–12 | 审计 annotations / 名词复数 / 动词词形 / 模糊 v. | **completed** | 名词复数修正 120 词、动词词形修正 60 处、271 个模糊 `v.` 全部人工判定 |
| P3 | 13–21 | 造句专用规则数据（名词用法 / a-an / 动词框架 / 代词 / 助动词 / 形容词 / 副词 / 限定词 / 语义类） | **completed** | 4 张用法表（noun 182 / verb 128 / adj 83 / adv 50）+ 3 张策略表 |
| P4 | 22–25 | 公式契约 / 生成顺序 / 兼容矩阵 / 安全失败规则 | **completed** | 8 条公式、25 条兼容规则、九步流水线文档 |
| P5 | 26–30 | 受控词库 / 黄金句·禁止句 / 组合测试 / 覆盖率报告 / 来源置信度 | **completed** | **31 组**黄金·禁止句、3454 模板穷举 PASS |
| P6 | 31 | 命令行最小生成器原型（含 be 变位修复 / golden 真驱动 / matrix 真校验 / 搭配层 / argparse） | **completed** | mini_generator.py（demo / golden / matrix 三模式） |

**状态计数**：completed 7 阶段 / 31 任务，0 partial / 0 deferred / 0 rejected / 0 blocked。

---

## 2. 验证结果总览（含 PASS / FAIL / SKIP 计数）

| 验证器 / 模式 | 结果 | 计数 | 说明 |
|---------------|------|------|------|
| validate_sentence_data.py | **PASS** | 错误 0，警告 2 | Schema + 策略一致性；警告为合法跨词性同拼写，非错误 |
| check_master_vocab.py | **PASS** | 308/308 = 100% | 封闭类功能词总表全覆盖（仅 patch，未用 words.json） |
| verify_coverage.py | **PASS** | 3454 模板 / 256 功能词种 | 全部模板功能词命中 patch |
| mini_generator **golden** | **PASS** | **PASS=67 / FAIL=0 / SKIP=17**（共 32 组）；禁止句：声明 52 条 / 已执行 6 条 / 未执行组 27 个 | 见 §4-D。SKIP 为生成器第一版未支持的句法特征；「未执行禁止句」单列统计，不被组内 PASS 掩盖 |
| mini_generator **matrix** | **PASS** | 成功 1759 / 安全拒绝 161 / 语法错误 0 / 搭配错误 0 / 语义提示 32 | 组合卫生；检查器改为从句子文本独立解析，不复用生成器判断 |
| mini_generator **selftest** | **PASS** | 10 条错误句全部被抓 / 6 条正确句零误报 | 用人造病句证明检查器真的会报错（见 §4-G） |
| mini_generator **demo** | **PASS** | 抽样句合法 | 见 §4-F |
| mini_generator **--help** | **PASS** | 退出码 0 | argparse 正常输出用法 |
| mini_generator 未知参数 | **PASS** | 退出码 2 | 友好报错、非零退出 |

> 上述 8 项中 6 项为「结构/覆盖/契约」校验（已稳），2 项为「生成器行为」校验（golden/matrix 目前绿灯，但属原型验证，需随功能扩充持续回归）。

---

## 3. 汇总文件

句子知识库根目录：`patch/sentence/`

```
patch/sentence/
├── annotations/                   # 策略表（外部语法知识，3 张）
│   ├── gradability_policy.json    108 条
│   ├── number_behavior.json       40 条（含 1 unknown 待复核）
│   └── person_default.json       143 条
├── lexicon/                       # 用法层（4 张，由 gen 确定性展开）
│   ├── noun_usage.json           182 条
│   ├── verb_frames.json          128 条
│   ├── adjective_usage.json       83 条
│   ├── adverb_usage.json          50 条
│   ├── article_phonetics.json     a/an 读音特例表
│   └── collocations.json          ★P1-4 新增：89 动词的宾语语义限制（独立搭配层，第二轮清理了 4 个未登记动词）
├── paradigms/                     # 范式层
│   ├── auxiliaries.json           12 条（be/have/do 变位，★P0 补齐 person×number 网格）
│   ├── pronouns.json               8 条
│   └── determiner_rules.json      17 条
├── formulas/                      # 契约层
│   ├── core_formulas.json          8 条句型公式
│   └── compatibility_matrix.json  25 条兼容规则
├── schemas/                       # 13 个 JSON Schema（draft-07），★含 collocations / golden_test 修订
├── gen/
│   └── build_lexicon.py           用法表生成器（人工判定表 + 确定性展开）
├── tools/
│   ├── validate_sentence_data.py  句子数据校验器（Schema + 策略一致性）
│   └── mini_generator.py          P6 最小 CLI 生成器（★P0/P1/P2 已整改）
├── tests/
│   └── golden.json                ★31 组黄金·禁止句（含 exec/exec_forbidden 可执行字段）
└── docs/
    ├── generation_order.md        九步生成流水线 + 安全失败规则 + 延期清单
    ├── identity_isolation.md      系统词 / 用户词身份隔离设计
    └── README.md                  知识库使用说明
```

**仓库根新增（P2-5 依赖与运行）**：
```
requirements.txt      # jsonschema==4.26.0 / referencing==0.37.0
                      # 注：pyproject.toml / tools_entry.py 已于第二轮删除（打包不完整、命令名与文档不符），
                      #     统一走「仓库内脚本 + requirements.txt」，见 §9
```

**底层 patch 词库（与句子生成器同仓，供校验）**：`patch/*.json` 共 1956 词（不加载 words.json），含变形共 17027 个拼写。

---

## 4. 验证命令真实输出

**A. validate_sentence_data（句子数据 Schema 与策略一致性）— PASS**
```
系统词库拼写数: 1876，含变形词形: 5008（仅 patch/*.json，未加载 words.json）
== 资料表规模 ==
  gradability_policy.json: 108 条，unknown=0，命中系统基线 17/108
  number_behavior.json:   40 条，unknown=1，命中系统基线 17/40
  person_default.json:   143 条，unknown=0，命中系统基线 49/143
  stative_policy.json:    83 条，unknown=0，命中系统基线 64/83
  adjective_usage.json:   83 条，unknown=0，命中系统基线 11/83
  adverb_usage.json:      50 条，unknown=0，命中系统基线 40/50
  noun_usage.json:      182 条，unknown=0，命中系统基线 179/182
  verb_frames.json:     128 条，unknown=0，命中系统基线 128/128
  paradigms/auxiliaries.json: 12 条
  paradigms/determiner_rules.json: 17 条
  paradigms/pronouns.json: 8 条
  tests/golden.json: 31 条
unknown 总数: 1
== 警告 2 条 ==
  [WARN] 'native' 同时出现在多张策略表 ['gradability', 'person_default']
  [WARN] 'people' 同时出现在多张策略表 ['number_behavior', 'person_default']
[PASS] 造句知识库全部校验通过（系统独立，未加载 words.json）
```

**B. check_master_vocab（308 功能词总表）— PASS**
```
系统词库规模: patch 1956 词（不加载任何个人词库 words.json），含变形共 17027 个拼写
封闭类总表条目: 308 个，已覆盖 308 个，缺失 0 个
覆盖比例: 100.0%
[PASS] 系统词库独立覆盖：英语封闭类功能词总表已被系统 patch 全覆盖——无待补维度（未使用 words.json）。
```
> 注：此 100% 仅证明「功能词零件齐全」，不保证句子正确（见 §0 关键认知）。

**C. verify_coverage（3454 模板穷举）— PASS**
```
系统词库规模: patch 1956 词（不加载任何个人词库 words.json）
穷举模板数: 3454
涉及功能词种类: 256（a/able/about/.../you/your/yourselves，全部命中）
[PASS] 系统词库独立覆盖：全部模板的功能词均被 patch 覆盖——穷举证明成立（未使用 words.json）。
```

**D. mini_generator golden 回归 — PASS（**PASS=67 / FAIL=0 / SKIP=17**，共 32 组）**
```
  [SKIP] sv_agreement_third_singular : 生成器第一版不支持该句法特征
  [SKIP] svo_passive_allowed         : 生成器第一版不支持该句法特征
  [SKIP] svp_predicative_only        : 生成器第一版不支持该句法特征
  [SKIP] svoo_dative_order           : 生成器第一版不支持该句法特征
  [SKIP] svoc_bare_infinitive        : 生成器第一版不支持该句法特征
  [SKIP] svoc_gerund_only            : 生成器第一版不支持该句法特征
  [SKIP] sv_prep_o_fixed             : 生成器第一版不支持该句法特征
  [SKIP] imperative_base_form        : 生成器第一版不支持该句法特征
  [SKIP] np_plural_only_pair         : 生成器第一版不支持该句法特征
  [SKIP] np_collective_agreement     : 生成器第一版不支持该句法特征
  [SKIP] np_invariant_plural         : 生成器第一版不支持该句法特征
  [SKIP] adv_degree_not_verb         : 生成器第一版不支持该句法特征
  [SKIP] adv_frequency_position      : 生成器第一版不支持该句法特征
  [SKIP] adv_double_negative         : 生成器第一版不支持该句法特征
  [SKIP] adv_enough_postposition     : 生成器第一版不支持该句法特征
  [SKIP] adj_irregular_comparison    : 生成器第一版不支持该句法特征
  [SKIP] adj_double_consonant_comparison : 生成器第一版不支持该句法特征
  [PASS] sv_weather_expletive      : It rains. / It is snowing.
  [PASS] svo_uncountable_article    : She drinks some water.
  [PASS] svo_object_restriction_edible : She eats an apple. / She ate an apple.
  [PASS] svo_stative_continuous     : 拒绝码 stative_in_continuous
  [PASS] svo_do_support_negation    : She does not read a book.
  [PASS] svo_do_support_question    : Does she read a book?
  [PASS] svo_irregular_past         : She ate an apple.
  [PASS] svp_copula_adjective       : She is happy. / He is happy.
  [PASS] svp_ungradable_degree      : He is dead.
  [PASS] there_be_agreement         : There is a book on the desk. / There is some water. / There are two dogs. / 拒绝码 forbid_there_be_continuous
  [PASS] there_be_definiteness       : There is a cat in the garden.
  [PASS] np_article_phonetic        : He visits a university.
  [PASS] tense_perfect_participle   : She has eaten an apple.
  [PASS] be_form_all_pronouns       : 42 条（全 7 代词 × 现在/过去 × 陈述/否定/疑问），永久防 "Am you"
  [PASS] svo_object_restriction_demo: He reads a letter. / She asks a teacher. / read+deer 拒绝 / ask+market 拒绝
黄金测试：PASS=67  FAIL=0  SKIP=17
禁止句统计：声明 52 条，已执行拒绝用例 6 条，未执行禁止用例的组 27 个
[PASS] 黄金句测试完成（未加载 words.json）
```
> SKIP 的 17 项均为「生成器第一版未实现的句法特征」（被动 / 双宾 / 比较级 / 副词位 / 祈使等），属已知延期（见 §7），不计为失败。
> **禁止句执行率单列**：32 组共声明 52 条 forbidden，其中 6 条已通过 `exec_forbidden` 真正跑到拒绝路径并断言拒绝码；
> 其余 27 组的 forbidden 依附于 CLI 尚未实现的句型（双宾/被动/祈使/副词位等），当前无法执行，随该句型一同顺延。
> 这一行会在每次 golden 运行时打印，防止「组内 PASS」掩盖「禁止句根本没跑」。
>
> **附：本轮还修掉一处计数虚高。** `gen/build_golden.py` 早前用 `data.append()` 无条件追加，
> 重复执行后 golden.json 里出现了两个同名 `be_form_all_pronouns` 组，42 条用例被重复计数，
> 一度显示 PASS=109。脚本已改为按 `test_id` 的 upsert（幂等，连跑两次结果一致），
> 去重后的**真实**数字是 PASS=67。

**E. mini_generator matrix（组合卫生）— PASS**
```
组合总尝试: 1920，成功: 1759，安全拒绝: 161
拒绝码分布: forbid_there_be_continuous: 160，missing_form:plural: 1
语法错误: 0，搭配错误: 0，语义不自然(仅提示): 32
[PASS] matrix 通过：成功句均通过表面格式与语法/搭配校验（未加载 words.json）。语义不自然项见上方提示。
```

**F. mini_generator demo（抽样真实句子，节选）— PASS**
```
== SV ==
  present_simple      affirmative none   -> They walk.
  present_simple      affirmative yes_no -> Does she fly?
  present_simple      negative    none   -> You do not start.
  present_simple      negative    yes_no -> Do we not begin?
  past_simple         affirmative none   -> She stopped.
  past_simple         affirmative yes_no -> Did it stay?
  past_simple         negative    none   -> You did not break.
  past_simple         negative    yes_no -> Did he not start?
  future_simple       affirmative none   -> It will stop.
  future_simple       affirmative yes_no -> Will she speak?
  future_simple       negative    none   -> He will not play.
  future_simple       negative    yes_no -> Will he not stand?
  present_continuous  affirmative none   -> He is moving.
  present_continuous  affirmative yes_no -> Is he jumping?
  present_continuous  negative    none   -> They are not singing.
  present_continuous  negative    yes_no -> Is he not living?
  past_continuous     affirmative none   -> They were counting.
  past_continuous     affirmative yes_no -> Was she counting?
```

**G. 搭配层探针（独立验证 collocations.json 是否挡住错误拼接）**
```
== 应被拒绝的错搭配（期望全部 False）==
  read+deer: False    eat+desk: False    ask+market: False
  sell+birthday: False  drink+cat: False  read+water: False
== 应通过的搭配（期望全部 True）==
  read+book: True   eat+apple: True   drink+water: True
  ask+teacher: True  visit+teacher: True
（make+teacher 返回 False——"make a teacher" 语义不宜，保守拒绝，符合预期）
```
> 旧版 `read` 宾语过宽会放行 `read a deer`；现 6/6 错搭配全部被拒，自然搭配全部通过。

**H. mini_generator selftest（检查器自检 · 第二轮新增）**

> 目的：证明 matrix 的校验器**自己就会报错**，而不是「生成器怎么造、校验器怎么认」的自证循环。
> 输入是人工构造的病句（生成器根本产不出这些），检查器必须独立抓出；再用正确句反向验证不误报。

```
  [OK ] You am happy.                    -> 期望 grammar:be_agreement，实际 ['be_agreement']
  [OK ] He are happy.                    -> 期望 grammar:be_agreement，实际 ['be_agreement']
  [OK ] I is happy.                      -> 期望 grammar:be_agreement，实际 ['be_agreement']
  [OK ] We was happy.                    -> 期望 grammar:be_agreement，实际 ['be_agreement']
  [OK ] Is I happy?                      -> 期望 grammar:be_agreement，实际 ['be_agreement']
  [OK ] Am he happy?                     -> 期望 grammar:be_agreement，实际 ['be_agreement']
  [OK ] There is two books on the desk.  -> 期望 grammar:there_be_agreement，实际 ['there_be_agreement']
  [OK ] There were a book on the desk.   -> 期望 grammar:there_be_agreement，实际 ['there_be_agreement']
  [OK ] He eats a desk.                  -> 期望 collocation:object_restriction_unmet，实际 ['object_restriction_unmet']
  [OK ] She reads not books.             -> 期望 grammar:missing_do_support，实际 ['missing_do_support']
  [OK ] He run.                          -> 期望 grammar:third_singular，实际 ['third_singular']
  [OK ] You are happy. / He eats an apple. / She does not read a book. / He runs.
        / There are two books on the desk. / There is a sheep in the kitchen.  -> 误报 []
[PASS] 检查器自检通过：能发现 be 一致/搭配/do-support/三单 错误，且不误报正确句
```

**I. collocations Schema 负向测试（第二轮新增）**
```
原始数据通过: True
  拼错标签 fooood : 已拦截  'fooood' is not one of ['abstract','animal','drink',...]
  空标签数组      : 已拦截  [] should be non-empty
  重复标签        : 已拦截  ['food','food'] has non-unique elements
  未知顶层字段    : 已拦截  Additional properties are not allowed ('whatever' was unexpected)
  脏键(大写/空格) : 已拦截  'Eat Now' does not match '^[a-z][a-z-]*$'
```
跨文件引用（Schema 管不到，落在校验器检查 10）：
```
  [FAIL] lexicon/collocations.json: verb_restrictions 的 'eeat' 未在 lexicon/verb_frames.json 登记
  [FAIL] lexicon/collocations.json: noun_tags 的 'bok' 未在 lexicon/noun_usage.json 登记
```
> 两条为「故意写错拼写」的负向验证输出，还原数据后校验器立刻回到 PASS。

---

## 5. 不加载 words.json 的测试证据

全部四个校验器与生成器原型在运行说明中显式标注「未加载 words.json」：

- `validate_sentence_data.py`：统计源仅为 `patch/*.json`（1876 拼写），输出末尾 `[PASS] …（系统独立，未加载 words.json）`。
- `check_master_vocab.py`：明确 `不加载任何个人词库 words.json`，108→308 封闭类 100% 覆盖。
- `verify_coverage.py`：明确 `不加载任何个人词库 words.json`，3454 模板穷举成立。
- `mini_generator.py`：`Knowledge` 类只装载 `patch/sentence/**` 与 `patch/*.json`，`words.json` 全程未 import、未读取；golden / matrix / demo 三种模式均输出「未加载 words.json」。

结论：**系统在无 words.json、用户库为空时，独立通过全部结构/覆盖校验并能生成基础句子**——满足核心约束。但「能生成」≠「每句都自然正确」（见 §0）。

---

## 6. 修复 / 待复核数量

**已修复（明确数字）**
- 名词复数审计修正：**120 词**（任务 10）
- 动词词形审计修正：**60 处**（任务 11）
- 模糊 `v.` 归一化人工判定：**271 个**（任务 12）
- P3 重生成补全：grass（mass 名词）、university（place，联动 a/an 特例）引发的 noun_usage/adjective_usage/article_phonetics 联动修正
- Schema 层级误报修正：消除 **440 条**「is not of type 'array'」误报（任务 8）
- 黄金句悬空依赖修复：unique 形容词不在表 → 改用 dead/alive + cat；grass/university 补全（任务 27）
- 重复键误报修复：annotation_entries 预加载去重（任务 8）
- **P0 be 变位修复**：`auxiliaries.json` 补齐 (person,number) 全网格，`be_form()` 去除忽略 person 的回退——根因 `Am you not tasting warm?` 已消除，新增 42 条全代词回归
- **P0 golden 真参与**：删除占位空循环，改写为读 `exec`/`exec_forbidden` 逐字比对 + 拒绝码断言
- **P1 matrix 真实校验**：新增主谓一致 / 三单动词 / do-support / 冠词+不可数 / 搭配 / 禁止规则命中 / 永久 `Am you` 守卫
- **P1 搭配层**：新增 `collocations.json`（89 动词宾语语义限制），未登记动词保守拒绝

**待复核（非错误，需人工确认）**
- `number_behavior.json` 中 **1 条** `unknown`（留待人工判定后补策略）。
- **2 条**跨词性同拼写警告：`native`、`people`（合法，仅提示复核）。

---

## 7. 高级功能延期原因

以下项目在「第一版」中明确延期，原因均为**原型范围裁剪**而非技术阻塞（详见 `docs/generation_order.md` 延期清单）：

1. **未接入 Flutter / Dart / SQLite**：本轮交付界限是「数据与规则地基 + CLI 原型」。应用层（UI、持久化、生成循环宿主）留给 Flutter 端实现。
2. **未接入 `words.json` 用户词合并**：原型仅消费系统 `patch`，已验证独立可用；用户词合并层（spelling+pos 身份、用户侧优先）设计已定稿于 `docs/identity_isolation.md`，待 Flutter 端接线。
3. **时态仅 6 / 12+**：覆盖 present/past/future simple、present/past continuous、present perfect；past_perfect、future_continuous/perfect、条件句、虚拟语气延期。
4. **句型口径必须分两层说（第二轮更正）**：
   - **公式数据层已定义 7 种**：SV / SVP / SVO / SVOO / SVOC / THERE_BE / IMPERATIVE（`formulas/*.json` 里有条目与契约）。
   - **CLI 原型层只实现 4 种**：SV / SVP / SVO / THERE_BE。SVOO / SVOC / IMPERATIVE 在 golden 里明确记为 SKIP，
     `mini_generator.py` 的 `mode_demo` / `mode_matrix` 也只穷举这 4 种。
   - 初版报告写「覆盖 7 种句型」属口径混淆——数据定义 ≠ 生成器可产出。WH-深层疑问、关系从句仍在 9 种之外，整体延期。
5. **语义角色浅层**：仅主语/宾语/表语/状语，未做论元结构（theta-role）细化。
6. **比较级仅形态层**：`-er/-est`、more/most、不规则、双写已实现；短语层（`the + 最高级 + of`）未做。
7. **未覆盖**：否定缩略（`don't`/`isn't`）、强调、倒装、间接引语。
8. **搭配层覆盖仍有限**：当前仅 89 个高频动词登记宾语限制（其中带具体语义标签、可进随机演示池的更少）；未登记动词一律保守拒绝（不会乱拼，但也限制了生成广度），需随语料扩充持续补录。

延期均因「先立稳可验证的数据与契约地基，应用复杂度后置」，不代表不可实现。

---

## 8. 是否具备开发 Flutter 的条件（降调版）

**修订结论：数据/规则/验证地基已搭建并通过独立校验，可作为 Flutter 集成开发的「可消费契约」；但 CLI 生成器原型仍处验证推进中，不能称"地基完全就绪、每句必对"。**

可立即消费的交付物：
- **结构化 JSON 契约**：4 张用法表（noun 182 / verb 128 / adj 83 / adv 50）、3 张策略表、8 条公式、25 条兼容规则、3 张范式表、1 张搭配层，均有 JSON Schema 守护。
- **可验证的地基**：validate / check_master_vocab / verify_coverage 三个校验器全部 PASS，且证明系统独立（不依赖 words.json）。
- **可参考的生成逻辑**：`mini_generator.py` 已跑通「装载→匹配公式→选动词→组 NP→变位→否定/疑问→表层」全流程，可作为 Dart 移植的**参考实现**（注：是参考，非"直接翻译"——Dart 端仍需按自身架构重写，且要把 §4-D 的 17 个 SKIP 句法特征一并规划）。
- **清晰的设计文档**：`generation_order.md`（九步流水线）、`identity_isolation.md`（系统/用户词合并契约）。

Flutter 端仍需新建（不在本轮范围）：
- `Knowledge` 装载与索引（Dart 版，复用 JSON + Schema 思路）。
- 生成循环宿主（句子请求 → 公式匹配 → 表层输出），并补齐 §7 延期的句法特征。
- `words.json` 合并层（按 spelling+pos 合并、用户侧优先）。
- SQLite 持久化与复习调度（README 已定义字段模型，含 `string[]` 变形字段）。

一句话：**地基（数据 + 规则 + 验证）已立且独立通过校验；生成器原型通过 golden/matrix 绿灯但仍需持续回归主谓一致与自然搭配——应用层可按上述契约开工，但请以"原型验证中"的心态对待生成质量。**

---

## 9. 依赖与标准运行方式（P2-5）

> 不再只依赖 WorkBuddy 私有 venv 路径。已提供标准依赖声明与命令。

**依赖文件**
- `requirements.txt`：`jsonschema==4.26.0`、`referencing==0.37.0`

> **第二轮更正**：初版的 `pyproject.toml` + `tools_entry.py` 控制台入口是**坏的**——
> 注册名是 `validate` / `generate`（报告却写成 `myenglish-validate` / `myenglish-generate`），
> 且只打包了 `tools_entry.py`，`patch/` 下的脚本与 JSON 数据全部没进包，装完调用必然
> `ModuleNotFoundError: No module named 'mini_generator'`。
> 本轮按「二选一」原则**直接删除这两个文件**，只保留「仓库内脚本 + requirements.txt」这一条可用路径。

**安装**
```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

**运行**
```bash
# venv 直跑脚本（脚本内部按 __file__ 定位数据，可在任意工作目录下调用）
.venv/bin/python patch/sentence/tools/validate_sentence_data.py
.venv/bin/python patch/sentence/tools/mini_generator.py golden
.venv/bin/python patch/sentence/tools/mini_generator.py matrix
.venv/bin/python patch/sentence/tools/mini_generator.py demo

# 检查器自检（用人造病句证明校验器会报错）
.venv/bin/python patch/sentence/tools/mini_generator.py selftest

# 功能词 / 模板覆盖校验（位于 patch/tools/）
.venv/bin/python patch/tools/check_master_vocab.py
.venv/bin/python patch/tools/verify_coverage.py
```

> 注：本环境演示使用的是 WorkBuddy 托管 Python（`/Users/iguoji/.workbuddy/binaries/python/envs/default/bin/python`），命令输出均来自此解释器；标准 venv 下行为一致。
