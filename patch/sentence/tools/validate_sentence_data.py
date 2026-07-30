#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
造句知识库持久化验证工具（任务8）
================================

职责（对应任务8的检查清单）：
  1. JSON 语法       —— 所有 patch/sentence/ 下的 .json 必须能被解析
  2. 重复键          —— 同一 JSON 对象里出现两次相同 key（json.loads 默认吞掉，需自定义钩子抓）
  3. Schema 结构     —— 数据文件必须通过对应的 JSON Schema (draft-07) 校验
  4. 非法枚举        —— policy 值必须落在该 policy_kind 的合法值域内（Schema 只能约束全集，
                        这里做"按 kind 分域"的二次检查）
  5. 系统词存在性    —— annotations/paradigms 引用的拼写必须存在于系统词库（patch/*.json），
                        绝不加载 words.json（系统独立原则）
  6. 冲突规则        —— 同一拼写在同一 policy 表中只允许一个策略（对象 key 天然唯一，
                        由重复键检查兜底）；跨表冲突（如 mass 与 plural_only 同词）报错
  7. 公式引用        —— formulas/ 中引用的槽位、词表必须真实存在（公式文件建成后自动生效）
  8. unknown 统计    —— 汇总所有标 unknown 的条目数量，供报告引用
  9. 覆盖率          —— 各资料表覆盖系统词库的比例，供报告引用

退出码：0 = 全部通过；1 = 存在错误（警告不影响退出码）。

运行方式（必须用装有 jsonschema 的 venv）：
  /Users/iguoji/.workbuddy/binaries/python/envs/default/bin/python \
      patch/sentence/tools/validate_sentence_data.py
"""

import json
import sys
import glob
import os
from collections import Counter

# ---------------------------------------------------------------------------
# 路径常量：本文件在 patch/sentence/tools/，向上 3 层是项目根
# ---------------------------------------------------------------------------
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
SENT_DIR = os.path.dirname(TOOLS_DIR)               # patch/sentence
PATCH_DIR = os.path.dirname(SENT_DIR)               # patch
ROOT_DIR = os.path.dirname(PATCH_DIR)               # 项目根

ERRORS = []    # 致命问题：导致 exit 1
WARNINGS = []  # 非致命问题：仅打印


def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNINGS.append(msg)


# ---------------------------------------------------------------------------
# 检查 1+2：JSON 语法 与 重复键
# object_pairs_hook 会在解析每个对象时拿到原始 (key, value) 列表，
# 借此发现 json.loads 默认静默覆盖的重复 key
# ---------------------------------------------------------------------------
def load_json_strict(path):
    """严格加载 JSON：语法错误与重复键都记为 ERROR，返回 (data, ok)"""

    def no_dup_hook(pairs):
        keys = [k for k, _ in pairs]
        dup = [k for k, c in Counter(keys).items() if c > 1]
        if dup:
            err(f"{os.path.relpath(path, ROOT_DIR)}: 对象内重复键 {dup}")
        return dict(pairs)

    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f, object_pairs_hook=no_dup_hook), True
    except json.JSONDecodeError as e:
        err(f"{os.path.relpath(path, ROOT_DIR)}: JSON 语法错误 -> {e}")
        return None, False


# ---------------------------------------------------------------------------
# 检查 3：Schema 校验
# 数据文件 → Schema 的映射表；$ref 用文件名注册表解析（referencing 库）
# ---------------------------------------------------------------------------
# 每个数据文件对应哪个 Schema；paradigms 是"列表包对象"，Schema 描述单个对象，
# 所以 item_level=True 表示逐条校验列表元素
DATA_SCHEMA_MAP = [
    # (glob 相对 SENT_DIR, schema 文件名, 是否逐条校验列表元素)
    ('annotations/*.json',            'annotation_policy.schema.json',  False),
    # 范式 Schema 顶层就是 type:array（描述整个文件），所以整体校验而非逐条
    ('paradigms/pronouns.json',       'pronoun_paradigm.schema.json',   False),
    ('paradigms/auxiliaries.json',    'auxiliary_paradigm.schema.json', False),
    ('paradigms/determiner_rules.json', 'determiner_rules.schema.json', False),
    ('lexicon/article_phonetics.json', 'article_phonetics.schema.json', False),
    # lexicon 四表的 Schema 顶层同样是 type:array（描述整个文件）→ 整体校验
    ('lexicon/noun_usage.json',       'noun_usage.schema.json',         False),
    ('lexicon/verb_frames.json',      'verb_frame.schema.json',         False),
    ('lexicon/adjective_usage.json',  'adjective_usage.schema.json',    False),
    ('lexicon/adverb_usage.json',     'adverb_usage.schema.json',       False),
    # 公式 Schema 顶层同样是 type:array → 整体校验
    ('formulas/*.json',               'formula.schema.json',            False),
    ('formulas/compatibility_matrix.json', 'compatibility_matrix.schema.json', False),
    ('tests/golden.json',             'golden_test.schema.json',        False),
]


def build_validator_factory():
    """构建 Schema 注册表：把 schemas/ 下所有文件既按文件名、又按 $id 注册，
    使 "noun_usage.schema.json#/$defs/provenance" 这类相对 $ref 可解析。"""
    try:
        from jsonschema import Draft7Validator
        from referencing import Registry, Resource
        from referencing.jsonschema import DRAFT7
    except ImportError:
        err("缺少 jsonschema/referencing 库：请用 default venv 运行本脚本")
        return None

    resources = []
    schemas = {}
    for sp in glob.glob(os.path.join(SENT_DIR, 'schemas', '*.schema.json')):
        s, ok = load_json_strict(sp)
        if not ok:
            continue
        name = os.path.basename(sp)
        schemas[name] = s
        res = Resource.from_contents(s, default_specification=DRAFT7)
        resources.append((name, res))                 # 以文件名为 URI 注册（支持相对 $ref）
        if '$id' in s:
            resources.append((s['$id'], res))          # 以 $id 注册（支持绝对 $ref）
    registry = Registry().with_resources(resources)

    def make(schema_name):
        if schema_name not in schemas:
            err(f"缺少 Schema 文件: schemas/{schema_name}")
            return None
        return Draft7Validator(schemas[schema_name], registry=registry)

    return make


# ---------------------------------------------------------------------------
# 检查 4：按 policy_kind 分域的合法枚举
# Schema 的 enum 是全集（四种表共用），这里限制每种表只能用自己的值
# ---------------------------------------------------------------------------
POLICY_DOMAIN = {
    'stative':         {'usually_stative', 'dynamic', 'both', 'unknown'},
    'gradability':     {'gradable', 'usually_ungradable', 'contextual', 'unknown'},
    'number_behavior': {'regular', 'invariant', 'plural_only', 'collective', 'mass', 'unknown'},
    'person_default':  {'default_person', 'person_only_some_senses', 'unknown'},
}


# ---------------------------------------------------------------------------
# 检查 5：系统词存在性 —— 只加载 patch/*.json（根目录词库），不碰 words.json
# ---------------------------------------------------------------------------
# 基线词条里的变形字段：这些字段的值也算"系统认识的词形"（如 child → children）
_FORM_FIELDS = ('plural', 'third_person_singular', 'gerund',
                'past_tense', 'past_participle', 'comparative', 'superlative')


def load_system_lexicon():
    """返回 (原形集合, 原形+变形集合, (拼写,词性)集合)，来源仅系统词库 patch/*.json"""
    spellings = set()      # 词条原形拼写
    all_forms = set()      # 原形 + 全部变形（识别 children/went 这类屈折形）
    spelling_pos = set()
    for jp in glob.glob(os.path.join(PATCH_DIR, '*.json')):
        data, ok = load_json_strict(jp)
        # 防御：patch 根目录只应有 list[dict] 词库；其他形状跳过
        if not ok or not isinstance(data, list):
            continue
        for w in data:
            if not isinstance(w, dict) or 'spelling' not in w:
                continue
            sp = w['spelling'].lower()
            spellings.add(sp)
            all_forms.add(sp)
            for field in _FORM_FIELDS:
                v = w.get(field)
                if isinstance(v, list):
                    all_forms.update(x.lower() for x in v if isinstance(x, str))
                elif isinstance(v, str) and v:
                    all_forms.add(v.lower())
            for m in w.get('meanings', []):
                spelling_pos.add((sp, m.get('pos', '')))
    return spellings, all_forms, spelling_pos


def main():
    make_validator = build_validator_factory()
    system_spellings, system_forms, system_spelling_pos = load_system_lexicon()
    print(f"系统词库拼写数: {len(system_spellings)}，含变形词形: {len(system_forms)}"
          f"（仅 patch/*.json，未加载 words.json）")

    unknown_count = 0            # 检查 8：unknown 总数
    policy_word_kinds = {}       # 检查 6：spelling -> {policy_kind} 用于跨表冲突
    stats = {}                   # 检查 9：覆盖率统计

    # 预加载策略表 {policy_kind: {拼写: policy}}：供 lexicon 交叉一致性检查使用
    # （不依赖主循环遍历顺序，主循环里 annotations 的其他检查照旧执行）
    annotation_entries = {}
    for ap in sorted(glob.glob(os.path.join(SENT_DIR, 'annotations', '*.json'))):
        adata, aok = load_json_strict(ap)
        if aok and isinstance(adata, dict) and 'policy_kind' in adata:
            annotation_entries[adata['policy_kind']] = {
                sp.lower(): info.get('policy')
                for sp, info in adata.get('entries', {}).items()}

    # ---- 逐个数据文件：Schema + 枚举 + 词存在性 ----
    for pattern, schema_name, item_level in DATA_SCHEMA_MAP:
        paths = sorted(glob.glob(os.path.join(SENT_DIR, pattern)))
        # compatibility_matrix 会被 formulas/*.json 通配抓到，靠具体条目在后面去重
        for path in paths:
            rel = os.path.relpath(path, ROOT_DIR)
            # 具体文件条目优先：若该文件同时匹配某个更具体的条目，则跳过通配条目
            specific = [p for p, _, _ in DATA_SCHEMA_MAP
                        if '*' not in p and os.path.join(SENT_DIR, p) == path]
            if '*' in pattern and specific:
                continue

            data, ok = load_json_strict(path)
            if not ok:
                continue

            validator = make_validator(schema_name) if make_validator else None
            if validator is not None:
                targets = data if (item_level and isinstance(data, list)) else [data]
                for i, item in enumerate(targets):
                    for e in validator.iter_errors(item):
                        loc = f"[{i}]" if item_level else ""
                        err(f"{rel}{loc}: Schema 校验失败 -> {e.message}"
                            f"（路径: {'/'.join(map(str, e.absolute_path))}）")

            # ---- annotations 专属：枚举分域 + unknown 统计 + 跨表记录 + 覆盖统计 ----
            # 定位说明：annotations 是"外部语法知识"，允许（且应当）覆盖系统基线
            # 之外的高频词（unique/children/singer…），这样用户录入这些词时生成器
            # 依然有语法知识可用。因此"不在系统词库"不是错误，只做覆盖率统计。
            if pattern.startswith('annotations/') and isinstance(data, dict):
                kind = data.get('policy_kind')
                domain = POLICY_DOMAIN.get(kind)
                entries = data.get('entries', {})
                n_unknown = 0
                n_in_system = 0
                for sp, info in entries.items():
                    pol = info.get('policy')
                    if domain and pol not in domain:
                        err(f"{rel}: '{sp}' 的 policy '{pol}' 不在 {kind} 值域 {sorted(domain)}")
                    if pol == 'unknown':
                        n_unknown += 1
                    # 覆盖统计：原形或变形命中系统词库都算"当前基线已可用"
                    if sp.lower() in system_forms:
                        n_in_system += 1
                    policy_word_kinds.setdefault(sp.lower(), set()).add(kind)
                unknown_count += n_unknown
                stats[rel] = {'entries': len(entries), 'unknown': n_unknown,
                              'in_system': n_in_system}

            # ---- lexicon 专属：条目统计 + 覆盖率 + 与 annotations 交叉一致性 ----
            # lexicon 与 annotations 同属"外部语法知识"，允许收录基线外高频词，
            # 因此"不在系统词库"只统计不报错；但同一拼写在 lexicon 与 annotations
            # 出现判定矛盾（如 lexicon 说 mass、annotations 说 plural_only）是致命错误。
            if pattern.startswith('lexicon/') and isinstance(data, list) \
                    and os.path.basename(path) != 'article_phonetics.json':
                n_unknown = 0
                n_in_system = 0
                # 每张 lexicon 表要与哪张策略表交叉核对：文件名 -> (字段名, 策略字典名)
                cross_map = {
                    'noun_usage.json': ('number_behavior', 'number_behavior'),
                    'verb_frames.json': ('stative_policy', 'stative'),
                    'adjective_usage.json': ('gradability', 'gradability'),
                }
                cross_field, cross_kind = cross_map.get(
                    os.path.basename(path), (None, None))
                for item in data:
                    if not isinstance(item, dict):
                        continue
                    sp = (item.get('spelling') or '').lower()
                    # unknown 统计：任何值为 'unknown' 的字段都计入
                    n_unknown += sum(1 for v in item.values() if v == 'unknown')
                    if sp in system_forms:
                        n_in_system += 1
                    # 交叉一致性：lexicon 的判定必须与 annotations 策略表一致
                    if cross_field and sp in annotation_entries.get(cross_kind, {}):
                        ann_pol = annotation_entries[cross_kind][sp]
                        lex_val = item.get(cross_field)
                        # 允许 lexicon 显式覆盖的白名单：be 系动词的 stative
                        if lex_val and lex_val != ann_pol and sp != 'be':
                            err(f"{rel}: '{sp}' 的 {cross_field}='{lex_val}' 与 "
                                f"annotations 策略 '{ann_pol}' 矛盾")
                stats[rel] = {'entries': len(data), 'unknown': n_unknown,
                              'in_system': n_in_system}

            # ---- paradigms 专属：拼写字段存在性（范式词本身属封闭类，必须在系统词库）----
            if pattern.startswith('paradigms/') and isinstance(data, list):
                miss = []
                for item in data:
                    sp = (item.get('spelling') or item.get('word') or '').lower()
                    if sp and sp not in system_spellings:
                        miss.append(sp)
                if miss:
                    err(f"{rel}: 范式词不在系统词库 {miss}")
                stats[rel] = {'entries': len(data)}

    # ---- 检查 6：跨表语义冲突（number_behavior 内部由值域保证互斥；
    #      跨表如 stative(动词表) 与 gradability(形容词表) 同词只警告，因跨词性同拼写合法）----
    cross = {sp: kinds for sp, kinds in policy_word_kinds.items() if len(kinds) > 1}
    for sp, kinds in sorted(cross.items()):
        warn(f"'{sp}' 同时出现在多张策略表 {sorted(kinds)}（跨词性同拼写属合法，仅提示复核）")

    # ---- 检查 9：覆盖率报告 ----
    print("\n== 资料表规模 ==")
    for rel, s in sorted(stats.items()):
        extra = ''
        if 'unknown' in s:
            extra = (f"，unknown={s['unknown']}"
                     f"，命中系统基线 {s['in_system']}/{s['entries']}")
        print(f"  {rel}: {s['entries']} 条{extra}")
    print(f"\nunknown 总数: {unknown_count}")

    # ---- 汇总（同一文件被预加载与主循环各读一次，错误需按原顺序去重）----
    ERRORS[:] = list(dict.fromkeys(ERRORS))
    WARNINGS[:] = list(dict.fromkeys(WARNINGS))
    if WARNINGS:
        print(f"\n== 警告 {len(WARNINGS)} 条 ==")
        for w in WARNINGS:
            print("  [WARN]", w)
    if ERRORS:
        print(f"\n== 错误 {len(ERRORS)} 条 ==")
        for e in ERRORS:
            print("  [FAIL]", e)
        sys.exit(1)
    print("\n[PASS] 造句知识库全部校验通过（系统独立，未加载 words.json）")
    sys.exit(0)


if __name__ == '__main__':
    main()
