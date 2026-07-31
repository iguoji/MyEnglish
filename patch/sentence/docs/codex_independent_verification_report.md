# Codex 独立复核报告

> 复核日期：2026-07-30
>
> 本报告由 `codex_corpus_audit.py` 与 `codex_generator_contract.py` 生成和复核。
> 两个程序均不调用 Hy3 的 `analyzer.py`、`mini_generator.check_grammar` 或
> `evaluate_corpus.py` 作为判定依据。

## 结论

2000 条语料已经具备开发期“发现问题”的价值，但不能称为已验证的 2000 条
黄金正确句，也不能把 Hy3 报告中的 `105/2000 = 5.25%` 称为真实误报率。

Codex 独立黑盒生成器契约测试为 **19/19 通过**：13 条正例按预期生成，6 条
反例按预期安全拒绝。这个结果只证明当前明确写下的受控生成契约，不代表它已经
覆盖自由英语、电视剧对白、名著长句或复杂从句。

语料结构审计结果为 **FAIL**，不是因为 2000 条数量不够，而是因为来源和元数据
仍不满足可审计要求。

## 语料审计结果

| 项目 | 结果 | 解释 |
|---|---:|---|
| 总句数 | 2000 | 数量达到目标 |
| 类别 | 20 类，每类 100 | 数量结构通过 |
| source_id | 53 | 来源标识数量达到报告所称规模 |
| 格式有效 URL | 52 | 其中一个来源 URL 含 `...`，不是完整地址 |
| 域名 | 32 | 来源有一定分散度 |
| 全局完全重复 | 0 | 归一化后未发现完全重复 |
| 仅标点/大小写不同的近重复 | 5 | 例如 `Good morning.` 与 `Good morning!` |
| 明显坏 URL 记录 | 20 条 | 这些句子集中使用 `engoo_intro` 的不完整 URL |
| 缺少来源登记表 | 1 项 | 没有 `corpus/sources.json` 记录标题、作者、许可、复核状态 |
| 语体字段 | 全部 `neutral` | 尚未逐句标注，不能据此判断正式/口语 |
| notes | 全部为空 | 没有人工复核留痕 |
| 采集时间 | 全部相同 | 只能表示同批导出时间，不能证明逐页采集时间 |

联网探测 52 个格式有效 URL：45 个返回 HTTP 200，1 个返回 403，6 个因证书、
TLS 或超时失败。403/网络失败只能说明当前探测受限，不能直接说明来源不存在；
但是它们也不能被报告成“已验证可访问”。

独立审计还发现 1 条缺少句末标点的记录：`It's cloudy`。另外，采集清单中存在
这些需要人工确认的文本：

- `It's kind of expensive. Is'nt there a sale or something.`：`Is'nt` 是明显错误缩写；
- `The tulips are sure beautiful at this time of year, aren't they.`：句末问句使用句号，且 `sure beautiful` 需要核对来源语境；
- `Can I have it in a cheaper price?`：常见表达通常是 `at a cheaper price`，需要回看原页面；
- `May I have the receipt, please.`：语法可以成立，但原页面标点/语境仍应回看。

这些项目没有被独立审计器擅自改写，因为语料的任务是保留来源原文；应标为待
人工复核，而不是悄悄修正文案。

## 生成器契约测试

测试文件：`patch/sentence/tools/codex_generator_contract.py`。

覆盖内容：

- SV、SVP、SVO、THERE_BE；
- 一般现在、一般过去、一般将来、现在进行、过去进行、现在完成；
- 肯定、否定、一般疑问；
- 三单、规则/不规则过去式、冠词 `a/an`、不可数名词、do-support、There be 数一致；
- 静态动词进行时、天气动词主语、动词框架、宾语搭配、There be 进行时和不可数复数的安全拒绝。

所有 19 项通过，说明这些明确契约目前可作为 Dart/Flutter 移植时的回归基线。

## Hy3 现有 matrix 的独立解释

`python3 patch/sentence/tools/mini_generator.py matrix` 仍报告 24 条语法错误。
抽样包括：`It jumps.`、`It walks.`、`It flew.`、`Was it walking?`。

这些句子在 `verb_frames.json` 中的动词限制为 `animate`，而生成器的候选主语池
明确把 `it` 纳入 animate；但 Hy3 的 analyzer 又把同样的 `it` 判为
`subject_restriction_unmet`。这不是 2000 句语料的统计问题，而是生成器和检查器
对 `animate` 的定义不一致。需要在项目内部统一策略：

- 若 `animate` 包含动物/非人生命体的 `it`，检查器应接受这些句子；
- 若不允许 `it`，生成器就必须从 animate 池移除 `it`。

在统一之前，不能把 matrix 的 24 条失败简单写成“语法规则已通过”。

## 运行命令

```bash
python3 patch/sentence/tools/codex_corpus_audit.py --selftest
python3 patch/sentence/tools/codex_corpus_audit.py
python3 patch/sentence/tools/codex_corpus_audit.py --check-urls
python3 patch/sentence/tools/codex_generator_contract.py
```

报告文件：

- `patch/sentence/reports/codex_corpus_audit.json`
- `patch/sentence/reports/codex_generator_contract.json`

## 适用范围

2000 条句子适合在开发期间做回归素材：把真实句子按“受控支持 / 超出范围 /
需要新增词库或搭配”分类，帮助发现缺口。它不适合作为运行时静态句库，也不能
单独证明复杂英语全部正确。电视剧对白、名著内容、Top 200 日常句可以继续加入
测试材料，但应保留 `unsupported` 状态；超出当前句型的句子不能被强行判 FAIL。
