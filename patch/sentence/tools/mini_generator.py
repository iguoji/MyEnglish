#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
最小句子生成器原型（任务31，整改版）
=============================

目标：证明"系统基线词库 + 造句知识库"闭环可用——不加载 words.json，
在 SV / SVP / SVO / There be 四种句型 × 六时态 × 肯/否/一般疑问 下
生成句子；任何数据缺口按安全失败规则返回机器可读拒绝码。

本文件是原理验证原型（CLI），不是 Flutter 正式实现；正式实现移植本逻辑。
注意：CLI 原型仍在验证"主谓一致 / 真实测试执行 / 自然搭配质量"，
尚不能宣称"100% 无病句"或"可直接翻译成 Dart"——见 docs 完成报告。

运行（标准方式见 requirements.txt）：
  python3 patch/sentence/tools/mini_generator.py demo      # 抽样打印
  python3 patch/sentence/tools/mini_generator.py matrix    # 组合卫生 + 语法校验
  python3 patch/sentence/tools/mini_generator.py golden    # 驱动 tests/golden.json
  python3 patch/sentence/tools/mini_generator.py --help
"""

import argparse
import itertools
import json
import glob
import os
import random
import re
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
# 数据装载：词条层（仅 patch/*.json）+ 知识层 + 用法层 + 范式层 + 搭配层
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

        # 搭配层（P1-4 新增，独立文件，不改动 verb_frames/noun_usage 结构）
        # verb_restrictions: 动词 -> 允许的宾语语义标签列表
        # noun_tags: 名词 -> 额外搭配标签（语义类别仍复用 noun_usage.semantic_category）
        self.colloc = load('lexicon/collocations.json')
        self.verb_restr = self.colloc['verb_restrictions']
        self.noun_tags = self.colloc.get('noun_tags', {})

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
    """从 auxiliaries 范式取 be 的变位（现在/过去）。

    严格按 (tense, person, number) 精确匹配——不回退到“只看 number”，
    否则 you（person=2，单数）会被错误回退到 am。
    范式覆盖全部 6 种 (person, number) 组合：
      I→am/was | you→are/were（单复同形）| he/she/it→is/was | we/they→are/were
    """
    for f in K.aux['be']['finite_forms']:
        if f['tense'] == tense_key and person in f['person'] and f['number'] == number:
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
    """主语的 (人称, 语法数, 主语文本)：代词查范式；其余拒绝"""
    if subj_kind == 'pronoun':
        p = K.pronouns[subj_value]
        return p['person'], p['number'], p['forms']['subject']
    raise Reject('unsupported_subject_kind')


def _object_ok(usage, verb):
    """宾语搭配过滤（P1-4 搭配层）：

    - 动词未在 collocations.verb_restrictions 登记 → 保守返回 False（禁止随机拼接）
    - 名词命中动词允许的任一语义标签即通过：
      标签既可与 noun_usage.semantic_category 相等（food/drink/person/place/object…），
      也可命中 noun_tags 里的细标签（如 readable）
    """
    tags = K.verb_restr.get(verb)
    if not tags:
        return False
    cat = usage.get('semantic_category')
    ntags = K.noun_tags.get(usage['spelling'], [])
    for t in tags:
        if t == cat:
            return True
        if t in ntags:
            return True
    return False


def _generate(pattern, tense, polarity, question, choice=None, full=False):
    """生成一个句子。

    choice 允许固定选词（黄金句回归用），否则用 random。
    返回句子字符串；当 full=True 时返回 (句子, info) 供语法校验使用。
    不合法组合抛 Reject。"""
    rng = choice or {}
    pick = rng.get('pick', random.choice)

    info = dict(pattern=pattern, tense=tense, polarity=polarity, question=question,
                subject=None, person=None, number=None, verb=None,
                is_be=False, object_noun=None, mass_object=False,
                semantic_unnatural=False)

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
        sent, info_there = gen_there_be(tense, polarity, question, rng, full=True)
        info.update(info_there)
        return (sent, info) if full else sent

    # 第 3 步：动词候选（按框架 + 静态×进行时预筛 + 搭配层登记）
    need_frame = {'SV': 'SV', 'SVP': 'SVP', 'SVO': 'SVO'}[pattern]
    cands = [v for v, f in K.verb_frames.items() if need_frame in f['frames']]
    if pattern == 'SVP':
        cands = [v for v in cands if K.verb_frames[v].get('copula')]
    if tense in ('present_continuous', 'past_continuous'):
        cands = [v for v in cands
                 if K.verb_frames[v]['stative_policy'] != 'usually_stative']
    # P1-4：SVO 仅从已登记搭配规则的动词中随机选取，未登记者保守排除
    if pattern == 'SVO':
        cands = [v for v in cands if v in K.verb_restr]
    if not cands:
        raise Reject('no_candidate_verb')
    verb = rng.get('verb') or pick(sorted(cands))
    vf = K.verb_frames[verb]
    info['verb'] = verb
    info['is_be'] = (verb == 'be')

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
    info['subject'] = subj_lemma
    info['person'] = person
    info['number'] = number

    # 第 7/8 步：变位 + 否定/疑问
    fronted, verb_words = conjugate(verb, tense, polarity, question,
                                    person, number)

    # 第 5 步：宾语 / 表语
    tail = []
    if pattern == 'SVO':
        obj_restr = vf.get('object_restriction', 'any')
        pool = [n for n, u in K.noun_usage.items()
                if _object_ok(u, verb)]
        if not pool:
            raise Reject('no_candidate_object')
        obj = rng.get('object') or pick(sorted(pool))
        np_text, _ = build_np(obj, number='singular', definite=False)
        u = K.noun_usage[obj]
        info['object_noun'] = obj
        info['mass_object'] = (u['number_behavior'] == 'mass')
        tail = [np_text]
    elif pattern == 'SVP':
        pool = [a for a, u in K.adj_usage.items() if u['predicative'] == 'yes']
        adj = rng.get('predicative') or pick(sorted(pool))
        tail = [adj]

    # 第 9 步：表层
    if fronted:
        words = [fronted, subj_text] + verb_words + tail
    else:
        words = [subj_text] + verb_words + tail
    sent = ' '.join(w for w in words if w)
    sent = sent[0].upper() + sent[1:]
    sent = sent + ('?' if question == 'yes_no' else '.')
    return (sent, info) if full else sent


def generate(pattern, tense, polarity, question, choice=None):
    """生成句子（仅返回字符串，供精确比对/演示）。"""
    return _generate(pattern, tense, polarity, question, choice=choice, full=False)


def generate_full(pattern, tense, polarity, question, choice=None):
    """生成句子并返回 (句子, info)，供 matrix 语法校验。"""
    return _generate(pattern, tense, polarity, question, choice=choice, full=True)


def gen_there_be(tense, polarity, question, rng, full=False):
    """There be 存在句：非特指 NP + 就近一致 + 可选地点状语"""
    pick = rng.get('pick', random.choice)
    info = dict(pattern='THERE_BE', tense=tense, polarity=polarity,
                question=question, subject='there', person=3, number=None,
                verb='be', is_be=True, object_noun=None,
                mass_object=False, semantic_unnatural=False)
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
    info['number'] = gram
    info['object_noun'] = noun
    info['mass_object'] = (u['number_behavior'] == 'mass')
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
        # 语义自然度启发式：抽象名词（如 health/idea）配地点状语不自然
        if u.get('semantic_category') == 'abstract':
            info['semantic_unnatural'] = True

    # 否定/疑问
    parts = be.split()
    head, rest = parts[0], parts[1:]
    if question == 'yes_no':
        body = f"{head} there" + (' not' if polarity == 'negative' else '') \
            + (' ' + ' '.join(rest) if rest else '') + f" {np_text}{loc}"
        s = body[0].upper() + body[1:] + '?'
        return (s, info) if full else s
    neg = ' not' if polarity == 'negative' else ''
    s = f"There {head}{neg}" + (' ' + ' '.join(rest) if rest else '') + f" {np_text}{loc}."
    return (s, info) if full else s


# ---------------------------------------------------------------------------
# 语法 / 搭配 / 语义 三层校验（供 matrix 使用）
# ---------------------------------------------------------------------------
# be 主谓一致守门正则：直接抓 "Am you / Is we / Was they / Are I ..." 这类错配
_BAD_BE = re.compile(
    r'^(Am|Is|Was)\s+(you|we|they)\b|^(Are|Were)\s+(I|he|she|it)\b')


def check_grammar(sent, info):
    """返回问题清单，每项 = (类别, 码, 句子)。类别：grammar / collocation / semantic。"""
    issues = []
    p, n, t = info['person'], info['number'], info['tense']
    pol, q = info['polarity'], info['question']
    is_be = info['is_be']

    # 1) be 主谓一致（直接守门，独立于 be_form 实现，专门防 "Am you" 回归）
    if _BAD_BE.match(sent):
        issues.append(('grammar', 'be_agreement', sent))

    # 2) do-support 存在性：实义动词一般现在/过去时的否定或疑问必须含 do/does/did
    #    （句首 Do/Does 大写，正则须忽略大小写）
    if not is_be and t in ('present_simple', 'past_simple') \
            and (pol == 'negative' or q == 'yes_no'):
        if not re.search(r'\b(do|does|did)\b', sent, re.IGNORECASE):
            issues.append(('grammar', 'missing_do_support', sent))

    # 3) 三单一般现在肯定：动词须为三单形
    if not is_be and t == 'present_simple' and pol == 'affirmative' \
            and q == 'none' and p == 3 and n == 'singular':
        exp = K.verb_form(info['verb'], 'third_person_singular')
        toks = sent.replace('?', '').replace('.', '').split()
        if len(toks) > 1 and exp and toks[1] != exp:
            issues.append(('grammar', 'third_singular', sent))

    # 4) 冠词 + 不可数：mass 宾语不得出现 a/an
    if info.get('mass_object') and info.get('object_noun') \
            and re.search(r'\b(a|an)\s+' + re.escape(info['object_noun']) + r'\b', sent):
        issues.append(('grammar', 'uncountable_with_article', sent))

    # 5) 语义自然度（启发式，单独归类，不计入语法失败导致构建中断）
    if info.get('semantic_unnatural'):
        issues.append(('semantic', 'there_be_abstract_location', sent))

    return issues


# ---------------------------------------------------------------------------
# 三种运行模式
# ---------------------------------------------------------------------------
def mode_demo():
    """演示：每种句型 × 六时态 × 肯否 × 陈述/疑问 各抽一句（优先可靠搭配）"""
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
    """组合测试（任务28 整改）：穷举 句型×时态×极性×疑问，每组合抽 20 次，
    成功句再做三层校验（表面格式 + 语法/搭配/语义）。任一层失败即记 FAIL。"""
    random.seed(42)
    total = ok = rejected = grammar_fail = colloc_fail = semantic_warn = 0
    reject_codes = {}
    failures = []
    for pattern, tense, polarity, question in itertools.product(
            ('SV', 'SVP', 'SVO', 'THERE_BE'), TENSES, POLARITIES, QUESTIONS):
        for _ in range(20):
            total += 1
            try:
                s, info = generate_full(pattern, tense, polarity, question)
                ok += 1
                # 表面格式卫生
                if 'None' in s or '  ' in s or not s[0].isupper():
                    grammar_fail += 1
                    failures.append(('surface', s,
                                     dict(pattern=pattern, tense=tense,
                                          polarity=polarity, question=question)))
                    continue
                # 三层校验
                issues = check_grammar(s, info)
                for cat, code, sent in issues:
                    if cat == 'grammar':
                        grammar_fail += 1
                        failures.append(('grammar:' + code, sent,
                                         dict(pattern=pattern, tense=tense)))
                    elif cat == 'collocation':
                        colloc_fail += 1
                        failures.append(('collocation:' + code, sent,
                                         dict(pattern=pattern, tense=tense)))
                    elif cat == 'semantic':
                        semantic_warn += 1
            except Reject as r:
                rejected += 1
                reject_codes[r.code] = reject_codes.get(r.code, 0) + 1
    print(f"组合总尝试: {total}，成功: {ok}，安全拒绝: {rejected}")
    print("拒绝码分布:")
    for c, n in sorted(reject_codes.items(), key=lambda x: -x[1]):
        print(f"  {c}: {n}")
    print(f"语法错误: {grammar_fail}，搭配错误: {colloc_fail}，"
          f"语义不自然(仅提示): {semantic_warn}")
    if failures:
        print(f"\n[FAIL] {len(failures)} 句未通过校验:")
        for b in failures[:12]:
            print('  ', b[0], '->', b[1], b[2])
        sys.exit(1)
    print("\n[PASS] matrix 通过：成功句均通过表面格式与语法/搭配校验"
          "（未加载 words.json）。语义不自然项见上方提示。")


def mode_golden():
    """黄金句回归（任务27/28 整改）：直接驱动 tests/golden.json。

    - exec: 可执行的黄金句，必须生成并精确比对 -> PASS/FAIL
    - exec_forbidden: 禁止组合，必须被拒绝且拒绝码匹配 -> PASS/FAIL
    - 其余无 exec/exec_forbidden 的条目 -> SKIP（说明原因，不计入 PASS）
    最终报告明确列出 PASS / FAIL / SKIP 实际数量。"""
    data = load('tests/golden.json')
    npass = nfail = nskip = 0
    fails = []

    for entry in data:
        tid = entry.get('test_id', '?')
        rule = entry.get('rule', '')
        # 可执行黄金句：精确比对
        for case in entry.get('exec', []):
            expect = case['expect']
            kw = {k: case[k] for k in ('pattern', 'tense', 'polarity', 'question')}
            kw['choice'] = case.get('choice', {})
            try:
                got = generate(**kw)
            except Reject as r:
                got = f"[REJECT:{r.code}]"
            if got == expect:
                npass += 1
                print(f"  [PASS] {tid}: {got}")
            else:
                nfail += 1
                fails.append((tid, expect, got))
                print(f"  [FAIL] {tid}: 期望「{expect}」得到「{got}」")
        # 禁止组合：必须被拒绝
        for case in entry.get('exec_forbidden', []):
            code = case['expect_reject']
            kw = {k: case[k] for k in ('pattern', 'tense', 'polarity', 'question')}
            kw['choice'] = case.get('choice', {})
            try:
                got = generate(**kw)
                nfail += 1
                fails.append((tid, f"应拒绝:{code}", got))
                print(f"  [FAIL] {tid}: 未被拒绝，生成了「{got}」")
            except Reject as r:
                if r.code == code:
                    npass += 1
                    print(f"  [PASS] {tid}: 拒绝码 {r.code}")
                else:
                    nfail += 1
                    fails.append((tid, code, r.code))
                    print(f"  [FAIL] {tid}: 期望拒绝 {code}，得到 {r.code}")
        # 无可执行规格 -> SKIP
        if not entry.get('exec') and not entry.get('exec_forbidden'):
            nskip += 1
            reason = entry.get('skip', '生成器第一版不支持该句法特征'
                               '（名词主语/定冠词/被动/双宾/比较级/副词等）')
            print(f"  [SKIP] {tid} ({rule}): {reason}")

    print(f"\n黄金测试：PASS={npass}  FAIL={nfail}  SKIP={nskip}")
    if fails:
        for f_ in fails:
            print('  [FAIL]', f_)
        sys.exit(1)
    print("[PASS] 黄金句测试完成（未加载 words.json）")


# ---------------------------------------------------------------------------
# CLI 入口：argparse（支持 --help / demo / golden / matrix / 未知参数非零退出）
# ---------------------------------------------------------------------------
def main():
    global K
    parser = argparse.ArgumentParser(
        prog='mini_generator.py',
        description='最小句子生成器原型（不加载 words.json）')
    parser.add_argument('mode', nargs='?', default='demo',
                        choices=['demo', 'golden', 'matrix'],
                        help='运行模式：demo（抽样）| golden（驱动 tests/golden.json）'
                             '| matrix（组合 + 语法校验）')
    args = parser.parse_args()
    K = Knowledge()
    {'demo': mode_demo, 'golden': mode_golden, 'matrix': mode_matrix}[args.mode]()


if __name__ == '__main__':
    main()
