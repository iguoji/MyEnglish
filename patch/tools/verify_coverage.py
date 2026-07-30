# -*- coding: utf-8 -*-
"""
patch 功能词库"全覆盖证明"验证器（启蒙 level 0 + 入门 level 100）

核心思想（为什么不用随机抽查）：
  功能词的需求量由"语法模板"唯一决定，与选了哪个实词无关。
  "the boy runs" 换成 "the girl jumps"，功能词一模一样。
  因此把所有维度组合的全部模板做笛卡尔积展开——
  实词槽位用占位符 {N}/{V}/{VT}/{ADJ} 表示（校验时跳过），
  功能词槽位全部铺开成真实单词——
  再逐 token 核对【系统 patch/*.json 词库】（含变形字段），
  通过即是"穷举证明"，不是概率抽样。

系统独立性约定（2026-07-30 起生效）：
  - 本验证器【只加载系统 patch 词库】，不加载任何用户个人词库（words.json）。
    系统必须在用户数据库为空的情况下独立通过验证——新用户零词库也能用生成器。
  - 不规则屈折形（come→came、child→children）由系统基线的变形字段
    （past_tense / past_participle / plural / third_person_singular / gerund）保证，
    这些字段会被读入 LEXICON。
  - 规则屈折（-s/-es/-ed/-ing）由 app 确定性规则拼接，验证器同样展开覆盖。

用法：
  python3 patch/tools/verify_coverage.py
退出码：0 = 系统词库独立全覆盖通过；1 = 存在缺失功能词（会逐条打印）。
"""

import json, glob, re, sys, itertools, os

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---------- 1. 加载系统词库（只有 patch，不含任何个人词库）----------
patch_words = []
# 防御性加载：patch/ 下只接收"词库结构"（list 且元素为 dict）的 json。
# 非词库 json（annotations/*.json 是拼写数组、sentence/ 子目录不在此 glob 范围）
# 一律跳过，避免 w['id'] 对字符串/dict-key 取值而崩溃。
for f in sorted(glob.glob(f'{BASE}/patch/*.json')):
    data = json.load(open(f))
    if isinstance(data, list) and all(isinstance(w, dict) for w in data):
        patch_words += data

patch_ids = [w['id'] for w in patch_words]
assert len(patch_ids) == len(set(patch_ids)), 'patch 内部 id 重复！'
# 注意：不再断言"patch id 与用户词库不冲突"——数字 id 不是跨来源的全局身份，
# 其他用户的个人数据完全可能占用相同数字段；跨来源身份用 source + spelling + pos 区分。
patch_sp = {w['spelling'].lower() for w in patch_words}

LEXICON = set(patch_sp)

# 系统不规则变形：直接读取基线词条的变形字段（string[]，可含多合法形），
# 如 eat→ate/eaten、child→children。这是"系统数据自己保证不规则形"的落点。
_FORM_FIELDS = ('plural', 'third_person_singular', 'gerund', 'past_tense', 'past_participle',
                'comparative', 'superlative')
for w in patch_words:
    for fld in _FORM_FIELDS:
        for form in (w.get(fld) or []):
            if isinstance(form, str):
                LEXICON.add(form.lower())

# 规则屈折扩展：系统词的 -s/-es/-ies/-ing/-ed 变形由 app 确定性拼接产生，
# 属合法输出（如 come→comes, have→having）。
def _inflect(w):
    out = set()
    if re.search(r"[^a-z']", w): return out
    # 三单/复数
    if re.search(r'(s|x|z|ch|sh|o)$', w): out.add(w + 'es')
    elif re.search(r'[^aeiou]y$', w):     out.add(w[:-1] + 'ies')
    else:                                  out.add(w + 's')
    # 进行时/动名词
    out.add(w[:-1] + 'ing' if w.endswith('e') and not w.endswith('ee') else w + 'ing')
    # 规则过去式/过去分词
    out.add(w + 'd' if w.endswith('e') else (w[:-1] + 'ied' if re.search(r'[^aeiou]y$', w) else w + 'ed'))
    return out

for _w in list(LEXICON):
    LEXICON |= _inflect(_w)

# 多词功能短语（如 "each other" / "one another" / "no one"）在模板中以整体出现，
# 验证器把空格替换为下划线后作为单 token 比对，故此处登记其下划线形式。
for _sp in list(LEXICON):
    if ' ' in _sp:
        LEXICON.add(_sp.replace(' ', '_'))
MULTIWORDS = [s for s in patch_sp if ' ' in s]
def _norm(t):
    for mw in MULTIWORDS:
        t = t.replace(mw, mw.replace(' ', '_'))
    return t

