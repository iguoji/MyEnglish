#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
受控句子结构分析器（surface-based analyzer）
============================================

【这个文件解决什么问题】
之前 mini_generator.py 的检查器有个致命偷懒：它默认「句子的第二个词就是动词」
（代码里写死 tokens[1]）。这在主语是单个代词时碰巧成立（He / runs），
一旦主语变成名词短语就全错：

    The dog runs.   -> tokens[1] = "dog"，被当成动词 -> 三单检查拿 dog 去比对 -> 误报
    The dog run.    -> tokens[1] = "dog"，同样错位 -> 真错误反而漏报

更严重的是，检查器大量信息直接读生成器传进来的 info 字典（tense / person / verb）。
测试里这个 info 是人手写的，于是「人写什么就检查什么」，等于自己给自己出答案，
测试通过毫无意义。

【本文件的定位（用 PHP / 小程序的话说）】
把它想成一个「后端的请求解析中间件」：
  - 输入：一个英文句子字符串（相当于 HTTP 原始报文）
  - 输出：一个结构化的分析结果对象 Analysis（相当于解析后的 $request 对象）
  - 全部字段只允许从「句子文本本身」推导，绝不接受调用方投喂答案。

然后检查器（check_grammar）拿这个 Analysis 去判断语法对错。
调用方如果同时提供了自己声明的 info，我们额外做一次「声明 vs 句面」对账，
对不上就返回 analysis_surface_mismatch —— 这就堵死了「伪造 info 骗过测试」的路。

【依赖注入，避免循环 import】
本文件不 import mini_generator（否则 mini_generator import analyzer 会成环）。
Analyzer 的构造函数接收一个「知识库对象」，只要它具备下列属性即可（鸭子类型）：
    .words        dict[(spelling_lower, pos)] -> 词条 dict（含变形字段数组）
    .noun_usage   dict[spelling] -> 名词用法条目
    .verb_frames  dict[spelling] -> 动词框架条目
    .adj_usage    dict[spelling] -> 形容词用法条目
    .pronouns     dict[lemma]    -> 代词范式条目
    .aux          dict[lemma]    -> 助动词范式条目
这正好就是 mini_generator.Knowledge 的形状。

【受控范围声明（非常重要，不许含糊）】
本分析器只覆盖当前生成器支持的句型：
    SV / SVP / SVO / SVOO / SVOC / SV_PREP_O / THERE_BE / IMPERATIVE
