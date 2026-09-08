#!/usr/bin/env bash
# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/run_all.sh
# Purpose     : Regenerates every published benchmark number from scratch.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/BENCHMARKS.md
# Depends on  : uv, the pinned Mojo compiler, the fetched corpus and vocabs.
# Invariants  : Records the machine, the versions, and the effective build
#               target alongside the numbers. A figure without them is not
#               comparable with anything.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
#
# Every number in docs/BENCHMARKS.md comes from this script. Run it from the
# repository root:
#
#     bash bench/run_all.sh
#     bash bench/run_all.sh 4          # smaller input, for a quick check
#
# Results land in bench/results/ as one file per run, named by timestamp, and
# those files are committed alongside the document that quotes them.
#
# A warning that is not decoration. Benchmark on an idle machine. An earlier
# run of this suite was taken while a fuzzing job held the cores, and the
# coefficient of variation came out above 0.2, which is large enough that the
# differences being measured were smaller than the noise. The harness reports
# that spread for exactly this reason: if it is large, the numbers are not
# worth publishing.

set -uo pipefail

MEGABYTES="${1:-16}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="bench/results/run-${STAMP}.txt"
mkdir -p bench/results

MOJO=".venv/bin/mojo"
if [ ! -x "$MOJO" ]; then
  echo "run_all: no Mojo compiler at $MOJO. Run 'uv sync --group dev' first." >&2
  exit 1
fi

if [ ! -f bench/corpus/mixed.txt ]; then
  echo "run_all: the corpus is missing. Run 'python scripts/fetch_corpus.py'." >&2
  exit 1
fi

# The Mojo benchmarks and the Python baselines must read the same slice of
# the corpus, and each language holds its own copy of the offset. Two copies
# is one more than is safe, so they are compared here rather than trusted. A
# baseline reading different text is not a baseline, and the failure would be
# invisible in the results: both sides would report plausible numbers.
MOJO_OFFSET="$(grep -oP 'comptime PROSE_OFFSET: Int = \K[0-9]+' bench/harness.mojo)"
PY_OFFSET="$(grep -oP '^PROSE_OFFSET = \K[0-9]+' bench/baselines/corpus_slice.py)"
if [ "$MOJO_OFFSET" != "$PY_OFFSET" ]; then
  echo "run_all: corpus offsets disagree." >&2
  echo "  bench/harness.mojo          : ${MOJO_OFFSET}" >&2
  echo "  bench/baselines/corpus_slice.py : ${PY_OFFSET}" >&2
  exit 1
fi

{
  echo "# Knap benchmark run"
  echo "# timestamp        : ${STAMP}"
  echo "# input megabytes  : ${MEGABYTES}"
  echo "#"
  echo "# --- machine ---"
  echo "# cpu model        : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
  echo "# logical cores    : $(nproc)"
  echo "# memory total     : $(grep MemTotal /proc/meminfo | awk '{print $2, $3}')"
  echo "# kernel           : $(uname -sr)"
  echo "#"
  echo "# --- versions ---"
  echo "# mojo             : $($MOJO --version 2>/dev/null | tr -d '\n')"
  echo "# python           : $(uv run python -c 'import sys; print(sys.version.split()[0])' 2>/dev/null)"
  echo "# tiktoken         : $(uv run python -c 'import tiktoken; print(tiktoken.__version__)' 2>/dev/null)"
  echo "# tokenizers       : $(uv run python -c 'import tokenizers; print(tokenizers.__version__)' 2>/dev/null)"
  echo "# rs-bpe           : $(uv run python -c 'import importlib.metadata as m; print(m.version("rs-bpe"))' 2>/dev/null)"
  echo "#"
  echo "# --- effective build target ---"
  $MOJO build --print-effective-target -I src -I bench bench/bench_encode.mojo 2>/dev/null \
    | grep -v Crashpad | sed 's/^/# /'
  echo "#"
  echo "# --- corpus ---"
  echo "# corpus bytes     : $(stat -c%s bench/corpus/mixed.txt)"
  echo "# corpus offset    : ${MOJO_OFFSET}, past the generated hazard section"
  echo "# corpus sha256    : $(sha256sum bench/corpus/mixed.txt | cut -d' ' -f1)"
  echo

  echo "## knap encode"
  $MOJO run -I src -I bench bench/bench_encode.mojo "$MEGABYTES" 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap encode, vectorised classifier"
  $MOJO run -I src -I bench -D KNAP_SIMD=1 bench/bench_encode.mojo "$MEGABYTES" 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap piece cache, uncached against cold and warm"
  $MOJO run -I src -I bench bench/bench_cache.mojo "$MEGABYTES" 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap short string latency"
  $MOJO run -I src -I bench bench/bench_short_strings.mojo 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap batch, single thread"
  $MOJO run -I src -I bench bench/bench_batch.mojo 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap decode, footnote metric only"
  $MOJO run -I src -I bench bench/bench_decode.mojo 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap pre-tokenization, scalar classifier, the default"
  $MOJO run -I src -I bench bench/bench_pretokenize.mojo "$MEGABYTES" 2>/dev/null | grep -v Crashpad
  echo

  echo "## knap pre-tokenization, vectorised classifier"
  $MOJO run -I src -I bench -D KNAP_SIMD=1 bench/bench_pretokenize.mojo "$MEGABYTES" 2>/dev/null | grep -v Crashpad
  echo

  echo "## baseline tiktoken"
  uv run python bench/baselines/bench_tiktoken.py --megabytes "$MEGABYTES" 2>&1
  echo

  echo "## baseline rs-bpe"
  uv run python bench/baselines/bench_rs_bpe.py --megabytes "$MEGABYTES" 2>&1
  echo

  echo "## baseline hugging face tokenizers"
  uv run python bench/baselines/bench_hf_tokenizers.py --megabytes "$MEGABYTES" 2>&1
  echo
} | tee "$OUT"

echo
echo "run_all: results written to $OUT"

# =============================================================================
# End of file: bench/run_all.sh
# =============================================================================
