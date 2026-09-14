#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
旧版完整备份（version=2）→ 新版导入备份（version=3）的一次性转换脚本。

用法：
    python3 tools/convert_backup_to_v3.py 旧备份.json 新备份.json

生活化解释：
    旧备份里只有「单词、含义、词库、会话、答题记录」这几摞纸，
    新版本要的是十一张表、而且每张表的格子名称都换过了。
    本脚本只把「单词」和「含义」这两摞纸按新格子重新誊一遍，
    其余几摞（计划、会话、答题、结算）直接给空表 —— 因为新旧结构差得太远，
    硬凑出来的会话会通不过新版本的导入校验（见 StudyRepository.validateImportedData）。

设计依据：`memory/数据结构.md` 与 `my_english/android/app/src/main/kotlin/com/example/my_english/`
下的 `StudySchema.kt`（建表）、`WordsDatabase.kt`（导入校验）、`StudyRepository.kt`（业务校验）。

转换后仍然是一份 JSON 文件，由 App 的「数据导入」入口整库替换写入。
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from typing import Any

# --------------------------------------------------------------------------
# 新版十一张表，以及每张表允许出现的列
# 与 StudySchema.kt 的 tables / 各表字段一一对应；多一个列都会被导入拒绝。
# --------------------------------------------------------------------------

TABLE_COLUMNS: dict[str, list[str]] = {
    "settings": ["id", "key", "value", "type", "created_at", "updated_at", "deleted_at"],
    "words": ["id", "spelling", "difficulty", "confusions", "syllables", "reviewed_at",
              "created_at", "updated_at", "deleted_at"],
    "word_meanings": ["id", "word_id", "pos", "sub_pos", "definition", "confusions", "sort",
                      "created_at", "updated_at", "deleted_at"],
    "plans": ["id", "date", "created_at", "updated_at", "deleted_at"],
    "plan_words": ["id", "plan_id", "word_id", "word_type", "created_at", "updated_at", "deleted_at"],
    "sessions": ["id", "module", "date", "kind", "status", "requires_answer", "settlement_status",
                 "plan_id", "current_main_question_id", "elapsed_seconds", "answer_seconds",
                 "created_at", "updated_at", "deleted_at"],
    "session_main_questions": ["id", "session_id", "question_no", "phase", "retry_count",
                               "current_sub_question_id", "created_at", "updated_at", "deleted_at"],
    "session_sub_questions": ["id", "main_question_id", "question_no", "question_type",
                              "content_type", "answer_type", "used_seconds", "content", "answers",
                              "distractors", "created_at", "updated_at", "deleted_at"],
    "session_question_details": ["id", "sub_question_id", "word_id", "meaning_id",
                                 "created_at", "updated_at", "deleted_at"],
    "session_question_answers": ["id", "sub_question_id", "attempt_no", "answer", "is_correct",
                                 "created_at", "updated_at", "deleted_at"],
    "session_word_settlements": ["id", "apply_status", "session_id", "word_id", "date", "is_correct",
                                 "difficulty_before", "difficulty_after", "suggested_adjustment",
                                 "adjustment", "operation", "created_at", "updated_at", "deleted_at"],
}

# 导入时会被还原成数组的列（其余一律是文本/数字）。
ARRAY_COLUMNS: dict[str, set[str]] = {
    "words": {"confusions", "syllables"},
    "word_meanings": {"confusions"},
    "session_sub_questions": {"content", "answers", "distractors"},
    "session_question_answers": {"answer"},
}

# 只搬运新版界面真正还会读取的偏好；旧版独有的键（含时长、音频不可用截止时间）直接丢弃。
SETTING_KEYS = [
    "accent", "theme", "definitionSeparator", "dailyGoal",
    "listeningRepeat", "listeningInterval", "listeningLoop", "listeningRevealAll",
]


# --------------------------------------------------------------------------
# 工具函数
# --------------------------------------------------------------------------

def millis(row: dict[str, Any], field: str) -> int | None:
    """
    取出某一列的毫秒时间戳。

    旧备份同时给了两种写法：`reviewed_at` 是给人看的 "2026-08-30 18:12:21"，
    `reviewed_at_ms` 才是真正要的毫秒整数。优先用后者，没有才退回去解析文本。
    两个都没有就返回 None（表示「没有这个时间」）。
    """
    raw = row.get(f"{field}_ms")
    if isinstance(raw, (int, float)):
        return int(raw)
    text = row.get(field)
    if not isinstance(text, str) or not text.strip():
        return None
    try:
        # 按本地时区解析，与导出时使用的格式化口径一致；毫秒精度已丢失，末尾补 000。
        return int(datetime.strptime(text.strip(), "%Y-%m-%d %H:%M:%S").timestamp() * 1000)
    except ValueError:
        return None


