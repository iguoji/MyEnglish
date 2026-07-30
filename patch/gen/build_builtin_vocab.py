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
    "get": ["got", ["got", "gotten"]], "sit": ["sat", "sat"], "shit": ["shit", "shit"],
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
    "throw": ["threw", "thrown"], "draw": ["drew", "drawn"], "show": ["showed", ["shown", "showed"]],
    "drive": ["drove", "driven"], "ride": ["rode", "ridden"], "rise": ["rose", "risen"],
    "fall": ["fell", "fallen"], "take": ["took", "taken"], "mistake": ["mistook", "mistaken"],
    "break": ["broke", "broken"], "speak": ["spoke", "spoken"], "steal": ["stole", "stolen"],
    "wake": [["woke", "waked"], ["woken", "waked"]], "choose": ["chose", "chosen"], "freeze": ["froze", "frozen"],
    "forget": ["forgot", ["forgotten", "forgot"]], "hide": ["hid", "hidden"], "bite": ["bit", ["bitten", "bit"]],
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
    "hide": ["hid", ["hidden", "hid"]], "provide": ["provided", "provided"], "divide": ["divided", "divided"],
    "decide": ["decided", "decided"], "ride": ["rode", "ridden"], "stride": ["strode", "stridden"],
    "arise": ["arose", "arisen"], "rise": ["rose", "risen"], "raise": ["raised", "raised"],
    "sew": ["sewed", "sewn"], "sow": ["sowed", "sown"], "mow": ["mowed", "mown"],
    "hew": ["hewed", "hewn"], "hew": ["hewed", "hewn"], "shew": ["shewed", "shewn"],
    "awake": ["awoke", "awoken"], "wake": [["woke", "waked"], ["woken", "waked"]], "bake": ["baked", "baked"],
    "shake": ["shook", "shaken"], "stake": ["staked", "staked"], "snake": ["snaked", "snaked"],
    "sneak": ["sneaked", "sneaked"], "speak": ["spoke", "spoken"], "break": ["broke", "broken"],
    "steal": ["stole", "stolen"], "speak": ["spoke", "spoken"], "wake": [["woke", "waked"], ["woken", "waked"]],
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
    "regret": ["regretted", "regretted"], "forget": ["forgot", ["forgotten", "forgot"]],
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

    # ------------------------------------------------------------------
    # 2026-07-30 任务11 审计修正块（后写覆盖先写：Python 字典字面量同键后者生效）
    # 判定全部由人工完成，依据主流词典通行形；多合法形"常用形在前"
    # ------------------------------------------------------------------
    "forbid": ["forbade", "forbidden"],          # 原被机械化成 forbided
    "withdraw": ["withdrew", "withdrawn"],       # 原被机械化成 withdrawed
    "undo": ["undid", "undone"],                 # 原被机械化成 undoed
    "upset": ["upset", "upset"],                 # 原被机械化成 upseted
    "bet": [["bet", "betted"], ["bet", "betted"]],   # bet 为主形，betted 少见但合法
    "fit": [["fit", "fitted"], ["fit", "fitted"]],   # 美式 fit / 英式 fitted 均合法
    "light": [["lit", "lighted"], ["lit", "lighted"]],   # README 示例明确要求双形
    "learn": [["learned", "learnt"], ["learned", "learnt"]],  # README 示例明确要求双形
    "burn": [["burned", "burnt"], ["burned", "burnt"]],
    "smell": [["smelled", "smelt"], ["smelled", "smelt"]],
    "spell": [["spelled", "spelt"], ["spelled", "spelt"]],
    "spill": [["spilled", "spilt"], ["spilled", "spilt"]],
    "leap": [["leapt", "leaped"], ["leapt", "leaped"]],
    "kneel": [["knelt", "kneeled"], ["knelt", "kneeled"]],
    "lean": [["leaned", "leant"], ["leaned", "leant"]],
    "dive": [["dived", "dove"], ["dived"]],      # dove 仅过去式（美式），过去分词只有 dived
    "spit": [["spat", "spit"], ["spat", "spit"]],
    "shine": [["shone", "shined"], ["shone", "shined"]],  # shined 用于"擦亮"义
    "saw": ["sawed", ["sawed", "sawn"]],
    "sew": ["sewed", ["sewn", "sewed"]],
    "mow": ["mowed", ["mown", "mowed"]],
    "sow": ["sowed", ["sown", "sowed"]],
    "well": ["welled", "welled"],                # 动词义"涌出"；原条目 wells 是名词复数，错误
}

