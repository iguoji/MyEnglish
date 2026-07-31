#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
语料评估器（任务：2000 句真实日常英语语料验证）
================================================

【这个脚本做什么】
collect_corpus.py 已经产出 daily_english_2000.json（2000 句、20 类各 100、
全局去重、每类 ≥3 来源）。本脚本在此基础上做"质检"，回答三个问题：

  1) 这 2000 句是不是真能被检查器当成"正确句"——即检查器对它们的
     误报率（false positive）有多高？
     → 因为语料来自权威 ESL 来源、且人工逐字转录，默认应判为正确；
       凡是检查器仍打上 grammar/collocation/semantic 标记的，都记为"误报"
       （检查器是面向"受控简单句型"的表层分析器，不是通用语法引擎，
        对自由真实句出现误报属于已知边界，需如实上报，不得粉饰）。

  2) 误报按"规则码"聚成几类，方便后续针对性收窄检查器作用域。

  3) 最小错误变体探针：故意把若干正确句做最小改动（缺三单、缺 do-support、
     不可数名词加 a、a/an 音系错），验证检查器确实能抓到——证明误报不是
     因为检查器"整体失灵"，而是作用域限制。

【产出】
  - reports/evaluate_corpus.json：机器可读结果
  - 标准输出：人类可读摘要（供 #19 报告引用）

【依赖】
  复用 mini_generator.Knowledge + analyzer + check_grammar，不另造轮子。
