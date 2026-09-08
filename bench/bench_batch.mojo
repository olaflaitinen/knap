# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/bench_batch.mojo
# Purpose     : Batch encode throughput across many documents.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/BENCHMARKS.md
# Depends on  : knap.tokenizer, harness.mojo
# Invariants  : Sequential, not parallel. Mojo 1.0.0 exposes no usable
#               parallelism primitive, which is recorded here rather than
#               worked around.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Batch encode throughput for Knap.

Many documents rather than one, which is the shape dataset preparation sees
and the only place this project intends to parallelize. A single document is
deliberately never split across threads, because a pattern match can span any
chunk boundary and independent chunks can produce different tokens. That
reasoning is in docs/ARCHITECTURE.md.

**This benchmark is sequential, and not by choice.** Mojo 1.0.0 exposes no
usable parallelism primitive. There is no parallelize in std.algorithm or
std.algorithm.functional, and the TaskGroup in std.runtime.asyncrt aborts
with an LLVM error on construction. The async support it depends on is
documented as unfinished. So the batch path runs on one thread, the number
below is a one thread number, and it is labelled as such rather than being
quietly presented as batch throughput.

The measurement is still worth having. It shows the per document overhead
that a batch amortises, and it is the baseline any future parallel
implementation has to beat.

    mojo run -I src -I bench bench/bench_batch.mojo
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

comptime DOCUMENT_COUNT = 2000
"""How many documents the batch holds."""

comptime DOCUMENT_BYTES = 2048
"""Size of each document, roughly a page of text."""

comptime LINE_SLACK = 65536
"""Extra bytes requested so line trimming cannot leave the batch short."""

comptime WARMUP_ITERATIONS = 1
"""Untimed iterations run before measurement."""

comptime MEASURED_ITERATIONS = 5
"""Timed iterations."""


def build_batch() raises -> List[List[UInt8]]:
    """Cut a batch of documents out of the corpus.

    Returns:
        The documents.

    Raises:
        Error: if the corpus is missing or too small.

    Real text rather than generated, because the merge loop's cost depends
    on piece length and synthetic documents get that wrong.
    """
    var needed = DOCUMENT_COUNT * DOCUMENT_BYTES
    # Asked for with slack, because the slice is trimmed back to a line
    # boundary and would otherwise land a few dozen bytes short of what the
    # batch needs. The first run of this after the corpus offset landed did
    # exactly that: it asked for 4096000 and was handed 4095949.
    var data = read_corpus_slice(
        String(CORPUS), PROSE_OFFSET, needed + LINE_SLACK
    )
    if len(data) < needed:
        raise Error(
            String(
                t"knap bench: the corpus has {len(data)} bytes but the batch"
                t" needs {needed}"
            )
        )

    var batch = List[List[UInt8]]()
    for index in range(DOCUMENT_COUNT):
        var start = index * DOCUMENT_BYTES
        var document = List[UInt8](capacity=DOCUMENT_BYTES)
        for offset in range(DOCUMENT_BYTES):
            document.append(data[start + offset])
        batch.append(document^)
    return batch^


def main() raises:
    """Measure sequential batch encode throughput.

    Raises:
        Error: if the corpus or the vocabulary is missing.
    """
    var batch = build_batch()
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var total_bytes = DOCUMENT_COUNT * DOCUMENT_BYTES

    print("# documents:", DOCUMENT_COUNT)
    print("# bytes per document:", DOCUMENT_BYTES)
    print("# threads: 1, see the module docstring for why")
    print("# warmup iterations:", WARMUP_ITERATIONS)
    print("# measured iterations:", MEASURED_ITERATIONS)

    for _ in range(WARMUP_ITERATIONS):
        for index in range(len(batch)):
            var ignored = tokenizer.encode_ordinary_bytes(Span(batch[index]))

    var samples = Samples()
    var tokens = 0
    for _ in range(MEASURED_ITERATIONS):
        var produced = 0
        var start = now()
        for index in range(len(batch)):
            var ids = tokenizer.encode_ordinary_bytes(Span(batch[index]))
            produced += len(ids)
        samples.add(now() - start)
        tokens = produced

    report_throughput(
        String("batch_encode_cl100k_base_1_thread"),
        total_bytes,
        tokens,
        samples,
    )


# =============================================================================
# End of file: bench/bench_batch.mojo
# =============================================================================
