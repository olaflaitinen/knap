# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/bench_cache.mojo
# Purpose     : Measures what the piece cache is worth, cold and warm, and
#               what it costs in memory.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/ROADMAP.md
# Depends on  : knap.cache, knap.tokenizer, harness.mojo
# Invariants  : The uncached path is measured in the same run, on the same
#               input, so the comparison is not against a remembered number.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Measure the piece cache.

Three numbers, because one would be misleading.

  * **Uncached.** The merge loop runs for every piece. This is the default
    and the baseline.
  * **Cold cache.** A fresh cache for each timed iteration. This is what a
    process encoding one document and exiting would see, and it is the case
    where the cache can lose, because it pays to fill a table it then throws
    away.
  * **Shared cache.** One cache reused across documents it has not seen
    before. This is what a long running service sees, and it is the number
    the cache should be judged on.
  * **Repeated document.** One cache and one document, encoded over and
    over. This is the best a piece cache can ever do and it is reported as a
    bound, not as a result. No real workload looks like this.

An earlier version of this file measured only the last of those and called
it the service case. That was wrong in the flattering direction, which is
the direction that matters: a service encodes text it has not seen.

The memory the cache holds is printed alongside, because a throughput gain
bought with an unbounded table is not a gain, it is a deferred problem. The
figure is the arenas plus the probe table, which is all of the storage.

Usage, with a size in megabytes:

    mojo run -I src -I bench bench/bench_cache.mojo 16
"""

from std.sys import argv

from harness import (
    PROSE_OFFSET,
    Samples,
    now,
    read_corpus_slice,
    report_throughput,
)
from knap.cache import PieceCache
from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_o200k_base_tokenizer,
)

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime WARMUP_ITERATIONS = 1
"""Untimed iterations run before measurement, to warm caches."""

comptime MEASURED_ITERATIONS = 5
"""Timed iterations. Small because each one encodes megabytes."""

comptime CACHE_CAPACITY = 262144
"""Entries the benchmark cache will hold.

