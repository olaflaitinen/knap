# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_pretokenize_corpus.mojo
# Purpose     : Boundary gate. Compares the scanner's piece boundaries
#               against the reference regex over the whole 110 MB corpus.
# Stage       : Pre-tokenization. See docs/ARCHITECTURE.md
# Depends on  : knap.pretokenize.scanner
# Invariants  : Pieces must tile the input exactly, so the sum of the piece
#               lengths always equals the corpus size.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Pre-tokenization parity tests for Knap.

This file is the boundary parity gate: for a corpus of at least
100 MB of mixed text, the piece boundaries the scanner produces must be
identical to those the Python regex module produces from the same pattern.

The reference is a compact binary of piece lengths written by
scripts/gen_pretoken_golden.py. Lengths rather than offsets, and one byte per
piece where possible, because a hundred megabytes of text is tens of millions
of pieces and the obvious encodings are an order of magnitude larger than the
corpus they describe.

Run the whole chain first:

    python scripts/fetch_corpus.py
    python scripts/gen_pretoken_golden.py
    mojo run -I src tests/test_pretokenize_corpus.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.pretokenize.scanner import scan_cl100k, scan_gpt2, scan_o200k

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime CL100K_LENGTHS = "bench/corpus/cl100k_base_lengths.bin"
"""Reference piece lengths for cl100k_base."""

comptime O200K_LENGTHS = "bench/corpus/o200k_base_lengths.bin"
"""Reference piece lengths for o200k_base."""

comptime GPT2_LENGTHS = "bench/corpus/gpt2_lengths.bin"
"""Reference piece lengths for the gpt2 pattern over the whole corpus."""

comptime MINIMUM_CORPUS_BYTES = 100 * 1024 * 1024
"""The corpus size the boundary parity gate requires."""


def read_file_bytes(path: String) raises -> List[UInt8]:
    """Read a whole file as raw bytes.

    Args:
        path: Path to read.

    Returns:
        The file contents.

    Raises:
        Error: if the file cannot be opened, naming the command that creates
            it, because a missing corpus is a setup step rather than a
            defect.

    read_bytes rather than read, for two reasons. The reference length files
    hold arbitrary bytes and are not valid UTF-8, so reading them as text
    fails outright. And read_bytes fills one allocation, where copying a
    110 MB corpus a byte at a time costs more than the scan it feeds.
    """
    try:
        var handle = open(path, "r")
        var data = handle.read_bytes()
        handle.close()
        return data^
    except:
        var message = String(t"knap tests: cannot open '{path}'.")
        message += " Run 'python scripts/fetch_corpus.py' and then"
        message += " 'python scripts/gen_pretoken_golden.py' first."
        raise Error(message)


def decode_reference_lengths(packed: Span[UInt8, _]) raises -> List[Int]:
    """Unpack the reference piece lengths.

    Args:
        packed: The binary written by scripts/gen_pretoken_golden.py.

    Returns:
        Piece lengths in bytes, in order.

    Raises:
        Error: if the encoding is truncated.

    The format is one byte per piece, where a zero byte introduces a four
    byte little endian length instead. Zero is safe as the escape because no
    alternative in either pattern can match an empty string.
    """
    var lengths = List[Int]()
    var index = 0
    while index < len(packed):
        var marker = packed[index]
        if marker != 0:
            lengths.append(Int(marker))
            index += 1
            continue

        if index + 4 >= len(packed):
            raise Error(String("knap tests: reference lengths end mid escape"))
        var value = Int(packed[index + 1])
        value |= Int(packed[index + 2]) << 8
        value |= Int(packed[index + 3]) << 16
        value |= Int(packed[index + 4]) << 24
        lengths.append(value)
        index += 5
    return lengths^


def compare_against_reference(
    corpus_bytes: Int, ends: List[Int], expected: List[Int], label: String
) raises:
    """Compare scanner output against the reference piece lengths.

    Args:
        corpus_bytes: Size of the scanned input.
        ends: Piece end offsets the scanner produced.
        expected: Reference piece lengths.
        label: Encoding name, for the failure message.

    Raises:
        Error: on the first differing piece, naming its index and byte
            offset so the input can be inspected directly.

    Reported at the first difference rather than counted. Boundary errors
    cascade: one wrong piece shifts every piece after it, so a count would
    say "twenty million differences" where the useful fact is the offset of
    the first one.
    """
    var previous = 0
    var limit = len(ends)
    if len(expected) < limit:
        limit = len(expected)

    for index in range(limit):
        var actual_length = ends[index] - previous
        if actual_length != expected[index]:
            var message = String(t"{label}: piece {index} at byte {previous}")
            message += String(
                t" is {actual_length} bytes, reference says {expected[index]}"
            )
            raise Error(message)
        previous = ends[index]

    assert_equal(
        len(ends),
        len(expected),
        String(
            t"{label}: scanner produced {len(ends)} pieces, reference has"
            t" {len(expected)}"
        ),
    )

    # The pieces must tile the input with no gap and no overlap. This is
    # implied by the per piece check above, and asserted anyway because it
    # is the property the rest of the pipeline depends on.
    assert_equal(
        previous,
        corpus_bytes,
        String(t"{label}: pieces cover {previous} of {corpus_bytes} bytes"),
    )


def test_cl100k_boundaries_match_the_reference() raises:
    """Check cl100k_base piece boundaries over the whole corpus.

    Raises:
        Error: if any piece boundary differs from the reference.
    """
    var corpus_data = read_file_bytes(String(CORPUS))
    var corpus = Span(corpus_data)
    assert_true(
        len(corpus) >= MINIMUM_CORPUS_BYTES,
        String(
            t"the corpus is {len(corpus)} bytes, below the 100 MB the"
            t" boundary parity gate requires"
        ),
    )

    var packed = read_file_bytes(String(CL100K_LENGTHS))
    var expected = decode_reference_lengths(Span(packed))

    var ends = List[Int]()
    scan_cl100k(corpus, ends)
    compare_against_reference(
        len(corpus), ends, expected, String("cl100k_base")
    )


def test_o200k_boundaries_match_the_reference() raises:
    """Check o200k_base piece boundaries over the whole corpus.

    Raises:
        Error: if any piece boundary differs from the reference.
    """
    var corpus_data = read_file_bytes(String(CORPUS))
    var corpus = Span(corpus_data)

    var packed = read_file_bytes(String(O200K_LENGTHS))
    var expected = decode_reference_lengths(Span(packed))

    var ends = List[Int]()
    scan_o200k(corpus, ends)
    compare_against_reference(len(corpus), ends, expected, String("o200k_base"))


def test_gpt2_boundaries_match_the_reference() raises:
    """Check gpt2 piece boundaries over the whole corpus.

    Raises:
        Error: if any piece boundary differs from the reference.

    The third and last pattern. It is the oldest of the three and the one
    with the fewest guards: its number runs are unbounded, its letter runs
    take at most one leading space, and its contraction group matches only
    lowercase. Each of those differences shows up somewhere in 115 MB.
    """
    var corpus_data = read_file_bytes(String(CORPUS))
    var corpus = Span(corpus_data)

    var packed = read_file_bytes(String(GPT2_LENGTHS))
    var expected = decode_reference_lengths(Span(packed))

    var ends = List[Int]()
    scan_gpt2(corpus, ends)
    compare_against_reference(len(corpus), ends, expected, String("gpt2"))


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_pretokenize_corpus.mojo
# =============================================================================
