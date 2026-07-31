#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""独立审计日常英语语料，不复用生成器或 Hy3 分析器的判断。

这个程序回答四类可以客观验证的问题：

1. 数据是否满足约定的 2000 条、20 类、字段类型等结构要求；
2. 句子是否重复，是否含占位符、坏标点、坏缩写等明显机械问题；
3. 来源 URL 是否自洽、可解析，以及是否缺少许可登记；
4. 语料中出现了哪些语言现象，帮助判断它能覆盖哪些开发场景。

程序刻意不做“任意英语句子的通用语法裁判”。没有人工 gold 标注或成熟
语言学模型时，把自然口语直接判成正确/错误会制造大量误报。这里把不确定
项目归为 warning/info，并保留原句供人工复核。
"""

from __future__ import annotations

import argparse
import collections
import concurrent.futures
import datetime as dt
import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


SENTENCE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CORPUS = SENTENCE_ROOT / "corpus" / "daily_english_2000.json"
DEFAULT_REPORT = SENTENCE_ROOT / "reports" / "codex_corpus_audit.json"
DEFAULT_SOURCE_REGISTRY = SENTENCE_ROOT / "corpus" / "sources.json"

EXPECTED_CATEGORIES = {
    "greetings",
    "introductions",
    "daily_routine",
    "food_dining",
    "shopping",
    "transportation",
    "weather",
    "health",
    "family",
    "work_study",
    "hobbies",
    "emotions",
    "requests_help",
    "phone_messages",
    "directions",
    "time_schedule",
    "home_housework",
    "travel",
    "money_payment",
    "small_talk",
}

REQUIRED_FIELDS = {
    "sentence": str,
    "category": str,
    "source_id": str,
    "source_url": (str, type(None)),
    "register": str,
    "collected_at": (int, type(None)),
    "notes": str,
}

ALLOWED_REGISTERS = {"neutral", "informal", "formal"}
SOURCE_ID_RE = re.compile(r"^[a-z][a-z0-9_-]*$")
TOKEN_RE = re.compile(r"[A-Za-z]+(?:['\u2019][A-Za-z]+)?|\d+(?:[.:/-]\d+)*")
PLACEHOLDER_RE = re.compile(
    r"(?:\[(?:name|xxx|placeholder|insert|your\s+\w+)[^]]*\]"
    r"|\{[^{}]+\}|<(?:name|placeholder|insert)[^>]*>|\bX{3,}\b)",
    re.IGNORECASE,
)
MALFORMED_NT_RE = re.compile(
    r"\b(?:is|are|was|were|do|does|did|has|have|had|can|could|would|should|"
    r"will|must|need|might)'nt\b",
    re.IGNORECASE,
)
REPEATED_WORD_RE = re.compile(r"\b([A-Za-z]+)\s+\1\b", re.IGNORECASE)


def read_json(path: Path) -> Any:
    """像 PHP 的 json_decode 一样读取 JSON，并把解析错误变成清晰异常。"""

    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    """统一写出 UTF-8 报告，保留中文并固定缩进，方便 Git 审阅。"""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def normalize_text(text: str, *, ignore_punctuation: bool = False) -> str:
    """把视觉上等价的句子折叠到同一个比较键，用于可靠去重。"""

    value = unicodedata.normalize("NFKC", text).replace("\u2019", "'")
    value = re.sub(r"\s+", " ", value.strip()).lower()
    if ignore_punctuation:
        value = re.sub(r"[^a-z0-9']+", " ", value)
        value = re.sub(r"\s+", " ", value).strip()
    return value


def make_finding(
    severity: str,
    code: str,
    detail: str,
    *,
    index: Optional[int] = None,
    sentence: Optional[str] = None,
) -> Dict[str, Any]:
    """所有问题共用同一结构，后续 Flutter 或 CI 都容易消费。"""

    finding: Dict[str, Any] = {
        "severity": severity,
        "code": code,
        "detail": detail,
    }
    if index is not None:
        finding["index"] = index
    if sentence is not None:
        finding["sentence"] = sentence
    return finding


def terminal_character(text: str) -> str:
    """忽略右引号或右括号后，取得真正的句末字符。"""

    return text.rstrip().rstrip('"\'\u201d\u2019)]}').rstrip()[-1:] or ""


def audit_surface(index: int, sentence: str) -> List[Dict[str, Any]]:
    """检查无需理解完整句法也能可靠发现的表层机械问题。"""

    findings: List[Dict[str, Any]] = []

    def add(severity: str, code: str, detail: str) -> None:
        findings.append(
            make_finding(severity, code, detail, index=index, sentence=sentence)
        )

    if sentence != sentence.strip():
        add("warning", "outer_whitespace", "句子首尾含多余空白")
    if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", sentence):
        add("error", "control_character", "句子含不可见控制字符")
    if PLACEHOLDER_RE.search(sentence):
        add("error", "placeholder", "句子仍含模板占位符")
    if terminal_character(sentence) not in {".", "?", "!"}:
        add("warning", "missing_terminal_punctuation", "句末缺少 . ? !")
    if re.search(r"\s+[,.!?;:]", sentence):
        add("warning", "space_before_punctuation", "标点前存在多余空格")
    if re.search(r"[,;:](?=[A-Za-z])", sentence):
        add("warning", "missing_space_after_punctuation", "逗号、分号或冒号后缺少空格")
    if MALFORMED_NT_RE.search(sentence):
        add("error", "malformed_negative_contraction", "否定缩写应写成 isn't / don't 等形式")
    if sentence.count("(") != sentence.count(")"):
        add("warning", "unbalanced_parentheses", "圆括号数量不配对")
    if sentence.count("[") != sentence.count("]"):
        add("warning", "unbalanced_brackets", "方括号数量不配对")
    if sentence.count('"') % 2:
        add("warning", "unbalanced_double_quotes", "英文双引号数量不配对")

    repeated = REPEATED_WORD_RE.search(sentence)
    # “had had”与“that that”可能合法，所以这里只提示人工看，不直接判错。
    if repeated:
        add("info", "repeated_adjacent_word", f"相邻单词重复：{repeated.group(0)!r}")

    token_count = len(TOKEN_RE.findall(sentence))
    if token_count == 0:
        add("error", "no_english_tokens", "没有识别到英文单词或数字")
    elif token_count > 40:
        add("info", "long_sentence", f"句子含 {token_count} 个词，超出基础简单句范围")

    return findings


def detect_feature_signals(sentence: str) -> Iterable[str]:
    """只统计“可能出现”的句法信号，不把启发式结果冒充精确句法分析。"""

    lower = normalize_text(sentence)
    tokens = [token.lower().replace("\u2019", "'") for token in TOKEN_RE.findall(sentence)]
    token_set = set(tokens)

    if "'" in lower:
        yield "contraction"
    if terminal_character(sentence) == "?":
        yield "question"
    if terminal_character(sentence) == "!":
        yield "exclamation"
    if tokens and tokens[0] in {"what", "who", "whose", "which", "when", "where", "why", "how"}:
        yield "wh_opening"
    if token_set & {"can", "could", "may", "might", "must", "shall", "should", "will", "would"}:
        yield "modal"
    if token_set & {"and", "but", "or", "so", "yet"}:
        yield "coordination"
    if token_set & {"because", "although", "though", "unless", "while", "whether", "if"}:
        yield "subordination_signal"
    if token_set & {"who", "whom", "whose", "which", "that"}:
        yield "relative_or_content_clause_signal"
    if token_set & {"have", "has", "had", "i've", "we've", "they've", "he's", "she's"} and any(
        token.endswith(("ed", "en")) for token in tokens
    ):
        yield "perfect_candidate"
    if token_set & {"am", "is", "are", "was", "were", "be", "been", "being"} and any(
        token.endswith("ing") for token in tokens
    ):
        yield "continuous_candidate"
    if token_set & {"am", "is", "are", "was", "were", "be", "been", "being"} and any(
        token.endswith(("ed", "en")) for token in tokens
    ):
        yield "passive_candidate"
    if any(char.isdigit() for char in sentence):
        yield "contains_number"
    if len(tokens) <= 4:
        yield "short_utterance_or_fragment"
    if sentence.count(".") + sentence.count("?") + sentence.count("!") > 1:
        yield "multiple_utterances"


def validate_url(url: Any) -> Optional[str]:
    """只验证 URL 形状；网页当前能否访问由可选的联网检查负责。"""

    if not isinstance(url, str) or not url.strip():
        return "来源 URL 为空"
    if any(marker in url for marker in ("...", "[", "]", "{", "}")):
        return "来源 URL 含省略号或占位符，不是完整地址"
    if re.search(r"\s", url):
        return "来源 URL 含空白"
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return "来源 URL 不是完整的 http/https 地址"
    return None


def check_one_url(url: str, timeout: float) -> Dict[str, Any]:
    """联网探测一个来源；403 代表网站拒绝机器人，不代表页面不存在。"""

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 corpus-source-audit/1.0"},
        method="GET",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {
                "url": url,
                "status": int(response.status),
                "final_url": response.geturl(),
                "elapsed_ms": round((time.monotonic() - started) * 1000),
            }
    except urllib.error.HTTPError as exc:
        return {
            "url": url,
            "status": int(exc.code),
            "error": f"HTTP {exc.code}",
            "elapsed_ms": round((time.monotonic() - started) * 1000),
        }
    except Exception as exc:  # 网络失败类型很多，统一记录但不让整批中断。
        return {
            "url": url,
            "status": None,
            "error": f"{type(exc).__name__}: {exc}",
            "elapsed_ms": round((time.monotonic() - started) * 1000),
        }


def check_urls(urls: Sequence[str], timeout: float, workers: int) -> List[Dict[str, Any]]:
    """并行检查独立 URL，避免几十个来源串行等待。"""

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        rows = list(executor.map(lambda url: check_one_url(url, timeout), urls))
    return sorted(rows, key=lambda row: row["url"])


def audit_corpus(
    corpus_path: Path,
    *,
    source_registry_path: Path,
    network: bool,
    timeout: float,
    workers: int,
) -> Dict[str, Any]:
    """执行完整审计，并返回可直接写成 JSON 的报告对象。"""

    findings: List[Dict[str, Any]] = []
    data = read_json(corpus_path)
    if not isinstance(data, list):
        raise ValueError("语料根节点必须是 JSON 数组")

    category_counts: collections.Counter[str] = collections.Counter()
    register_counts: collections.Counter[str] = collections.Counter()
    source_counts: collections.Counter[str] = collections.Counter()
    domain_counts: collections.Counter[str] = collections.Counter()
    feature_counts: collections.Counter[str] = collections.Counter()
    category_sources: Dict[str, set] = collections.defaultdict(set)
    source_urls: Dict[str, set] = collections.defaultdict(set)
    exact_seen: Dict[str, int] = {}
    loose_seen: Dict[str, int] = {}
    valid_urls: set = set()
    timestamps: List[int] = []
    empty_notes = 0

    if len(data) != 2000:
        findings.append(make_finding("error", "wrong_total", f"应为 2000 条，实际为 {len(data)} 条"))

    for index, row in enumerate(data):
        if not isinstance(row, dict):
            findings.append(make_finding("error", "row_not_object", "记录不是 JSON 对象", index=index))
            continue

        missing = sorted(set(REQUIRED_FIELDS) - set(row))
        extra = sorted(set(row) - set(REQUIRED_FIELDS))
        if missing:
            findings.append(make_finding("error", "missing_fields", f"缺少字段：{missing}", index=index))
        if extra:
            findings.append(make_finding("warning", "unexpected_fields", f"存在未约定字段：{extra}", index=index))

        for field, expected_type in REQUIRED_FIELDS.items():
            if field in row and not isinstance(row[field], expected_type):
                findings.append(
                    make_finding(
                        "error",
                        "wrong_field_type",
                        f"字段 {field} 类型错误：{type(row[field]).__name__}",
                        index=index,
                    )
                )

        sentence = row.get("sentence")
        if not isinstance(sentence, str) or not sentence.strip():
            findings.append(make_finding("error", "empty_sentence", "sentence 为空", index=index))
            continue

        findings.extend(audit_surface(index, sentence))
        feature_counts.update(detect_feature_signals(sentence))

        exact_key = normalize_text(sentence)
        loose_key = normalize_text(sentence, ignore_punctuation=True)
        if exact_key in exact_seen:
            findings.append(
                make_finding(
                    "error",
                    "duplicate_sentence",
                    f"与第 {exact_seen[exact_key]} 条归一化后完全重复",
                    index=index,
                    sentence=sentence,
                )
            )
        else:
            exact_seen[exact_key] = index
        previous_loose = loose_seen.get(loose_key)
        if previous_loose is not None and normalize_text(data[previous_loose]["sentence"]) != exact_key:
            findings.append(
                make_finding(
                    "warning",
                    "punctuation_only_duplicate",
                    f"与第 {previous_loose} 条仅大小写或标点不同",
                    index=index,
                    sentence=sentence,
                )
            )
        else:
            loose_seen[loose_key] = index

        category = row.get("category")
        if isinstance(category, str):
            category_counts[category] += 1
            if category not in EXPECTED_CATEGORIES:
                findings.append(make_finding("error", "unknown_category", f"未知类别：{category}", index=index))

        register = row.get("register")
        if isinstance(register, str):
            register_counts[register] += 1
            if register not in ALLOWED_REGISTERS:
                findings.append(make_finding("error", "unknown_register", f"未知语体：{register}", index=index))

        source_id = row.get("source_id")
        source_url = row.get("source_url")
        if isinstance(source_id, str):
            source_counts[source_id] += 1
            if not SOURCE_ID_RE.fullmatch(source_id):
                findings.append(make_finding("error", "invalid_source_id", f"非法 source_id：{source_id}", index=index))
            if isinstance(category, str):
                category_sources[category].add(source_id)
            if isinstance(source_url, str):
                source_urls[source_id].add(source_url)

        url_problem = validate_url(source_url)
        if url_problem:
            findings.append(
                make_finding("error", "invalid_source_url", url_problem, index=index, sentence=sentence)
            )
        elif isinstance(source_url, str):
            valid_urls.add(source_url)
            domain_counts[urllib.parse.urlparse(source_url).netloc.lower()] += 1

        collected_at = row.get("collected_at")
        if isinstance(collected_at, int):
            timestamps.append(collected_at)
            if collected_at < 0:
                findings.append(make_finding("error", "negative_timestamp", "collected_at 不能为负数", index=index))
            if collected_at > int(time.time()) + 86400:
                findings.append(make_finding("warning", "future_timestamp", "collected_at 比当前时间晚超过一天", index=index))

        if row.get("notes") == "":
            empty_notes += 1

    for category in sorted(EXPECTED_CATEGORIES):
        count = category_counts.get(category, 0)
        if count != 100:
            findings.append(make_finding("error", "wrong_category_size", f"类别 {category} 应为 100 条，实际 {count} 条"))
        source_total = len(category_sources.get(category, set()))
        if source_total < 3:
            findings.append(make_finding("error", "insufficient_category_sources", f"类别 {category} 只有 {source_total} 个来源"))

    for source_id, urls in sorted(source_urls.items()):
        if len(urls) > 1:
            findings.append(
                make_finding("warning", "source_id_multiple_urls", f"source_id {source_id} 对应 {len(urls)} 个 URL")
            )

    if not source_registry_path.exists():
        findings.append(
            make_finding(
                "error",
                "missing_source_registry",
                "缺少 corpus/sources.json，无法登记来源标题、发布者、许可和复核状态",
            )
        )
    if len(register_counts) == 1 and register_counts.get("neutral") == len(data):
        findings.append(
            make_finding("warning", "uniform_register", "全部句子均标为 neutral，语体字段明显尚未逐句标注")
        )
    if empty_notes == len(data):
        findings.append(make_finding("info", "all_notes_empty", "全部 notes 为空，尚无人工复核留痕"))
    if timestamps and len(set(timestamps)) == 1:
        findings.append(
            make_finding("info", "single_collection_timestamp", "全部记录使用同一个导出时间，不能证明逐页采集时间")
        )

    network_rows: List[Dict[str, Any]] = []
    if network:
        network_rows = check_urls(sorted(valid_urls), timeout, workers)
        for row in network_rows:
            status = row.get("status")
            if status is None or status >= 400:
                findings.append(
                    make_finding(
                        "warning",
                        "source_not_reachable_now",
                        f"来源当前探测失败：{row['url']} ({row.get('error', status)})",
                    )
                )

    severity_counts = collections.Counter(finding["severity"] for finding in findings)
    code_counts = collections.Counter(finding["code"] for finding in findings)
    generated_at = dt.datetime.now(dt.timezone.utc).isoformat()

    return {
        "meta": {
            "auditor": "codex_corpus_audit.py",
            "independent_from": ["analyzer.py", "mini_generator.check_grammar", "evaluate_corpus.py"],
            "generated_at": generated_at,
            "corpus": str(corpus_path),
            "network_check_enabled": network,
            "scope": "结构、来源、重复、机械文本质量与覆盖信号；不宣称通用英语语法判定",
        },
        "summary": {
            "records": len(data),
            "categories": len(category_counts),
            "sources": len(source_counts),
            "source_urls": len(valid_urls),
            "domains": len(domain_counts),
            "severity_counts": dict(sorted(severity_counts.items())),
            "result": "FAIL" if severity_counts["error"] else "PASS_WITH_WARNINGS" if severity_counts["warning"] else "PASS",
        },
        "distributions": {
            "categories": dict(sorted(category_counts.items())),
            "registers": dict(sorted(register_counts.items())),
            "sources": dict(source_counts.most_common()),
            "domains": dict(domain_counts.most_common()),
            "feature_signals": dict(feature_counts.most_common()),
        },
        "finding_code_counts": dict(code_counts.most_common()),
        "findings": findings,
        "network_sources": network_rows,
    }


def run_selftest() -> int:
    """用小样本证明审计器能发现整类问题，而非只记住项目中的某一句。"""

    cases: List[Tuple[str, str]] = [
        ("Is'nt this ready?", "malformed_negative_contraction"),
        ("Are'nt they ready?", "malformed_negative_contraction"),
        ("Hello , world!", "space_before_punctuation"),
        ("My name is [Name].", "placeholder"),
        ("This sentence has no ending", "missing_terminal_punctuation"),
        ("This has (an opening.", "unbalanced_parentheses"),
    ]
    failed = 0
    for index, (sentence, expected) in enumerate(cases):
        codes = {finding["code"] for finding in audit_surface(index, sentence)}
        ok = expected in codes
        print(f"[{'PASS' if ok else 'FAIL'}] {sentence!r} -> {expected}")
        failed += 0 if ok else 1

    clean_cases = ["How are you?", "I'd like a coffee.", "Two coffees, please."]
    forbidden_errors = {"malformed_negative_contraction", "placeholder", "control_character"}
    for index, sentence in enumerate(clean_cases, start=len(cases)):
        codes = {finding["code"] for finding in audit_surface(index, sentence)}
        ok = not (codes & forbidden_errors)
        print(f"[{'PASS' if ok else 'FAIL'}] clean {sentence!r}")
        failed += 0 if ok else 1

    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    """集中声明命令行参数，避免路径和网络行为藏在代码里。"""

    parser = argparse.ArgumentParser(description="独立审计 2000 条日常英语语料")
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS, help="待审计 JSON 文件")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT, help="审计报告输出位置")
    parser.add_argument("--sources", type=Path, default=DEFAULT_SOURCE_REGISTRY, help="来源登记文件")
    parser.add_argument("--check-urls", action="store_true", help="联网探测每个来源 URL")
    parser.add_argument("--timeout", type=float, default=8.0, help="单个 URL 超时秒数")
    parser.add_argument("--workers", type=int, default=8, help="URL 并发数")
    parser.add_argument("--strict", action="store_true", help="warning 也返回非零退出码")
    parser.add_argument("--selftest", action="store_true", help="运行审计器自身测试")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    """命令行入口：审计、写报告、打印摘要，并用退出码服务 CI。"""

    args = build_parser().parse_args(argv)
    if args.selftest:
        return run_selftest()
    if args.timeout <= 0 or args.workers <= 0:
        print("[FAIL] timeout 和 workers 必须大于 0", file=sys.stderr)
        return 2

    try:
        report = audit_corpus(
            args.corpus.resolve(),
            source_registry_path=args.sources.resolve(),
            network=args.check_urls,
            timeout=args.timeout,
            workers=args.workers,
        )
        write_json(args.report.resolve(), report)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[FAIL] 无法完成审计：{exc}", file=sys.stderr)
        return 2

    summary = report["summary"]
    counts = summary["severity_counts"]
    print(
        f"语料 {summary['records']} 条，{summary['categories']} 类，"
        f"{summary['sources']} 个 source_id，{summary['domains']} 个域名"
    )
    print(
        f"结果 {summary['result']}：error={counts.get('error', 0)}，"
        f"warning={counts.get('warning', 0)}，info={counts.get('info', 0)}"
    )
    print(f"报告：{args.report.resolve()}")

    if counts.get("error", 0):
        return 1
    if args.strict and counts.get("warning", 0):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
