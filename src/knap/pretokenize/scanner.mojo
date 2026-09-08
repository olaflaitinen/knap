# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/scanner.mojo
# Purpose     : Hand rolled scanners reproducing the two pre-tokenization
#               patterns, emitting piece boundaries as byte offsets.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : classifier.mojo, unicode_tables.mojo, utf8.mojo
# Invariants  : Boundaries are byte offsets that always land on a UTF-8 lead
#               byte or at end of input, and the pieces tile the input with
#               no gap and no overlap.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Pre-tokenization scanners for Knap.

This is not a regex engine. It is a hand written matcher for two specific
patterns, which is a far smaller problem and the only tractable path to SIMD
later. Each pattern's alternatives are transcribed one function at a time, in
the order the pattern lists them, because alternation order is load bearing:
the first alternative that matches at a position wins, and reordering them
changes the pieces on some inputs.

Two things about the patterns drive the shape of the code, and both were
confirmed against the reference implementation rather than assumed.

  * cl100k_base uses possessive quantifiers and o200k_base does not. A
    possessive quantifier never gives back what it consumed, so an
    alternative that fails after one has failed outright. Where o200k_base
    uses a plain quantifier, the matcher below really does backtrack.
  * The case insensitive contraction groups fold beyond ASCII in exactly one
    place: U+017F, LATIN SMALL LETTER LONG S, matches "s". Nothing else in
    either contraction set has a non-ASCII fold, and no single code point
    matches a two character alternative. That was enumerated over the whole
    code point space, not recalled.