# 三单不规则（have→has, do→does, go→goes 已由规则+特例处理）
IRREGULAR_TPS = {
    "have": "has", "do": "does", "go": "goes",
}

# 现在分词/过去式需双写尾辅音的「重音在末音节」动词（规则无法自动判定重音，用特例表）
# 例：prefer→preferring/preferred, occur→occurring/occurred, begin→beginning/began(不规则)
GERUND_DOUBLE = {
    "prefer", "refer", "occur", "admit", "omit", "begin", "forget", "regret",
    "permit", "commit", "control", "travel", "cancel", "model", "label",
    "quarrel", "equip", "kidnap", "defer", "deter", "transfer", "patrol",
    "compel", "expel", "repel", "counsel", "parallel",
    # 2026-07-30 任务11 审计修正：
    #   移除 profit/target（重音在首音节：profiting/profited、targeting/targeted）
    #   补充末音节重读多音节动词：submit/transmit/upset/forbid
    #   worship/signal 取英式双写（与不规则表 worshipped/signalled 保持一致）
    #   program 取双写主形 programming/programmed
    #   strap/strip/split 为单音节 CVC，但长度 >4 被机械规则漏掉，显式补入
    "submit", "transmit", "upset", "forbid", "worship", "signal", "program",
    "strap", "strip", "split",
}

# ============================================================================
# 2. 不规则名词复数表
#    结构：{ 原形: [复数形] }  多合法形用数组（如 octopus→["octopuses","octopi"]）
# ============================================================================
IRREGULAR_NOUNS = {
    "bus": ["buses", "busses"], "child": ["children"], "man": ["men"], "woman": ["women"],
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
    "wharf": ["wharves", "wharfs"], "hoof": ["hooves", "hoofs"],
    # 2026-07-30 任务10 审计修正：
    #   buffalo 原条目拼写错误(bufalo)导致规则未命中；单复同形亦合法一并补上
    #   reef 若走 f→ves 规则会生成错误的 reeves（那是 reeve 的复数），显式钉死
    #   zero 机械规则给 zeroes，实际 zeros 更常用，两者均合法
    "buffalo": ["buffaloes", "buffalo"], "reef": ["reefs"], "zero": ["zeros", "zeroes"],
}

# ----------------------------------------------------------------------------
# 不可数名词总表（2026-07-30 任务10 逐词人工审计产出）
# README 约定：plural 为非空数组 ⇒ 可数。因此不可数名词的 plural 必须是空数组 []，
# 绝不能填自身（否则被推导成"单复同形可数词"，生成 *two rice* 这类病句）。
# 歧义词按基线释义的义项判定：tin罐头/marble弹珠/nickel五分币/straw吸管/lace鞋带/
# cold感冒/litter一窝/wood森林/glass杯子/matter事情 等含可数义的词【不在】本表。
# ----------------------------------------------------------------------------
UNCOUNTABLE_NOUNS = {
    # 食物饮品
    "water", "rain", "snow", "ice", "rice", "bread", "meat", "milk", "tea", "coffee",
    "sugar", "salt", "oil", "butter", "cheese", "soup", "pepper", "wheat", "flour",
    "honey", "corn", "cream", "pork", "beef", "bacon", "wine", "beer", "garlic", "toast",
    # 材料物质
    "sand", "grass", "gold", "silver", "steel", "steam", "silk", "wool", "cotton",
    "coal", "cement", "chalk", "leather", "paper", "plastic", "cloth", "fur", "flesh",
    "mud", "dust", "dirt", "moss", "smoke", "soap", "soil", "yarn", "carbon", "zinc",
    "wood_material_only_DO_NOT_ADD",  # 占位提醒：wood 含"森林 woods"可数义，不入表
    # 自然现象/抽象
    "fog", "frost", "mist", "gravity", "scenery", "weather", "earth", "land", "ground",
    "space", "time", "energy", "power", "hair", "skin", "blood", "health", "news",
    "east", "west", "south", "north", "midnight",
    # 学科/概念
    "money", "music", "knowledge", "advice", "luggage", "baggage", "furniture", "math",
    "grammar", "art", "history", "information", "equipment", "homework", "wealth",
    "physics", "politics", "cash", "traffic", "fun", "luck", "progress", "research",
    "evidence", "advertising", "agriculture", "aid", "alcohol", "anger", "appreciation",
    "approval", "architecture", "assistance", "beauty", "behavior", "biology",
    "bravery", "breadth", "praise", "powder", "wash", "affection", "access", "abuse",
    "amusement", "golf",
}
UNCOUNTABLE_NOUNS.discard("wood_material_only_DO_NOT_ADD")  # 移除占位提醒项

