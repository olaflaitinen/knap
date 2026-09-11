# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/classifier.mojo
# Purpose     : Scalar classifier mapping a code point to the flag set the
#               scanner's alternatives test.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : unicode_tables.mojo
# Invariants  : Flags are derived from exactly one Unicode class lookup, so
#               a code point can never be reported as both a letter and a
#               number.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Scalar code point classifier for the Knap pre-tokenizer.

The scanner never looks at a raw code point value after this point. It asks
only whether a position is a letter, a number, whitespace, a line break, or
none of those, which is what lets the vectorised classifier be swapped in
without touching the state machine.

Flags rather than a single class, because the patterns need overlapping
membership. o200k_base in particular distinguishes an uppercase-ish set
(Lu, Lt, Lm, Lo, M) from a lowercase-ish set (Ll, Lm, Lo, M), and those
overlap in three classes. A single enum could not express that without the
scanner doing the union itself.

This is the scalar reference implementation. It stays in the repository
permanently: when the SIMD classifier arrives, this is what it is
differentially tested against.
"""

from .unicode_tables import (
    CLASS_LL,
    CLASS_LM,
    CLASS_LO,
    CLASS_LT,
    CLASS_LU,
    CLASS_M,
    CLASS_N,
    class_of_code_point,
    is_whitespace,
)


# -----------------------------------------------------------------------------
# Flag bits
#
# One bit per membership test the alternatives perform. Kept as a bit set so
# that a test is a mask rather than a chain of comparisons, and so that the
# overlapping upper and lower sets cost nothing extra.
# -----------------------------------------------------------------------------

comptime FLAG_LETTER: UInt8 = 1
"""Unicode category L, the union of the five letter classes."""

comptime FLAG_NUMBER: UInt8 = 2
"""Unicode category N."""

comptime FLAG_WHITESPACE: UInt8 = 4
"""One of the 25 code points the reference patterns treat as whitespace."""

comptime FLAG_NEWLINE: UInt8 = 8
"""Carriage return or line feed, which several alternatives single out."""

comptime FLAG_UPPERISH: UInt8 = 16
"""In o200k_base's first character class: Lu, Lt, Lm, Lo, or M."""

comptime FLAG_LOWERISH: UInt8 = 32
"""In o200k_base's second character class: Ll, Lm, Lo, or M."""

comptime FLAG_MARK: UInt8 = 64
"""Unicode category M."""

comptime CARRIAGE_RETURN: Int = 0x0D
"""Code point of the carriage return character."""

comptime LINE_FEED: Int = 0x0A
"""Code point of the line feed character."""

comptime SPACE: Int = 0x20
"""Code point of the plain space character, which alternative 3 singles out."""


# -----------------------------------------------------------------------------
# Classification
# -----------------------------------------------------------------------------


def flags_of(code_point: Int) -> UInt8:
    """Return the flag set for one code point.

    Args:
        code_point: The code point to classify, or a negative value for a
            malformed byte.

    Returns:
        The bitwise union of every FLAG_ the code point belongs to.

    A malformed byte is deliberately given an empty flag set, which makes it
    behave like punctuation: not a letter, not a number, not whitespace. That
    routes it to the alternative that accepts arbitrary characters, which is
    the only choice consistent with Knap accepting arbitrary bytes. See
    utf8.mojo for why this is an extension rather than a parity claim.
    """
    if code_point < 0:
        return 0

    var flags: UInt8 = 0
    var unicode_class = class_of_code_point(code_point)

    # Letter is classes Lu through Lo, which are contiguous by construction.
    if unicode_class >= CLASS_LU and unicode_class <= CLASS_LO:
        flags |= FLAG_LETTER
    elif unicode_class == CLASS_N:
        flags |= FLAG_NUMBER

    if unicode_class == CLASS_M:
        flags |= FLAG_MARK

    # o200k_base's two letter runs. Lm, Lo, and M are in both, which is what
    # makes its first two alternatives need backtracking.
    if (
        unicode_class == CLASS_LU
        or unicode_class == CLASS_LT
        or unicode_class == CLASS_LM
        or unicode_class == CLASS_LO
        or unicode_class == CLASS_M
    ):
        flags |= FLAG_UPPERISH
    if (
        unicode_class == CLASS_LL
        or unicode_class == CLASS_LM
        or unicode_class == CLASS_LO
        or unicode_class == CLASS_M
    ):
        flags |= FLAG_LOWERISH

    if is_whitespace(code_point):
        flags |= FLAG_WHITESPACE
    if code_point == CARRIAGE_RETURN or code_point == LINE_FEED:
        flags |= FLAG_NEWLINE

    return flags


def has(flags: UInt8, wanted: UInt8) -> Bool:
    """Report whether a flag set contains a flag.

    Args:
        flags: A flag set from flags_of.
        wanted: The flag to test.

    Returns:
        True when the flag is present.
    """
    return (flags & wanted) != 0


def is_letter_or_number(flags: UInt8) -> Bool:
    """Report whether a flag set is a letter or a number.

    Args:
        flags: A flag set from flags_of.

    Returns:
        True for either category.

    Both patterns exclude letters and numbers together in their leading
    optional class, so the union is worth naming once.
    """
    return (flags & (FLAG_LETTER | FLAG_NUMBER)) != 0


# =============================================================================
# End of file: src/knap/pretokenize/classifier.mojo
# =============================================================================
