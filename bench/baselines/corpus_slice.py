# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/baselines/corpus_slice.py
# Purpose     : Gives the baselines the same corpus slice the Mojo side uses.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/ROADMAP.md
# Depends on  : Nothing outside the standard library.
# Invariants  : Byte for byte identical to read_corpus_slice in
#               bench/harness.mojo. A baseline reading different text is not
#               a baseline.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Read the benchmark corpus the same way the Mojo benchmarks do.

A baseline comparison is only a comparison if both sides see the same bytes.
This module exists so that the slicing rule lives in one place per language
rather than in five copies, and so that a change to it cannot silently apply
to one side only.

The rule, which mirrors `read_corpus_slice` in `bench/harness.mojo`:

  1. Start at `PROSE_OFFSET`.
  2. Advance to the first byte after the next line feed.
  3. Take at most `limit` bytes.
  4. Trim back so the slice ends on a line feed.

Why an offset at all: the mixed corpus begins with a large generated hazard
section, and a prefix of the file is that section rather than natural
language. Its first two megabytes hold 205 distinct whitespace separated
words. Throughput measured there is a measurement of repetition, not of
text.

Why whole lines: a slice cut mid character is not valid UTF-8, and every
reference implementation here takes text rather than bytes, so it could not
be handed the same input at all.
"""

from __future__ import annotations

from pathlib import Path

PROSE_OFFSET = 30408704
"""Byte offset where the corpus stops being generated hazard text.

Must equal PROSE_OFFSET in bench/harness.mojo. The two are checked against
each other by bench/run_all.sh, which refuses to run if they differ.
"""


def read_corpus_slice(path: Path, offset: int, limit: int) -> bytes:
    """Read a whole-line slice of the corpus.

    Args:
        path: The corpus file.
        offset: Byte offset to start near.
        limit: How many bytes to keep, before trimming to a line boundary.

    Returns:
        The slice, beginning just after a line feed and ending on one.

    Raises:
        SystemExit: if the corpus is missing, or holds no line feed after
            the offset, which would mean it is not the file this expects.
    """
    if not path.is_file():
        raise SystemExit(
            f"corpus_slice: {path} is missing. Run "
            "'python scripts/fetch_corpus.py' first."
        )

    data = path.read_bytes()

    start = offset if offset < len(data) else 0
    newline = data.find(b"\n", start)
    if newline < 0:
        raise SystemExit(
            f"corpus_slice: no line boundary after offset {offset}"
        )
    start = newline + 1

    end = min(start + limit, len(data))
    last = data.rfind(b"\n", start, end)
    if last > start:
        end = last + 1

    return data[start:end]


# =============================================================================
# End of file: bench/baselines/corpus_slice.py
# =============================================================================