"""

import collections
import json
import os
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
SENT = os.path.dirname(TOOLS)
CORPUS = os.path.join(SENT, 'corpus', 'daily_english_2000.json')
REPORT = os.path.join(SENT, 'reports', 'evaluate_corpus.json')

# 把 tools 目录塞进 sys.path，保证能 import mini_generator / analyzer
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

import mini_generator as mg


# ---------------------------------------------------------------------------
# 1) 主流程：对每句跑检查器，按 (类别, 码) 聚合
# ---------------------------------------------------------------------------
def evaluate():
    # 装载知识库（同生成器一致），并让 check_grammar 使用它
    mg.K = mg.Knowledge()

    data = json.load(open(CORPUS, encoding='utf-8'))

    # 每句的检查结果：flagged=是否被任何 grammar/collocation/semantic 标记
    per_cat = collections.defaultdict(lambda: {'total': 0, 'flagged': 0})
    code_counter = collections.Counter()          # (类别, 码) -> 次数
    cat_code = collections.defaultdict(collections.Counter)  # 类别 -> 码 -> 次数
    samples = collections.defaultdict(list)       # 码 -> 样例句（最多 5 条）
    flagged_sentences = []                        # 被标记的句子明细

    for o in data:
        sent = o['sentence']
        cat = o['category']
        per_cat[cat]['total'] += 1
        try:
            issues = mg.check_grammar(sent, None)
        except Exception as e:  # 分析器解析异常也记一笔，不能静默吞掉
            issues = [('structure', 'analyzer_exception:' + type(e).__name__, sent)]
        # 仅 grammar/collocation/semantic 算"误报"；structure 单算（解析失败）
        false_pos = [it for it in issues
                     if it[0] in ('grammar', 'collocation', 'semantic')]
        if false_pos:
            per_cat[cat]['flagged'] += 1
            for c, code, s in false_pos:
                code_counter[(c, code)] += 1
                cat_code[cat][code] += 1
                if len(samples[code]) < 5:
                    samples[code].append(s)
            flagged_sentences.append({
                'sentence': sent, 'category': cat,
                'codes': [code for _, code, _ in false_pos],
            })

    total = len(data)
    total_flagged = len(flagged_sentences)
    summary = {
        'total_sentences': total,
        'flagged_sentences': total_flagged,
        'false_positive_rate': round(total_flagged / total, 4) if total else 0,
        'per_category': {c: per_cat[c] for c in sorted(per_cat)},
        'code_distribution': [
            {'category': c, 'code': code, 'count': n}
            for (c, code), n in code_counter.most_common()
        ],
        'samples': {code: ss for code, ss in samples.items()},
    }
    return summary, flagged_sentences


# ---------------------------------------------------------------------------
# 2) 最小错误变体探针：验证检查器"能抓错"（召回），与误报形成对照
# ---------------------------------------------------------------------------
def minimal_error_probes():
    """对一组正确句做最小改动，期望检查器命中对应错误码。

    返回 (总探针, 命中数, 明细列表)。任何一项未命中都记下来供复核。
    """
    # 探针 = (原句, info 覆盖, 期望码, 改后句)
    # info 给 check_grammar 提供"声明"用于主谓一致对账（与黄金测试同机制）
    base = dict(pattern='X', polarity='affirmative', question='none',
                is_be=False, person=None, number=None, verb=None,
                object_noun=None, mass_object=False, semantic_unnatural=False)
    probes = [
        # 三单缺失：He run.
        ("He runs.", dict(tense='present_simple', person=3, number='singular',
                          verb='run'), 'third_singular', "He run."),
        # 缺 do-support 否定：She reads not books.
        ("She reads books.", dict(tense='present_simple', polarity='negative',
                                  verb='read'), 'missing_do_support',
         "She reads not books."),
        # 不可数名词加 a：a water
        ("Water is cold.", dict(tense='present_simple', is_be=True),
         'uncountable_with_indefinite_article', "A water is cold."),
        # a/an 音系错：a apple
        ("An apple is red.", dict(tense='present_simple', is_be=True),
         'article_phonetic_exception', "A apple is red."),
        # be 一致错：He are happy.
        ("He is happy.", dict(tense='present_simple', is_be=True),
         'be_agreement', "He are happy."),
        # 存在句就近一致：There is two books.
        ("There are two books on the desk.",
         dict(tense='present_simple', pattern='THERE_BE', is_be=True),
         'existential_agreement_violation', "There is two books on the desk."),
    ]
    hit = 0
    rows = []
    for orig, info, exp_code, corrupted in probes:
        full = dict(base)
        full.update(info)
        issues = mg.check_grammar(corrupted, full)
        codes = [c for _, c, _ in issues]
        ok = exp_code in codes
        hit += 1 if ok else 0
        rows.append({'corrupted': corrupted, 'expected': exp_code,
                     'got': codes, 'hit': ok})
    return {'total': len(probes), 'hit': hit, 'rows': rows}


# ---------------------------------------------------------------------------
# 3) 入口
# ---------------------------------------------------------------------------
def main():
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    summary, flagged = evaluate()
    probes = minimal_error_probes()

    out = {
        'corpus_evaluation': summary,
        'minimal_error_probe': probes,
    }
    json.dump(out, open(REPORT, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=2)

    # ---- 人类可读摘要 ----
    s = summary
    print(f"语料总句数: {s['total_sentences']}")
    print(f"被检查器标记（误报口径）: {s['flagged_sentences']} 句"
          f"（误报率 {s['false_positive_rate']*100:.2f}%）")
    print("\n各类别被标记句数（total / flagged）：")
    for c in sorted(s['per_category']):
        t = s['per_category'][c]['total']
        f = s['per_category'][c]['flagged']
        mark = '' if f == 0 else f"  <-- {f}"
        print(f"  {c:16s}: {t:3d} / {f:3d}{mark}")
    print("\n误报规则码分布（top）：")
    for row in s['code_distribution'][:15]:
        print(f"  {row['category']:11s} {row['code']:38s}: {row['count']}")
    print("\n最小错误变体探针：命中 %d / %d" % (probes['hit'], probes['total']))
    for r in probes['rows']:
        print(f"  [{'OK ' if r['hit'] else 'MISS'}] {r['corrupted']!r}"
              f" -> 期望 {r['expected']}，实际 {r['got']}")
    print(f"\n写出：{REPORT}")


if __name__ == '__main__':
    main()