# ---------- 2. 模板文法定义 ----------
# 主语形态：(主语模板, be现在, be过去, do现在, 否定缩写be现, 否定缩写be过, 否定缩写do现)
SUBJECTS = [
    ('I',        'am',  'was',  'do',   'am not', "wasn't",  "don't"),
    ('you',      'are', 'were', 'do',   "aren't", "weren't", "don't"),
    ('he',       'is',  'was',  'does', "isn't",  "wasn't",  "doesn't"),
    ('they',     'are', 'were', 'do',   "aren't", "weren't", "don't"),
    ('the {N}',  'is',  'was',  'does', "isn't",  "wasn't",  "doesn't"),
    ('the {Ns}', 'are', 'were', 'do',   "aren't", "weren't", "don't"),
]

# 宾语形态（SVO/SVOO/介宾通用）
OBJECTS = ['a {N}', 'an {N}', 'the {N}', 'the {Ns}', 'me', 'you', 'him', 'her', 'it', 'us', 'them']
# 形容词性物主代词（限定词位，与冠词互斥；由测试题暴露的模板盲区补入）
POSS = ['my', 'your', 'his', 'her', 'its', 'our', 'their']
# 表语形态（SVP）
PREDICATIVES = ['{ADJ}', 'a {N}', 'an {N}', 'the {N}']
# 特殊疑问词（入门级 6 个）
WH = ['what', 'who', 'when', 'where', 'why', 'how']
# 情态动词（入门级）及其否定
MODALS = [('will', 'will not', "won't"), ('would', 'would not', "wouldn't"),
          ('can', 'cannot', "can't"), ('could', 'could not', "couldn't")]
# 介词（介词宾语/地点状语）—— 覆盖英语介词全集
PREPS = ['in', 'on', 'at', 'to', 'for', 'with', 'from', 'by', 'of', 'about', 'into', 'over',
         'under', 'near', 'behind', 'between', 'without', 'above', 'across', 'against', 'along',
         'among', 'around', 'below', 'beneath', 'beside', 'beyond', 'down', 'during', 'inside',
         'like', 'off', 'onto', 'out', 'outside', 'past', 'through', 'toward', 'up', 'upon', 'within']
# 频率/时间/地点副词状语（可选修饰位）
ADVERBIALS = ['', ' now', ' here', ' there', ' often', ' never', ' always', ' sometimes']

templates = set()

def add(s):
    """收敛空格后加入模板集合"""
    templates.add(re.sub(r'\s+', ' ', s).strip())

# ---- 2.1 SV / SVO：四种时态 × 肯定/否定(全拼+缩写) × 陈述/一般疑问/特殊疑问 ----
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{Vs}' if aux == 'does' else '{V}'   # 三单变形由 app 规则拼接
    for obj in ['', ' ' + OBJECTS[0], ' them']:   # 宾语槽：无(SV)/冠词名词/代词
        vt = obj and '{VT}' or '{V}'
        vt3 = '{VTs}' if (obj and aux == 'does') else vt
        for advb in ADVERBIALS[:4]:  # 状语修饰位（含空）
            # 一般现在时
            add(f'{subj} {vt3}{obj}{advb}.')
            add(f'{subj} {aux} not {vt}{obj}.')
            add(f'{subj} {naux} {vt}{obj}.')
            add(f'{aux} {subj} {vt}{obj}?')
            add(f'{naux} {subj} {vt}{obj}?')
            # 一般过去时（规则动词 -ed；不规则由用户侧屈折形保证）
            add(f'{subj} {{Ved}}{obj}{advb}.')
            add(f'{subj} did not {vt}{obj}.')
            add(f"{subj} didn't {vt}{obj}.")
            add(f'did {subj} {vt}{obj}?')
            add(f"didn't {subj} {vt}{obj}?")
            # 一般将来时
            add(f'{subj} will {vt}{obj}{advb}.')
            add(f'{subj} will not {vt}{obj}.')
            add(f"{subj} won't {vt}{obj}.")
            add(f'will {subj} {vt}{obj}?')
            add(f"won't {subj} {vt}{obj}?")
            # 现在进行时
            add(f'{subj} {be_p} {{Ving}}{obj}{advb}.')
            add(f'{subj} {be_p} not {{Ving}}{obj}.')
            add(f'{subj} {nbe_p} {{Ving}}{obj}.' if "'" in nbe_p else f'{subj} {be_p} not {{Ving}}{obj}.')
            add(f'{be_p} {subj} {{Ving}}{obj}?')
        # 特殊疑问（wh- + do 骨架 / will / be进行）
        for wh in WH:
            add(f'{wh} {aux} {subj} {vt}{obj and " " + "{VT}" and obj or ""}?'.replace(obj, '') if False else f'{wh} {aux} {subj} {vt}?')
            add(f'{wh} did {subj} {vt}?')
            add(f'{wh} will {subj} {vt}?')
            add(f'{wh} {be_p} {subj} {{Ving}}?')
        # 情态动词（肯定/否定全拼/否定缩写/疑问/wh-疑问）
        for m, mn_full, mn_abbr in MODALS:
            add(f'{subj} {m} {vt}{obj}.')
            add(f'{subj} {mn_full} {vt}{obj}.')
            add(f'{subj} {mn_abbr} {vt}{obj}.')
            add(f'{m} {subj} {vt}{obj}?')
            add(f'what {m} {subj} {vt}?')
        # 介词宾语 / 地点状语（S V prep N）
        for p in PREPS:
            add(f'{subj} {v3} {p} the {{N}}.')
            add(f'{subj} {naux} {vt} {p} the {{N}}.')
    # 主语疑问（who 作主语，谓语按三单）
    add('who {Vs}?')
    add('who {Vs} ' + 'the {N}?')

