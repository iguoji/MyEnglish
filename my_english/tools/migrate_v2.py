#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
旧库（11 张表 + 2 份 SharedPreferences）→ 新库（5 张表）的一次性迁移脚本。

用法：
    python3 tools/migrate_v2.py 旧导出.json 新格式.json

设计依据：项目根目录的 `数据结构.md`。
这个脚本只做「数据形状转换」，不写数据库；产物是一份可以肉眼验收的 JSON，
确认无误后再由 App 的导入流程写进新表。

生活化解释：这就像搬家前先把所有东西摊在地板上分类打包，
贴好标签给你看一眼，你点头了才装车。
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from typing import Any

# --------------------------------------------------------------------------
# 词性拆分规则
# --------------------------------------------------------------------------

# 主词性 -> (主词性, 子词性) 的映射。
# 生活化解释：`vt.` 这种「及物动词」本质上还是动词，所以主词性统一记成 `v.`，
# 「及物 / 不及物」这一级降为子词性，便于按大类聚合统计。
POS_RULES: dict[str, list[tuple[str, str | None]]] = {
    # 未选词性：数据结构.md 约定主词性存空串，界面照旧显示成 '*'。
    "*": [("", None)],
    "": [("", None)],
    # 动词的三种子类。
    "vt.": [("v.", "vt.")],
    "vi.": [("v.", "vi.")],
    "vlink.": [("v.", "vlink.")],
    # 同时是及物和不及物：按 数据结构.md 拆成两条独立记录。
    "vi. vt.": [("v.", "vi."), ("v.", "vt.")],
    "vt. vi.": [("v.", "vi."), ("v.", "vt.")],
}


def split_pos(pos: str) -> list[tuple[str, str | None]]:
    """把旧的单个词性字符串拆成一个或多个 (主词性, 子词性)。"""
    key = (pos or "").strip()
    # 命中特殊规则的走映射表。
    if key in POS_RULES:
        return POS_RULES[key]
    # 其余（n. / adj. / adv. / num. / prep. / conj. / int. / v.）本身就是主词性。
    return [(key, None)]


# --------------------------------------------------------------------------
# 释义错切修复
# --------------------------------------------------------------------------

# 成对括号；用来识别「顿号切在括号里面」造成的碎片。
BRACKET_PAIRS = {
    "(": ")", "（": "）", "[": "]", "【": "】", "〔": "〕",
    "「": "」", "『": "』", "《": "》", "{": "}",
}
BRACKET_CLOSERS = {v: k for k, v in BRACKET_PAIRS.items()}


def bracket_balance(text: str) -> int:
    """返回未闭合的左括号数量；0 表示括号配对完整。"""
    depth = 0
    for char in text:
        if char in BRACKET_PAIRS:
            depth += 1
        elif char in BRACKET_CLOSERS and depth > 0:
            depth -= 1
    return depth


def repair_definitions(definitions: list[str]) -> tuple[list[str], bool]:
    """
    把「括号内顿号被误切」的碎片重新粘回去。

    例：['(骑马', '骑车或乘车的)旅程'] -> ['(骑马、骑车或乘车的)旅程']
    返回 (修复后的列表, 是否发生过修复)。
    """
    merged: list[str] = []
    buffer = ""
    repaired = False
    for item in definitions:
        # buffer 非空说明上一段的括号还没闭合，当前段属于同一个释义。
        if buffer:
            buffer = f"{buffer}、{item}"
            repaired = True
        else:
            buffer = item
        # 括号已经配平，这一条释义才算完整。
        if bracket_balance(buffer) == 0:
            merged.append(buffer)
            buffer = ""
    # 收尾：括号始终没配平时也不能丢数据，原样放回。
    if buffer:
        merged.append(buffer)
    return merged, repaired


# --------------------------------------------------------------------------
# 时间戳
# --------------------------------------------------------------------------

