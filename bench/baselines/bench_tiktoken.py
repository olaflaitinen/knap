# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/baselines/bench_tiktoken.py
# Purpose     : Runs the same measurements against tiktoken, on this machine.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/BENCHMARKS.md
# Depends on  : tiktoken
# Invariants  : Same inputs, same warmup, same estimators as the Mojo
#               benchmarks. A comparison against differently measured
#               numbers is not a comparison.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Benchmark tiktoken as a baseline for Knap.

Run by the author, on the author's machine, against the same corpus prefix
and with the same warmup and estimator definitions as the Mojo benchmarks.
Numbers are never copied from another project's README, because a number
measured elsewhere on unknown hardware is not a baseline.

If this baseline wins, that gets published in the same table with the same
prominence. It frequently will: tiktoken's core is Rust and has had far more
attention than this project.

    python bench/baselines/bench_tiktoken.py --megabytes 16
"""

from __future__ import annotations

import argparse
import math
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from corpus_slice import PROSE_OFFSET, read_corpus_slice

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CORPUS = REPO_ROOT / "bench" / "corpus" / "mixed.txt"

WARMUP_ITERATIONS = 1
MEASURED_ITERATIONS = 5

LATENCY_SAMPLES = 2000
LATENCY_WARMUP = 200
LATENCY_CLASSES = (
    ("latency_about_10_tokens", 24),
    ("latency_about_50_tokens", 120),
    ("latency_about_200_tokens", 480),
)


def percentile(samples: list[int], fraction: float) -> int:
    """Return a percentile by the nearest rank method.

    Args:
        samples: Durations in nanoseconds.
        fraction: The percentile as a fraction.

    Returns:
        The sample at that rank.

    Nearest rank with no interpolation, matching bench/harness.mojo exactly.
    A p99 computed by a different convention is not comparable with one
    computed by this convention, so both sides use the same.
    """
    ordered = sorted(samples)
    rank = math.ceil(fraction * len(ordered))
    rank = max(1, min(rank, len(ordered)))
    return ordered[rank - 1]


def report_throughput(name, byte_count, tokens, samples):
    """Print one throughput measurement in the collected line format."""
    mean_ns = statistics.fmean(samples)
    stddev = statistics.stdev(samples) if len(samples) > 1 else 0.0
    seconds = mean_ns / 1e9
    print(
        f"BENCH name={name} kind=throughput samples={len(samples)} "
        f"bytes={byte_count} tokens={tokens} mean_ns={int(mean_ns)} "
        f"stddev_ns={int(stddev)} cv={stddev / mean_ns if mean_ns else 0} "
        f"mb_per_s={byte_count / 1048576 / seconds if seconds else 0} "
        f"tokens_per_s={tokens / seconds if seconds else 0} "
        f"bytes_per_token={byte_count / tokens if tokens else 0}"
    )


def report_latency(name, samples):
    """Print one latency measurement in the collected line format."""
    mean_ns = statistics.fmean(samples)
    stddev = statistics.stdev(samples) if len(samples) > 1 else 0.0
    print(
        f"BENCH name={name} kind=latency samples={len(samples)} "
        f"mean_ns={int(mean_ns)} stddev_ns={int(stddev)} "
        f"cv={stddev / mean_ns if mean_ns else 0} "
        f"p50_ns={percentile(samples, 0.50)} "
        f"p90_ns={percentile(samples, 0.90)} "
        f"p99_ns={percentile(samples, 0.99)}"
    )


def main() -> int:
    """Measure tiktoken throughput, latency, and decode."""
    parser = argparse.ArgumentParser(description="Benchmark tiktoken.")
    parser.add_argument("--megabytes", type=int, default=16)
    arguments = parser.parse_args()

    try:
        import tiktoken
    except ImportError:
        raise SystemExit(
            "bench_tiktoken: tiktoken is not installed. Run 'uv sync "
            "--group dev' first."
        )

    if not CORPUS.is_file():
        raise SystemExit(
            "bench_tiktoken: the corpus is missing. Run "
            "'python scripts/fetch_corpus.py' first."
        )

    # The same slice the Mojo benchmarks read, by the same rule. A
    # prefix of this corpus is the generated hazard section rather than
    # natural language, so measuring one would measure repetition.
    raw = read_corpus_slice(
        CORPUS, PROSE_OFFSET, arguments.megabytes * 1024 * 1024
    )
    # Trim any partial sequence at the cut, so both sides see the same text.
    while raw:
        try:
            text = raw.decode("utf-8")
            break
        except UnicodeDecodeError:
            raw = raw[:-1]
    byte_count = len(raw)

    print(f"# tiktoken {getattr(tiktoken, '__version__', 'unknown')}")
    print(f"# input bytes: {byte_count}")
    print(f"# warmup iterations: {WARMUP_ITERATIONS}")
    print(f"# measured iterations: {MEASURED_ITERATIONS}")

    for name in ("cl100k_base", "o200k_base"):
        encoding = tiktoken.get_encoding(name)

        for _ in range(WARMUP_ITERATIONS):
            encoding.encode_ordinary(text)

        samples = []
        tokens = 0
        for _ in range(MEASURED_ITERATIONS):
            start = time.perf_counter_ns()
            ids = encoding.encode_ordinary(text)
            samples.append(time.perf_counter_ns() - start)
            tokens = len(ids)
        report_throughput(f"encode_{name}", byte_count, tokens, samples)

    # Latency, cut from the same corpus at the same offsets as the Mojo side.
    encoding = tiktoken.get_encoding("cl100k_base")
    latency_source = raw[: 8 * 1024 * 1024]
    for label, size in LATENCY_CLASSES:
        stride = max(1, len(latency_source) // (LATENCY_SAMPLES + LATENCY_WARMUP + 1))

        for index in range(LATENCY_WARMUP):
            chunk = latency_source[index * stride : index * stride + size]
            encoding.encode_ordinary(chunk.decode("utf-8", errors="ignore"))

        samples = []
        for index in range(LATENCY_SAMPLES):
            offset = (LATENCY_WARMUP + index) * stride
            chunk = latency_source[offset : offset + size]
            piece = chunk.decode("utf-8", errors="ignore")
            start = time.perf_counter_ns()
            encoding.encode_ordinary(piece)
            samples.append(time.perf_counter_ns() - start)
        report_latency(label, samples)

    # Decode, reported as a footnote for the same reason the Mojo side does.
    ids = encoding.encode_ordinary(text)
    for _ in range(2):
        encoding.decode_bytes(ids)
    samples = []
    produced = 0
    for _ in range(10):
        start = time.perf_counter_ns()
        out = encoding.decode_bytes(ids)
        samples.append(time.perf_counter_ns() - start)
        produced = len(out)
    report_throughput("decode_cl100k_base", produced, len(ids), samples)
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: bench/baselines/bench_tiktoken.py
# =============================================================================