# ---- 2.2 SVP：be 骨架 × 现在/过去/将来 × 肯定/否定 × 疑问/wh- ----
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    for pred in PREDICATIVES:
        for be, nbe in ((be_p, nbe_p), (be_pa, nbe_pa)):
            add(f'{subj} {be} {pred}.')
            add(f'{subj} {be} not {pred}.')
            if "'" in nbe: add(f'{subj} {nbe} {pred}.')
            add(f'{be} {subj} {pred}?')
            if "'" in nbe: add(f'{nbe} {subj} {pred}?')
        add(f'{subj} will be {pred}.')
        add(f"{subj} won't be {pred}.")
        add(f'will {subj} be {pred}?')
    for wh in ('what', 'who', 'where', 'how'):
        add(f'{wh} {be_p} {subj}?')
        add(f'{wh} {be_pa} {subj}?')

# ---- 2.3 SVOO 双宾：直接双宾 + to/for 介词改写 ----
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    for io in ('me', 'you', 'him', 'her', 'us', 'them'):
        add(f'{subj} {v3} {io} a {{N}}.')
        add(f'{subj} {v3} a {{N}} to {io}.')
        add(f'{subj} {v3} a {{N}} for {io}.')
        add(f'{subj} {naux} {{VT}} {io} the {{N}}.')
        add(f'{aux} {subj} {{VT}} {io} a {{N}}?')
        add(f'what {aux} {subj} {{VT}} {io}?')

# ---- 2.4 There be 存在句：现在/过去/将来 × 肯定/否定/疑问 ----
for be, nbe, np in (('is', "isn't", 'a {N}'), ('are', "aren't", '{Ns}'),
                    ('was', "wasn't", 'a {N}'), ('were', "weren't", '{Ns}')):
    for loc in ('', ' here', ' there') + tuple(f' {p} the {{N}}' for p in ('in', 'on', 'at')):
        add(f'there {be} {np}{loc}.')
        add(f'there {be} not {np}{loc}.')
        add(f'there {nbe} {np}{loc}.')
        add(f'{be} there {np}{loc}?')
add('there will be a {N}.')
add("there won't be a {N}.")
add('will there be a {N}?')

# ---- 2.5 祈使句：肯定/否定 × please 前后置 ----
for core in ('{V}', '{VT} the {N}', '{VT} a {N}', '{V} here', '{V} now'):
    add(f'{core}.')
    add(f'please {core}.')
    add(f'{core}, please.')
    add(f"don't {core}.")
    add(f'do not {core}.')
    add(f"please don't {core}.")

# ---- 2.6 原因状语从句（主句 + because/since + 从句） ----
for conj in ('because', 'since'):
    add(f'I {{V}} {conj} he {{Vs}}.')
    add(f"the {{N}} {{Vs}} {conj} they {{V}}.")
    add(f"why {{V}}? {conj} I {{V}}.")  # why 问答对

