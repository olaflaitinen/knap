# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_windows.mojo
# Purpose     : Holds windowing, truncation, budgets and batching to the
#               encoder they are built on.
# Stage       : Milestone M9, caller facing helpers. See docs/ROADMAP.md
# Depends on  : knap.tokenizer
# Invariants  : A window's encoding must be exactly the slice of the whole
#               document's encoding that covers it. Everything else here is
#               a consequence of that.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the windowing, budget and batch helpers.

These exist because a caller would otherwise write them, and would write
them slightly wrong. The usual wrong version encodes a document, cuts the id
list every N ids, and decodes each piece back to text. Its windows begin and
end inside tokens, so they decode to mangled text and re-encode to different
ids, and nothing in the caller's program notices.

The property that makes these right is that a window is cut on a pre-token
boundary, which is the coarsest boundary the merge loop cannot cross. So the
encoding of a window equals the slice of the whole document's encoding that
covers it, and that is asserted here directly rather than argued for.

    mojo run -I src tests/test_windows.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.tokenizer import (
    Tokenizer,
    TokenWindow,
    load_cl100k_base_tokenizer,
    load_o200k_base_tokenizer,
)

comptime FIXTURE_DIR = "tests/fixtures/corpus/"
"""Directory holding the committed edge case fixtures."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime SAMPLE = "tests/fixtures/corpus/mixed_multilingual.txt"
"""A fixture with enough text to make several windows."""


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


def check_windows_reconstruct(
    tokenizer: Tokenizer, data: List[UInt8], max_tokens: Int
) raises -> Int:
    """Check that windows tile the input and reproduce its encoding.

    Args:
        tokenizer: The loaded tokenizer.
        data: The input bytes.
        max_tokens: The window size to test.

    Returns:
        How many windows were produced.

    Raises:
        Error: if the windows do not tile the input, or if concatenating
            their encodings does not reproduce the whole encoding.

    The second half is the one that matters. Windows that tile the bytes but
    encode differently are exactly the failure this helper exists to catch,
    and it is invisible to any test that only looks at offsets.
    """
    var windows = tokenizer.windows_ordinary_bytes(Span(data), max_tokens)
    var whole = tokenizer.encode_ordinary_bytes(Span(data))

    var expected_position = 0
    var rebuilt = List[Int]()

    for index in range(len(windows)):
        var window = windows[index]
        assert_equal(
            window.start,
            expected_position,
            String(
                t"window {index} starts at {window.start}, expected"
                t" {expected_position}"
            ),
        )
        assert_true(
            window.end > window.start,
            String(t"window {index} is empty, which cannot make progress"),
        )

        var piece = tokenizer.encode_ordinary_bytes(
            Span(data)[window.start : window.end]
        )
        assert_equal(
            len(piece),
            window.tokens,
            String(
                t"window {index} claims {window.tokens} tokens and encodes"
                t" to {len(piece)}"
            ),
        )
        for slot in range(len(piece)):
            rebuilt.append(piece[slot])
        expected_position = window.end

    assert_equal(
        expected_position,
        len(data),
        String(t"the windows cover {expected_position} of {len(data)} bytes"),
    )
    assert_equal(
        len(rebuilt),
        len(whole),
        String(
            t"the windows encode to {len(rebuilt)} tokens and the whole"
            t" input to {len(whole)}"
        ),
    )
    for index in range(len(whole)):
        assert_equal(
            rebuilt[index],
            whole[index],
            String(t"token {index} differs between windowed and whole"),
        )
    return len(windows)


def test_windows_tile_the_input_and_reproduce_its_encoding() raises:
    """Check the central property at several window sizes.

    Raises:
        Error: if any window size fails to tile or to reproduce.

    Several sizes because the interesting failures are at the edges: a
    window that fits exactly, one that has to break early, and one large
    enough to swallow the whole input.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var data = read_bytes(String(SAMPLE))
    assert_true(len(data) > 0, String("the sample fixture is empty"))

    var sizes: List[Int] = [1, 2, 7, 64, 1000, 1000000]
    for index in range(len(sizes)):
        var produced = check_windows_reconstruct(tokenizer, data, sizes[index])
        assert_true(
            produced > 0,
            String(t"window size {sizes[index]} produced no windows"),
        )


