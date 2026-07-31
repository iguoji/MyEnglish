# 句子生成器语料与检查器补全报告

> 生成时间：2026-07-30
> 产物路径：`patch/sentence/`
> 状态：本轮工作已完成，尚未提交 Git，待 GPT-Codex 独立复核（见第 11 节）。

---

## 1. 任务目标与范围

本任务聚焦 `patch/sentence/` 下的句子生成器基础设施，分三层推进：

1. **修复生成器骨架**：分析器驱动的检查器（`analyzer.py` + `mini_generator.check_grammar`）已在上轮完成并落地 11 组表层语法规则；`The scissors is sharp.` 的 forbidden 声明与真实检查也已恢复。
2. **2000 句真实日常英语语料验证**：联网收集并逐字转录恰好 2000 条去重真实句，覆盖 20 个日常类别、每类 100 句、每类来源 ≥3，且**不得用程序批量替换人名/代词/数字凑数**。
3. **检查器对真实语料的误报评估**：用上述 2000 句回灌检查器，量化误报率与误报边界，并用最小错误探针验证召回。

本报告如实记录结果，**不宣称 100% 无病句、不宣称可直接上线**（见第 10、11 节）。

---

## 2. 语料采集方法与真实性保证

- **逐字转录**：所有句子均从权威 ESL / 英语教学页面逐字抄录，未做改写、未做机械替换（人名、地名、数字一律保留原样或整句剔除，绝不在脚本里批量变换）。
- **占位符剔除**：`collect_corpus.py` 在 `main()` 中显式剔除含 `[PLACEHOLDER]`/`[Name]`/`[XXX]` 的占位模板句（如 `My name is [Name].`），从源头杜绝"假句子"混入。
- **来源页均为真实网页**：通过 WebSearch 检索来源页、WebFetch 逐字提取页面句子（prompt 要求 verbatim、不加编号/翻译）。原定部分来源（easyenglearn、englishclub introductions、unnaticlasses requests）因 404 或防爬拦截被替换，替换后仍满足"真实 ESL 页面"标准。
- **采集/裁剪流程可复现**：`collect_corpus.py` 的 `RAW` 是三元组 `(sentence, category, source_id)` 列表，经 `normalize()` 折叠空白、全局去重、每类上限 100 裁剪、缺口报告，最终写出 `corpus/daily_english_2000.json`。

---

## 3. 语料规模与结构

运行 `collect_corpus.py` 后关键输出（保留原始命令输出）：

```
总句数（全局去重 + 每类上限100）：2000
目标总数（20 × 100）：2000
各类别数量：
  greetings: 100  introductions: 100  daily_routine: 100  food_dining: 100
  shopping: 100  transportation: 100  weather: 100  health: 100
  family: 100  work_study: 100  hobbies: 100  emotions: 100
  requests_help: 100  phone_messages: 100  directions: 100  time_schedule: 100
  home_housework: 100  travel: 100  money_payment: 100  small_talk: 100
缺口类别数：0
```

20 个类别各恰好 100 句，累加 2000，缺口为 0。

---

## 4. 去重与缺口控制机制

- **全局去重**：以"归一化小写句文本"为唯一键，跨类别跨来源去重（同一句在不同来源出现只保留首次出现的一条）。
- **每类上限 100 裁剪**：去重后按 `RAW` 首次出现顺序逐类入桶，桶满即截断；超额类被钳到 100，缺口类在报告中显式暴露，绝不用其他类溢出补位。
- **缺口闭环**：BATCH 8 后仍有 2 个缺口（introductions 94 / money_payment 99），追加 BATCH 9（loveyou_intro 22 句 + wordln_money3 14 句）补齐，最终恰好 2000、缺口 0。
- **完整性复核**（独立统计脚本，绝对路径重跑）：
  - 归一化小写重复句数：**0**
  - 含占位符句子数：**0**
  - 不同来源数（source_id）：**53**

---

## 5. 来源多样性

每类来源数统计（独立脚本复核）：

```
不同来源数(source_id): 53
每类来源数 min/max: 3 / 11
  daily_routine: 3   directions: 3     travel: 3        (最少，均 ≥3)
  introductions: 11  health: 8         phone_messages: 7 (最多)
  ... 其余 17 类介于 4~6 之间
```

20 个类别每类来源数均 ≥3，满足"每类 ≥3 独立来源"的多样性约束，避免单一来源口音/模板偏差。

---

## 6. 检查器架构回顾

