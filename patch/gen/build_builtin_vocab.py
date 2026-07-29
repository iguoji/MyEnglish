# -*- coding: utf-8 -*-
"""
内置基线词库生成器（类似小程序里的「数据初始化脚本」）

作用：
    把一份「英文单词 + 中文释义」的清单，按 README 定义的 word 模型，
    自动补全变形字段（过去式/分词/三单/现在分词/复数），
    生成可直接被 app 导入的 JSON 词库文件。

为什么需要它（类比 PHP 的 Eloquent 模型工厂）：
    数据库表有 20 个字段，但录入单词时我们只关心「拼写」和「意思」，
    其余变形字段（如 eat→ate→eaten）有固定规律，让程序「按规则推导」比人工逐个填更稳。
    本脚本 = 规则引擎 + 数据清单。

输出文件：
    patch/content_baseline_verbs.json   （动词地板，id 102001 起）
    patch/content_baseline_nouns.json   （名词地板，id 103001 起）

用法：
    python3 patch/gen/build_builtin_vocab.py
"""

import json
import os
import time
import glob

BASE = os.path.dirname(os.path.abspath(__file__))          # patch/gen/ 目录（本生成脚本与 data_*.py 数据源所在）
ROOT = os.path.dirname(BASE)                               # patch/ 目录（词库 JSON 与 annotations/ 所在，生成产物也写到这里）
NOW = int(time.time())                                    # 统一的「创建/更新时间」戳（unix 秒）

