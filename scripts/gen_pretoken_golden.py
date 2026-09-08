# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/gen_pretoken_golden.py
# Purpose     : Produces reference piece boundaries from the Python regex
#               module for both patterns.
# Stage       : Milestone M2, pre-tokenizer. See docs/ROADMAP.md
# Depends on  : regex and tiktoken, as the reference implementations.
# Invariants  : Boundaries are byte offsets into UTF-8, not character
#               offsets. The reference regex works on decoded text, so every
#               span is converted before being written.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Generate reference pre-tokenization boundaries.

Two outputs, because the two consumers have opposite needs.

The small fixtures under tests/fixtures/corpus get a JSON Lines file each.
Those are read by people as often as by tests, so they hold the piece text
alongside its offsets and stay legible.

The large corpus gets a compact binary instead. At roughly four bytes per
piece, a hundred megabytes of text produces tens of millions of pieces, and
writing those as JSON Lines would cost around half a gigabyte per pattern to
express what fits in a few tens of megabytes. Piece lengths are written as
single bytes, with a zero byte introducing a four byte length for the rare
piece longer than 255 bytes. A length of zero is otherwise impossible,
because every alternative consumes at least one character, which is what
makes zero safe to use as the escape.

    python scripts/gen_pretoken_golden.py

Exit status is 0 when every requested output was written.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "corpus"
GOLDEN_ROOT = REPO_ROOT / "tests" / "golden"
CORPUS = REPO_ROOT / "bench" / "corpus" / "mixed.txt"

ENCODINGS = ("cl100k_base", "o200k_base")

ESCAPE = 0
MAX_INLINE_LENGTH = 255


def compiled_patterns() -> dict:
    """Compile the reference pattern for each target encoding.

    Returns:
        A mapping from encoding name to compiled pattern.

    Raises:
        SystemExit: if either dependency is missing.

    The patterns come from tiktoken rather than from the generated Mojo
    constant, so that this reference is independent of anything Knap
    generated. Comparing Knap against a file Knap produced would prove
    nothing.
    """
    try:
        import regex
        import tiktoken
    except ImportError as exc:
        raise SystemExit(
            "gen_pretoken_golden: regex and tiktoken are required. Run "
            "'uv sync --group dev' first."
        ) from exc

    return {
        name: regex.compile(tiktoken.get_encoding(name)._pat_str)
        for name in ENCODINGS
    }


def byte_lengths(text: str, pattern) -> list[int]:
    """Return the byte length of every piece the reference produces.

    Args:
        text: The decoded text to pre-tokenize.
        pattern: A compiled reference pattern.

    Returns:
        Piece lengths in bytes, in order.

    Lengths rather than offsets, because lengths are small and compress into
    a single byte for almost every piece. Offsets grow with the corpus and
    would need four bytes each throughout.
    """
    lengths: list[int] = []
    for match in pattern.finditer(text):
        lengths.append(len(match.group().encode("utf-8")))
    return lengths


def encode_lengths(lengths: list[int]) -> bytes:
    """Pack piece lengths into the compact binary form.

    Args:
        lengths: Piece lengths in bytes.

    Returns:
        The packed bytes.

    Raises:
        ValueError: on a length of zero, which no alternative can produce
            and which the escape marker reserves.
    """
    out = bytearray()
    for length in lengths:
        if length <= 0:
            raise ValueError("a piece of zero length is not possible")
        if length <= MAX_INLINE_LENGTH:
            out.append(length)
        else:
            out.append(ESCAPE)
            out.extend(struct.pack("<I", length))
    return bytes(out)


def write_fixture_goldens(patterns: dict) -> int:
    """Write a readable JSON Lines golden for each small fixture.

    Args:
        patterns: Compiled reference patterns by encoding name.

    Returns:
        How many fixture files were processed.
    """
    if not FIXTURE_DIR.is_dir():
        return 0

    fixtures = sorted(
        path
        for path in FIXTURE_DIR.iterdir()
        if path.is_file() and path.suffix in (".txt",)
    )
    if not fixtures:
        return 0

    for name, pattern in patterns.items():
        destination = GOLDEN_ROOT / name / "pretoken_boundaries.jsonl"
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("w", encoding="utf-8", newline="\n") as handle:
            for fixture in fixtures:
                # Read bytes and decode explicitly. read_text applies
                # universal newline translation, which silently turns
                # a carriage return line feed pair into a single line
                # feed and would make the reference disagree with the
                # bytes on disk.
                text = fixture.read_bytes().decode("utf-8")
                offset = 0
                for match in pattern.finditer(text):
                    piece = match.group().encode("utf-8")
                    handle.write(
                        json.dumps(
                            {
                                "file": fixture.name,
                                "start": offset,
                                "length": len(piece),
                                "piece": match.group(),
                            },
                            ensure_ascii=True,
                            separators=(",", ":"),
                        )
                        + "\n"
                    )
                    offset += len(piece)
        print(
            f"  {name}: fixture boundaries -> "
            f"{destination.relative_to(REPO_ROOT)}"
        )
    return len(fixtures)


def write_corpus_goldens(patterns: dict) -> bool:
    """Write the compact binary golden for the large corpus.

    Args:
        patterns: Compiled reference patterns by encoding name.

    Returns:
        True when the corpus was present and processed.
    """
    if not CORPUS.is_file():
        print(
            "  corpus: bench/corpus/mixed.txt is absent, skipping the large "
            "goldens. Run 'python scripts/fetch_corpus.py' first."
        )
        return False

    # Bytes then an explicit decode, never read_text: universal newline
    # translation would rewrite every carriage return line feed pair in
    # the corpus before the reference pattern ever saw it.
    text = CORPUS.read_bytes().decode("utf-8")
    encoded_size = len(text.encode("utf-8"))
    print(f"  corpus: {encoded_size / (1 << 20):.1f} MB of text")

    summary = {}
    for name, pattern in patterns.items():
        lengths = byte_lengths(text, pattern)
        packed = encode_lengths(lengths)
        destination = CORPUS.parent / f"{name}_lengths.bin"
        destination.write_bytes(packed)
        total = sum(lengths)
        if total != encoded_size:
            raise SystemExit(
                f"gen_pretoken_golden: {name} pieces total {total} bytes but "
                f"the corpus is {encoded_size}. The pieces must tile the "
                "input exactly."
            )
        summary[name] = {"pieces": len(lengths), "packed_bytes": len(packed)}
        print(
            f"  {name}: {len(lengths)} pieces, "
            f"{len(packed) / (1 << 20):.1f} MB packed -> "
            f"{destination.relative_to(REPO_ROOT)}"
        )

    manifest = CORPUS.parent / "boundaries_manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "generated": datetime.now(timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
                "corpus_bytes": encoded_size,
                "encodings": summary,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return True


def main() -> int:
    """Generate every reference boundary file that has an input."""
    parser = argparse.ArgumentParser(
        description="Generate reference pre-tokenization boundaries."
    )
    parser.parse_args()

    patterns = compiled_patterns()
    print("gen_pretoken_golden: generating reference boundaries")

    fixtures = write_fixture_goldens(patterns)
    if fixtures:
        print(f"  fixtures: {fixtures} files")
    else:
        print("  fixtures: none present, skipping")

    write_corpus_goldens(patterns)
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/gen_pretoken_golden.py
# =============================================================================
