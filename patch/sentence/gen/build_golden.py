#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""重建 tests/golden.json
=========================
保留原有文档型测试组，注入可由生成器真实执行的 exec / exec_forbidden，
并补充 be_form_all_pronouns、svo_object_restriction_demo 两个回归组。

给小程序/PHP 背景的同学看的说明：
  这就像一个「数据迁移脚本」——读入现有 JSON，按 test_id 匹配后把可执行用例塞进去，
  再写回同一个文件。**必须幂等**：跑一次和跑十次结果一样，否则会像下面这样出事——
  早前版本用 data.append() 无条件追加，重复执行就多出一个同名 be_form_all_pronouns 组。
  现在改为 upsert（有则整组覆盖，无则追加）。
"""
import json, os

# 路径按 __file__ 推导：本文件在 patch/sentence/gen/，上一级即 patch/sentence/
SENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(SENT, 'tests/golden.json')
data = json.load(open(path, encoding='utf-8'))


def upsert(entry):
    """按 test_id 覆盖写入：已存在则整组替换（保证幂等），不存在才追加。"""
    tid = entry['test_id']
    for i, e in enumerate(data):
        if e.get('test_id') == tid:
            data[i] = entry
            return
    data.append(entry)


# 先清掉历史上重复追加产生的同名组（只保留第一处，后面由 upsert 覆盖内容）
seen = set()
_dedup = []
for e in data:
    tid = e.get('test_id')
    if tid in seen:
        continue
    seen.add(tid)
    _dedup.append(e)
data[:] = _dedup

# 各 test_id 注入的可执行黄金句（expect 必须与 generate() 输出逐字一致）
EXEC = {
    'sv_weather_expletive': [
        {"expect": "It rains.", "pattern": "SV", "tense": "present_simple",
         "polarity": "affirmative", "question": "none", "choice": {"verb": "rain"}},
        {"expect": "It is snowing.", "pattern": "SV", "tense": "present_continuous",
         "polarity": "affirmative", "question": "none", "choice": {"verb": "snow"}},
    ],
    'svo_uncountable_article': [
        {"expect": "She drinks some water.", "pattern": "SVO", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "drink", "subject": "she", "object": "water"}},
    ],
    'svo_object_restriction_edible': [
        {"expect": "She eats an apple.", "pattern": "SVO", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "eat", "subject": "she", "object": "apple"}},
        {"expect": "She ate an apple.", "pattern": "SVO", "tense": "past_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "eat", "subject": "she", "object": "apple"}},
    ],
    'svo_do_support_negation': [
        {"expect": "She does not read a book.", "pattern": "SVO", "tense": "present_simple",
         "polarity": "negative", "question": "none",
         "choice": {"verb": "read", "subject": "she", "object": "book"}},
    ],
    'svo_do_support_question': [
        {"expect": "Does she read a book?", "pattern": "SVO", "tense": "present_simple",
         "polarity": "affirmative", "question": "yes_no",
         "choice": {"verb": "read", "subject": "she", "object": "book"}},
    ],
    'svo_irregular_past': [
        {"expect": "She ate an apple.", "pattern": "SVO", "tense": "past_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "eat", "subject": "she", "object": "apple"}},
    ],
    'svp_copula_adjective': [
        {"expect": "She is happy.", "pattern": "SVP", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "be", "subject": "she", "predicative": "happy"}},
        {"expect": "He is happy.", "pattern": "SVP", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "be", "subject": "he", "predicative": "happy"}},
    ],
    'svp_ungradable_degree': [
        {"expect": "He is dead.", "pattern": "SVP", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "be", "subject": "he", "predicative": "dead"}},
    ],
    'there_be_agreement': [
        {"expect": "There is a book on the desk.", "pattern": "THERE_BE",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "choice": {"noun": "book", "np_number": "singular", "location": "desk"}},
        {"expect": "There is some water.", "pattern": "THERE_BE",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "choice": {"noun": "water", "with_location": False}},
        {"expect": "There are two dogs.", "pattern": "THERE_BE",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "choice": {"noun": "dog", "np_number": "plural", "with_location": False}},
    ],
    'there_be_definiteness': [
        {"expect": "There is a cat in the garden.", "pattern": "THERE_BE",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "choice": {"noun": "cat", "np_number": "singular", "location": "garden"}},
    ],
    'np_article_phonetic': [
        {"expect": "He visits a university.", "pattern": "SVO", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "visit", "subject": "he", "object": "university"}},
    ],
    'tense_perfect_participle': [
        {"expect": "She has eaten an apple.", "pattern": "SVO", "tense": "present_perfect",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "eat", "subject": "she", "object": "apple"}},
    ],
}
EXEC_FORBIDDEN = {
    'svo_stative_continuous': [
        {"expect_reject": "stative_in_continuous", "pattern": "SVO",
         "tense": "present_continuous", "polarity": "affirmative", "question": "none",
         "forbidden_sentence": "I am knowing the answer.",
         "choice": {"verb": "know", "subject": "I", "object": "answer"}},
    ],
    'there_be_agreement': [
        {"expect_reject": "forbid_there_be_continuous", "pattern": "THERE_BE",
         "tense": "present_continuous", "polarity": "affirmative", "question": "none",
         "forbidden_sentence": "There is being a book on the desk.",
         "choice": {}},
    ],
    # 虚主语动词只能接 it；强行指定 dog 作主语必须被 subject_restriction_unmet 拒绝
    'sv_weather_expletive': [
        {"expect_reject": "subject_restriction_unmet", "pattern": "SV",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "forbidden_sentence": "The dog rains.",
         "choice": {"verb": "rain", "subject": "dog"}},
    ],
    # eat 宾语必须可食用；eat+desk 必须被 object_restriction_unmet 拒绝
    'svo_object_restriction_edible': [
        {"expect_reject": "object_restriction_unmet", "pattern": "SVO",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "forbidden_sentence": "The boy eats a desk.",
         "choice": {"verb": "eat", "subject": "she", "object": "desk"}},
    ],
}

# 已经具备独立检查能力的禁止句，直接附上 check_info。
# 这样 forbidden 不再只是文档文字，而会在 golden 模式中逐句交给 check_grammar()。
CHECK_INFO = {
    'svo_uncountable_article': {
        "She drinks a water.": {"pattern": "SVO", "tense": "present_simple",
                                 "verb": "drink", "object_noun": "water",
                                 "mass_object": True, "person": 3, "number": "singular"},
        "She drinks two waters.": {"pattern": "SVO", "tense": "present_simple",
                                    "verb": "drink", "object_noun": "water",
                                    "mass_object": True, "person": 3, "number": "singular"},
    },
    'svo_do_support_negation': {
        "She reads not books.": {"pattern": "SVO", "tense": "present_simple",
                                  "polarity": "negative", "verb": "read",
                                  "object_noun": "book", "person": 3,
                                  "number": "singular"},
        "She does not reads books.": {"pattern": "SVO", "tense": "present_simple",
                                       "polarity": "negative", "verb": "read",
                                       "object_noun": "book", "person": 3,
                                       "number": "singular"},
    },
    'svo_do_support_question': {
        "Reads she books?": {"pattern": "SVO", "tense": "present_simple",
                              "question": "yes_no", "verb": "read",
                              "object_noun": "book", "person": 3,
                              "number": "singular"},
        "Does she reads books?": {"pattern": "SVO", "tense": "present_simple",
                                   "question": "yes_no", "verb": "read",
                                   "object_noun": "book", "person": 3,
                                   "number": "singular"},
    },
    'svo_irregular_past': {
        "She eated an apple.": {"pattern": "SVO", "tense": "past_simple",
                                 "verb": "eat", "object_noun": "apple",
                                 "person": 3, "number": "singular"},
        "He writed a letter.": {"pattern": "SVO", "tense": "past_simple",
                                 "verb": "write", "object_noun": "letter",
                                 "person": 3, "number": "singular"},
    },
    'svp_copula_adjective': {
        "The soup tastes well.": {"pattern": "SVP", "tense": "present_simple",
                                   "verb": "taste", "predicative": "well"},
    },
    'svp_ungradable_degree': {
        "The man is very dead.": {"pattern": "SVP", "tense": "present_simple",
                                   "is_be": True, "verb": "be",
                                   "predicative": "dead"},
        "The cat is more alive.": {"pattern": "SVP", "tense": "present_simple",
                                    "is_be": True, "verb": "be",
                                    "predicative": "alive"},
    },
    'there_be_definiteness': {
        "There is the cat in the garden.": {"pattern": "THERE_BE",
                                             "tense": "present_simple",
                                             "is_be": True,
                                             "object_noun": "cat"},
    },
    'np_article_phonetic': {
        "A hour is enough.": {"pattern": "NP", "tense": "present_simple",
                               "object_noun": "hour"},
        "She visits an university.": {"pattern": "SVO", "tense": "present_simple",
                                       "verb": "visit",
                                       "object_noun": "university",
                                       "person": 3, "number": "singular"},
    },
    'tense_perfect_participle': {
        "She has ate an apple.": {"pattern": "SVO", "tense": "present_perfect",
                                   "verb": "eat", "object_noun": "apple",
                                   "person": 3, "number": "singular"},
        "They have goed.": {"pattern": "SV", "tense": "present_perfect",
                             "verb": "go", "person": 3, "number": "plural"},
    },
    'be_form_all_pronouns': {
        "Am you happy.": {"pattern": "SVP", "tense": "present_simple",
                           "is_be": True, "verb": "be"},
    },
    'there_be_agreement': {
        "There are a book.": {"pattern": "THERE_BE", "tense": "present_simple",
                               "is_be": True, "object_noun": "book"},
        "There is two dogs.": {"pattern": "THERE_BE", "tense": "present_simple",
                                "is_be": True, "object_noun": "dog"},
    },
    # —— 以下为 Hy3 复查补强：把生成器已具备独立检查能力、但此前仅 SKIP 的禁止句
    #    接入 check_info，使其逐句交给 check_grammar() 真实执行（不再靠组数掩盖）。
    'sv_agreement_third_singular': {
        "The dog run.": {"pattern": "SV", "tense": "present_simple",
                         "polarity": "affirmative", "question": "none",
                         "person": 3, "number": "singular", "verb": "run"},
        "He gos.": {"pattern": "SV", "tense": "present_simple",
                    "polarity": "affirmative", "question": "none",
                    "person": 3, "number": "singular", "verb": "go"},
    },
    'svo_stative_continuous': {
        "She is liking music.": {"pattern": "SVO", "tense": "present_continuous",
                                 "polarity": "affirmative", "question": "none",
                                 "person": 3, "number": "singular", "verb": "like",
                                 "is_be": False},
    },
    'np_invariant_plural': {
        "Two sheeps eat grass.": {"pattern": "SV", "tense": "present_simple",
                                  "polarity": "affirmative", "question": "none",
                                  "is_be": False},
    },
    'np_plural_only_pair': {
        "She buys a scissors.": {"pattern": "SVO", "tense": "present_simple",
                                 "polarity": "affirmative", "question": "none",
                                 "is_be": False},
    },
    'adv_double_negative': {
        "She does not never eat meat.": {"pattern": "SVO", "tense": "present_simple",
                                        "polarity": "negative", "question": "none",
                                        "is_be": False, "verb": "eat",
                                        "person": 3, "number": "singular"},
    },
}

# There-be 连续时本来没有文档禁止句，补一条与拒绝码一一对应的声明。
for entry in data:
    if entry.get('test_id') == 'there_be_agreement':
        sentence = 'There is being a book on the desk.'
        if not any(x.get('sentence') == sentence for x in entry.get('forbidden', [])):
            entry.setdefault('forbidden', []).append({
                'sentence': sentence,
                'reason': 'forbid_there_be_continuous',
            })

for e in data:
    tid = e.get('test_id')
    if tid in EXEC:
        e['exec'] = EXEC[tid]
    if tid in EXEC_FORBIDDEN:
        e['exec_forbidden'] = EXEC_FORBIDDEN[tid]
    checks = CHECK_INFO.get(tid, {})
    for forbidden in e.get('forbidden', []):
        forbidden.pop('check_info', None)
        if forbidden.get('sentence') in checks:
            forbidden['check_info'] = checks[forbidden['sentence']]

# be 变位全回归组（永久防 "Am you"）
pron = [('I', 'am', 'was'), ('you', 'are', 'were'), ('he', 'is', 'was'),
        ('she', 'is', 'was'), ('it', 'is', 'was'), ('we', 'are', 'were'),
        ('they', 'are', 'were')]
execs = []
for subj, bpre, bpas in pron:
    s = subj.capitalize()
    execs.append({"expect": f"{s} {bpre} happy.", "pattern": "SVP",
                  "tense": "present_simple", "polarity": "affirmative",
                  "question": "none", "choice": {"verb": "be", "subject": subj, "predicative": "happy"}})
    execs.append({"expect": f"{s} {bpre} not hungry.", "pattern": "SVP",
                  "tense": "present_simple", "polarity": "negative",
                  "question": "none", "choice": {"verb": "be", "subject": subj, "predicative": "hungry"}})
    execs.append({"expect": f"{bpre.capitalize()} {subj} happy?", "pattern": "SVP",
                  "tense": "present_simple", "polarity": "affirmative",
                  "question": "yes_no", "choice": {"verb": "be", "subject": subj, "predicative": "happy"}})
    execs.append({"expect": f"{s} {bpas} happy.", "pattern": "SVP",
                  "tense": "past_simple", "polarity": "affirmative",
                  "question": "none", "choice": {"verb": "be", "subject": subj, "predicative": "happy"}})
    execs.append({"expect": f"{s} {bpre} eating an apple.", "pattern": "SVO",
                  "tense": "present_continuous", "polarity": "affirmative",
                  "question": "none", "choice": {"verb": "eat", "subject": subj, "object": "apple"}})
    execs.append({"expect": f"{s} {bpas} eating an apple.", "pattern": "SVO",
                  "tense": "past_continuous", "polarity": "affirmative",
                  "question": "none", "choice": {"verb": "eat", "subject": subj, "object": "apple"}})

upsert({
    "test_id": "be_form_all_pronouns",
    "rule": "be 变位必须按 (person, number) 精确匹配：I→am/was；you→are/were（单复同形）；he/she/it→is/was；we/they→are/were。覆盖全部 7 代词 × 现在/过去 × 陈述/否定/疑问，永久防 'Am you' 类回退。",
    "golden": ["I am happy.", "You are happy.", "He is happy.", "We are happy.", "They are happy.",
               "Are you happy?", "Is he happy?", "I was happy.", "You were happy."],
    "forbidden": [{"sentence": "Am you happy.", "reason": "be_agreement",
                    "check_info": CHECK_INFO['be_form_all_pronouns']["Am you happy."]}],
    "formula_id": "svp_copula",
    "exec": execs,
})

# 第二轮复查明确要求：eat+desk / read+deer / ask+market 的真实拒绝测试
# （其中 eat+desk 已并入 svo_object_restriction_edible 的 exec_forbidden，
#  这里补 read+deer 与 ask+market，三者各测一次，避免重复计数）
upsert({
    "test_id": "svo_object_restriction_demo",
    "rule": "SVO 宾语必须匹配动词语义限制：read→readable、ask→person/question。"
            "通过 choice 强行指定错搭（read+deer / ask+market）必须被 object_restriction_unmet 拒绝。",
    "golden": ["He reads a letter.", "She asks a teacher."],
    "forbidden": [
        {"sentence": "He reads a deer.", "reason": "object_restriction_unmet"},
        {"sentence": "She asks a market.", "reason": "object_restriction_unmet"},
    ],
    "formula_id": "svo_basic",
    "exec": [
        {"expect": "He reads a letter.", "pattern": "SVO", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "read", "subject": "he", "object": "letter"}},
        {"expect": "She asks a teacher.", "pattern": "SVO", "tense": "present_simple",
         "polarity": "affirmative", "question": "none",
         "choice": {"verb": "ask", "subject": "she", "object": "teacher"}},
    ],
    "exec_forbidden": [
        {"expect_reject": "object_restriction_unmet", "pattern": "SVO",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "forbidden_sentence": "He reads a deer.",
         "choice": {"verb": "read", "subject": "he", "object": "deer"}},
        {"expect_reject": "object_restriction_unmet", "pattern": "SVO",
         "tense": "present_simple", "polarity": "affirmative", "question": "none",
         "forbidden_sentence": "She asks a market.",
         "choice": {"verb": "ask", "subject": "she", "object": "market"}},
    ],
})

json.dump(data, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("golden.json 已重建：", len(data), "组；注入 exec 的组：",
      sum(1 for e in data if e.get('exec')), "；exec_forbidden 的组：",
      sum(1 for e in data if e.get('exec_forbidden')))