# ============================================================================
# 1. 不规则动词表（英语约 180 个高频不规则动词）
#    结构：{ 原形: [过去式, 过去分词] }
#    规则动词不在此表，由下方 infer_verb_forms() 按拼写规则推导。
#    注意：be/do/have 属功能词库（patch/ 已收），此处只放「实义不规则动词」。
# ============================================================================
IRREGULAR_VERBS = {
    # 三类变化（AAA / ABA / ABB / ABC）
    "cut": ["cut", "cut"], "put": ["put", "put"], "set": ["set", "set"],
    "let": ["let", "let"], "hit": ["hit", "hit"], "shut": ["shut", "shut"],
    "split": ["split", "split"], "spread": ["spread", "spread"],
    "cost": ["cost", "cost"], "hurt": ["hurt", "hurt"], "read": ["read", "read"],
    "burst": ["burst", "burst"], "cast": ["cast", "cast"], "thrust": ["thrust", "thrust"],
    "cut": ["cut", "cut"], "bid": ["bid", "bid"], "rid": ["rid", "rid"], "beat": ["beat", "beaten"], "withhold": ["withheld", "withheld"],
    "shed": ["shed", "shed"], "slit": ["slit", "slit"], "spit": ["spat", "spat"],
    "quit": ["quit", "quit"], "wet": ["wet", "wet"], "fit": ["fit", "fit"],

    # ABB 型（过去式=过去分词，与原形不同）
    "build": ["built", "built"], "lend": ["lent", "lent"], "send": ["sent", "sent"],
    "spend": ["spent", "spent"], "bend": ["bent", "bent"], "burn": ["burnt", "burnt"],
    "learn": ["learnt", "learnt"], "mean": ["meant", "meant"], "hear": ["heard", "heard"],
    "pay": ["paid", "paid"], "say": ["said", "said"], "see": ["saw", "seen"], "lay": ["laid", "laid"],
    "dig": ["dug", "dug"], "stick": ["stuck", "stuck"], "strike": ["struck", "struck"],
    "win": ["won", "won"], "spin": ["spun", "spun"], "swing": ["swung", "swung"],
    "hang": ["hung", "hung"], "shine": ["shone", "shone"], "hold": ["held", "held"],
    "tell": ["told", "told"], "sell": ["sold", "sold"], "find": ["found", "found"],
    "get": ["got", "got"], "sit": ["sat", "sat"], "shit": ["shit", "shit"],
    "light": ["lit", "lit"], "meet": ["met", "met"], "lead": ["led", "led"], "lie": ["lay", "lain"],
    "feed": ["fed", "fed"], "feel": ["felt", "felt"], "keep": ["kept", "kept"],
    "sleep": ["slept", "slept"], "sweep": ["swept", "swept"], "weep": ["wept", "wept"],
    "leave": ["left", "left"], "lose": ["lost", "lost"], "deal": ["dealt", "dealt"],
    "dream": ["dreamt", "dreamt"], "smell": ["smelt", "smelt"], "spell": ["spelt", "spelt"],
    "spill": ["spilt", "spilt"], "creep": ["crept", "crept"], "kneel": ["knelt", "knelt"],
    "bleed": ["bled", "bled"], "speed": ["sped", "sped"], "breed": ["bred", "bred"],
    "shoot": ["shot", "shot"], "stand": ["stood", "stood"], "understand": ["understood", "understood"],
    "bring": ["brought", "brought"], "think": ["thought", "thought"],
    "teach": ["taught", "taught"], "catch": ["caught", "caught"], "seek": ["sought", "sought"],
    "buy": ["bought", "bought"], "fight": ["fought", "fought"], "fly": ["flew", "flown"],
    "blow": ["blew", "blown"], "grow": ["grew", "grown"], "know": ["knew", "known"],
    "throw": ["threw", "thrown"], "draw": ["drew", "drawn"], "show": ["showed", "shown"],
    "drive": ["drove", "driven"], "ride": ["rode", "ridden"], "rise": ["rose", "risen"],
    "fall": ["fell", "fallen"], "take": ["took", "taken"], "mistake": ["mistook", "mistaken"],
    "break": ["broke", "broken"], "speak": ["spoke", "spoken"], "steal": ["stole", "stolen"],
    "wake": ["woke", "woken"], "choose": ["chose", "chosen"], "freeze": ["froze", "frozen"],
    "forget": ["forgot", "forgotten"], "hide": ["hid", "hidden"], "bite": ["bit", "bitten"],
    "write": ["wrote", "written"], "eat": ["ate", "eaten"], "give": ["gave", "given"],
    "forgive": ["forgave", "forgiven"], "shake": ["shook", "shaken"], "take": ["took", "taken"],
    "undertake": ["undertook", "undertaken"], "overtake": ["overtook", "overtaken"],
    "come": ["came", "come"], "become": ["became", "become"], "overcome": ["overcame", "overcome"],
    "run": ["ran", "run"], "swim": ["swam", "swum"], "drink": ["drank", "drunk"],
    "sink": ["sank", "sunk"], "ring": ["rang", "rung"], "sing": ["sang", "sung"],
    "begin": ["began", "begun"], "ring": ["rang", "rung"], "spring": ["sprang", "sprung"],
    "stink": ["stank", "stunk"], "shrink": ["shrank", "shrunk"], "slink": ["slunk", "slunk"],
    "weave": ["wove", "woven"], "cleave": ["clove", "cloven"], "heave": ["heaved", "heaved"],
    "tear": ["tore", "torn"], "wear": ["wore", "worn"], "swear": ["swore", "sworn"],
    "bear": ["bore", "borne"], "flee": ["fled", "fled"], "fling": ["flung", "flung"],
    "grind": ["ground", "ground"], "wind": ["wound", "wound"], "bind": ["bound", "bound"],
    "find": ["found", "found"], "behind": ["behind", "behind"], "remind": ["reminded", "reminded"],
    "slide": ["slid", "slid"], "stride": ["strode", "stridden"], "ride": ["rode", "ridden"],
    "chide": ["chid", "chidden"], "slide": ["slid", "slid"], "glide": ["glided", "glided"],
    "hide": ["hid", "hidden"], "provide": ["provided", "provided"], "divide": ["divided", "divided"],
    "decide": ["decided", "decided"], "ride": ["rode", "ridden"], "stride": ["strode", "stridden"],
    "arise": ["arose", "arisen"], "rise": ["rose", "risen"], "raise": ["raised", "raised"],
    "sew": ["sewed", "sewn"], "sow": ["sowed", "sown"], "mow": ["mowed", "mown"],
    "hew": ["hewed", "hewn"], "hew": ["hewed", "hewn"], "shew": ["shewed", "shewn"],
    "awake": ["awoke", "awoken"], "wake": ["woke", "woken"], "bake": ["baked", "baked"],
    "shake": ["shook", "shaken"], "stake": ["staked", "staked"], "snake": ["snaked", "snaked"],
    "sneak": ["sneaked", "sneaked"], "speak": ["spoke", "spoken"], "break": ["broke", "broken"],
    "steal": ["stole", "stolen"], "speak": ["spoke", "spoken"], "wake": ["woke", "woken"],
    "freeze": ["froze", "frozen"], "flee": ["fled", "fled"], "fling": ["flung", "flung"],
    "string": ["strung", "strung"], "swing": ["swung", "swung"], "cling": ["clung", "clung"],
    "wring": ["wrung", "wrung"], "sting": ["stung", "stung"], "bang": ["banged", "banged"],
    "hang": ["hung", "hung"], "sling": ["slung", "slung"], "wing": ["winged", "winged"],
    "slink": ["slunk", "slunk"], "shrink": ["shrank", "shrunk"], "drink": ["drank", "drunk"],
    "sink": ["sank", "sunk"], "think": ["thought", "thought"], "bring": ["brought", "brought"],
    "ring": ["rang", "rung"], "sing": ["sang", "sung"], "spring": ["sprang", "sprung"],
    "swim": ["swam", "swum"], "run": ["ran", "run"], "come": ["came", "come"],
    "become": ["became", "become"], "overcome": ["overcame", "overcome"], "welcome": ["welcomed", "welcomed"],
    "tread": ["trod", "trodden"], "dread": ["dreaded", "dreaded"], "bread": ["breaded", "breaded"],
    "spread": ["spread", "spread"], "thread": ["threaded", "threaded"], "read": ["read", "read"],
    "bleed": ["bled", "bled"], "breed": ["bred", "bred"], "creed": ["creed", "creed"],
    "speed": ["sped", "sped"], "succeed": ["succeeded", "succeeded"], "proceed": ["proceeded", "proceeded"],
    "exceed": ["exceeded", "exceeded"], "feed": ["fed", "fed"], "need": ["needed", "needed"],
    "seed": ["seeded", "seeded"], "weed": ["weeded", "weeded"], "greed": ["greedy", "greedy"],
    "indeed": ["indeed", "indeed"], "deed": ["deed", "deed"], "creed": ["creed", "creed"],
    "sweep": ["swept", "swept"], "keep": ["kept", "kept"], "sleep": ["slept", "slept"],
    "creep": ["crept", "crept"], "weep": ["wept", "wept"], "leap": ["leapt", "leapt"],
    "cheap": ["cheaper", "cheapest"], "heap": ["heaped", "heaped"], "reap": ["reaped", "reaped"],
    "deal": ["dealt", "dealt"], "meal": ["meals", "meals"], "seal": ["sealed", "sealed"],
    "steal": ["stole", "stolen"], "heal": ["healed", "healed"], "veal": ["veal", "veal"],
    "real": ["real", "real"], "teal": ["teal", "teal"], "zeal": ["zeal", "zeal"],
    "feel": ["felt", "felt"], "kneel": ["knelt", "knelt"], "peel": ["peeled", "peeled"],
    "reel": ["reeled", "reeled"], "steel": ["steel", "steel"], "wheel": ["wheeled", "wheeled"],
    "smell": ["smelt", "smelt"], "spell": ["spelt", "spelt"], "tell": ["told", "told"],
    "fell": ["felled", "felled"], "well": ["wells", "wells"], "dwell": ["dwelt", "dwelt"],
    "swell": ["swelled", "swollen"], "yell": ["yelled", "yelled"], "sell": ["sold", "sold"],
    "shell": ["shelled", "shelled"], "spell": ["spelt", "spelt"], "cell": ["cells", "cells"],
    "bell": ["belled", "belled"], "fell": ["felled", "felled"], "hell": ["hells", "hells"],
    "sell": ["sold", "sold"], "tell": ["told", "told"], "spell": ["spelt", "spelt"],
    "misspell": ["misspelt", "misspelt"], "foretell": ["foretold", "foretold"],

    # 多音节重读闭音节双写（CVC 结尾且重音在末音节）
    "occur": ["occurred", "occurred"], "prefer": ["preferred", "preferred"],
    "refer": ["referred", "referred"], "defer": ["deferred", "deferred"],
    "infer": ["inferred", "inferred"], "transfer": ["transferred", "transferred"],
    "commit": ["committed", "committed"], "permit": ["permitted", "permitted"],
    "omit": ["omitted", "omitted"], "emit": ["emitted", "emitted"],
    "remit": ["remitted", "remitted"], "submit": ["submitted", "submitted"],
    "admit": ["admitted", "admitted"], "equip": ["equipped", "equipped"],
    "kidnap": ["kidnapped", "kidnapped"], "worship": ["worshipped", "worshipped"],
    "handicap": ["handicapped", "handicapped"], "travel": ["travelled", "travelled"],
    "cancel": ["cancelled", "cancelled"], "label": ["labelled", "labelled"],
    "model": ["modelled", "modelled"], "quarrel": ["quarrelled", "quarrelled"],
    "signal": ["signalled", "signalled"], "control": ["controlled", "controlled"],
    "patrol": ["patrolled", "patrolled"], "counsel": ["counselled", "counselled"],
    "enrol": ["enrolled", "enrolled"], "fulfil": ["fulfilled", "fulfilled"],
    "regret": ["regretted", "regretted"], "forget": ["forgot", "forgotten"],
    "begin": ["began", "begun"], "shop": ["shopped", "shopped"], "stop": ["stopped", "stopped"],
    "drop": ["dropped", "dropped"], "nod": ["nodded", "nodded"], "rob": ["robbed", "robbed"],
    "rub": ["rubbed", "rubbed"], "snap": ["snapped", "snapped"], "wrap": ["wrapped", "wrapped"],
    "chat": ["chatted", "chatted"], "pat": ["patted", "patted"], "plan": ["planned", "planned"],
    "tan": ["tanned", "tanned"], "scan": ["scanned", "scanned"], "ban": ["banned", "banned"],
    "fan": ["fanned", "fanned"], "man": ["manned", "manned"], "pan": ["panned", "panned"],
    "ran": ["ran", "ran"], "tan": ["tanned", "tanned"], "wan": ["wanned", "wanned"],
    "dim": ["dimmed", "dimmed"], "trim": ["trimmed", "trimmed"], "grim": ["grimmed", "grimmed"],
    "skim": ["skimmed", "skimmed"], "slim": ["slimmed", "slimmed"], "swim": ["swam", "swum"],
    "hum": ["hummed", "hummed"], "sum": ["summed", "summed"], "rim": ["rimmed", "rimmed"],
    "vim": ["vims", "vims"], "pin": ["pinned", "pinned"], "win": ["won", "won"],
    "spin": ["spun", "spun"], "thin": ["thinned", "thinned"], "sin": ["sinned", "sinned"],
    "tin": ["tinned", "tinned"], "kin": ["kins", "kins"], "bin": ["binned", "binned"],
    "fin": ["finned", "finned"], "din": ["dinned", "dinned"], "grin": ["grinned", "grinned"],
    "shin": ["shinned", "shinned"], "skin": ["skinned", "skinned"], "spin": ["spun", "spun"],

    # 其他常见
    "go": ["went", "gone"], "do": ["did", "done"], "have": ["had", "had"],
    "be": ["was", "were"], "can": ["could", "could"], "will": ["would", "would"],
    "shall": ["should", "should"], "may": ["might", "might"], "make": ["made", "made"], "must": ["must", "must"],
    "seek": ["sought", "sought"], "flee": ["fled", "fled"], "fling": ["flung", "flung"],
    "slay": ["slew", "slain"], "slay": ["slew", "slain"], "sling": ["slung", "slung"],
    "sting": ["stung", "stung"], "swing": ["swung", "swung"], "wring": ["wrung", "wrung"],
    "cling": ["clung", "clung"], "fling": ["flung", "flung"], "string": ["strung", "strung"],
    "fling": ["flung", "flung"], "sling": ["slung", "slung"], "sting": ["stung", "stung"],
    "swing": ["swung", "swung"], "wring": ["wrung", "wrung"], "cling": ["clung", "clung"],
}

