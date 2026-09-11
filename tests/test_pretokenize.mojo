# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_pretokenize.mojo
# Purpose     : Fast pre-tokenization parity tests against the committed
#               edge case fixtures.
# Stage       : Pre-tokenization. See docs/ARCHITECTURE.md
# Depends on  : knap.pretokenize.scanner
# Invariants  : These need no fetched corpus, so they run on every push. The
#               110 MB gate lives in tests/test_pretokenize_corpus.mojo.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Fast pre-tokenization parity tests.

These run against the small committed fixtures in tests/fixtures/corpus,
which are chosen to concentrate the hazards listed in docs/CORRECTNESS.md:
multilingual scripts, emoji with joiners and modifiers, punctuation dense
source code, and whitespace at document boundaries.

They exist because the real gate is expensive. Checking 110 MB of text
requires a download, a minute of reference generation, and half a minute of
comparison, which is too much for every push. These fixtures cover the same
alternatives in a few kilobytes, so a regression in the scanner is caught in
under a second, and the full corpus gate confirms it at scale on demand.

Generate the reference first:

    python scripts/gen_pretoken_golden.py
    mojo run -I src tests/test_pretokenize.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.pretokenize.pattern import (
    CL100K_BASE_ALTERNATIVES,
    CL100K_BASE_PATTERN,
    GPT2_ALTERNATIVES,
    GPT2_PATTERN,
    O200K_BASE_ALTERNATIVES,
    O200K_BASE_PATTERN,
)
from knap.pretokenize.scanner import scan_cl100k, scan_gpt2, scan_o200k

comptime FIXTURE_DIR = "tests/fixtures/corpus/"
"""Directory holding the committed edge case fixtures."""

comptime CL100K_GOLDEN = "tests/golden/cl100k_base/pretoken_boundaries.jsonl"
"""Reference piece boundaries for cl100k_base over the fixtures."""

comptime O200K_GOLDEN = "tests/golden/o200k_base/pretoken_boundaries.jsonl"
"""Reference piece boundaries for o200k_base over the fixtures."""

comptime GPT2_GOLDEN = "tests/golden/gpt2/pretoken_boundaries.jsonl"
"""Reference piece boundaries for the gpt2 pattern over the fixtures."""

comptime PATTERN_CL100K: Int = 0
"""Scan with the cl100k_base pattern."""

comptime PATTERN_O200K: Int = 1
"""Scan with the o200k_base pattern."""

comptime PATTERN_GPT2: Int = 2
"""Scan with the gpt2 pattern.

Three patterns serve seven encodings. These constants repeat the ones in
knap.tokenizer rather than importing them, because the pre-tokenizer sits
below the tokenizer and a test for the lower layer should not need the
higher one to compile.
"""


def read_bytes(path: String) raises -> List[UInt8]:
    """Read a whole file as raw bytes.

    Args:
        path: Path to read.

    Returns:
        The file contents.

    Raises:
        Error: if the file cannot be opened.
    """
    try:
        var handle = open(path, "r")
        var data = handle.read_bytes()
        handle.close()
        return data^
    except:
        var message = String(t"knap tests: cannot open '{path}'.")
        message += " Run 'python scripts/gen_pretoken_golden.py' first."
        raise Error(message)


def read_text(path: String) raises -> String:
    """Read a whole file as text.

    Args:
        path: Path to read.

    Returns:
        The file contents.

    Raises:
        Error: if the file cannot be opened.
    """
    try:
        var handle = open(path, "r")
        var text = handle.read()
        handle.close()
        return text^
    except:
        var message = String(t"knap tests: cannot open '{path}'.")
        message += " Run 'python scripts/gen_pretoken_golden.py' first."
        raise Error(message)


# -----------------------------------------------------------------------------
# Golden reading
#
# The fixture golden is JSON Lines shaped like
#
#     {"file":"code.txt","start":0,"length":1,"piece":"#"}
#
# Only the file name and the length are read. Rather than parse JSON, the
# reader searches for the two key names, which is safe because they cannot
# occur inside the values that precede them: the file name is a bare
# filename, and the piece text is always the last field.
# -----------------------------------------------------------------------------


