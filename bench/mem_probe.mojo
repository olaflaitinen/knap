# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/mem_probe.mojo
# Purpose     : Does one thing and exits, so that a parent process can
#               attribute its peak resident memory to that one thing.
# Stage       : Benchmarking. See docs/BENCHMARKS.md
# Depends on  : knap.tokenizer, knap.vocab, bench/harness.mojo
# Invariants  : One stage per process. Measuring two stages in one run
#               would report the larger and attribute it to both.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""One stage of work, so that its peak memory can be attributed to it.

Peak resident memory is a high water mark, so a process that loads a
vocabulary and then encodes reports one number for both and tells you
nothing about either. This program does exactly one stage and exits, and
bench/memory.py runs it once per stage and reads the peak of each child.

The empty stage is the control and it is the most important one. Without it
a reader has no way to tell how much of a figure is the language runtime,
and a number quoted without that control is how a library gets accused of
using twenty times the memory it actually uses.

    mojo run -I src -I bench bench/mem_probe.mojo empty
"""

from std.sys import argv

from harness import PROSE_OFFSET, read_corpus_slice
from knap.tokenizer import load_cl100k_base_tokenizer
from knap.vocab import load_cl100k_base

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime SLICE_MEGABYTES = 80
"""Input size for the encode and count stages.

Large on purpose. At four megabytes the list of token ids is about ten
megabytes, which is invisible against everything else, and the encode and
count stages report the same number. The difference between them only
appears once the ids are the largest thing in the process.
"""


def main() raises:
    """Run one named stage and exit.

    Raises:
        Error: if an input is missing, or if the stage name is unknown. An
            unknown stage is refused rather than treated as the empty one,
            because a silently empty stage would report the control's
            memory under another name.
    """
    var args = argv()
    if len(args) < 2:
        raise Error(
            String(
                "usage: mem_probe <empty|file|vocabulary|tokenizer|count"
                "|encode>"
            )
        )
    var stage = String(args[1])

    if stage == "empty":
        print("stage=empty")
        return

    if stage == "file":
        var handle = open(String(VOCAB), "r")
        var text = handle.read()
        handle.close()
        print("stage=file bytes=", text.byte_length(), sep="")
        return

    if stage == "vocabulary":
        var vocabulary = load_cl100k_base(String(VOCAB))
        print("stage=vocabulary merges=", vocabulary.merge_count(), sep="")
        return

    if stage == "tokenizer":
        var tokenizer = load_cl100k_base_tokenizer(String(VOCAB))
        print("stage=tokenizer ranks=", tokenizer.ranks.size(), sep="")
        return

    if stage == "count" or stage == "encode":
        var limit = SLICE_MEGABYTES * 1024 * 1024
        var data = read_corpus_slice(String(CORPUS), PROSE_OFFSET, limit)
        var tokenizer = load_cl100k_base_tokenizer(String(VOCAB))

        if stage == "count":
            var counted = tokenizer.count_ordinary_bytes(Span(data))
            print("stage=count tokens=", counted, sep="")
            return

        var ids = tokenizer.encode_ordinary_bytes(Span(data))
        print("stage=encode tokens=", len(ids), sep="")
        return

    raise Error(String(t"mem_probe: unknown stage '{stage}'"))


# =============================================================================
# End of file: bench/mem_probe.mojo
# =============================================================================