# 三单不规则（have→has, do→does, go→goes 已由规则+特例处理）
IRREGULAR_TPS = {
    "have": "has", "do": "does", "go": "goes",
}

# ============================================================================
# 2. 不规则名词复数表
#    结构：{ 原形: [复数形] }  多合法形用数组（如 octopus→["octopuses","octopi"]）
# ============================================================================
IRREGULAR_NOUNS = {
    "child": ["children"], "man": ["men"], "woman": ["women"],
    "person": ["people", "persons"], "ox": ["oxen"], "goose": ["geese"],
    "mouse": ["mice"], "tooth": ["teeth"], "foot": ["feet"], "louse": ["lice"],
    "datum": ["data"], "criterion": ["criteria"], "phenomenon": ["phenomena"],
    "analysis": ["analyses"], "basis": ["bases"], "crisis": ["crises"],
    "thesis": ["theses"], "appendix": ["appendices", "appendixes"],
    "index": ["indices", "indexes"], "matrix": ["matrices", "matrixes"],
    "vertex": ["vertices"], "cactus": ["cacti", "cactuses"], "focus": ["foci", "focuses"],
    "nucleus": ["nuclei"], "syllabus": ["syllabi", "syllabuses"], "oasis": ["oases"],
    "bureau": ["bureaus", "bureaux"], "memorandum": ["memoranda", "memorandums"],
    "curriculum": ["curricula", "curriculums"], "alumnus": ["alumni"],
    "stimulus": ["stimuli"], "medium": ["media"], "bacterium": ["bacteria"],
    "fungus": ["fungi", "funguses"], "larva": ["larvae"], "nebula": ["nebulae"],
    "vertebra": ["vertebrae"], "corpus": ["corpora"], "genus": ["genera"],
    "species": ["species"], "series": ["series"], "deer": ["deer"],
    "sheep": ["sheep"], "fish": ["fish", "fishes"], "salmon": ["salmon"],
    "Chinese": ["Chinese"], "Japanese": ["Japanese"], "Swiss": ["Swiss"],
    "aircraft": ["aircraft"], "offspring": ["offspring"], "hovercraft": ["hovercraft"],
    "policeman": ["policemen"], "policewoman": ["policewomen"], "salesman": ["salesmen"],
    "chairman": ["chairmen"], "spokesman": ["spokesmen"], "postman": ["postmen"],
    "fireman": ["firemen"], "fisherman": ["fishermen"], "businessman": ["businessmen"],
    "Englishman": ["Englishmen"], "Frenchman": ["Frenchmen"], "countryman": ["countrymen"],
    "merman": ["mermen"], "stepson": ["stepsons"], "grandson": ["grandsons"],
    "octopus": ["octopuses", "octopi"], "hippopotamus": ["hippopotamuses", "hippopotami"],
    "cactus": ["cacti", "cactuses"], "syllabus": ["syllabi"], "nucleus": ["nuclei"],
    "alumna": ["alumnae"], "alumnus": ["alumni"], "formula": ["formulas", "formulae"],
    "antenna": ["antennas", "antennae"], "millennium": ["millennia"],
    "criterion": ["criteria"], "phenomenon": ["phenomena"], "automaton": ["automata"],
    "cannon": ["cannons", "cannon"], "echo": ["echoes"], "hero": ["heroes"],
    "potato": ["potatoes"], "tomato": ["tomatoes"], "volcano": ["volcanoes", "volcanos"],
    "cargo": ["cargoes", "cargos"], "mango": ["mangoes", "mangos"], "bufalo": ["buffaloes"],
    "calf": ["calves"], "half": ["halves"], "knife": ["knives"], "leaf": ["leaves"],
    "life": ["lives"], "loaf": ["loaves"], "self": ["selves"], "sheaf": ["sheaves"],
    "shelf": ["shelves"], "thief": ["thieves"], "wife": ["wives"], "wolf": ["wolves"],
    "elf": ["elves"], "dwarf": ["dwarves", "dwarfs"], "scarf": ["scarves", "scarfs"],
    "wharf": ["wharves", "wharfs"], "hoof": ["hooves", "hoofs"], "beef": ["beeves", "beefs"],
    # 不可数名词（无复数，复数形=自身）
    "news": ["news"], "music": ["music"], "bread": ["bread"], "information": ["information"],
    "advice": ["advice"], "furniture": ["furniture"], "luggage": ["luggage"],
    "baggage": ["baggage"], "equipment": ["equipment"], "homework": ["homework"],
    "knowledge": ["knowledge"], "weather": ["weather"], "money": ["money"],
    "health": ["health"], "wealth": ["wealth"], "math": ["math"], "physics": ["physics"],
    "politics": ["politics"], "cash": ["cash"], "hair": ["hair"], "traffic": ["traffic"],
    "fun": ["fun"], "luck": ["luck"], "progress": ["progress"], "research": ["research"],
    "evidence": ["evidence"], "rice": ["rice"], "sugar": ["sugar"], "butter": ["butter"],
}