def field_after(line: String, key: String) raises -> Int:
    """Read the integer that follows a key in one golden line.

    Args:
        line: The JSON Lines record.
        key: The quoted key including its colon.

    Returns:
        The integer value.

    Raises:
        Error: if the key is absent or is not followed by digits.
    """
    var at = line.find(key)
    if at < 0:
        raise Error(String(t"golden line has no {key}: {line}"))

    var bytes = line.as_bytes()
    var position = at + key.byte_length()
    var value = 0
    var digits = 0
    while (
        position < len(bytes)
        and bytes[position] >= 48
        and bytes[position] <= 57
    ):
        value = value * 10 + (Int(bytes[position]) - 48)
        position += 1
        digits += 1
    if digits == 0:
        raise Error(String(t"golden line has no digits after {key}: {line}"))
    return value


def file_name_in(line: String) raises -> String:
    """Read the fixture file name from one golden line.

    Args:
        line: The JSON Lines record.

    Returns:
        The bare file name.

    Raises:
        Error: if the record does not open with a file field.
    """
    var key = String('{"file":"')
    var at = line.find(key)
    if at != 0:
        raise Error(String(t"golden line does not start with a file field"))

    var bytes = line.as_bytes()
    var start = key.byte_length()
    var position = start
    while position < len(bytes) and bytes[position] != 34:
        position += 1

    var out = List[UInt8](capacity=position - start)
    for index in range(start, position):
        out.append(bytes[index])
    return String(unsafe_from_utf8=Span(out))


def check_fixtures(golden_path: String, pattern: Int) raises -> Int:
    """Compare the scanner against the reference for every fixture.

    Args:
        golden_path: Path to that encoding's fixture golden.
        pattern: Which pattern to scan with, one of the PATTERN constants.

    Returns:
        The number of pieces compared.

    Raises:
        Error: on the first differing piece, or if a fixture is missing.

    Each fixture is scanned in full and compared piece by piece. Reported at
    the first difference, because a boundary error shifts every piece after
    it and a count would bury the useful fact.
    """
    var golden = read_text(golden_path)
    var lines = golden.splitlines()

    var current_name = String("")
    var expected = List[Int]()
    var compared = 0

    # A trailing empty entry lets the loop flush the final fixture without
    # duplicating the comparison code after it.
    for index in range(len(lines) + 1):
        var name = String("")
        var length = 0
        if index < len(lines):
            var line = String(lines[index])
            if line.strip().byte_length() == 0:
                continue
            name = file_name_in(line)
            length = field_after(line, String('"length":'))

        if name != current_name:
            if current_name != "":
                compared += compare_one_fixture(current_name, expected, pattern)
            expected = List[Int]()
            current_name = name
        if index < len(lines):
            expected.append(length)

    return compared


def compare_one_fixture(
    name: String, expected: List[Int], pattern: Int
) raises -> Int:
    """Scan one fixture and compare it against its reference lengths.

    Args:
        name: Bare fixture file name.
        expected: Reference piece lengths, in order.
        pattern: Which pattern to scan with, one of the PATTERN constants.

    Returns:
        The number of pieces compared.

    Raises:
        Error: on the first differing piece.
    """
    var path = String(FIXTURE_DIR) + name
    var data = read_bytes(path)

    var ends = List[Int]()
    if pattern == PATTERN_CL100K:
        scan_cl100k(Span(data), ends)
    elif pattern == PATTERN_GPT2:
        scan_gpt2(Span(data), ends)
    else:
        scan_o200k(Span(data), ends)

    var previous = 0
    var limit = len(ends)
    if len(expected) < limit:
        limit = len(expected)

    for index in range(limit):
        var actual = ends[index] - previous
        if actual != expected[index]:
            var message = String(t"{name}: piece {index} at byte {previous}")
            message += String(
                t" is {actual} bytes, reference says {expected[index]}"
            )
            raise Error(message)
        previous = ends[index]

    assert_equal(
        len(ends),
        len(expected),
        String(
            t"{name}: scanner produced {len(ends)} pieces, reference has"
            t" {len(expected)}"
        ),
    )
    assert_equal(
        previous,
        len(data),
        String(t"{name}: pieces cover {previous} of {len(data)} bytes"),
    )
    return len(ends)


