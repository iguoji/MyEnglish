from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Pair:
    word_id: int
    meaning_id: int
    definition: str
    order: int


def try_build_rounds(source: OrderedDict[str, list[Pair]], round_size: int):
    buckets = OrderedDict((key, list(values)) for key, values in source.items())
    rounds: list[list[Pair]] = []
    previous_words: set[int] = set()

    while any(buckets.values()):
        available = [
            (definition, bucket)
            for definition, bucket in buckets.items()
            if bucket
        ]
        available.sort(key=lambda item: (-len(item[1]), item[1][0].order))
        remaining_count = sum(len(bucket) for bucket in buckets.values())
        is_last_round = remaining_count <= round_size

        if not is_last_round and len(available) < round_size:
            return None
        if is_last_round and len(available) < remaining_count:
            return None

        current: list[Pair] = []
        current_words: set[int] = set()
        for _, bucket in available[:round_size]:
            index = next(
                (
                    index
                    for index, candidate in enumerate(bucket)
                    if candidate.word_id not in current_words
                    and candidate.word_id not in previous_words
                ),
                None,
            )
            if index is None:
                index = next(
                    (
                        index
                        for index, candidate in enumerate(bucket)
                        if candidate.word_id not in current_words
                    ),
                    None,
                )
            if index is None:
                index = 0

            picked = bucket.pop(index)
            current.append(picked)
            current_words.add(picked.word_id)

        expected = remaining_count if is_last_round else round_size
        if len(current) != expected:
            return None
        rounds.append(current)
        previous_words = current_words

    return rounds


def build_rounds(meaning_counts: list[int], shared_definition: bool = False):
    candidates: list[Pair] = []
    order = 0
    for word_id, meaning_count in enumerate(meaning_counts, start=1):
        for meaning_index in range(1, meaning_count + 1):
            definition = (
                f"M{meaning_index}" if shared_definition else f"D{word_id}.{meaning_index}"
            )
            candidates.append(
                Pair(word_id, word_id * 100 + meaning_index, definition, order)
            )
            order += 1

    if not candidates:
        return []

    buckets: OrderedDict[str, list[Pair]] = OrderedDict()
    for candidate in candidates:
        buckets.setdefault(candidate.definition, []).append(candidate)

    for round_size in range(5, 0, -1):
        rounds = try_build_rounds(buckets, round_size)
        if rounds is not None:
            return rounds
    return []


def format_rounds(rounds: list[list[Pair]]) -> str:
    if not rounds:
        return "无配对"
    return " | ".join(
        f"第{index}轮（{len(round)}对）："
        + "、".join(f"词{pair.word_id}/义{pair.meaning_id % 100}" for pair in round)
        for index, round in enumerate(rounds, start=1)
    )


def validate(rounds: list[list[Pair]], meaning_counts: list[int]) -> list[str]:
    errors: list[str] = []
    expected_total = sum(meaning_counts)
    actual = [pair for round in rounds for pair in round]
    if len(actual) != expected_total:
        errors.append(f"总配对数错误：应为 {expected_total}，实际 {len(actual)}")
    identities = {(pair.word_id, pair.meaning_id) for pair in actual}
    if len(identities) != len(actual):
        errors.append("存在重复的（单词、含义）配对")
    for index, round in enumerate(rounds, start=1):
        if not 1 <= len(round) <= 5:
            errors.append(f"第 {index} 轮行数越界：{len(round)}")
        definitions = [pair.definition for pair in round]
        if len(set(definitions)) != len(definitions):
            errors.append(f"第 {index} 轮出现重复释义")
    if rounds and any(len(round) != len(rounds[0]) for round in rounds[:-1]):
        errors.append("最后一轮之前的轮次行数不一致")
    return errors


def main() -> None:
    output = Path(__file__).with_name("meaning_match_pair_simulation.txt")
    lines: list[str] = []
    lines.append("词义连连配对模拟")
    lines.append("规则：每条含义各出现一次；同轮释义不重复；统一轮次尽量 5 行；尾轮不足按实际数量显示；不复制旧题。")
    lines.append("")
    lines.append("一、单词数量 × 每词含义数量（释义文本全部唯一）")
    lines.append("格式：W=单词数，M=每词含义数，后面是各轮配对数量和单词分布。")
    for word_count in range(1, 9):
        for meaning_count in range(1, 6):
            counts = [meaning_count] * word_count
            rounds = build_rounds(counts)
            sizes = ",".join(str(len(round)) for round in rounds)
            words = "/".join("".join(str(pair.word_id) for pair in round) for round in rounds)
            errors = validate(rounds, counts)
            suffix = f"；校验失败：{'；'.join(errors)}" if errors else "；校验通过"
            lines.append(
                f"W{word_count} M{meaning_count}，总{sum(counts)}对：轮次[{sizes}]，单词分布[{words}]{suffix}"
            )

    lines.append("")
    lines.append("二、不同单词含义量混合")
    mixed_cases = [
        [1],
        [2],
        [3],
        [1, 1],
        [2, 2],
        [3, 3],
        [1, 2, 3],
        [1, 2, 3, 4, 5],
        [1, 5, 1, 5],
        [2, 2, 2, 2, 2],
    ]
    for counts in mixed_cases:
        rounds = build_rounds(counts)
        errors = validate(rounds, counts)
        lines.append(
            f"含义量={counts}，总{sum(counts)}对：{format_rounds(rounds)}"
            + (f"；校验失败：{'；'.join(errors)}" if errors else "；校验通过")
        )

    lines.append("")
    lines.append("三、不同单词共享相同释义文本")
    shared_cases = [[2, 2], [2, 2, 2], [5, 5], [2, 5], [1, 2, 3]]
    for counts in shared_cases:
        rounds = build_rounds(counts, shared_definition=True)
        errors = validate(rounds, counts)
        lines.append(
            f"含义量={counts}，总{sum(counts)}对：{format_rounds(rounds)}"
            + (f"；校验失败：{'；'.join(errors)}" if errors else "；校验通过")
        )

    lines.append("")
    lines.append("四、结论")
    lines.append("1. 总配对数始终等于所有有效含义数量，不会因为单词数量少而漏掉多义词含义。")
    lines.append("2. 单词数少、含义数多时，同一单词在同一轮出现多次是必然的；这是为了保证每条含义都出现。")
    lines.append("3. 单词数和含义数都充足时，算法会尽量把不同单词分散到一轮内，并避开上一轮的单词。")
    lines.append("4. 如果不同单词共享完全相同的释义文本，算法会把它们安排到不同轮次；否则同一轮会出现重复释义。")
    lines.append("5. 行数统一规则优先于‘每轮尽量 5 行’：无法安全凑出 5 行时，会降到 4、3、2 或 1 行。")
    lines.append("")
    lines.append("说明：这是按当前 Dart ReviewFlow 算法等价实现的离线模拟，不会修改词库或数据库。")
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(output)
    print("模拟组合：40 组固定含义量 + 10 组混合含义量 + 5 组共享释义")


if __name__ == "__main__":
    main()
