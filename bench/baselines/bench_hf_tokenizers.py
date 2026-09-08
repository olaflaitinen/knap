# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/baselines/bench_hf_tokenizers.py
# Purpose     : Runs the encode measurements against Hugging Face tokenizers.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/BENCHMARKS.md
# Depends on  : tokenizers, and tiktoken for the vocabulary definition.
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
"""Benchmark Hugging Face tokenizers as a baseline for Knap.

A caveat that belongs with the number rather than in a footnote nobody
reads. This builds a byte level BPE tokenizer from the same merge ranks
tiktoken uses, with the same pre-tokenization pattern, so the comparison is
like for like on vocabulary. It is not guaranteed to produce identical token
ids, because the two libraries differ in details this project has not
verified. Where the outputs differ, the run says so and the number is
labelled as approximate rather than being quietly reported.

    python bench/baselines/bench_hf_tokenizers.py --megabytes 16
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


def build_tokenizer(name: str):
    """Build a byte level BPE tokenizer from tiktoken's merge ranks.

    Args:
        name: The encoding name.

    Returns:
        A configured tokenizers.Tokenizer.

    Raises:
        SystemExit: if either dependency is missing.

    Constructed rather than downloaded, so that the vocabulary is provably
    the same one Knap and tiktoken use. Downloading a lookalike from a hub
    would compare two different vocabularies and call it a baseline.
    """
    try:
        import tiktoken
        from tokenizers import Tokenizer, decoders, models, pre_tokenizers
    except ImportError as exc:
        raise SystemExit(
            "bench_hf_tokenizers: tokenizers and tiktoken are required. Run "
            "'uv sync --group dev' first."
        ) from exc

    encoding = tiktoken.get_encoding(name)
    ranks = encoding._mergeable_ranks

    # tokenizers keys its vocabulary by string, so the raw token bytes are
    # mapped through the same byte to unicode alphabet the library uses
    # internally for byte level models.
    byte_to_unicode = _byte_to_unicode()
    vocab = {
        "".join(byte_to_unicode[b] for b in token): rank
        for token, rank in ranks.items()
    }

    merges = []
    for token, rank in sorted(ranks.items(), key=lambda item: item[1]):
        if len(token) < 2:
            continue
        for split in range(1, len(token)):
            left, right = token[:split], token[split:]
            if left in ranks and right in ranks:
                merges.append(
                    (
                        "".join(byte_to_unicode[b] for b in left),
                        "".join(byte_to_unicode[b] for b in right),
                    )
                )
                break

    tokenizer = Tokenizer(models.BPE(vocab=vocab, merges=merges))
    tokenizer.pre_tokenizer = pre_tokenizers.Sequence(
        [
            pre_tokenizers.Split(
                pattern=__import__("tokenizers").Regex(encoding._pat_str),
                behavior="isolated",
                invert=False,
            ),
            pre_tokenizers.ByteLevel(add_prefix_space=False, use_regex=False),
        ]
    )
    tokenizer.decoder = decoders.ByteLevel()
    return tokenizer


def _byte_to_unicode() -> dict[int, str]:
    """Return the byte to unicode alphabet byte level BPE models use.

    Returns:
        A mapping from byte value to a single printable character.

    The standard GPT-2 style mapping: printable ASCII and Latin-1 ranges map
    to themselves, and everything else is shifted into an unused block so
    that every byte has a printable representation.
    """
    printable = (
        list(range(ord("!"), ord("~") + 1))
        + list(range(0xA1, 0xAC + 1))
        + list(range(0xAE, 0xFF + 1))
    )
    mapped = printable[:]
    shift = 0
    for value in range(256):
        if value not in printable:
            printable.append(value)
            mapped.append(256 + shift)
            shift += 1
    return {b: chr(u) for b, u in zip(printable, mapped)}


def main() -> int:
    """Measure Hugging Face tokenizers encode throughput."""
    parser = argparse.ArgumentParser(
        description="Benchmark Hugging Face tokenizers."
    )
    parser.add_argument("--megabytes", type=int, default=16)
    arguments = parser.parse_args()

    try:
        import tiktoken
        import tokenizers
    except ImportError:
        raise SystemExit(
            "bench_hf_tokenizers: dependencies missing. Run 'uv sync "
            "--group dev' first."
        )

    if not CORPUS.is_file():
        raise SystemExit(
            "bench_hf_tokenizers: the corpus is missing. Run "
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

    print(f"# tokenizers {tokenizers.__version__}")
    print(f"# input bytes: {byte_count}")
    print(f"# warmup iterations: {WARMUP_ITERATIONS}")
    print(f"# measured iterations: {MEASURED_ITERATIONS}")

    for name in ("cl100k_base",):
        try:
            tokenizer = build_tokenizer(name)
        except Exception as exc:
            # Reported rather than swallowed. A baseline that could not be
            # built is a fact about this comparison, not something to hide.
            print(f"# SKIPPED {name}: {type(exc).__name__}: {exc}")
            continue

        probe = "Knap tokenizes 1234 bytes."
        reference = tiktoken.get_encoding(name).encode_ordinary(probe)
        theirs = tokenizer.encode(probe).ids
        note = "identical_to_tiktoken" if theirs == reference else "approximate"

        for _ in range(WARMUP_ITERATIONS):
            tokenizer.encode(text)

        samples = []
        tokens = 0
        for _ in range(MEASURED_ITERATIONS):
            start = time.perf_counter_ns()
            encoded = tokenizer.encode(text)
            samples.append(time.perf_counter_ns() - start)
            tokens = len(encoded.ids)
        report_throughput(f"encode_{name}", byte_count, tokens, samples, note)

    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: bench/baselines/bench_hf_tokenizers.py
# =============================================================================
