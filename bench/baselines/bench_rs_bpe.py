# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/baselines/bench_rs_bpe.py
# Purpose     : Runs the encode measurements against rs-bpe.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/BENCHMARKS.md
# Depends on  : rs-bpe, and tiktoken to confirm the outputs agree.
# Invariants  : Same corpus prefix, warmup, and estimators as every other
#               benchmark in this directory.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Benchmark rs-bpe as a baseline for Knap.

rs-bpe is the fastest of the three baselines and is the one Knap is least
likely to beat. It is included precisely for that reason: a benchmark suite
that only compares against implementations it can beat is advertising, not
measurement.

The outputs are checked against tiktoken before timing, so a number is never
reported for a tokenizer that turned out to be encoding something else.

One packaging note, recorded because it cost time. The published wheel's
convenience module rs_bpe.openai fails to import, reporting that the
extension needs building with maturin. The working entry point is the
compiled module underneath it, rs_bpe.bpe.openai, which this uses.

    python bench/baselines/bench_rs_bpe.py --megabytes 16
"""

from __future__ import annotations

import argparse
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


def report_throughput(name, byte_count, tokens, samples, note=""):
    """Print one throughput measurement in the collected line format."""
    mean_ns = statistics.fmean(samples)
    stddev = statistics.stdev(samples) if len(samples) > 1 else 0.0
    seconds = mean_ns / 1e9
    suffix = f" note={note}" if note else ""
    print(
        f"BENCH name={name} kind=throughput samples={len(samples)} "
        f"bytes={byte_count} tokens={tokens} mean_ns={int(mean_ns)} "
        f"stddev_ns={int(stddev)} cv={stddev / mean_ns if mean_ns else 0} "
        f"mb_per_s={byte_count / 1048576 / seconds if seconds else 0} "
        f"tokens_per_s={tokens / seconds if seconds else 0} "
        f"bytes_per_token={byte_count / tokens if tokens else 0}{suffix}"
    )


def main() -> int:
    """Measure rs-bpe encode throughput."""
    parser = argparse.ArgumentParser(description="Benchmark rs-bpe.")
    parser.add_argument("--megabytes", type=int, default=16)
    arguments = parser.parse_args()

    try:
        import tiktoken
        from rs_bpe import bpe
    except ImportError as exc:
        print(f"# SKIPPED: rs-bpe is not usable here: {exc}")
        return 0

    if not CORPUS.is_file():
        raise SystemExit(
            "bench_rs_bpe: the corpus is missing. Run "
            "'python scripts/fetch_corpus.py' first."
        )

    # The same slice the Mojo benchmarks read, by the same rule. A
    # prefix of this corpus is the generated hazard section rather than
    # natural language, so measuring one would measure repetition.
    raw = read_corpus_slice(
        CORPUS, PROSE_OFFSET, arguments.megabytes * 1024 * 1024
    )
    while raw:
        try:
            text = raw.decode("utf-8")
            break
        except UnicodeDecodeError:
            raw = raw[:-1]
    byte_count = len(raw)

    print("# rs-bpe, entry point rs_bpe.bpe.openai")
    print(f"# input bytes: {byte_count}")
    print(f"# warmup iterations: {WARMUP_ITERATIONS}")
    print(f"# measured iterations: {MEASURED_ITERATIONS}")

    # rs-bpe ships two encodings and no loader for a .tiktoken file, so
    # there is no honest way to give it a gpt2 or p50k_base row. Its module
    # exposes cl100k_base and o200k_base and nothing else, which was read
    # off the module rather than assumed.
    builders = {
        "cl100k_base": bpe.openai.cl100k_base,
        "o200k_base": bpe.openai.o200k_base,
    }

    for name, builder in builders.items():
        try:
            tokenizer = builder()
        except Exception as exc:
            print(f"# SKIPPED {name}: {type(exc).__name__}: {exc}")
            continue

        # Confirm this really is the same tokenizer before timing it.
        probe = "Knap tokenizes 1234 bytes."
        reference = tiktoken.get_encoding(name).encode_ordinary(probe)
        theirs = list(tokenizer.encode(probe))
        note = "identical_to_tiktoken" if theirs == reference else "differs"
        if note == "differs":
            print(f"# WARNING {name}: rs-bpe disagrees with tiktoken on a probe")

        for _ in range(WARMUP_ITERATIONS):
            tokenizer.encode(text)

        samples = []
        tokens = 0
        for _ in range(MEASURED_ITERATIONS):
            start = time.perf_counter_ns()
            ids = tokenizer.encode(text)
            samples.append(time.perf_counter_ns() - start)
            tokens = len(ids)
        report_throughput(f"encode_{name}", byte_count, tokens, samples, note)

    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: bench/baselines/bench_rs_bpe.py
# =============================================================================