def parse_export_time(value: Any) -> int | None:
    """
    把导出文件里的时间还原成毫秒时间戳。

    旧导出把毫秒时间戳格式化成了本地时区的 'yyyy-MM-dd HH:mm:ss'，
    空字符串代表「没有这个时间」。毫秒精度在导出时已经永久丢失，
    这里按「秒」还原，末尾补 000。
    """
    # 已经是数字的字段（如 reviewed_at_before）直接采用。
    if isinstance(value, (int, float)):
        return int(value) or None
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        # 按本地时区解析，与导出时使用的 SimpleDateFormat 口径一致。
        return int(datetime.strptime(value.strip(), "%Y-%m-%d %H:%M:%S").timestamp() * 1000)
    except ValueError:
        return None


def date_key(millis: int | None) -> str:
    """把毫秒时间戳转成 yyyy-MM-dd；没有时间时返回空串。"""
    if not millis:
        return ""
    return datetime.fromtimestamp(millis / 1000).strftime("%Y-%m-%d")


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------

def migrate(old: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """把旧导出对象转换成新表结构；同时返回一份供人工核对的报告。"""
    report: dict[str, Any] = {"repaired_definitions": [], "dropped": {}, "warnings": []}
    now = int(datetime.now().timestamp() * 1000)

    # ---- 音节划分：按拼写建索引，等下并进单词行 ----------------------------
    syllables_by_spelling = {
        row["word"]: row.get("syllables") or []
        for row in old.get("syllable_divisions") or []
    }

    # ---- 单词表 + 含义表 --------------------------------------------------
    new_words: list[dict[str, Any]] = []
    new_meanings: list[dict[str, Any]] = []
    meaning_id = 0
    # 旧含义行 id -> 新含义行 id 列表（一行炸成多行，会话记录要靠它对上号）。
    meaning_id_map: dict[int, list[int]] = {}

    for word in old.get("words") or []:
        word_id = word["id"]
        created = parse_export_time(word.get("created_at")) or now
        new_words.append({
            "id": word_id,
            "spelling": word["spelling"],
            "difficulty": int(word.get("difficulty") or 0),
            # 混淆词留空，由各模块首次遇到该词时实时生成并回写。
            "confusions": [],
            # 拆分沿用旧的音节表；没算过的词留空，用到时现算。
            "syllables": syllables_by_spelling.get(word["spelling"], []),
            "reviewed_at": parse_export_time(word.get("reviewed_at")),
            "created_at": created,
            "updated_at": parse_export_time(word.get("updated_at")) or created,
            "deleted_at": None,
        })

        # 含义按旧规则「排序值大的在前」展开，保证界面顺序完全不变。
        old_meanings = sorted(
            word.get("meanings") or [],
            key=lambda m: (-int(m.get("index") or 0), m["id"]),
        )
        # 先把这个词的全部 (主词性, 子词性, 含义) 拉平，再统一倒着发排序值。
        flat: list[tuple[int, str, str | None, str]] = []
        for meaning in old_meanings:
            definitions, repaired = repair_definitions(meaning.get("definitions") or [])
            if repaired:
                report["repaired_definitions"].append({
                    "word_id": word_id,
                    "spelling": word["spelling"],
                    "old_meaning_id": meaning["id"],
                    "before": meaning.get("definitions"),
                    "after": definitions,
                })
            for pos, sub_pos in split_pos(meaning.get("pos") or ""):
                for definition in definitions:
                    flat.append((meaning["id"], pos, sub_pos, definition))

        # 排序值降序发放：第一条拿最大值，界面照旧显示在最前面。
        total = len(flat)
        for offset, (old_mid, pos, sub_pos, definition) in enumerate(flat):
            meaning_id += 1
            new_meanings.append({
                "id": meaning_id,
                "word_id": word_id,
                "pos": pos,
                "sub_pos": sub_pos,
                "definition": definition,
                "confusions": [],
                "sort": total - offset,
                "created_at": created,
                "updated_at": created,
                "deleted_at": None,
            })
            meaning_id_map.setdefault(old_mid, []).append(meaning_id)

    # ---- 设置表 -----------------------------------------------------------
    old_settings = old.get("settings") or {}
    new_settings: list[dict[str, Any]] = []

    def put_setting(key: str, value: Any, type_name: str) -> None:
        """把一个配置项写成设置表的一行。"""
        new_settings.append({
            "id": len(new_settings) + 1,
            "key": key,
            # 统一以文本保存，真实类型交给 type 字段声明。
            "value": json.dumps(value, ensure_ascii=False) if type_name == "json"
                     else ("true" if value is True else "false" if value is False else str(value)),
            "type": type_name,
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })

    # 原 app_settings 的五个键，键名保持不变，迁过来就能直接用。
    put_setting("accent", old_settings.get("accent", "american"), "string")
    put_setting("theme", old_settings.get("theme", "light"), "string")
    put_setting("definitionSeparator", old_settings.get("definitionSeparator", "full_width_semicolon"), "string")
    put_setting("dailyGoal", int(old_settings.get("dailyGoal", 50)), "int")
    put_setting("meaningMatchDuration", int(old_settings.get("meaningMatchDuration", 150)), "int")

    # 随身听的播放偏好：旧版藏在 learning_sessions 的快照里，现在升级成正式设置。
    listening_state: dict[str, Any] = {}
    for session in old.get("learning_sessions") or []:
        if session.get("session_type") == "listening":
            listening_state = session.get("state_json") or {}
    put_setting("listeningRepeat", int(listening_state.get("repeat", 2)), "int")
    put_setting("listeningInterval", int(listening_state.get("interval", 2)), "int")
    put_setting("listeningLoop", bool(listening_state.get("loop", True)), "bool")
    put_setting("listeningRevealAll", bool(listening_state.get("revealAll", False)), "bool")
    # 原 word_audio_network 那份 SharedPreferences 只有这一个值，一并收编。
    put_setting("audioNetworkUnavailableUntil", 0, "int")

    # ---- 复习词库表 -------------------------------------------------------
    new_word_sets: list[dict[str, Any]] = []
    for row in old.get("daily_word_sets") or []:
        created = parse_export_time(row.get("created_at")) or now
        new_word_sets.append({
            "id": row["id"],
            "word_count": int(row.get("word_count") or 0),
            "today_word_ids": row.get("word_ids_json") or [],
            # 旧库没有「明日单词列表」，留空；下一次开巩固局时按规则现补。
            "tomorrow_word_ids": [],
            "date": row.get("set_date") or "",
            "created_at": created,
            "updated_at": parse_export_time(row.get("updated_at")) or created,
            "deleted_at": None,
        })

    # ---- 会话表 -----------------------------------------------------------
    # 数据列表的元素形状因模块而异；旧库只存了单词 id，能还原多少算多少。
    PAIR_MODULES = {"meaning_match"}          # 需要 [单词, 含义] 成对
    MEANING_MODULES = {"meaning_word_choice"}  # 需要 [含义]
    new_sessions: list[dict[str, Any]] = []
    for row in old.get("review_sessions") or []:
        state = row.get("state_json") or {}
        created = parse_export_time(row.get("created_at")) or now
        module = row.get("module") or ""
        word_ids = row.get("word_ids_json") or []

        # 旧的「进行中」会话丢掉 state_json 后无法续玩，统一判为中断。
        status = int(row.get("status") or 1)
        if status == 1:
            status = 3
            report["warnings"].append(
                f"会话 #{row['id']}（{module}）原为进行中，因页面现场无法还原已改判为中断"
            )

        # 只有这两类模块的数据列表形状对不上，标注出来而不是悄悄丢掉。
        if module in PAIR_MODULES or module in MEANING_MODULES:
            report["warnings"].append(
                f"会话 #{row['id']}（{module}）的数据列表在旧库里只有单词 id，"
                f"无法还原成新结构要求的形状，已按单词 id 原样留档"
            )

        new_sessions.append({
            "id": row["id"],
            "module": module,
            "kind": int(row.get("kind") or 1),
            "status": status,
            "word_set_id": row.get("word_set_id") or None,
            "items": word_ids,
            # 外层索引：不同模块字段名不同，挨个试。
            "cursor": int(
                state.get("wordIndex")
                or state.get("roundIndex")
                or state.get("groupIndex")
                or state.get("index")
                or 0
            ),
            # 所用时间统一换算成秒。
            "elapsed": int((state.get("elapsedMs") or state.get("totalMs") or 0) / 1000),
            "date": row.get("session_date") or "",
            "created_at": created,
            "updated_at": parse_export_time(row.get("updated_at")) or created,
            "deleted_at": None,
        })

    # 旧的随身听长期会话升级成正式会话，类型记为「无限巩固练习」。
    for row in old.get("learning_sessions") or []:
        if row.get("session_type") != "listening":
            continue
        state = row.get("state_json") or {}
        updated = parse_export_time(row.get("updated_at")) or now
        new_sessions.append({
            "id": max((s["id"] for s in new_sessions), default=0) + 1,
            "module": "listening",
            "kind": 2,
            "status": 3,
            "word_set_id": None,
            "items": row.get("word_ids_json") or [],
            "cursor": int(state.get("index") or 0),
            "elapsed": 0,
            "date": date_key(updated),
            "created_at": updated,
            "updated_at": updated,
            "deleted_at": None,
        })

    # ---- 会话记录表 -------------------------------------------------------
    new_records: list[dict[str, Any]] = []
    for row in old.get("review_records") or []:
        created = parse_export_time(row.get("created_at")) or now
        new_records.append({
            "id": row["id"],
            "session_id": row.get("session_id") or None,
            "word_id": row["word_id"],
            # 旧记录是「一个词一条汇总」，没有精确到具体含义。
            "meaning_id": None,
            # 旧版从没记录过用户实际点了什么（扩展字段一直是空对象）。
            "input": "",
            "result": 1 if int(row.get("is_correct") or 0) == 1 else 0,
            "date": row.get("created_date") or date_key(created),
            "created_at": created,
            "updated_at": created,
            "deleted_at": None,
        })

    # ---- 被丢弃的东西，逐项列清楚 -----------------------------------------
    report["dropped"] = {
        "分组(groups)": len(old.get("groups") or []),
        "分组成员(members)": len(old.get("members") or []),
        "分组顺序(group_positions)": len(old.get("group_positions") or []),
        "听音辨义候选缓存": len(old.get("listening_meaning_option_cache") or []),
        "音标(phonetic_uk/us)": sum(
            1 for w in old.get("words") or [] if w.get("phonetic_uk") or w.get("phonetic_us")
        ),
        "词型(复数/时态等)": sum(
            1 for w in old.get("words") or []
            for k in ("plural", "third_person_singular", "gerund", "past_tense",
                      "past_participle", "comparative", "superlative")
            if w.get(k)
        ),
        "连对次数(streak)": len(old.get("review_records") or []),
        "难度前后值/复习时间前后值": len(old.get("review_records") or []),
        "提示次数(hint_count)": len(old.get("review_records") or []),
        "会话现场(state_json)": len(old.get("review_sessions") or []),
    }

    new = {
        "version": 2,
        "settings": new_settings,
        "words": new_words,
        "meanings": new_meanings,
        "word_sets": new_word_sets,
        "sessions": new_sessions,
        "session_records": new_records,
    }
    return new, report


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    source, target = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as handle:
        old = json.load(handle)

    new, report = migrate(old)

    with open(target, "w", encoding="utf-8") as handle:
        json.dump(new, handle, ensure_ascii=False, indent=1)

    # ---- 控制台报告 -------------------------------------------------------
    print("=" * 70)
    print("迁移完成：", target)
    print("=" * 70)
    print(f"  设置表      {len(new['settings']):>6} 行")
    print(f"  单词表      {len(new['words']):>6} 行")
    print(f"  含义表      {len(new['meanings']):>6} 行   "
          f"(旧库 {sum(len(w.get('meanings') or []) for w in old['words'])} 行，一行一数组)")
    print(f"  复习词库表  {len(new['word_sets']):>6} 行")
    print(f"  会话表      {len(new['sessions']):>6} 行")
    print(f"  会话记录表  {len(new['session_records']):>6} 行")

    print("\n--- 修复的错切释义 ---")
    if report["repaired_definitions"]:
        for item in report["repaired_definitions"]:
            print(f"  #{item['word_id']} {item['spelling']}")
            print(f"      修复前 {item['before']}")
            print(f"      修复后 {item['after']}")
    else:
        print("  无")

    print("\n--- 主动丢弃的数据 ---")
    for name, count in report["dropped"].items():
        print(f"  {name:<28} {count} 条")

    print("\n--- 需要你知道的降级 ---")
    for warning in report["warnings"]:
        print(f"  · {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
