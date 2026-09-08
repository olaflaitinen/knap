# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/fuzz/harness.mojo
# Purpose     : Drives Knap and tiktoken over one generated input and reports
#               any difference.
# Stage       : Milestone M4, differential fuzzing. See docs/ROADMAP.md
# Depends on  : knap.tokenizer, std.python, generators.mojo
# Invariants  : Input that is not valid UTF-8 is never sent to the reference,
#               which accepts only decoded text. It is checked against Knap's
#               own round trip invariant instead, and counted separately.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""The differential comparison for the Knap fuzzer.

Both implementations run in one process. Mojo installs as an ordinary Python
package, so the compiler, tiktoken, and Knap share an interpreter: there is
no subprocess boundary, no serialisation of token lists across a pipe, and no
ambiguity about which tiktoken produced a reference. Measured at roughly
seven microseconds per comparison including reading every returned id back,
which is what makes ten million comparisons practical.

Two checks, chosen by whether the input is valid UTF-8.

  * Valid input is encoded by both and compared token for token. This is
    parity.
  * Invalid input is encoded and decoded by Knap alone, and the bytes must
    come back unchanged. This is not parity and is never counted as such,
    because the reference cannot accept undecodable input and so has no
    opinion to compare against.

A divergence is reported with the offending bytes in hexadecimal, so the
input can be replayed and kept as a regression seed.
"""

from std.python import Python, PythonObject

from knap.pretokenize.utf8 import decode_at
from knap.tokenizer import Tokenizer


@fieldwise_init
struct FuzzStats(Copyable, Movable):
    """Running totals for one fuzzing session."""

    var compared: Int
    """Inputs encoded by both implementations and compared token for token."""

    var round_tripped: Int
    """Inputs checked for round tripping only, because they are not UTF-8."""

    var divergences: Int
    """Inputs where the two implementations disagreed."""

    var refusals_checked: Int
    """Inputs where a disallowed special token was correctly refused."""


def is_valid_utf8(data: Span[UInt8, _]) -> Bool:
    """Report whether a byte sequence decodes as well formed UTF-8.

    Args:
        data: The bytes to check.

    Returns:
        True when every sequence is well formed.

    This decides which of the two checks an input receives, so it must agree
    with what Python will accept. Over-long forms, surrogates, and values
    past the Unicode maximum are all rejected here, exactly as the decoder in
    utf8.mojo rejects them.
    """
    var position = 0
    while position < len(data):
        var step = decode_at(data, position)
        if step.width == 0:
            return False
        if not step.valid:
            return False
        position += step.width
    return True


def to_hex(data: Span[UInt8, _]) -> String:
    """Render bytes as lowercase hexadecimal.

    Args:
        data: The bytes to render.

    Returns:
        Two hex digits per byte.

    Used only when reporting a divergence. Hexadecimal rather than the text
    itself because a diverging input is frequently unprintable, and a report
    that mangles the very bytes it is reporting is worse than useless.
    """
    comptime DIGITS = "0123456789abcdef"
    var digits = String(DIGITS).as_bytes()
    var out = List[UInt8](capacity=len(data) * 2)
    for index in range(len(data)):
        var byte = Int(data[index])
        out.append(digits[byte >> 4])
        out.append(digits[byte & 0x0F])
    return String(unsafe_from_utf8=Span(out))


def contains_marker(data: Span[UInt8, _], marker: String) -> Bool:
    """Report whether a byte sequence contains a literal.

    Args:
        data: The bytes to search.
        marker: The literal to look for.

    Returns:
        True when the literal occurs.
    """
    var needle = marker.as_bytes()
    if len(needle) == 0 or len(needle) > len(data):
        return False
    for start in range(len(data) - len(needle) + 1):
        var matched = True
        for offset in range(len(needle)):
            if data[start + offset] != needle[offset]:
                matched = False
                break
        if matched:
            return True
    return False


def check_round_trip(
    tokenizer: Tokenizer, data: Span[UInt8, _]
) raises -> String:
    """Encode and decode one input, checking the bytes survive.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.

    Returns:
        An empty string when the round trip held, or a description of the
        first difference.

    This is the check applied to input the reference cannot accept. It is a
    weaker property than parity and is reported as such, but it would still
    catch a byte being dropped, replaced, or reordered.
    """
    var ids = tokenizer.encode_ordinary_bytes(data)
    var back = tokenizer.decode_bytes(ids)

    if len(back) != len(data):
        return String(
            t"round trip changed the length from {len(data)} to {len(back)}"
        )
    for index in range(len(data)):
        if back[index] != data[index]:
            return String(t"round trip altered byte {index}")
    return String("")


def check_parity(
    tokenizer: Tokenizer, encoding: PythonObject, text: String
) raises -> String:
    """Encode one input with both implementations and compare.

    Args:
        tokenizer: The tokenizer under test.
        encoding: The tiktoken encoding object.
        text: The input, which must be valid UTF-8.

    Returns:
        An empty string when the two agree, or a description of the first
        difference.

    Ordinary encoding is compared, so a special token literal in the input
    is treated as text by both sides. The allowed and disallowed paths are
    exercised separately, because they are about refusal rather than about
    token values.
    """
    var mine = tokenizer.encode_ordinary(text)
    var theirs = encoding.encode_ordinary(text)
    var their_count = Int(theirs.__len__())

    var limit = len(mine)
    if their_count < limit:
        limit = their_count

    for index in range(limit):
        var expected = Int(py=theirs[index])
        if mine[index] != expected:
            return String(
                t"token {index} is {mine[index]}, reference says {expected}"
            )

    if len(mine) != their_count:
        return String(
            t"produced {len(mine)} tokens, reference produced {their_count}"
        )
    return String("")


def any_marker_present(
    tokenizer: Tokenizer, data: Span[UInt8, _]
) raises -> Bool:
    """Report whether the input holds any special token this encoding knows.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.

    Returns:
        True when at least one marker occurs.
    """
    for index in range(tokenizer.vocabulary.specials.count()):
        var name = tokenizer.vocabulary.specials.name_at(index)
        if contains_marker(data, name):
            return True
    return False


def check_special_handling(
    tokenizer: Tokenizer, data: Span[UInt8, _]
) raises -> String:
    """Check both special token paths on an input that contains a marker.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.

    Returns:
        An empty string when the behaviour was correct, or a description of
        what went wrong.

    Two things are asserted, and the first is the security relevant one.

      * With nothing allowed, an input holding any marker must be refused.
        Encoding it would let untrusted text inject a control token.
      * With every marker allowed, encoding must succeed and must emit the
        id of each marker that occurs.

    The second half allows all markers rather than one, because a generated
    input frequently holds several and permitting only one would leave the
    others disallowed, which correctly raises and would otherwise look like
    a failure of this check.
    """
    var nothing_allowed = List[String]()
    var refused = False
    try:
        var ignored = tokenizer.encode_bytes(data, nothing_allowed)
    except:
        refused = True
    if not refused:
        return String(
            "input containing a special token was encoded instead of refused"
        )

    var allowed = List[String]()
    for index in range(tokenizer.vocabulary.specials.count()):
        allowed.append(tokenizer.vocabulary.specials.name_at(index))

    var ids = tokenizer.encode_bytes(data, allowed)

    for index in range(tokenizer.vocabulary.specials.count()):
        var name = tokenizer.vocabulary.specials.name_at(index)
        if not contains_marker(data, name):
            continue
        var wanted = tokenizer.vocabulary.specials.id_at(index)
        var seen = False
        for position in range(len(ids)):
            if ids[position] == wanted:
                seen = True
        if not seen:
            return String(
                t"'{name}' occurs in the input but its id was not emitted"
            )
    return String("")


def check_one(
    tokenizer: Tokenizer,
    encoding: PythonObject,
    data: Span[UInt8, _],
    mut stats: FuzzStats,
) raises -> String:
    """Run every applicable check on one generated input.

    Args:
        tokenizer: The tokenizer under test.
        encoding: The tiktoken encoding object.
        data: The generated input bytes.
        stats: Running totals, updated in place.

    Returns:
        An empty string when everything held, or the first failure.

    Which checks apply depends on the input. Valid UTF-8 gets full parity
    plus round tripping; everything else gets round tripping only. Both
    paths are counted separately so a report cannot overstate how much was
    actually compared against the reference.
    """
    var failure = check_round_trip(tokenizer, data)
    if failure != "":
        stats.divergences += 1
        return failure

    if not is_valid_utf8(data):
        stats.round_tripped += 1
        return String("")

    var text = String(unsafe_from_utf8=data)

    failure = check_parity(tokenizer, encoding, text)
    if failure != "":
        stats.divergences += 1
        return failure
    stats.compared += 1

    if any_marker_present(tokenizer, data):
        failure = check_special_handling(tokenizer, data)
        if failure != "":
            stats.divergences += 1
            return failure
        stats.refusals_checked += 1

    return String("")


# =============================================================================
# End of file: tests/fuzz/harness.mojo
# =============================================================================