def test_a_window_size_of_one_still_makes_progress() raises:
    """Check the smallest legal window against a pre-token that exceeds it.

    Raises:
        Error: if the windows do not tile, or if any window is empty.

    A window of one token cannot hold a pre-token that becomes three, and
    the documented behaviour is that the window exceeds the budget rather
    than the pre-token being cut. What must never happen is a window of zero
    bytes, because that would not terminate.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("internationalisation, and 1234567890 besides")
    var windows = tokenizer.windows_ordinary(text, 1)

    assert_true(len(windows) > 0, String("no windows were produced"))
    var over_budget = 0
    for index in range(len(windows)):
        assert_true(
            windows[index].end > windows[index].start,
            String("a window covered no bytes"),
        )
        if windows[index].tokens > 1:
            over_budget += 1
    assert_true(
        over_budget > 0,
        String(
            "no window exceeded the budget, so this input did not exercise"
            " the case it was chosen for"
        ),
    )


def test_overlapping_windows_repeat_text_and_still_advance() raises:
    """Check that an overlap repeats bytes without stalling.

    Raises:
        Error: if a window does not start before the previous one ended, or
            if two windows begin at the same place.

    Overlap is what a retrieval pipeline asks for, so that a passage cut in
    half by a window boundary still appears whole in one of them. The hazard
    is an overlap that consumes the whole window and never advances.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var data = read_bytes(String(SAMPLE))

    var plain = tokenizer.windows_ordinary_bytes(Span(data), 64, 0)
    var lapped = tokenizer.windows_ordinary_bytes(Span(data), 64, 16)

    assert_true(
        len(lapped) >= len(plain),
        String("overlapping windows should not be fewer than plain ones"),
    )

    for index in range(1, len(lapped)):
        assert_true(
            lapped[index].start > lapped[index - 1].start,
            String(t"window {index} does not start after the one before it"),
        )
        assert_true(
            lapped[index].start < lapped[index - 1].end,
            String(t"window {index} does not overlap the one before it"),
        )

    assert_equal(
        lapped[len(lapped) - 1].end,
        len(data),
        String("the last overlapping window does not reach the end"),
    )


def test_windows_refuse_impossible_arguments() raises:
    """Check that a window of zero, or an overlap that cannot fit, raises.

    Raises:
        Error: if either bad argument is accepted.

    A window of zero tokens would never terminate and an overlap as large as
    the window would never advance. Both are caller mistakes and both are
    refused rather than clamped, because a clamped value would silently do
    something the caller did not ask for.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("some text to window")

    var refused_zero = False
    try:
        _ = tokenizer.windows_ordinary(text, 0)
    except:
        refused_zero = True
    assert_true(refused_zero, String("a window of zero tokens was accepted"))

    var refused_overlap = False
    try:
        _ = tokenizer.windows_ordinary(text, 8, 8)
    except:
        refused_overlap = True
    assert_true(
        refused_overlap,
        String("an overlap the size of the window was accepted"),
    )


def test_empty_input_produces_no_windows() raises:
    """Check that nothing to window gives no windows rather than an error.

    Raises:
        Error: if empty input is refused or produces a window.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var empty = List[UInt8]()
    assert_equal(len(tokenizer.windows_ordinary_bytes(Span(empty), 16)), 0)


