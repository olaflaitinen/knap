# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_count.mojo
# Purpose     : Holds the counting path to the encoding path. A count is an
#               optimisation, never a second opinion about what a token is.
# Stage       : Milestone M9, the counting fast path. See docs/ROADMAP.md
# Depends on  : knap.tokenizer, knap.cache
# Invariants  : Every assertion here compares count against len(encode) on
#               the same input. Nothing is asserted against a number that
#               was written down by hand.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Counting parity tests for Knap.

`count_ordinary` exists because counting is the most common thing anyone
asks a tokenizer to do and the list of ids is usually thrown away
immediately after its length is read. It walks the same scanner and the same
merge loop and simply does not append.

That makes it an optimisation, and an optimisation of this shape has exactly
one way to be wrong: to disagree with the thing it optimises. So every test
here compares a count against the length of the encode of the same input,
rather than against a number somebody wrote down. A hand written expected
count would drift the first time a vocabulary changed, and worse, it would
still pass if both paths were wrong in the same way.

    mojo run -I src tests/test_count.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.cache import PieceCache
from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_gpt2_tokenizer,
    load_o200k_base_tokenizer,
    load_p50k_base_tokenizer,
)

comptime FIXTURE_DIR = "tests/fixtures/corpus/"
"""Directory holding the committed edge case fixtures."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime R50K_VOCAB = "tests/fixtures/vocabs/r50k_base.tiktoken"
"""Path to the fetched r50k_base merge vocabulary, shared with gpt2."""

comptime P50K_VOCAB = "tests/fixtures/vocabs/p50k_base.tiktoken"
"""Path to the fetched p50k_base vocabulary, shared with p50k_edit."""

comptime END_OF_TEXT = "<|endoftext|>"
"""The special token every shipped encoding defines."""

comptime CACHE_CAPACITY = 4096
"""Entries for the cached counting test. Small enough to stay honest."""


def read_bytes(path: String) raises -> List[UInt8]:
    """Read a whole file as raw bytes.

    Args:
        path: Path to read.

    Returns:
        The file contents.

    Raises:
        Error: if the file cannot be opened.
    """
    var handle = open(path, "r")
    var data = handle.read_bytes()
    handle.close()
    return data^


def fixture_names() -> List[String]:
    """List the committed edge case fixtures.

    Returns:
        Bare file names, including the one that is not valid UTF-8.
    """
    var names: List[String] = [
        String("ascii_en.txt"),
        String("mixed_multilingual.txt"),
        String("code.txt"),
        String("emoji.txt"),
        String("whitespace_edges.txt"),
        String("invalid_utf8.bin"),
    ]
    return names^


def check_counts_match(tokenizer: Tokenizer, label: String) raises -> Int:
    """Compare the count against the encode length on every fixture.

    Args:
        tokenizer: The loaded tokenizer under test.
        label: The encoding name, for the failure message.

    Returns:
        The total number of tokens compared.

    Raises:
        Error: if a count differs from the length of the encode.
    """
    var names = fixture_names()
    var total = 0

    for index in range(len(names)):
        var data = read_bytes(String(FIXTURE_DIR) + names[index])
        var ids = tokenizer.encode_ordinary_bytes(Span(data))
        var counted = tokenizer.count_ordinary_bytes(Span(data))
        assert_equal(
            counted,
            len(ids),
            String(
                t"{label} {names[index]}: counted {counted}, encoding gave"
                t" {len(ids)}"
            ),
        )
        total += counted

    return total


def test_counting_matches_encoding_on_every_fixture() raises:
    """Check the counting path against the encoding path, four behaviours.

    Raises:
        Error: if any count differs from the length of the encode.

    Four rather than seven, because counting walks the ordinary encode path
    and nothing else, and the seven encodings reduce to four distinct
    ordinary behaviours. The special token path is covered separately below,
    and that is where the seven genuinely differ.
    """
    var cl100k = check_counts_match(
        load_cl100k_base_tokenizer(String(CL100K_VOCAB)),
        String("cl100k_base"),
    )
    assert_true(cl100k > 0, String("no cl100k_base tokens were counted"))

    var o200k = check_counts_match(
        load_o200k_base_tokenizer(String(O200K_VOCAB)), String("o200k_base")
    )
    assert_true(o200k > 0, String("no o200k_base tokens were counted"))

    var gpt2 = check_counts_match(
        load_gpt2_tokenizer(String(R50K_VOCAB)), String("gpt2")
    )
    assert_true(gpt2 > 0, String("no gpt2 tokens were counted"))

    var p50k = check_counts_match(
        load_p50k_base_tokenizer(String(P50K_VOCAB)), String("p50k_base")
    )
    assert_true(p50k > 0, String("no p50k_base tokens were counted"))


def test_empty_input_counts_zero() raises:
    """Check that nothing counts as no tokens rather than as an error.

    Raises:
        Error: if empty input does not count zero.

    Empty input is one of the hazards in docs/CORRECTNESS.md, and a counting
    path is a new place for it to go wrong.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var empty = List[UInt8]()
    assert_equal(tokenizer.count_ordinary_bytes(Span(empty)), 0)
    assert_equal(tokenizer.count_ordinary(String("")), 0)


