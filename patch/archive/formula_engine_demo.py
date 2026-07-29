#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 sentence.html 的"语法维度"解析成结构化「公式schema」，并附一个最小可跑的生成器，
证明核心机制：公式(免费) + 槽位词库(可变) + 用户词混入 = 句子随录入自动变化。

这是给零基础用户的"原理验证"版，只实现 SVO 及其少量修饰，不覆盖全部 16 时态——
全部时态的引擎是更大的后续工程，此处只为证明机制可行、工作量可控。
"""
import re, json

HTML = open('/Users/iguoji/Desktop/Learn/MyEnglish/ui/sentence.html', encoding='utf-8').read()

# ---------- 第 1 步：从 HTML 解析出所有维度 ----------
inp_re = re.compile(r'<input[^>]*?type="(radio|checkbox)"[^>]*?name="([^"]+)"[^>]*?>', re.S)
inputs = []
for m in inp_re.finditer(HTML):
    seg = m.group(0)
    lvl = re.search(r'data-level="(\d+)"', seg)
    val = re.search(r'value="([^"]+)"', seg)
    lab = re.search(r'for="[^"]+">([^<]+)<', seg)
    inputs.append({
        'type': m.group(1), 'name': m.group(2),
        'level': int(lvl.group(1)) if lvl else 0,
        'value': val.group(1) if val else None,
        'label': lab.group(1).strip() if lab else None,
    })

radio, check = {}, {}
for it in inputs:
    (radio if it['type'] == 'radio' else check).setdefault(it['name'], []).append(it)

# user_level 是"门禁"不是公式维度，单独记
schema = {
    'meta': {
        'source': 'ui/sentence.html',
        'note': '公式=语法维度组合(免费代码)；单词只在槽位里，与配方数无关',
        'gating_selector': 'user_level(11级，只控制选项可见性，不乘进配方数)',
    },
    'radio_dimensions': {k: [v['value'] for v in vals] for k, vals in radio.items() if k != 'user_level'},
    'checkbox_dimensions': {k: [v['value'] for v in vals] for k, vals in check.items()},
    # 每个句型需要"填词"的槽位（这就是"相关单词"的落点）
    'slot_model': {
        'sv':     ['subject', 'verb'],
        'svp':    ['subject', 'be', 'predicative'],
        'svo':    ['subject', 'verb', 'object'],
        'svoo':   ['subject', 'verb', 'object1', 'object2'],
        'svoc':   ['subject', 'verb', 'object', 'complement'],
        'therebe':['there', 'be', 'object', 'place'],
    },
    # 修饰开关各自往句子里加的槽位
    'modifier_slots': {
        'ext_modals': ['modal'],
        'ext_attr':   ['attribute'],
        'ext_adv':    ['adverbial'],
    },
}

with open('/Users/iguoji/Desktop/Learn/MyEnglish/patch/formula_schema.json', 'w', encoding='utf-8') as f:
    json.dump(schema, f, ensure_ascii=False, indent=2)
print('[已生成] patch/formula_schema.json')

# ---------- 第 2 步：最小生成器（仅 SVO + 少量修饰，演示机制）----------

# 系统内置槽位词库（即"相关的单词"，可随用户录入扩充）
BANKS = {
    'subject':   [{'w': 'I', 'person': 1, 'num': 'sg'},
                  {'w': 'He', 'person': 3, 'num': 'sg'},
                  {'w': 'They', 'person': 3, 'num': 'pl'}],
    'verb':      [{'w': 'eat', 'reg': True}, {'w': 'like', 'reg': True}, {'w': 'see', 'reg': False}],
    'object':    [{'w': 'apple'}, {'w': 'banana'}],
    'modal':     [{'w': 'can'}],
    'attribute': [{'w': 'red'}],
    'adverbial': [{'w': 'every day'}],
}

def inflect_verb(v, person, num, tense):
    """极简变形：仅演示机制，覆盖规则/不规则与三单/过去"""
    base = v['w']; reg = v.get('reg', True)
    if tense == 'past':
        return base + 'ed' if reg else {'see': 'saw', 'eat': 'ate', 'like': 'liked'}.get(base, base + 'ed')
    if tense == 'present' and person == 3 and num == 'sg':
        return base + 's' if reg else {'see': 'sees', 'eat': 'eats', 'like': 'likes'}.get(base, base + 's')
    return base

def gen_svo(formula, banks, tense='present'):
    out = []
    for s in banks['subject']:
        for v in banks['verb']:
            for o in banks['object']:
                subj = s['w']
                verb = inflect_verb(v, s['person'], s['num'], tense)
                obj = o['w']
                sent = f'{subj} {verb} {obj}'
                if 'modal' in formula and banks.get('modal'):
                    sent = f"{subj} {banks['modal'][0]['w']} {v['w']} {obj}"
                if 'attribute' in formula and banks.get('attribute'):
                    sent = f"{sent} ({banks['attribute'][0]['w']})"   # 演示定语混入
                if 'adverbial' in formula and banks.get('adverbial'):
                    sent = f"{sent} {banks['adverbial'][0]['w']}"
                out.append(sent)
    return out

# ---------- 第 3 步：跑演示 + 用户词混入 ----------
print('\n=== 演示：系统原始词库生成的 SVO 句子（取前 4 条）===')
base = gen_svo(['modal'], BANKS, tense='present')
for s in base[:4]:
    print('  ', s)

print('\n=== 用户录入新词 "watermelon"(西瓜) → 混入 object 槽 ===')
BANKS['object'].append({'w': 'watermelon'})   # 用户词入库，机制上只是往槽位词库加一条
mixed = gen_svo(['modal'], BANKS, tense='present')
new = [s for s in mixed if 'watermelon' in s]
for s in new[:4]:
    print('  ', s)
print(f'\n→ 仅因 object 槽多了一个词，瞬间多出 {len(new)} 句「...watermelon」变体，'
      f'语法结构不变，正是你说的"我吃苹果→我吃西瓜"。')
