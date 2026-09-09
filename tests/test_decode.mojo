# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_decode.mojo
# Purpose     : Milestone M1 gate. Decodes every token id in all seven
#               shipped encodings and compares against a tiktoken fixture.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : knap.vocab, knap.flat_vocab, std.base64
# Invariants  : Every id in the space is checked, including the ones tiktoken
#               refuses. An id the reference rejects must raise here too.
#               The number of refused ids is asserted exactly, not loosely.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Decode parity tests for Knap.

This file is the milestone M1 acceptance gate. It decodes every single token
id in all seven shipped encodings, 702463 ids in total, and compares the
bytes against a fixture generated from tiktoken by
scripts/gen_encode_golden.py.

Two properties are checked, and the second matters as much as the first:

  1. Every assigned id decodes to byte identical output.
  2. Every unassigned id raises. An implementation that helpfully returned
     empty bytes for a hole would diverge from the reference exactly where a
     caller most needs to be told something is wrong.

The count of holes is asserted exactly rather than as "at least one", which
is what this file used to do. That was written when only two encodings were
shipped and both had holes. Four of the seven have none: gpt2, r50k_base,
p50k_base and p50k_edit fill their id space completely, and o200k_harmony
fills every one of the nineteen holes o200k_base leaves, because its 1091
special tokens land on exactly those ids and then continue past them.

A loose assertion would have passed on all seven while checking nothing on
four of them. The exact counts are 16 for cl100k_base, 19 for o200k_base,
and zero for the rest, and each was read off the reference rather than
predicted.

Run it after fetching the vocabularies and generating the goldens:

    python scripts/fetch_vocabs.py
    python scripts/gen_encode_golden.py
    mojo run -I src tests/test_decode.mojo