def test_counting_a_marker_as_text_matches_encoding() raises:
    """Check the ordinary count treats a marker as characters, as encode does.

    Raises:
        Error: if the count differs from the length of the encode.

    The ordinary path never emits a special token id, so a marker written
    out in the input counts as the characters that spell it. This is the
    safe default and it is worth a test of its own, because a counting path
    that quietly took the special token branch would return a smaller number
    than the encoder does for the same input.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("before ") + String(END_OF_TEXT) + String(" after")

    var ids = tokenizer.encode_ordinary(text)
    assert_equal(tokenizer.count_ordinary(text), len(ids))


def test_counting_with_an_allowed_marker_matches_encoding() raises:
    """Check the special token count against the special token encode.

    Raises:
        Error: if the count differs from the length of the encode.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("before ") + String(END_OF_TEXT) + String(" after")
    var allowed: List[String] = [String(END_OF_TEXT)]

    var ids = tokenizer.encode(text, allowed)
    assert_equal(tokenizer.count(text, allowed), len(ids))

    # The marker became one token rather than the several its characters
    # would have taken, so the two paths must give different numbers here.
    # If they agreed, the test above and this one would both pass while the
    # policy did nothing.
    assert_true(
        tokenizer.count(text, allowed) < tokenizer.count_ordinary(text),
        String("an allowed marker should count as one token, not several"),
    )


def test_counting_refuses_a_disallowed_marker() raises:
    """Check that counting refuses what encoding refuses.

    Raises:
        Error: if a disallowed marker is counted rather than refused.

    Counting a document that could not be encoded would produce a number
    nobody can act on, and the refusal is the security relevant behaviour:
    it is what stops text from somewhere else injecting a control token.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("before ") + String(END_OF_TEXT) + String(" after")
    var nothing_allowed = List[String]()

    var refused = False
    try:
        _ = tokenizer.count(text, nothing_allowed)
    except:
        refused = True
    assert_true(refused, String("counting should refuse a disallowed marker"))


def test_cached_counting_matches_uncached_counting() raises:
    """Check that a cache changes the speed and not the answer.

    Raises:
        Error: if a cached count differs from an uncached one, or if the
            cache was never consulted.

    The second half matters as much as the first. A cached count that never
    looked anything up would agree with the uncached one trivially, and this
    test would pass while testing nothing.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var cache = PieceCache(CACHE_CAPACITY)
    var names = fixture_names()

    for index in range(len(names)):
        var data = read_bytes(String(FIXTURE_DIR) + names[index])
        var plain = tokenizer.count_ordinary_bytes(Span(data))
        var cached = tokenizer.count_ordinary_bytes_cached(Span(data), cache)
        assert_equal(
            cached,
            plain,
            String(t"{names[index]}: cached count {cached}, plain {plain}"),
        )

    assert_true(
        cache.count() > 0,
        String("the cache stored nothing, so it was never consulted"),
    )
    assert_true(
        cache.hit_rate() > 0.0,
        String("the cache answered no lookups, so it was never used"),
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_count.mojo
# =============================================================================
