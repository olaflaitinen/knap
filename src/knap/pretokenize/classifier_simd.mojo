# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/classifier_simd.mojo
# Purpose     : Vectorised ASCII run scanning for the scanner's inner loops.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : std.sys for the lane count. No Unicode tables at all.
# Invariants  : A run is only ever advanced when every lane in the chunk is
#               ASCII and in the requested class, so the vectorised answer is
#               a prefix of the scalar answer and can never overshoot.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Vectorised ASCII scanning for the Knap pre-tokenizer.

The scanner spends most of its time in four loops that all have the same
shape: advance while the current byte is in some class. Those loops are what
this file accelerates, and they are the only part of pre-tokenization that
vectorises at all. The state machine around them is data dependent branching
and stays scalar.

The design makes parity structural rather than something to be tested for.
Each function advances by a whole vector **only when every lane is ASCII and
in the requested class**, and returns as soon as that stops holding. So the
answer is always a prefix of what the scalar loop would produce, and the
caller finishes the remainder scalar-ly. There is no path on which the
vectorised code can accept a byte the scalar code would reject.

That also means non-ASCII input is never touched here. It falls straight
through to the scalar path with its Unicode table lookups, which is the
documented slow path and is fine: real text is dominated by ASCII.

Two things about the Mojo used below. The lane count comes from the target
through simd_width_of and is never written as a literal; on the development
machine it resolves to 32. And the loads are unaligned by construction,
because a piece boundary lands wherever the input puts it.
"""

from std.sys import simd_width_of

from ..config import SCALAR_ONLY

comptime LANES: Int = simd_width_of[DType.uint8]()
"""Bytes processed per vector, taken from the target rather than assumed."""

comptime CLASS_LETTER: Int = 0
"""ASCII letters, upper or lower case."""

comptime CLASS_DIGIT: Int = 1
"""ASCII decimal digits."""

comptime CLASS_WHITESPACE: Int = 2
"""ASCII whitespace: space, tab, line feed, vertical tab, form feed, return."""

comptime CLASS_PUNCTUATION: Int = 3
"""ASCII that is none of letter, digit, or whitespace."""

comptime CLASS_ASCII_UPPER: Int = 4
"""ASCII uppercase letters, which are Unicode category Lu."""

comptime CLASS_ASCII_LOWER: Int = 5
"""ASCII lowercase letters, which are Unicode category Ll."""


def _class_mask[
    kind: Int
](chunk: SIMD[DType.uint8, LANES]) -> SIMD[DType.bool, LANES]:
    """Return a per lane mask of membership in one ASCII class.

    Parameters:
        kind: One of the CLASS_ constants. A compile time parameter so the
            comparison chain is specialised and no branch survives into the
            loop.

    Args:
        chunk: One vector of input bytes.

    Returns:
        One Bool per lane, true where that byte is ASCII and in the class.

    Every branch below tests ASCII explicitly rather than relying on the
    class comparisons to exclude high bytes. They mostly would, but "mostly"
    is not a property worth resting a tokenizer on, and the extra comparison
    is free next to the load.

    Note the spelling of the comparisons. On a SIMD vector the "greater than"
    operator returns a single Bool for the whole vector, while the gt method
    returns one Bool per lane. Using the operator here would compile and
    silently compute something else entirely.
    """
    # Bytes below 0x80 are ASCII. Everything here requires that first.
    var ascii = chunk.lt(SIMD[DType.uint8, LANES](0x80))

    comptime if kind == CLASS_LETTER:
        # Folding case with a single OR maps A-Z onto a-z, so one range test
        # covers both. 0x20 is the case bit for ASCII letters.
        var folded = chunk | SIMD[DType.uint8, LANES](0x20)
        var lower = folded.ge(SIMD[DType.uint8, LANES](0x61))
        var upper = folded.le(SIMD[DType.uint8, LANES](0x7A))
        return ascii & lower & upper

    comptime if kind == CLASS_DIGIT:
        var lower = chunk.ge(SIMD[DType.uint8, LANES](0x30))
        var upper = chunk.le(SIMD[DType.uint8, LANES](0x39))
        return ascii & lower & upper

    comptime if kind == CLASS_WHITESPACE:
        # Space, plus the contiguous run 0x09 to 0x0D.
        var space = chunk.eq(SIMD[DType.uint8, LANES](0x20))
        var control_low = chunk.ge(SIMD[DType.uint8, LANES](0x09))
        var control_high = chunk.le(SIMD[DType.uint8, LANES](0x0D))
        return ascii & (space | (control_low & control_high))

    comptime if kind == CLASS_ASCII_UPPER:
        # o200k_base's first letter class accepts Lu among others. The ASCII
        # members of Lu are exactly A to Z, so this is a valid prefix scan
        # for that class even though the class is wider.
        var lower = chunk.ge(SIMD[DType.uint8, LANES](0x41))
        var upper = chunk.le(SIMD[DType.uint8, LANES](0x5A))
        return ascii & lower & upper

    comptime if kind == CLASS_ASCII_LOWER:
        # Likewise for Ll and the range a to z.
        var lower = chunk.ge(SIMD[DType.uint8, LANES](0x61))
        var upper = chunk.le(SIMD[DType.uint8, LANES](0x7A))
        return ascii & lower & upper

    # CLASS_PUNCTUATION: ASCII, and none of the others.
    var folded = chunk | SIMD[DType.uint8, LANES](0x20)
    var is_letter = folded.ge(SIMD[DType.uint8, LANES](0x61)) & folded.le(
        SIMD[DType.uint8, LANES](0x7A)
    )
    var is_digit = chunk.ge(SIMD[DType.uint8, LANES](0x30)) & chunk.le(
        SIMD[DType.uint8, LANES](0x39)
    )
    var is_space = chunk.eq(SIMD[DType.uint8, LANES](0x20))
    var is_control = chunk.ge(SIMD[DType.uint8, LANES](0x09)) & chunk.le(
        SIMD[DType.uint8, LANES](0x0D)
    )
    return ascii & ~(is_letter | is_digit | is_space | is_control)


def ascii_run[kind: Int](data: Span[UInt8, _], start: Int) -> Int:
    """Advance over whole vectors of ASCII bytes in one class.

    Parameters:
        kind: One of the CLASS_ constants.

    Args:
        data: The bytes being scanned.
        start: Offset to begin at.

    Returns:
        How many bytes were consumed. Always a multiple of the lane count,
        and always a prefix of what the scalar loop would consume. Always
        zero under a scalar only build.

    The return value is deliberately conservative. A partial vector is never
    consumed, even when its leading lanes would qualify, because working out
    how many leading lanes matched costs more than letting the caller's
    existing scalar loop finish the job. The caller must always continue
    scalar-ly from the returned offset.

    Failure modes: none. A start past the end, or fewer than one vector of
    input remaining, simply returns zero.
    """
    # The toggle lives here rather than at the call sites, so that a scalar
    # only build genuinely removes the vectorised path everywhere instead of
    # leaving it reachable through some other caller.
    comptime if SCALAR_ONLY:
        return 0

    var length = len(data)
    if start < 0 or start >= length:
        return 0

    var pointer = data.unsafe_ptr()
    var position = start

    while position + LANES <= length:
        # Unaligned load. A piece boundary lands wherever the input puts it,
        # so alignment cannot be assumed, and an unaligned vector load costs
        # nothing measurable on the targets Knap builds for.
        var chunk = pointer.unsafe_offset(position).unsafe_load[width=LANES]()
        var mask = _class_mask[kind](chunk)
        # reduce_and is true only when every lane qualifies. Advancing on a
        # partial match is what would break the prefix property.
        if not mask.reduce_and():
            break
        position += LANES

    return position - start


# =============================================================================
# End of file: src/knap/pretokenize/classifier_simd.mojo
# =============================================================================
