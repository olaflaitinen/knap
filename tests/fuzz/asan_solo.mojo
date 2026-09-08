# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/fuzz/asan_solo.mojo
# Purpose     : Exercises Knap over generated input with no Python in the
#               process, so a sanitizer run needs no suppressions.
# Stage       : Milestone M4, differential fuzzing. See docs/ROADMAP.md
# Depends on  : The generators, and Knap itself. Deliberately not the
#               harness, because the harness imports the reference.
# Invariants  : Nothing here starts an interpreter. Any leak or memory error
#               this run reports belongs to Knap.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Run Knap alone over generated input, for the sanitizers.

The differential fuzzer embeds a CPython interpreter so that it can call
tiktoken. That interpreter is never finalised, and neither CPython nor the
tiktoken extension frees its tables at exit, so a leak checker reports
several megabytes on every run of it. Those reports are real, and they are
not Knap's.

This driver exists to remove the ambiguity. It takes the same generators and
drives the same encode and decode paths, but it never imports a Python
module, so nothing in the process is anyone else's allocation. A leak
reported here has exactly one owner. That is why this run is checked with no
suppression file at all, while the differential run needs one.

The two together give the property that matters:

  * This run proves Knap does not leak and does not corrupt memory.
  * The differential run proves parity holds while the sanitizer watches,
    with the reference implementation's own allocations suppressed by name.

Neither claim is strong enough alone. Suppressing by name would hide a Knap
leak that happened to sit under a suppressed frame, and a run without the
reference cannot check parity at all.

Usage:

    mojo run -I src -I tests/fuzz tests/fuzz/asan_solo.mojo
        <seed> <count> <vocabulary path> [encoding]

Every run is a pure function of its seed, exactly as the fuzzer is.
"""

from std.sys import argv

from knap.pretokenize.utf8 import decode_at
from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_o200k_base_tokenizer,
)

from generators import KIND_COUNT, Rng, generate, kind_name


def round_trip_failure(
    tokenizer: Tokenizer, data: Span[UInt8, _]
) raises -> String:
    """Encode and decode one input, checking the bytes survive.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.

    Returns:
        An empty string when the round trip held, or a description of the
        first difference.

    Raises:
        Error: if encoding or decoding fails outright.

    Deliberately duplicated from the harness rather than imported. The
    harness imports the reference implementation at module scope, and the
    single promise this file makes is that no interpreter starts here.
    """
    var ids = tokenizer.encode_ordinary_bytes(data)
    var back = tokenizer.decode_bytes(ids)

    if len(back) != len(data):
        return String(
            t"round trip changed the length from {len(data)} to {len(back)}"
        )
    for index in range(len(data)):
        if back[index] != data[index]:
            return String(t"round trip altered byte {index}")
    return String("")


def main() raises:
    """Drive Knap over generated input and report what the run covered.

    Raises:
        Error: if the arguments are missing, if the vocabulary cannot be
            loaded, or if a round trip fails. Raising makes a bad run a
            failing process, which is what continuous integration needs.
    """
    var args = argv()
    if len(args) < 4:
        raise Error(
            String(
                "usage: asan_solo <seed> <count> <vocabulary path>"
                " [cl100k_base|o200k_base]"
            )
        )

    var seed = UInt64(Int(String(args[1])))
    var count = Int(String(args[2]))
    var vocabulary_path = String(args[3])
    var encoding_name = String("cl100k_base")
    if len(args) > 4:
        encoding_name = String(args[4])

    var tokenizer: Tokenizer
    if encoding_name == "o200k_base":
        tokenizer = load_o200k_base_tokenizer(vocabulary_path)
    else:
        tokenizer = load_cl100k_base_tokenizer(vocabulary_path)

    var rng = Rng(seed)
    var round_tripped = 0
    var tokens = 0

    for index in range(count):
        var kind = rng.below(KIND_COUNT)
        var data = List[UInt8]()
        generate(kind, rng, data)

        # Encoding is driven twice on purpose. Once through the byte entry
        # point, which every input can take, and once through the string
        # entry point when the bytes happen to be well formed, because the
        # two do not allocate identically.
        var failure = round_trip_failure(tokenizer, Span(data))
        if failure != "":
            print("FAILURE")
            print("  seed      :", seed)
            print("  index     :", index)
            print("  generator :", kind_name(kind))
            print("  failure   :", failure)
            raise Error(
                String(t"knap asan_solo: failure at index {index}: {failure}")
            )
        round_tripped += 1

        if is_well_formed(Span(data)):
            var text = String(unsafe_from_utf8=Span(data))
            tokens += len(tokenizer.encode_ordinary(text))

    print(
        "RESULT seed=",
        seed,
        " generated=",
        count,
        " round_tripped=",
        round_tripped,
        " tokens=",
        tokens,
        sep="",
    )
    print("  no interpreter was started, encoding:", encoding_name)


def is_well_formed(data: Span[UInt8, _]) -> Bool:
    """Report whether a byte sequence decodes as well formed UTF-8.

    Args:
        data: The bytes to check.

    Returns:
        True when every sequence is well formed.

    Duplicated from the harness for the same reason as the round trip check.
    """
    var position = 0
    while position < len(data):
        var step = decode_at(data, position)
        if step.width == 0:
            return False
        if not step.valid:
            return False
        position += step.width
    return True


# =============================================================================
# End of file: tests/fuzz/asan_solo.mojo
# =============================================================================
