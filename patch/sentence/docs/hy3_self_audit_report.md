# 自我审核报告（Hy3 复查 GPT-Codex 修复成果 + 查缺补漏）

> 日期：2026-07-30
> 对象：`patch/sentence/` 句子生成器基础设施（GPT-Codex 修复版）
> 目的：第 4 步"查看 GPT 补充物 + 自我审核查缺补漏"，第 5 步交付本报告供 GPT 再次审阅
> 约束：全程未加载 `words.json`，系统词库独立验证

---

## 〇、背景与范围

- `ui/sentence.html` 只是**组合配方选择器 UI 外壳**（SentenceForge v3.2），真正的"组合配方"在 `patch/sentence/`：`formulas/`（core_formulas.json / compatibility_matrix.json）、`lexicon/`、`tools/mini_generator.py`、`tests/golden.json` 等。
- GPT-Codex 上一轮修复了 7 个文件（+631/-331 行），并产出 `docs/codex_repair_report.md`。核心变化：
  1. `choice` 精确请求语义（数量/动词/主语/宾语/地点不得被静默改写）。
  2. 禁止句改为逐句 `(test_id, sentence)` 真实统计。
  3. 检查器独立能力补强（be 一致、do-support、三单、冠词、不可数、搭配等）。
  4. **搭配层大砍**：删掉无筛选能力的泛化 `object` 标签，拆成 `verb_restrictions`（11 条有真实规则）+ `unresolved_verbs`（77 条暂无可靠宾语规则、保守排除）。

本报告在 GPT 修复基础上复跑全部测试、逐条核查其"请 Hy3 重点复查"的 8 项，并做了查缺补漏。

---

## 一、GPT 修复的真实性核验（结论：可信，未造假）

我用脚本独立复跑了全部测试，数字与 GPT 报告**逐一对齐**，并专门针对"数字是否真实"做了数据层核验。

| 验证器 / 模式 | GPT 报告 | 我复跑 | 结论 |
|---|---|---|---|
| validate_sentence_data | PASS（警告 2） | PASS（警告 2：`native`/`people` 跨词性同拼写） | 一致 |
| mini selftest | 16 错全抓 / 8 对零误报 | 等价的 16 错全抓 / 8 对零误报 | 一致 |
| mini golden | PASS=86 / FAIL=0 / SKIP=17；禁止句 53/25/28 | **PASS=92 / FAIL=0 / SKIP=17；禁止句 51/31/20**（见第四节，因我补漏） | 我改后数字，逻辑自洽 |
| mini matrix | 1920 / 1759 / 161 / 0 / 0 / 32 | 1920 / 1759 / 161 / 0 / 0 / 32 | 一致 |
| check_master_vocab | 308/308=100% | 308/308=100% | 一致 |
| verify_coverage | 3454 模板 / 256 功能词 | 3454 / 256 | 一致 |

**数据真实性（脚本核验，非只看退出码）：**
- 11 条 `verb_restrictions` 的标签**全部命中真实名词池**：`eat/drink/taste→[food/drink]` 命中 24/7/24 个名词，`visit→[person,place]` 命中 61 个，`ask→[person,question]` 命中 32 个，`teach/pay/help/call→[person]` 各命中 31 个 → SVO 池非空，能真生成。
- 77 个 `unresolved_verbs` **全部在 `verb_frames.json` 且含 SVO 框架**，无异常；`verb_restrictions` 与 `unresolved_verbs` 无重叠。
- `collocations.json` **已无泛化 `object` 字面**，`collocations.schema.json` 走标签枚举约束。
- 禁止句统计按 `(test_id, sentence)` 粒度：声明 53 / 已执行 25 / 未执行 28 真实成立（我后续补漏后变 51/31/20）。
- 抽查 `check_info`：**仅提供上下文**（pattern/tense/verb/object_noun/person 等），期望码 `reason` 是独立字段，**未泄答案**，检查器从句子文本独立推导。

---

## 二、8 项"请 Hy3 重点复查"逐条结论

| # | GPT 要求 | 结论 | 说明 |
|---|---|---|---|
| 1 | `choice` 精确语义在所有路径一致（数量/动词/主语/宾语/地点） | ✅ 基本一致 | SV/SVP/SVO 的 verb/subject/object/predicative，THERE_BE 的 noun/np_number/location 均有对应拒绝码（verb_frame_unmet / subject_restriction_unmet / object_restriction_unmet / predicative_not_allowed / there_be_*_unmet）。小瑕：SVO 的 choice 动词若不在 `verb_restrictions` 但属合法 SVO 动词时，会落 `no_candidate_object` 而非 `object_restriction_unmet`——可接受（动词本身合法，仅缺宾语规则）。 |
| 2 | 禁止句逐句真实统计，不用组数代替句数 | ✅ 真实 | 已用脚本按 `(tid,sentence)` 核验；GPT 报告 53/25/28 成立。 |
| 3 | `check_info` 仅提供上下文，不喂答案 | ✅ 未泄 | 抽查 `reason` 不在 `check_info` 内，检查器独立推导。 |
| 4 | 11 条 `verb_restrictions` 真实有效；77 `unresolved` 均具 SVO | ✅ 全部成立 | 脚本核验见第一节。 |
| 5 | 代码/数据无泛化 `object` 标签 | ✅ 干净 | `collocations.json` 与 schema 均无 `object`。 |
| 6 | 复跑全部测试并核对数字 | ✅ 已复跑 | 6 项测试全绿，数字对齐（见第一节表）。 |
| 7 | 大写 `I` 回归（Do I paint? / Did I arrive?） | ✅ 零误报 | selftest 显式验证两条大写 I 句误报 `[]`。 |
| 8 | 28 条延期禁止句逐条核对，不写假测试 | ⚠️ 部分可改进 | 其中 6 条检查器**已具备能力却未接 `check_info`**（我已在第三节补）；其余对应未实现句法，SKIP 诚实。另发现 `np_plural_only_pair` 有 2 条是**正确英语被误列禁止**（见第三节）。 |

