# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/bench_pretokenize.mojo
# Purpose     : Pre-tokenization in isolation, scalar against vectorised.
# Stage       : Vectorisation and benchmarks. See docs/BENCHMARKS.md
# Depends on  : knap.pretokenize.scanner, knap.config, harness.mojo
# Invariants  : Which classifier is compiled in is a build time choice, so
#               this reports it rather than choosing it.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Pre-tokenization throughput, measured on its own.

Stage 2 in isolation, so the merge loop's cost does not hide it. This is the
benchmark that decided whether the vectorised classifier ships, and it is
the reason it does not.

Run it twice to compare, once per build:

    mojo run -I src -I bench bench/bench_pretokenize.mojo
    mojo run -I src -I bench -D KNAP_SIMD=1 bench/bench_pretokenize.mojo

The build reports which classifier it contains, so the two runs cannot be
mixed up in the results file.
"""

from std.sys import argv

from harness import (
    PROSE_OFFSET,
    Samples,
    now,
    read_corpus_slice,
    report_throughput,
)
from knap.config import SCALAR_ONLY
from knap.pretokenize.scanner import scan_cl100k, scan_o200k

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime WARMUP_ITERATIONS = 1
"""Untimed iterations run before measurement."""

comptime MEASURED_ITERATIONS = 5
"""Timed iterations."""


def main() raises:
    """Measure pre-tokenization throughput for both patterns.

    Raises:
        Error: if the corpus is missing.
    """
    var args = argv()
    var megabytes = 16
    if len(args) > 1:
        megabytes = Int(String(args[1]))

    var data = read_corpus_slice(
        String(CORPUS), PROSE_OFFSET, megabytes * 1024 * 1024
    )
    var classifier = String("simd")
    if SCALAR_ONLY:
        classifier = String("scalar")

    print("# classifier:", classifier)
    print("# corpus offset:", PROSE_OFFSET)
    print("# input bytes:", len(data))
    print("# warmup iterations:", WARMUP_ITERATIONS)
    print("# measured iterations:", MEASURED_ITERATIONS)

    for which in range(2):
        var name = String("pretokenize_cl100k_base_") + classifier
        if which == 1:
            name = String("pretokenize_o200k_base_") + classifier

        for _ in range(WARMUP_ITERATIONS):
            var warm = List[Int]()
            if which == 0:
                scan_cl100k(Span(data), warm)
            else:
                scan_o200k(Span(data), warm)

        var samples = Samples()
        var pieces = 0
        for _ in range(MEASURED_ITERATIONS):
            var ends = List[Int]()
            var start = now()
            if which == 0:
                scan_cl100k(Span(data), ends)
            else:
                scan_o200k(Span(data), ends)
            samples.add(now() - start)
            pieces = len(ends)

        # Pieces stand in for tokens here. Stage 2 emits pieces, and the
        # ratio between bytes and pieces is the thing that governs whether
        # a vector wide enough to matter ever fills.
        report_throughput(name, len(data), pieces, samples)


# =============================================================================
# End of file: bench/bench_pretokenize.mojo
# =============================================================================