# 复数拼写例外（以 o 结尾但 +s，不 +es）
O_PLUS_S = {"photo", "piano", "radio", "video", "zoo", "kilo", "logo", " solo", "tobacco", "memo", "auto"}
# 以 f/fe 结尾但 +s（不 +ves）的例外
F_PLUS_S = {"chef", "chief", "belief", "roof", "proof", "gulf", "cliff", "dwarf"}


# ============================================================================
# 3. 推导函数（类比 PHP 里的 helper 工具函数）
# ============================================================================

def _is_vowel(ch):
    """判断一个字母是不是元音（a/e/i/o/u）"""
    return ch in "aeiou"


def infer_verb_forms(spelling):
    """
    推导一个动词的「三单 / 现在分词 / 过去式 / 过去分词」。
    返回 dict，每个值都是 list（与 README 的 string[] 一致，可容纳多合法形）。

    优先级：不规则表（IRREGULAR_VERBS / IRREGULAR_TPS）> 拼写规则。
    """
    sp = spelling.lower()

    # --- 三单 (third person singular) ---
    if sp in IRREGULAR_TPS:
        tps = [IRREGULAR_TPS[sp]]
    elif sp.endswith(("s", "x", "z", "ch", "sh")):
        tps = [sp + "es"]
    elif sp.endswith("o") and sp not in O_PLUS_S:
        tps = [sp + "es"]
    elif len(sp) >= 2 and sp[-1] == "y" and not _is_vowel(sp[-2]):
        tps = [sp[:-1] + "ies"]          # study → studies
    else:
        tps = [sp + "s"]                  # run → runs

    # --- 现在分词 (gerund / present participle) ---
    if len(sp) == 3 and not _is_vowel(sp[0]) and sp[1] in "aeiou" and not _is_vowel(sp[2]) and sp[2] not in "wx":
        # 真 CVC 结构（首辅音+中元音+尾辅音，如 run/sit/stop）→ 双写尾辅音
        # 注意：eat(e-a-t) 首字母是元音，不双写 → eating；故加 not _is_vowel(sp[0]) 排除
        gerund = [sp + sp[-1] + "ing"]
    elif sp.endswith("ie"):
        gerund = [sp[:-2] + "ying"]      # lie → lying, die → dying
    elif sp.endswith("e") and not sp.endswith("ee"):
        gerund = [sp[:-1] + "ing"]       # make → making, take → taking
    else:
        gerund = [sp + "ing"]            # eat → eating, go → going

    # --- 过去式 / 过去分词 ---
    if sp in IRREGULAR_VERBS:
        past, pp = IRREGULAR_VERBS[sp]
        past_tense = [past]
        past_participle = [pp]
    else:
        # 规则动词：过去式与过去分词同形，按拼写规则加 -ed
        if sp.endswith(("s", "x", "z", "ch", "sh")):
            ed = sp + "ed"
        elif len(sp) == 3 and sp[1] in "aeiou" and not _is_vowel(sp[2]) and sp[2] not in "wx":
            ed = sp + sp[-1] + "ed"      # stop → stopped, plan → planned
        elif sp.endswith("y") and not _is_vowel(sp[-2]):
            ed = sp[:-1] + "ied"         # study → studied, try → tried
        elif sp.endswith("e"):
            ed = sp + "d"                # love → loved, make → made? (e+oed)
        else:
            ed = sp + "ed"               # walk → walked
        past_tense = [ed]
        past_participle = [ed]

    return {
        "third_person_singular": tps,
        "gerund": gerund,
        "past_tense": past_tense,
        "past_participle": past_participle,
    }


