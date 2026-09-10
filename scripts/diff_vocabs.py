# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/diff_vocabs.py
# Purpose     : Compares two vocabularies and characterises the difference,
#               so that a claim about how they relate can be checked.
# Stage       : Investigation tool. See docs/CORRECTNESS.md
# Depends on  : The fetched .tiktoken files. Standard library only.
# Invariants  : Reports what it found rather than what it expected. The
#               characterisation is derived from the tokens, not asserted.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Compare two vocabularies and say how they differ.

This repository makes several claims about how its seven encodings relate to
each other: that two of them share a merge table byte for byte, that another
extends a third by exactly twenty four tokens, and that those twenty four
are all runs of spaces. Every one of those started as an observation, and an
observation nobody can repeat is a memory.

So this is the tool that made them. Give it two encoding names and it reads
both vocabularies, reports what is in one and not the other, and
characterises the difference from the tokens themselves rather than from an
expectation:

    python scripts/diff_vocabs.py r50k_base p50k_base

It answers three questions. Are the shared tokens at the same ranks, which
is what makes two encodings interchangeable rather than merely similar. What
is in one and not the other. And is there a pattern in that, which is
usually the interesting part: twenty four extra tokens is a fact, twenty
four extra runs of two to twenty five spaces is an explanation.
"""

from __future__ import annotations

import base64
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VOCAB_DIR = REPO_ROOT / "tests" / "fixtures" / "vocabs"

# Which file each encoding is stored in. Seven names, four files.
VOCABULARY_FILE = {
    "cl100k_base": "cl100k_base.tiktoken",
    "o200k_base": "o200k_base.tiktoken",
    "o200k_harmony": "o200k_base.tiktoken",
    "gpt2": "r50k_base.tiktoken",
    "r50k_base": "r50k_base.tiktoken",
    "p50k_base": "p50k_base.tiktoken",
    "p50k_edit": "p50k_base.tiktoken",
}

SAMPLE_LIMIT = 30
"""Most differing tokens to print in full before summarising."""


def read_vocabulary(name: str) -> dict[bytes, int]:
    """Read one vocabulary as a map from token bytes to rank.

    Args:
        name: The encoding name.

    Returns:
        Every merge token and the rank it holds.

    Raises:
        SystemExit: if the name is unknown or the file is not fetched.
    """
    if name not in VOCABULARY_FILE:
        known = ", ".join(sorted(VOCABULARY_FILE))
        raise SystemExit(f"diff_vocabs: unknown encoding {name!r}. Try: {known}")

    path = VOCAB_DIR / VOCABULARY_FILE[name]
    if not path.is_file():
        raise SystemExit(
            f"diff_vocabs: {path.relative_to(REPO_ROOT)} is missing. Run "
            "'python scripts/fetch_vocabs.py' first."
        )

    ranks: dict[bytes, int] = {}
    with path.open("rb") as handle:
        for number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            fields = line.split()
            if len(fields) != 2:
                raise SystemExit(
                    f"diff_vocabs: {path.name} line {number} has "
                    f"{len(fields)} fields, expected 2"
                )
            ranks[base64.b64decode(fields[0])] = int(fields[1])
    return ranks


def describe(token: bytes) -> str:
    """Render one token so that whitespace is visible.

    Args:
        token: The token bytes.

    Returns:
        A printable description.

    Whitespace matters here more than anywhere else, because the difference
    between two of these vocabularies is entirely whitespace, and a token
    printed as itself would look like nothing at all.
    """
    try:
        text = token.decode("utf-8")
    except UnicodeDecodeError:
        return f"{token.hex()} (not valid UTF-8)"

    if text and all(character == " " for character in text):
        return f"{len(text)} spaces"
    if text.strip() == "" and text:
        return f"{len(text)} whitespace characters, {text.encode().hex()}"
    return repr(text)


def characterise(tokens: list[bytes]) -> list[str]:
    """Look for a pattern in a set of tokens.

    Args:
        tokens: The tokens that appear in one vocabulary and not the other.

    Returns:
        Lines describing whatever pattern holds for all of them, empty when
        none does.

    Only patterns that hold for every token are reported. A pattern that
    holds for most of them is the kind of thing that becomes a sentence in a
    document and then turns out to be false.
    """
    if not tokens:
        return []

    lines: list[str] = []
    lengths = sorted(len(token) for token in tokens)
    lines.append(
        f"  lengths run from {lengths[0]} to {lengths[-1]} bytes"
    )

    decoded: list[str] = []
    for token in tokens:
        try:
            decoded.append(token.decode("utf-8"))
        except UnicodeDecodeError:
            decoded = []
            break

    if not decoded:
        lines.append("  at least one is not valid UTF-8 on its own")
        return lines

    if all(text and all(character == " " for character in text) for text in decoded):
        counts = sorted(len(text) for text in decoded)
        lines.append(
            f"  every one is a run of spaces, from {counts[0]} to "
            f"{counts[-1]}"
        )
        missing = [
            length
            for length in range(counts[0], counts[-1] + 1)
            if length not in set(counts)
        ]
        if missing:
            lines.append(f"  lengths not present: {missing}")
        else:
            lines.append("  every length in that range is present")
    elif all(text.strip() == "" for text in decoded):
        lines.append("  every one is whitespace")
    elif all(text.isdigit() for text in decoded):
        lines.append("  every one is digits")
    elif all(text.startswith(" ") for text in decoded):
        lines.append("  every one begins with a space")

    return lines


def main() -> int:
    """Compare two vocabularies and print what separates them."""
    if len(sys.argv) != 3:
        known = ", ".join(sorted(VOCABULARY_FILE))
        print(f"usage: diff_vocabs.py <encoding> <encoding>")
        print(f"encodings: {known}")
        return 2

    left_name, right_name = sys.argv[1], sys.argv[2]
    left = read_vocabulary(left_name)
    right = read_vocabulary(right_name)

    print(f"diff_vocabs: {left_name} against {right_name}")
    print(f"  {left_name}: {len(left)} merge tokens")
    print(f"  {right_name}: {len(right)} merge tokens")

    if left == right:
        print("  the two tables are identical, token for token and rank for rank")
        return 0

    shared = set(left) & set(right)
    moved = [token for token in shared if left[token] != right[token]]
    only_left = sorted(set(left) - set(right), key=lambda token: left[token])
    only_right = sorted(set(right) - set(left), key=lambda token: right[token])

    print(f"  shared tokens: {len(shared)}")
    if moved:
        print(f"  shared tokens at different ranks: {len(moved)}")
        for token in sorted(moved, key=lambda t: left[t])[:SAMPLE_LIMIT]:
            print(
                f"    {describe(token)}: rank {left[token]} against "
                f"{right[token]}"
            )
    else:
        print("  every shared token holds the same rank in both")

    for name, other, only in (
        (left_name, right_name, only_left),
        (right_name, left_name, only_right),
    ):
        if not only:
            print(f"  nothing is in {name} alone")
            continue
        print(f"  in {name} and not in {other}: {len(only)}")
        for line in characterise(only):
            print(line)
        for token in only[:SAMPLE_LIMIT]:
            print(f"    rank {left.get(token, right.get(token))}: {describe(token)}")
        if len(only) > SAMPLE_LIMIT:
            print(f"    and {len(only) - SAMPLE_LIMIT} more")

    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/diff_vocabs.py
# =============================================================================
