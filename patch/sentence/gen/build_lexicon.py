#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
造句知识库 lexicon 生成器（P3：任务13/15/18/19/21）
====================================================

职责：
  把本文件内嵌的「人工判定表」展开成四个 lexicon JSON：
    lexicon/noun_usage.json       —— 名词用法（可数性/单复数行为/语义类别）
    lexicon/verb_frames.json      —— 动词句法框架（SV/SVO/SVOO/SVOC/固定介词/补语）
    lexicon/adjective_usage.json  —— 形容词用法（定语/表语/分级/比较策略/补语）
    lexicon/adverb_usage.json     —— 副词位置（类别/front-mid-end/修饰对象）

设计原则（与 patch/gen/build_builtin_vocab.py 同一套路）：
  1. 判定表是唯一事实源，全部为人工逐词判定（curated_by_agent），脚本只做
     确定性的"展开 + 补默认值 + 排序 + 落盘"，绝不做任何语言学猜测。
  2. 三个策略维度不在这里重复判定，而是直接读取 annotations/ 三张策略表：
        动词 stative_policy   ← annotations/stative_policy.json
        形容词 gradability    ← annotations/gradability_policy.json
        名词 number_behavior  ← annotations/number_behavior.json（命中才覆盖）
     这样 lexicon 与 annotations 永远零冲突（验证工具还会二次交叉核对）。
  3. 词条以系统基线（patch/*.json）为主，少量基线外高频词（police/information/
     glasses/manner 副词/内容形容词）允许收录——lexicon 与 annotations 一样属
     "外部语法知识"，按 spelling+pos 联接，用户词库出现同名词时同样受益。
  4. 未知一律写 unknown / 不收录，禁止默认可数、默认及物。

运行：
  /Users/iguoji/.workbuddy/binaries/python/envs/default/bin/python \
      patch/sentence/gen/build_lexicon.py
"""

import json
import os

# --------------------------------------------------------------------------
# 路径：本文件在 patch/sentence/gen/，上一层是 patch/sentence
# --------------------------------------------------------------------------
GEN_DIR = os.path.dirname(os.path.abspath(__file__))
SENT_DIR = os.path.dirname(GEN_DIR)
LEX_DIR = os.path.join(SENT_DIR, 'lexicon')
ANN_DIR = os.path.join(SENT_DIR, 'annotations')

CHECKED_AT = '2026-07-30'   # 本批判定日期（全部人工复核过）

# 溯源信息：本批全部为"由智能体逐词判定 + 已复核 + 高置信"
PROV = {"source": "curated_by_agent", "reviewed": True,
        "confidence": "high", "checked_at": CHECKED_AT}


def load_annotation(fname):
    """读取一张策略表，返回 {拼写: policy} 字典（策略表是外部语法知识的唯一事实源）"""
    with open(os.path.join(ANN_DIR, fname), encoding='utf-8') as f:
        return {k: v['policy'] for k, v in json.load(f)['entries'].items()}


# 三张策略表：生成时直接引用，保证 lexicon 与 annotations 零冲突
NUMBER_POLICY = load_annotation('number_behavior.json')     # 名词单复数行为
STATIVE_POLICY = load_annotation('stative_policy.json')     # 动词静态性
GRADABILITY_POLICY = load_annotation('gradability_policy.json')  # 形容词分级性


# ==========================================================================
# 一、名词用法判定表（任务13 + 任务21 语义分类）
# ==========================================================================
# 普通规则可数名词按语义类别分组（人工归类），默认：
#   countability=countable, number_behavior=regular, default_number=singular
NOUN_REGULAR_BY_CATEGORY = {
    # 人物类（可作 SVO 主语；is_person 语义由此类别表达，任务21）
    "person": [
        "boy", "girl", "man", "woman", "child", "baby", "friend", "teacher",
        "student", "doctor", "nurse", "farmer", "driver", "parent", "cousin",
        "aunt", "uncle", "king", "queen", "lady", "guest", "boss", "artist",
        "actor", "hero", "person",
    ],
    # 动物类（可作 eat/run 等 animate 主语）
    "animal": [
        "dog", "cat", "bird", "horse", "cow", "pig", "monkey", "elephant",
        "lion", "tiger", "duck", "hen", "goat", "goose", "ox", "rabbit",
        "frog", "bear", "panda", "mouse",
    ],
    # 食物类·可数（eat 的合法宾语，object_restriction=edible）
    "food": [
        "apple", "banana", "egg", "carrot", "lemon", "onion", "orange",
        "peach", "pear", "pie", "cookie", "bean",
    ],
    # 物品类（拿/放/用 的具体宾语）
    "object": [
        "book", "pen", "pencil", "desk", "chair", "table", "door", "window",
        "car", "bus", "bike", "boat", "plane", "phone", "computer", "camera",
        "key", "knife", "fork", "cup", "bottle", "box", "bag", "ball",
        "clock", "lamp", "mirror", "umbrella", "toy", "gift", "picture",
        "letter", "map",
    ],
    # 地点类（go to / at 的宾语）
    "place": [
        "school", "house", "park", "farm", "factory", "hospital", "library",
        "kitchen", "bathroom", "bedroom", "garden", "city", "country",
        "market", "office", "church", "beach", "mountain", "lake", "island",
        "forest", "shop", "store", "street", "room", "zoo", "station",
    ],
    # 时间类（时间状语）
    "time": [
        "day", "night", "morning", "evening", "hour", "minute", "week",
        "month", "year", "birthday",
    ],
    # 抽象类·可数
    "abstract": [
        "idea", "question", "answer", "story", "song", "game", "dream",
    ],
}

# 不可数（物质/抽象）名词：countability=uncountable, number_behavior=mass,
# 禁止不定冠词（*a water），谓语一致按单数
NOUN_MASS = {
    "food":  ["bread", "rice", "meat", "cheese", "beef", "butter", "corn", "soup"],
    "drink": ["milk", "water", "coffee", "tea", "juice", "beer", "wine"],
    "abstract": ["advice", "money", "music", "knowledge", "health", "energy",
                 "history", "grammar", "math", "information"],
}

# 特殊名词：逐词人工判定（不能用任何默认值概括的少数派）
NOUN_SPECIAL = [
    # ---- 集体名词 ----
    {"spelling": "people", "countability": "countable", "number_behavior": "collective",
     "semantic_category": "person", "default_number": "plural",
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "three people 直接计数；*a people（民族义除外，本表不收）"},
    {"spelling": "police", "countability": "uncountable", "number_behavior": "collective",
     "semantic_category": "person", "default_number": "plural",
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "the police are...；计数用 police officers"},
    {"spelling": "cattle", "countability": "countable", "number_behavior": "collective",
     "semantic_category": "animal", "default_number": "plural",
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "twenty cattle 合法；*a cattle"},
    {"spelling": "family", "countability": "countable", "number_behavior": "collective",
     "semantic_category": "person", "default_number": "singular",
     "verb_agreement": "both", "notes": "英式可 my family are；生成器默认单数一致"},
    {"spelling": "team", "countability": "countable", "number_behavior": "collective",
     "semantic_category": "person", "default_number": "singular",
     "verb_agreement": "both"},
    {"spelling": "group", "countability": "countable", "number_behavior": "collective",
     "semantic_category": "person", "default_number": "singular",
     "verb_agreement": "both"},
    # ---- 单复同形 ----
    {"spelling": "sheep", "countability": "countable", "number_behavior": "invariant",
     "semantic_category": "animal", "verb_agreement": "both",
     "notes": "a sheep / two sheep；谓语随指称数"},
    {"spelling": "deer", "countability": "countable", "number_behavior": "invariant",
     "semantic_category": "animal", "verb_agreement": "both"},
    {"spelling": "fish", "countability": "countable", "number_behavior": "invariant",
     "semantic_category": "animal", "verb_agreement": "both",
     "notes": "复数 fish；fishes 仅指多鱼种，生成器不用"},
    # ---- 只有复数形 ----
    {"spelling": "scissors", "countability": "countable", "number_behavior": "plural_only",
     "semantic_category": "object", "default_number": "plural", "pair_construction": True,
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "计数必须 a pair of scissors"},
    {"spelling": "pants", "countability": "countable", "number_behavior": "plural_only",
     "semantic_category": "object", "default_number": "plural", "pair_construction": True,
     "indefinite_article_override": "none", "verb_agreement": "plural"},
    {"spelling": "jeans", "countability": "countable", "number_behavior": "plural_only",
     "semantic_category": "object", "default_number": "plural", "pair_construction": True,
     "indefinite_article_override": "none", "verb_agreement": "plural"},
    {"spelling": "glasses", "countability": "countable", "number_behavior": "plural_only",
     "semantic_category": "object", "default_number": "plural", "pair_construction": True,
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "眼镜义；玻璃杯义是 glass 的规则复数，另词处理"},
    {"spelling": "clothes", "countability": "uncountable", "number_behavior": "plural_only",
     "semantic_category": "object", "default_number": "plural", "pair_construction": False,
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "*three clothes / *a pair of clothes；计数换 pieces of clothing"},
    {"spelling": "stairs", "countability": "countable", "number_behavior": "plural_only",
     "semantic_category": "place", "default_number": "plural", "pair_construction": False,
     "indefinite_article_override": "none", "verb_agreement": "plural",
     "notes": "习惯用复数；单数 stair 罕用，生成器不产出"},
    # ---- 特殊抽象/时间 ----
    {"spelling": "news", "countability": "uncountable", "number_behavior": "mass",
     "semantic_category": "abstract", "default_number": "singular",
     "indefinite_article_override": "none", "verb_agreement": "singular",
     "notes": "形似复数实为单数：The news is good；计数 a piece of news"},
    {"spelling": "home", "countability": "countable", "number_behavior": "regular",
     "semantic_category": "place",
     "notes": "go home / at home 为副词性用法，不加冠词与介词 to"},
    {"spelling": "cake", "countability": "both", "number_behavior": "regular",
     "semantic_category": "food",
     "notes": "a cake 整只可数 / some cake 切块不可数；生成器默认按可数用"},
    {"spelling": "candy", "countability": "both", "number_behavior": "regular",
     "semantic_category": "food", "notes": "美式 a candy 可数；也常作物质名词"},
    {"spelling": "cabbage", "countability": "both", "number_behavior": "regular",
     "semantic_category": "food", "notes": "a cabbage 整棵 / some cabbage 菜肴"},
]


def build_noun_usage():
    """展开名词判定表 → noun_usage.json 条目列表（含与 annotations 的对齐）"""
    entries = []
    # 1) 规则可数名词：按类别批量展开，字段全部取默认值
    for cat, words in NOUN_REGULAR_BY_CATEGORY.items():
        for sp in words:
            entries.append({
                "spelling": sp, "pos": "n.",
                "countability": "countable",
                "number_behavior": "regular",
                "default_number": "singular",
                "semantic_category": cat,
                "provenance": dict(PROV),
            })
    # 2) 物质/抽象不可数：mass + 禁不定冠词 + 谓语单数
    for cat, words in NOUN_MASS.items():
        for sp in words:
            entries.append({
                "spelling": sp, "pos": "n.",
                "countability": "uncountable",
                "number_behavior": "mass",
                "default_number": "singular",
                "indefinite_article_override": "none",
                "verb_agreement": "singular",
                "semantic_category": cat,
                "provenance": dict(PROV),
            })
    # 3) 特殊名词：逐词判定直接采用
    for item in NOUN_SPECIAL:
        e = dict(item)
        e["pos"] = "n."
        e["provenance"] = dict(PROV)
        entries.append(e)
    # 4) 对齐校验：凡 annotations/number_behavior 已判定的词，本表必须一致
    for e in entries:
        pol = NUMBER_POLICY.get(e["spelling"])
        if pol and pol != e["number_behavior"]:
            raise SystemExit(f"[冲突] {e['spelling']}: lexicon={e['number_behavior']} "
                             f"annotations={pol}，请先统一判定")
    entries.sort(key=lambda x: x["spelling"])
    return entries


# ==========================================================================
# 二、动词句法框架判定表（任务15）
# ==========================================================================
# 元组格式：(拼写, pos基线词性, frames, 额外字段dict)
# stative_policy 不在此判定：命中 annotations/stative_policy.json 用表值，否则 dynamic
VERB_FRAMES = [
    # ---- 系动词 / 半系动词（SVP：主语+系+表语）----
    ("be", "vlink.", ["SVP"], {"copula": True, "allows_passive": "no",
        "stative_override": "usually_stative",
        "notes": "唯一纯系动词；变位由 paradigms/auxiliaries.json 提供"}),
    ("become", "vi.", ["SVP"], {"copula": True, "allows_passive": "no",
        "complement_types": ["adjective", "noun_phrase"]}),
    ("seem", "vi.", ["SVP", "SV_COMP"], {"copula": True, "allows_passive": "no",
        "complement_types": ["adjective", "to_infinitive"],
        "notes": "seem happy / seem to know"}),
    ("look", "vi.", ["SVP", "SV_PREP_O"], {"copula": True, "fixed_preposition": "at",
        "allows_passive": "no", "complement_types": ["adjective"],
        "notes": "look happy(系) / look at(短语动词) 两用法"}),
    ("smell", "vi. vt.", ["SVP", "SVO"], {"copula": True,
        "complement_types": ["adjective"], "allows_passive": "yes"}),
    ("taste", "vi. vt.", ["SVP", "SVO"], {"copula": True,
        "complement_types": ["adjective"], "allows_passive": "yes"}),
    ("turn", "vt.", ["SVO", "SV", "SVP"], {"copula": True,
        "complement_types": ["adjective"], "allows_passive": "yes",
        "notes": "turn red 变得（系）；turn the key 转动（及物）"}),
    ("grow", "vi. vt.", ["SV", "SVO", "SVP"], {"copula": True,
        "complement_types": ["adjective"], "allows_passive": "yes",
        "notes": "grow old 渐变（系）；grow rice 种植（及物）"}),
    ("stay", "vi.", ["SV", "SVP"], {"copula": True,
        "complement_types": ["adjective"], "allows_passive": "no"}),
    ("get", "vt.", ["SVO", "SVP"], {"copula": True,
        "complement_types": ["adjective"], "allows_passive": "yes",
        "notes": "get tired 变化（系）；get a gift 获得（及物）"}),

    # ---- 双宾语动词（SVOO）----
    ("give", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to"}),
    ("send", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to"}),
    ("show", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to"}),
    ("sell", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to"}),
    ("teach", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to",
        "subject_restriction": "person"}),
    ("bring", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to"}),
    ("pay", "vt.", ["SVO", "SVOO"], {"dative_alternation": "to",
        "subject_restriction": "person"}),
    ("buy", "vt.", ["SVO", "SVOO"], {"dative_alternation": "for",
        "subject_restriction": "person"}),
    ("cook", "vt.", ["SVO", "SVOO"], {"dative_alternation": "for",
        "object_optional": True, "subject_restriction": "person"}),
    ("tell", "vt.", ["SVO", "SVOO", "SVOC"], {"dative_alternation": "to",
        "complement_types": ["to_infinitive", "that_clause"],
        "subject_restriction": "person",
        "notes": "tell him a story(双宾) / tell him to go(宾补)"}),
    ("ask", "vt.", ["SVO", "SVOO", "SVOC"], {"dative_alternation": "none",
        "complement_types": ["to_infinitive"], "subject_restriction": "person",
        "notes": "ask him a question；双宾不可改介词句"}),
    ("wish", "vt.", ["SVOO", "SV_COMP"], {"dative_alternation": "none",
        "complement_types": ["to_infinitive", "that_clause"],
        "subject_restriction": "person", "allows_passive": "no",
        "notes": "wish you luck(双宾) / wish to go(补语)；*wish a car"}),

    # ---- 宾语补足语动词（SVOC）----
    ("make", "vt.", ["SVO", "SVOO", "SVOC"], {"dative_alternation": "for",
        "complement_types": ["bare_infinitive", "adjective", "noun_phrase"],
        "notes": "make him cry / make him happy / make him a star"}),
    ("call", "vt.", ["SVO", "SVOC"], {"complement_types": ["noun_phrase"],
        "notes": "call him Tom"}),
    ("keep", "vt.", ["SVO", "SVOC"], {"complement_types": ["adjective", "gerund"],
        "notes": "keep the room clean / keep him waiting"}),
    ("find", "vt.", ["SVO", "SVOC"], {"complement_types": ["adjective"],
        "notes": "find the book interesting"}),
    ("let", "vt.", ["SVOC"], {"complement_types": ["bare_infinitive"],
        "allows_passive": "no", "notes": "let him go；无被动"}),
    ("help", "vt.", ["SVO", "SVOC"],
        {"complement_types": ["bare_infinitive", "to_infinitive"],
         "subject_restriction": "person"}),
    ("want", "vt.", ["SVO", "SVOC", "SV_COMP"],
        {"complement_types": ["to_infinitive"],
         "notes": "want a car / want him to go / want to go"}),
    ("see", "vt.", ["SVO", "SVOC"],
        {"complement_types": ["bare_infinitive", "gerund"],
         "subject_restriction": "animate",
         "notes": "see him cross(全程)/crossing(片段)"}),
    ("watch", "vt.", ["SVO", "SVOC"],
        {"complement_types": ["bare_infinitive", "gerund"],
         "subject_restriction": "animate"}),
    ("hear", "vt.", ["SVO", "SVOC"],
        {"complement_types": ["bare_infinitive", "gerund"],
         "subject_restriction": "animate"}),

    # ---- 从句/非谓语补语动词（SV_COMP：不能接普通名词短语宾语的用法单列）----
    ("hope", "vt.", ["SV_COMP"], {"complement_types": ["to_infinitive", "that_clause"],
        "allows_passive": "no", "subject_restriction": "person",
        "notes": "*hope a gift；接名词需 hope for"}),
    ("decide", "vi. vt.", ["SV_COMP"],
        {"complement_types": ["to_infinitive", "that_clause"],
         "subject_restriction": "person"}),
    ("promise", "vt.", ["SVO", "SVOO", "SV_COMP"], {"dative_alternation": "none",
        "complement_types": ["to_infinitive", "that_clause"],
        "subject_restriction": "person"}),
    ("plan", "vi. vt.", ["SVO", "SV_COMP"], {"complement_types": ["to_infinitive"],
        "subject_restriction": "person"}),
    ("learn", "vi. vt.", ["SV", "SVO", "SV_COMP"],
        {"complement_types": ["to_infinitive"], "subject_restriction": "person"}),
    ("try", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["to_infinitive", "gerund"],
         "notes": "try to do 设法 / try doing 尝试，义不同"}),
    ("like", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive"]}),
    ("love", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive"]}),
    ("hate", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive"]}),
    ("prefer", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive"]}),
    ("enjoy", "vt.", ["SVO", "SV_COMP"], {"complement_types": ["gerund"],
        "notes": "只接动名词：enjoy reading，*enjoy to read；宾语不可省"}),
    ("finish", "vi. vt.", ["SV", "SVO", "SV_COMP"], {"complement_types": ["gerund"],
        "notes": "只接动名词：finish doing"}),
    ("stop", "vi. vt.", ["SV", "SVO", "SV_COMP"], {"complement_types": ["gerund"],
        "notes": "stop doing 停止做；stop to do 的 to do 是目的状语不是补语"}),
    ("begin", "vi. vt.", ["SV", "SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive"]}),
    ("start", "vi. vt.", ["SV", "SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive"]}),
    ("remember", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive", "that_clause"],
         "notes": "remember to do 未做 / doing 已做，义不同"}),
    ("forget", "vt.", ["SVO", "SV_COMP"],
        {"complement_types": ["gerund", "to_infinitive", "that_clause"],
         "notes": "同 remember，to do/doing 义不同"}),
    ("know", "vt.", ["SVO", "SV_COMP"], {"complement_types": ["that_clause"],
        "subject_restriction": "person"}),
    ("think", "vi. vt.", ["SV", "SV_COMP", "SV_PREP_O"],
        {"complement_types": ["that_clause"], "fixed_preposition": "about",
         "subject_restriction": "person", "allows_passive": "no"}),
    ("believe", "vi. vt.", ["SVO", "SV_COMP"], {"complement_types": ["that_clause"],
        "subject_restriction": "person"}),
    ("say", "vt.", ["SVO", "SV_COMP"], {"complement_types": ["that_clause"],
        "subject_restriction": "person"}),
    ("understand", "vt.", ["SVO", "SV_COMP"], {"complement_types": ["that_clause"],
        "subject_restriction": "person"}),
    ("mean", "vt.", ["SVO", "SV_COMP"], {"complement_types": ["that_clause"]}),
    ("agree", "vi. vt.", ["SV", "SV_PREP_O", "SV_COMP"],
        {"fixed_preposition": "with",
         "complement_types": ["to_infinitive", "that_clause"],
         "subject_restriction": "person", "allows_passive": "no"}),

    # ---- 固定介词动词（SV_PREP_O）----
    ("listen", "vi.", ["SV", "SV_PREP_O"], {"fixed_preposition": "to",
        "subject_restriction": "animate", "allows_passive": "no"}),
    ("wait", "vi.", ["SV", "SV_PREP_O"], {"fixed_preposition": "for",
        "allows_passive": "no"}),
    ("talk", "vi.", ["SV", "SV_PREP_O"], {"fixed_preposition": "to",
        "subject_restriction": "person", "allows_passive": "no"}),
    ("belong", "vi.", ["SV_PREP_O"], {"fixed_preposition": "to",
        "allows_passive": "no"}),

    # ---- 天气动词（虚主语 it）----
    ("rain", "vi.", ["SV"], {"subject_restriction": "expletive_it",
        "allows_passive": "no", "notes": "It rains. *The dog rains"}),
    ("snow", "vi.", ["SV"], {"subject_restriction": "expletive_it",
        "allows_passive": "no"}),

    # ---- 纯不及物（SV）----
    ("run", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("walk", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("jump", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("swim", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("fly", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("sleep", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("sit", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("stand", "vi.", ["SV"], {"subject_restriction": "animate"}),
    ("come", "vi.", ["SV"], {}),
    ("go", "vi.", ["SV"], {}),
    ("arrive", "vi.", ["SV"], {"notes": "地点用 at(小)/in(大)，属状语非补语"}),
    ("dance", "vi.", ["SV"], {"subject_restriction": "person"}),
    ("laugh", "vi.", ["SV"], {"subject_restriction": "person"}),
    ("smile", "vi.", ["SV"], {"subject_restriction": "person"}),
    ("cry", "vi. vt.", ["SV"], {"subject_restriction": "person"}),
    ("travel", "vi.", ["SV"], {"subject_restriction": "person"}),
    ("work", "vi.", ["SV"], {"notes": "人工作/机器运转均可"}),
    ("live", "vi.", ["SV"], {"subject_restriction": "animate",
        "notes": "live in 的 in 属地点状语，非固定介词补语"}),
    ("shout", "vi. vt.", ["SV"], {"subject_restriction": "person"}),

    # ---- 及物为主（SVO；object_optional=True 表示可省宾语退化成 SV）----
    ("eat", "vt.", ["SVO"], {"object_optional": True,
        "subject_restriction": "animate", "object_restriction": "edible"}),
    ("drink", "vt.", ["SVO"], {"object_optional": True,
        "subject_restriction": "animate", "object_restriction": "drinkable"}),
    ("read", "vt.", ["SVO"], {"object_optional": True,
        "subject_restriction": "person", "object_restriction": "concrete"}),
    ("write", "vt.", ["SVO", "SVOO"], {"object_optional": True,
        "dative_alternation": "to", "subject_restriction": "person"}),
    ("draw", "vt.", ["SVO"], {"object_optional": True,
        "subject_restriction": "person"}),
    ("win", "vt.", ["SVO"], {"object_optional": True,
        "subject_restriction": "person"}),
    ("sing", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person"}),
    ("play", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "animate"}),
    ("study", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person"}),
    ("speak", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person",
        "notes": "speak English 语言作宾语"}),
    ("drive", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person"}),
    ("ride", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person"}),
    ("paint", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person"}),
    ("move", "vi. vt.", ["SV", "SVO"], {}),
    ("break", "vi. vt.", ["SV", "SVO"], {"notes": "The window broke（作格动词）"}),
    ("count", "vi. vt.", ["SV", "SVO"], {"subject_restriction": "person"}),
    ("leave", "vi. vt.", ["SV", "SVO"], {}),
    ("open", "vt.", ["SVO"], {}),
    ("close", "vt.", ["SVO"], {}),
    ("need", "vt.", ["SVO", "SV_COMP"], {"complement_types": ["to_infinitive"]}),
    ("take", "vt.", ["SVO"], {}),
    ("visit", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("wash", "vt.", ["SVO"], {"object_optional": True}),
    ("clean", "vt.", ["SVO"], {}),
    ("cut", "vt.", ["SVO"], {}),
    ("carry", "vt.", ["SVO"], {}),
    ("hold", "vt.", ["SVO"], {}),
    ("put", "vt.", ["SVO"], {"notes": "必须带地点状语：put it on the desk，*put it"}),
    ("lose", "vt.", ["SVO"], {}),
    ("use", "vt.", ["SVO"], {}),
    ("wear", "vt.", ["SVO"], {"subject_restriction": "person",
        "object_restriction": "concrete"}),
    ("throw", "vt.", ["SVO"], {"subject_restriction": "animate"}),
    ("catch", "vt.", ["SVO"], {"subject_restriction": "animate"}),
    ("hit", "vt.", ["SVO"], {}),
    ("push", "vt.", ["SVO"], {}),
    ("pull", "vt.", ["SVO"], {}),
    ("build", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("fix", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("repair", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("borrow", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("spend", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("save", "vt.", ["SVO"], {}),
    ("pick", "vt.", ["SVO"], {}),
    ("choose", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("share", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("own", "vt.", ["SVO"], {"subject_restriction": "person"}),
    ("fit", "vi. vt.", ["SV", "SVO"], {"allows_passive": "no",
        "notes": "The coat fits me；无被动"}),
]

# 不参与被动的框架组合：全部 frames 都是 SV/SVP/SV_PREP_O/SV_COMP 时默认 no
_NO_PASSIVE_FRAMES = {"SV", "SVP", "SV_PREP_O", "SV_COMP"}


def build_verb_frames():
    """展开动词判定表 → verb_frames.json 条目列表"""
    entries = []
    for spelling, pos, frames, extra in VERB_FRAMES:
        e = {"spelling": spelling, "pos": pos, "frames": list(frames)}
        # stative：优先本表显式覆盖（仅 be），其次策略表，最后 dynamic
        override = extra.pop("stative_override", None)
        e_extra = dict(extra)
        e.update(e_extra)
        e["stative_policy"] = override or STATIVE_POLICY.get(spelling, "dynamic")
        # allows_passive 默认值：含宾语框架→yes；纯不及物/系动词→no（显式值优先）
        if "allows_passive" not in e:
            has_object = any(f not in _NO_PASSIVE_FRAMES for f in frames)
            e["allows_passive"] = "yes" if has_object else "no"
        e["provenance"] = dict(PROV)
        entries.append(e)
    entries.sort(key=lambda x: x["spelling"])
    return entries


# ==========================================================================
# 三、形容词用法判定表（任务18）
# ==========================================================================
# 分组默认：定语+表语都可(yes/yes)；gradability 命中策略表用表值，否则 gradable
ADJ_INFLECTIONAL = [  # 单音节 / -y 双音节：-er/-est 屈折比较
    "big", "small", "good", "bad", "happy", "sad", "hot", "cold", "new",
    "old", "young", "tall", "short", "long", "high", "low", "fast", "slow",
    "early", "late", "easy", "hard", "dark", "bright", "warm", "cool",
    "dry", "wet", "hungry", "thirsty", "busy", "angry", "kind", "nice",
    "cheap", "loud", "fresh", "rich", "poor", "strong", "weak", "heavy",
    "light", "clean", "dirty", "safe", "sick", "ugly", "sorry", "healthy",
    "smart", "sweet", "full", "sure", "glad", "empty",
]
ADJ_PERIPHRASTIC = [  # 多音节：more/most 迂回比较
    "beautiful", "difficult", "expensive", "delicious", "interesting",
    "boring", "important", "careful", "dangerous", "tired", "afraid",
    "ready", "quiet", "clever", "interested", "different", "open",
    "wooden", "dead", "alive", "main", "favorite", "asleep", "awake",
    "alone", "ill",
]
ADJ_BOTH_STRATEGY = {"clever", "quiet"}       # -er/-est 与 more/most 均可
# 只能作表语（*an afraid child）
ADJ_PREDICATIVE_ONLY = {"afraid", "asleep", "awake", "alone", "ill", "glad",
                        "sorry", "ready"}
# 只能作定语（*The reason is main）
ADJ_ATTRIBUTIVE_ONLY = {"main", "favorite"}
# 策略表之外仍需判 usually_ungradable 的少数派（策略表只覆盖了部分）
ADJ_LOCAL_UNGRADABLE = {"asleep", "awake", "alone", "favorite"}
# 不规则比较级/最高级（多合法形均列出，与基线 string[] 约定一致）
ADJ_IRREGULAR_COMP = {
    "good": (["better"], ["best"]),
    "bad": (["worse"], ["worst"]),
}
# 单音节 CVC 双写比较级（防机械 -er 出 biger）
ADJ_DOUBLE_COMP = {
    "big": (["bigger"], ["biggest"]),
    "hot": (["hotter"], ["hottest"]),
    "sad": (["sadder"], ["saddest"]),
    "wet": (["wetter"], ["wettest"]),
}
# 常用补语搭配（afraid of / interested in / ready to ...）
ADJ_COMPLEMENTS = {
    "afraid": [("prep_of", "afraid of dogs"), ("to_infinitive", "afraid to go")],
    "interested": [("prep_in", "interested in music")],
    "good": [("prep_at", "good at math")],
    "bad": [("prep_at", "bad at cooking")],
    "angry": [("prep_with", "angry with him"), ("prep_about", "angry about it")],
    "kind": [("prep_to", "kind to animals")],
    "ready": [("to_infinitive", "ready to go"), ("prep_for", "ready for school")],
    "sorry": [("prep_for", "sorry for him"), ("prep_about", "sorry about that"),
              ("to_infinitive", "sorry to hear that")],
    "sure": [("prep_of", "sure of it"), ("that_clause", "sure that he will come"),
             ("to_infinitive", "sure to win")],
    "happy": [("to_infinitive", "happy to help"),
              ("that_clause", "happy that you came")],
    "glad": [("to_infinitive", "glad to see you"),
             ("that_clause", "glad that you came")],
    "tired": [("prep_of", "tired of waiting")],
    "full": [("prep_of", "full of water")],
    "different": [("prep_from", "different from mine")],
}


def build_adjective_usage():
    """展开形容词判定表 → adjective_usage.json 条目列表"""
    entries = []
    for group, strategy in ((ADJ_INFLECTIONAL, "inflectional"),
                            (ADJ_PERIPHRASTIC, "periphrastic")):
        for sp in group:
            # gradability：策略表优先（含 contextual），其次本地少数派，默认 gradable
            grad = GRADABILITY_POLICY.get(sp)
            if grad is None:
                grad = "usually_ungradable" if sp in ADJ_LOCAL_UNGRADABLE else "gradable"
            # 比较策略：不可分级 → none；双可 → both；其余按分组
            if grad == "usually_ungradable":
                strat = "none"
            elif sp in ADJ_BOTH_STRATEGY:
                strat = "both"
            else:
                strat = strategy
            e = {
                "spelling": sp, "pos": "adj.",
                "attributive": "no" if sp in ADJ_PREDICATIVE_ONLY else "yes",
                "predicative": "no" if sp in ADJ_ATTRIBUTIVE_ONLY else "yes",
                "gradability": grad,
                "comparison_strategy": strat,
            }
            if sp in ADJ_IRREGULAR_COMP:
                e["comparative"], e["superlative"] = ADJ_IRREGULAR_COMP[sp]
            elif sp in ADJ_DOUBLE_COMP:
                e["comparative"], e["superlative"] = ADJ_DOUBLE_COMP[sp]
            if sp in ADJ_COMPLEMENTS:
                e["complements"] = [{"type": t, "example": ex}
                                    for t, ex in ADJ_COMPLEMENTS[sp]]
            e["provenance"] = dict(PROV)
            entries.append(e)
    entries.sort(key=lambda x: x["spelling"])
    return entries


# ==========================================================================
# 四、副词位置判定表（任务19）
# ==========================================================================
# 元组格式：(拼写, 类别, 合法位置, 默认位置, 修饰对象, 备注)
ADVERBS = [
    # ---- 频度副词：中位（助动词后/实义动词前）----
    ("always", "frequency", ["mid"], "mid", ["verb"], ""),
    ("usually", "frequency", ["front", "mid"], "mid", ["verb"], ""),
    ("often", "frequency", ["mid", "end"], "mid", ["verb"], ""),
    ("sometimes", "frequency", ["front", "mid", "end"], "mid", ["verb"], ""),
    ("never", "frequency", ["mid"], "mid", ["verb"], "自带否定义，不与 not 连用"),
    ("rarely", "frequency", ["mid"], "mid", ["verb"], "自带否定义"),
    ("seldom", "frequency", ["mid"], "mid", ["verb"], "自带否定义"),
    ("ever", "frequency", ["mid"], "mid", ["verb"], "限疑问/否定/完成时"),
    ("hardly", "frequency", ["mid"], "mid", ["verb"], "自带否定义：hardly ever"),
    # ---- 时间副词：句尾为主，句首可强调 ----
    ("today", "time", ["front", "end"], "end", ["sentence"], ""),
    ("tomorrow", "time", ["front", "end"], "end", ["sentence"], ""),
    ("yesterday", "time", ["front", "end"], "end", ["sentence"], ""),
    ("now", "time", ["front", "mid", "end"], "end", ["sentence"], ""),
    ("soon", "time", ["end"], "end", ["sentence"], ""),
    ("then", "time", ["front", "end"], "end", ["sentence"], ""),
    ("already", "time", ["mid", "end"], "mid", ["verb"], "多用于肯定/完成时"),
    ("yet", "time", ["end"], "end", ["sentence"], "限否定与疑问：not...yet"),
    ("still", "time", ["mid"], "mid", ["verb"], ""),
    ("just", "time", ["mid"], "mid", ["verb"], "完成时常用：have just done"),
    ("again", "time", ["end"], "end", ["verb"], ""),
    # ---- 地点副词：句尾 ----
    ("here", "place", ["front", "end"], "end", ["sentence"], "无介词：come here"),
    ("there", "place", ["front", "end"], "end", ["sentence"], "无介词：go there"),
    ("away", "place", ["end"], "end", ["verb"], ""),
    ("ahead", "place", ["end"], "end", ["verb"], ""),
    # ---- 程度副词：紧贴被修饰的形容词/副词前，不修饰动词 ----
    ("very", "degree", ["mid"], "mid", ["adjective", "adverb"],
     "*very like；修饰动词改 very much 句尾"),
    ("too", "degree", ["mid"], "mid", ["adjective", "adverb"],
     "too big 过于；句尾'也'义另算"),
    ("quite", "degree", ["mid"], "mid", ["adjective", "adverb"], ""),
    ("rather", "degree", ["mid"], "mid", ["adjective", "adverb"], ""),
    ("so", "degree", ["mid"], "mid", ["adjective", "adverb"], "so big that..."),
    ("almost", "degree", ["mid"], "mid", ["verb", "adjective", "adverb"], ""),
    ("enough", "degree", ["end"], "end", ["adjective", "adverb"],
     "唯一后置的程度副词：good enough，*enough good"),
    # ---- 方式副词：句尾（基线外高频，供用户词与后续扩基线使用）----
    ("slowly", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("quickly", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("carefully", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("quietly", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("loudly", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("happily", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("easily", "manner", ["mid", "end"], "end", ["verb"], ""),
    ("badly", "manner", ["end"], "end", ["verb"], ""),
    ("well", "manner", ["end"], "end", ["verb"], "good 的副词形；不规则"),
    ("fast", "manner", ["end"], "end", ["verb"], "形副同形：run fast"),
    ("hard", "manner", ["end"], "end", ["verb"],
     "形副同形：work hard；hardly 是另一个词"),
    # ---- 评注/连接副词：句首 + 逗号 ----
    ("maybe", "comment", ["front"], "front", ["sentence"], ""),
    ("perhaps", "comment", ["front"], "front", ["sentence"], ""),
    ("however", "comment", ["front"], "front", ["sentence"], "句首需逗号"),
    ("also", "comment", ["mid"], "mid", ["sentence"], ""),
    ("only", "comment", ["mid"], "mid", ["sentence"], "位置影响辖域，默认中位"),
    ("even", "comment", ["mid"], "mid", ["sentence"], ""),
    ("together", "comment", ["end"], "end", ["verb"], ""),
    ("please", "comment", ["front", "end"], "front", ["sentence"], "祈使句礼貌标记"),
]


def build_adverb_usage():
    """展开副词判定表 → adverb_usage.json 条目列表"""
    entries = []
    for sp, cat, positions, default, modifies, notes in ADVERBS:
        e = {
            "spelling": sp, "pos": "adv.",
            "category": cat,
            "positions": list(positions),
            "default_position": default,
            "modifies": list(modifies),
        }
        if notes:
            e["notes"] = notes
        e["provenance"] = dict(PROV)
        entries.append(e)
    entries.sort(key=lambda x: x["spelling"])
    return entries


# ==========================================================================
# 主流程：展开四张表并落盘
# ==========================================================================
def main():
    os.makedirs(LEX_DIR, exist_ok=True)
    outputs = {
        'noun_usage.json': build_noun_usage(),
        'verb_frames.json': build_verb_frames(),
        'adjective_usage.json': build_adjective_usage(),
        'adverb_usage.json': build_adverb_usage(),
    }
    for fname, data in outputs.items():
        path = os.path.join(LEX_DIR, fname)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f"已生成 {os.path.relpath(path, os.path.dirname(SENT_DIR))}: {len(data)} 条")


if __name__ == '__main__':
    main()