# 只有复数形（拼写本身即复数）与集体名词：plural 同样置空，
# 具体行为（谓语用复数等）由 patch/sentence/annotations/number_behavior.json 驱动
PLURAL_ONLY_OR_COLLECTIVE_NOUNS = {"scissors", "clothes", "pants", "stairs", "cattle"}

# 复数拼写例外（以 o 结尾但 +s，不 +es）；修正：原表 " solo" 带前导空格永远匹配不上
O_PLUS_S = {"photo", "piano", "radio", "video", "zoo", "kilo", "logo", "solo", "tobacco", "memo", "auto", "kangaroo", "bamboo"}
# 以 f/fe 结尾但 +s（不 +ves）的例外
F_PLUS_S = {"chef", "chief", "belief", "roof", "proof", "gulf", "cliff", "dwarf", "reef", "beef", "safe", "giraffe", "cafe"}


# ============================================================================
# 3. 推导函数（类比 PHP 里的 helper 工具函数）
# ============================================================================

def _is_vowel(ch):
    """判断一个字母是不是元音（a/e/i/o/u）"""
    return ch in "aeiou"


def _count_vowels(sp):
    """统计拼写中的元音字母个数（粗略判断音节数，用于单音节 CVC 双写判定）"""
    return sum(1 for ch in sp if ch in "aeiou")


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
    if sp in GERUND_DOUBLE:
        # 多音节且重音在末音节（prefer→preferring, occur→occurring）
        gerund = [sp + sp[-1] + "ing"]
    elif (len(sp) <= 4 and sp[0] not in "aeiou" and _count_vowels(sp) == 1
          and _is_vowel(sp[-2]) and not _is_vowel(sp[-1]) and sp[-1] not in "wyx"):
        # 单音节 CVC 结构（stop/swim/run/plan/sit）→ 双写尾辅音
        # 须满足：尾三字母辅-元-辅（sp[-3] 为辅，排除 read=e-a-d 的 VVC）、且整词仅 1 个元音（排除 keep/meet 等多音节）
        gerund = [sp + sp[-1] + "ing"]
    elif sp.endswith("ie"):
        gerund = [sp[:-2] + "ying"]      # lie → lying, die → dying
    elif sp.endswith("e") and not sp.endswith("ee"):
        gerund = [sp[:-1] + "ing"]       # make → making, take → taking
    else:
        gerund = [sp + "ing"]            # eat → eating, go → going, buy → buying

    # --- 过去式 / 过去分词 ---
    if sp in IRREGULAR_VERBS:
        past, pp = IRREGULAR_VERBS[sp]
        # past/pp 既可为字符串（单形），也可为列表（多合法形，如 get→got/gotten）
        past_tense = past if isinstance(past, list) else [past]
        past_participle = pp if isinstance(pp, list) else [pp]
    else:
        # 规则动词：过去式与过去分词同形，按拼写规则加 -ed
        if sp in GERUND_DOUBLE:
            ed = sp + sp[-1] + "ed"      # prefer → preferred, occur → occurred
        elif sp.endswith(("s", "x", "z", "ch", "sh")):
            ed = sp + "ed"               # watch → watched, mix → mixed
        elif (len(sp) <= 4 and sp[0] not in "aeiou" and _count_vowels(sp) == 1
              and _is_vowel(sp[-2]) and not _is_vowel(sp[-1]) and sp[-1] not in "wyx"):
            ed = sp + sp[-1] + "ed"      # stop → stopped, plan → planned
        elif sp.endswith("y") and not _is_vowel(sp[-2]):
            ed = sp[:-1] + "ied"         # study → studied, try → tried
        elif sp.endswith("e"):
            ed = sp + "d"                # love → loved, bake → baked
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
    优先级：不可数/只有复数形（返回空表） > 不规则表 > 拼写规则。
    README 约定：plural 非空 ⇒ 可数；因此不可数词必须返回 []。
    """
    sp = spelling.lower()
    # 不可数名词与"拼写本身即复数/集体名词"：没有可生成的复数形
    if sp in UNCOUNTABLE_NOUNS or sp in PLURAL_ONLY_OR_COLLECTIVE_NOUNS:
        return []
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
# 4. annotations 说明（重要：定位已变更，2026-07-30 起生效）
#    patch/annotations/ 下的四个词表（plural_only / ungradable / stative / is_person）
#    是「句子生成器的外部语法知识」，只供造句知识库（patch/sentence/）和独立校验工具使用。
#    它们【不再】写回 Word / Meaning —— README 数据模型中已删除这四个字段，
#    Word、Meaning、SQLite、用户备份、导入格式一律不含它们。
#    本生成器保留读取能力（load_annotation），但构建 word 对象时绝不使用。
# ============================================================================

def load_annotation(filename):
    """读取 patch/annotations/ 下的标注词表，返回小写拼写集合。
    仅供外部工具复用（如造句知识库构建脚本 import 本模块调用），
    本脚本自身不再用它生成任何 Word/Meaning 字段。"""
    path = os.path.join(ROOT, "annotations", filename)
    if not os.path.exists(path):
        return set()
    return {w.lower() for w in json.load(open(path, encoding="utf-8"))}


# ============================================================================
# 5. 构建 word 对象（严格按 README 的 word 模型字段）
# ============================================================================

# ----------------------------------------------------------------------------
# 及物性归一化总表（2026-07-30 任务12 逐词人工判定产出，共 271 词）
# 数据源 data_verbs_*.py 中部分动词只标了模糊的 "v."，无法驱动生成器选句型
# （vt. 才能进 SVO，vi. 只能进 SV）。本表按【基线中文释义对应义项】的日常用法判定：
#   vt.      —— 该义项基本总带宾语（remember/believe/celebrate…）
#   vi.      —— 该义项基本不带宾语（travel/rest/complain/retire…）
#   vi. vt.  —— 两种用法都常见（start/play/break/move…），生成器可自由选句型
# 判定为人工完成；脚本仅查表应用。不在表中的 "v." 一律保持原样并计入 unknown。
# ----------------------------------------------------------------------------
POS_OVERRIDE = {
    # ---- 两栖（vi. vt.）：及物/不及物都常见 ----
    "start": "vi. vt.", "leave": "vi. vt.", "play": "vi. vt.", "study": "vi. vt.",
    "learn": "vi. vt.", "break": "vi. vt.", "drive": "vi. vt.", "lead": "vi. vt.",
    "sing": "vi. vt.", "think": "vi. vt.", "count": "vi. vt.", "cross": "vi. vt.",
    "develop": "vi. vt.", "fight": "vi. vt.", "gather": "vi. vt.", "guess": "vi. vt.",
    "hunt": "vi. vt.", "join": "vi. vt.", "lean": "vi. vt.", "measure": "vi. vt.",
    "move": "vi. vt.", "paint": "vi. vt.", "pass": "vi. vt.", "plan": "vi. vt.",
    "point": "vi. vt.", "pray": "vi. vt.", "prepare": "vi. vt.", "reflect": "vi. vt.",
    "relate": "vi. vt.", "reply": "vi. vt.", "report": "vi. vt.", "return": "vi. vt.",
    "ride": "vi. vt.", "ring": "vi. vt.", "roll": "vi. vt.", "rule": "vi. vt.",
    "search": "vi. vt.", "separate": "vi. vt.", "shake": "vi. vt.", "shave": "vi. vt.",
    "shoot": "vi. vt.", "sign": "vi. vt.", "smell": "vi. vt.", "spill": "vi. vt.",
    "spin": "vi. vt.", "split": "vi. vt.", "spread": "vi. vt.", "stick": "vi. vt.",
    "stop": "vi. vt.", "stretch": "vi. vt.", "strike": "vi. vt.", "submit": "vi. vt.",
    "taste": "vi. vt.", "train": "vi. vt.", "unite": "vi. vt.", "vary": "vi. vt.",
    "wake": "vi. vt.", "wave": "vi. vt.", "weigh": "vi. vt.", "withdraw": "vi. vt.",
    "wonder": "vi. vt.", "worry": "vi. vt.", "yield": "vi. vt.", "boil": "vi. vt.",
    "burn": "vi. vt.", "climb": "vi. vt.", "cry": "vi. vt.", "drop": "vi. vt.",
    "grow": "vi. vt.", "hide": "vi. vt.", "melt": "vi. vt.", "pack": "vi. vt.",
    "row": "vi. vt.", "sew": "vi. vt.", "shout": "vi. vt.", "skip": "vi. vt.",
    "snap": "vi. vt.", "soak": "vi. vt.", "spit": "vi. vt.", "stamp": "vi. vt.",
    "sway": "vi. vt.", "sweep": "vi. vt.", "swing": "vi. vt.", "weave": "vi. vt.",
    "whistle": "vi. vt.", "agree": "vi. vt.", "attack": "vi. vt.", "beg": "vi. vt.",
    "begin": "vi. vt.", "believe": "vi. vt.", "bend": "vi. vt.", "blow": "vi. vt.",
    "bounce": "vi. vt.", "bowl": "vi. vt.", "brake": "vi. vt.", "breathe": "vi. vt.",
    "bump": "vi. vt.", "care": "vi. vt.", "cease": "vi. vt.", "charge": "vi. vt.",
    "cheat": "vi. vt.", "check": "vi. vt.", "cheer": "vi. vt.", "circle": "vi. vt.",
    "clear": "vi. vt.", "command": "vi. vt.", "comment": "vi. vt.", "confess": "vi. vt.",
    "continue": "vi. vt.", "cool": "vi. vt.", "crack": "vi. vt.", "crash": "vi. vt.",
    "curl": "vi. vt.", "curve": "vi. vt.", "cycle": "vi. vt.", "dare": "vi. vt.",
    "debate": "vi. vt.", "decide": "vi. vt.", "decrease": "vi. vt.", "delay": "vi. vt.",
    "demand": "vt.", "dictate": "vi. vt.", "dispute": "vi. vt.", "dissolve": "vi. vt.",
    "divorce": "vi. vt.", "double": "vi. vt.", "dress": "vi. vt.", "drown": "vi. vt.",
    "dry": "vi. vt.", "end": "vi. vt.", "engage": "vi. vt.", "enter": "vi. vt.",
    "escape": "vi. vt.", "exercise": "vi. vt.", "expand": "vi. vt.", "extend": "vi. vt.",
    "farm": "vi. vt.", "fear": "vt.", "finish": "vi. vt.", "fit": "vi. vt.",
    "flap": "vi. vt.", "flash": "vi. vt.", "focus": "vi. vt.", "fold": "vi. vt.",
    "pop": "vi. vt.", "pose": "vi. vt.", "preach": "vi. vt.", "press": "vi. vt.",
    "probe": "vi. vt.", "qualify": "vi. vt.", "quit": "vi. vt.", "race": "vi. vt.",
    "rank": "vi. vt.", "reason": "vi. vt.", "reckon": "vi. vt.", "recover": "vi. vt.",
    "register": "vi. vt.", "remark": "vi. vt.", "resign": "vi. vt.", "resolve": "vi. vt.",
    "reverse": "vi. vt.", "roar": "vi. vt.", "rock": "vi. vt.", "root": "vi. vt.",
    "sail": "vi. vt.", "scatter": "vi. vt.", "score": "vi. vt.", "scratch": "vi. vt.",
    "settle": "vi. vt.", "shift": "vi. vt.", "shrink": "vi. vt.", "signal": "vi. vt.",
    "sink": "vi. vt.", "smash": "vi. vt.", "smoke": "vi. vt.", "sniff": "vi. vt.",
    "spark": "vi. vt.", "spell": "vi. vt.", "stitch": "vi. vt.", "surf": "vi. vt.",
    "survive": "vi. vt.", "swallow": "vi. vt.", "swear": "vi. vt.", "swell": "vi. vt.",
    "switch": "vi. vt.", "tap": "vi. vt.", "telephone": "vi. vt.", "tend": "vi. vt.",
    "thaw": "vi. vt.", "theorize": "vi. vt.", "tick": "vi. vt.", "tidy": "vi. vt.",
    "tip": "vi. vt.", "trade": "vi. vt.", "tug": "vi. vt.", "twist": "vi. vt.",
    "unfold": "vi. vt.", "venture": "vi. vt.", "vote": "vi. vt.", "warm": "vi. vt.",
    "weaken": "vi. vt.", "widen": "vi. vt.", "wind": "vi. vt.", "worsen": "vi. vt.",
    "wrestle": "vi. vt.", "accelerate": "vi. vt.", "accumulate": "vi. vt.",
    "adapt": "vi. vt.", "adjust": "vi. vt.", "advance": "vi. vt.",
    "advertise": "vi. vt.", "answer": "vi. vt.", "applaud": "vi. vt.",
    "apply": "vi. vt.", "approach": "vi. vt.", "approve": "vi. vt.",
    "argue": "vi. vt.", "ascend": "vi. vt.", "assist": "vi. vt.",
    "awaken": "vi. vt.", "bang": "vi. vt.", "bathe": "vi. vt.", "beat": "vi. vt.",
    "bet": "vi. vt.", "bid": "vi. vt.", "bite": "vi. vt.", "blend": "vi. vt.",
    "blink": "vi. vt.", "boast": "vi. vt.", "breed": "vi. vt.", "browse": "vi. vt.",
    "end_of_amphibious_block_DO_NOT_ADD": "",
    # ---- 纯及物（vt.）：该义项几乎总带宾语 ----
    "remember": "vt.", "hurt": "vt.", "celebrate": "vt.", "arrange": "vt.",
    "bother": "vt.", "seek": "vt.", "suspect": "vt.", "tire": "vt.",
    "witness": "vt.", "worship": "vt.", "admit": "vt.", "alter": "vt.",
    "explore": "vt.", "pretend": "vt.", "spoil": "vt.", "dispose": "vi.",
    "avail": "vt.", "bank": "vi. vt.", "bruise": "vt.", "bust": "vi. vt.",
    "bound": "vi.",
    # ---- 纯不及物（vi.）：该义项基本不带宾语 ----
    "stand": "vi.", "fail": "vi.", "look": "vi.", "nod": "vi.", "respond": "vi.",
    "rest": "vi.", "travel": "vi.", "fade": "vi.", "bow": "vi.", "complain": "vi.",
    "profit": "vi.", "relax": "vi.", "remain": "vi.", "retire": "vi.",
    "scream": "vi.", "sneak": "vi.", "trip": "vi.", "refer": "vi.",
    "behave": "vi.",
}
POS_OVERRIDE.pop("end_of_amphibious_block_DO_NOT_ADD")  # 移除分块占位提醒项


def make_verb_word(wid, spelling, pos, zh):
    """构建动词 word 对象"""
    forms = infer_verb_forms(spelling)
    # 及物性归一化：数据源标 "v." 的动词优先查人工判定总表；
    # 表里没有则保持原值（由校验工具计为 unknown，禁止机器猜测）
    if pos == "v.":
        pos = POS_OVERRIDE.get(spelling.lower(), pos)
    return {
        "id": wid,
        "spelling": spelling,
        "meanings": [
            {
                "index": 1,
                "pos": pos,                       # vt. / vi. / vi. vt.
                "definitions": [zh],
                # 注意：stative 等语法标记不属于 Meaning 模型（README 已删除），
                # 静态动词知识由 patch/sentence/ 造句知识库承载。
            }
        ],
        "difficulty": 0,                          # number，系统基线无难度梯度
        "phonetic_uk": None,                      # 音标可空
        "phonetic_us": None,
        "plural": [],                             # 动词无复数
        "third_person_singular": forms["third_person_singular"],
        "gerund": forms["gerund"],
        "past_tense": forms["past_tense"],
        "past_participle": forms["past_participle"],
        "comparative": [],
        "superlative": [],
        "reviewed_at": None,
        "created_at": NOW,                        # number 时间戳
        "updated_at": NOW,
        "deleted_at": None,
    }


def make_noun_word(wid, spelling, zh):
    """构建名词 word 对象（严格按 README 现行字段，不含任何已删除的语法标记）"""
    return {
        "id": wid,
        "spelling": spelling,
        "meanings": [
            {
                "index": 1,
                "pos": "n.",
                "definitions": [zh],
                # 注意：is_person 等语义标记不属于 Meaning 模型（README 已删除），
                # 人物名词知识由 patch/sentence/ 造句知识库承载。
            }
        ],
        "difficulty": 0,
        "phonetic_uk": None,
        "phonetic_us": None,
        "plural": infer_noun_plural(spelling),    # 由规则推导
        "third_person_singular": [],
        "gerund": [],
        "past_tense": [],
        "past_participle": [],
        "comparative": [],
        "superlative": [],
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