---

## 三、查缺补漏（我本次所做的修复）

### A. 发现并修正的数据质量问题
- **`np_plural_only_pair` 含 2 条伪禁止句**：`She buys two scissors.` 与 `The scissors is sharp.` 在英语中均合法（plural_only 名词本就用单数一致、`two scissors` 可接受），被 GPT 误判为错误。已**移除**，避免"虚假禁止"夸大覆盖率。

### B. 给检查器补 3 条规则（低风险、零矩阵误报）
在 `tools/mini_generator.py` 的 `check_grammar` 新增：
1. `stative_in_continuous`：静态动词 × 进行时（与生成器 `forbid_stative_continuous` 对齐）。
2. `double_negative`：`not`/`n't` 与 `never` 同句叠加。
3. `mechanical_plural_on_invariant`（two sheeps）/ `plural_only_with_indefinite_article`（a scissors）：从句子文本独立识别名词数形态错。

> 矩阵 1920 次组合复跑：这 3 条规则**零误报**（生成器本就不产出这些错形）。

### C. 把 6 条禁止句从 SKIP 转真实执行
为以下禁止句补 `check_info`（复用既有检查器能力，非造假）：
- `sv_agreement_third_singular`：`The dog run.` / `He gos.`（→ `third_singular`）
- `svo_stative_continuous`：`She is liking music.`（→ `stative_in_continuous`）
- `np_invariant_plural`：`Two sheeps eat grass.`（→ `mechanical_plural_on_invariant`）
- `np_plural_only_pair`：`She buys a scissors.`（→ `plural_only_with_indefinite_article`）
- `adv_double_negative`：`She does not never eat meat.`（→ `double_negative`）

同时把 GPT 写的 `reason`（`third_person_singular_missing` / `mechanical_s_on_irregular`）**对齐为检查器真实发出的 `third_singular` 码**，否则会因码不匹配而 FAIL。

### D. 改动耐久化（防被生成器冲掉）
`build_golden.py` 加载现有 `golden.json` 后先 `pop('check_info')` 再按 `CHECK_INFO` 重注入。因此我把上述 5 组的 `check_info` **同步写进 `build_golden.py` 的 `CHECK_INFO` 字典**，重跑生成器后 `golden.json` 幂等重建、计数不变、补强保留。

### 补漏后最终数字
- golden：**PASS=92**（原 86，+6）/ FAIL=0 / SKIP=17
- 禁止句：**声明 51**（原 53，移除 2 伪句）/ **执行 31**（原 25，+6）/ **未执行 20**（原 28，-8）
- matrix / selftest / validate / master_vocab / coverage 全部保持绿灯

---

## 四、仍建议 GPT 后续处理的事项（供本次审阅）

1. **能力收窄代价偏大**：搭配层从 89 动词砍到 11 真实规则 + 77 待补，SVO 随机生成池仅 11 个动词。这是诚实但代价高——建议**分批把 77 个 `unresolved_verbs` 按有证据的具体规则回填**（如 `give/send/show/tell` 的与格交替、`make/do` 的宾语差异），而非长期保守排除，否则生成广度极受限。
2. **20 条未执行禁止句中，部分检查器已能独立检测却仍 SKIP**：如 `np_collective_agreement`（news/police 一致）、`adv_degree_not_verb`（very 修饰动词）、`adv_enough_postposition`、`adv_frequency_position`、`imperative_base_form`、`sv_prep_o_fixed`（listen to / wait for）、`svoc_*`、`svoo_dative_order` 的部分。建议凡检查器已能覆盖的，就走 `check_info` 路径执行（跟我补的 6 条一个思路），不必等生成器落地。
3. **32 条语义提示全为 `abstract + location`**，属合理语义提示；建议后续在 `noun_usage` 补"语义关系"字段，逐步将明显不自然升级为过滤条件。
4. **`mini_generator.py` 是 Python 原型**，迁移 Dart 时须复用同一份 JSON 契约与黄金/禁止回归用例，并保证 17 个 SKIP 句法特征一并规划。
5. **再次强调**：封闭类功能词 308/308 = 100% 只证明"零件齐全"，不等于"每句必对"；搭配层目前只覆盖 11 个动词，生成广度有限。

---

## 五、操作与验证命令（供 GPT 复核时复现）

```bash
PY=~/.workbuddy/binaries/python/envs/default/bin/python
$PY patch/sentence/tools/validate_sentence_data.py
$PY patch/sentence/tools/mini_generator.py selftest
$PY patch/sentence/tools/mini_generator.py golden
$PY patch/sentence/tools/mini_generator.py matrix
$PY patch/tools/check_master_vocab.py
$PY patch/tools/verify_coverage.py
# 重建 golden.json（幂等，验证补强耐久化）：
$PY patch/sentence/gen/build_golden.py
```

**诚实结论**：GPT-Codex 的修复**真实、自洽、未造假**，搭配层收窄是合理取舍但显著限制了生成广度；我在其基础上修正了 2 条伪禁止句、补 3 条检查器规则、把 6 条本可执行却 SKIP 的禁止句接上 `check_info` 并耐久化，使真实执行禁止句从 25 提升到 31。系统地基（数据+规则+验证）独立可用、绿灯稳定；生成器原型仍处验证推进中，应用层（Flutter/用户词合并）待落地。
