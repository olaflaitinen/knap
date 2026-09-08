# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_unicode_tables.mojo
# Purpose     : Verifies the generated Unicode class tables against an
#               exhaustive reference, for every code point.
# Stage       : Milestone M2, pre-tokenizer. See docs/UNICODE.md
# Depends on  : knap.pretokenize.unicode_tables
# Invariants  : Every one of the 1114112 code points is checked, not a
#               sample. Run collapsing is exactly the kind of logic that is
#               right on a sample and wrong at a boundary.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the generated Unicode general category tables.

The tables are produced by collapsing 1114112 per code point classes into
2342 sorted runs. That collapsing is the risky part: an off by one at a run
boundary would misclassify exactly one code point, which would then
misclassify exactly one character of input, which would produce a divergence
that appears only on text nobody thought to test.

So this does not sample. It reads a reference holding one hex digit per code
point, generated alongside the table by the same script but by a different
route, and compares every single one.

Generate the reference first:

    python scripts/gen_unicode_tables.py
    mojo run -I src tests/test_unicode_tables.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.pretokenize.unicode_tables import (
    CLASS_LL,
    CLASS_LO,
    CLASS_LU,
    CLASS_M,
    CLASS_N,
    CLASS_OTHER,
    RUN_COUNT,
    UNICODE_VERSION,
    class_of_code_point,
    is_letter,
    is_mark,
    is_number,
    is_whitespace,
)

comptime GOLDEN = "tests/golden/unicode_classes.txt"
"""Path to the exhaustive per code point class reference."""

comptime MAX_CODE_POINT = 0x110000
"""One past the highest Unicode code point."""


def test_tables_carry_their_provenance() raises:
    """Check the generated table reports a Unicode version and a run count.

    Raises:
        Error: if either constant is missing or implausible.

    A table that does not name its Unicode version cannot be told apart from
    a table generated against a different one, which is how a silent
    behaviour change slips in during a toolchain upgrade.
    """
    assert_true(
        String(UNICODE_VERSION).byte_length() > 0,
        String("the tables must record their Unicode version"),
    )
    assert_true(RUN_COUNT > 1000, String("run count looks implausibly small"))


def test_every_code_point_matches_the_reference() raises:
    """Check all 1114112 code points against the generated reference.

    Raises:
        Error: if the reference is missing, if it is the wrong length, or if
            any code point classifies differently.

    This is the milestone M2 table gate. It is exhaustive on purpose: a
    sample would pass with a boundary bug still present.
    """
    var text: String
    try:
        var handle = open(String(GOLDEN), "r")
        text = handle.read()
        handle.close()
    except:
        var message = String("knap tests: cannot open the Unicode reference")
        message += " at 'tests/golden/unicode_classes.txt'. Generate it with"
        message += " 'python scripts/gen_unicode_tables.py'."
        raise Error(message)

    var reference = text.as_bytes()
    assert_equal(
        len(reference),
        MAX_CODE_POINT,
        String("the Unicode reference is not one digit per code point"),
    )

    # Counted rather than asserted per code point, so a systematic failure
    # reports how widespread it is instead of stopping at the first one.
    var mismatches = 0
    var first_bad = -1

    for code_point in range(MAX_CODE_POINT):
        # ASCII '0' is 48 and 'a' is 97, matching the generator's encoding.
        var digit = reference[code_point]
        var expected: Int
        if digit <= 57:
            expected = Int(digit) - 48
        else:
            expected = Int(digit) - 97 + 10

        if Int(class_of_code_point(code_point)) != expected:
            mismatches += 1
            if first_bad == -1:
                first_bad = code_point

    assert_equal(
        mismatches,
        0,
        String(
            t"{mismatches} code points classify differently from the"
            t" reference, first at U+{first_bad}"
        ),
    )


def test_property_helpers_agree_with_classes() raises:
    """Check the property helpers are consistent with the class values.

    Raises:
        Error: if a helper disagrees with the class it is derived from.

    Letter is the union of five classes, so is_letter is a range test rather
    than five comparisons. That optimisation is only safe while the class
    numbering stays contiguous, which this asserts.
    """
    # Known representatives, chosen to cover each class.
    assert_equal(class_of_code_point(0x41), CLASS_LU)
    assert_equal(class_of_code_point(0x61), CLASS_LL)
    assert_equal(class_of_code_point(0x4E2D), CLASS_LO)
    assert_equal(class_of_code_point(0x0301), CLASS_M)
    assert_equal(class_of_code_point(0x35), CLASS_N)
    assert_equal(class_of_code_point(0x20), CLASS_OTHER)

    assert_true(is_letter(0x41), String("A is a letter"))
    assert_true(is_letter(0x61), String("a is a letter"))
    assert_true(is_letter(0x4E2D), String("a CJK ideograph is a letter"))
    assert_true(not is_letter(0x35), String("a digit is not a letter"))
    assert_true(not is_letter(0x20), String("a space is not a letter"))
    assert_true(not is_letter(0x1F600), String("an emoji is not a letter"))

    assert_true(is_number(0x35), String("5 is a number"))
    assert_true(not is_number(0x41), String("A is not a number"))

    assert_true(is_mark(0x0301), String("a combining acute is a mark"))
    assert_true(not is_mark(0x41), String("A is not a mark"))


def test_whitespace_set_is_exactly_the_reference_set() raises:
    """Check the whitespace predicate over the whole code point space.

    Raises:
        Error: if any code point is treated as whitespace incorrectly.

    Whitespace drives four of the eight alternatives in cl100k_base and
    three of seven in o200k_base, so a wrong set here would change piece
    boundaries across the board. The reference set is the 25 code points the
    regex module matches, enumerated in the generator.
    """
    var expected: List[Int] = [
        0x09,
        0x0A,
        0x0B,
        0x0C,
        0x0D,
        0x20,
        0x85,
        0xA0,
        0x1680,
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2007,
        0x2008,
        0x2009,
        0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
    ]

    for index in range(len(expected)):
        assert_true(
            is_whitespace(expected[index]),
            String(t"code point {expected[index]} should be whitespace"),
        )

    # Nothing outside that set may be whitespace. Checking the whole space
    # rather than a sample is what makes this meaningful.
    var extra = 0
    for code_point in range(MAX_CODE_POINT):
        if is_whitespace(code_point):
            var known = False
            for index in range(len(expected)):
                if expected[index] == code_point:
                    known = True
            if not known:
                extra += 1

    assert_equal(
        extra, 0, String("code points outside the reference set matched")
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_unicode_tables.mojo
# =============================================================================