def infer_noun_plural(spelling):
    """
    推导名词复数。返回 list（多合法形）。
    优先级：不规则表 > 拼写规则。
    """
    sp = spelling.lower()
    if sp in IRREGULAR_NOUNS:
        return IRREGULAR_NOUNS[sp]

    # 以 s/x/z/ch/sh 结尾 +es
    if sp.endswith(("s", "x", "z", "ch", "sh")):
        return [sp + "es"]
    # 以 o 结尾
    if sp.endswith("o"):
        if sp in O_PLUS_S or sp[-2] in "aeiou":
            return [sp + "s"]
        return [sp + "es"]               # potato → potatoes, hero → heroes
    # 以辅音 + y 结尾 → ies
    if sp.endswith("y") and len(sp) >= 2 and not _is_vowel(sp[-2]):
        return [sp[:-1] + "ies"]         # baby → babies
    # 以 f/fe 结尾
    if sp.endswith("f"):
        if sp[:-1] in F_PLUS_S or sp in F_PLUS_S:
            return [sp + "s"]
        return [sp[:-1] + "ves"]         # leaf → leaves, wolf → wolves
    if sp.endswith("fe"):
        if sp[:-2] in F_PLUS_S or sp in F_PLUS_S:
            return [sp + "s"]
        return [sp[:-2] + "ves"]         # knife → knives, life → lives
    # 以 us 结尾 → i（拉丁语源）
    if sp.endswith("us"):
        return [sp[:-2] + "i"]           # focus → foci（也允许 focus → focuses，但取主形）
    # 以 is 结尾 → es
    if sp.endswith("is"):
        return [sp[:-2] + "es"]          # analysis → analyses（不规则表已覆盖多数）
    # 默认 +s
    return [sp + "s"]