"""

from std.base64 import b64decode
from std.testing import assert_equal, assert_true, TestSuite

from knap.vocab import (
    Vocabulary,
    load_cl100k_base,
    load_gpt2,
    load_o200k_base,
    load_o200k_harmony,
    load_p50k_base,
    load_p50k_edit,
    load_r50k_base,
)

# Paths are relative to the repository root, which is where the test runner
# is expected to be invoked from.
comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime CL100K_GOLDEN = "tests/golden/cl100k_base/decode_single_tokens.jsonl"
"""Path to the generated cl100k_base decode golden fixture."""

comptime O200K_GOLDEN = "tests/golden/o200k_base/decode_single_tokens.jsonl"
"""Path to the generated o200k_base decode golden fixture."""

comptime R50K_VOCAB = "tests/fixtures/vocabs/r50k_base.tiktoken"
"""Path to the fetched r50k_base merge vocabulary, shared with gpt2."""

comptime P50K_VOCAB = "tests/fixtures/vocabs/p50k_base.tiktoken"
"""Path to the fetched p50k_base vocabulary, shared with p50k_edit."""

comptime HARMONY_GOLDEN = (
    "tests/golden/o200k_harmony/decode_single_tokens.jsonl"
)
"""Path to the generated o200k_harmony decode golden fixture."""

comptime GPT2_GOLDEN = "tests/golden/gpt2/decode_single_tokens.jsonl"
"""Path to the generated gpt2 decode golden fixture."""

comptime R50K_GOLDEN = "tests/golden/r50k_base/decode_single_tokens.jsonl"
"""Path to the generated r50k_base decode golden fixture."""

comptime P50K_GOLDEN = "tests/golden/p50k_base/decode_single_tokens.jsonl"
"""Path to the generated p50k_base decode golden fixture."""

comptime P50K_EDIT_GOLDEN = "tests/golden/p50k_edit/decode_single_tokens.jsonl"
"""Path to the generated p50k_edit decode golden fixture."""


@fieldwise_init
struct GoldenEntry(Copyable, Movable):
    """One line of a decode golden fixture."""

    var token_id: Int
    """The token id this line describes."""

    var assigned: Bool
    """False when the reference implementation refuses to decode this id."""

    var encoded: String
    """Base64 of the expected bytes, empty when the id is unassigned."""


# -----------------------------------------------------------------------------
# Golden fixture reading
#
# The fixture is JSON Lines, but this is deliberately not a JSON parser. It
# reads exactly the shape scripts/gen_encode_golden.py writes, with no spaces
# and only two keys:
#
#     {"id":15339,"b64":"aGVsbG8="}
#     {"id":100256,"b64":null}
#
# Splitting on a comma and then a colon is safe here because the only values
# are an integer and base64, and the base64 alphabet contains neither
# character. Writing a general JSON parser to read a file this project also
# generates would be more code and more risk for no benefit. If the generator
# changes shape, this reader changes with it.
# -----------------------------------------------------------------------------


def parse_golden_line(line: String) raises -> GoldenEntry:
    """Parse one line of a decode golden fixture.

    Args:
        line: A single line as written by scripts/gen_encode_golden.py.

    Returns:
        The parsed entry.

    Raises:
        Error: if the line does not have the expected two field shape. A
            malformed fixture is reported rather than skipped, because a
            silently dropped line would weaken the gate without failing it.
    """
    var fields = line.strip().split(",")
    if len(fields) != 2:
        raise Error(
            String(
                t"golden line has {len(fields)} comma separated fields,"
                t" expected 2: {line}"
            )
        )

    # Left field is {"id":N
    var left = String(fields[0]).split(":")
    if len(left) != 2:
        raise Error(String(t"golden line has a malformed id field: {line}"))
    var token_id = Int(String(left[1]).strip())

    # Right field is "b64":"XXXX"} or "b64":null}
    var right = String(fields[1]).split(":")
    if len(right) != 2:
        raise Error(String(t"golden line has a malformed b64 field: {line}"))

    var value = String(String(right[1]).strip().removesuffix("}"))
    if value == "null":
        return GoldenEntry(token_id, False, String(""))

    # Strip the surrounding quotation marks. Base64 never contains one, so
    # no escape handling is needed.
    var encoded = String(String(value.removeprefix('"')).removesuffix('"'))
    return GoldenEntry(token_id, True, encoded)


def check_vocabulary_against_golden(
    vocabulary: Vocabulary, golden_path: String, expected_holes: Int
) raises -> Int:
    """Compare every id in one vocabulary against its golden fixture.

    Args:
        vocabulary: The loaded vocabulary under test.
        golden_path: Path to that encoding's decode golden.
        expected_holes: How many ids the reference refuses to decode. It is
            asserted exactly, so a fixture that lost its holes fails here
            instead of quietly weakening the gate.

    Returns:
        The number of ids checked.

    Raises:
        Error: if the fixture is missing, if any assigned id decodes to
            different bytes, or if any unassigned id fails to raise.

    The comparison is on bytes, never on text. Many token byte strings are
    not valid UTF-8 on their own, because a multi-byte character is
    routinely split across several tokens, so comparing decoded Strings
    would compare something other than what parity is defined on.
    """
    var text: String
    try:
        var handle = open(golden_path, "r")
        text = handle.read()
        handle.close()
    except:
        var message = String(t"knap tests: cannot open '{golden_path}'.")
        message += " Generate it with 'python scripts/gen_encode_golden.py'."
        raise Error(message)

    var lines = text.splitlines()
    var checked = 0
    var unassigned_seen = 0

    for index in range(len(lines)):
        var raw = String(lines[index])
        if raw.strip().byte_length() == 0:
            continue

        var entry = parse_golden_line(raw)

        if not entry.assigned:
            # The reference refuses this id, so Knap must refuse it too.
            unassigned_seen += 1
            assert_equal(
                vocabulary.is_assigned(entry.token_id),
                False,
                String(
                    t"id {entry.token_id} is unassigned in tiktoken but"
                    t" Knap reports it as assigned"
                ),
            )
            var raised = False
            try:
                var ignored = vocabulary.token_bytes(entry.token_id)
            except:
                raised = True
            assert_true(
                raised,
                String(t"decoding unassigned id {entry.token_id} should raise"),
            )
            checked += 1
            continue

        var expected = b64decode[validate=True](entry.encoded)
        var actual = vocabulary.token_bytes(entry.token_id)

        assert_equal(
            len(actual),
            len(expected),
            String(
                t"id {entry.token_id} decoded to {len(actual)} bytes,"
                t" expected {len(expected)}"
            ),
        )
        for byte_index in range(len(expected)):
            assert_equal(
                actual[byte_index],
                expected[byte_index],
                String(
                    t"id {entry.token_id} byte {byte_index} differs from"
                    t" the tiktoken reference"
                ),
            )
        checked += 1

    # The number of holes is part of the fixture, not an incidental detail.
    # An earlier version of this asserted only that there was at least one,
    # which was true of the two encodings shipped at the time and is false
    # of four of the seven shipped now. The exact count keeps the second
    # half of the gate meaningful for every encoding, including the ones
    # whose id space is completely full.
    assert_equal(
        unassigned_seen,
        expected_holes,
        String(
            t"golden '{golden_path}' recorded {unassigned_seen} unassigned"
            t" ids, expected {expected_holes}"
        ),
    )
    return checked


# -----------------------------------------------------------------------------
# The gate
# -----------------------------------------------------------------------------


def test_cl100k_base_decodes_byte_identically() raises:
    """Check every cl100k_base token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.
    """
    var vocabulary = load_cl100k_base(String(CL100K_VOCAB))
    assert_equal(vocabulary.merge_count(), 100256)
    assert_equal(vocabulary.id_space_size(), 100277)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(CL100K_GOLDEN), 16
    )
    assert_equal(checked, 100277)


def test_o200k_base_decodes_byte_identically() raises:
    """Check every o200k_base token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.
    """
    var vocabulary = load_o200k_base(String(O200K_VOCAB))
    assert_equal(vocabulary.merge_count(), 199998)
    assert_equal(vocabulary.id_space_size(), 200019)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(O200K_GOLDEN), 19
    )
    assert_equal(checked, 200019)


def test_o200k_harmony_decodes_byte_identically() raises:
    """Check every o200k_harmony token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.

    The largest id space of the seven, and the only one where the special
    tokens do most of the work: 1091 of them, against o200k_base's two. They
    land on every one of the nineteen ids o200k_base leaves empty and then
    continue to 201087, so this encoding has no holes at all.
    """
    var vocabulary = load_o200k_harmony(String(O200K_VOCAB))
    assert_equal(vocabulary.merge_count(), 199998)
    assert_equal(vocabulary.id_space_size(), 201088)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(HARMONY_GOLDEN), 0
    )
    assert_equal(checked, 201088)


def test_gpt2_decodes_byte_identically() raises:
    """Check every gpt2 token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.

    Loaded from r50k_base.tiktoken, because the merge ranks are byte
    identical and Knap does not read the GPT-2 era pair of files. This gate
    is what makes that claim testable rather than asserted: if the two
    tables differed anywhere, some id here would decode to the wrong bytes.
    """
    var vocabulary = load_gpt2(String(R50K_VOCAB))
    assert_equal(vocabulary.merge_count(), 50256)
    assert_equal(vocabulary.id_space_size(), 50257)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(GPT2_GOLDEN), 0
    )
    assert_equal(checked, 50257)


def test_r50k_base_decodes_byte_identically() raises:
    """Check every r50k_base token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.
    """
    var vocabulary = load_r50k_base(String(R50K_VOCAB))
    assert_equal(vocabulary.merge_count(), 50256)
    assert_equal(vocabulary.id_space_size(), 50257)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(R50K_GOLDEN), 0
    )
    assert_equal(checked, 50257)


def test_p50k_base_decodes_byte_identically() raises:
    """Check every p50k_base token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.

    The encoding that motivated the reserved id path. Its merge ranks are
    not dense: rank 50256 holds no merge token because the special token
    sits there, and the merges resume at 50257 and run to 50280. Every other
    shipped encoding puts its specials above the merges instead.

    So the id space has no holes even though the merge table does, and this
    gate checks both halves of that at once.
    """
    var vocabulary = load_p50k_base(String(P50K_VOCAB))
    assert_equal(vocabulary.merge_count(), 50281)
    assert_equal(vocabulary.id_space_size(), 50281)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(P50K_GOLDEN), 0
    )
    assert_equal(checked, 50281)


def test_p50k_edit_decodes_byte_identically() raises:
    """Check every p50k_edit token id against the tiktoken reference.

    Raises:
        Error: if any id decodes differently, or if the vocabulary or the
            golden fixture is missing.

    The same vocabulary file as p50k_base with three fill in the middle
    markers stacked above it, so the id space runs three further.
    """
    var vocabulary = load_p50k_edit(String(P50K_VOCAB))
    assert_equal(vocabulary.merge_count(), 50281)
    assert_equal(vocabulary.id_space_size(), 50284)

    var checked = check_vocabulary_against_golden(
        vocabulary, String(P50K_EDIT_GOLDEN), 0
    )
    assert_equal(checked, 50284)


def test_multi_token_sequences_concatenate() raises:
    """Check that decoding a sequence equals concatenating single decodes.

    Raises:
        Error: if a sequence decode differs from the concatenation of its
            parts, or if the empty input is not handled.

    Decoding is defined as concatenation, so this holds by construction. It
    is asserted anyway because it is the property callers actually rely on,
    and because it exercises the buffer sizing path that single token
    decoding never reaches.
    """
    var vocabulary = load_cl100k_base(String(CL100K_VOCAB))

    var ids: List[Int] = [15339, 1917, 100257, 13]
    var joined = vocabulary.decode_bytes(ids)

    var expected = List[UInt8]()
    for index in range(len(ids)):
        var part = vocabulary.token_bytes(ids[index])
        for byte_index in range(len(part)):
            expected.append(part[byte_index])

    assert_equal(len(joined), len(expected))
    for index in range(len(expected)):
        assert_equal(joined[index], expected[index])

    # Empty input returns an empty list, not an error. This is one of the
    # correctness hazards listed in docs/CORRECTNESS.md.
    var empty: List[Int] = []
    assert_equal(len(vocabulary.decode_bytes(empty)), 0)


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_decode.mojo
# =============================================================================
