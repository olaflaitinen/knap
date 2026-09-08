# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/utf8.mojo
# Purpose     : UTF-8 decoding for the scanner, including a defined policy
#               for malformed input.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : Nothing outside the Mojo standard library.
# Invariants  : Every read advances by at least one byte, so a scan over any
#               byte sequence terminates. A malformed byte is reported as
#               malformed and consumed singly, never skipped and never
#               replaced.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""UTF-8 decoding for the Knap pre-tokenizer.

The scanner walks bytes but reasons about code points, because every class
the patterns test is a code point property. This module is the bridge.

Malformed input has a defined policy rather than an accident. Knap is a byte
level tokenizer and must accept arbitrary bytes, so a malformed byte is
reported with a width of one and a validity flag of false. It is never
rejected, never replaced with a substitution character, and never skipped.
The scanner then treats it as an ordinary non letter, non number, non
whitespace character.

That policy is an extension rather than a parity claim, and the distinction
matters. tiktoken's interface takes decoded text, so malformed UTF-8 cannot
reach it and there is no reference behaviour to match. See
docs/CORRECTNESS.md.

Over-long encodings, surrogates, and values above the Unicode maximum are all
treated as malformed. Accepting them would let two different byte sequences
decode to one code point, which is a well known source of security bugs and
would also break the round trip Knap promises.
"""


@fieldwise_init
struct CodePointRead(Copyable, Movable):
    """The result of decoding one UTF-8 sequence."""

    var code_point: Int
    """The decoded code point, or the raw byte value when malformed."""

    var width: Int
    """Bytes consumed. Always at least one, so scanning terminates."""

    var valid: Bool
    """False when the bytes were not a well formed UTF-8 sequence."""


# -----------------------------------------------------------------------------
# Decoding
#
# Written as an explicit branch per sequence length rather than as a loop.
# The lengths differ in their continuation count, their minimum legal value,
# and, for three byte sequences, an excluded surrogate range, so a loop would
# need all three special cases inside it anyway.
# -----------------------------------------------------------------------------


def _is_continuation(byte: UInt8) -> Bool:
    """Report whether a byte is a UTF-8 continuation byte.

    Args:
        byte: The byte to test.

    Returns:
        True when the top two bits are 10, which marks a continuation.
    """
    # 0xC0 masks the top two bits; 0x80 is the continuation marker.
    return (byte & 0xC0) == 0x80


def decode_at(data: Span[UInt8, _], index: Int) -> CodePointRead:
    """Decode the UTF-8 sequence starting at one byte offset.

    Args:
        data: The bytes being scanned.
        index: Offset of the first byte of the sequence.

    Returns:
        The decoded code point, the number of bytes it occupied, and whether
        the sequence was well formed.

    A malformed sequence yields the raw lead byte value, a width of one, and
    valid set to false. Consuming exactly one byte is what guarantees the
    caller makes progress on any input, including a buffer of random bytes.

    Failure modes: an index at or past the end returns a width of zero with
    valid false, which callers must treat as end of input rather than as a
    malformed byte.
    """
    var length = len(data)
    if index < 0 or index >= length:
        return CodePointRead(0, 0, False)

    var lead = data[index]

    # One byte, 0xxxxxxx. The overwhelming majority of real input.
    if lead < 0x80:
        return CodePointRead(Int(lead), 1, True)

    # A continuation byte cannot start a sequence.
    if lead < 0xC2:
        # 0x80 to 0xBF are stray continuations. 0xC0 and 0xC1 could only
        # ever encode an over-long form of an ASCII character.
        return CodePointRead(Int(lead), 1, False)

    # Two bytes, 110xxxxx 10xxxxxx, encoding U+0080 to U+07FF.
    if lead < 0xE0:
        if index + 1 >= length or not _is_continuation(data[index + 1]):
            return CodePointRead(Int(lead), 1, False)
        var value = (Int(lead) & 0x1F) << 6
        value = value | (Int(data[index + 1]) & 0x3F)
        return CodePointRead(value, 2, True)

    # Three bytes, 1110xxxx 10xxxxxx 10xxxxxx, encoding U+0800 to U+FFFF.
    if lead < 0xF0:
        if index + 2 >= length:
            return CodePointRead(Int(lead), 1, False)
        if not _is_continuation(data[index + 1]):
            return CodePointRead(Int(lead), 1, False)
        if not _is_continuation(data[index + 2]):
            return CodePointRead(Int(lead), 1, False)
        var value = (Int(lead) & 0x0F) << 12
        value = value | ((Int(data[index + 1]) & 0x3F) << 6)
        value = value | (Int(data[index + 2]) & 0x3F)
        # Below 0x800 is an over-long encoding. The surrogate range is not
        # valid UTF-8 at all: those code points exist only inside UTF-16.
        if value < 0x800:
            return CodePointRead(Int(lead), 1, False)
        if value >= 0xD800 and value <= 0xDFFF:
            return CodePointRead(Int(lead), 1, False)
        return CodePointRead(value, 3, True)

    # Four bytes, 11110xxx and three continuations, up to U+10FFFF.
    if lead < 0xF5:
        if index + 3 >= length:
            return CodePointRead(Int(lead), 1, False)
        if not _is_continuation(data[index + 1]):
            return CodePointRead(Int(lead), 1, False)
        if not _is_continuation(data[index + 2]):
            return CodePointRead(Int(lead), 1, False)
        if not _is_continuation(data[index + 3]):
            return CodePointRead(Int(lead), 1, False)
        var value = (Int(lead) & 0x07) << 18
        value = value | ((Int(data[index + 1]) & 0x3F) << 12)
        value = value | ((Int(data[index + 2]) & 0x3F) << 6)
        value = value | (Int(data[index + 3]) & 0x3F)
        if value < 0x10000 or value > 0x10FFFF:
            return CodePointRead(Int(lead), 1, False)
        return CodePointRead(value, 4, True)

    # 0xF5 and above can only encode values past U+10FFFF.
    return CodePointRead(Int(lead), 1, False)


def is_lead_byte(byte: UInt8) -> Bool:
    """Report whether a byte may begin a UTF-8 sequence.

    Args:
        byte: The byte to test.

    Returns:
        True for an ASCII byte or a multi byte lead, false for a
        continuation byte.

    Used to assert the scanner's invariant that every piece boundary lands on
    a sequence start, never inside one.
    """
    return not _is_continuation(byte)


# =============================================================================
# End of file: src/knap/pretokenize/utf8.mojo
# =============================================================================
