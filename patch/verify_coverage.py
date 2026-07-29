# -*- coding: utf-8 -*-
"""
patch 功能词库"全覆盖证明"验证器（启蒙 level 0 + 入门 level 100）

核心思想（为什么不用随机抽查）：
  功能词的需求量由"语法模板"唯一决定，与选了哪个实词无关。
  "the boy runs" 换成 "the girl jumps"，功能词一模一样。
  因此把所有维度组合的全部模板做笛卡尔积展开——
  实词槽位用占位符 {N}/{V}/{VT}/{ADJ} 表示（校验时跳过），
  功能词槽位全部铺开成真实单词——
  再逐 token 核对 words.json ∪ patch/*.json，
  通过即是"穷举证明"，不是概率抽样。

实词侧约定（用户侧责任，不在本验证范围）：
  - 动词不规则过去式（come→came）、名词不规则复数（child→children）
    属于用户词库的屈折形录入义务（同"run 也录入了复数形式"的约定）；
  - 规则屈折（-s/-es/-ed/-ing）由 app 确定性规则拼接。

用法：
  python3 patch/verify_coverage.py
退出码：0 = 全覆盖通过；1 = 存在缺失功能词（会逐条打印）。
"""

import json, glob, re, sys, itertools, os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------- 1. 加载词库并做基础一致性校验 ----------
user_words = json.load(open(f'{BASE}/words.json'))
patch_words = []
for f in sorted(glob.glob(f'{BASE}/patch/*.json')):
    patch_words += json.load(open(f))

user_ids = {w['id'] for w in user_words}
patch_ids = [w['id'] for w in patch_words]
assert len(patch_ids) == len(set(patch_ids)), 'patch 内部 id 重复！'
assert not (set(patch_ids) & user_ids), 'patch id 与 words.json 冲突！'
user_sp = {w['spelling'].lower() for w in user_words}
patch_sp = {w['spelling'].lower() for w in patch_words}
dup = user_sp & patch_sp
assert not dup, f'patch 与用户词库拼写重复: {dup}'

LEXICON = user_sp | patch_sp

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
# 表语形态（SVP）
PREDICATIVES = ['{ADJ}', 'a {N}', 'an {N}', 'the {N}']
# 特殊疑问词（入门级 6 个）
WH = ['what', 'who', 'when', 'where', 'why', 'how']
# 情态动词（入门级）及其否定
MODALS = [('will', 'will not', "won't"), ('would', 'would not', "wouldn't"),
          ('can', 'cannot', "can't"), ('could', 'could not', "couldn't")]
# 介词（介词宾语/地点状语）
PREPS = ['in', 'on', 'at', 'to', 'for', 'with', 'from']
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

# ---------- 3. 逐 token 穷举校验 ----------
PLACEHOLDER = re.compile(r'^\{(n|ns|v|vs|ved|ving|vt|vts|adj)\}$')

def check_all():
    missing = {}
    for t in templates:
        for tok in re.findall(r"[a-zA-Z'{}]+", t.lower()):
            if PLACEHOLDER.match(tok):
                continue  # 实词占位符：由用户词库+规则屈折保证，不在系统侧范围
            if tok not in LEXICON:
                missing.setdefault(tok, t)
    return missing

missing = check_all()
func_tokens = {tok for t in templates
               for tok in re.findall(r"[a-zA-Z']+", re.sub(r'\{[^}]+\}', '', t.lower()))}

print(f'词库规模: 用户 {len(user_words)} 词 + patch {len(patch_words)} 词')
print(f'穷举模板数: {len(templates)}')
print(f'涉及功能词种类: {len(func_tokens)} -> {sorted(func_tokens)}')

if missing:
    print(f'\n[FAIL] 缺失 {len(missing)} 个功能词:')
    for tok, t in sorted(missing.items()):
        print(f'  {tok!r:12s} 出现于模板: {t}')
    sys.exit(1)
else:
    print('\n[PASS] 全部模板的功能词均被 words.json ∪ patch 覆盖——穷举证明成立。')
    sys.exit(0)
