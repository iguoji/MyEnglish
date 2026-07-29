# -*- coding: utf-8 -*-
"""
封闭类功能词"总表自检"工具 —— 让缺词"自主暴露"，不再依赖用户逐句查缺补漏。

为什么需要它（解决的核心痛点）：
  上一版 verify_coverage.py 的盲区是"循环论证"：
    它只证明"我手写过的模板里出现的功能词都覆盖了"，
    但"我没想到要写某类模板"这件事它本身发现不了。
  于是用户每次给一句中文（有人正在敲门… / 他们互相帮助…），
  才暴露一个粘合词维度（复合不定代词 / 相互代词 / let 祈使…）。

  破解办法：功能词是"封闭类"（finite / closed class）——
    英语里冠词、代词、介词、连词、助动词、情态动词……数量是有限且可枚举的。
    只要维护一份"英语功能词总表"，拿它和 words.json ∪ patch 做差集，
    差集里的词就是系统还缺的粘合词。这完全不依赖任何例句。

  两份工具分工：
    - verify_coverage.py ：证明"已铺的模板"全覆盖（穷举校验，防回归）。
    - check_master_vocab.py ：发现"还没铺的维度"（封闭类总表 diff，主动找缺口）。
      本工具只回答一个问题：英语该有的功能词，我们是不是全有了？

用法：
  python3 patch/check_master_vocab.py
退出码：0 = 封闭类总表已被全覆盖；1 = 仍有缺失（会逐条打印，按类别分组）。
"""

import json, glob, os, sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------- 1. 加载词库（用户词 + 全部 patch）----------
user_words = json.load(open(f'{BASE}/words.json'))
patch_words = []
for f in sorted(glob.glob(f'{BASE}/patch/*.json')):
    patch_words += json.load(open(f))

# 统一转小写做不区分大小写比对（功能词无所谓大小写，首字母大写只是句首）
LEX = {w['spelling'].lower() for w in user_words} | {w['spelling'].lower() for w in patch_words}

# 与 verify_coverage.py 保持一致：规则屈折（-s/-ing/-ed 等）由 app 确定性拼接产生，
# 属"已有词的合法变形"，不应算作缺失。这里复用同一套 _inflect 把基础词展开，
# 避免把 having（have 的 -ing）/ others（other 的 -s）等误报成缺口。
import re as _re
def _inflect(w):
    out = set()
    if _re.search(r"[^a-z']", w):
        return out
    if _re.search(r'(s|x|z|ch|sh|o)$', w):
        out.add(w + 'es')
    elif _re.search(r'[^aeiou]y$', w):
        out.add(w[:-1] + 'ies')
    else:
        out.add(w + 's')
    out.add(w[:-1] + 'ing' if w.endswith('e') and not w.endswith('ee') else w + 'ing')
    out.add(w + 'd' if w.endswith('e') else (w[:-1] + 'ied' if _re.search(r'[^aeiou]y$', w) else w + 'ed'))
    return out

for _w in list(LEX):
    LEX |= _inflect(_w)

