# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_bpe.mojo
# Purpose     : Unit tests for the merge loop, using a synthetic vocabulary
#               small enough to reason about by hand.
# Stage       : Milestone M3, BPE merge and encode. See docs/ROADMAP.md
# Depends on  : knap.bpe, knap.ranks, knap.flat_vocab
# Invariants  : The synthetic vocabulary always holds all 256 single bytes,
#               because a byte level vocabulary without them cannot encode.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Unit tests for the byte pair merge loop.

The real encodings have a hundred thousand merges, which makes their
behaviour impossible to predict by hand. These tests use a vocabulary with
all 256 single bytes plus three deliberate merges, so every expected result
below can be derived on paper from the merge rule alone.

That matters because the merge rule has one subtlety worth testing directly:
each round picks the **globally** lowest ranked adjacent pair, not the
leftmost ranked one. A loop that merged left to right would agree with this
one on most input and differ on exactly the cases these tests cover.
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.bpe import merge_piece_to_list
from knap.flat_vocab import FlatVocab
from knap.ranks import RankTable, UNRANKED

comptime BYTE_A: Int = 0x61
"""Code point and byte value of the letter a."""

comptime BYTE_B: Int = 0x62
"""Code point and byte value of the letter b."""

comptime BYTE_C: Int = 0x63
"""Code point and byte value of the letter c."""


def build_synthetic_ranks() raises -> RankTable:
    """Build a small vocabulary whose merges can be reasoned about by hand.

    Returns:
        A rank table over 256 single bytes plus three merges.

    Raises:
        Error: if the vocabulary is inconsistent, which would be a defect in
            this helper rather than in the code under test.

    The merges, in rank order, are "ab" at 256, "bc" at 257, and "abc" at
    258. Lower ranks are applied first, so "ab" always wins over "bc" when
    both are available.
    """
    var data = List[UInt8]()
    var offsets = List[Int]()
    var lengths = List[Int]()

    # Ids 0 through 255 are the single bytes, in value order.
    for value in range(256):
        offsets.append(len(data))
        lengths.append(1)
        data.append(UInt8(value))

    # Id 256 is "ab".
    offsets.append(len(data))
    lengths.append(2)
    data.append(UInt8(BYTE_A))
    data.append(UInt8(BYTE_B))

    # Id 257 is "bc".
    offsets.append(len(data))
    lengths.append(2)
    data.append(UInt8(BYTE_B))
    data.append(UInt8(BYTE_C))

    # Id 258 is "abc".
    offsets.append(len(data))
    lengths.append(3)
    data.append(UInt8(BYTE_A))
    data.append(UInt8(BYTE_B))
    data.append(UInt8(BYTE_C))

    var vocabulary = FlatVocab(data^, offsets^, lengths^)
    return RankTable(vocabulary)


def bytes_of(text: String) -> List[UInt8]:
    """Copy a string's bytes into a list.

    Args:
        text: The text to copy.

    Returns:
        Its bytes.
    """
    var raw = text.as_bytes()
    var out = List[UInt8](capacity=len(raw))
    for index in range(len(raw)):
        out.append(raw[index])
    return out^


def test_single_byte_piece_is_looked_up_directly() raises:
    """Check that a one byte piece needs no merging.

    Raises:
        Error: if the token id is wrong.
    """
    var ranks = build_synthetic_ranks()
    var data = bytes_of(String("a"))
    var ids = merge_piece_to_list(ranks, Span(data), 0, 1)
    assert_equal(len(ids), 1)
    assert_equal(ids[0], BYTE_A)


def test_empty_piece_produces_nothing() raises:
    """Check that an empty range appends no tokens.

    Raises:
        Error: if an empty piece produces a token.
    """
    var ranks = build_synthetic_ranks()
    var data = bytes_of(String("a"))
    var ids = merge_piece_to_list(ranks, Span(data), 0, 0)
    assert_equal(len(ids), 0)