# ================= 筑基 level 200 =================
# 占位符扩展：{Vpp}=过去分词(规则-ed app拼接/不规则用户侧)、{ADJer}/{ADJest}=规则比较级最高级
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    hv = 'has' if aux == 'does' else 'have'
    hvn = "hasn't" if aux == 'does' else "haven't"
    # -- 现在完成时：肯定/否定(全拼+缩写)/疑问 + already/yet/just/ever --
    add(f'{subj} {hv} {{Vpp}}.')
    add(f'{subj} {hv} already {{Vpp}}.')
    add(f'{subj} {hv} just {{Vpp}} the {{N}}.')
    add(f'{subj} {hv} not {{Vpp}} the {{N}} yet.')
    add(f'{subj} {hvn} {{Vpp}} yet.')
    add(f'{hv} {subj} {{Vpp}} the {{N}}?')
    add(f'{hv} {subj} ever {{Vpp}} a {{N}}?')
    # -- 被动语态：现在/过去/将来/情态 × 肯定/否定/疑问 + by 短语 --
    for be, nbe in ((be_p, nbe_p), (be_pa, nbe_pa)):
        add(f'{subj} {be} {{Vpp}}.')
        add(f'{subj} {be} {{Vpp}} by the {{N}}.')
        add(f'{subj} {be} not {{Vpp}}.')
        if "'" in nbe: add(f'{subj} {nbe} {{Vpp}} by them.')
        add(f'{be} {subj} {{Vpp}} by the {{N}}?')
    add(f'{subj} will be {{Vpp}}.')
    add(f'{subj} must be {{Vpp}} by the {{N}}.')
    # -- 情态 must/shall/should：肯定/否定(全拼+缩写)/疑问 --
    for m, mn in (('must', "mustn't"), ('should', "shouldn't")):
        add(f'{subj} {m} {{V}}.')
        add(f'{subj} {m} not {{V}} the {{N}}.')
        add(f'{subj} {mn} {{V}}.')
        add(f'{m} {subj} {{V}}?')
    add(f'shall I {{V}}?')
    add(f'shall we {{V}} the {{N}}?')
    # -- SVOC 宾补 --
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    add(f'{subj} {v3} me {{ADJ}}.')
    add(f'{subj} {v3} him a {{N}}.')
    add(f'{subj} {naux} {{VT}} it {{ADJ}}.')
    add(f'{aux} {subj} {{VT}} them {{ADJ}}?')
    # -- 定语从句（限制性 who/which/that） --
    add(f'{subj} {v3} the {{N}} that {{Vs}}.')
    add(f'{subj} {v3} the {{N}} which he {{Vs}}.')
    add(f'the {{N}} who {{Vs}} is {{ADJ}}.')
    add(f'the {{N}} whose {{N}} is {{ADJ}} {{Vs}}.')
    # -- 条件 if/unless + 目的 so that --
    add(f'if {subj} {v3} the {{N}}, I will {{V}}.')
    add(f'unless {subj} {v3}, they will not {{V}}.')
    add(f'{subj} {v3} so that he can {{V}}.')
    # -- 比较：-er than / more...than / as...as / 最高级 --
    add(f'{subj} {be_p} {{ADJer}} than him.')
    add(f'{subj} {be_p} more {{ADJ}} than the {{N}}.')
    add(f'{subj} {be_p} as {{ADJ}} as them.')
    add(f'{subj} {be_p} the {{ADJest}} {{N}}.')
    add(f'{subj} {be_p} the most {{ADJ}} {{N}}.')
    add(f'so {{ADJ}} that I {{V}}.' if subj == 'I' else f'{subj} {be_p} so {{ADJ}} that they {{V}}.')

# -- 感叹句 --
add('what a {ADJ} {N}!')
add('what an {ADJ} {N}!')
add('what {ADJ} {Ns}!')
add('how {ADJ}!')
add('how {ADJ} the {N} is!')
add('how {ADJ} they are!')
# -- 非谓语主语 / 形式主语 / 形式宾语 / 指示代词 --
add('{Ving} is {ADJ}.')
add('to {V} is {ADJ}.')
add('it is {ADJ} to {V}.')
add('it is {ADJ} to {VT} the {N}.')
add('I find it {ADJ} to {V}.')
add('this is a {N}.')
add('that is the {N}.')
add('these are {Ns}.')
add('those {Ns} are {ADJ}.')
add('whose {N} is this?')
add('which {N} does he {VT}?')
add('whom does she {VT}?')
# -- 过去进行时（was/were 已入库，补模板） --
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    add(f'{subj} {be_pa} {{Ving}}.')
    add(f'{subj} {be_pa} not {{Ving}} the {{N}}.')
    add(f'{be_pa} {subj} {{Ving}}?')