# ============================================================================
# 4. 加载自动标注词表（patch/annotations/ 下的拼写数组，单一事实源）
# ============================================================================

def load_annotation(filename):
    """读取 patch/annotations/ 下的标注词表，返回小写拼写集合"""
    path = os.path.join(ROOT, "annotations", filename)
    if not os.path.exists(path):
        return set()
    return {w.lower() for w in json.load(open(path, encoding="utf-8"))}


IS_PERSON = load_annotation("is_person.json")        # meaning 层 is_person=true
PLURAL_ONLY = load_annotation("plural_only.json")    # word 层 plural_only=true
UNGRADABLE = load_annotation("ungradable.json")      # word 层 gradable=false
STATIVE = load_annotation("stative.json")            # meaning 层 stative=true


# ============================================================================
# 5. 构建 word 对象（严格按 README 的 word 模型字段）
# ============================================================================

def make_verb_word(wid, spelling, pos, zh):
    """构建动词 word 对象"""
    forms = infer_verb_forms(spelling)
    return {
        "id": wid,
        "spelling": spelling,
        "meanings": [
            {
                "index": 1,
                "pos": pos,                       # vt. / vi. / vi. vt.
                "definitions": [zh],
                "stative": spelling.lower() in STATIVE,   # 静态动词标记（绑定词性）
            }
        ],
        "difficulty": 0,                          # number，系统基线无难度梯度
        "phonetic_uk": None,                      # 音标可空
        "phonetic_us": None,
        "plural": [],                             # 动词无复数
        "plural_only": False,
        "third_person_singular": forms["third_person_singular"],
        "gerund": forms["gerund"],
        "past_tense": forms["past_tense"],
        "past_participle": forms["past_participle"],
        "comparative": [],
        "superlative": [],
        "gradable": True,                         # 动词 gradable 无意义，给默认 true
        "reviewed_at": None,
        "created_at": NOW,                        # number 时间戳
        "updated_at": NOW,
        "deleted_at": None,
    }