def test_merges_are_applied_in_rank_order() raises:
    """Check that the lowest ranked pair merges first, then the result.

    Raises:
        Error: if the merge order differs.

    Working it through by hand for "abc": the adjacent pairs are "ab" at
    rank 256 and "bc" at rank 257, so "ab" merges first. That leaves the
    parts "ab" and "c", whose only pair is "abc" at rank 258, which merges.
    The result is one token.
    """
    var ranks = build_synthetic_ranks()
    var data = bytes_of(String("abc"))
    var ids = merge_piece_to_list(ranks, Span(data), 0, 3)
    assert_equal(len(ids), 1)
    assert_equal(ids[0], 258)


def test_unranked_pairs_stop_the_loop() raises:
    """Check that the loop halts when no adjacent pair is ranked.

    Raises:
        Error: if unmergeable bytes are not emitted individually.

    The pair "ca" has no rank in this vocabulary, so "ca" must come out as
    two separate single byte tokens rather than being forced together.
    """
    var ranks = build_synthetic_ranks()
    var data = bytes_of(String("ca"))
    var ids = merge_piece_to_list(ranks, Span(data), 0, 2)
    assert_equal(len(ids), 2)
    assert_equal(ids[0], BYTE_C)
    assert_equal(ids[1], BYTE_A)


def test_lowest_rank_wins_over_leftmost() raises:
    """Check that the globally lowest pair merges, not the leftmost one.

    Raises:
        Error: if the loop merges left to right instead.

    This is the case that separates a correct merge loop from a plausible
    one. In "cab" the adjacent pairs are "ca", which is unranked, and "ab"
    at rank 256. A loop that took the leftmost ranked pair would still get
    this right, so the stronger case is "abc" preceded by a byte: in "abca"
    the pairs are "ab" at 256, "bc" at 257, and "ca" unranked. Merging by
    lowest rank gives "ab" first.
    """
    var ranks = build_synthetic_ranks()

    var cab = bytes_of(String("cab"))
    var cab_ids = merge_piece_to_list(ranks, Span(cab), 0, 3)
    assert_equal(len(cab_ids), 2)
    assert_equal(cab_ids[0], BYTE_C)
    assert_equal(cab_ids[1], 256)

    # "abca": "ab" merges first at rank 256, leaving "ab", "c", "a". The
    # only remaining pair is "abc" at 258, which merges, leaving "abc" and
    # "a". The pair "abca" is unranked, so the loop stops.
    var abca = bytes_of(String("abca"))
    var abca_ids = merge_piece_to_list(ranks, Span(abca), 0, 4)
    assert_equal(len(abca_ids), 2)
    assert_equal(abca_ids[0], 258)
    assert_equal(abca_ids[1], BYTE_A)


def test_pieces_are_merged_independently() raises:
    """Check that merging respects the range it is given.

    Raises:
        Error: if the loop reads outside its range.

    The merge loop must never look past the piece it was handed, because
    pre-tokenization decides which merges are reachable. Handing it the
    middle of a longer buffer proves it honours the bounds.
    """
    var ranks = build_synthetic_ranks()
    var data = bytes_of(String("cabc"))

    # Only the "ab" in the middle, which must merge to one token.
    var middle = merge_piece_to_list(ranks, Span(data), 1, 3)
    assert_equal(len(middle), 1)
    assert_equal(middle[0], 256)

    # The trailing "bc", which must not reach back for the leading "a".
    var tail = merge_piece_to_list(ranks, Span(data), 2, 4)
    assert_equal(len(tail), 1)
    assert_equal(tail[0], 257)


def test_rank_lookup_reports_unranked() raises:
    """Check that the rank table distinguishes absent from present.

    Raises:
        Error: if an absent sequence is reported as ranked.
    """
    var ranks = build_synthetic_ranks()
    var data = bytes_of(String("abc"))

    assert_equal(ranks.rank_of(Span(data), 0, 2), 256)
    assert_equal(ranks.rank_of(Span(data), 1, 3), 257)
    assert_equal(ranks.rank_of(Span(data), 0, 3), 258)

    var unranked = bytes_of(String("ca"))
    assert_equal(ranks.rank_of(Span(unranked), 0, 2), UNRANKED)
    assert_true(ranks.size() >= 256 + 3, String("table is too small"))


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_bpe.mojo
# =============================================================================
