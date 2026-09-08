# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_classifier_parity.mojo
# Purpose     : Checks the vectorised classifier never disagrees with the
#               scalar rule it is meant to accelerate.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/ROADMAP.md
# Depends on  : knap.pretokenize.classifier_simd
# Invariants  : Whatever the vectorised scan consumes must be a prefix of
#               what the scalar rule would consume, and a whole number of
#               vectors.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Differential tests for the vectorised classifier.

The scalar classifier is the reference and stays in the repository
permanently. This checks the vectorised one against it.

The property tested is stronger than "they agree on some inputs". For every
class and every starting offset, whatever the vectorised scan consumed must
satisfy two things:

  * every byte in it is ASCII and in the requested class, judged by a plain
    scalar rule written out separately below, and
  * the length is a whole number of vectors.

Together those make the vectorised answer a prefix of the scalar answer,
which is the invariant the scanner relies on when it continues scalar-ly from
wherever this stopped. A vectorised scan that overshot by even one byte would
silently change piece boundaries.

The suite also runs under a scalar only build, so both paths are exercised:

    mojo run -I src tests/test_classifier_parity.mojo
    mojo run -I src -D KNAP_SIMD=1 tests/test_classifier_parity.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.config import SCALAR_ONLY
from knap.pretokenize.classifier_simd import (
    CLASS_ASCII_LOWER,
    CLASS_ASCII_UPPER,
    CLASS_DIGIT,
    CLASS_LETTER,
    CLASS_PUNCTUATION,
    CLASS_WHITESPACE,
    LANES,
    ascii_run,
)


def scalar_in_class(byte: UInt8, kind: Int) -> Bool:
    """Judge one byte by a plain scalar rule.

    Args:
        byte: The byte to judge.
        kind: One of the classifier's CLASS_ constants.

    Returns:
        True when the byte is ASCII and in that class.

    Written out longhand on purpose. Sharing an implementation with the code
    under test would make this a tautology rather than a check.
    """
    if byte >= 0x80:
        return False

    var is_upper = byte >= 0x41 and byte <= 0x5A
    var is_lower = byte >= 0x61 and byte <= 0x7A
    var is_digit = byte >= 0x30 and byte <= 0x39
    var is_space = byte == 0x20
    var is_control = byte >= 0x09 and byte <= 0x0D

    if kind == CLASS_LETTER:
        return is_upper or is_lower
    if kind == CLASS_DIGIT:
        return is_digit
    if kind == CLASS_WHITESPACE:
        return is_space or is_control
    if kind == CLASS_ASCII_UPPER:
        return is_upper
    if kind == CLASS_ASCII_LOWER:
        return is_lower
    return not (is_upper or is_lower or is_digit or is_space or is_control)


def check_prefix[kind: Int](data: List[UInt8], label: String) raises:
    """Check the vectorised scan is a valid prefix at every offset.

    Parameters:
        kind: One of the classifier's CLASS_ constants.

    Args:
        data: The bytes to scan.
        label: Name for the failure message.

    Raises:
        Error: if the scan consumed a byte the scalar rule rejects, or if it
            consumed a partial vector.

    Every offset is tried, not just zero. A vectorised loop that mishandled
    an unaligned start would pass a test that only ever began at the
    beginning of the buffer.
    """
    for start in range(len(data) + 1):
        var taken = ascii_run[kind](Span(data), start)

        assert_true(
            taken >= 0,
            String(t"{label}: negative run at offset {start}"),
        )
        assert_equal(
            taken % LANES,
            0,
            String(
                t"{label}: run of {taken} at offset {start} is not a whole"
                t" number of vectors"
            ),
        )
        assert_true(
            start + taken <= len(data),
            String(t"{label}: run at offset {start} ran past the end"),
        )

        for offset in range(taken):
            assert_true(
                scalar_in_class(data[start + offset], kind),
                String(
                    t"{label}: byte at {start + offset} was consumed but the"
                    t" scalar rule rejects it"
                ),
            )


def build_mixed() -> List[UInt8]:
    """Build a buffer covering every byte value and several run shapes.

    Returns:
        Bytes holding long runs of each class, boundaries between them, and
        every byte value from 0 to 255.

    Long runs matter: a buffer shorter than one vector would never enter the
    vectorised path at all, and the test would pass without testing
    anything.
    """
    var data = List[UInt8]()

    # Long runs, comfortably longer than one vector at any plausible width.
    for _ in range(LANES * 3 + 5):
        data.append(UInt8(0x61))
    for _ in range(LANES * 2 + 3):
        data.append(UInt8(0x41))
    for _ in range(LANES * 2 + 1):
        data.append(UInt8(0x30))
    for _ in range(LANES * 2 + 7):
        data.append(UInt8(0x20))
    for _ in range(LANES + 9):
        data.append(UInt8(0x21))

    # Mixed boundaries, where a run ends part way through a vector.
    for index in range(LANES * 2):
        data.append(UInt8(0x61 + (index % 26)))
    data.append(UInt8(0xC3))
    data.append(UInt8(0xA9))

    # Every byte value, so no class rule can be wrong about one of them.
    for value in range(256):
        data.append(UInt8(value))

    return data^


def test_letter_runs_are_valid_prefixes() raises:
    """Check the letter class at every offset.

    Raises:
        Error: if the vectorised scan and the scalar rule disagree.
    """
    var data = build_mixed()
    check_prefix[CLASS_LETTER](data, String("letter"))


def test_digit_and_whitespace_runs_are_valid_prefixes() raises:
    """Check the digit and whitespace classes at every offset.

    Raises:
        Error: if the vectorised scan and the scalar rule disagree.
    """
    var data = build_mixed()
    check_prefix[CLASS_DIGIT](data, String("digit"))
    check_prefix[CLASS_WHITESPACE](data, String("whitespace"))


def test_punctuation_runs_are_valid_prefixes() raises:
    """Check the punctuation class at every offset.

    Raises:
        Error: if the vectorised scan and the scalar rule disagree.

    Punctuation is the class most likely to be wrong, because it is defined
    by exclusion rather than by a range.
    """
    var data = build_mixed()
    check_prefix[CLASS_PUNCTUATION](data, String("punctuation"))


def test_case_specific_runs_are_valid_prefixes() raises:
    """Check the two case specific classes at every offset.

    Raises:
        Error: if the vectorised scan and the scalar rule disagree.

    These exist for o200k_base, whose two letter classes distinguish case.
    """
    var data = build_mixed()
    check_prefix[CLASS_ASCII_UPPER](data, String("ascii upper"))
    check_prefix[CLASS_ASCII_LOWER](data, String("ascii lower"))


def test_scalar_only_build_consumes_nothing() raises:
    """Check the toggle really removes the vectorised path.

    Raises:
        Error: if the toggle does not behave as documented.

    Under a scalar only build every scan must return zero, which forces the
    caller's scalar loop to do all the work. Asserting it here means the
    comparison between the two builds is a real comparison rather than the
    same code twice.
    """
    var data = build_mixed()
    var taken = ascii_run[CLASS_LETTER](Span(data), 0)

    comptime if SCALAR_ONLY:
        assert_equal(
            taken,
            0,
            String("a scalar only build must not consume anything here"),
        )
    else:
        assert_true(
            taken >= LANES,
            String(
                "the vectorised build should consume at least one vector of"
                " the leading letter run"
            ),
        )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_classifier_parity.mojo
# =============================================================================