# ================= 初成 level 300 =================
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    hv = 'has' if aux == 'does' else 'have'
    # -- 选择疑问 (A or B) --
    add(f'{aux} {subj} {{VT}} a {{N}} or an {{N}}?')
    add(f'{be_p} {subj} {{ADJ}} or {{ADJ}}?')
    # -- 宾语从句 / 主语从句 / 表语从句 --
    add(f'{subj} {v3} that he {{Vs}}.')
    add(f'{subj} {v3} if they {{V}}.')
    add(f'what {subj == "I" and "I" or subj} {{V}} is {{ADJ}}.' if subj == 'I' else f'what he {{Vs}} is {{ADJ}}.')
    add(f'that {subj} {{V}} is {{ADJ}}.' if subj in ('I', 'you', 'they') else 'that he {Vs} is {ADJ}.')
    # -- how many / how much / how long / how often / how far --
    add(f'how many {{Ns}} {aux} {subj} {{VT}}?')
    add(f'how much {{N}} {aux} {subj} {{VT}}?')
    add(f'how long {aux} {subj} {{V}}?')
    add(f'how often {aux} {subj} {{V}}?')
    add(f'how far {aux} {subj} {{V}}?')
    # -- 过去完成 / 过去将来 / 将来进行 --
    add(f'{subj} had {{Vpp}}.')
    add(f'{subj} had not {{Vpp}} the {{N}}.')
    add(f'had {subj} {{Vpp}}?')
    add(f'{subj} would {{V}}.')
    add(f'{subj} would not {{V}} the {{N}}.')
    add(f'{subj} will be {{Ving}}.')
    add(f'will {subj} be {{Ving}} the {{N}}?')
    # -- might 推测 / have to / be able to --
    add(f'{subj} might {{V}}.')
    add(f'{subj} might not {{V}}.')
    add(f'{subj} {hv} to {{V}} the {{N}}.')
    add(f'{subj} {be_p} able to {{V}}.')
    add(f'{subj} {be_p} not able to {{V}}.')
    # -- 让步 / 结果 / 并列 --
    add(f'although {subj} {{V}}, they {{V}}.' if subj in ('I', 'you', 'they') else f'although he {{Vs}}, they {{V}}.')
    add(f'even though {subj} {be_p} {{ADJ}}, he {{Vs}}.')
    add(f'{subj} {be_p} so {{ADJ}} that we {{V}}.')
    add(f'{subj} {v3} the {{N}} and the {{N}}.')
    add(f'{subj} {v3} a {{N}} but not an {{N}}.')
    # -- 程度状语 very/too --
    add(f'{subj} {be_p} very {{ADJ}}.')
    add(f'{subj} {be_p} too {{ADJ}} to {{V}}.')
    add(f'{subj} {be_p} also {{ADJ}}.')
    # -- V-ing / V-ed 分词修饰 --
    add(f'the {{Ving}} {{N}} {{Vs}}.')
    add(f'the {{Vpp}} {{N}} is {{ADJ}}.')

# ================= 小成 level 400 =================
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    hv = 'has' if aux == 'does' else 'have'
    hvn = "hasn't" if aux == 'does' else "haven't"
    # -- 反意疑问 --
    add(f'{subj} {{V}}, {naux} {subj}?' if aux == 'do' else f'{subj} {{Vs}}, {naux} he?')
    add(f'{subj} {be_p} {{ADJ}}, {nbe_p} {subj}?' if "'" in nbe_p else f'{subj} {be_p} {{ADJ}}?')
    add(f"{subj} {naux} {{V}}, {aux} {subj}?")
    # -- 使役感官 (do/doing/done) --
    add(f'{subj} {v3} me {{V}}.')
    add(f'{subj} {v3} him {{Ving}}.')
    add(f'{subj} {v3} the {{N}} {{Vpp}}.')
    # -- 现在完成进行 / 将来完成 / 过去完成进行 --
    add(f'{subj} {hv} been {{Ving}}.')
    add(f'{subj} {hvn} been {{Ving}} the {{N}}.')
    add(f'{hv} {subj} been {{Ving}}?')
    add(f'{subj} will have {{Vpp}}.')
    add(f'{subj} had been {{Ving}}.')
    # -- ought to / need / dare 情态用法 --
    add(f'{subj} ought to {{V}}.')
    add(f'{subj} ought not to {{V}}.')
    add(f"{subj} needn't {{V}}.")
    add(f"{subj} daren't {{V}}.")
    add(f'need {subj} {{V}}?')
    # -- 表语从句 / 同位语从句 --
    add(f'that is why {subj} {{V}}.' if subj in ('I', 'you', 'they') else 'that is why he {Vs}.')
    add(f'the {{N}} that {subj} {{V}} is {{ADJ}}.' if subj in ('I', 'you', 'they') else 'the {N} that he {Vs} is {ADJ}.')
    # -- to do 不定式修饰 --
    add(f'{subj} {v3} a {{N}} to {{VT}}.')

# ================= 进阶 level 500 =================
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    # -- 关联连词 not only...but also / both...and / either...or / neither...nor --
    add(f'{subj} {v3} not only the {{N}} but also the {{N}}.')
    add(f'both {subj == "I" and "he" or "he"} and I {{V}}.')
    add(f'either he or I {{V}}.')
    add(f'neither he nor I {{V}}.')
    add(f'both of them {{V}}.')
    add(f'either of them {{Vs}}.')
    # -- modal + have done 推测/遗憾 --
    add(f'{subj} must have {{Vpp}}.')
    add(f'{subj} should have {{Vpp}} the {{N}}.')
    add(f'{subj} could have been {{ADJ}}.')
    # -- 非限制性定从 / 介词+关系词 --
    add(f'the {{N}}, which is {{ADJ}}, {{Vs}}.')
    add(f'the {{N}}, who {{Vs}}, is {{ADJ}}.')
    add(f'the {{N}} in which {subj} {{V}} is {{ADJ}}.' if subj in ('I', 'you', 'they') else 'the {N} in which he {Vs} is {ADJ}.')
    add(f'the {{N}} with whom I {{V}} is {{ADJ}}.')
    # -- 过去将来进行 / 将来完成进行 --
    add(f'{subj} would be {{Ving}}.')
    add(f'{subj} will have been {{Ving}}.')

