#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""由 Codex 编写的黑盒生成器契约测试。

这里允许把 ``mini_generator`` 当成“被测系统”导入，但不调用它的
``check_grammar``、``analyzer`` 或 Hy3 的评估器。测试答案、拒绝答案和表层
检查均在本文件中独立定义，避免生成器和检测器共享同一套判定逻辑而一起出错。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence


TOOLS_DIR = Path(__file__).resolve().parent
REPORT = TOOLS_DIR.parent / "reports" / "codex_generator_contract.json"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import mini_generator as under_test


POSITIVE_CASES: List[Dict[str, Any]] = [
    {"id": "sv_present_third", "args": ("SV", "present_simple", "affirmative", "none"), "choice": {"subject": "he", "verb": "run"}, "expect": "He runs."},
    {"id": "sv_past_irregular", "args": ("SV", "past_simple", "affirmative", "none"), "choice": {"subject": "she", "verb": "go"}, "expect": "She went."},
    {"id": "svp_be", "args": ("SVP", "present_simple", "affirmative", "none"), "choice": {"subject": "she", "verb": "be", "predicative": "happy"}, "expect": "She is happy."},
    {"id": "svo_mass_noun", "args": ("SVO", "present_simple", "affirmative", "none"), "choice": {"subject": "she", "verb": "drink", "object": "water"}, "expect": "She drinks some water."},
    {"id": "svo_article_phonetics", "args": ("SVO", "present_simple", "affirmative", "none"), "choice": {"subject": "she", "verb": "eat", "object": "apple"}, "expect": "She eats an apple."},
    {"id": "svo_negative_do", "args": ("SVO", "present_simple", "negative", "none"), "choice": {"subject": "she", "verb": "read", "object": "book"}, "expect": "She does not read a book."},
    {"id": "svo_yes_no_do", "args": ("SVO", "present_simple", "affirmative", "yes_no"), "choice": {"subject": "she", "verb": "read", "object": "book"}, "expect": "Does she read a book?"},
    {"id": "sv_future", "args": ("SV", "future_simple", "affirmative", "none"), "choice": {"subject": "he", "verb": "run"}, "expect": "He will run."},
    {"id": "svo_present_continuous", "args": ("SVO", "present_continuous", "affirmative", "none"), "choice": {"subject": "I", "verb": "eat", "object": "apple"}, "expect": "I am eating an apple."},
    {"id": "svo_past_continuous", "args": ("SVO", "past_continuous", "affirmative", "none"), "choice": {"subject": "they", "verb": "read", "object": "book"}, "expect": "They were reading a book."},
    {"id": "svo_present_perfect", "args": ("SVO", "present_perfect", "affirmative", "none"), "choice": {"subject": "she", "verb": "eat", "object": "apple"}, "expect": "She has eaten an apple."},
    {"id": "there_be_singular", "args": ("THERE_BE", "present_simple", "affirmative", "none"), "choice": {"noun": "book", "np_number": "singular", "with_location": False}, "expect": "There is a book."},
    {"id": "there_be_plural", "args": ("THERE_BE", "present_simple", "affirmative", "none"), "choice": {"noun": "book", "np_number": "plural", "with_location": False}, "expect": "There are two books."},
]

NEGATIVE_CASES: List[Dict[str, Any]] = [
    {"id": "stative_continuous", "args": ("SVO", "present_continuous", "affirmative", "none"), "choice": {"subject": "I", "verb": "know", "object": "answer"}, "expect_code": "stative_in_continuous"},
    {"id": "weather_non_it", "args": ("SV", "present_simple", "affirmative", "none"), "choice": {"subject": "dog", "verb": "rain"}, "expect_code": "subject_restriction_unmet"},
    {"id": "bad_object", "args": ("SVO", "present_simple", "affirmative", "none"), "choice": {"subject": "she", "verb": "eat", "object": "desk"}, "expect_code": "object_restriction_unmet"},
    {"id": "bad_frame", "args": ("SVO", "present_simple", "affirmative", "none"), "choice": {"subject": "he", "verb": "run", "object": "book"}, "expect_code": "verb_frame_unmet"},
    {"id": "there_be_continuous", "args": ("THERE_BE", "present_continuous", "affirmative", "none"), "choice": {"noun": "book"}, "expect_code": "forbid_there_be_continuous"},
    {"id": "mass_plural", "args": ("THERE_BE", "present_simple", "affirmative", "none"), "choice": {"noun": "water", "np_number": "plural"}, "expect_code": "there_be_number_unmet"},
]