def test_cl100k_fixtures_match_the_reference() raises:
    """Check cl100k_base boundaries on every committed fixture.

    Raises:
        Error: if any piece boundary differs from the reference.
    """
    var compared = check_fixtures(String(CL100K_GOLDEN), PATTERN_CL100K)
    assert_true(
        compared > 100,
        String(t"only {compared} pieces compared, the fixtures look empty"),
    )


def test_o200k_fixtures_match_the_reference() raises:
    """Check o200k_base boundaries on every committed fixture.

    Raises:
        Error: if any piece boundary differs from the reference.
    """
    var compared = check_fixtures(String(O200K_GOLDEN), PATTERN_O200K)
    assert_true(
        compared > 100,
        String(t"only {compared} pieces compared, the fixtures look empty"),
    )


def test_gpt2_fixtures_match_the_reference() raises:
    """Check gpt2 boundaries on every committed fixture.

    Raises:
        Error: if any piece boundary differs from the reference.

    The fixtures are the edge cases: malformed UTF-8, long whitespace runs,
    contraction forms, and scripts with no spaces. The gpt2 pattern treats
    several of those differently from the other two, so a fixture set built
    for cl100k_base is more useful here than it looks.
    """
    var compared = check_fixtures(String(GPT2_GOLDEN), PATTERN_GPT2)
    assert_true(
        compared > 100,
        String(t"only {compared} pieces compared, the fixtures look empty"),
    )


def test_pattern_constants_survived_formatting() raises:
    """Check the generated pattern constants still hold the exact patterns.

    Raises:
        Error: if either constant has the wrong length or alternative count.

    The formatter splits these long literals across several lines using
    implicit concatenation. That preserves the value, but it rewrites a
    generated file that must stay verbatim, so the lengths are asserted here
    as a cheap guard against a future formatter changing more than it should.

    The authoritative check is scripts/check_generated.py, which re-extracts
    the pattern from tiktoken and compares. This one runs in the Mojo suite
    so a corrupted constant fails next to the scanner it describes.
    """
    assert_equal(String(CL100K_BASE_PATTERN).byte_length(), 117)
    assert_equal(CL100K_BASE_ALTERNATIVES, 8)
    assert_equal(String(O200K_BASE_PATTERN).byte_length(), 274)
    assert_equal(O200K_BASE_ALTERNATIVES, 7)
    assert_equal(String(GPT2_PATTERN).byte_length(), 79)
    assert_equal(GPT2_ALTERNATIVES, 7)


def test_empty_input_produces_no_pieces() raises:
    """Check that empty input yields an empty piece list.

    Raises:
        Error: if either scanner invents a piece for empty input.

    One of the correctness hazards in docs/CORRECTNESS.md: empty input is an
    empty result, never an error and never a zero length piece.
    """
    var empty = List[UInt8]()

    var cl_ends = List[Int]()
    scan_cl100k(Span(empty), cl_ends)
    assert_equal(len(cl_ends), 0)

    var o2_ends = List[Int]()
    scan_o200k(Span(empty), o2_ends)
    assert_equal(len(o2_ends), 0)


def test_malformed_utf8_is_tiled_not_rejected() raises:
    """Check that arbitrary bytes scan without error and tile completely.

    Raises:
        Error: if either scanner rejects the input or loses a byte.

    There is no reference for this case and none can exist: the reference
    regex operates on decoded text, so undecodable input cannot be given to
    it. What is asserted here is Knap's own documented policy, that a
    malformed byte is neither rejected nor replaced, and that the pieces
    still cover every byte exactly once. See docs/CORRECTNESS.md.
    """
    var data = read_bytes(String(FIXTURE_DIR) + "invalid_utf8.bin")
    assert_true(len(data) > 0, String("the malformed fixture is empty"))

    var cl_ends = List[Int]()
    scan_cl100k(Span(data), cl_ends)
    assert_true(len(cl_ends) > 0, String("no pieces from malformed bytes"))
    assert_equal(
        cl_ends[len(cl_ends) - 1],
        len(data),
        String("cl100k pieces do not cover the malformed fixture"),
    )

    var o2_ends = List[Int]()
    scan_o200k(Span(data), o2_ends)
    assert_equal(
        o2_ends[len(o2_ends) - 1],
        len(data),
        String("o200k pieces do not cover the malformed fixture"),
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_pretokenize.mojo
# =============================================================================
