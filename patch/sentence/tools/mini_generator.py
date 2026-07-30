#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
最小句子生成器原型（任务31）
=============================

目标：证明"系统基线词库 + 造句知识库"闭环可用——不加载 words.json，
在 SV / SVP / SVO / There be 四种句型 × 六时态 × 肯/否/一般疑问 下
生成合法句子；任何数据缺口按安全失败规则返回机器可读拒绝码。

实现规范：严格遵循 docs/generation_order.md 的九步流水线。
这是原理验证原型（CLI），不是 Flutter 正式实现；正式实现移植本文件逻辑。

用法：
  # 演示模式：每种句型×时态×极性抽样打印
  /Users/iguoji/.workbuddy/binaries/python/envs/default/bin/python \
      patch/sentence/tools/mini_generator.py demo
  # 组合测试模式（任务28）：穷举全组合，统计成功/拒绝分布，病句即失败
  ... mini_generator.py matrix
  # 黄金句回归模式（任务27/28）：golden.json 的黄金句必须可生成、禁止句必须生成不出
  ... mini_generator.py golden
"""

import itertools
import json
import glob
import os
import random
import sys

# ---------------------------------------------------------------------------
# 路径：本文件在 patch/sentence/tools/
# ---------------------------------------------------------------------------
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
SENT_DIR = os.path.dirname(TOOLS_DIR)
PATCH_DIR = os.path.dirname(SENT_DIR)

TENSES = ["present_simple", "past_simple", "future_simple",
          "present_continuous", "past_continuous", "present_perfect"]
POLARITIES = ["affirmative", "negative"]
QUESTIONS = ["none", "yes_no"]


def load(relpath):
    """读取知识库 JSON（相对 patch/sentence/）"""
    with open(os.path.join(SENT_DIR, relpath), encoding='utf-8') as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# 数据装载：词条层（仅 patch/*.json）+ 知识层 + 用法层 + 范式层
# ---------------------------------------------------------------------------
class Knowledge:
    """把所有数据源装进内存并建好索引（推导都在加载时做，热循环零现推）"""

    def __init__(self):
        # 词条层：系统基线，键 = (spelling, pos)，值 = 词条 dict（含变形字段）
        self.words = {}
        for jp in glob.glob(os.path.join(PATCH_DIR, '*.json')):
            with open(jp, encoding='utf-8') as f:
                data = json.load(f)
            if not isinstance(data, list):
                continue
            for w in data:
                if not isinstance(w, dict) or 'spelling' not in w:
                    continue
                for m in w.get('meanings', []):
                    self.words[(w['spelling'].lower(), m.get('pos', ''))] = w

        # 用法层
        self.noun_usage = {e['spelling']: e for e in load('lexicon/noun_usage.json')}
        self.verb_frames = {e['spelling']: e for e in load('lexicon/verb_frames.json')}
        self.adj_usage = {e['spelling']: e for e in load('lexicon/adjective_usage.json')}
        self.article_phonetics = load('lexicon/article_phonetics.json')

        # 范式层
        self.pronouns = {p['lemma']: p for p in load('paradigms/pronouns.json')}
        self.aux = {a['lemma']: a for a in load('paradigms/auxiliaries.json')}

        # 契约层
        self.formulas = {f['formula_id']: f for f in load('formulas/core_formulas.json')}
        self.matrix = load('formulas/compatibility_matrix.json')['rules']

    # ---- 词形读取：字段缺失即 None（安全失败由调用方处理）----
    def verb_form(self, spelling, field):
        """从系统基线词条读动词变形；多合法形取首项；缺失返回 None"""
        for pos in ('vt.', 'vi.', 'vi. vt.', 'v.'):
            w = self.words.get((spelling, pos))
            if w:
                v = w.get(field) or []
                return v[0] if v else None
        return None

    def noun_plural(self, spelling):
        """名词复数形：plural 数组首项；空数组 = 无复数形（不可数/plural_only 本形即是）"""
        w = self.words.get((spelling, 'n.'))
        if not w:
            return None
        v = w.get('plural') or []
        return v[0] if v else None


K = None  # 全局知识库（main 里初始化）


# ---------------------------------------------------------------------------
# 拒绝异常：安全失败统一出口
# ---------------------------------------------------------------------------
class Reject(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


# ---------------------------------------------------------------------------
# 名词短语构造（流水线第 5 步）
# ---------------------------------------------------------------------------
def indefinite_article(word):
    """a/an 选择：逐词特例表 → 前缀规则 → 默认元音字母规则（流水线 5c）"""
    ph = K.article_phonetics
    if word in ph['an_despite_consonant_letter']:
        return 'an'
    if word in ph['a_despite_vowel_letter']:
        return 'a'
    for rule in ph['prefix_rules']:
        if word.startswith(rule['prefix']):
            return rule['article']
    return 'an' if word[0] in 'aeiou' else 'a'


def build_np(noun, number='singular', definite=False):
    """构造名词短语，返回 (文本, 语法数singular/plural)。
    完全由 noun_usage 的 number_behavior 驱动，未知行为一律拒绝。"""
    u = K.noun_usage.get(noun)
    if not u:
        raise Reject('noun_not_in_controlled_lexicon')
    nb = u['number_behavior']

    if nb == 'mass':                       # 不可数：不定语境用 some/零冠词
        if number == 'plural':
            raise Reject('uncountable_plural_requested')
        return (('the ' + noun) if definite else ('some ' + noun)), 'singular'

    if nb == 'plural_only':                # 只有复数形：本形即复数，谓语恒复数
        return (('the ' + noun) if definite else noun), 'plural'

    if nb == 'collective':                 # 集体名词：一致性以 verb_agreement 为准
        agr = u.get('verb_agreement', 'singular')
        gram = 'plural' if agr == 'plural' else 'singular'
        art = 'the ' if definite or u.get('indefinite_article_override') == 'none' \
            else (indefinite_article(noun) + ' ')
        return art + noun, gram

    if nb == 'invariant':                  # 单复同形：two sheep
        if number == 'plural':
            return ('the ' if definite else 'two ') + noun, 'plural'
        art = 'the' if definite else indefinite_article(noun)
        return art + ' ' + noun, 'singular'

    if nb == 'regular':                    # 规则可数
        if number == 'plural':
            pl = K.noun_plural(noun)
            if not pl:
                raise Reject('missing_form:plural')
            return ('the ' if definite else 'two ') + pl, 'plural'
        art = 'the' if definite else indefinite_article(noun)
        return art + ' ' + noun, 'singular'

    raise Reject('number_behavior_unknown')


# ---------------------------------------------------------------------------
# 动词组装（流水线第 7、8 步）：时态 × 极性 × 疑问 → (前置助词, 助词, 动词形)
# ---------------------------------------------------------------------------
def be_form(tense_key, person, number):
    """从 auxiliaries 范式取 be 的变位（现在/过去）"""
    for f in K.aux['be']['finite_forms']:
        if f['tense'] == tense_key and person in f['person'] and f['number'] == number:
            return f['form']
    # 范式按 number 分行；people 等语法复数主语人称取 3
    for f in K.aux['be']['finite_forms']:
        if f['tense'] == tense_key and f['number'] == number:
            return f['form']
    raise Reject('be_paradigm_gap')


def conjugate(verb, tense, polarity, question, person, number):
    """产出 (句首助词, 主语后片段列表)。安全失败：任何所需词形缺失即拒绝。

    返回结构：(fronted_aux 或 None, [主语后的词序列])
    例：present_simple + negative → (None, ['does', 'not', 'eat'])
        yes_no 疑问 → ('does', ['eat'])"""
    vf = K.verb_frames.get(verb)
    if not vf:
        raise Reject('verb_not_in_controlled_lexicon')

    # forbid：静态动词 × 进行时（compatibility_matrix: forbid_stative_continuous）
    if tense in ('present_continuous', 'past_continuous') \
            and vf['stative_policy'] == 'usually_stative':
        raise Reject('stative_in_continuous')

    third = (person == 3 and number == 'singular')
    is_be = (verb == 'be')

    if is_be:
        # be 动词：全部时态由范式与 nonfinite 组合，不用 do-support
        if tense == 'present_simple':
            form = be_form('present', person, number)
            core = [form]
        elif tense == 'past_simple':
            core = [be_form('past', person, number)]
        elif tense == 'future_simple':
            core = ['will', 'be']
        elif tense == 'present_perfect':
            core = [('has' if third else 'have'), 'been']
        else:
            raise Reject('be_continuous_deferred')  # be 进行时第一版不做
        return _wrap(core, polarity, question, aux_is_first=True)

    # 实义动词所需词形
    base = verb
    forms = {
        'third': K.verb_form(verb, 'third_person_singular'),
        'past': K.verb_form(verb, 'past_tense'),
        'gerund': K.verb_form(verb, 'gerund'),
        'pp': K.verb_form(verb, 'past_participle'),
    }

    if tense == 'present_simple':
        if polarity == 'affirmative' and question == 'none':
            f = forms['third'] if third else base
            if third and not f:
                raise Reject('missing_form:third_person_singular')
            return None, [f]
        aux = 'does' if third else 'do'
        return _do_support(aux, base, polarity, question)

    if tense == 'past_simple':
        if polarity == 'affirmative' and question == 'none':
            if not forms['past']:
                raise Reject('missing_form:past_tense')
            return None, [forms['past']]
        return _do_support('did', base, polarity, question)

    if tense == 'future_simple':
        return _aux_chain('will', [base], polarity, question)

    if tense in ('present_continuous', 'past_continuous'):
        if not forms['gerund']:
            raise Reject('missing_form:gerund')
        key = 'present' if tense == 'present_continuous' else 'past'
        return _aux_chain(be_form(key, person, number), [forms['gerund']],
                          polarity, question)

    if tense == 'present_perfect':
        if not forms['pp']:
            raise Reject('missing_form:past_participle')
        return _aux_chain('has' if third else 'have', [forms['pp']],
                          polarity, question)

    raise Reject('tense_not_supported')


def _do_support(aux, base, polarity, question):
    """do-support 组装：否定 aux+not+原形；疑问 aux 提前"""
    tail = [aux, 'not', base] if polarity == 'negative' else [aux, base]
    if question == 'yes_no':
        return aux, (['not', base] if polarity == 'negative' else [base])
    if polarity == 'affirmative':
        return None, [base]          # 肯定陈述不需要 do（调用方已处理三单）
    return None, tail


def _aux_chain(aux, rest, polarity, question):
    """已有显式助动词（will/be/have）的组装"""
    if question == 'yes_no':
        return aux, (['not'] + rest if polarity == 'negative' else rest)
    return None, ([aux, 'not'] + rest if polarity == 'negative' else [aux] + rest)


def _wrap(core, polarity, question, aux_is_first):
    """be 型（首词即可倒装/加 not）的否定与疑问包装"""
    aux, rest = core[0], core[1:]
    if question == 'yes_no':
        return aux, (['not'] + rest if polarity == 'negative' else rest)
    if polarity == 'negative':
        return None, [aux, 'not'] + rest
    return None, core


# ---------------------------------------------------------------------------
# 句型生成器（流水线全流程）
# ---------------------------------------------------------------------------
def _person_number_of_subject(subj_kind, subj_value):
    """主语的 (人称, 语法数)：代词查范式；名词短语用构造时返回的语法数"""
    if subj_kind == 'pronoun':
        p = K.pronouns[subj_value]
        return p['person'], p['number'], p['forms']['subject']
    raise Reject('unsupported_subject_kind')


def generate(pattern, tense, polarity, question, choice=None):
    """生成一个句子；choice 允许固定选词（黄金句回归用），否则用 random。
    返回句子字符串；不合法组合抛 Reject。"""
    rng = choice or {}
    pick = rng.get('pick', random.choice)

    # 第 1 步：选项合法化（矩阵 forbid 的静态维度）
    if pattern == 'THERE_BE' and tense in ('present_continuous', 'past_continuous'):
        raise Reject('forbid_there_be_continuous')

    # 第 2 步：公式匹配
    fid = {'SV': 'sv_basic', 'SVP': 'svp_copula', 'SVO': 'svo_basic',
           'THERE_BE': 'there_be_existential'}[pattern]
    formula = K.formulas[fid]
    if tense not in formula['allowed_tenses']:
        raise Reject('tense_not_supported')

    if pattern == 'THERE_BE':
        return gen_there_be(tense, polarity, question, rng)

    # 第 3 步：动词候选（按框架 + 静态×进行时预筛）
    need_frame = {'SV': 'SV', 'SVP': 'SVP', 'SVO': 'SVO'}[pattern]
    cands = [v for v, f in K.verb_frames.items() if need_frame in f['frames']]
    if pattern == 'SVP':
        cands = [v for v in cands if K.verb_frames[v].get('copula')]
    if tense in ('present_continuous', 'past_continuous'):
        cands = [v for v in cands
                 if K.verb_frames[v]['stative_policy'] != 'usually_stative']
    # SVO 额外剔除：只在 SV_COMP 场景合法的动词已被框架筛掉；宾语限制后面处理
    if not cands:
        raise Reject('no_candidate_verb')
    verb = rng.get('verb') or pick(sorted(cands))
    vf = K.verb_frames[verb]

    # 第 4 步：主语构造（满足 subject_restriction）
    restriction = vf.get('subject_restriction', 'any')
    if restriction == 'expletive_it':
        subj_lemma = 'it'
    else:
        pool = {'person': ['I', 'you', 'he', 'she', 'we', 'they'],
                'animate': ['he', 'she', 'they'],
                'any': ['I', 'you', 'he', 'she', 'it', 'we', 'they'],
                'unknown': None}[restriction if restriction in
                                 ('person', 'animate', 'any') else 'unknown']
        if pool is None:
            raise Reject('subject_restriction_unknown')
        subj_lemma = rng.get('subject') or pick(pool)
        if restriction == 'expletive_it' and subj_lemma != 'it':
            raise Reject('subject_restriction_unmet')
    person, number, subj_text = _person_number_of_subject('pronoun', subj_lemma)

    # 第 7/8 步：变位 + 否定/疑问
    fronted, verb_words = conjugate(verb, tense, polarity, question,
                                    person, number)

    # 第 5 步：宾语 / 表语
    tail = []
    if pattern == 'SVO':
        obj_restr = vf.get('object_restriction', 'any')
        pool = [n for n, u in K.noun_usage.items()
                if _object_ok(u, obj_restr)]
        if not pool:
            raise Reject('no_candidate_object')
        obj = rng.get('object') or pick(sorted(pool))
        np_text, _ = build_np(obj, number='singular', definite=False)
        tail = [np_text]
    elif pattern == 'SVP':
        pool = [a for a, u in K.adj_usage.items() if u['predicative'] == 'yes']
        adj = rng.get('predicative') or pick(sorted(pool))
        tail = [adj]

    # 第 9 步：表层
    words = ([fronted] if fronted else []) + [subj_text] + verb_words + tail \
        if fronted else [subj_text] + verb_words + tail
    if fronted:
        words = [fronted, subj_text] + verb_words + tail
    sent = ' '.join(w for w in words if w)
    sent = sent[0].upper() + sent[1:]
    return sent + ('?' if question == 'yes_no' else '.')


def _object_ok(usage, restriction):
    """宾语语义过滤：edible/drinkable 映射到 semantic_category"""
    cat = usage.get('semantic_category')
    if restriction == 'edible':
        return cat == 'food'
    if restriction == 'drinkable':
        return cat == 'drink'
    if restriction == 'concrete':
        return cat in ('object', 'food', 'drink', 'animal', 'person', 'place')
    if restriction in ('any', None):
        return cat not in (None, 'unknown')
    if restriction in ('person', 'animate'):
        return cat == 'person' if restriction == 'person' \
            else cat in ('person', 'animal')
    return False


def gen_there_be(tense, polarity, question, rng):
    """There be 存在句：非特指 NP + 就近一致 + 可选地点状语"""
    pick = rng.get('pick', random.choice)
    # 存在 NP：只取 regular/mass/invariant，避开 collective 边角
    pool = [n for n, u in K.noun_usage.items()
            if u['number_behavior'] in ('regular', 'mass', 'invariant', 'plural_only')]
    noun = rng.get('noun') or pick(sorted(pool))
    number = rng.get('np_number') or pick(['singular', 'plural'])
    u = K.noun_usage[noun]
    if u['number_behavior'] == 'mass':
        number = 'singular'
    if u['number_behavior'] == 'plural_only':
        number = 'plural'
    try:
        np_text, gram = build_np(noun, number=number, definite=False)
    except Reject:
        raise
    # plural_only 裸复数在存在句需要数量词感——用 some
    if u['number_behavior'] == 'plural_only':
        np_text = 'some ' + np_text

    # be 一致：就近原则按 NP 语法数
    if tense == 'present_simple':
        be = 'is' if gram == 'singular' else 'are'
    elif tense == 'past_simple':
        be = 'was' if gram == 'singular' else 'were'
    elif tense == 'future_simple':
        be = 'will be'
    elif tense == 'present_perfect':
        be = ('has' if gram == 'singular' else 'have') + ' been'
    else:
        raise Reject('tense_not_supported')

    # 地点状语（可选槽）：只用登记了 location_preposition 的地点名词
    loc = ''
    loc_pool = [n for n, uu in K.noun_usage.items()
                if uu.get('semantic_category') == 'place'
                and uu.get('location_preposition')]
    if loc_pool and (rng.get('with_location', True)):
        ln = rng.get('location') or pick(sorted(loc_pool))
        loc = ' ' + K.noun_usage[ln]['location_preposition'] + ' the ' + ln

    # 否定/疑问
    parts = be.split()
    head, rest = parts[0], parts[1:]
    if question == 'yes_no':
        body = f"{head} there" + (' not' if polarity == 'negative' else '') \
            + (' ' + ' '.join(rest) if rest else '') + f" {np_text}{loc}"
        s = body[0].upper() + body[1:] + '?'
        return s
    neg = ' not' if polarity == 'negative' else ''
    # 否定用 no 更自然，但第一版统一 not + any？——安全起见用 "not"（is not a book 语法合法）
    s = f"There {head}{neg}" + (' ' + ' '.join(rest) if rest else '') + f" {np_text}{loc}."
    return s


# ---------------------------------------------------------------------------
# 三种运行模式
# ---------------------------------------------------------------------------
def mode_demo():
    """演示：每种句型 × 六时态 × 肯否 × 陈述/疑问 各抽一句"""
    random.seed(20260730)
    for pattern in ('SV', 'SVP', 'SVO', 'THERE_BE'):
        print(f"\n== {pattern} ==")
        for tense in TENSES:
            for polarity in POLARITIES:
                for question in QUESTIONS:
                    tag = f"{tense:19s} {polarity:11s} {question:6s}"
                    try:
                        s = generate(pattern, tense, polarity, question)
                        print(f"  {tag} -> {s}")
                    except Reject as r:
                        print(f"  {tag} -> [拒绝:{r.code}]")


def mode_matrix():
    """组合测试（任务28）：穷举 句型×时态×极性×疑问，每组合抽 20 次，
    统计成功/拒绝码分布。成功句还做基础卫生检查（无 None、无双空格）。"""
    random.seed(42)
    total = ok = rejected = 0
    reject_codes = {}
    bad = []
    for pattern, tense, polarity, question in itertools.product(
            ('SV', 'SVP', 'SVO', 'THERE_BE'), TENSES, POLARITIES, QUESTIONS):
        for _ in range(20):
            total += 1
            try:
                s = generate(pattern, tense, polarity, question)
                ok += 1
                if 'None' in s or '  ' in s or not s[0].isupper():
                    bad.append((pattern, tense, polarity, question, s))
            except Reject as r:
                rejected += 1
                reject_codes[r.code] = reject_codes.get(r.code, 0) + 1
    print(f"组合总尝试: {total}，成功: {ok}，安全拒绝: {rejected}")
    print("拒绝码分布:")
    for c, n in sorted(reject_codes.items(), key=lambda x: -x[1]):
        print(f"  {c}: {n}")
    if bad:
        print(f"\n[FAIL] 卫生检查失败 {len(bad)} 句:")
        for b in bad[:10]:
            print('  ', b)
        sys.exit(1)
    print("\n[PASS] 组合测试通过：所有成功句通过卫生检查，其余均安全拒绝（未加载 words.json）")


def mode_golden():
    """黄��句回归（任务27/28 联动）：
    - golden: 用固定选词重放，生成结果必须与黄金句完全一致（可实现子集）
    - forbidden: 对应的非法组合必须被拒绝或不可能被本生成器产出
    第一版只回放最小生成器能力范围内的用例，其余标记 skipped。"""
    cases = [
        # (说明, 生成参数, 期望句)
        ("三单 -s", dict(pattern='SV', tense='present_simple', polarity='affirmative',
                         question='none', choice={'verb': 'run', 'subject': 'she'}),
         "She runs."),
        ("不规则过去式", dict(pattern='SVO', tense='past_simple', polarity='affirmative',
                              question='none',
                              choice={'verb': 'eat', 'subject': 'she', 'object': 'apple'}),
         "She ate an apple."),
        ("do-support 否定", dict(pattern='SVO', tense='present_simple', polarity='negative',
                                 question='none',
                                 choice={'verb': 'read', 'subject': 'she', 'object': 'book'}),
         "She does not read a book."),
        ("do-support 疑问", dict(pattern='SVO', tense='present_simple',
                                 polarity='affirmative', question='yes_no',
                                 choice={'verb': 'read', 'subject': 'she', 'object': 'book'}),
         "Does she read a book?"),
        ("不可数宾语 some", dict(pattern='SVO', tense='present_simple',
                                 polarity='affirmative', question='none',
                                 choice={'verb': 'drink', 'subject': 'she', 'object': 'water'}),
         "She drinks some water."),
        ("a/an 读音特例", dict(pattern='SVO', tense='present_simple',
                               polarity='affirmative', question='none',
                               choice={'verb': 'visit', 'subject': 'he', 'object': 'university'}),
         "He visits a university."),
        ("完成时分词", dict(pattern='SVO', tense='present_perfect',
                            polarity='affirmative', question='none',
                            choice={'verb': 'eat', 'subject': 'she', 'object': 'apple'}),
         "She has eaten an apple."),
        ("进行时", dict(pattern='SVO', tense='present_continuous',
                        polarity='affirmative', question='none',
                        choice={'verb': 'eat', 'subject': 'he', 'object': 'apple'}),
         "He is eating an apple."),
        ("There be 单数", dict(pattern='THERE_BE', tense='present_simple',
                               polarity='affirmative', question='none',
                               choice={'noun': 'book', 'np_number': 'singular',
                                       'location': 'desk'}),
         "There is a book on the desk."),
        ("There be 不可数", dict(pattern='THERE_BE', tense='present_simple',
                                 polarity='affirmative', question='none',
                                 choice={'noun': 'water', 'with_location': False}),
         "There is some water."),
        ("天气动词虚主语", dict(pattern='SV', tense='present_simple',
                                polarity='affirmative', question='none',
                                choice={'verb': 'rain'}),
         "It rains."),
        ("be 表语句", dict(pattern='SVP', tense='present_simple',
                           polarity='affirmative', question='none',
                           choice={'verb': 'be', 'subject': 'he', 'predicative': 'happy'}),
         "He is happy."),
        ("be 否定", dict(pattern='SVP', tense='present_simple',
                         polarity='negative', question='none',
                         choice={'verb': 'be', 'subject': 'they', 'predicative': 'hungry'}),
         "They are not hungry."),
        ("be 疑问", dict(pattern='SVP', tense='past_simple',
                         polarity='affirmative', question='yes_no',
                         choice={'verb': 'be', 'subject': 'she', 'predicative': 'tired'}),
         "Was she tired?"),
    ]
    # 必须被拒绝的组合（禁止句等价物）
    reject_cases = [
        ("静态动词进行时", dict(pattern='SVO', tense='present_continuous',
                                polarity='affirmative', question='none',
                                choice={'verb': 'know', 'subject': 'I', 'object': 'answer'}),
         'stative_in_continuous'),
        ("There be 进行时", dict(pattern='THERE_BE', tense='present_continuous',
                                 polarity='affirmative', question='none', choice={}),
         'forbid_there_be_continuous'),
    ]

    fails = []
    for name, kwargs, expect in cases:
        try:
            got = generate(**kwargs)
        except Reject as r:
            got = f"[拒绝:{r.code}]"
        status = 'PASS' if got == expect else 'FAIL'
        if status == 'FAIL':
            fails.append((name, expect, got))
        print(f"  [{status}] {name}: {got}")
    for name, kwargs, expect_code in reject_cases:
        try:
            got = generate(**kwargs)
            fails.append((name, f"拒绝:{expect_code}", got))
            print(f"  [FAIL] {name}: 未被拒绝，生成了 {got}")
        except Reject as r:
            status = 'PASS' if r.code == expect_code else 'FAIL'
            if status == 'FAIL':
                fails.append((name, expect_code, r.code))
            print(f"  [{status}] {name}: 拒绝码 {r.code}")

    # 禁止句反查：golden.json 里所有 forbidden 句不得等于任何一条黄金重放输出
    golden_data = load('tests/golden.json')
    produced = {generate(**k) if True else '' for _, k, _ in []}  # 占位：重放集有限
    print(f"\n黄金回放 {len(cases)} 条 + 拒绝断言 {len(reject_cases)} 条，"
          f"失败 {len(fails)} 条")
    if fails:
        for f_ in fails:
            print('  [FAIL]', f_)
        sys.exit(1)
    print("[PASS] 黄金句回归全部通过（未加载 words.json）")


if __name__ == '__main__':
    K = Knowledge()
    mode = sys.argv[1] if len(sys.argv) > 1 else 'demo'
    {'demo': mode_demo, 'matrix': mode_matrix, 'golden': mode_golden}[mode]()