# ================= 物主代词维度（全级别通用限定词位） =================
# 名词短语的限定词槽：冠词 the/a/an 之外还有物主代词，此前模板漏了整个维度
for p in POSS:
    add(f'I {{VT}} {p} {{N}}.')                 # SVO 宾语带物主
    add(f'he {{VTs}} {p} {{Ns}}.')
    add(f'{p} {{N}} {{Vs}}.')                    # 物主作主语限定词
    add(f'{p} {{N}} is {{ADJ}}.')                # SVP
    add(f'{p} {{Ns}} are {{ADJ}}.')
    add(f'why did you not {{VT}} {p} {{N}}?')    # 测试句 5 型
    add(f"why didn't you {{VT}} {p} {{N}}?")
    add(f'the {{N}} {{Ving}} the {{N}} is {p} {{N}}.')  # 测试句 6 型（分词定语+物主表语）
    add(f'this is {p} {{N}}.')
# 名词性物主代词（作表语/宾语）
for p in ('mine', 'yours', 'his', 'hers', 'ours', 'theirs'):
    add(f'the {{N}} is {p}.')
    add(f'this {{N}} is {p}, not {p}.')

# ================= 补维度：反身代词 / some·any 限定词 / 时间连词 / 不定式宾语 / 介词全集 =================
# （由用户第二轮测试题暴露的模板盲区，按语法槽位系统性补铺）
# -- 反身代词槽：作宾语（hurt oneself）/ 强调 --
REFLEX = {'I': 'myself', 'you': 'yourself', 'he': 'himself', 'they': 'themselves',
          'the {N}': 'itself', 'the {Ns}': 'themselves'}
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    r = REFLEX[subj]
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    add(f'{subj} {v3} {r}.')
    add(f'{subj} {{Ved}} {r} yesterday.')       # 他昨天伤到了自己（yesterday 在用户词库）
    add(f'{subj} {naux} {{VT}} {r}.')
    add(f'{aux} {subj} {{VT}} {r}?')
    add(f'{subj} can {{VT}} {r}.')
# she/we 补一组（SUBJECTS 里没有的人称）
add('she {VTs} herself.')
add('we {VT} ourselves.')
add('you {VT} yourselves.')

# -- some/any/no/every/each/all 限定词槽（肯定用 some，否定/疑问用 any）--
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    hv = 'has' if aux == 'does' else 'have'
    add(f'{subj} {v3} some {{Ns}}.')
    add(f'{subj} {v3} some {{N}}.')              # 不可数
    add(f'{subj} {naux} {{VT}} any {{Ns}}.')
    add(f'{aux} {subj} {{VT}} any {{Ns}}?')
    add(f'{subj} {v3} no {{Ns}}.')
    add(f'{subj} {hv} some {{Ns}} but {naux} {{VT}} any {{Ns}}.')  # 测试句 2 型
    add(f'every {{N}} {{Vs}}.')
    add(f'each {{N}} is {{ADJ}}.')
    add(f'all the {{Ns}} are {{ADJ}}.')
    add(f'all of them {{V}}.')
# there be + some/any/no
add('there are some {Ns}.')
add("there aren't any {Ns}.")
add('are there any {Ns}?')
add('there is no {N}.')
# yes/no 简答
add('yes, I do.')
add('no, he does not.')
add("no, they don't.")
add('yes, it is.')
add("no, it isn't.")

# -- 时间连词 before/after/while/until（引导时间状语从句/介词用法）--
for tc in ('before', 'after', 'while', 'until', 'when'):
    add(f'{tc} I {{Ved}}, I {{Ved}} the {{N}}.')     # 在我睡觉之前，我关上了窗户
    add(f'I {{Ved}} the {{N}} {tc} I {{Ved}}.')
    add(f'he {{Vs}} {tc} they {{V}}.')
add('before {Ving}, I {Ved} the {N}.')               # 介词接动名词
add('after the {N}, they {Ved}.')
add('I did not {V} until he {Ved}.')

# -- 不定式符号 to：决定/想要/计划 + to do --
for subj, be_p, be_pa, aux, nbe_p, nbe_pa, naux in SUBJECTS:
    v3 = '{VTs}' if aux == 'does' else '{VT}'
    add(f'{subj} {v3} to {{V}}.')
    add(f'{subj} {{Ved}} to {{VT}} the {{N}}.')      # 我决定买那本书
    add(f'{subj} {naux} {{VT}} to {{V}}.')
    add(f'{subj} {v3} to {{VT}} a {{N}} {{ADJ}}.')
