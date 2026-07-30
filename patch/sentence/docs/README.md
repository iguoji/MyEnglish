# patch/sentence/ —— 句子生成器知识库

> 与普通词库（patch/*.json）完全分离：词库负责"这个词长什么样"，
> 本目录负责"这个词怎么造句"。本目录数据**不进入** Word/Meaning/SQLite/备份格式。

## 目录分层

| 目录 | 内容 | 性质 |
|---|---|---|
| `schemas/` | 全部数据文件的 JSON Schema（draft-07） | 表单验证契约 |
| `annotations/` | 策略化标注（stative/gradability/number_behavior/person_default） | 多值策略，升级自 patch/annotations 的 Boolean 词表 |
| `lexicon/` | 名词用法、动词框架、形容词/副词用法、a-an 特例、语义分类 | 结构化规则（与 Boolean 标注分离） |
| `paradigms/` | 代词、be/do/have、情态、限定词范式 | 封闭类完整范式 |
| `formulas/` | 正式公式契约、兼容矩阵、生成顺序、安全失败规则 | 可运行契约 |
| `tests/` | 黄金句/禁止句、组合测试配置 | 测试数据（与正式数据分离） |
| `reports/` | 校验与覆盖率报告输出 | 生成物，不手改 |
| `tools/` | 校验器、覆盖率报告器、CLI 生成器原型 | 可执行 |
| `docs/` | 架构决策文档 | 说明 |

## 统一查找键（任务 7 约定）

- **主键：`normalized_spelling + pos`**。normalized = 小写、去首尾空格、多词短语保留单空格。
- 同拼写不同词性是不同条目：`water+n.` 与 `water+v.`、`light+n./v./adj.` 互不串规则。
- 同拼写同词性有多用法时，追加 `usage_id`（如 `water#liquid`），**只在本知识库拆分，不改原 Meaning**。
- **禁止用数字 id 作为跨来源身份**（见 `identity_isolation.md`）。

## 数据纪律

- 不确定 → `unknown` / 排除 / 待复核，禁止猜测写成事实。
- 未知不得默认 countable / 默认允许被动 / 默认动词框架。
- 每条人工判断的数据带 `provenance`（来源、是否复核、置信度、检查日期）。
- 新增数据必须通过 `tools/validate_sentence_data.py` 后才可提交。