def make_noun_word(wid, spelling, zh):
    """构建名词 word 对象"""
    sp = spelling.lower()
    return {
        "id": wid,
        "spelling": spelling,
        "meanings": [
            {
                "index": 1,
                "pos": "n.",
                "definitions": [zh],
                "is_person": sp in IS_PERSON,     # 是否为人（绑定词性）
            }
        ],
        "difficulty": 0,
        "phonetic_uk": None,
        "phonetic_us": None,
        "plural": infer_noun_plural(spelling),    # 由规则推导
        "plural_only": sp in PLURAL_ONLY,         # 只有复数（scissors 等）
        "third_person_singular": [],
        "gerund": [],
        "past_tense": [],
        "past_participle": [],
        "comparative": [],
        "superlative": [],
        "gradable": True,                         # 名词 gradable 无意义，给默认 true
        "reviewed_at": None,
        "created_at": NOW,
        "updated_at": NOW,
        "deleted_at": None,
    }


# ============================================================================
# 6. 主流程：导入数据模块 → 构建 → 写文件
# ============================================================================

def main():
    # 导入数据清单（每个文件是一个 [(拼写, 及物性, 中文)] 或 [(拼写, 中文)] 的列表）
    VERBS = []
    NOUNS = []

    # 动态导入 patch/data_*.py 下的所有动词/名词数据模块
    for f in sorted(glob.glob(os.path.join(BASE, "data_verbs_*.py"))):
        mod = __import__("data_verbs_" + os.path.basename(f)[11:-3], fromlist=["VERBS"])
        VERBS += mod.VERBS
    for f in sorted(glob.glob(os.path.join(BASE, "data_nouns_*.py"))):
        mod = __import__("data_nouns_" + os.path.basename(f)[11:-3], fromlist=["NOUNS"])
        NOUNS += mod.NOUNS

    print(f"[数据] 动词 {len(VERBS)} 条，名词 {len(NOUNS)} 条")

    # 构建动词（id 102001 起，避开功能词 100001-101704 与既有动词 102001-102200 段计划续接）
    verbs_out = []
    vid = 102001
    seen_v = set()
    for (sp, pos, zh) in VERBS:
        if sp.lower() in seen_v:
            continue                    # 去重
        seen_v.add(sp.lower())
        verbs_out.append(make_verb_word(vid, sp, pos, zh))
        vid += 1

    # 构建名词（id 103001 起）
    nouns_out = []
    nid = 103001
    seen_n = set()
    for (sp, zh) in NOUNS:
        if sp.lower() in seen_n:
            continue
        seen_n.add(sp.lower())
        nouns_out.append(make_noun_word(nid, sp, zh))
        nid += 1

    # 写出
    with open(os.path.join(ROOT, "content_baseline_verbs.json"), "w", encoding="utf-8") as fp:
        json.dump(verbs_out, fp, ensure_ascii=False, indent=2)
    with open(os.path.join(ROOT, "content_baseline_nouns.json"), "w", encoding="utf-8") as fp:
        json.dump(nouns_out, fp, ensure_ascii=False, indent=2)

    print(f"[生成] content_baseline_verbs.json  {len(verbs_out)} 条 (id {verbs_out[0]['id']}~{verbs_out[-1]['id']})")
    print(f"[生成] content_baseline_nouns.json  {len(nouns_out)} 条 (id {nouns_out[0]['id']}~{nouns_out[-1]['id']})")


if __name__ == "__main__":
    main()