Boundaries are emitted as piece end offsets. Piece i spans from the previous
end, or zero for the first, to ends[i]. The pieces tile the input completely:
every code point matches at least one alternative, so no input position is
ever skipped.
"""

from .classifier import (
    FLAG_LETTER,
    FLAG_LOWERISH,
    FLAG_NEWLINE,
    FLAG_NUMBER,
    FLAG_UPPERISH,
    FLAG_WHITESPACE,
    SPACE,
    flags_of,
    has,
    is_letter_or_number,
)
from .utf8 import decode_at


@fieldwise_init
struct Step(Copyable, Movable):
    """One decoded position: its code point, its width, and its classes."""

    var code_point: Int
    """Decoded code point, or -1 when the bytes were malformed."""

    var width: Int
    """Bytes consumed. Zero only at end of input."""

    var flags: UInt8
    """Classifier flags for this position."""


def read(data: Span[UInt8, _], index: Int) -> Step:
    """Decode and classify the position at one byte offset.

    Args:
        data: The bytes being scanned.
        index: Byte offset to read at.

    Returns:
        The decoded step. A width of zero means end of input.

    A malformed byte yields code point -1 and an empty flag set, so it
    behaves like punctuation and is consumed one byte at a time. That keeps
    the scan progressing on arbitrary bytes.
    """
    var decoded = decode_at(data, index)
    if decoded.width == 0:
        return Step(-1, 0, 0)
    if not decoded.valid:
        return Step(-1, decoded.width, 0)
    return Step(decoded.code_point, decoded.width, flags_of(decoded.code_point))


# -----------------------------------------------------------------------------
# Shared primitives
# -----------------------------------------------------------------------------


def _fold_ascii(code_point: Int) -> Int:
    """Lowercase an ASCII letter, leaving everything else alone.

    Args:
        code_point: The code point to fold.

    Returns:
        The folded code point.

    Only ASCII folding is needed here. The one non-ASCII fold either pattern
    can reach, U+017F to "s", is handled explicitly by the callers that need
    it rather than by a general case folding routine.
    """
    if code_point >= 0x41 and code_point <= 0x5A:
        return code_point + 32
    return code_point


def _whitespace_run_end(data: Span[UInt8, _], start: Int) -> Int:
    """Return the offset just past the maximal whitespace run at start.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        The end offset, equal to start when there is no whitespace.
    """
    var position = start
    while True:
        var step = read(data, position)
        if step.width == 0 or not has(step.flags, FLAG_WHITESPACE):
            break
        position += step.width
    return position


def _last_newline_end(data: Span[UInt8, _], start: Int, limit: Int) -> Int:
    """Return the offset just past the last line break before limit.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.
        limit: Exclusive upper bound, normally a whitespace run end.

    Returns:
        The end offset of the last line break found, or -1 when the range
        holds none.

    This is what implements a greedy whitespace run that must finish on a
    line break. The regex form backtracks to find it; scanning forward and
    remembering the last hit reaches the same answer in one pass.
    """
    var position = start
    var found = -1
    while position < limit:
        var step = read(data, position)
        if step.width == 0:
            break
        if has(step.flags, FLAG_NEWLINE):
            found = position + step.width
        position += step.width
    return found


def _match_digits(data: Span[UInt8, _], start: Int, limit: Int) -> Int:
    """Match a bounded run of numbers.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.
        limit: Maximum count of code points to take.

    Returns:
        Bytes matched, or -1 when there is not at least one number.

    The bound is what produces the digit run limit hazard: a four digit
    number becomes two pieces because the run stops at three.
    """
    var position = start
    var taken = 0
    while taken < limit:
        var step = read(data, position)
        if step.width == 0 or not has(step.flags, FLAG_NUMBER):
            break
        position += step.width
        taken += 1
    if taken == 0:
        return -1
    return position - start


def _match_punctuation(
    data: Span[UInt8, _], start: Int, slash_in_tail: Bool
) -> Int:
    """Match an optional space, a punctuation run, then trailing breaks.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.
        slash_in_tail: True for o200k_base, whose trailing class also
            accepts a forward slash.

    Returns:
        Bytes matched, or -1 when no punctuation follows.

    The leading space is optional and backtrackable in the pattern, but the
    backtrack can never succeed: if the space is given back, the position
    starts on whitespace, which the punctuation class excludes. So a failed
    run is a failed alternative, with no second attempt.
    """
    var position = start

    var first = read(data, position)
    if first.width > 0 and first.code_point == SPACE:
        position += first.width

    var run_start = position
    while True:
        var step = read(data, position)
        if step.width == 0:
            break
        if has(step.flags, FLAG_WHITESPACE) or is_letter_or_number(step.flags):
            break
        position += step.width

    if position == run_start:
        return -1

    while True:
        var step = read(data, position)
        if step.width == 0:
            break
        var accepted = has(step.flags, FLAG_NEWLINE)
        if slash_in_tail and step.code_point == 0x2F:
            accepted = True
        if not accepted:
            break
        position += step.width

    return position - start


def _match_whitespace_to_end(data: Span[UInt8, _], start: Int) -> Int:
    """Match a whitespace run only when it reaches end of input.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1.

    The pattern writes this as a possessive whitespace run anchored to the
    end. Because the run is possessive it consumes every whitespace
    character including a trailing line break, so the anchor can only be
    satisfied at the true end of input.
    """
    var end = _whitespace_run_end(data, start)
    if end == start:
        return -1
    if end != len(data):
        return -1
    return end - start


def _match_whitespace_then_newline(data: Span[UInt8, _], start: Int) -> Int:
    """Match whitespace ending on a line break.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1 when the run holds no line break.
    """
    var end = _whitespace_run_end(data, start)
    var last = _last_newline_end(data, start, end)
    if last == -1:
        return -1
    return last - start


def _match_whitespace_not_before_visible(
    data: Span[UInt8, _], start: Int
) -> Int:
    """Match a whitespace run that is not followed by a visible character.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1.

    The pattern spells this as a greedy whitespace run with a negative
    lookahead. At end of input the whole run qualifies. Otherwise the run is
    followed by a visible character, so the run gives back its final
    character and the lookahead then sees whitespace. A run of one character
    has nothing to give back and fails.
    """
    var end = _whitespace_run_end(data, start)
    if end == start:
        return -1
    if end == len(data):
        return end - start

    # Find where the final whitespace character of the run begins.
    var position = start
    var last_start = start
    while position < end:
        var step = read(data, position)
        if step.width == 0:
            break
        last_start = position
        position += step.width

    if last_start == start:
        return -1
    return last_start - start


def _match_single_whitespace(data: Span[UInt8, _], start: Int) -> Int:
    """Match exactly one whitespace character.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1.
    """
    var step = read(data, start)
    if step.width == 0 or not has(step.flags, FLAG_WHITESPACE):
        return -1
    return step.width


def _match_whitespace_run(data: Span[UInt8, _], start: Int) -> Int:
    """Match a whole whitespace run.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1 when there is no whitespace.
    """
    var end = _whitespace_run_end(data, start)
    if end == start:
        return -1
    return end - start


# -----------------------------------------------------------------------------
# cl100k_base
#
# Eight alternatives, tried in this order:
#   0. '(?i:[sdmt]|ll|ve|re)
#   1. [^\r\n\p{L}\p{N}]?+\p{L}++
#   2. \p{N}{1,3}+
#   3.  ?[^\s\p{L}\p{N}]++[\r\n]*+
#   4. \s++$
#   5. \s*[\r\n]
#   6. \s+(?!\S)
#   7. \s
# -----------------------------------------------------------------------------


def _match_cl100k_contraction(data: Span[UInt8, _], start: Int) -> Int:
    """Match an apostrophe followed by an English contraction ending.

    Args:
        data: The bytes being scanned.
        start: Offset of the apostrophe.

    Returns:
        Bytes matched, or -1.

    The single character endings are tried before the two character ones,
    matching the order inside the pattern's group. U+017F is accepted for
    "s" because the case insensitive group folds it, which was enumerated
    over the whole code point space rather than recalled.
    """
    var quote = read(data, start)
    if quote.width == 0 or quote.code_point != 0x27:
        return -1

    var position = start + quote.width
    var first = read(data, position)
    if first.width == 0:
        return -1

    var folded = _fold_ascii(first.code_point)
    # The single character endings: s, d, m, t, plus the long s fold.
    if (
        folded == 0x73
        or folded == 0x64
        or folded == 0x6D
        or folded == 0x74
        or first.code_point == 0x17F
    ):
        return (position + first.width) - start

    var second = read(data, position + first.width)
    if second.width == 0:
        return -1
    var folded_second = _fold_ascii(second.code_point)

    # The two character endings: ll, ve, re. No non-ASCII code point folds
    # to any of these letters, so plain ASCII folding is exact here.
    var is_ll = folded == 0x6C and folded_second == 0x6C
    var is_ve = folded == 0x76 and folded_second == 0x65
    var is_re = folded == 0x72 and folded_second == 0x65
    if is_ll or is_ve or is_re:
        return (position + first.width + second.width) - start

    return -1


def _match_cl100k_letters(data: Span[UInt8, _], start: Int) -> Int:
    """Match an optional leading character then a run of letters.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1 when no letter follows.

    Both quantifiers are possessive. If the optional leading character is
    taken and no letter follows, the alternative fails outright rather than
    retrying without it. That is why a run such as two exclamation marks
    before a letter does not become one piece.
    """
    var position = start

    var first = read(data, position)
    if first.width == 0:
        return -1
    if not has(first.flags, FLAG_NEWLINE) and not is_letter_or_number(
        first.flags
    ):
        position += first.width

    var letters_start = position
    while True:
        var step = read(data, position)
        if step.width == 0 or not has(step.flags, FLAG_LETTER):
            break
        position += step.width

    if position == letters_start:
        return -1
    return position - start


def scan_cl100k(data: Span[UInt8, _], mut ends: List[Int]) raises:
    """Scan a byte sequence with the cl100k_base pattern.

    Args:
        data: The bytes to scan.
        ends: Receives the end offset of each piece, in order.

    Raises:
        Error: if the scanner fails to advance, which would mean a defect in
            one of the alternative matchers rather than a property of the
            input.

    Empty input produces no pieces, which matches the reference.
    """
    var position = 0
    var length = len(data)

    while position < length:
        var taken = _match_cl100k_contraction(data, position)
        if taken < 0:
            taken = _match_cl100k_letters(data, position)
        if taken < 0:
            taken = _match_digits(data, position, 3)
        if taken < 0:
            taken = _match_punctuation(data, position, False)
        if taken < 0:
            taken = _match_whitespace_to_end(data, position)
        if taken < 0:
            taken = _match_whitespace_then_newline(data, position)
        if taken < 0:
            taken = _match_whitespace_not_before_visible(data, position)
        if taken < 0:
            taken = _match_single_whitespace(data, position)

        if taken <= 0:
            # Unreachable for this pattern: every code point is a letter, a
            # number, whitespace, or none of those, and the alternatives
            # cover all four. Raising rather than skipping means a defect
            # surfaces instead of silently changing the output.
            raise Error(
                String(
                    t"knap: cl100k scanner made no progress at byte"
                    t" {position} of {length}"
                )
            )

        position += taken
        ends.append(position)


# -----------------------------------------------------------------------------
# o200k_base
#
# Seven alternatives, tried in this order:
#   0. [^\r\n\p{L}\p{N}]?[Lu Lt Lm Lo M]*[Ll Lm Lo M]+(contraction)?
#   1. [^\r\n\p{L}\p{N}]?[Lu Lt Lm Lo M]+[Ll Lm Lo M]*(contraction)?
#   2. \p{N}{1,3}
#   3.  ?[^\s\p{L}\p{N}]+[\r\n/]*
#   4. \s*[\r\n]+
#   5. \s+(?!\S)
#   6. \s+
# -----------------------------------------------------------------------------


def _match_o200k_contraction(data: Span[UInt8, _], start: Int) -> Int:
    """Match an apostrophe followed by a contraction ending.

    Args:
        data: The bytes being scanned.
        start: Offset of the apostrophe.

    Returns:
        Bytes matched, or -1.

    The set differs from cl100k_base: it adds "m" and "d" as their own
    alternatives and lists them in a different order. The order does not
    change the result here because the endings are distinguishable by their
    first character, but it is preserved anyway.
    """
    var quote = read(data, start)
    if quote.width == 0 or quote.code_point != 0x27:
        return -1

    var position = start + quote.width
    var first = read(data, position)
    if first.width == 0:
        return -1

    var folded = _fold_ascii(first.code_point)
    if (
        folded == 0x73
        or folded == 0x74
        or folded == 0x6D
        or folded == 0x64
        or first.code_point == 0x17F
    ):
        return (position + first.width) - start

    var second = read(data, position + first.width)
    if second.width == 0:
        return -1
    var folded_second = _fold_ascii(second.code_point)

    var is_re = folded == 0x72 and folded_second == 0x65
    var is_ve = folded == 0x76 and folded_second == 0x65
    var is_ll = folded == 0x6C and folded_second == 0x6C
    if is_re or is_ve or is_ll:
        return (position + first.width + second.width) - start

    return -1


def _o200k_prefix_width(data: Span[UInt8, _], start: Int) -> Int:
    """Return the width of the optional leading character, or -1.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes the leading class would consume, or -1 when it matches
        nothing here.

    The class excludes line breaks, letters, and numbers. A malformed byte
    has an empty flag set and therefore qualifies, which is what lets a
    stray byte attach to a following word exactly as punctuation would.
    """
    var first = read(data, start)
    if first.width == 0:
        return -1
    if has(first.flags, FLAG_NEWLINE) or is_letter_or_number(first.flags):
        return -1
    return first.width


def _match_o200k_alt0(data: Span[UInt8, _], start: Int) -> Int:
    """Match o200k_base alternative 0: optional upper run, then lower run.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1.

    This is the one alternative in either pattern that genuinely backtracks.
    The two character classes overlap in three Unicode categories, Lm, Lo,
    and M, so the greedy upper-ish run can swallow characters the lower-ish
    run needs. The loop gives them back one at a time, longest run first,
    which is the order the reference engine explores.

    The leading optional character backtracks as well: if taking it makes
    everything after fail, the alternative is retried without it.
    """
    for attempt in range(2):
        var position = start
        if attempt == 0:
            var width = _o200k_prefix_width(data, start)
            if width < 0:
                continue
            position += width

        # Greedily take the upper-ish run, remembering where each character
        # started so it can be given back.
        var upper_offsets = List[Int]()
        var after_upper = position
        while True:
            var step = read(data, after_upper)
            if step.width == 0 or not has(step.flags, FLAG_UPPERISH):
                break
            upper_offsets.append(after_upper)
            after_upper += step.width

        var kept = len(upper_offsets)
        while True:
            var lower_start = after_upper
            if kept < len(upper_offsets):
                lower_start = upper_offsets[kept]

            var lower_end = lower_start
            while True:
                var step = read(data, lower_end)
                if step.width == 0 or not has(step.flags, FLAG_LOWERISH):
                    break
                lower_end += step.width

            if lower_end > lower_start:
                var total = lower_end
                var contraction = _match_o200k_contraction(data, total)
                if contraction > 0:
                    total += contraction
                return total - start

            if kept == 0:
                break
            kept -= 1

    return -1


def _match_o200k_alt1(data: Span[UInt8, _], start: Int) -> Int:
    """Match o200k_base alternative 1: upper run, then optional lower run.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        Bytes matched, or -1 when there is no upper-ish character.

    No backtracking is needed here, unlike alternative 0. The upper-ish run
    is greedy and required, and the lower-ish run that follows may be empty,
    so the first exploration the reference engine tries already succeeds.
    """
    for attempt in range(2):
        var position = start
        if attempt == 0:
            var width = _o200k_prefix_width(data, start)
            if width < 0:
                continue
            position += width

        var upper_end = position
        while True:
            var step = read(data, upper_end)
            if step.width == 0 or not has(step.flags, FLAG_UPPERISH):
                break
            upper_end += step.width

        if upper_end == position:
            # The upper-ish run is required. Retry without the prefix.
            continue

        var lower_end = upper_end
        while True:
            var step = read(data, lower_end)
            if step.width == 0 or not has(step.flags, FLAG_LOWERISH):
                break
            lower_end += step.width

        var total = lower_end
        var contraction = _match_o200k_contraction(data, total)
        if contraction > 0:
            total += contraction
        return total - start

    return -1


def scan_o200k(data: Span[UInt8, _], mut ends: List[Int]) raises:
    """Scan a byte sequence with the o200k_base pattern.

    Args:
        data: The bytes to scan.
        ends: Receives the end offset of each piece, in order.

    Raises:
        Error: if the scanner fails to advance, which would mean a defect in
            one of the alternative matchers.

    Empty input produces no pieces, which matches the reference.
    """
    var position = 0
    var length = len(data)

    while position < length:
        var taken = _match_o200k_alt0(data, position)
        if taken < 0:
            taken = _match_o200k_alt1(data, position)
        if taken < 0:
            taken = _match_digits(data, position, 3)
        if taken < 0:
            taken = _match_punctuation(data, position, True)
        if taken < 0:
            taken = _match_whitespace_then_newline(data, position)
        if taken < 0:
            taken = _match_whitespace_not_before_visible(data, position)
        if taken < 0:
            taken = _match_whitespace_run(data, position)

        if taken <= 0:
            raise Error(
                String(
                    t"knap: o200k scanner made no progress at byte"
                    t" {position} of {length}"
                )
            )

        position += taken
        ends.append(position)


# =============================================================================
# End of file: src/knap/pretokenize/scanner.mojo
# =============================================================================