- **入口**：`mini_generator.check_grammar(sent, info=None)` → `Analyzer.analyze` → `Analysis` → 对账 `surface_ok` 与 `verify_declaration`，再按 11 组规则消费 `Analysis` 字段。
- **覆盖句型**：`Analyzer` 仅覆盖 SV / SVP / SVO / SVOO / SVOC / SV_PREP_O / THERE_BE / IMPERATIVE 八种基本句型；超出范围标 `pattern='unknown'` 并写 `unresolved`，**不强行判定**。
- **forbidden 声明**：`The scissors is sharp.` 的 forbidden 声明与真实检查已恢复（上轮完成），`scissors` 等 plural-only 名词的就近一致得到约束。
- **已知边界**（详见第 10 节）：检查器是面向"受控简单句型"的表层分析器，不是通用语法引擎。

---

## 7. 检查器对真实语料的误报评估

运行 `evaluate_corpus.py`（对 2000 句逐句 `check_grammar`，将 grammar/collocation/semantic 标记记为"误报口径"），原始输出：

```
语料总句数: 2000
被检查器标记（误报口径）: 105 句（误报率 5.25%）

各类别被标记句数（total / flagged）：
  daily_routine: 100 / 2      directions: 100 / 2      emotions: 100 / 4
  family: 100 / 4             food_dining: 100 / 4     greetings: 100 / 3
  health: 100 / 6             hobbies: 100 / 0         home_housework: 100 / 2
  introductions: 100 / 2      money_payment: 100 / 7   phone_messages: 100 / 9
  requests_help: 100 / 10     shopping: 100 / 7        small_talk: 100 / 13
  time_schedule: 100 / 4      transportation: 100 / 14 travel: 100 / 5
  weather: 100 / 3            work_study: 100 / 4

误报规则码分布（top）：
  grammar  complement_type_mismatch            : 34
  grammar  third_singular                      : 19
  grammar  missing_do_support                  : 19
  grammar  inflected_imperative                : 12
  grammar  missing_fixed_preposition           : 9
  grammar  be_agreement                        : 8
  grammar  uncountable_with_indefinite_article : 4
  grammar  subject_restriction_unmet           : 3
  grammar  wrong_dative_preposition            : 2
  grammar  degree_adverb_on_verb               : 2
  grammar  missing_copula                      : 1
  grammar  mechanical_ed_on_irregular          : 1
  grammar  uncountable_with_numeral            : 1
  grammar  have_agreement                      : 1
```

**结论**：约 5.25%（105/2000）的句子被检查器标记，但结合第 8 节采样可见，这些几乎全部是检查器对自由真实口语过度套用受控规则所致，并非真实病句（语料来自权威 ESL 来源、人工逐字转录，默认正确）。

---

## 8. 误报边界定性分析（采样）

从 `reports/evaluate_corpus.json` 的 `samples` 抽取典型误报，逐类定性：

| 规则码 | 典型误报句 | 真实情况 |
|---|---|---|
| `uncountable_with_indefinite_article` | `I'd like a coffee.` / `Can I have a coffee, please?` | 标准用法：mass noun 作"一份"可数（a coffee = a cup of coffee） |
| `uncountable_with_numeral` | `Two coffees, please.` | 同上，计数的是"杯数"而非液体本身 |
| `missing_do_support` | `Is this dish made fresh?` | 被动句，并非缺 do-support |
| `be_agreement` | `Good morning, are you open?` / `Summer days are hot and humid.` | 主谓一致正确，检查器对缩略/复合主语误判 |
| `third_singular` | `Long time no see!` / `Time to sleep.` | 习语 / 祈使 / 非三单结构 |
| `missing_fixed_preposition` | `I've been looking forward to seeing you.` | 介词 `to` 实际存在，检查器误解析 |
| `complement_type_mismatch` | `Did you finish the report?` / `I start my work.` | 合法句子，补语类型判定过严 |
| `inflected_imperative` | `Thanks for the ride.` / `Staying up is harmful...` | 祈使/动名词，非必误 |
| `missing_copula` | `A one-way ticket to Paris, please.` | 口语省略（ellipsis），合法 |
| `wrong_dative_preposition` | `show it to the inspector` | `to` 恰为正确双宾语介词 |
| `subject_restriction_unmet` | `Buses run every 15 minutes...` | 合法主谓 |
| `degree_adverb_on_verb` | `I'm so excited for the weekend.` | `so` 修饰形容词 excited，合法 |
| `have_agreement` | `Have a great time at the movies!` | 祈使句，无主谓一致问题 |
| `mechanical_ed_on_irregular` | `with no clouds` | `clouds` 属规则变化，无错误 |

