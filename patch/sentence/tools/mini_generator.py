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
        self.unresolved_verbs = set(self.colloc.get('unresolved_verbs', []))

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
    - 名词命中动词允许的任一【具体】语义标签即通过：
      标签既可与 noun_usage.semantic_category 相等（food/drink/person/place…），
      也可命中 noun_tags 里的细标签（如 readable）

    collocations.schema.json 已禁止没有筛选能力的通用 object 标签；尚未补齐具体
    规则的动词统一放进 unresolved_verbs，不会进入这里的可运行规则表。
    """
    tags = K.verb_restr.get(verb)
    if not tags:
        return False
    cat = usage.get('semantic_category')
    ntags = K.noun_tags.get(usage['spelling'], [])
    for t in tags:
        if t == cat or t in ntags:
            return True
    return False


def _is_demo_safe_verb(verb):
    """动词是否有已经验证并可运行的宾语限制。

    verb_restrictions 只含已确认规则；待补规则的动词位于 unresolved_verbs，
    不会被此函数放入随机演示池。"""
    return bool(K.verb_restr.get(verb))


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
    # frame_cands：仅按“句型框架”判定，用于 choice 的 verb_frame_unmet 校验
    #             （与进行时/搭配预筛解耦，避免 know（静态动词）在进行时里被误判为 verb_frame_unmet）
    need_frame = {'SV': 'SV', 'SVP': 'SVP', 'SVO': 'SVO'}[pattern]
    frame_cands = [v for v, f in K.verb_frames.items() if need_frame in f['frames']]
    if pattern == 'SVP':
        frame_cands = [v for v in frame_cands if K.verb_frames[v].get('copula')]
    # cands：随机候选池，再叠加 静态×进行时 / 搭配登记 / 具体标签 预筛
    cands = list(frame_cands)
    if tense in ('present_continuous', 'past_continuous'):
        cands = [v for v in cands
                 if K.verb_frames[v]['stative_policy'] != 'usually_stative']
    # P1-4：SVO 仅从已登记搭配规则的动词中随机选取，未登记者保守排除
    if pattern == 'SVO':
        cands = [v for v in cands if v in K.verb_restr]
        # 随机池再收窄：仅保留“有具体语义标签”的动词（排除仅靠通用 'object' 兜底的），
        # 否则随机会造出 play a pencil / help a computer / move pants 之类错搭
        cands = [v for v in cands if _is_demo_safe_verb(v)]
    if not cands:
        raise Reject('no_candidate_verb')
    verb = rng.get('verb') or pick(sorted(cands))
    # P0 修复：choice 指定的动词必须真的落在当前句型框架候选里（与进行时/搭配预筛无关），否则拒绝对齐框架
    if rng.get('verb') and verb not in frame_cands:
        raise Reject('verb_frame_unmet')
    vf = K.verb_frames[verb]
    info['verb'] = verb
    info['is_be'] = (verb == 'be')

    # 第 4 步：主语构造（满足 subject_restriction）
    restriction = vf.get('subject_restriction', 'any')
    if restriction == 'expletive_it':
        # 虚主语动词（rain/snow）主语恒为 it；若通过 choice 强行指定其它主语（如 dog），
        # 必须拒绝，不能静默改回 it（否则禁止句 dog rains 永远测不到）
        if rng.get('subject') is not None and rng.get('subject') != 'it':
            raise Reject('subject_restriction_unmet')
        subj_lemma = 'it'
    else:
        # 主语池按 subject_restriction 分级（越往下越宽）：
        #   person  = 只能是人：I/you/he/she/we/they（排除 it，it 不指人）
        #   animate = 有生命即可：person ∪ {it}（it 可指动物，"It is eating an apple." 合法）
        #             注意 animate 必须是 person 的超集，早前写成 [he,she,they] 比 person 还窄，属数据 bug
        #   any     = 无限制
        pool = {'person': ['I', 'you', 'he', 'she', 'we', 'they'],
                'animate': ['I', 'you', 'he', 'she', 'it', 'we', 'they'],
                'any': ['I', 'you', 'he', 'she', 'it', 'we', 'they'],
                'unknown': None}[restriction if restriction in
                                 ('person', 'animate', 'any') else 'unknown']
        if pool is None:
            raise Reject('subject_restriction_unknown')
        subj_lemma = rng.get('subject') or pick(pool)
        # P0 修复：choice 指定的主语必须符合该动词的主语限制，否则拒绝
        if rng.get('subject') and subj_lemma not in pool:
            raise Reject('subject_restriction_unmet')
    # 虚主语动词（rain/snow）若被强行指定非 it 主语，同样拒绝
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
        # P0 修复：choice 指定的宾语必须落在搭配过滤后的宾语池，否则拒绝（eat+desk / read+deer 等）
        if rng.get('object') and obj not in pool:
            raise Reject('object_restriction_unmet')
        np_text, _ = build_np(obj, number='singular', definite=False)
        u = K.noun_usage[obj]
        info['object_noun'] = obj
        info['mass_object'] = (u['number_behavior'] == 'mass')
        tail = [np_text]
    elif pattern == 'SVP':
        pool = [a for a, u in K.adj_usage.items() if u['predicative'] == 'yes']
        adj = rng.get('predicative') or pick(sorted(pool))
        # P0 修复：choice 指定的表语必须真的可作表语（在形容词表语池里），否则拒绝
        if rng.get('predicative') and adj not in pool:
            raise Reject('predicative_not_allowed')
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
    # P0 修复：choice 指定的存在句名词必须落在合法存在名词池
    if rng.get('noun') and noun not in pool:
        raise Reject('there_be_noun_unmet')
    number = rng.get('np_number') or pick(['singular', 'plural'])
    if rng.get('np_number') and number not in ('singular', 'plural'):
        raise Reject('there_be_number_unmet')
    u = K.noun_usage[noun]
    # choice 是黄金测试和未来调用端的“精确请求”。不可数名词要求复数、
    # plural_only 名词要求单数时必须明确拒绝，不能静默改写成另一种数量。
    if rng.get('np_number') == 'plural' and u['number_behavior'] == 'mass':
        raise Reject('there_be_number_unmet')
    if rng.get('np_number') == 'singular' and u['number_behavior'] == 'plural_only':
        raise Reject('there_be_number_unmet')
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

    # 地点状语（可选槽）：判定依据是"有没有登记 location_preposition"，
    # 而不是 semantic_category 是否为 place —— desk/table/chair/box/bag 属 object 类，
    # 但都登记了 on/in，"There is a book on the desk." 完全合法，不能被类别过滤误杀。
    loc = ''
    loc_pool = [n for n, uu in K.noun_usage.items()
                if uu.get('location_preposition')]
    if loc_pool and (rng.get('with_location', True)):
        ln = rng.get('location') or pick(sorted(loc_pool))
        # P0 修复：choice 指定地点必须符合地点介词规则池
        if rng.get('location') and ln not in loc_pool:
            raise Reject('there_be_location_unmet')
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
# 语法 / 搭配 / 语义 三层校验（供 matrix / golden / selftest 使用）
# ---------------------------------------------------------------------------
# 【2026-07-30 重构】旧版检查器按固定下标猜成分（默认句子第 2 个词就是动词），
# 一遇到名词短语主语（The dog runs）就整体错位。现已全部改为：
#
#   句子文本 --> analyzer.Analyzer.analyze() --> Analysis（结构事实）
#            --> check_grammar 只消费 Analysis，自己一个下标都不数
#
# 调用方传进来的 info 只做一件事：对账。
# 也就是说 info 不再是"结论的依据"，而是"被怀疑的对象"——
# 谁要是把 She likes music. 标成 present_continuous 想骗出 stative 错误，
# 对账阶段就会先报 analysis_surface_mismatch，不给它蒙混过关的机会。
#
# 用 PHP 的话说：以前是「前端传什么就信什么」，现在是「后端重新解析请求体，
# 再拿前端声明的字段跟解析结果做一次 diff，不一致直接 422」。
# ---------------------------------------------------------------------------

# 完整 be 变位表：校验器自带，独立于生成器 be_form() 的实现，
# 专门防"两边一起写错仍 PASS"。覆盖全部 (tense_key, person, number)。
BE_TABLE = {
    ('present', 1, 'singular'): 'am', ('present', 2, 'singular'): 'are',
    ('present', 3, 'singular'): 'is',  ('present', 1, 'plural'): 'are',
    ('present', 2, 'plural'): 'are',   ('present', 3, 'plural'): 'are',
    ('past', 1, 'singular'): 'was',   ('past', 2, 'singular'): 'were',
    ('past', 3, 'singular'): 'was',   ('past', 1, 'plural'): 'were',
    ('past', 2, 'plural'): 'were',     ('past', 3, 'plural'): 'were',
}
# be 的全部限定形（判断"是不是被动语态"时要用）
_BE_SURFACES = {'am', 'is', 'are', 'was', 'were', 'been', 'being', 'be'}
# 与格/目标类介词：wrong_fixed_preposition 只在这两个介词之间互判，
# 避免把 "They wait in the garden."（地点状语）误判成介词用错。
_GOAL_PREPS = {'to', 'for'}

_ANALYZER = None            # 分析器单例
_ANALYZER_K = None          # 建这个分析器时用的 Knowledge，换库要重建


def _analyzer():
    """惰性构造分析器。

    相当于 PHP 里「第一次请求时把配置读进 APCu，后续请求直接命中缓存」。
    索引建一次就够了，别在每句校验里重复建。
    """
    global _ANALYZER, _ANALYZER_K
    if _ANALYZER is None or _ANALYZER_K is not K:
        if TOOLS_DIR not in sys.path:
            sys.path.insert(0, TOOLS_DIR)
        from analyzer import Analyzer
        _ANALYZER = Analyzer(K)
        _ANALYZER_K = K
    return _ANALYZER


def _check_collocation(verb, noun):
    """校验器侧的宾语搭配检查（独立于生成器 _object_ok，复用同一份数据但独立判定）。
    只接受 schema 已验证过的具体标签，避免错搭放行。"""
    tags = K.verb_restr.get(verb)
    if not tags:
        return False
    u = K.noun_usage.get(noun)
    if not u:
        return False
    cat = u.get('semantic_category')
    ntags = K.noun_tags.get(noun, [])
    for t in tags:
        if t == cat or t in ntags:
            return True
    return False


def _agreement_code(head, default):
    """主谓一致出错时，按主语中心词的名词类别挑更精确的错误码。

    同样是"谓语的数不对"，成因却不同，报出来的码也应该不同：
        police  -> 集体名词恒复数            -> collective_agreement_violation
        news    -> 形似复数实为单数          -> false_plural_form
        scissors-> 只有复数形，谓语恒复数    -> plural_only_agreement_violation
        其它    -> 普通主谓不一致            -> default（be_agreement / third_singular ...）
    判据全部来自 noun_usage.number_behavior，不硬编码词表：
    今后往词库里加 trousers，这里自动生效。
    """
    u = K.noun_usage.get(head or '')
    if not u:
        return default
    nb = u.get('number_behavior')
    if nb == 'collective':
        return 'collective_agreement_violation'
    if nb == 'mass' and (head or '').endswith('s'):
        return 'false_plural_form'
    if nb == 'plural_only':
        return 'plural_only_agreement_violation'
    return default


def _lexical_verb(a):
    """取句子的"实义动词原形"。

    复合时态里实义动词在 main_verb（has eaten -> eat）；
    简单时态里限定动词本身就是实义动词（She reads -> read）。
    be / have / do / 情态动词这些纯助动词不算实义动词，返回 None。
    """
    if a.main_verb_lemma:
        return a.main_verb_lemma
    if a.finite_verb_form_tag in ('be', 'have', 'do', 'modal'):
        return None
    return a.finite_verb_lemma


def _subject_semantic_ok(restriction, a):
    """主语是否满足动词的 subject_restriction。

    数据来自 verb_frames.subject_restriction + noun_usage.semantic_category：
        expletive_it  只能是虚主语 it        （It rains. / *The dog rains.）
        person        必须是人               （read / buy）
        animate       人或动物               （listen）
    词库里查不到的名词一律放行（安全失败：不下没有依据的结论）。
    """
    head = a.subject_head
    if not head:
        return True
    if restriction == 'expletive_it':
        return a.subject_is_pronoun and head == 'it'
    if a.subject_is_pronoun:
        # 人称代词：除 it 外都当作指人
        if restriction in ('person', 'animate'):
            return head != 'it'
        return True
    u = K.noun_usage.get(head)
    if not u:
        return True
    cat = u.get('semantic_category')
    if restriction == 'person':
        return cat == 'person'
    if restriction == 'animate':
        return cat in ('person', 'animal')
    return True


def _there_be_checks(a, az, sent, issues):
    """存在句 There be 专用校验：就近一致 + 定指限制 + 禁进行时。

    分析器对 THERE_BE 只判到"形式主语是 there"就返回了（存在主体不是句法主语），
    所以这里自己用 parse_np 把 be 后面那个名词短语切出来——
    切法与分析器完全同源（同一个 parse_np），不是另写一套正则。
    """
    if a.pattern != 'THERE_BE':
        return
    low = a.lower
    # 1) There is being ... —— 存在句不进行时
    if any(s.lower() == 'being' for s in a.auxiliary_surfaces):
        issues.append(('grammar', 'forbid_there_be_continuous', sent))
    # 2) 将来时（will be）没有数标记，不判一致
    if 'will' in low:
        return
    # 3) 取数标记：is/was/has = 单数，are/were/have = 复数
    sg, pl = {'is', 'was', 'has'}, {'are', 'were', 'have'}
    mark_num = mark_i = None
    for i, w in enumerate(low):
        if w in sg:
            mark_i, mark_num = i, 'singular'
            break
        if w in pl:
            mark_i, mark_num = i, 'plural'
            break
    if mark_i is None:
        return
    # 4) 就近原则：从最后一个助动词之后开始，切出第一个名词短语
    start = (max(a.auxiliary_indices) + 1) if a.auxiliary_indices else mark_i + 1
    np = None
    j = start
    while j < len(a.tokens) and np is None:
        if low[j] == 'not':                 # 跳过否定词：There is not a book
            j += 1
            continue
        np = az.parse_np(a.tokens, j)
        if np is None:
            j += 1
    if np is None:
        return
    # 5) 定指限制：存在句默认引入新信息，不能直接用 the
    if (np.get('determiner') or '') == 'the':
        issues.append(('grammar', 'definite_np_rejected', sent))
    # 6) 就近一致：NP 的数必须与数标记一致（数不明 / both 时不下结论）
    num = np.get('number')
    if num in ('singular', 'plural') and num != mark_num:
        issues.append(('grammar', 'existential_agreement_violation', sent))


def check_grammar(sent, info=None):
    """返回问题清单，每项 = (类别, 码, 句子)。

    类别：structure / grammar / collocation / semantic
    - structure   结构信息与句面对不上（analysis_surface_mismatch），一票否决
    - grammar     语法错
    - collocation 搭配错（动宾语义限制）
    - semantic    自然度提示（不判失败，仅提示）

    info 可以为 None。传了就参与对账，不参与判定。
    """
    issues = []
    az = _analyzer()
    a = az.analyze(sent)

    # ---- 0) 结构自校验 + 声明对账（用户要求的硬门槛）--------------------
    # 分析器自己算出来的下标必须真的指向那个词；主语文本必须能原样拼回来。
    if not a.surface_ok:
        return [('structure', 'analysis_surface_mismatch', sent)]
    if info:
        from analyzer import verify_declaration
        bad = verify_declaration(a, info)
        if bad:
            # 结构都对不上，后面任何语法结论都是空中楼阁，直接短路返回
            return [('structure', 'analysis_surface_mismatch', sent)]

    low = a.lower
    lex = _lexical_verb(a)
    frame = K.verb_frames.get(lex) if lex else None
    # 主语的数可靠吗？None（线索不足）和 both（sheep 这类）都不下一致性结论
    num_known = a.subject_number in ('singular', 'plural')
    is_3sg = (a.subject_person == 3 and a.subject_number == 'singular')

    # ---- 1) 主谓一致 ----------------------------------------------------
    # 1a) be 作限定动词：查完整 BE_TABLE
    if a.finite_verb_lemma == 'be' and a.subject_person and num_known \
            and a.tense_key and not a.subject_is_expletive:
        expected = BE_TABLE[(a.tense_key, a.subject_person, a.subject_number)]
        if (a.finite_verb_surface or '').lower() != expected:
            issues.append(('grammar',
                           _agreement_code(a.subject_head, 'be_agreement'), sent))

    # 1b) 缺系动词：有主语、有形容词，却根本没有限定动词（You happy.）
    if a.finite_verb_lemma is None and a.subject_span:
        nxt_i = a.subject_span[1]
        if nxt_i < len(low) and (az.is_adjective(low[nxt_i])
                                 or az.is_determiner(low[nxt_i])
                                 or az.is_noun_surface(low[nxt_i])):
            issues.append(('grammar', 'missing_copula', sent))

    # 1c) have 作完成时助动词：has / have 要跟主语一致
    if a.tense == 'present_perfect' and a.finite_verb_lemma == 'have' \
            and a.subject_person and num_known:
        expected = 'has' if is_3sg else 'have'
        if (a.finite_verb_surface or '').lower() != expected:
            issues.append(('grammar',
                           _agreement_code(a.subject_head, 'have_agreement'), sent))

    # 1d) 实义动词一般现在时（没有助动词）：三单 / 非三单
    if a.tense == 'present_simple' and not a.auxiliary_surfaces and lex \
            and a.pattern != 'IMPERATIVE' and a.subject_person and num_known:
        surface = (a.finite_verb_surface or '').lower()
        if is_3sg:
            expected = K.verb_form(lex, 'third_person_singular')
            if expected and surface != expected:
                issues.append(('grammar',
                               _agreement_code(a.subject_head, 'third_singular'),
                               sent))
        else:
            # 非三单必须用原形；写成三单形（The dogs runs.）同样是不一致
            if surface != lex:
                issues.append(('grammar',
                               _agreement_code(a.subject_head,
                                               'subject_verb_agreement'), sent))

    # ---- 2) 存在句 ------------------------------------------------------
    _there_be_checks(a, az, sent, issues)

    # ---- 3) do-support --------------------------------------------------
    # 一般现在/过去时的 not 否定与一般疑问句必须借助 do/does/did。
    # 注意：never / seldom 这类否定义副词不触发 do-support（She never eats meat. 是对的），
    # 所以判据是"句面上真的出现了 not"，而不是分析器算出来的 polarity。
    if a.tense in ('present_simple', 'past_simple') and lex \
            and a.pattern != 'IMPERATIVE':
        needs_do = (a.question == 'yes_no') or ('not' in low)
        if needs_do:
            do_pos = [i for i, s in zip(a.auxiliary_indices, a.auxiliary_surfaces)
                      if s.lower() in ('do', 'does', 'did')]
            if not do_pos:
                issues.append(('grammar', 'missing_do_support', sent))
            else:
                actual = a.tokens[do_pos[0]].lower()
                if a.tense == 'past_simple':
                    expected = 'did'
                else:
                    expected = 'does' if is_3sg else 'do'
                if num_known and actual != expected:
                    issues.append(('grammar',
                                   _agreement_code(a.subject_head, 'do_agreement'),
                                   sent))
                # do 之后必须是动词原形（Does she reads / Did she ate 都是错的）
                if a.main_verb_form_tag and a.main_verb_form_tag != 'base':
                    issues.append(('grammar', 'double_inflection_after_do', sent))
    # 倒装疑问句却没有助动词：Reads she books?
    # 分析器会把它当成祈使句（动词开头），但祈使句不带问号，据此识别。
    if a.pattern == 'IMPERATIVE' and a.has_question_mark:
        issues.append(('grammar', 'missing_do_support', sent))

    # ---- 4) 动词形态 ----------------------------------------------------
    # 4a) 一般过去时必须用词库里的过去式，不能机械加 -ed
    if a.tense == 'past_simple' and not a.auxiliary_surfaces and lex \
            and a.pattern != 'IMPERATIVE':
        expected = K.verb_form(lex, 'past_tense')
        if expected and (a.finite_verb_surface or '').lower() != expected:
            issues.append(('grammar', 'mechanical_ed_on_irregular', sent))
    # 4b) 完成时必须用过去分词，不能用过去式
    if a.tense in ('present_perfect', 'past_perfect') and a.main_verb_lemma:
        pp = K.verb_form(a.main_verb_lemma, 'past_participle')
        past = K.verb_form(a.main_verb_lemma, 'past_tense')
        actual = (a.main_verb_surface or '').lower()
        if pp and actual != pp:
            code = 'past_tense_as_participle' if actual == past \
                else 'mechanical_ed_on_irregular'
            issues.append(('grammar', code, sent))

    # ---- 5) 名词短语层 --------------------------------------------------
    # 遍历句中每个名词短语（主语 NP 也在里面），逐个查 noun_usage。
    from analyzer import CARDINALS
    for np in a.noun_phrases:
        head = np.get('head')
        det = (np.get('determiner') or '').lower()
        u = K.noun_usage.get(head)
        if u:
            nb = u.get('number_behavior')
            if nb == 'mass':
                if det in ('a', 'an'):
                    issues.append(('grammar',
                                   'uncountable_with_indefinite_article', sent))
                if det in CARDINALS:
                    issues.append(('grammar', 'uncountable_with_numeral', sent))
                elif np.get('malformed_plural'):
                    issues.append(('grammar', 'uncountable_plural_form', sent))
            elif nb == 'invariant' and np.get('malformed_plural'):
                # two sheeps：单复同形的名词被机械加了 -s
                issues.append(('grammar', 'mechanical_plural_on_invariant', sent))
            elif nb == 'plural_only' and det in ('a', 'an'):
                # a scissors：只有复数形的名词不能用不定冠词，要 a pair of
                issues.append(('grammar',
                               'plural_only_with_indefinite_article', sent))
        # 冠词音系：a/an 按后面那个词的读音选，不能只看首字母
        if det in ('a', 'an'):
            s0, e0 = np['span']
            if s0 + 1 < e0:
                nxt = low[s0 + 1]
                if indefinite_article(nxt) != det:
                    issues.append(('grammar', 'article_phonetic_exception', sent))
        # 定语形容词：attributive == 'no' 的词不能放在名词前（*an afraid child）
        for _idx, adj_lemma in (np.get('adjectives') or []):
            au = K.adj_usage.get(adj_lemma)
            if au and au.get('attributive') == 'no':
                issues.append(('grammar', 'adjective_predicative_only', sent))

    # ---- 6) 表语与形容词形态 --------------------------------------------
    pred = a.predicative
    if pred:
        if a.predicative_form_tag == 'adverb':
            # 副词占了表语位。但只有方式副词才算错——
            # here / there 这类地点副词作表语是合法的（The police are here.）。
            cat = (az.adv_usage.get(pred) or {}).get('category')
            if cat == 'manner':
                issues.append(('grammar', 'adverb_as_predicative', sent))
        else:
            au = K.adj_usage.get(pred)
            if au:
                if au.get('predicative') == 'no':
                    issues.append(('grammar', 'adjective_attributive_only', sent))
                grad = au.get('gradability')
                strategy = au.get('comparison_strategy')
                # 6a) 修饰这个表语的程度副词
                for d in a.degree_modifiers:
                    if d.get('target_index') != a.predicative_index:
                        continue
                    w = d['word']
                    if grad == 'usually_ungradable':
                        issues.append((
                            'grammar',
                            'ungradable_with_comparative' if w in ('more', 'most')
                            else 'ungradable_with_degree', sent))
                    elif w in ('more', 'most') and strategy == 'inflectional':
                        # good 走屈折比较级（better），不能用 more good
                        issues.append(('grammar',
                                       'periphrastic_on_inflectional', sent))
                    if w == 'enough' and d.get('target_kind') == 'adjective':
                        # enough 修饰形容词必须后置：big enough，不能 enough big
                        issues.append(('grammar', 'enough_preposed', sent))
                # 6b) 机械比较级：gooder / biger
                tag = a.predicative_form_tag or ''
                if tag.endswith('_malformed'):
                    field = 'superlative' if tag.startswith('superlative') \
                        else 'comparative'
                    forms = au.get(field) or []
                    expected = forms[0] if forms else None
                    if expected:
                        # 期望形是"末字母双写 + er/est"（bigger/biggest）说明
                        # 错在没双写辅音；否则说明这个词根本是不规则比较级（better）。
                        suffix = 'est' if field == 'superlative' else 'er'
                        # 注意：pred 是形容词原形（lemma="big"），但用户写的是错形
                        # 表面 biger，必须用表面形做"剥后缀 + 双写"的几何运算。
                        # 先剥掉误加的后缀（biger -> big），再补"末辅音双写 + er"
                        # 得到正确形（big -> bigger）。若期望形恰等于这个双写形，
                        # 说明错在没双写；否则说明该词本来走不规则比较级
                        # （good -> better），用户却机械加了 er。
                        pred_surf = a.predicative_surface or pred
                        base = pred_surf[: -len(suffix)]
                        doubled = base + base[-1] + suffix
                        issues.append((
                            'grammar',
                            'missing_consonant_doubling' if expected == doubled
                            else 'mechanical_er_on_irregular', sent))

    # ---- 7) 动词框架层 --------------------------------------------------
    if frame:
        # 7a) 静态动词不进进行时
        if frame.get('stative_policy') == 'usually_stative' \
                and a.tense in ('present_continuous', 'past_continuous'):
            issues.append(('grammar', 'stative_in_continuous', sent))
        # 7b) 不允许被动的动词却出现 be + 过去分词
        if frame.get('allows_passive') == 'no' \
                and a.main_verb_form_tag in ('pp', 'past') \
                and any(s.lower() in _BE_SURFACES for s in a.auxiliary_surfaces):
            issues.append(('grammar', 'passive_not_allowed', sent))
        # 7c) 主语语义限制（rain 只能配虚主语 it）
        sr = frame.get('subject_restriction')
        if sr and a.pattern != 'IMPERATIVE' and not a.subject_is_expletive \
                and a.subject_head and not _subject_semantic_ok(sr, a):
            issues.append(('grammar', 'subject_restriction_unmet', sent))
        # 7d) 补语类型：enjoy 只接动名词、make 只接不带 to 的不定式
        allowed = frame.get('complement_types')
        if a.complement and allowed and a.complement['type'] not in allowed:
            code = 'to_infinitive_after_causative' \
                if (a.complement['type'] == 'to_infinitive'
                    and 'bare_infinitive' in allowed) else 'complement_type_mismatch'
            issues.append(('grammar', code, sent))
        # 7e) 固定介词：listen to / wait for
        fixed = frame.get('fixed_preposition')
        if fixed:
            if a.preposition and a.preposition != fixed \
                    and a.preposition in _GOAL_PREPS and fixed in _GOAL_PREPS:
                issues.append(('grammar', 'wrong_fixed_preposition', sent))
            elif a.pattern == 'SVO' and 'SVO' not in (frame.get('frames') or []):
                # 该动词没有及物用法，却直接跟了个宾语 -> 漏了固定介词
                issues.append(('grammar', 'missing_fixed_preposition', sent))
        # 7f) 双宾与格
        dative = frame.get('dative_alternation')
        if dative:
            if a.preposition in _GOAL_PREPS and a.preposition != dative:
                issues.append(('grammar', 'wrong_dative_preposition', sent))
            if a.pattern == 'SVOO' and not a.preposition and len(a.objects) == 2:
                def _recipient(x):
                    if x in az.pronoun_object_forms:
                        return True
                    nu = K.noun_usage.get(x) or {}
                    return nu.get('semantic_category') == 'person'
                if _recipient(a.objects[1]) and not _recipient(a.objects[0]):
                    # 无介词双宾语必须"人在前、物在后"
                    issues.append(('grammar', 'dative_order_violation', sent))
        # 7g) 宾语语义搭配（只有动词在 collocations 里登记了限制才判）
        if a.pattern == 'SVO' and a.objects and lex in K.verb_restr \
                and K.noun_usage.get(a.objects[0]):
            if not _check_collocation(lex, a.objects[0]):
                issues.append(('collocation', 'object_restriction_unmet', sent))

    # ---- 8) 副词位置 ----------------------------------------------------
    # 8a) 程度副词不能直接修饰动词（*I very like it. 要用 very much 且后置）
    for d in a.degree_modifiers:
        if d.get('target_kind') == 'verb':
            issues.append(('grammar', 'degree_adverb_on_verb', sent))
    # 8b) 频度副词不能出现在主语之前
    adv_by_index = {d['index']: d for d in a.adverbs}
    for i in a.leading_adverbs:
        if (adv_by_index.get(i) or {}).get('category') == 'frequency':
            issues.append(('grammar', 'frequency_adverb_front_disallowed', sent))
    # 8c) 频度副词不能卡在动词与宾语之间（*She reads always books.）
    vidx = a.main_verb_token_index if a.main_verb_token_index is not None \
        else a.finite_verb_token_index
    if vidx is not None and a.noun_phrases:
        after = [np['span'][0] for np in a.noun_phrases if np['span'][0] > vidx]
        if after:
            obj_start = min(after)
            for d in a.adverbs:
                if d.get('category') == 'frequency' and vidx < d['index'] < obj_start:
                    issues.append(('grammar', 'adverb_between_verb_object', sent))

    # ---- 9) 祈使句 ------------------------------------------------------
    if a.pattern == 'IMPERATIVE' and not a.has_question_mark \
            and a.finite_verb_form_tag != 'base':
        issues.append(('grammar', 'inflected_imperative', sent))

    # ---- 10) 双重否定 ---------------------------------------------------
    from analyzer import NEGATIVE_ADVERBS
    if 'not' in low and any(w in NEGATIVE_ADVERBS for w in low):
        issues.append(('grammar', 'double_negative', sent))

    # ---- 11) 语义自然度（生成器侧启发式，单独归类，不计入语法失败）-------
    if info and info.get('semantic_unnatural'):
        issues.append(('semantic', 'there_be_abstract_location', sent))

    # 去重：同一条错误可能被两条路径命中（例如不可数 + 数词），只报一次
    seen, uniq = set(), []
    for it in issues:
        if it[:2] in seen:
            continue
        seen.add(it[:2])
        uniq.append(it)
    return uniq


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
    # 禁止句按 (test_id, sentence) 建立身份，避免“组里执行过一条”掩盖其它句子没跑。
    # exec_forbidden 验证生成器拒绝路径；forbidden.check_info 验证独立检查器。
    forb_declared = set()
    forb_executed = set()

    for entry in data:
        tid = entry.get('test_id', '?')
        rule = entry.get('rule', '')
        forbidden_by_sentence = {
            item['sentence']: item for item in entry.get('forbidden', [])
        }
        for sentence in forbidden_by_sentence:
            forb_declared.add((tid, sentence))
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
            linked_sentence = case.get('forbidden_sentence')
            if linked_sentence:
                key = (tid, linked_sentence)
                if linked_sentence not in forbidden_by_sentence:
                    nfail += 1
                    fails.append((tid, 'forbidden_sentence 必须引用本组 forbidden',
                                  linked_sentence))
                    print(f"  [FAIL] {tid}: exec_forbidden 引用了未声明句子「{linked_sentence}」")
                    continue
                forb_executed.add(key)
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

        # 检查器型禁止句：直接把声明的错误句交给独立检查器，必须命中 reason。
        for sentence, item in forbidden_by_sentence.items():
            check_info = item.get('check_info')
            if not check_info:
                continue
            forb_executed.add((tid, sentence))
            full = dict(pattern='X', tense='present_simple',
                        polarity='affirmative', question='none', is_be=False,
                        person=None, number=None, verb=None, object_noun=None,
                        mass_object=False, predicative=None,
                        semantic_unnatural=False)
            full.update(check_info)
            issues = check_grammar(sentence, full)
            codes = [code for _, code, _ in issues]
            expected = item['reason']
            if expected in codes:
                npass += 1
                print(f"  [PASS] {tid}: 检查器拒绝「{sentence}」-> {expected}")
            else:
                nfail += 1
                fails.append((tid, expected, codes))
                print(f"  [FAIL] {tid}: 禁止句「{sentence}」期望 {expected}，得到 {codes}")
        # 无可执行规格 -> SKIP
        if not entry.get('exec') and not entry.get('exec_forbidden'):
            nskip += 1
            reason = entry.get('skip', '生成器第一版不支持该句法特征'
                               '（名词主语/定冠词/被动/双宾/比较级/副词等）')
            print(f"  [SKIP] {tid} ({rule}): {reason}")

    print(f"\n黄金测试：PASS={npass}  FAIL={nfail}  SKIP={nskip}")
    unexecuted = sorted(forb_declared - forb_executed)
    print(f"禁止句统计：声明 {len(forb_declared)} 条，已执行 {len(forb_executed)} 条，"
          f"未执行 {len(unexecuted)} 条")
    if unexecuted:
        print("  未执行禁止句（均须保留到对应句法能力实现后补测）：")
        for group, sentence in unexecuted:
            print(f"    - {group}: {sentence}")
    if fails:
        for f_ in fails:
            print('  [FAIL]', f_)
        sys.exit(1)
    print("[PASS] 黄金句测试完成（未加载 words.json）")


# ---------------------------------------------------------------------------
# 检查器自检（P1 整改）：用人工构造的错误句证明 check_grammar 能独立发现错误，
# 而不只是复检生成器输出；并反向验证正确句不被误报。任一条未通过即非零退出。
# ---------------------------------------------------------------------------
def mode_checker_selftest():
    base = dict(pattern='X', polarity='affirmative', question='none',
                is_be=False, person=None, number=None,
                verb=None, object_noun=None, mass_object=False,
                semantic_unnatural=False)
    # (句子, info 覆盖, 期望类别, 期望码)
    cases = [
        # be 主谓一致：代词在前（You am / He are / I is / We was）与在后（Is I / Am he）都覆盖
        ("You am happy.", dict(tense='present_simple', is_be=True), 'grammar', 'be_agreement'),
        ("He are happy.", dict(tense='present_simple', is_be=True), 'grammar', 'be_agreement'),
        ("I is happy.", dict(tense='present_simple', is_be=True), 'grammar', 'be_agreement'),
        ("We was happy.", dict(tense='past_simple', is_be=True), 'grammar', 'be_agreement'),
        ("Is I happy?", dict(tense='present_simple', is_be=True, question='yes_no'), 'grammar', 'be_agreement'),
        ("Am he happy?", dict(tense='present_simple', is_be=True, question='yes_no'), 'grammar', 'be_agreement'),
        # 存在句就近一致：单数标记配复数 NP、复数标记配单数 NP 都要抓到
        ("There is two books on the desk.",
         dict(tense='present_simple', pattern='THERE_BE', is_be=True),
         'grammar', 'existential_agreement_violation'),
        ("There were a book on the desk.",
         dict(tense='past_simple', pattern='THERE_BE', is_be=True),
         'grammar', 'existential_agreement_violation'),
        # 宾语搭配
        ("He eats a desk.", dict(tense='present_simple', pattern='SVO', verb='eat', object_noun='desk'), 'collocation', 'object_restriction_unmet'),
        # do-support 缺失
        ("She reads not books.", dict(tense='present_simple', polarity='negative', verb='read'), 'grammar', 'missing_do_support'),
        # 三单缺失
        ("He run.", dict(tense='present_simple', person=3, number='singular', verb='run'), 'grammar', 'third_singular'),
        # 缺少系动词、do/does 主谓一致、助动词后的动词原形。
        ("You happy.", dict(tense='present_simple', pattern='SVP', is_be=True),
         'grammar', 'missing_copula'),
        ("Do she read a book?", dict(tense='present_simple', pattern='SVO',
                                     question='yes_no', verb='read', object_noun='book'),
         'grammar', 'do_agreement'),
        ("Does they read a book?", dict(tense='present_simple', pattern='SVO',
                                        question='yes_no', verb='read', object_noun='book'),
         'grammar', 'do_agreement'),
        ("Did she ate an apple?", dict(tense='past_simple', pattern='SVO',
                                       question='yes_no', verb='eat', object_noun='apple'),
         'grammar', 'double_inflection_after_do'),
        ("She has ate an apple.", dict(tense='present_perfect', pattern='SVO',
                                       verb='eat', object_noun='apple'),
         'grammar', 'past_tense_as_participle'),
    ]
    nfail = 0
    for sent, info, exp_cat, exp_code in cases:
        full = dict(base)
        full.update(info)
        issues = check_grammar(sent, full)
        found = any(c == exp_code for (_, c, _) in issues)
        codes = [c for (_, c, _) in issues]
        print(f"  [{'OK ' if found else 'MISS'}] {sent}  -> 期望 {exp_cat}:{exp_code}，实际 {codes}")
        if not found:
            nfail += 1
    # 反向：正确句必须不被误报
    good = [
        ("You are happy.", dict(tense='present_simple', is_be=True)),
        ("He eats an apple.", dict(tense='present_simple', pattern='SVO', verb='eat', object_noun='apple')),
        ("She does not read a book.", dict(tense='present_simple', polarity='negative', verb='read')),
        ("Do I paint?", dict(tense='present_simple', question='yes_no', verb='paint')),
        ("Did I arrive?", dict(tense='past_simple', question='yes_no', verb='arrive')),
        ("He runs.", dict(tense='present_simple', person=3, number='singular', verb='run')),
        ("There are two books on the desk.",
         dict(tense='present_simple', pattern='THERE_BE', is_be=True)),
        ("There is a sheep in the kitchen.",
         dict(tense='present_simple', pattern='THERE_BE', is_be=True)),
    ]
    for sent, info in good:
        full = dict(base)
        full.update(info)
        issues = check_grammar(sent, full)
        bad = [c for (_, c, _) in issues
               if c in ('be_agreement', 'existential_agreement_violation',
                        'object_restriction_unmet',
                        'missing_do_support', 'do_agreement',
                        'double_inflection_after_do', 'third_singular')]
        print(f"  [{'OK ' if not bad else 'FALSE+'}] {sent}  -> 误报 {bad}")
        if bad:
            nfail += 1
    if nfail:
        print(f"\n[FAIL] 检查器自检 {nfail} 项未通过")
        sys.exit(1)
    print("\n[PASS] 检查器自检通过：能发现 be 一致/搭配/do-support/三单 错误，且不误报正确句")


# ---------------------------------------------------------------------------
# CLI 入口：argparse（支持 --help / demo / golden / matrix / selftest / 未知参数非零退出）
# ---------------------------------------------------------------------------
def main():
    global K
    parser = argparse.ArgumentParser(
        prog='mini_generator.py',
        description='最小句子生成器原型（不加载 words.json）')
    parser.add_argument('mode', nargs='?', default='demo',
                        choices=['demo', 'golden', 'matrix', 'selftest'],
                        help='运行模式：demo（抽样）| golden（驱动 tests/golden.json）'
                             '| matrix（组合 + 语法校验）| selftest（检查器自检）')
    args = parser.parse_args()
    K = Knowledge()
    {'demo': mode_demo, 'golden': mode_golden, 'matrix': mode_matrix,
     'selftest': mode_checker_selftest}[args.mode]()


if __name__ == '__main__':
    main()
