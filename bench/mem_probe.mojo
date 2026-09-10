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
    mojo run -I src -I bench bench/mem_probe.mojo tokenizer o200k_harmony
"""

from std.sys import argv

from harness import PROSE_OFFSET, read_corpus_slice
from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_gpt2_tokenizer,
    load_o200k_base_tokenizer,
    load_o200k_harmony_tokenizer,
    load_p50k_base_tokenizer,
    load_p50k_edit_tokenizer,
    load_r50k_base_tokenizer,
)
from knap.vocab import Vocabulary, load_cl100k_base

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime VOCAB_DIR = "tests/fixtures/vocabs/"
"""Directory holding the fetched vocabularies."""

comptime SLICE_MEGABYTES = 80
"""Input size for the encode and count stages.

Large on purpose. At four megabytes the list of token ids is about ten
megabytes, which is invisible against everything else, and the encode and
count stages report the same number. The difference between them only
appears once the ids are the largest thing in the process.
"""


def vocabulary_path(encoding: String) raises -> String:
    """Return the file one encoding is stored in.

    Args:
        encoding: The encoding name.

    Returns:
        The path to its .tiktoken file.

    Raises:
        Error: if the name is not one of the seven.

    Seven names, four files. Three of the seven are stored under another
    encoding's name, so this cannot be derived from the name.
    """
    var stem = encoding
    if encoding == "o200k_harmony":
        stem = String("o200k_base")
    elif encoding == "p50k_edit":
        stem = String("p50k_base")
    elif encoding == "gpt2":
        stem = String("r50k_base")
    elif (
        encoding != "cl100k_base"
        and encoding != "o200k_base"
        and encoding != "r50k_base"
        and encoding != "p50k_base"
    ):
        raise Error(String(t"mem_probe: unknown encoding '{encoding}'"))
    return String(VOCAB_DIR) + stem + String(".tiktoken")


def load_named(encoding: String) raises -> Tokenizer:
    """Load one encoding by name.

    Args:
        encoding: The encoding name.

    Returns:
        A ready tokenizer.

    Raises:
        Error: if the name is unknown or the vocabulary will not load.
    """
    var path = vocabulary_path(encoding)
    if encoding == "o200k_base":
        return load_o200k_base_tokenizer(path)
    if encoding == "o200k_harmony":
        return load_o200k_harmony_tokenizer(path)
    if encoding == "gpt2":
        return load_gpt2_tokenizer(path)
    if encoding == "r50k_base":
        return load_r50k_base_tokenizer(path)
    if encoding == "p50k_base":
        return load_p50k_base_tokenizer(path)
    if encoding == "p50k_edit":
        return load_p50k_edit_tokenizer(path)
    return load_cl100k_base_tokenizer(path)


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
                "|encode> [encoding]"
            )
        )
    var stage = String(args[1])
    var encoding = String("cl100k_base")
    if len(args) > 2:
        encoding = String(args[2])

    if stage == "empty":
        print("stage=empty")
        return

    if stage == "file":
        var handle = open(vocabulary_path(encoding), "r")
        var text = handle.read()
        handle.close()
        print("stage=file bytes=", text.byte_length(), sep="")
        return

    if stage == "vocabulary":
        var vocabulary = load_cl100k_base(vocabulary_path(encoding))
        print("stage=vocabulary merges=", vocabulary.merge_count(), sep="")
        return

    if stage == "tokenizer":
        var tokenizer = load_named(encoding)
        print("stage=tokenizer ranks=", tokenizer.ranks.size(), sep="")
        return

    if stage == "count" or stage == "encode":
        var limit = SLICE_MEGABYTES * 1024 * 1024
        var data = read_corpus_slice(String(CORPUS), PROSE_OFFSET, limit)
        var tokenizer = load_named(encoding)

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