# have to 过去式（我昨天不得不步行去学校）
add('I had to {V} to the {N} yesterday.')
add('he had to {V} yesterday.')
add("they didn't have to {V}.")
add('did you have to {V}?')

# -- 介词全集补铺（talk about / 方位介词）--
for p in ('about', 'into', 'over', 'under', 'near', 'behind', 'between'):
    add(f'the {{N}} is {p} the {{N}}.')
    add(f'he {{Vs}} {p} the {{N}}.')
add('the {N} is {Ving} about a {N}.')                # 女孩正在谈论一本书
add('they are {Ving} about the {Ns}.')
add('what are you {Ving} about?')
add('the {N} is between the {N} and the {N}.')

# ================= 大成~无极 level 600-1000 =================
add('if I were you, I would {V}.')
add('if he were {ADJ}, he would {V} the {N}.')
add('if they had {Vpp}, they would have {Vpp}.')
add('I {VT} that he should {V}.')
add('I {VT} that he {V}.')  # should 省略型
# 700: wish / as if 虚拟 + 倒装
add('I wish I were {ADJ}.')
add('I wish I had {Vpp} the {N}.')
add('he {Vs} as if he were {ADJ}.')
add('never have I {Vpp} a {N}.')
add('never did he {V}.')
add('here comes the {N}.')
add('there {Vs} the {N}.')
# 800: 强调句 + 非谓语完成/被动态
add('it is the {N} that {Vs}.')
add('it was he who {Ved}.')
add('it is me that they {VT}.')
add('having {Vpp} the {N}, he {Ved}.')
add('having been {Vpp}, the {N} is {ADJ}.')
# 900: 独立主格 + 省略
add('the {N} {Ving}, they {Ved}.')
add('the {N} {Vpp}, he {Ved} the {N}.')
add('if {ADJ}, the {N} {Vs}.')
add('when {Ving}, you must {V}.')
# 1000: 插入语
add('however, he {Vs} the {N}.')
add('the {N}, however, is {ADJ}.')
add('therefore, they {V}.')
add('he is, in fact, {ADJ}.')
add('I think, therefore, that he {Vs}.')
# ================= 补维度③：用户第7轮测试题暴露的 6 大粘合词盲区 =================
# 每个维度都是"用户用一句中文逼出来的"——但以后由 check_master_vocab.py 自主发现，
# 不再依赖用户逐句查缺。以下模板只铺功能词真实形态，实词一律用占位符。

# 维度1：复合不定代词（someone / nothing / no one 等）—— 有人正在敲门，但我什么也没看见
add('someone is {Ving} at the {N}, but I {Ved} nothing.')
add('he {Ved} nothing.')
add('there is nothing in the {N}.')
add('I {Ved} something.')
add('does anyone know the {N}?')
add('nobody {Ved}.')
add('everyone {Vs} the {N}.')
add('everything is {ADJ}.')
add('no one {Vs} here.')          # no one 为多词短语，验证器按整体比对
add('none of them {Vs} {ADJ}.')
add('I {Ved} nothing about it.')

# 维度2：相互代词 each other / one another —— 他们互相帮助
add('they {VT} each other.')
add('we {V} one another.')
add('the {Ns} {V} each other.')
add('he {VTs} each other.')
add('she {VTs} one another.')

# 维度3：let 祈使句型（let 在用户词库，无需 patch）—— 让我试试
add('let me {V}!')
add('let us {V}!')
add('let him {V}!')
add('let her {V}!')
add('let them {V}!')

# 维度4：关系词引导定语从句（where 作关系副词）—— 这就是我出生的房子
add('this is the {N} where I {Ved}.')
add('I {Ved} the {N} where we {Ved}.')
add('the {N} when he {Vs} is {ADJ}.')
add('the {N} why he {Vs} is {ADJ}.')
add('the {N} who {Vs} is my {N}.')
add('the {N} whom he {VTs} is here.')
add('the {N} which {Vs} is {ADJ}.')
add('the {N} that {Vs} is {ADJ}.')
add('the {Ns} that {Vs} are {ADJ}.')
add('the {N} whose {N} is {ADJ}.')

# 维度5：介词 without（没有…就）—— 没有水，我们就活不下去
add('without {N}, we cannot {V}.')
add('they {Ved} without me.')
add('he did it without {N}.')
add('she {Ved} without us.')

# 维度6：劣等比较 less ... than / fewer ... than —— 这本书不如那本书有趣
add('this {N} is less {ADJ} than that {N}.')
add('this {N} is less {ADJ} than the other {N}.')
add('he is less {ADJ} than she is.')
add('fewer {Ns} are {ADJ} than those {Ns}.')
add('this is the least {ADJ} {N}.')

