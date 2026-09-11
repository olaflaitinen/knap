# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/bench_decode.mojo
# Purpose     : Decode throughput, reported as a footnote and never as a
#               headline.
# Stage       : Vectorisation and benchmarks. See docs/BENCHMARKS.md
# Depends on  : knap.tokenizer, harness.mojo
# Invariants  : This number is not a selling point and must not be presented
#               as one. See the docstring.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Decode throughput for Knap, as a footnote.

Decoding is a series of copies from a contiguous buffer. It is already
trivially fast in every implementation, including the ones this project
compares itself against, and a decode figure says nothing about whether a
tokenizer is good.

It is measured here so that docs/BENCHMARKS.md can state the number and then
state plainly that it is not a bottleneck in any real pipeline. Publishing it
as a headline would be the kind of benchmark presentation this project exists
to avoid: technically true, and chosen because it flatters.

    mojo run -I src -I bench bench/bench_decode.mojo
"""

from harness import (
    PROSE_OFFSET,
    Samples,
    now,
    read_corpus_slice,
    report_throughput,
)
from knap.tokenizer import load_cl100k_base_tokenizer

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime INPUT_MEGABYTES = 8
"""How much corpus to encode first, providing the ids to decode."""

comptime WARMUP_ITERATIONS = 2
"""Untimed iterations run before measurement."""

comptime MEASURED_ITERATIONS = 10
"""Timed iterations. Higher than the encode benchmark, since each is fast."""


def main() raises:
    """Measure decode throughput.

    Raises:
        Error: if the corpus or the vocabulary is missing.
    """
    var data = read_corpus_slice(
        String(CORPUS), PROSE_OFFSET, INPUT_MEGABYTES * 1024 * 1024
    )

    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var ids = tokenizer.encode_ordinary_bytes(Span(data))

    print("# corpus offset:", PROSE_OFFSET)
    print("# tokens to decode:", len(ids))
    print("# warmup iterations:", WARMUP_ITERATIONS)
    print("# measured iterations:", MEASURED_ITERATIONS)
    print("# note: decode is a footnote metric, not a headline")

    for _ in range(WARMUP_ITERATIONS):
        var ignored = tokenizer.decode_bytes(ids)

    var samples = Samples()
    var produced = 0
    for _ in range(MEASURED_ITERATIONS):
        var start = now()
        var bytes_out = tokenizer.decode_bytes(ids)
        samples.add(now() - start)
        produced = len(bytes_out)

    report_throughput(String("decode_cl100k_base"), produced, len(ids), samples)


# =============================================================================
# End of file: bench/bench_decode.mojo
# =============================================================================
