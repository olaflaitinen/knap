# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/fuzz/fuzz_main.mojo
# Purpose     : Fuzzer entry point. Takes a seed and a count and reports what
#               it compared.
# Stage       : Milestone M4, differential fuzzing. See docs/ROADMAP.md
# Depends on  : generators.mojo, harness.mojo, knap.tokenizer
# Invariants  : Output is machine readable on the last line, so the Python
#               driver can aggregate many shards without parsing prose.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Differential fuzzer entry point for Knap.

Generates inputs, runs them through Knap and tiktoken in one process, and
reports the first divergence together with the bytes that produced it.

Usage:

    mojo run -I src tests/fuzz/fuzz_main.mojo <seed> <count> <vocab> [encoding]

The encoding defaults to cl100k_base. Every run is a pure function of its
seed, so a reported result can be replayed exactly. A fuzzing result that
cannot be reproduced is an anecdote, not evidence.

The final line is machine readable and looks like:

    RESULT seed=1 generated=1000 compared=812 round_tripped=188 \
divergences=0

so that scripts/../tests/fuzz/run_fuzz.py can aggregate many shards without
parsing the human readable part.
"""

from std.python import Python
from std.sys import argv

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

from generators import KIND_COUNT, Rng, generate, kind_name
from harness import FuzzStats, check_one, to_hex


def main() raises:
    """Run one fuzzing shard and report what it found.

    Raises:
        Error: if the arguments are missing, if the vocabulary cannot be
            loaded, or if a divergence is found. Raising on divergence is
            deliberate: it makes a failing shard a failing process, which is
            what the driver and continuous integration both need.
    """
    var args = argv()
    if len(args) < 4:
        raise Error(
            String(
                "usage: fuzz_main <seed> <count> <vocabulary path>"
                " <encoding>"
                " where <encoding> is one of cl100k_base, o200k_base,"
                " o200k_harmony, gpt2, r50k_base, p50k_base, p50k_edit."
            )
        )

    var seed = UInt64(Int(String(args[1])))
    var count = Int(String(args[2]))
    var vocabulary_path = String(args[3])
    var encoding_name = String("cl100k_base")
    if len(args) > 4:
        encoding_name = String(args[4])

    # The driver passes the vocabulary path and the encoding name
    # separately, because three of the seven load from a file named after
    # another encoding and a name is not enough to find the file.
    var tokenizer: Tokenizer
    if encoding_name == "o200k_base":
        tokenizer = load_o200k_base_tokenizer(vocabulary_path)
    elif encoding_name == "o200k_harmony":
        tokenizer = load_o200k_harmony_tokenizer(vocabulary_path)
    elif encoding_name == "gpt2":
        tokenizer = load_gpt2_tokenizer(vocabulary_path)
    elif encoding_name == "r50k_base":
        tokenizer = load_r50k_base_tokenizer(vocabulary_path)
    elif encoding_name == "p50k_base":
        tokenizer = load_p50k_base_tokenizer(vocabulary_path)
    elif encoding_name == "p50k_edit":
        tokenizer = load_p50k_edit_tokenizer(vocabulary_path)
    elif encoding_name == "cl100k_base":
        tokenizer = load_cl100k_base_tokenizer(vocabulary_path)
    else:
        raise Error(
            String(
                t"unknown encoding '{encoding_name}'. A silent fall back to"
                t" cl100k_base would report a clean run for an encoding that"
                t" was never fuzzed."
            )
        )

    var tiktoken = Python.import_module("tiktoken")
    var encoding = tiktoken.get_encoding(encoding_name)

    var rng = Rng(seed)
    var stats = FuzzStats(0, 0, 0, 0)

    for index in range(count):
        var kind = rng.below(KIND_COUNT)
        var data = List[UInt8]()
        generate(kind, rng, data)

        var failure = check_one(tokenizer, encoding, Span(data), stats)
        if failure != "":
            # Everything a person needs to reproduce this exact case.
            print("DIVERGENCE")
            print("  seed      :", seed)
            print("  index     :", index)
            print("  generator :", kind_name(kind))
            print("  bytes     :", len(data))
            print("  hex       :", to_hex(Span(data)))
            print("  failure   :", failure)
            print(
                "RESULT seed=",
                seed,
                " generated=",
                index + 1,
                " compared=",
                stats.compared,
                " round_tripped=",
                stats.round_tripped,
                " divergences=",
                stats.divergences,
                sep="",
            )
            raise Error(
                String(t"knap fuzz: divergence at index {index}: {failure}")
            )

    print(
        "RESULT seed=",
        seed,
        " generated=",
        count,
        " compared=",
        stats.compared,
        " round_tripped=",
        stats.round_tripped,
        " divergences=",
        stats.divergences,
        sep="",
    )
    print(
        "  refusal checks:",
        stats.refusals_checked,
        " encoding:",
        encoding_name,
    )


# =============================================================================
# End of file: tests/fuzz/fuzz_main.mojo
# =============================================================================