**定性结论**：误报的根因是检查器把"受控简单句"的规则外推到自由口语（省略、习语、mass-noun 可数用法、被动、缩略、祈使/动名词），属于**已知作用域边界**，不代表语料本身有病句。

---

## 9. 最小错误探针召回验证

`evaluate_corpus.py` 内置 6 个"正确句 → 最小改动错误句"探针，验证检查器确实能抓错（与误报形成对照）：

```
最小错误变体探针：命中 6 / 6
  [OK ] 'He run.'                          -> 期望 third_singular, 实际 ['third_singular']
  [OK ] 'She reads not books.'             -> 期望 missing_do_support, 实际 ['missing_do_support']
  [OK ] 'A water is cold.'                 -> 期望 uncountable_with_indefinite_article, 实际 [...]
  [OK ] 'A apple is red.'                  -> 期望 article_phonetic_exception, 实际 [...]
  [OK ] 'He are happy.'                    -> 期望 be_agreement, 实际 ['be_agreement']
  [OK ] 'There is two books on the desk.' -> 期望 existential_agreement_violation, 实际 [...]
```

**结论**：6/6 命中，证明检查器对"明确语法错误"有召回能力，第 7 节的误报是作用域限制而非整体失灵。

---

## 10. 已知限制与未覆盖边界（如实披露）

1. **句型覆盖有限**：`Analyzer` 仅覆盖 8 种基本句型，复杂句（从句、非谓语嵌套、并列结构）标 `unknown` 而不判定，不会误伤也不会纠错。
2. **自由口语误报**：对省略、习语、祈使、动名词、mass-noun 可数用法等会过度套用受控规则（第 8 节），误报率约 5.25%。
3. **mass-noun 可数用法未建模**：`a coffee` / `two coffees` 这类标准用法被误判，需在知识库标注"serving 可数"语义或检查器加白名单。
4. **未做语义/搭配的深层校验**：collocation / semantic 类标记在本语料上未触发（均为 0），但对用户自造句的深层搭配仍需后续补充。
5. **不宣称无病句**：语料默认正确，但 2000 句人工逐字转录不排除个别来源页面自身的录入瑕疵；检查器误报边界外也不保证 100% 正确。

---

## 11. 复核待办与下一步

- **待 GPT-Codex 独立复核**：本任务**未提交 Git**，全部文件与命令输出保留在 `patch/sentence/` 下，供 GPT-Codex 独立复核语料真实性与检查器边界。
- **检查器收窄方向**（供复核参考）：将第 7 节高频误报码（`complement_type_mismatch` 34、`third_singular` 19、`missing_do_support` 19、`inflected_imperative` 12、`missing_fixed_preposition` 9、`be_agreement` 8）按第 8 节定性逐一收窄——例如 mass-noun 加 serving 白名单、被动句排除 missing_do_support、缩略/复合主语修正 be_agreement。
- **语义层补全**：后续可补充 collocation / semantic 真实样本以验证深层检查路径。

---

## 12. 交付物清单与命令留痕

**新增/改动文件**：
- `patch/sentence/tools/collect_corpus.py` — 加每类上限 100 + 缺口报告；注册 BATCH 8/9 来源并写入 RAW；最终产出 2000 句。
- `patch/sentence/corpus/daily_english_2000.json` — 2000 句、20×100、53 源、全局去重、无占位符（机器可读语料）。
- `patch/sentence/tools/evaluate_corpus.py` — 回灌检查器做误报评估 + 最小错误探针（本轮新建）。
- `patch/sentence/reports/evaluate_corpus.json` — 机器可读评估结果（误报分布 + 探针命中）。
- `docs/hy3_corpus_and_checker_completion_report.md` — 本报告（本轮新建）。

**关键命令留痕**：
```bash
# 1) 采集并写出语料（输出见第 3 节）
cd patch/sentence/tools && python3 evaluate_corpus.py   # 注：collect 由 collect_corpus.py 执行
# 2) 运行评估器（输出见第 7、9 节）
cd patch/sentence/tools && python3 evaluate_corpus.py
# 3) 独立复核语料完整性（第 4 节：重复 0 / 占位符 0 / 53 源）
python3 -c "import json,collections,re; d=json.load(open('corpus/daily_english_2000.json',encoding='utf-8')); ..."
```

**复核结论（中性）**：语料达到"恰好 2000 句、20×100、每类 ≥3 来源、全局去重、无占位符"的既定目标；检查器对受控错误有 6/6 召回，对自由真实口语存在约 5.25% 的已知误报边界。两项均**未宣称完成度 100% / 可直接上线**，待 GPT-Codex 独立复核后决定是否提交 Git。