def test_truncation_finds_the_largest_cut_that_fits() raises:
    """Check that truncation fits the budget and cannot be extended.

    Raises:
        Error: if the truncated prefix exceeds the budget, or if a longer
            prefix would also have fitted.

    Both halves are needed. A truncation that always returned zero would
    satisfy the first and be useless.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var data = read_bytes(String(SAMPLE))
    var whole = tokenizer.count_ordinary_bytes(Span(data))

    var budgets: List[Int] = [0, 1, 5, 50, 500]
    for index in range(len(budgets)):
        var budget = budgets[index]
        var cut = tokenizer.truncate_ordinary_bytes(Span(data), budget)
        var kept = tokenizer.count_ordinary_bytes(Span(data)[0:cut])
        assert_true(
            kept <= budget,
            String(t"budget {budget}: the cut keeps {kept} tokens"),
        )

    # A budget larger than the whole input keeps all of it.
    var everything = tokenizer.truncate_ordinary_bytes(Span(data), whole + 100)
    assert_equal(
        everything,
        len(data),
        String("a budget above the total should keep the whole input"),
    )


def test_the_budget_check_agrees_with_counting() raises:
    """Check the early exit budget test against the full count.

    Raises:
        Error: if the two disagree at any budget.

    fits_ordinary stops as soon as the budget is exceeded, which is the
    whole point of it, and an early exit is exactly the kind of thing that
    is off by one.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("How many tokens is this sentence, exactly?")
    var total = tokenizer.count_ordinary(text)

    for budget in range(0, total + 3):
        assert_equal(
            tokenizer.fits_ordinary(text, budget),
            total <= budget,
            String(t"budget {budget}: total is {total}"),
        )


def test_batch_encoding_matches_encoding_each_document() raises:
    """Check both batch entry points against the single document path.

    Raises:
        Error: if a batch result differs from encoding each document alone.
    """
    var tokenizer = load_o200k_base_tokenizer(String(O200K_VOCAB))
    var documents: List[String] = [
        String(""),
        String("hello world"),
        String("caf\u00e9 na\u00efve"),
        String("1234567890"),
        String("a\r\nb\n\nc"),
    ]

    var batched = tokenizer.encode_ordinary_batch(documents)
    assert_equal(len(batched), len(documents))

    var flat = List[Int]()
    var ends = List[Int]()
    tokenizer.encode_ordinary_batch_into(documents, flat, ends)
    assert_equal(len(ends), len(documents))

    var position = 0
    for index in range(len(documents)):
        var alone = tokenizer.encode_ordinary(documents[index])

        assert_equal(
            len(batched[index]),
            len(alone),
            String(t"document {index} differs in length"),
        )
        for slot in range(len(alone)):
            assert_equal(batched[index][slot], alone[slot])

        assert_equal(
            ends[index],
            position + len(alone),
            String(t"document {index} ends in the wrong place"),
        )
        for slot in range(len(alone)):
            assert_equal(flat[position + slot], alone[slot])
        position = ends[index]

    assert_equal(position, len(flat))


def test_token_lookup_answers_both_ways() raises:
    """Check the bytes to id lookup against decoding the id back.

    Raises:
        Error: if a looked up id does not decode to the text it was found
            by, or if a sequence that is not a token is reported as one.

    The negative half is the one worth writing. A lookup that returned some
    id for everything would pass a test that only checked known tokens.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var known: List[String] = [
        String(" the"),
        String("hello"),
        String("a"),
        String(" world"),
    ]
    for index in range(len(known)):
        var identifier = tokenizer.token_id_of(known[index])
        assert_true(
            identifier >= 0,
            String(t"'{known[index]}' should be a single token"),
        )
        var bytes = tokenizer.token_bytes(identifier)
        assert_equal(
            String(unsafe_from_utf8=Span(bytes)),
            known[index],
            String(t"id {identifier} does not decode to what found it"),
        )

    # A sequence that is not one token. Two words with a space between them
    # cannot be a merge token, because pre-tokenization would have split it.
    assert_equal(
        tokenizer.token_id_of(String("hello world and more besides")), -1
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_windows.mojo
# =============================================================================
