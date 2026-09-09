# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_flat_vocab.mojo
# Purpose     : Tests the contiguous token store: construction validation,
#               single token access, and the decode path.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : knap.flat_vocab
# Invariants  : These tests use hand built vocabularies only, so they run
#               without any fetched file.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for FlatVocab, the contiguous token byte store.

Everything here is built by hand rather than loaded, so these tests run
without fetching a vocabulary and they fail for exactly one reason: FlatVocab
itself is wrong.

The emphasis is on the construction time validation. FlatVocab promises that
every token span is inside the buffer, and the decode path relies on that
promise instead of checking on every read. A constructor that accepted a bad
span would turn a loading mistake into an out of bounds read much later.
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.flat_vocab import FlatVocab


def build_sample() raises -> FlatVocab:
    """Build a small three token vocabulary for the tests below.

    Returns:
        A FlatVocab holding "Hi", "!", and a reserved id.

    Raises:
        Error: never, since the arrays below are consistent by construction.

    The third entry has zero length, which marks it as reserved rather than
    empty: an id inside the space with nothing assigned to it.

    This docstring used to say that zero length entries are legal and occur
    in real vocabularies. That was written without being checked and it is
    false. No token in any of the seven shipped encodings is empty; the
    shortest is one byte in all of them. An empty merge token would be
    meaningless anyway, since it matches at every position and the merge
    loop would never terminate on it.

    The length is now the marker for a reserved id, which p50k_base needs at
    rank 50256. The correction is recorded rather than quietly applied,
    because a claim that survived in this repository without being tested is
    worth noticing.
    """
    var data = List[UInt8]()
    data.append(UInt8(72))  # H
    data.append(UInt8(105))  # i
    data.append(UInt8(33))  # !

    var offsets: List[Int] = [0, 2, 3]
    var lengths: List[Int] = [2, 1, 0]
    return FlatVocab(data^, offsets^, lengths^)


def test_size_and_token_lengths() raises:
    """Check the reported size and per token lengths.

    Raises:
        Error: if a size or a length is wrong.
    """
    var vocabulary = build_sample()
    assert_equal(vocabulary.size(), 3)
    assert_equal(vocabulary.token_length(0), 2)
    assert_equal(vocabulary.token_length(1), 1)
    assert_equal(vocabulary.token_length(2), 0)


def test_token_bytes_returns_exact_bytes() raises:
    """Check that single token access returns the stored bytes.

    Raises:
        Error: if any token's bytes differ from what was stored.
    """
    var vocabulary = build_sample()

    var first = vocabulary.token_bytes(0)
    assert_equal(len(first), 2)
    assert_equal(first[0], UInt8(72))
    assert_equal(first[1], UInt8(105))

    var second = vocabulary.token_bytes(1)
    assert_equal(len(second), 1)
    assert_equal(second[0], UInt8(33))


def test_a_reserved_id_refuses_to_decode() raises:
    """An id with no bytes is not an empty token and does not decode.

    Raises:
        Error: if it returns empty bytes instead of refusing.

    The distinction matters because the two failures look identical to a
    caller until something downstream is wrong. An empty result silently
    shortens a decoded document. A refusal says which id was missing.

    p50k_base is the encoding that makes this real: rank 50256 is reserved
    for its special token and has no merge bytes behind it.
    """
    var vocabulary = build_sample()

    assert_true(vocabulary.is_assigned(0), String("id 0 should be assigned"))
    assert_true(vocabulary.is_assigned(1), String("id 1 should be assigned"))
    assert_true(
        not vocabulary.is_assigned(2), String("id 2 should be reserved")
    )

    var refused = False
    try:
        _ = vocabulary.token_bytes(2)
    except:
        refused = True
    assert_true(refused, String("token_bytes should refuse a reserved id"))

    var appended = False
    var out = List[UInt8]()
    try:
        vocabulary.append_token(2, out)
    except:
        appended = True
    assert_true(appended, String("append_token should refuse a reserved id"))


def test_decode_concatenates_in_order() raises:
    """Check that decoding a sequence concatenates its tokens in order.

    Raises:
        Error: if the decoded bytes or text differ from the expectation.
    """
    var vocabulary = build_sample()

    var ids: List[Int] = [0, 1]
    assert_equal(vocabulary.decode(ids), String("Hi!"))

    # Repeats and the zero length token must both behave.
    var repeated: List[Int] = [1, 2, 1]
    assert_equal(vocabulary.decode(repeated), String("!!"))

    var empty: List[Int] = []
    assert_equal(len(vocabulary.decode_bytes(empty)), 0)


def test_append_token_writes_into_caller_buffer() raises:
    """Check the append primitive the decode loop is built on.

    Raises:
        Error: if the buffer does not receive the expected bytes.

    append_token exists so that decoding a stream does not allocate one list
    per token, so the test appends twice into one buffer.
    """
    var vocabulary = build_sample()
    var buffer = List[UInt8]()

    vocabulary.append_token(0, buffer)
    vocabulary.append_token(1, buffer)

    assert_equal(len(buffer), 3)
    assert_equal(buffer[0], UInt8(72))
    assert_equal(buffer[2], UInt8(33))


def test_out_of_range_ids_raise() raises:
    """Check that every accessor rejects an id outside the vocabulary.

    Raises:
        Error: if any accessor accepts an invalid id.

    Negative and past the end are both checked, on every entry point, because
    an accessor that forgot its bounds test would otherwise read whatever
    happened to sit next to the buffer.
    """
    var vocabulary = build_sample()

    var raised_negative = False
    try:
        var ignored = vocabulary.token_bytes(-1)
    except:
        raised_negative = True
    assert_true(raised_negative, String("token_bytes(-1) should raise"))

    var raised_past_end = False
    try:
        var ignored = vocabulary.token_bytes(3)
    except:
        raised_past_end = True
    assert_true(raised_past_end, String("token_bytes(3) should raise"))

    var raised_length = False
    try:
        var ignored = vocabulary.token_length(99)
    except:
        raised_length = True
    assert_true(raised_length, String("token_length(99) should raise"))

    var raised_decode = False
    try:
        var bad: List[Int] = [0, 42]
        var ignored = vocabulary.decode_bytes(bad)
    except:
        raised_decode = True
    assert_true(
        raised_decode, String("decode_bytes with a bad id should raise")
    )


def test_inconsistent_arrays_are_rejected() raises:
    """Check that the constructor refuses arrays it cannot honour.

    Raises:
        Error: if the constructor accepts an inconsistent vocabulary.

    This is the check that lets the decode path skip bounds testing. Two
    cases are covered: parallel arrays of different lengths, and a token span
    that runs past the end of the buffer.
    """
    var mismatched = False
    try:
        var data = List[UInt8]()
        data.append(UInt8(65))
        var offsets: List[Int] = [0, 1]
        var lengths: List[Int] = [1]
        var ignored = FlatVocab(data^, offsets^, lengths^)
    except:
        mismatched = True
    assert_true(
        mismatched, String("offsets and lengths of unequal size must raise")
    )

    var overrun = False
    try:
        var data = List[UInt8]()
        data.append(UInt8(65))
        # One byte of data, but the entry claims four.
        var offsets: List[Int] = [0]
        var lengths: List[Int] = [4]
        var ignored = FlatVocab(data^, offsets^, lengths^)
    except:
        overrun = True
    assert_true(overrun, String("a span past the end of data must raise"))


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_flat_vocab.mojo
# =============================================================================