def surface_problems(sentence: str) -> List[str]:
    """只检查生成结果的机械表面，不调用被测系统的检查器。"""

    problems: List[str] = []
    if not sentence or not sentence.strip():
        problems.append("empty")
        return problems
    if sentence != sentence.strip():
        problems.append("outer_whitespace")
    if "  " in sentence:
        problems.append("double_space")
    if not re.search(r"[.!?]$", sentence):
        problems.append("missing_terminal_punctuation")
    if not sentence[0].isupper():
        problems.append("not_capitalized")
    if re.search(r"\b(?:is|are|was|were|do|does|did)'nt\b", sentence, re.IGNORECASE):
        problems.append("malformed_negative_contraction")
    return problems


def run_case(case: Dict[str, Any]) -> Dict[str, Any]:
    """执行一条正例或反例，并把异常转换成报告行。"""

    try:
        actual = under_test.generate(*case["args"], choice=case["choice"])
        if "expect" in case:
            surface = surface_problems(actual)
            passed = actual == case["expect"] and not surface
            return {
                "id": case["id"],
                "kind": "positive",
                "passed": passed,
                "expected": case["expect"],
                "actual": actual,
                "surface_problems": surface,
            }
        return {
            "id": case["id"],
            "kind": "negative",
            "passed": False,
            "expected_code": case["expect_code"],
            "actual": actual,
            "failure": "本应拒绝但生成了句子",
        }
    except Exception as exc:
        code = getattr(exc, "code", type(exc).__name__)
        if "expect" in case:
            return {
                "id": case["id"],
                "kind": "positive",
                "passed": False,
                "expected": case["expect"],
                "actual_exception": code,
            }
        return {
            "id": case["id"],
            "kind": "negative",
            "passed": code == case["expect_code"],
            "expected_code": case["expect_code"],
            "actual_code": code,
        }


def run_contract() -> Dict[str, Any]:
    """载入被测词库，执行独立正反例并汇总。"""

    under_test.K = under_test.Knowledge()
    rows = [run_case(case) for case in POSITIVE_CASES + NEGATIVE_CASES]
    passed = sum(1 for row in rows if row["passed"])
    positive_total = len(POSITIVE_CASES)
    negative_total = len(NEGATIVE_CASES)
    return {
        "meta": {
            "tester": "codex_generator_contract.py",
            "under_test": "mini_generator.generate",
            "not_used": ["mini_generator.check_grammar", "analyzer.py", "evaluate_corpus.py"],
            "purpose": "独立验证生成文本和安全拒绝契约，不代表通用英语语法覆盖",
        },
        "summary": {
            "total": len(rows),
            "passed": passed,
            "failed": len(rows) - passed,
            "positive_total": positive_total,
            "positive_passed": sum(1 for row in rows[:positive_total] if row["passed"]),
            "negative_total": negative_total,
            "negative_passed": sum(1 for row in rows[positive_total:] if row["passed"]),
            "result": "PASS" if passed == len(rows) else "FAIL",
        },
        "cases": rows,
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="运行独立黑盒生成器契约测试")
    parser.add_argument("--report", type=Path, default=REPORT)
    args = parser.parse_args(argv)
    try:
        report = run_contract()
    except Exception as exc:
        print(f"[FAIL] 契约测试无法启动：{type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = report["summary"]
    print(f"黑盒契约测试：{summary['passed']}/{summary['total']} PASS，结果 {summary['result']}")
    print(f"报告：{args.report.resolve()}")
    for row in report["cases"]:
        if not row["passed"]:
            print(f"[FAIL] {row['id']}: {row}")
    return 0 if summary["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