Chosen to be larger than the distinct piece count of a few megabytes of
mixed text, so the measurement reports what the cache does rather than what
its bound does. The memory figure printed with each result is what makes
that choice honest instead of hidden.
"""


def cache_bytes(cache: PieceCache) -> Int:
    """Report the storage one cache holds.

    Args:
        cache: The cache to measure.

    Returns:
        Bytes held by the key arena, the value arena, the per entry index
        lists, and the probe table.

    Counted rather than estimated. An eight byte integer is assumed for
    every list of integers, which is what the target uses, and the key arena
    is one byte per stored byte.
    """
    var per_int = 8
    var entries = cache.count()
    var total = len(cache.key_data)
    total += len(cache.value_data) * per_int
    total += len(cache.slots) * per_int
    total += entries * per_int * 4
    return total


def report_cache(name: String, cache: PieceCache):
    """Print what one cache held and how well it served.

    Args:
        name: Label for the measurement.
        cache: The cache to report on.
    """
    print("#", name, "entries:", cache.count())
    print("#", name, "hits:", cache.hits)
    print("#", name, "misses:", cache.misses)
    print("#", name, "rejected:", cache.rejected)
    print("#", name, "hit rate:", cache.hit_rate())
    print("#", name, "bytes held:", cache_bytes(cache))


def encode_uncached(tokenizer: Tokenizer, data: Span[UInt8, _]) raises -> Int:
    """Encode once with no cache and report the token count.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.

    Returns:
        How many tokens were produced.

    Raises:
        Error: if encoding fails.
    """
    var ids = tokenizer.encode_ordinary_bytes(data)
    return len(ids)


def encode_cached(
    tokenizer: Tokenizer, data: Span[UInt8, _], mut cache: PieceCache
) raises -> Int:
    """Encode once with a cache and report the token count.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.
        cache: The cache to use, updated in place.

    Returns:
        How many tokens were produced.

    Raises:
        Error: if encoding fails.
    """
    var ids = tokenizer.encode_ordinary_bytes_cached(data, cache)
    return len(ids)


def measure_one(
    tokenizer: Tokenizer, data: Span[UInt8, _], label: String
) raises:
    """Measure one tokenizer four ways and print all four.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.
        label: Encoding name, used in the reported measurement names.

    Raises:
        Error: if encoding fails or the input is too small to divide.

    The input is cut into equal chunks and each timed iteration encodes a
    different one, so the first three measurements see the same text in the
    same order and differ only in what they do with a cache.

    The fourth deliberately does not. It re-encodes one chunk over and over
    against a warm cache, which is the best a piece cache can ever do, and
    it is reported as a bound rather than as a result. An earlier version of
    this benchmark measured only that case and called it the long running
    service number. It is not: a service encodes documents it has not seen,
    and the number that describes it is the shared cache one.
    """
    var chunk = len(data) // MEASURED_ITERATIONS
    if chunk < 1024:
        raise Error(
            String("knap bench: the input is too small to divide into chunks")
        )

    # --- uncached, the baseline ------------------------------------------
    for _ in range(WARMUP_ITERATIONS):
        var ignored = encode_uncached(tokenizer, data[0:chunk])

    var plain = Samples()
    var tokens = 0
    for index in range(MEASURED_ITERATIONS):
        var at = index * chunk
        var start = now()
        tokens = encode_uncached(tokenizer, data[at : at + chunk])
        plain.add(now() - start)
    report_throughput(String("encode_uncached_") + label, chunk, tokens, plain)

    # --- cold cache, a fresh table for every document --------------------
    for _ in range(WARMUP_ITERATIONS):
        var throwaway = PieceCache(CACHE_CAPACITY)
        var ignored = encode_cached(tokenizer, data[0:chunk], throwaway)

    var cold = Samples()
    var cold_cache = PieceCache(0)
    for index in range(MEASURED_ITERATIONS):
        var at = index * chunk
        var fresh = PieceCache(CACHE_CAPACITY)
        var start = now()
        tokens = encode_cached(tokenizer, data[at : at + chunk], fresh)
        cold.add(now() - start)
        cold_cache = fresh^
    report_throughput(String("encode_cold_cache_") + label, chunk, tokens, cold)
    report_cache(String("cold_cache_") + label, cold_cache)

    # --- shared cache across documents it has not seen before ------------
    var shared = PieceCache(CACHE_CAPACITY)
    for _ in range(WARMUP_ITERATIONS):
        var ignored = encode_cached(tokenizer, data[0:chunk], shared)

    var across = Samples()
    for index in range(MEASURED_ITERATIONS):
        var at = index * chunk
        var start = now()
        tokens = encode_cached(tokenizer, data[at : at + chunk], shared)
        across.add(now() - start)
    report_throughput(
        String("encode_shared_cache_") + label, chunk, tokens, across
    )
    report_cache(String("shared_cache_") + label, shared)

    # --- the same document repeated, an upper bound only -----------------
    var repeated_cache = PieceCache(CACHE_CAPACITY)
    for _ in range(WARMUP_ITERATIONS):
        var ignored = encode_cached(tokenizer, data[0:chunk], repeated_cache)

    var repeated = Samples()
    for _ in range(MEASURED_ITERATIONS):
        var start = now()
        tokens = encode_cached(tokenizer, data[0:chunk], repeated_cache)
        repeated.add(now() - start)
    report_throughput(
        String("encode_repeated_document_") + label, chunk, tokens, repeated
    )
    report_cache(String("repeated_document_") + label, repeated_cache)


def main() raises:
    """Measure the piece cache for both encodings.

    Raises:
        Error: if an input is missing.
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
    print("# cache capacity:", CACHE_CAPACITY)

    var cl100k = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    measure_one(cl100k, Span(data), String("cl100k_base"))

    var o200k = load_o200k_base_tokenizer(String(O200K_VOCAB))
    measure_one(o200k, Span(data), String("o200k_base"))


# =============================================================================
# End of file: bench/bench_cache.mojo
# =============================================================================