def clean_text(value: Any) -> str:
    """把任意值收敛成去掉首尾空白的字符串。"""
    return "" if value is None else str(value).strip()


def string_list(raw: Any) -> list[str]:
    """把混淆词/音节这类列收敛成去重后的非空字符串数组。"""
    if not isinstance(raw, list):
        return []
    seen: list[str] = []
    for item in raw:
        text = clean_text(item)
        if text and text not in seen:
            seen.append(text)
    return seen


def to_row(table: str, row: dict[str, Any]) -> dict[str, Any]:
    """
    按目标表的列白名单过滤一行，顺带做一次自检。

    导入会拒绝任何未知列，所以这里主动剔除旧备份多出来的 `_ms`、可读时间等字段，
    而不是等 App 报错。
    """
    allowed = set(TABLE_COLUMNS[table])
    result = {key: value for key, value in row.items() if key in allowed}
    unknown = set(row) - allowed
    if unknown:
        raise ValueError(f"{table} 第 {row.get('id')} 行含未知字段：{sorted(unknown)}")
    return result


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------

def convert(old: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """把旧备份对象转成新版导入对象；同时返回一份供人工核对的报告。"""
    if int(old.get("version") or 0) != 2:
        raise ValueError(f"只支持转换 version=2 的旧备份，当前是 {old.get('version')!r}")

    report: dict[str, Any] = {"dropped": {}, "warnings": []}
    now = int(datetime.now().timestamp() * 1000)

    # ---- 单词表 ----------------------------------------------------------
    new_words: list[dict[str, Any]] = []
    for word in old.get("words") or []:
        spelling = clean_text(word.get("spelling"))
        if not spelling:
            raise ValueError(f"单词 #{word.get('id')} 拼写为空，新版不允许")
        created = millis(word, "created_at") or now
        new_words.append(to_row("words", {
            "id": int(word["id"]),
            "spelling": spelling,
            "difficulty": int(word.get("difficulty") or 0),
            # 混淆词与音节都是「用到时现算」，但旧备份里已有的照搬过来，省一次重算。
            "confusions": string_list(word.get("confusions")),
            "syllables": string_list(word.get("syllables")),
            "reviewed_at": millis(word, "reviewed_at"),
            "created_at": created,
            "updated_at": millis(word, "updated_at") or created,
            "deleted_at": millis(word, "deleted_at"),
        }))

    # ---- 含义表 ----------------------------------------------------------
    word_ids = {word["id"] for word in new_words}
    new_meanings: list[dict[str, Any]] = []
    for meaning in old.get("meanings") or []:
        definition = clean_text(meaning.get("definition"))
        if not definition:
            raise ValueError(f"含义 #{meaning.get('id')} 内容为空，新版不允许")
        if int(meaning["word_id"]) not in word_ids:
            raise ValueError(f"含义 #{meaning.get('id')} 指向不存在的单词 #{meaning['word_id']}")
        created = millis(meaning, "created_at") or now
        # 空词性统一存成空值：新版展示层把空值显示成 '*'，写空串会绕过这层判断。
        pos = clean_text(meaning.get("pos"))
        sub_pos = clean_text(meaning.get("sub_pos"))
        new_meanings.append(to_row("word_meanings", {
            "id": int(meaning["id"]),
            "word_id": int(meaning["word_id"]),
            "pos": pos or None,
            "sub_pos": sub_pos or None,
            "definition": definition,
            "confusions": string_list(meaning.get("confusions")),
            "sort": int(meaning.get("sort") or 0),
            "created_at": created,
            "updated_at": millis(meaning, "updated_at") or created,
            "deleted_at": millis(meaning, "deleted_at"),
        }))

    # ---- 设置表 ----------------------------------------------------------
    # 旧备份的 settings 是一张「键 → 值 + 类型」的清单，新版结构完全相同，
    # 差别只在于新版不再使用其中两个键，这里按白名单筛一遍。
    old_settings = {row["key"]: row for row in old.get("settings") or []}
    new_settings: list[dict[str, Any]] = []
    for key in SETTING_KEYS:
        source = old_settings.get(key)
        if source is None:
            report["warnings"].append(f"设置 {key} 在旧备份中不存在，将由 App 使用默认值")
            continue
        created = millis(source, "created_at") or now
        new_settings.append(to_row("settings", {
            "id": len(new_settings) + 1,
            "key": key,
            "value": clean_text(source.get("value")),
            "type": clean_text(source.get("type")) or "string",
            "created_at": created,
            "updated_at": millis(source, "updated_at") or created,
            "deleted_at": None,
        }))

    # ---- 明确丢弃的东西，逐项列清楚 ---------------------------------------
    report["dropped"] = {
        "计划/复习词库(word_sets)": len(old.get("word_sets") or []),
        "会话(sessions)": len(old.get("sessions") or []),
        "答题记录(session_records)": len(old.get("session_records") or []),
        "旧版设置键": len(set(old_settings) - set(SETTING_KEYS)),
    }
    if old.get("sessions") or old.get("session_records"):
        report["warnings"].append(
            "新旧会话结构完全不同（旧版是一层平表，新版是大题/小题/明细/答题四层），"
            "无法自动还原，已全部丢弃；首页连对、曲线与热力图统计会从零开始"
        )

    new: dict[str, Any] = {"version": 3, "time_unit": "milliseconds"}
    for table in TABLE_COLUMNS:
        if table == "settings":
            new[table] = new_settings
        elif table == "words":
            new[table] = new_words
        elif table == "word_meanings":
            new[table] = new_meanings
        else:
            # 其余八张表给空数组：导入要求十一张表全部出现，缺一张都会整份拒绝。
            new[table] = []
    return new, report


# --------------------------------------------------------------------------
# 自检：模拟 App 导入时会做的全部检查，提前把问题挡在本机
# --------------------------------------------------------------------------

DATE_PATTERN = re.compile(r"\d{4}-\d{2}-\d{2}")


def validate(new: dict[str, Any]) -> None:
    """照着 WordsDatabase.importData 的口径把产物过一遍。"""
    assert new["version"] == 3, "版本号必须是 3"
    assert new.get("time_unit") == "milliseconds", "时间单位必须是 milliseconds"

    for table, columns in TABLE_COLUMNS.items():
        rows = new.get(table)
        assert isinstance(rows, list), f"缺少 {table} 数组"
        for index, row in enumerate(rows):
            where = f"{table} 第 {index + 1} 行"
            assert isinstance(row, dict), f"{where} 不是对象"
            unknown = set(row) - set(columns)
            assert not unknown, f"{where} 含未知字段 {sorted(unknown)}"
            assert int(row["id"]) > 0, f"{where} 编号无效"
            for column in ARRAY_COLUMNS.get(table, set()):
                if row.get(column) is not None:
                    assert isinstance(row[column], list) and all(
                        isinstance(item, str) for item in row[column]
                    ), f"{where}.{column} 必须是文本数组"
            for column in ("created_at", "updated_at", "deleted_at", "reviewed_at"):
                value = row.get(column)
                if column in columns and value is not None:
                    assert isinstance(value, int), f"{where}.{column} 必须是毫秒整数"
            if "date" in columns:
                assert DATE_PATTERN.fullmatch(str(row.get("date") or "")), f"{where} 日期无效"

    # 外键：含义必须挂在存在的单词上。
    ids = {row["id"] for row in new["words"]}
    for row in new["word_meanings"]:
        assert row["word_id"] in ids, f"含义 #{row['id']} 指向不存在的单词"

    # 数据库自身的取值约束。
    for row in new["words"]:
        assert row["difficulty"] >= 0, f"单词 #{row['id']} 难度为负"
        assert row["spelling"].strip(), f"单词 #{row['id']} 拼写为空"
    for row in new["word_meanings"]:
        assert row["definition"].strip(), f"含义 #{row['id']} 内容为空"

    # 设置键不能重复（settings 上有「未删除时键唯一」的索引）。
    keys = [row["key"] for row in new["settings"]]
    assert len(keys) == len(set(keys)), "设置键重复"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    source, target = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as handle:
        old = json.load(handle)

    new, report = convert(old)
    validate(new)

    with open(target, "w", encoding="utf-8") as handle:
        json.dump(new, handle, ensure_ascii=False, indent=1)

    # ---- 控制台报告 -------------------------------------------------------
    print("=" * 70)
    print("转换完成：", target)
    print("=" * 70)
    for table, columns in TABLE_COLUMNS.items():
        print(f"  {table:<26} {len(new[table]):>6} 行")

    print("\n--- 主动丢弃的数据 ---")
    for name, count in report["dropped"].items():
        print(f"  {name:<28} {count} 条")

    print("\n--- 需要你知道的降级 ---")
    for warning in report["warnings"]:
        print(f"  · {warning}")
    print("\n自检通过：结构、字段、外键、约束全部符合新版导入要求。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