# ---------- 2. 封闭类功能词"总表"（英语该有的，全列在此）----------
# 分类只是便于阅读缺失报告；每个词都是英语里货真价实的"封闭类"成员。
# 多词短语保留空格（与 patch 里 "each other" / "no one" 的拼写一致）。
MASTER = {
    # 冠词 / 限定词
    '限定词-冠词': ['a', 'an', 'the'],
    '限定词-指示': ['this', 'that', 'these', 'those'],
    '限定词-物主': ['my', 'your', 'his', 'her', 'its', 'our', 'their'],
    '限定词-量化': ['some', 'any', 'no', 'all', 'both', 'each', 'every',
                  'either', 'neither', 'another', 'other', 'such',
                  'few', 'little', 'many', 'much', 'several', 'enough'],

    # 人称代词（主格 + 宾格）
    '人称代词': ['i', 'me', 'you', 'he', 'him', 'she', 'her', 'it',
               'we', 'us', 'they', 'them'],
    # 名词性物主代词
    '物主代词': ['mine', 'yours', 'his', 'hers', 'ours', 'theirs'],
    # 反身代词
    '反身代词': ['myself', 'yourself', 'himself', 'herself', 'itself',
               'ourselves', 'yourselves', 'themselves'],
    # 相互代词（多词短语）
    '相互代词': ['each other', 'one another'],
    # 复合不定代词
    '复合不定代词': ['someone', 'somebody', 'something', 'anyone', 'anybody',
                   'anything', 'everyone', 'everybody', 'everything',
                   'no one', 'nobody', 'nothing', 'none', 'others'],
    # 疑问词 / 关系词（含 ever- 自由关系变体）
    '疑问-关系词': ['what', 'who', 'whom', 'whose', 'which',
                  'where', 'when', 'why', 'how',
                  'whatever', 'whoever', 'whichever', 'wherever',
                  'whenever', 'however'],

    # be 动词（含分词/进行时）
    'be动词': ['be', 'am', 'is', 'are', 'was', 'were', 'been', 'being'],
    # 基本助动词
    '基本助动词': ['do', 'does', 'did', 'have', 'has', 'had', 'having', 'done'],
    # 情态动词 / 半情态（含多词短语）
    '情态-半情态': ['will', 'would', 'shall', 'should', 'can', 'could',
                  'may', 'might', 'must', 'ought', 'need', 'dare',
                  'used to', 'ought to', 'be able to', 'have to',
                  'has to', 'had to', 'be going to', 'had better', 'would rather'],

    # 介词（英语介词全集——封闭且可枚举）
    '介词': ['about', 'above', 'across', 'after', 'against', 'along', 'amid',
           'among', 'around', 'at', 'before', 'behind', 'below', 'beneath',
           'beside', 'between', 'beyond', 'but', 'by', 'down', 'during',
           'except', 'for', 'from', 'in', 'inside', 'into', 'like', 'near',
           'of', 'off', 'on', 'onto', 'out', 'outside', 'over', 'past',
           'since', 'through', 'throughout', 'to', 'toward', 'towards', 'under',
           'underneath', 'until', 'up', 'upon', 'with', 'within', 'without',
           # —— 用户网搜清单补齐的单字介词 ——
           'despite', 'per', 'till', 'via', 'unlike', 'opposite',
           'regarding', 'concerning', 'plus', 'minus',
           # —— 复合介词（多词短语）——
           'because of', 'instead of', 'in front of', 'next to', 'according to',
           'in spite of', 'due to', 'out of', 'away from', 'ahead of',
           'regardless of', 'apart from', 'in addition to', 'up to',
           'prior to', 'except for'],

    # 连词（并列 + 从属）
    '连词': ['and', 'but', 'or', 'nor', 'for', 'yet', 'so',
           'because', 'since', 'as', 'although', 'though', 'if', 'unless',
           'while', 'whereas', 'after', 'before', 'until', 'once', 'than',
           'that', 'whether', 'lest',
           # —— 用户网搜清单补齐的单字连词 ——
           'otherwise', 'nevertheless', 'nonetheless', 'furthermore',
           'meanwhile', 'consequently', 'similarly', 'likewise',
           # —— 复合连词（多词短语）——
           'even though', 'as soon as', 'as well as', 'in order to', 'even if',
           'as long as', 'so that', 'in case', 'provided that', 'as if',
           'as though', 'now that'],

    # 基础副词 / 否定 / 连接副词（封闭倾向强的一组）
    '副词-否定-连接': ['not', 'never', 'always', 'often', 'sometimes',
                     'usually', 'seldom', 'rarely', 'here', 'there', 'now',
                     'then', 'today', 'tomorrow', 'yesterday', 'very', 'too',
                     'also', 'only', 'just', 'even', 'still', 'yet', 'already',
                     'again', 'soon', 'maybe', 'perhaps', 'quite', 'rather',
                     'however', 'therefore', 'thus', 'hence', 'moreover',
                     'besides', 'instead', 'anyway', 'else', 'away', 'back',
                     'together', 'alone', 'ahead'],

    # 比较级关联词
    '比较关联': ['as', 'than', 'less', 'more', 'fewer', 'most', 'fewest',
                'least', 'rather', 'quite', 'such', 'else'],

    # 应答/语气词（封闭小类）
    '应答词': ['yes', 'no', 'please', 'thanks', 'okay'],
}

# 有意识"暂不打分"的词（如某些半开放性副词，先观察不强制）：留空即可。
# 若以后确认不需要，可加进这里避免误报；需要则保持为空。
WHITELIST = set()

# ---------- 3. 做差集：总表里有、词库里没有的 = 缺口 ----------
missing_by_cat = {}
total_master = 0
covered = 0
for cat, words in MASTER.items():
    miss = [w for w in words if w.lower() not in LEX and w.lower() not in WHITELIST]
    if miss:
        missing_by_cat[cat] = miss
    total_master += len(words)
    covered += len(words) - len(miss)

# ---------- 4. 报告 ----------
print(f'词库规模: 用户 {len(user_words)} 词 + patch {len(patch_words)} 词 = 合计 {len(LEX)} 个拼写')
print(f'封闭类总表条目: {total_master} 个，已覆盖 {covered} 个，缺失 {total_master - covered} 个')
print(f'覆盖比例: {covered / total_master * 100:.1f}%')

if not missing_by_cat:
    print('\n[PASS] 英语封闭类功能词总表已被 words.json ∪ patch 全覆盖——无待补维度。')
    sys.exit(0)

print(f'\n[MISSING] 以下封闭类功能词在词库中缺失（按类别）：共 {sum(len(v) for v in missing_by_cat.values())} 个')
for cat, miss in missing_by_cat.items():
    print(f'\n  ▸ {cat}（缺 {len(miss)}）：')
    for w in miss:
        tag = '（多词短语）' if ' ' in w else ''
        print(f'      - {w}{tag}')
print('\n建议：把上述词按类别补进对应 patch/*.json（或确认已在用户词库），')
print('      然后重跑本工具与 verify_coverage.py 做双向确认。')
sys.exit(1)
