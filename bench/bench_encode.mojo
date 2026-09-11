# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/bench_encode.mojo
# Purpose     : Single document encode throughput, the headline metric.
# Stage       : Vectorisation and benchmarks. See docs/BENCHMARKS.md
# Depends on  : knap.tokenizer, harness.mojo
# Invariants  : The vocabulary and the corpus are loaded before timing starts,
#               so neither the file read nor the rank table build is counted.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Single document encode throughput for Knap.

This is the headline metric. It measures what a caller gets when they hand
the tokenizer one large document, which is the shape that batch processing
and dataset preparation actually see.

What is deliberately excluded from the timing: reading the corpus from disk,
loading the vocabulary, and building the rank table. Those are start up
costs paid once, and folding them into a throughput number would understate
the steady state that matters.

What is deliberately included: pre-tokenization and the merge loop together.
Splitting them would produce a faster looking number for each half that
nobody could act on.

Usage, with a size in megabytes so a full run and a quick check use the same
code path:

    mojo run -I src -I bench bench/bench_encode.mojo 16
"""

from std.sys import argv

from harness import (
    PROSE_OFFSET,
    Samples,
    now,
    read_corpus_slice,
    report_throughput,
)
from knap.tokenizer import (
    load_cl100k_base_tokenizer,
    load_gpt2_tokenizer,
    load_o200k_base_tokenizer,
    load_p50k_base_tokenizer,
)

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime R50K_VOCAB = "tests/fixtures/vocabs/r50k_base.tiktoken"
"""Path to the fetched r50k_base merge vocabulary, shared with gpt2."""

comptime P50K_VOCAB = "tests/fixtures/vocabs/p50k_base.tiktoken"
"""Path to the fetched p50k_base vocabulary, shared with p50k_edit."""

comptime WARMUP_ITERATIONS = 1
"""Untimed iterations run before measurement, to warm caches."""

comptime MEASURED_ITERATIONS = 5
"""Timed iterations. Small because each one encodes megabytes."""


def main() raises:
    """Measure encode throughput for the four distinct encode behaviours.

    Raises:
        Error: if an input is missing.

    Four rather than seven. Ordinary encoding is decided by the pattern and
    the merge ranks and by nothing else, so the other three names would
    reproduce a number already in the table and cost three more passes over
    the corpus to do it.

    Counting is measured after encoding, on the same input in the same run,
    because the only interesting thing about the counting path is how it
    compares with the encoding it optimises.
    """
    var args = argv()
    var megabytes = 16
    if len(args) > 1:
        megabytes = Int(String(args[1]))
    var limit = megabytes * 1024 * 1024

    var data = read_corpus_slice(String(CORPUS), PROSE_OFFSET, limit)
    print("# corpus offset:", PROSE_OFFSET)
    print("# input bytes:", len(data))
    print("# warmup iterations:", WARMUP_ITERATIONS)
    print("# measured iterations:", MEASURED_ITERATIONS)

    var cl100k = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var o200k = load_o200k_base_tokenizer(String(O200K_VOCAB))
    var gpt2 = load_gpt2_tokenizer(String(R50K_VOCAB))
    var p50k = load_p50k_base_tokenizer(String(P50K_VOCAB))

    for which in range(4):
        var name = String("encode_cl100k_base")
        if which == 1:
            name = String("encode_o200k_base")
        elif which == 2:
            name = String("encode_gpt2")
        elif which == 3:
            name = String("encode_p50k_base")

        # Warm up outside the timer. The first pass touches the whole rank
        # table and the corpus, and counting that would measure page faults
        # rather than the tokenizer.
        for _ in range(WARMUP_ITERATIONS):
            if which == 0:
                var ignored = cl100k.encode_ordinary_bytes(Span(data))
            elif which == 1:
                var ignored = o200k.encode_ordinary_bytes(Span(data))
            elif which == 2:
                var ignored = gpt2.encode_ordinary_bytes(Span(data))
            else:
                var ignored = p50k.encode_ordinary_bytes(Span(data))

        var samples = Samples()
        var tokens = 0
        for _ in range(MEASURED_ITERATIONS):
            var start = now()
            if which == 0:
                var ids = cl100k.encode_ordinary_bytes(Span(data))
                tokens = len(ids)
            elif which == 1:
                var ids = o200k.encode_ordinary_bytes(Span(data))
                tokens = len(ids)
            elif which == 2:
                var ids = gpt2.encode_ordinary_bytes(Span(data))
                tokens = len(ids)
            else:
                var ids = p50k.encode_ordinary_bytes(Span(data))
                tokens = len(ids)
            samples.add(now() - start)

        report_throughput(name, len(data), tokens, samples)

    # Counting, on the same input, in the same run, immediately after. The
    # claim being measured is narrow: counting walks the same scanner and
    # the same merge loop and differs only in not building the list of ids.
    # If that list costs nothing, these rows will match the ones above and
    # the counting path is not worth having.
    for which in range(4):
        var name = String("count_cl100k_base")
        if which == 1:
            name = String("count_o200k_base")
        elif which == 2:
            name = String("count_gpt2")
        elif which == 3:
            name = String("count_p50k_base")

        for _ in range(WARMUP_ITERATIONS):
            if which == 0:
                var ignored = cl100k.count_ordinary_bytes(Span(data))
            elif which == 1:
                var ignored = o200k.count_ordinary_bytes(Span(data))
            elif which == 2:
                var ignored = gpt2.count_ordinary_bytes(Span(data))
            else:
                var ignored = p50k.count_ordinary_bytes(Span(data))

        var samples = Samples()
        var tokens = 0
        for _ in range(MEASURED_ITERATIONS):
            var start = now()
            if which == 0:
                tokens = cl100k.count_ordinary_bytes(Span(data))
            elif which == 1:
                tokens = o200k.count_ordinary_bytes(Span(data))
            elif which == 2:
                tokens = gpt2.count_ordinary_bytes(Span(data))
            else:
                tokens = p50k.count_ordinary_bytes(Span(data))
            samples.add(now() - start)

        report_throughput(name, len(data), tokens, samples)


# =============================================================================
# End of file: bench/bench_encode.mojo
# =============================================================================
