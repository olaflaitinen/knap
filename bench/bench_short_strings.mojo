# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/bench_short_strings.mojo
# Purpose     : Short string encode latency, reported as percentiles.
# Stage       : Vectorisation and benchmarks. See docs/BENCHMARKS.md
# Depends on  : knap.tokenizer, harness.mojo
# Invariants  : Every sample times one encode of one string, so a percentile
#               describes a single call rather than an amortised batch.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Short string encode latency for Knap.

Throughput on a large document is the wrong measurement for serving, where
the tokenizer is handed one short prompt at a time and the number that
matters is how long that single call takes, including its tail.

So this times individual encodes of strings in the ten to two hundred token
range and reports percentiles rather than a mean. A mean latency averages
away exactly the behaviour anyone would care about.

The inputs are cut from the real corpus rather than generated, because
synthetic strings have unrealistic piece length distributions and the merge
loop's cost depends on piece length.

    mojo run -I src -I bench bench/bench_short_strings.mojo
"""

from harness import (
    PROSE_OFFSET,
    Samples,
    now,
    read_corpus_slice,
    report_latency,
)
from knap.tokenizer import Tokenizer, load_cl100k_base_tokenizer

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime SAMPLE_COUNT = 2000
"""Strings measured per size class. Enough for a stable ninety ninth."""

comptime WARMUP_SAMPLES = 200
"""Untimed encodes run first, to warm caches and branch predictors."""


def slice_at(data: List[UInt8], start: Int, length: Int) -> List[UInt8]:
    """Copy a byte range out of the corpus.

    Args:
        data: The corpus bytes.
        start: Where to begin.
        length: How many bytes to take.

    Returns:
        The slice, clipped to the available input.

    Copied rather than borrowed so that each timed call receives its own
    buffer, which keeps one sample from warming the next through a shared
    cache line.
    """
    var out = List[UInt8]()
    var index = start
    var taken = 0
    while index < len(data) and taken < length:
        out.append(data[index])
        index += 1
        taken += 1
    return out^


def measure(
    tokenizer: Tokenizer, data: List[UInt8], byte_length: Int, name: String
) raises:
    """Time many single encodes of one size class.

    Args:
        tokenizer: The tokenizer under test.
        data: The corpus to cut strings from.
        byte_length: Approximate input size for this class.
        name: Benchmark name.

    Raises:
        Error: if there are no samples.

    Strings are taken from evenly spaced offsets so the class covers varied
    content rather than one region of the corpus. Offsets are not aligned to
    any boundary, which is realistic: a prompt does not begin on a piece
    boundary either.
    """
    var stride = len(data) // (SAMPLE_COUNT + WARMUP_SAMPLES + 1)
    if stride < 1:
        stride = 1

    for index in range(WARMUP_SAMPLES):
        var piece = slice_at(data, index * stride, byte_length)
        var ignored = tokenizer.encode_ordinary_bytes(Span(piece))

    var samples = Samples()
    for index in range(SAMPLE_COUNT):
        var offset = (WARMUP_SAMPLES + index) * stride
        var piece = slice_at(data, offset, byte_length)
        var start = now()
        var ids = tokenizer.encode_ordinary_bytes(Span(piece))
        samples.add(now() - start)
        # Keep the result reachable so the encode cannot be optimised away.
        if len(ids) == 0xFFFFFF:
            print("unreachable")

    report_latency(name, samples)


def main() raises:
    """Measure latency across three short string size classes.

    Raises:
        Error: if the corpus or the vocabulary is missing.

    Roughly ten, fifty, and two hundred tokens, converted through the
    compression ratio the corpus actually exhibits, which is close to two
    bytes per token.
    """
    var data = read_corpus_slice(String(CORPUS), PROSE_OFFSET, 8 * 1024 * 1024)
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    print("# samples per class:", SAMPLE_COUNT)
    print("# warmup per class:", WARMUP_SAMPLES)
    print("# percentile method: nearest rank, no interpolation")

    measure(tokenizer, data, 24, String("latency_about_10_tokens"))
    measure(tokenizer, data, 120, String("latency_about_50_tokens"))
    measure(tokenizer, data, 480, String("latency_about_200_tokens"))


# =============================================================================
# End of file: bench/bench_short_strings.mojo
# =============================================================================