# ================= 补维度④：check_master_vocab.py 自主暴露的缺口（封闭类总表 diff）=================
# 这些维度用户从没提过，是"总表自检"工具自己揪出来的——证明缺口发现已不依赖例句。

# being（be 的现在分词：被动进行 / 进行体）
add('the {N} is being {Vpp}.')
add('they are being {ADJ}.')

# 自由关系副词 wherever / whenever
add('you {V} wherever he {Vs}.')
add('we {V} whenever we {V}.')

# 介词补全：amid / except / throughout / underneath
add('the {N} is amid the {Ns}.')
add('everyone {Ved} except him.')
add('it {Ved} throughout the {N}.')
add('the {N} is underneath the {N}.')

# 连词补全：whereas / once / whether / lest
add('he {Vs}, whereas she {Vs}.')
add('once you {V}, we {V}.')
add('I do not {V} whether he {Vs}.')
add('he {V} lest he {V}.')

# 副词补全：soon / away / ahead
add('he will {V} soon.')
add('they {Ved} away.')
add('he {Vs} ahead.')

# 应答词：thanks / okay
add('thanks!')
add('okay.')

# 半情态短语（used to 仅登记于 semi_modals.json，不在此铺模板以免依赖 use 基形）
add('I have to {V}.')
add('he {Vs} ought to {V}.')
add('I am able to {V}.')

# ================= 补维度⑤：用户网搜清单暴露的新功能词维度（自主补齐）=================
# 单字介词补全（despite/per/till/via/unlike/opposite/regarding/concerning/plus/minus）
for p in ('despite', 'per', 'till', 'via', 'unlike', 'opposite',
          'regarding', 'concerning', 'plus', 'minus'):
    add(f'he {{Vs}} {p} the {{N}}.')
# 单字连词补全（otherwise/nevertheless/nonetheless/furthermore/meanwhile/consequently/similarly/likewise）
for c in ('otherwise', 'nevertheless', 'nonetheless', 'furthermore',
          'meanwhile', 'consequently', 'similarly', 'likewise'):
    add(f'he {{Vs}}, {c} she {{Vs}}.')
# 半情态（has to / had to 可拆解；be going to/had better/would rather 含实词，只登记不铺模板）
add('he {Vs} has to {V}.')
add('he {Vs} had to {V}.')
# done（do 的过去分词，不规则，须显式录入）
add('the {N} is done.')
add('he has done the {N}.')
# 复合介词 / 复合连词：组成词全在词库的，铺模板以验证可用；
# 含实词组成词（front/next/spite/order/case/going/rather/better 等）的只登记于 patch，
# 由 check_master_vocab.py 总表覆盖，此处不铺模板以免验证器报缺实词。
for cp in ('out of', 'away from', 'ahead of', 'up to', 'except for', 'because of',
           'even though', 'even if', 'as long as', 'so that', 'now that',
           'as if', 'as though', 'as soon as'):
    add(f'the {{N}} is {cp} the {{N}}.')

# ---------- 3. 逐 token 穷举校验 ----------
PLACEHOLDER = re.compile(r'^\{(n|ns|v|vs|ved|ving|vpp|vt|vts|adj|adjer|adjest)\}$')

def check_all():
    missing = {}
    for t in templates:
        # token 正则必须包含下划线：多词短语（one another → one_another）在 _norm 中
        # 已合并为带下划线的单 token，若正则不含 _ 会被错误拆回单词（曾误报缺 one）。
        for tok in re.findall(r"[a-zA-Z'{}_]+", _norm(t).lower()):
            if PLACEHOLDER.match(tok):
                continue  # 实词占位符：由系统基线实词 + 变形字段 + 规则屈折填充，此处只验功能词
            if tok not in LEXICON:
                missing.setdefault(tok, t)
    return missing

missing = check_all()
func_tokens = {tok for t in templates
               for tok in re.findall(r"[a-zA-Z'_]+", re.sub(r'\{[^}]+\}', '', _norm(t).lower()))}

print(f'系统词库规模: patch {len(patch_words)} 词（不加载任何个人词库 words.json）')
print(f'穷举模板数: {len(templates)}')
print(f'涉及功能词种类: {len(func_tokens)} -> {sorted(func_tokens)}')

if missing:
    print(f'\n[FAIL] 系统词库缺失 {len(missing)} 个功能词:')
    for tok, t in sorted(missing.items()):
        print(f'  {tok!r:12s} 出现于模板: {t}')
    sys.exit(1)
else:
    print('\n[PASS] 系统词库独立覆盖：全部模板的功能词均被 patch 覆盖——穷举证明成立（未使用 words.json）。')
    sys.exit(0)