超出范围（从句、被动、非谓语作主语、并列句、wh- 疑问等）一律把 pattern 标为
'unknown' 并在 analysis.unresolved 里写清原因，绝不硬猜。
「猜不出来」是合法输出；「猜错了还很自信」才是事故。
"""

import os
import re
import sys

# ---------------------------------------------------------------------------
# 常量表：这些是英语封闭类词，数量有限且不随词库增长，直接内置
# ---------------------------------------------------------------------------

# 基数词。determiner_rules.json 里没有收数词（它只收 a/the/many/some 这类限定词），
# 但生成器 build_np 会产出 "two books"，分析器必须认得，否则切不出名词短语。
CARDINALS = {
    'one': 'singular',      # one 后面接单数
    'two': 'plural', 'three': 'plural', 'four': 'plural', 'five': 'plural',
    'six': 'plural', 'seven': 'plural', 'eight': 'plural', 'nine': 'plural',
    'ten': 'plural', 'eleven': 'plural', 'twelve': 'plural',
}

# 物主限定词 + 指示词里没被 determiner_rules 收录的部分。
# 这些词只能出现在名词前，不会是动词，识别它们能可靠地定位名词短语起点。
POSSESSIVE_DETERMINERS = {'my', 'your', 'his', 'her', 'its', 'our', 'their'}

# 否定词。缩写形（don't / isn't）在分词阶段会被展开成两个 token，这里只列完整形。
NEGATORS = {'not', 'never', 'no'}

# 语义自带否定的副词（never/seldom/rarely/hardly/barely/scarcely）。
# 双重否定检查要用；它们不等同于 not，但与 not 叠加就是双重否定。
NEGATIVE_ADVERBS = {'never', 'seldom', 'rarely', 'hardly', 'barely', 'scarcely'}

# wh- 疑问词。出现在句首就是特殊疑问句，超出当前受控范围。
WH_WORDS = {'what', 'who', 'whom', 'whose', 'which', 'where', 'when', 'why', 'how'}

# 常见介词。判断 SV_PREP_O / 状语短语要用。
# 只收生成器 verb_frames.fixed_preposition 会用到的 + 高频空间时间介词。
PREPOSITIONS = {
    'about', 'above', 'across', 'after', 'against', 'along', 'among', 'around',
    'at', 'before', 'behind', 'below', 'beside', 'between', 'by', 'down',
    'during', 'for', 'from', 'in', 'inside', 'into', 'like', 'near', 'of',
    'off', 'on', 'onto', 'out', 'outside', 'over', 'past', 'through', 'to',
    'toward', 'towards', 'under', 'until', 'up', 'upon', 'with', 'within',
    'without',
}

# 缩写展开表。英语口语大量使用缩写，语料评估阶段必须先归一化，
# 否则 "doesn't" 会被当成一个陌生 token 而整句无法分析。
# 相当于 PHP 里先跑一遍 str_replace 再解析。
CONTRACTIONS = {
    "don't": ['do', 'not'], "doesn't": ['does', 'not'], "didn't": ['did', 'not'],
    "isn't": ['is', 'not'], "aren't": ['are', 'not'],
    "wasn't": ['was', 'not'], "weren't": ['were', 'not'],
    "hasn't": ['has', 'not'], "haven't": ['have', 'not'], "hadn't": ['had', 'not'],
    "won't": ['will', 'not'], "wouldn't": ['would', 'not'],
    "can't": ['can', 'not'], "cannot": ['can', 'not'], "couldn't": ['could', 'not'],
    "shouldn't": ['should', 'not'], "mustn't": ['must', 'not'],
    "shan't": ['shall', 'not'], "mightn't": ['might', 'not'],
    "i'm": ['I', 'am'], "you're": ['you', 'are'], "he's": ['he', 'is'],
    "she's": ['she', 'is'], "it's": ['it', 'is'], "we're": ['we', 'are'],
    "they're": ['they', 'are'],
    "i've": ['I', 'have'], "you've": ['you', 'have'],
    "we've": ['we', 'have'], "they've": ['they', 'have'],
    "i'll": ['I', 'will'], "you'll": ['you', 'will'], "he'll": ['he', 'will'],
    "she'll": ['she', 'will'], "it'll": ['it', 'will'],
    "we'll": ['we', 'will'], "they'll": ['they', 'will'],
    "i'd": ['I', 'would'], "you'd": ['you', 'would'], "he'd": ['he', 'would'],
    "she'd": ['she', 'would'], "we'd": ['we', 'would'], "they'd": ['they', 'would'],
    "there's": ['there', 'is'], "there're": ['there', 'are'],
    "that's": ['that', 'is'], "here's": ['here', 'is'],
    "let's": ['let', 'us'],
}

# be 的全部限定形（从 auxiliaries.json 也能取，这里内置一份做交叉校验用）
BE_FINITE = {'am', 'is', 'are', 'was', 'were'}
HAVE_FINITE = {'have', 'has', 'had'}
DO_FINITE = {'do', 'does', 'did'}
MODALS = {'will', 'would', 'can', 'could', 'may', 'might',
          'must', 'shall', 'should'}

# be 的「主语人称/数 -> 正确形式」权威表。
# 键 = (时态键, 人称, 数)。这张表是主谓一致判断的唯一事实源。
BE_TABLE = {
    ('present', 1, 'singular'): 'am',
    ('present', 2, 'singular'): 'are',
    ('present', 3, 'singular'): 'is',
    ('present', 1, 'plural'): 'are',
    ('present', 2, 'plural'): 'are',
    ('present', 3, 'plural'): 'are',
    ('past', 1, 'singular'): 'was',
    ('past', 2, 'singular'): 'were',
    ('past', 3, 'singular'): 'was',
    ('past', 1, 'plural'): 'were',
    ('past', 2, 'plural'): 'were',
    ('past', 3, 'plural'): 'were',
}

# 词库中动词词条可能使用的 pos 标签（系统词库历史上四种写法并存）
VERB_POS = ('vt.', 'vi.', 'vi. vt.', 'v.')


# ---------------------------------------------------------------------------
# 分析结果对象
# ---------------------------------------------------------------------------
class Analysis:
    """一次句子分析的全部结论。

    用 PHP 的话说，这就是一个纯数据的 DTO（Data Transfer Object）。
    没有任何业务逻辑，只负责把「从句面读出来的事实」装好交给检查器。

    字段分三组：
      A. 原始层  —— tokens / lower / raw
      B. 结构层  —— 主语、限定动词、助动词链
      C. 语法层  —— 时态、极性、疑问、句型

    另外两个「诚实字段」：
      unresolved  分析器搞不定的地方（列表，每项是一个原因码）
      surface_ok  句面自校验是否通过（False 表示自己算出来的东西对不上原句）
    """

    __slots__ = (
        'raw', 'tokens', 'lower', 'has_question_mark',
        'subject_text', 'subject_head', 'subject_person', 'subject_number',
        'subject_span', 'subject_is_pronoun', 'subject_is_expletive',
        'finite_verb_lemma', 'finite_verb_surface', 'finite_verb_token_index',
        'finite_verb_form_tag',
        'auxiliary_surfaces', 'auxiliary_indices',
        'main_verb_lemma', 'main_verb_surface', 'main_verb_token_index',
        'main_verb_form_tag',
        'tense', 'polarity', 'question', 'pattern',
        'predicative', 'objects', 'preposition',
        'noun_phrases', 'post_verb_tokens', 'complement',
        'adverbs', 'leading_adverbs', 'degree_modifiers',
        'predicative_surface', 'predicative_index', 'predicative_form_tag',
        'unresolved', 'surface_ok',
    )

    def __init__(self):
        self.raw = ''
        self.tokens = []                 # 展开缩写、去标点后的词序列（保留原大小写）
        self.lower = []                  # 同上的小写副本，比对时用
        self.has_question_mark = False

        self.subject_text = None         # 主语的原文，如 "The dog"
        self.subject_head = None         # 主语中心词的原形，如 "dog"
        self.subject_person = None       # 1 / 2 / 3
        self.subject_number = None       # 'singular' / 'plural'
        self.subject_span = None         # (起, 止) 左闭右开的 token 下标区间
        self.subject_is_pronoun = False
        self.subject_is_expletive = False  # There be 里的形式主语 there

        self.finite_verb_lemma = None    # 限定动词原形（助动词句里就是助动词本身）
        self.finite_verb_surface = None  # 限定动词在句中的实际拼写
        self.finite_verb_token_index = None
        self.finite_verb_form_tag = None  # base / 3sg / past / be / modal ...

        self.auxiliary_surfaces = []     # 助动词链的实际拼写列表，如 ['has', 'been']
        self.auxiliary_indices = []      # 对应的 token 下标

        self.main_verb_lemma = None      # 实义动词原形（"has eaten" -> eat）
        self.main_verb_surface = None
        self.main_verb_token_index = None
        self.main_verb_form_tag = None

        self.tense = None                # present_simple / past_simple / ...
        self.polarity = 'affirmative'
        self.question = 'none'           # none / yes_no / wh
        self.pattern = 'unknown'

        self.predicative = None          # SVP 的表语（形容词原形）
        self.objects = []                # 宾语中心词原形列表，SVOO 时有两个
        self.preposition = None          # SV_PREP_O 的介词

        # 句中出现过的全部名词短语（含主语与宾语），每项是 parse_np 的返回 dict。
        # 定语形容词检查（*an afraid child）要靠它，因为形容词是不是"定语"
        # 取决于它有没有出现在某个名词短语内部。
        self.noun_phrases = []
        # 谓语之后的 token 下标列表（跳过 not），供词序类规则使用
        self.post_verb_tokens = []
        # 动词补语：{'type', 'index', 'lemma'}。
        # type 取值与 verb_frames.complement_types 对齐：
        #   to_infinitive / gerund / bare_infinitive / adjective / noun_phrase
        # enjoy to read（应为 gerund）、make him to cry（应为 bare_infinitive）
        # 这两类错误全靠它判定。
        self.complement = None

        # --- 副词层（2026-07-30 新增，用于副词位置类规则）-------------------
        # adverbs：句中出现的全部副词，每项 dict：
        #   {'index': token 下标, 'word': 拼写, 'category': adverb_usage 的类别}
        # 有了它，检查器就能算「这个频度副词到底在主语前还是动词前」，
        # 而不用再自己数下标。
        self.adverbs = []
        # leading_adverbs：出现在主语之前的副词下标列表。
        # *Always she reads books. 就是靠它抓的：频度副词不允许出现在这个位置。
        self.leading_adverbs = []
        # degree_modifiers：程度副词及其修饰目标，每项 dict：
        #   {'index', 'word', 'target_index', 'target_kind'}
        #   target_kind 取值 'adjective' / 'verb' / 'none'
        # *I very like it.（very 修饰动词）与 *The room is enough big.
        #（enough 前置）两类错误都靠它判定。
        self.degree_modifiers = []

        # 表语的「句面真相」：predicative 存的是词库原形（便于查 adjective_usage），
        # 这三个字段存原句里到底写的是什么形态。
        # This book is gooder. -> predicative='good'（推回的原形）
        #                         predicative_surface='gooder'
        #                         predicative_form_tag='comparative_malformed'
        self.predicative_surface = None
        self.predicative_index = None
        self.predicative_form_tag = None

        self.unresolved = []
        self.surface_ok = True

    # -- 便捷判断：给检查器用的语法糖 -------------------------------------
    @property
    def is_copula(self):
        """限定动词是不是系动词 be（且没有后接 -ing/-ed 构成复合时态）。"""
        return self.finite_verb_lemma == 'be' and self.main_verb_lemma is None

    @property
    def tense_key(self):
        """把六时态折叠成 be 表需要的 present / past 两键；将来时返回 None。"""
        if self.tense in ('present_simple', 'present_continuous',
                          'present_perfect'):
            return 'present'
        if self.tense in ('past_simple', 'past_continuous', 'past_perfect'):
            return 'past'
        return None

    def to_dict(self):
        """导出成普通 dict，方便写进 JSON 报告 / 单测断言。"""
        return {k: getattr(self, k) for k in self.__slots__}

    def __repr__(self):
        return (f"<Analysis pattern={self.pattern} tense={self.tense} "
                f"subj={self.subject_text!r}({self.subject_person}"
                f"/{self.subject_number}) "
                f"fin={self.finite_verb_surface!r}@{self.finite_verb_token_index} "
                f"main={self.main_verb_surface!r} pol={self.polarity} "
                f"q={self.question} unresolved={self.unresolved}>")


# ---------------------------------------------------------------------------
# 分析器主体
# ---------------------------------------------------------------------------
class Analyzer:
    """从句面推导结构。构造一次、复用多次（索引只建一遍）。"""

    def __init__(self, knowledge):
        self.K = knowledge
        # 下面这些索引全部在构造时建好。
        # 相当于 PHP 里应用启动时把配置表读进 APCu，请求处理阶段零查库。
        self._build_indexes()

    # ---- 索引构建 --------------------------------------------------------
    def _build_indexes(self):
        """把词库里散落的变形字段，反向索引成「表面拼写 -> 候选解释」。

        为什么要反向索引？
        因为分析器拿到的是句子里的 "runs" / "ate" / "eaten"，
        必须反查回 run / eat / eat，才能知道这是三单、过去式还是过去分词。
        正向查（run -> runs）词库天生支持；反向查必须自己建表。
        """
        K = self.K

        # verb_surface[拼写] = [(原形, 形态标签), ...]
        # 一个拼写可能对应多个解释：read 既是 base 也是 past 也是 pp。
        self.verb_surface = {}
        # verb_lemmas：所有已知动词原形集合
        self.verb_lemmas = set()

        def add_verb(surface, lemma, tag):
            if not surface:
                return
            self.verb_surface.setdefault(surface.lower(), [])
            pair = (lemma, tag)
            if pair not in self.verb_surface[surface.lower()]:
                self.verb_surface[surface.lower()].append(pair)

        for (spelling, pos), entry in K.words.items():
            if pos not in VERB_POS:
                continue
            lemma = spelling.lower()
            self.verb_lemmas.add(lemma)
            add_verb(lemma, lemma, 'base')
            for field, tag in (('third_person_singular', '3sg'),
                               ('gerund', 'ing'),
                               ('past_tense', 'past'),
                               ('past_participle', 'pp')):
                for form in (entry.get(field) or []):
                    add_verb(form, lemma, tag)

        # verb_frames 里声明过的动词一律视为受控动词，
        # 即便系统基线词库暂时缺它的变形字段（缺就在分析时报 unresolved）。
        for spelling in K.verb_frames:
            self.verb_lemmas.add(spelling)
            add_verb(spelling, spelling, 'base')

        # noun_surface[拼写] = (原形, 'singular' | 'plural')
        # 复数形优先级低于单数形：单复同形（sheep）时按单数登记，靠限定词区分。
        self.noun_surface = {}
        for (spelling, pos), entry in K.words.items():
            if pos != 'n.':
                continue
            lemma = spelling.lower()
            self.noun_surface.setdefault(lemma, (lemma, 'singular'))
            for form in (entry.get('plural') or []):
                f = form.lower()
                if f != lemma:
                    self.noun_surface.setdefault(f, (lemma, 'plural'))
        # noun_usage 是受控名词权威表，它里面的词一定要认得
        for spelling in K.noun_usage:
            self.noun_surface.setdefault(spelling, (spelling, 'singular'))

        # 形容词：原形 + 比较级 + 最高级 都要能反查
        #
        # 三张表各司其职：
        #   adj_surface[拼写]  -> 原形            （"这个词是不是形容词"）
        #   adj_form_tag[拼写] -> (原形, 形态标签)（"它是原级/比较级/最高级"）
        #   adj_comparison[原形] -> {'comparative': [...], 'superlative': [...]}
        #                          （"它的合法比较级到底该怎么写"）
        # 第三张表是判 *gooder / *biger 的唯一依据——
        # 必须拿词库里真实的 better / bigger 来比对，不能靠拼写规则猜。
        self.adj_surface = {}
        self.adj_form_tag = {}
        self.adj_comparison = {}
        for (spelling, pos), entry in K.words.items():
            if pos != 'adj.':
                continue
            lemma = spelling.lower()
            self.adj_surface.setdefault(lemma, lemma)
            self.adj_form_tag.setdefault(lemma, (lemma, 'base'))
            row = self.adj_comparison.setdefault(
                lemma, {'comparative': [], 'superlative': []})
            for field, tag in (('comparative', 'comparative'),
                               ('superlative', 'superlative')):
                for form in (entry.get(field) or []):
                    f = form.lower()
                    self.adj_surface.setdefault(f, lemma)
                    self.adj_form_tag.setdefault(f, (lemma, tag))
                    if f not in row[field]:
                        row[field].append(f)
        # adjective_usage.json 是造句模块自己的形容词权威表。
        # 系统基线词库目前只收了 15 个功能性形容词（some/any/much...），
        # happy / good / big 这些内容词的比较级形态只存在这里，
        # 所以必须一并读进来，否则 *gooder / *biger 根本无从判定。
        for spelling, row in K.adj_usage.items():
            self.adj_surface.setdefault(spelling, spelling)
            self.adj_form_tag.setdefault(spelling, (spelling, 'base'))
            cmp_row = self.adj_comparison.setdefault(
                spelling, {'comparative': [], 'superlative': []})
            for field, tag in (('comparative', 'comparative'),
                               ('superlative', 'superlative')):
                for form in (row.get(field) or []):
                    f = form.lower()
                    self.adj_surface.setdefault(f, spelling)
                    self.adj_form_tag.setdefault(f, (spelling, tag))
                    if f not in cmp_row[field]:
                        cmp_row[field].append(f)

        # 副词表：从 adverb_usage.json 读（Knowledge 目前没装它，这里自己兜底读）
        self.adv_usage = getattr(K, 'adv_usage', None)
        if self.adv_usage is None:
            self.adv_usage = self._load_adverb_usage()
        self.adv_set = set(self.adv_usage)

        # 限定词表：determiner_rules.json + 数词 + 物主限定词
        self.determiners = {}
        for row in self._load_determiners():
            self.determiners[row['spelling']] = row.get('verb_agreement',
                                                        'follows_noun')
        for word, num in CARDINALS.items():
            self.determiners.setdefault(word, num)
        for word in POSSESSIVE_DETERMINERS:
            self.determiners.setdefault(word, 'follows_noun')

        # 代词表：把「主格拼写」映射到范式条目。
        # 注意 you 与 you_plural 主格同形，单独处理：默认按 you（单数记法，
        # 但 be 用 are，与复数一致），需要区分时由上下文另行判断。
        self.pronoun_by_surface = {}
        for lemma, row in K.pronouns.items():
            subj = row['forms']['subject'].lower()
            # you 单数条目先登记，you_plural 不覆盖它（二者 be 形一致，不影响判断）
            self.pronoun_by_surface.setdefault(subj, row)
        # 宾格代词也要认得（做宾语识别用）
        self.pronoun_object_forms = {}
        for lemma, row in K.pronouns.items():
            self.pronoun_object_forms.setdefault(
                row['forms']['object'].lower(), row)

        # plural_only / invariant / collective / mass 四类特殊名词集合。
        # 全部从 noun_usage.number_behavior 动态推导——
        # 这就是用户要求的「不要只修示例词，要覆盖整类」。
        self.plural_only_nouns = {
            n for n, u in K.noun_usage.items()
            if u.get('number_behavior') == 'plural_only'}
        self.invariant_nouns = {
            n for n, u in K.noun_usage.items()
            if u.get('number_behavior') == 'invariant'}
        self.collective_nouns = {
            n: u.get('verb_agreement', 'singular')
            for n, u in K.noun_usage.items()
            if u.get('number_behavior') == 'collective'}
        self.mass_nouns = {
            n for n, u in K.noun_usage.items()
            if u.get('number_behavior') == 'mass'}

        # 系动词类实义动词（taste / look / smell / sound / feel / seem ...）。
        # 它们语法上像 be：后面接形容词表语而不是宾语。
        # 数据源是 verb_frames 的 copula 标志，加词自动生效。
        self.copula_verbs = {v for v, f in K.verb_frames.items()
                             if f.get('copula')}

    def _sent_dir(self):
        """定位 patch/sentence 目录（本文件在 patch/sentence/tools/）。"""
        return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def _load_adverb_usage(self):
        import json
        path = os.path.join(self._sent_dir(), 'lexicon', 'adverb_usage.json')
        with open(path, encoding='utf-8') as f:
            return {e['spelling']: e for e in json.load(f)}

    def _load_determiners(self):
        import json
        path = os.path.join(self._sent_dir(), 'paradigms',
                            'determiner_rules.json')
        with open(path, encoding='utf-8') as f:
            return json.load(f)

    # ---- 分词 ------------------------------------------------------------
    def tokenize(self, sentence):
        """把句子切成 token 列表，并展开缩写。

        步骤（跟 PHP 里写个 parser 一样，一步步剥）：
          1. 记住句尾是不是问号（这是判断疑问句最硬的证据）
          2. 去掉句末标点和句内逗号
          3. 按空白切分
          4. 逐个 token 查缩写表，命中就展开成两个 token
        返回 (tokens, has_question_mark)。
        """
        s = sentence.strip()
        has_q = s.endswith('?')
        # 去掉句末的 . ! ? 以及句内的逗号、分号、引号
        s = re.sub(r'[.!?]+$', '', s)
        s = s.replace(',', ' ').replace(';', ' ')
        s = s.replace('"', ' ').replace('\u201c', ' ').replace('\u201d', ' ')
        # 弯引号统一成直引号，否则 don’t 查不到缩写表
        s = s.replace('\u2019', "'")
        raw_tokens = [t for t in s.split() if t]

        tokens = []
        for t in raw_tokens:
            key = t.lower()
            if key in CONTRACTIONS:
                # 展开时保留首字母大小写线索：句首 "Don't" -> ["Do", "not"]
                expanded = list(CONTRACTIONS[key])
                if t[0].isupper() and expanded[0] not in ('I',):
                    expanded[0] = expanded[0].capitalize()
                tokens.extend(expanded)
            else:
                tokens.append(t)
        return tokens, has_q

    # ---- 词性探测小工具 ---------------------------------------------------
    def is_determiner(self, w):
        return w.lower() in self.determiners

    def is_adjective(self, w):
        return w.lower() in self.adj_surface

    def is_adverb(self, w):
        return w.lower() in self.adv_set

    def is_noun_surface(self, w):
        return w.lower() in self.noun_surface

    def verb_readings(self, w):
        """返回该拼写的全部动词解释 [(原形, 形态标签), ...]，没有就空列表。"""
        return self.verb_surface.get(w.lower(), [])

    def malformed_verb_reading(self, w):
        """当一个词不是任何合法动词形态时，尝试判断它是不是「拼错的动词变形」。

        为什么必须有这一步？
        因为 golden 里的错误句大量是这种形态：
            He gos.          -> gos 不是 go 的任何合法形（正确是 goes）
            She eated ...    -> eated 不是 eat 的任何合法形（正确是 ate）
            They have goed.  -> goed 不是 go 的任何合法形（正确是 gone）
        如果分析器只认合法形，这些句子会直接「找不到动词」，
        检查器就无从判断错在哪，测试永远是 SKIP —— 那才是真正的漏检。

        做法：按英语最常见的机械构形规则剥后缀，剥完能命中已知动词原形就认。
        返回 (原形, 形态标签) 或 None；标签带 _malformed 后缀，
        方便检查器知道「这个形态本身就是错的」。
        """
        wl = w.lower()
        if wl in self.verb_surface:
            return None                      # 本来就是合法形，不走这条路
        # 机械加 -s（gos / doos）
        if wl.endswith('s') and not wl.endswith('ss'):
            stem = wl[:-1]
            if stem in self.verb_lemmas:
                return (stem, '3sg_malformed')
        # 机械加 -ed（eated / writed / goed）
        if wl.endswith('ed'):
            for stem in (wl[:-2], wl[:-1]):   # eated->eat, writed->write
                if stem in self.verb_lemmas:
                    return (stem, 'past_malformed')
            # 双写辅音后加 -ed（runned -> run）
            if len(wl) > 4 and wl[-3] == wl[-4]:
                stem = wl[:-3]
                if stem in self.verb_lemmas:
                    return (stem, 'past_malformed')
        # 机械加 -ing（eatting）
        if wl.endswith('ing'):
            for stem in (wl[:-3], wl[:-3] + 'e'):
                if stem in self.verb_lemmas:
                    return (stem, 'ing_malformed')
        return None

    def adj_reading(self, w):
        """合法形容词读法：返回 (原形, 'base'/'comparative'/'superlative')，否则 None。"""
        return self.adj_form_tag.get(w.lower())

    def malformed_adjective_reading(self, w):
        """判断一个词是不是「机械构造出来的错误比较级/最高级」。

        为什么必须有这一步？
        golden 里 *This book is gooder.* / *The dog is biger.* 这两句，
        gooder / biger 在词库里根本查不到（合法形是 better / bigger），
        分析器如果只认合法形，表语就会是 None，检查器无从下手，测试永远 SKIP。

        做法跟 malformed_verb_reading 一个套路：按机械规则剥后缀，
        剥完能命中已知形容词原形就认，并打上 _malformed 标签。
            gooder -> 剥 er -> good  ✅（good 是已知形容词）-> comparative_malformed
            biger  -> 剥 er -> big   ✅ -> comparative_malformed
            happyer-> 剥 er -> happy ✅ -> comparative_malformed
        注意顺序：先试 est（最高级）再试 er，否则 "biggest" 会被 er 规则误伤。
        """
        wl = w.lower()
        if wl in self.adj_surface:
            return None                       # 本来就是合法形，不走这条路
        for suffix, tag in (('est', 'superlative'), ('er', 'comparative')):
            if not wl.endswith(suffix) or len(wl) <= len(suffix) + 1:
                continue
            stem = wl[:-len(suffix)]
            # 三种回推：直接剥（gooder->good / biger->big）、
            #           补回被删的 e（*nicer 合法，此处兜底 *largr 类笔误）、
            #           补回被改成 i 的 y（happyer 已经是 y，这里处理 happier 反向）
            for cand in (stem, stem + 'e', stem[:-1] + 'y' if stem.endswith('i')
                         else None):
                if cand and cand in self.adj_comparison:
                    return (cand, tag + '_malformed')
        return None

    def is_finite_verb_surface(self, w):
        """这个拼写能不能充当【限定动词】（谓语动词）？

        限定形 = base（我们把 base 也算，因为 I run / they run 是合法谓语）
                / 3sg / past / be 形 / 助动词 / 情态动词
        非限定形 = ing / pp（它们必须配助动词，不能单独当谓语）
        """
        wl = w.lower()
        if wl in BE_FINITE or wl in HAVE_FINITE or wl in DO_FINITE \
                or wl in MODALS:
            return True
        for _, tag in self.verb_readings(wl):
            if tag in ('base', '3sg', 'past'):
                return True
        return False

    def is_auxiliary_surface(self, w):
        wl = w.lower()
        return (wl in BE_FINITE or wl in HAVE_FINITE or wl in DO_FINITE
                or wl in MODALS or wl in ('been', 'being'))

    # ---- 名词短语切分 ----------------------------------------------------
    def parse_np(self, tokens, start):
        """从 tokens[start] 开始，贪心切出一个名词短语。

        返回 dict：
            {'text', 'head', 'number', 'span', 'is_pronoun', 'determiner'}
        切不出来返回 None。

        【核心的消歧规则，直接决定 The dog runs 会不会被切错】
        名词短语一旦已经拿到中心名词（head），再遇到一个「能当限定动词」的词，
        立即停止吞并。这样：
            The dog runs  -> 吃 the、吃 dog（head 到手）、看到 runs 是限定形 -> 停
                             NP = "The dog"，动词从下标 2 开始 ✅
            The dog run   -> 同理 NP = "The dog"，动词 run ✅（然后一致性检查报错）
        如果没有这条规则，runs 会被当成名词 run 的复数吞进 NP，整句结构就废了。
        """
        i = start
        n = len(tokens)
        if i >= n:
            return None

        first = tokens[i].lower()

        # 情况一：单个代词做主语，最省事
        if first in self.pronoun_by_surface and not self.is_determiner(first):
            row = self.pronoun_by_surface[first]
            return {
                'text': tokens[i], 'head': first,
                'number': row['number'], 'person': row['person'],
                'span': (i, i + 1), 'is_pronoun': True, 'determiner': None,
            }

        # 情况二：形式主语 there
        if first == 'there':
            return {
                'text': tokens[i], 'head': 'there', 'number': None,
                'person': 3, 'span': (i, i + 1), 'is_pronoun': False,
                'determiner': None, 'expletive': True,
            }

        # 情况三：限定词 + 若干形容词 + 名词（可含 of 短语，如 a pair of scissors）
        determiner = None
        head = None
        head_index = None
        head_number = None
        j = i

        # 3a. 吃限定词（最多一个冠词/数词/物主，英语不允许 *the my book）
        if j < n and self.is_determiner(tokens[j]):
            determiner = tokens[j].lower()
            j += 1

        # 3b. 吃形容词（可以连吃：the big red book）
        #     注意：形容词表里可能有词同时是动词（如 clean），
        #     只有在「后面还有名词」的前提下才当形容词，这里先贪心吃，
        #     最后如果没吃到名词就整体回退。
        #     吃进来的形容词全部登记到 attributive_adjectives——
        #     它们出现在名词短语内部，语法角色就是"定语"，
        #     后续 *an afraid child 这类检查全靠这份名单。
        adj_start = j
        attributive_adjectives = []
        while j < n and self.is_adjective(tokens[j]) \
                and not self.is_noun_surface(tokens[j]):
            attributive_adjectives.append((j, self.adj_surface[tokens[j].lower()]))
            j += 1
        # 副词修饰形容词：a very big book
        if j < n and self.is_adverb(tokens[j]) and j + 1 < n \
                and self.is_adjective(tokens[j + 1]):
            attributive_adjectives.append(
                (j + 1, self.adj_surface[tokens[j + 1].lower()]))
            j += 2
            while j < n and self.is_adjective(tokens[j]) \
                    and not self.is_noun_surface(tokens[j]):
                attributive_adjectives.append(
                    (j, self.adj_surface[tokens[j].lower()]))
                j += 1

        # 3c. 吃中心名词
        malformed_plural = False
        if j < n and self.is_noun_surface(tokens[j]):
            head, head_number = self.noun_surface[tokens[j].lower()]
            head_index = j
            j += 1
        elif j < n and self._malformed_plural_stem(tokens[j]):
            # 机械加 -s 造出来的假复数：waters（不可数）/ sheeps（单复同形）。
            # 词库里查不到这个形，但去掉 -s 能命中原形，说明是「错误的复数」。
            # 如实记下来（malformed_plural=True），交给检查器判错。
            head = self._malformed_plural_stem(tokens[j])
            head_number = 'plural'
            head_index = j
            malformed_plural = True
            j += 1

        if head is None:
            # 没吃到名词。如果之前吃了限定词/形容词，说明这是个残缺 NP，
            # 交给调用方处理（可能是 "The scissors" 这种 head 不在词库的情况）
            if determiner and adj_start < n:
                # 兜底：把限定词后的第一个词当 head（即使词库没收）
                k = i + 1
                if k < n and not self.is_finite_verb_surface(tokens[k]):
                    head = tokens[k].lower()
                    head_index = k
                    head_number = None
                    j = k + 1
                else:
                    return None
            else:
                return None

        # 3d. "a pair of scissors" / "a lot of water"：of 短语。
        #     英语里 of 短语的主谓一致取决于前面的量词（pair/lot），不是 of 后的名词。
        #     这里保留原 head（pair），并把 of 后的名词记在 of_noun 里。
        of_noun = None
        if j + 1 < n and tokens[j].lower() == 'of' \
                and self.is_noun_surface(tokens[j + 1]):
            of_noun = self.noun_surface[tokens[j + 1].lower()][0]
            j += 2

        # 3e. 确定 NP 的语法数
        number = self._np_number(determiner, head, head_number)

        result = {
            'text': ' '.join(tokens[i:j]),
            'head': head,
            'head_index': head_index,
            'number': number,
            'person': 3,                  # 名词短语一律第三人称
            'span': (i, j),
            'is_pronoun': False,
            'determiner': determiner,
            'of_noun': of_noun,
            'adjectives': attributive_adjectives,
            'malformed_plural': malformed_plural,
        }
        return result

    def _malformed_plural_stem(self, word):
        """word 是不是「机械加 -s 造出来的非法复数」？是就返回原形，否则 None。

        只在词库查不到这个拼写时才尝试，所以合法复数（books / boxes）不会命中。
        以 -ss 结尾的词（grass / glass）排除，避免把 gras 当原形。
        """
        wl = word.lower()
        if wl in self.noun_surface or wl.endswith('ss'):
            return None
        if wl.endswith('es') and wl[:-2] in self.noun_surface:
            return self.noun_surface[wl[:-2]][0]
        if wl.endswith('s') and wl[:-1] in self.noun_surface:
            return self.noun_surface[wl[:-1]][0]
        return None

    def _np_number(self, determiner, head, surface_number):
        """推导名词短语的语法数。优先级：特殊名词类别 > 限定词 > 名词形态。

        这一段就是修复 plural-only 主谓一致的核心：
        scissors / glasses / jeans / pants / stairs / clothes 这些词，
        无论前面是不是 the，谓语都必须用复数（The scissors ARE sharp）。
        而且集合来自 noun_usage.number_behavior == 'plural_only'，
        今后往 noun_usage 里加 trousers / shorts，这里自动生效，不用改代码。
        """
        if head in self.plural_only_nouns:
            return 'plural'
        if head in self.mass_nouns:
            return 'singular'
        if head in self.collective_nouns:
            agr = self.collective_nouns[head]
            # verb_agreement 可能是 'plural' / 'singular' / 'both'
            if agr == 'plural':
                return 'plural'
            if agr == 'singular':
                return 'singular'
            return 'both'          # both = 两种一致都可接受，检查器要放行
        if head in self.invariant_nouns:
            # sheep / fish / deer：拼写分不出数，只能看限定词
            if determiner in ('a', 'an', 'one', 'this', 'that', 'every', 'each'):
                return 'singular'
            if determiner in CARDINALS and CARDINALS[determiner] == 'plural':
                return 'plural'
            if determiner in ('these', 'those', 'many', 'several', 'few'):
                return 'plural'
            return None            # 没有线索，诚实地返回未知
        # 普通名词：先看限定词的强制要求，再看名词自身形态
        if determiner:
            agr = self.determiners.get(determiner)
            if agr in ('singular', 'plural'):
                return agr
        return surface_number or 'singular'

    # ---- 主入口 ----------------------------------------------------------
    def analyze(self, sentence):
        """分析一个句子，返回 Analysis 对象。永远不抛异常。"""
        a = Analysis()
        a.raw = sentence
        a.tokens, a.has_question_mark = self.tokenize(sentence)
        a.lower = [t.lower() for t in a.tokens]

        if not a.tokens:
            a.unresolved.append('empty_sentence')
            return a

        # 超范围早退：并列连词 / 从句引导词 / wh- 疑问，直接标记为 unknown。
        # 与其猜错，不如说不知道。
        low = a.lower
        if low[0] in WH_WORDS:
            a.question = 'wh'
            a.unresolved.append('wh_question_out_of_scope')
        for marker in ('because', 'although', 'though', 'while', 'if', 'when',
                       'that', 'which', 'who', 'and', 'but', 'or', 'so'):
            if marker in low[1:]:
                a.unresolved.append('multi_clause_out_of_scope:' + marker)
                break

        self._scan_adverbs(a)
        self._locate_core(a)
        self._derive_tense(a)
        self._derive_polarity(a)
        self._derive_question(a)
        self._derive_pattern(a)
        self._scan_degree_modifiers(a)
        self._surface_selfcheck(a)
        return a

    # ---- 第零步：副词清单 -------------------------------------------------
    def _scan_adverbs(self, a):
        """把句中所有副词登记成清单（下标 + 拼写 + 类别）。

        用 PHP 的话说，这一步相当于先把表单里所有 name="adv[]" 的字段
        扫成一个数组，后面的校验规则直接遍历这个数组，
        而不是每条规则都自己再 explode 一遍句子。

        类别（category）来自 lexicon/adverb_usage.json：
            frequency（always/often/never...）
            degree（very/quite/enough/more...）
            manner（well/quickly...）
        位置类规则全部按 category 分流，不硬编码具体词。
        """
        for i, w in enumerate(a.lower):
            row = self.adv_usage.get(w)
            if not row:
                continue
            a.adverbs.append({'index': i, 'word': w,
                              'category': row.get('category'),
                              'default_position': row.get('default_position')})

    # ---- 第五步半：程度副词的修饰目标 -------------------------------------
    def _scan_degree_modifiers(self, a):
        """给每个程度副词找出它到底在修饰谁。

        三种结果：
            adjective            very heavy / enough big   （前置修饰形容词）
            adjective_postposed  big enough                （后置修饰形容词）
            verb                 very like                 （错误：修饰动词）
            none                 like it very much         （修饰不明，不下结论）
        检查器据此判 degree_adverb_on_verb / enough_preposed，
        不需要再去数「very 在第几个词」。
        """
        low, n = a.lower, len(a.lower)
        for adv in a.adverbs:
            if adv['category'] != 'degree':
                continue
            i = adv['index']
            target_index, kind = None, 'none'
            if i + 1 < n:
                nxt = low[i + 1]
                if self.is_adverb(nxt):
                    # very much：程度副词修饰副词，合法，不必再往下判
                    target_index, kind = i + 1, 'adverb'
                elif self.is_adjective(nxt) \
                        or self.malformed_adjective_reading(nxt):
                    target_index, kind = i + 1, 'adjective'
                elif self.verb_readings(nxt) or self.malformed_verb_reading(nxt):
                    target_index, kind = i + 1, 'verb'
            if kind == 'none' and i > 0 and self.is_adjective(low[i - 1]):
                target_index, kind = i - 1, 'adjective_postposed'
            a.degree_modifiers.append({
                'index': i, 'word': adv['word'],
                'target_index': target_index, 'target_kind': kind})

    # ---- 第一步：定位主语与限定动词 ---------------------------------------
    def _locate_core(self, a):
        """找出主语和限定动词。这是整个分析器最关键的一步。

        英语受控句型只有三种开头形态：
          (1) 陈述句：[主语 NP] [助动词链] [动词] ...
          (2) 一般疑问句：[助动词/be] [主语 NP] [动词] ...
          (3) 祈使句：[动词原形] ...（没有主语）
        我们按这三种情况分别处理，不做统计猜测。
        """
        tokens, low, n = a.tokens, a.lower, len(a.tokens)

        # --- 情况 0：跳过句首副词 ---
        # "Always she reads books." / "Usually I walk to school."
        # 句首副词不是主语，必须先跳过去再找主语，否则 parse_np 会从 Always
        # 开始切，切不出名词就整句报 subject_np_unparsed（这正是上一版的缺口）。
        # 跳过的下标记进 leading_adverbs，检查器据此判「频度副词不许前置」。
        # 三个「长得像副词但不能跳」的例外：
        #   there —— 存在句的形式主语（There are two books.），跳了就没主语了
        #   限定词 / 代词 —— 本来就是主语的一部分
        #   名词形 —— 可能是真主语（如 "Today is Monday." 里的 today）
        sbase = 0
        while sbase + 1 < n and self.is_adverb(low[sbase]) \
                and low[sbase] != 'there' \
                and not self.is_determiner(low[sbase]) \
                and not self.is_noun_surface(low[sbase]) \
                and low[sbase] not in self.pronoun_by_surface:
            a.leading_adverbs.append(sbase)
            sbase += 1

        # --- 情况 3：祈使句 ---
        # 判据：首词是动词原形（且不是助动词/be），并且这个词不能同时被解读为
        # 一个可以做主语的名词或代词。 "Open the door." / "Please sit down."
        first = low[sbase]
        start = sbase
        if first == 'please' and sbase + 1 < n:
            start = sbase + 1
            first = low[start]
        if first == "don't":     # 理论上已被缩写展开，这里保险
            first = 'do'
        imperative = False
        if first not in self.pronoun_by_surface and first != 'there' \
                and not self.is_determiner(first) \
                and not self.is_auxiliary_surface(first):
            readings = self.verb_readings(first)
            malformed = self.malformed_verb_reading(first)
            # "Do not open" 的否定祈使：首词 do + not + 原形
            neg_imperative = (first in ('do',) and start + 1 < n
                              and low[start + 1] == 'not')
            # 【关键消歧】首词有动词读法时，怎么区分「祈使句」和「名词主语句」？
            #   Books are cheap.  -> books 虽然是 book 的三单形，
            #                        但紧跟着 are（限定动词），所以 books 是主语
            #   Opens the door.   -> 紧跟着 the（限定词），不可能有别的谓语，
            #                        所以 Opens 就是（写错形态的）祈使句动词
            # 判据：后面还有没有另一个限定动词。有 -> 首词是主语；没有 -> 祈使句。
            nxt_is_finite = (start + 1 < n
                             and self.is_finite_verb_surface(low[start + 1]))
            if (readings or malformed) and not nxt_is_finite:
                # 祈使句动词必须是原形（base）。若句首是「屈折实义动词 + 问号 +
                # 后面紧跟主语」（Reads she books? / Reads the book?），这是 V-S
                # 倒装疑问句，不是祈使句——交给「情况 2b」解析，否则会误判成祈使句。
                # 而 Open it? 这种「原形动词 + 问号 + 宾语代词」仍是合法祈使句，放行。
                has_base = any(r[1] == 'base' for r in readings)
                looks_like_inverted_q = (a.has_question_mark and start + 1 < n
                                         and not self.is_finite_verb_surface(
                                             low[start + 1]))
                if not (looks_like_inverted_q and not has_base):
                    imperative = True
            if neg_imperative:
                imperative = True
        if imperative:
            a.subject_text = None
            a.subject_head = None
            a.subject_person = 2          # 祈使句逻辑主语是 you
            a.subject_number = None
            a.pattern = 'IMPERATIVE'
            if low[start] == 'do' and start + 1 < n and low[start + 1] == 'not':
                a.auxiliary_surfaces = ['do']
                a.auxiliary_indices = [start]
                vi = start + 2
            else:
                vi = start
            if vi < n:
                a.finite_verb_surface = tokens[vi]
                a.finite_verb_token_index = vi
                readings = self.verb_readings(low[vi])
                base = [r for r in readings if r[1] == 'base']
                if base:
                    a.finite_verb_lemma = base[0][0]
                    a.finite_verb_form_tag = 'base'
                elif readings:
                    # 祈使句里出现了非原形（Opens / Opened）——如实记录形态，
                    # 由检查器判 inflected_imperative，分析器不越权下结论。
                    a.finite_verb_lemma = readings[0][0]
                    a.finite_verb_form_tag = readings[0][1]
                else:
                    mal = self.malformed_verb_reading(low[vi])
                    if mal:
                        a.finite_verb_lemma, a.finite_verb_form_tag = mal
                a.main_verb_lemma = a.finite_verb_lemma
                a.main_verb_surface = a.finite_verb_surface
                a.main_verb_token_index = vi
                a.main_verb_form_tag = a.finite_verb_form_tag
            return

        # --- 情况 2：一般疑问句（助动词/be 提前）---
        inverted = self.is_auxiliary_surface(low[sbase]) and n > sbase + 1
        if inverted:
            aux_index = sbase
            np = self.parse_np(tokens, sbase + 1)
            if np is None:
                a.unresolved.append('subject_np_unparsed')
                return
            self._assign_subject(a, np)
            a.auxiliary_surfaces.append(tokens[aux_index])
            a.auxiliary_indices.append(aux_index)
            a.finite_verb_surface = tokens[aux_index]
            a.finite_verb_token_index = aux_index
            a.finite_verb_lemma = self._aux_lemma(low[aux_index])
            a.finite_verb_form_tag = self._aux_tag(low[aux_index])
            # 主语之后继续吃助动词链，再找实义动词
            self._scan_predicate(a, np['span'][1])
            return

        # --- 情况 2b：疑问句但句首是实义动词（错误的倒装）---
        # "Reads she books?" 是病句（应为 Does she read books?），
        # 但结构必须解析出来，否则检查器无法报 missing_do_support。
        if a.has_question_mark and n > sbase + 1:
            readings0 = self.verb_readings(low[sbase])
            finite0 = [r for r in readings0 if r[1] in ('base', '3sg', 'past')]
            if finite0 and low[sbase] not in self.pronoun_by_surface \
                    and not self.is_determiner(low[sbase]):
                np = self.parse_np(tokens, sbase + 1)
                if np:
                    self._assign_subject(a, np)
                    a.finite_verb_surface = tokens[sbase]
                    a.finite_verb_token_index = sbase
                    a.finite_verb_lemma = finite0[0][0]
                    a.finite_verb_form_tag = finite0[0][1]
                    a.main_verb_lemma = finite0[0][0]
                    a.main_verb_surface = tokens[sbase]
                    a.main_verb_token_index = sbase
                    a.main_verb_form_tag = finite0[0][1]
                    return

        # --- 情况 1：陈述句 ---
        np = self.parse_np(tokens, sbase)
        if np is None:
            a.unresolved.append('subject_np_unparsed')
            return
        self._assign_subject(a, np)
        self._scan_predicate(a, np['span'][1])

    def _assign_subject(self, a, np):
        """把 parse_np 的结果写进 Analysis 的主语字段。"""
        a.subject_text = np['text']
        a.subject_head = np['head']
        a.subject_person = np.get('person', 3)
        a.subject_number = np.get('number')
        a.subject_span = np['span']
        a.subject_is_pronoun = np.get('is_pronoun', False)
        a.subject_is_expletive = np.get('expletive', False)
        if np.get('head') and not np.get('is_pronoun') \
                and not np.get('expletive'):
            a.noun_phrases.append(np)
        if a.subject_number is None and not a.subject_is_expletive:
            a.unresolved.append('subject_number_undetermined')

    def _aux_lemma(self, w):
        if w in BE_FINITE or w in ('been', 'being', 'be'):
            return 'be'
        if w in HAVE_FINITE:
            return 'have'
        if w in DO_FINITE:
            return 'do'
        if w in MODALS:
            return w
        return w

    def _aux_tag(self, w):
        if w in BE_FINITE:
            return 'be'
        if w in HAVE_FINITE:
            return 'have'
        if w in DO_FINITE:
            return 'do'
        if w in MODALS:
            return 'modal'
        return 'unknown'

    def _scan_predicate(self, a, i):
        """从下标 i 开始扫描谓语部分：助动词链 -> not -> 副词 -> 实义动词。

        用 PHP 的思路说，这就是一个状态机：
          状态A（吃助动词）：碰到 is/are/has/will/do 就收进 auxiliary_surfaces
          状态B（跳过 not 和插入语副词）：not / never / always / often ...
          状态C（认定实义动词）：第一个非助动词的动词形态，就是主动词
        """
        tokens, low, n = a.tokens, a.lower, len(a.tokens)
        first_finite_set = a.finite_verb_token_index is not None

        while i < n:
            w = low[i]
            # 跳过否定词和中位副词（She does not always read.）
            if w in ('not',) or (w in self.adv_set
                                 and self.adv_usage.get(w, {}).get('category')
                                 in ('frequency', 'degree', 'focus')):
                i += 1
                continue
            if self.is_auxiliary_surface(w):
                a.auxiliary_surfaces.append(tokens[i])
                a.auxiliary_indices.append(i)
                if not first_finite_set:
                    a.finite_verb_surface = tokens[i]
                    a.finite_verb_token_index = i
                    a.finite_verb_lemma = self._aux_lemma(w)
                    a.finite_verb_form_tag = self._aux_tag(w)
                    first_finite_set = True
                i += 1
                continue
            readings = self.verb_readings(w)
            if readings:
                # 找到实义动词。挑一个最合理的解释：
                #   有助动词在前 -> 期待 ing / pp / base（取决于助动词类型）
                #   没有助动词   -> 期待 base / 3sg / past
                tag = self._pick_verb_reading(a, readings)
                a.main_verb_lemma = tag[0]
                a.main_verb_form_tag = tag[1]
                a.main_verb_surface = tokens[i]
                a.main_verb_token_index = i
                if not first_finite_set:
                    a.finite_verb_surface = tokens[i]
                    a.finite_verb_token_index = i
                    a.finite_verb_lemma = tag[0]
                    a.finite_verb_form_tag = tag[1]
                    first_finite_set = True
                return
            # 合法动词形态都不匹配 -> 试试是不是拼错的变形（gos / eated / goed）
            mal = self.malformed_verb_reading(w)
            if mal:
                a.main_verb_lemma, a.main_verb_form_tag = mal
                a.main_verb_surface = tokens[i]
                a.main_verb_token_index = i
                if not first_finite_set:
                    a.finite_verb_surface = tokens[i]
                    a.finite_verb_token_index = i
                    a.finite_verb_lemma = mal[0]
                    a.finite_verb_form_tag = mal[1]
                    first_finite_set = True
                a.unresolved.append('malformed_verb_form:' + w)
                return
            # 既不是助动词也不是动词：如果还没找到任何谓语，继续往后找；
            # 已经有助动词（如系动词 be），那这个词就是表语/宾语，扫描结束。
            if first_finite_set:
                return
            i += 1

        if not first_finite_set:
            a.unresolved.append('finite_verb_not_found')

    def _pick_verb_reading(self, a, readings):
        """一个拼写有多种动词解释时，按前面的助动词决定取哪个。

        例：read 同时是 base / past / pp。
            "I read a book."        没助动词 -> 取 base（现在时）
            "I have read a book."   前有 have -> 取 pp
        """
        prev_aux = [w.lower() for w in a.auxiliary_surfaces]
        want = None
        if prev_aux:
            last = prev_aux[-1]
            if last in BE_FINITE or last in ('been', 'being'):
                want = 'ing'          # be + V-ing
            elif last in HAVE_FINITE:
                want = 'pp'           # have + V-pp
            elif last in DO_FINITE or last in MODALS:
                want = 'base'         # do/will + V-base
        if want:
            for r in readings:
                if r[1] == want:
                    return r
        # 没有偏好或偏好落空：按 3sg > past > base > pp > ing 的优先级，
        # 因为限定形比非限定形更可能是谓语核心。
        priority = {'3sg': 0, 'past': 1, 'base': 2, 'pp': 3, 'ing': 4}
        return sorted(readings, key=lambda r: priority.get(r[1], 9))[0]

    # ---- 第二步：时态推导 -------------------------------------------------
    def _derive_tense(self, a):
        """根据助动词链 + 主动词形态反推时态。纯句面证据，不看任何声明。"""
        aux = [w.lower() for w in a.auxiliary_surfaces]
        mv_tag = a.main_verb_form_tag
        # 助动词链里 do/does/did 只是 do-support，不参与时态判断的"形态"部分，
        # 但它自己的形态（do/does=现在，did=过去）决定时态。
        if a.pattern == 'IMPERATIVE':
            a.tense = 'imperative'
            return

        if not aux:
            # 没有助动词：只能是简单时态，看主动词形态。
            # *_malformed 是「拼错的变形」，时态意图仍然清楚（gos 意图三单现在时），
            # 所以按对应时态归类，形态错误留给检查器报。
            if mv_tag in ('3sg', '3sg_malformed'):
                a.tense = 'present_simple'
            elif mv_tag in ('past', 'past_malformed'):
                a.tense = 'past_simple'
            elif mv_tag == 'base':
                a.tense = 'present_simple'
            elif mv_tag in ('ing', 'pp'):
                # 非限定形单独做谓语 = 缺助动词，这是个语法错误，
                # 但分析器只负责如实报告结构，判错留给检查器。
                a.tense = None
                a.unresolved.append('nonfinite_verb_without_auxiliary')
            elif a.finite_verb_form_tag == 'be':
                a.tense = ('present_simple'
                           if a.finite_verb_surface.lower() in ('am', 'is', 'are')
                           else 'past_simple')
            return

        first = aux[0]
        # will / shall + 原形 = 将来时
        if first in ('will', 'shall'):
            if 'be' in aux and mv_tag == 'ing':
                a.tense = 'future_continuous'
            elif 'have' in aux and mv_tag == 'pp':
                a.tense = 'future_perfect'
            else:
                a.tense = 'future_simple'
            return
        # 其他情态动词：受控范围外的时态，标注为 modal
        if first in MODALS:
            a.tense = 'modal'
            a.unresolved.append('modal_out_of_tense_scope:' + first)
            return
        # have/has/had + pp = 完成时
        if first in HAVE_FINITE:
            base = 'past_perfect' if first == 'had' else 'present_perfect'
            if 'been' in aux and mv_tag == 'ing':
                a.tense = base.replace('perfect', 'perfect_continuous')
            else:
                a.tense = base
            return
        # do/does/did + 原形 = do-support 下的简单时态
        if first in DO_FINITE:
            a.tense = 'past_simple' if first == 'did' else 'present_simple'
            return
        # be + ing = 进行时；be + pp = 被动（受控范围外）
        if first in BE_FINITE:
            if mv_tag == 'ing':
                a.tense = ('present_continuous'
                           if first in ('am', 'is', 'are') else 'past_continuous')
            elif mv_tag == 'pp':
                a.tense = ('present_simple'
                           if first in ('am', 'is', 'are') else 'past_simple')
                a.unresolved.append('passive_voice_out_of_scope')
            else:
                # 系动词 be，没有主动词
                a.tense = ('present_simple'
                           if first in ('am', 'is', 'are') else 'past_simple')
            return
        a.tense = None
        a.unresolved.append('tense_undetermined')

    # ---- 第三步：极性 -----------------------------------------------------
    def _derive_polarity(self, a):
        """有 not 就是否定。never/seldom 等语义否定副词单独记，不覆盖 polarity，
        因为它们与 not 的语法行为不同（never 不需要 do-support 之外的处理）。"""
        if 'not' in a.lower:
            a.polarity = 'negative'
        elif any(w in NEGATIVE_ADVERBS for w in a.lower):
            a.polarity = 'negative'
        else:
            a.polarity = 'affirmative'

    # ---- 第四步：疑问 -----------------------------------------------------
    def _derive_question(self, a):
        if a.question == 'wh':
            return
        if a.has_question_mark:
            a.question = 'yes_no'
            return
        # 没问号但有倒装（助动词在主语前）也算疑问句——
        # 这样 "Is I happy" 这种漏了问号的测试用例也能正确归类。
        if a.subject_span and a.auxiliary_indices \
                and a.auxiliary_indices[0] < a.subject_span[0]:
            a.question = 'yes_no'
            return
        a.question = 'none'

    # ---- 第五步：句型 -----------------------------------------------------
    def _derive_pattern(self, a):
        """判定句型。只在受控范围内下结论，其余标 unknown。"""
        if a.pattern == 'IMPERATIVE':
            return
        if a.subject_is_expletive:
            a.pattern = 'THERE_BE'
            return
        if a.finite_verb_token_index is None:
            a.pattern = 'unknown'
            return

        tokens, low, n = a.tokens, a.lower, len(a.tokens)
        # 谓语之后的部分（跳过 not / 副词）
        start = (a.main_verb_token_index if a.main_verb_token_index is not None
                 else a.finite_verb_token_index) + 1
        rest = []
        for i in range(start, n):
            w = low[i]
            if w == 'not':
                continue
            rest.append((i, w))
        a.post_verb_tokens = [i for i, _ in rest]

        # 系动词句：be + 形容词/名词；或 taste/look/smell/sound/feel 这类
        # 系动词类实义动词（判据来自 verb_frames 的 copula 标志，不是硬编码词表）。
        #
        # 注意 taste 这类词是两栖的：
        #     The soup tastes good.   -> 系动词用法，good 是表语，SVP
        #     She tastes the soup.    -> 及物用法，the soup 是宾语，SVO
        # 所以只能"先按系动词试探，接不到形容词就掉回普通及物句"。
        copular_candidate = a.is_copula or (
            a.main_verb_lemma in self.copula_verbs)
        if copular_candidate:
            idx = 0
            while idx < len(rest):
                i, w = rest[idx]

                # 【第一优先：副词 + 形容词，副词只是修饰语】
                #   very happy / enough big / more good  （程度副词）
                #   is always happy                      （频度副词，中位）
                # 真正的表语是后面那个形容词，把副词跳过去继续找。
                # 这一步必须排在所有分支之前，因为 enough / much 这类词
                # 同时挂在形容词表和副词表里，先判 is_adjective 就会把
                # "enough big" 的表语误认成 enough。
                # 判据是「后面紧跟着形容词」，不是硬编码词表——
                # 副词后面没有形容词（The soup tastes well.）才算它占了表语位。
                nxt = rest[idx + 1][1] if idx + 1 < len(rest) else None
                if self.is_adverb(w) and nxt \
                        and (self.is_adjective(nxt)
                             or self.malformed_adjective_reading(nxt)):
                    idx += 1
                    continue

                if self.is_adverb(w) and not self.is_adjective(w):
                    # 其它副词占住表语位置：The soup tastes well.
                    # 这本身就是要抓的错误，如实记进 predicative 交检查器判。
                    a.predicative = w
                    a.predicative_surface = tokens[i]
                    a.predicative_index = i
                    a.predicative_form_tag = 'adverb'
                    a.pattern = 'SVP'
                    return
                if self.is_adjective(w):
                    lemma, tag = self.adj_form_tag.get(
                        w, (self.adj_surface[w], 'base'))
                    a.predicative = lemma
                    a.predicative_surface = tokens[i]
                    a.predicative_index = i
                    a.predicative_form_tag = tag
                    a.pattern = 'SVP'
                    return
                mal = self.malformed_adjective_reading(w)
                if mal:
                    # *gooder / *biger：词库查不到，但能推回 good / big。
                    # 记下推回的原形 + 原句实际拼写 + malformed 标签。
                    a.predicative, a.predicative_form_tag = mal
                    a.predicative_surface = tokens[i]
                    a.predicative_index = i
                    a.pattern = 'SVP'
                    return
                if self.is_determiner(w) or self.is_noun_surface(w):
                    if a.is_copula:
                        a.pattern = 'SVP'      # be + 名词短语仍是 SVP
                        np = self.parse_np(tokens, i)
                        if np:
                            a.noun_phrases.append(np)
                            a.objects = [np['head']]
                        return
                    break                      # taste + 名词 -> 掉到 SVO 分支
                break
            if a.is_copula:
                a.pattern = 'SVP' if rest else 'unknown'
                if not rest:
                    a.unresolved.append('copula_without_complement')
                return

        # 固定介词动词：listen to / wait for / look at
        if a.main_verb_lemma:
            frame = self.K.verb_frames.get(a.main_verb_lemma)
            fixed = (frame or {}).get('fixed_preposition')
            for i, w in rest:
                if self.is_adverb(w):
                    continue
                if w in PREPOSITIONS:
                    a.preposition = w
                    if fixed and w == fixed:
                        a.pattern = 'SV_PREP_O'
                        return
                break

        # 扫描谓语之后的成分：名词短语 / 介词短语 / 不定式 / 动名词 / 形容词补语。
        # 用 PHP 的思路说，这是一个「按优先级依次 match，命中就吃掉一段」的循环。
        nps = []
        i = start
        ss = a.subject_span
        while i < n:
            w = low[i]
            # 倒装疑问句（Reads she books?）里主语在动词之后，已被 _assign_subject
            # 认领，不能再当宾语数进去——否则 she 会被误判成第一个宾语 -> SVOO。
            # 对正常陈述句，主语在动词之前、subject_span 与这里不重叠，跳过无副作用。
            if ss and ss[0] <= i < ss[1]:
                i += 1
                continue
            if w == 'not' or (self.is_adverb(w) and not self.is_adjective(w)):
                i += 1
                continue

            # (a) to + 动词原形 = 不定式补语（to read / to cry）
            #     必须排在介词分支之前，否则 to 会被当成介词。
            if w == 'to' and i + 1 < n:
                nxt = low[i + 1]
                base = [r for r in self.verb_readings(nxt) if r[1] == 'base']
                if base and not self.is_determiner(nxt):
                    if a.complement is None:
                        a.complement = {'type': 'to_infinitive',
                                        'index': i + 1, 'lemma': base[0][0]}
                    i += 2
                    continue

            # (b) 介词短语：整段跳过，不算宾语
            if w in PREPOSITIONS:
                a.preposition = a.preposition or w
                np = self.parse_np(tokens, i + 1)
                if np:
                    a.noun_phrases.append(np)
                    i = np['span'][1]
                else:
                    i += 1
                continue

            # (c) 宾格代词：him / her / them / me / us / it
            if w in self.pronoun_object_forms and not self.is_noun_surface(w):
                row = self.pronoun_object_forms[w]
                nps.append({'head': w, 'number': row['number'],
                            'span': (i, i + 1), 'is_pronoun': True,
                            'adjectives': [], 'determiner': None})
                i += 1
                continue

            # (d) 名词短语
            np = self.parse_np(tokens, i)
            if np:
                nps.append(np)
                a.noun_phrases.append(np)
                i = np['span'][1]
                continue

            # (e) 光杆动词形态：-ing 是动名词补语，原形是不带 to 的不定式
            readings = self.verb_readings(w)
            if readings:
                ing = [r for r in readings if r[1] == 'ing']
                base = [r for r in readings if r[1] == 'base']
                if ing and a.complement is None:
                    a.complement = {'type': 'gerund', 'index': i,
                                    'lemma': ing[0][0]}
                elif base and a.complement is None:
                    a.complement = {'type': 'bare_infinitive', 'index': i,
                                    'lemma': base[0][0]}
                i += 1
                continue
            i += 1

        a.objects = [np['head'] for np in nps]
        if len(nps) == 0:
            a.pattern = 'SV' if a.complement is None else 'SV_COMP'
        elif len(nps) == 1:
            a.pattern = 'SVO'
        elif len(nps) == 2:
            # 两个 NP：可能是双宾（SVOO），也可能是宾补（SVOC，补语为名词）
            a.pattern = 'SVOO'
        else:
            a.pattern = 'unknown'
            a.unresolved.append('too_many_noun_phrases')

        # 宾语之后还有补语 -> SVOC（She makes him cry. / She makes me happy.）
        if len(nps) == 1:
            after = nps[0]['span'][1]
            if a.complement and a.complement['index'] >= after:
                a.pattern = 'SVOC'
            else:
                for i in range(after, n):
                    w = low[i]
                    # 这里跳过【所有】副词，而不只是"不兼职形容词的副词"。
                    # 原因：I like it very much. 里的 much 既在形容词表又在副词表，
                    # 旧写法会把它当宾补，误判成 SVOC + predicative='much'，
                    # 进而触发一串"表语不合法"的假阳性。
                    if self.is_adverb(w):
                        continue
                    if self.is_adjective(w):
                        lemma, tag = self.adj_form_tag.get(
                            w, (self.adj_surface[w], 'base'))
                        a.predicative = lemma
                        a.predicative_surface = a.tokens[i]
                        a.predicative_index = i
                        a.predicative_form_tag = tag
                        a.pattern = 'SVOC'
                    break

    # ---- 第六步：句面自校验（用户要求的硬门槛）-----------------------------
    def _surface_selfcheck(self, a):
        """验证分析结果与原句真的对得上。

        用户的原话是：「token index 对应的单词必须等于 finite_verb_surface；
        主语文本必须真实存在于句首相应位置。结构信息与句面不符时返回
        analysis_surface_mismatch」。

        这一步看似多余（数据是我们自己填的），但它是防回归的保险丝：
        今后有人改了 _locate_core 却忘了同步下标，这里立刻炸掉，
        而不是让错误的下标悄悄流进检查器。
        """
        ok = True
        # 1) 限定动词下标必须真的指向那个词
        if a.finite_verb_token_index is not None:
            idx = a.finite_verb_token_index
            if not (0 <= idx < len(a.tokens)):
                a.unresolved.append('finite_verb_index_out_of_range')
                ok = False
            elif a.tokens[idx] != a.finite_verb_surface:
                a.unresolved.append('finite_verb_surface_index_mismatch')
                ok = False
        # 2) 主动词下标同理
        if a.main_verb_token_index is not None:
            idx = a.main_verb_token_index
            if not (0 <= idx < len(a.tokens)) \
                    or a.tokens[idx] != a.main_verb_surface:
                a.unresolved.append('main_verb_surface_index_mismatch')
                ok = False
        # 3) 主语文本必须能在它声明的区间里原样拼回来
        if a.subject_span and a.subject_text is not None:
            s, e = a.subject_span
            if ' '.join(a.tokens[s:e]) != a.subject_text:
                a.unresolved.append('subject_span_text_mismatch')
                ok = False
        # 4) 助动词下标一一对应
        for idx, surf in zip(a.auxiliary_indices, a.auxiliary_surfaces):
            if not (0 <= idx < len(a.tokens)) or a.tokens[idx] != surf:
                a.unresolved.append('auxiliary_surface_index_mismatch')
                ok = False
                break
        a.surface_ok = ok


# ---------------------------------------------------------------------------
# 声明 vs 句面 对账：堵死「伪造 info 骗测试」
# ---------------------------------------------------------------------------
def verify_declaration(analysis, declared):
    """把调用方声明的 info 与句面分析结果逐项对账。

    返回 mismatch 原因列表（空列表 = 一致）。
    检查器拿到非空列表时，必须直接报 analysis_surface_mismatch 并停止后续判断——
    因为在结构信息都对不上的情况下，任何语法结论都是空中楼阁。

    用户举的例子：把 "She likes music." 标成 tense=present_continuous
    企图触发 stative_in_continuous。对账后发现句面是 present_simple，
    于是先报结构冲突，不给它蒙混过关的机会。

    对账项（只对账 declared 里真的写了的字段，没写的不管）：
      tense / polarity / question / verb / person / number / pattern / is_be
    """
    bad = []

    def declared_has(key):
        return key in declared and declared[key] is not None

    if declared_has('tense'):
        # imperative / modal 这类分析器专用标记不参与对账
        if analysis.tense and analysis.tense not in ('imperative', 'modal') \
                and declared['tense'] != analysis.tense:
            bad.append(f"tense:declared={declared['tense']},"
                       f"surface={analysis.tense}")

    if declared_has('polarity') and declared['polarity'] != analysis.polarity:
        bad.append(f"polarity:declared={declared['polarity']},"
                   f"surface={analysis.polarity}")

    if declared_has('question') and analysis.question != 'wh' \
            and declared['question'] != analysis.question:
        bad.append(f"question:declared={declared['question']},"
                   f"surface={analysis.question}")

    if declared_has('verb'):
        surface_verb = analysis.main_verb_lemma or analysis.finite_verb_lemma
        if surface_verb and declared['verb'] != surface_verb:
            bad.append(f"verb:declared={declared['verb']},surface={surface_verb}")

    if declared_has('person') and analysis.subject_person \
            and declared['person'] != analysis.subject_person:
        bad.append(f"person:declared={declared['person']},"
                   f"surface={analysis.subject_person}")

    if declared_has('number') and analysis.subject_number \
            and analysis.subject_number != 'both' \
            and declared['number'] != analysis.subject_number:
        bad.append(f"number:declared={declared['number']},"
                   f"surface={analysis.subject_number}")

    if declared_has('is_be'):
        # is_be 声明「这是系动词句」。句面上系动词句的特征是：
        # 限定动词是 be，且没有主动词（有主动词就是进行时/被动，不是系动词）。
        surface_is_be = analysis.is_copula
        # 进行时也走 be，但生成器把 is_be 用于「be 作谓语核心」的场合，
        # 因此这里只在「声明 is_be=True 而句面连 be 都没有」时判冲突。
        if declared['is_be'] and analysis.finite_verb_lemma != 'be' \
                and analysis.finite_verb_lemma is not None:
            bad.append('is_be:declared=True,surface_has_no_be')
        if not declared['is_be'] and surface_is_be \
                and analysis.finite_verb_lemma == 'be':
            bad.append('is_be:declared=False,surface_is_copula')

    if declared_has('pattern') and declared['pattern'] not in ('X',) \
            and analysis.pattern not in ('unknown',) \
            and declared['pattern'] != analysis.pattern:
        # pattern 声明冲突只在两者都确定时才算数
        bad.append(f"pattern:declared={declared['pattern']},"
                   f"surface={analysis.pattern}")

    return bad


# ---------------------------------------------------------------------------
# 自检：直接运行本文件时跑一批固定用例，证明分析器本身是对的
# ---------------------------------------------------------------------------
def _selftest():
    """analyzer 自己的单元测试。

    只有分析器先被证明可靠，基于它的检查器结论才有意义。
    这里刻意包含了「名词短语主语」这一整类——正是旧代码 tokens[1] 挂掉的地方。
    """
    # 运行时才 import，避免模块级循环依赖
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mini_generator as mg
    mg.K = mg.Knowledge()
    az = Analyzer(mg.K)

    # (句子, 期望字段字典)
    cases = [
        ("He runs.", dict(subject_head='he', subject_person=3,
                          subject_number='singular',
                          finite_verb_lemma='run', finite_verb_token_index=1,
                          tense='present_simple', pattern='SV')),
        ("The dog runs.", dict(subject_text='The dog', subject_head='dog',
                               subject_number='singular',
                               finite_verb_lemma='run',
                               finite_verb_token_index=2,
                               tense='present_simple', pattern='SV')),
        ("The dog run.", dict(subject_head='dog', subject_number='singular',
                              finite_verb_lemma='run',
                              finite_verb_token_index=2)),
        ("The scissors are sharp.", dict(subject_head='scissors',
                                         subject_number='plural',
                                         finite_verb_lemma='be',
                                         finite_verb_token_index=2,
                                         pattern='SVP', predicative='sharp')),
        ("The scissors is sharp.", dict(subject_head='scissors',
                                        subject_number='plural',
                                        finite_verb_surface='is')),
        ("She likes music.", dict(subject_head='she',
                                  main_verb_lemma='like',
                                  main_verb_form_tag='3sg',
                                  tense='present_simple', pattern='SVO')),
        ("She is liking music.", dict(main_verb_lemma='like',
                                      main_verb_form_tag='ing',
                                      tense='present_continuous')),
        ("I know the answer.", dict(subject_head='i', main_verb_lemma='know',
                                    tense='present_simple', pattern='SVO')),
        ("She does not read a book.", dict(subject_head='she',
                                           main_verb_lemma='read',
                                           tense='present_simple',
                                           polarity='negative')),
        ("Does she read a book?", dict(subject_head='she',
                                       main_verb_lemma='read',
                                       question='yes_no',
                                       finite_verb_token_index=0)),
        ("She has eaten an apple.", dict(main_verb_lemma='eat',
                                         main_verb_form_tag='pp',
                                         tense='present_perfect')),
        ("There are two books on the desk.", dict(subject_is_expletive=True,
                                                  pattern='THERE_BE')),
        ("Open the door.", dict(pattern='IMPERATIVE',
                                finite_verb_lemma='open',
                                subject_person=2)),
        ("Two sheep eat grass.", dict(subject_head='sheep',
                                      subject_number='plural',
                                      main_verb_lemma='eat')),
        ("The family is happy.", dict(subject_head='family', pattern='SVP')),
        # 系动词类实义动词：taste 接形容词是 SVP，接名词是 SVO
        ("The soup tastes good.", dict(main_verb_lemma='taste',
                                       pattern='SVP', predicative='good')),
        ("The soup tastes well.", dict(main_verb_lemma='taste',
                                       pattern='SVP', predicative='well')),
        # 补语类型识别：动名词 / 不定式 / 不带 to 的不定式
        ("She enjoys reading.", dict(main_verb_lemma='enjoy',
                                     complement={'type': 'gerund', 'index': 2,
                                                 'lemma': 'read'})),
        ("She enjoys to read.", dict(main_verb_lemma='enjoy',
                                     complement={'type': 'to_infinitive',
                                                 'index': 3, 'lemma': 'read'})),
        ("She makes him cry.", dict(main_verb_lemma='make', objects=['him'],
                                    pattern='SVOC',
                                    complement={'type': 'bare_infinitive',
                                                'index': 3, 'lemma': 'cry'})),
        ("She makes him to cry.", dict(main_verb_lemma='make',
                                       objects=['him'], pattern='SVOC',
                                       complement={'type': 'to_infinitive',
                                                   'index': 4,
                                                   'lemma': 'cry'})),
        # 固定介词
        ("She listens to music.", dict(main_verb_lemma='listen',
                                       pattern='SV_PREP_O', preposition='to')),
        ("She listens music.", dict(main_verb_lemma='listen',
                                    pattern='SVO', objects=['music'])),
        # 双宾
        ("He gives her a gift.", dict(main_verb_lemma='give',
                                      objects=['her', 'gift'],
                                      pattern='SVOO')),
        # plural_only 名词做宾语时的数
        ("She buys two scissors.", dict(main_verb_lemma='buy',
                                        objects=['scissors'])),
    ]

    nfail = 0
    for sent, expect in cases:
        a = az.analyze(sent)
        diffs = []
        for k, v in expect.items():
            got = getattr(a, k)
            if got != v:
                diffs.append(f"{k}: 期望 {v!r} 实际 {got!r}")
        if not a.surface_ok:
            diffs.append('surface_ok=False -> ' + ','.join(a.unresolved))
        status = 'OK ' if not diffs else 'FAIL'
        print(f"  [{status}] {sent}")
        if diffs:
            nfail += 1
            for d in diffs:
                print(f"          {d}")
            print(f"          分析结果：{a!r}")

    # 对账功能自检：伪造 info 必须被抓到
    a = az.analyze("She likes music.")
    bad = verify_declaration(a, dict(tense='present_continuous', verb='like'))
    print(f"  [{'OK ' if bad else 'FAIL'}] 伪造 tense=present_continuous 被抓到: {bad}")
    if not bad:
        nfail += 1
    bad2 = verify_declaration(a, dict(tense='present_simple', verb='like',
                                      person=3, number='singular'))
    print(f"  [{'OK ' if not bad2 else 'FAIL'}] 真实声明不误报: {bad2}")
    if bad2:
        nfail += 1

    if nfail:
        print(f"\n[FAIL] 分析器自检 {nfail} 项未通过")
        sys.exit(1)
    print("\n[PASS] 分析器自检全部通过")


if __name__ == '__main__':
    _selftest()
