# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/fuzz/generators.mojo
# Purpose     : Input generators for the differential fuzzer, one function
#               per class of input listed in docs/CORRECTNESS.md.
# Stage       : Differential fuzzing. See docs/CORRECTNESS.md
# Depends on  : Nothing outside the Mojo standard library.
# Invariants  : Every generator is a pure function of the seed, so any
#               reported run can be reproduced exactly from its seed.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Input generators for the Knap differential fuzzer.

Each generator targets one way a tokenizer can go wrong, taken from the
hazard list in docs/CORRECTNESS.md. Random text alone would spend almost all
its time on cases that already work: a hundred megabytes of natural language
is unlikely to contain a seven digit number followed immediately by end of
input, and that is precisely the shape that breaks whitespace lookahead.

Everything is driven by one seeded generator with no hidden state, so a run
reported as "seed 12345, ten million strings" can be replayed exactly. A
fuzzing result that cannot be reproduced is an anecdote.

Two generators deliberately produce input that is not valid UTF-8. Those
cannot be compared against the reference implementation, which accepts only
decoded text, so the harness checks Knap's own round trip invariant for them
instead. That distinction is recorded rather than blurred.
"""

comptime KIND_RANDOM_BYTES: Int = 0
"""Uniform random bytes, frequently not valid UTF-8."""

comptime KIND_VALID_UTF8: Int = 1
"""Random code points from every plane, always well formed."""

comptime KIND_EMOJI: Int = 2
"""Emoji with joiners, skin tone modifiers, and flag pairs."""

comptime KIND_SCRIPTS: Int = 3
"""CJK, Arabic, Hebrew, Devanagari, Thai, and Hangul."""

comptime KIND_COMBINING: Int = 4
"""Base letters carrying combining marks stacked to unusual depth."""

comptime KIND_WHITESPACE: Int = 5
"""Long runs of spaces, tabs, newlines, and mixtures."""

comptime KIND_TRUNCATED: Int = 6
"""Text cut mid whitespace or mid multi-byte sequence."""

comptime KIND_SPECIAL: Int = 7
"""Text containing special token literals."""

comptime KIND_DIGITS: Int = 8
"""Numeric sequences of every length from 1 to 20."""

comptime KIND_CONCAT: Int = 9
"""Concatenations of the others, to catch boundary interactions."""

comptime KIND_COUNT: Int = 10
"""How many generator kinds exist."""


struct Rng(Copyable, Movable):
    """A seeded xorshift generator.

    Deliberately small and deterministic. The fuzzer's whole value rests on
    a reported seed reproducing a reported result, so this must never
    consult the clock, the address space, or any other ambient state.
    """

    var state: UInt64
    """Current generator state. Never zero, which xorshift cannot escape."""

    def __init__(out self, seed: UInt64):
        """Seed the generator.

        Args:
            seed: Any value. Zero is remapped, since xorshift has a fixed
                point there and would return zero forever.
        """
        if seed == 0:
            self.state = 0x9E3779B97F4A7C15
        else:
            self.state = seed

    def next(mut self) -> UInt64:
        """Advance the state and return the new value.

        Returns:
            The next pseudo random value.
        """
        var x = self.state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        self.state = x
        return x

    def below(mut self, limit: Int) -> Int:
        """Return a value in the half open range zero to limit.

        Args:
            limit: Exclusive upper bound. A limit of zero or less returns
                zero rather than dividing by zero.

        Returns:
            A value in range.

        Modulo introduces a slight bias for limits that do not divide the
        generator's range. That bias is irrelevant here: the goal is broad
        coverage, not statistical purity.
        """
        if limit <= 0:
            return 0
        return Int(self.next() % UInt64(limit))

    def between(mut self, low: Int, high: Int) -> Int:
        """Return a value in the inclusive range low to high.

        Args:
            low: Lower bound.
            high: Upper bound.

        Returns:
            A value in range.
        """
        if high <= low:
            return low
        return low + self.below(high - low + 1)


# -----------------------------------------------------------------------------
# UTF-8 emission
# -----------------------------------------------------------------------------


def append_code_point(mut out: List[UInt8], code_point: Int):
    """Append one code point as well formed UTF-8.

    Args:
        out: Buffer to append to.
        code_point: The code point to encode. Values outside the Unicode
            range and surrogates are skipped rather than encoded, because
            neither has a legal UTF-8 form.
    """
    if code_point < 0 or code_point > 0x10FFFF:
        return
    if code_point >= 0xD800 and code_point <= 0xDFFF:
        return

    if code_point < 0x80:
        out.append(UInt8(code_point))
        return
    if code_point < 0x800:
        out.append(UInt8(0xC0 | (code_point >> 6)))
        out.append(UInt8(0x80 | (code_point & 0x3F)))
        return
    if code_point < 0x10000:
        out.append(UInt8(0xE0 | (code_point >> 12)))
        out.append(UInt8(0x80 | ((code_point >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (code_point & 0x3F)))
        return
    out.append(UInt8(0xF0 | (code_point >> 18)))
    out.append(UInt8(0x80 | ((code_point >> 12) & 0x3F)))
    out.append(UInt8(0x80 | ((code_point >> 6) & 0x3F)))
    out.append(UInt8(0x80 | (code_point & 0x3F)))


def append_text(mut out: List[UInt8], text: String):
    """Append a literal string's bytes.

    Args:
        out: Buffer to append to.
        text: The text to append.
    """
    var raw = text.as_bytes()
    for index in range(len(raw)):
        out.append(raw[index])


# -----------------------------------------------------------------------------
# The generators
# -----------------------------------------------------------------------------


def gen_random_bytes(mut rng: Rng, mut out: List[UInt8]):
    """Emit uniform random bytes.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    Most outputs are not valid UTF-8, which is the point: byte level BPE
    must accept arbitrary bytes. The harness checks round tripping for
    these rather than parity, because the reference cannot be given
    undecodable input.
    """
    var length = rng.between(0, 64)
    for _ in range(length):
        out.append(UInt8(rng.below(256)))


def gen_valid_utf8(mut rng: Rng, mut out: List[UInt8]):
    """Emit random well formed UTF-8 from every plane.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    Planes are chosen with roughly equal weight rather than by frequency, so
    astral characters appear far more often than in real text. Ordinary text
    is already covered by the 110 MB corpus gate; this exists to reach what
    that corpus does not.
    """
    var count = rng.between(0, 24)
    for _ in range(count):
        var plane = rng.below(4)
        var code_point: Int
        if plane == 0:
            code_point = rng.between(0x20, 0x7E)
        elif plane == 1:
            code_point = rng.between(0x80, 0x7FF)
        elif plane == 2:
            code_point = rng.between(0x800, 0xFFFF)
        else:
            code_point = rng.between(0x10000, 0x10FFFF)
        append_code_point(out, code_point)


def gen_emoji(mut rng: Rng, mut out: List[UInt8]):
    """Emit emoji, including joined sequences and modifiers.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    Three shapes are produced: bare emoji, emoji followed by a skin tone
    modifier, and sequences joined with U+200D. Flag pairs are built from
    regional indicators, which are two code points that render as one glyph
    and are a classic source of boundary mistakes.
    """
    var count = rng.between(1, 6)
    for _ in range(count):
        var shape = rng.below(4)
        if shape == 0:
            append_code_point(out, rng.between(0x1F600, 0x1F64F))
        elif shape == 1:
            append_code_point(out, 0x1F44D)
            append_code_point(out, rng.between(0x1F3FB, 0x1F3FF))
        elif shape == 2:
            append_code_point(out, 0x1F468)
            append_code_point(out, 0x200D)
            append_code_point(out, 0x1F469)
            append_code_point(out, 0x200D)
            append_code_point(out, 0x1F466)
        else:
            append_code_point(out, rng.between(0x1F1E6, 0x1F1FF))
            append_code_point(out, rng.between(0x1F1E6, 0x1F1FF))
        if rng.below(3) == 0:
            out.append(UInt8(0x20))


def gen_scripts(mut rng: Rng, mut out: List[UInt8]):
    """Emit text from scripts that stress different pattern branches.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    CJK and Thai have no word spacing, so the letter alternative must run to
    the end of a long run. Arabic and Hebrew are right to left. Hangul is
    emitted both precomposed and as decomposed jamo, which are different
    code point sequences for the same visible text and must tokenize on
    their own terms.
    """
    var count = rng.between(1, 12)
    for _ in range(count):
        var script = rng.below(6)
        if script == 0:
            append_code_point(out, rng.between(0x4E00, 0x9FFF))
        elif script == 1:
            append_code_point(out, rng.between(0x0600, 0x06FF))
        elif script == 2:
            append_code_point(out, rng.between(0x0590, 0x05FF))
        elif script == 3:
            append_code_point(out, rng.between(0x0900, 0x097F))
        elif script == 4:
            append_code_point(out, rng.between(0x0E00, 0x0E5F))
        else:
            if rng.below(2) == 0:
                # Precomposed Hangul syllable.
                append_code_point(out, rng.between(0xAC00, 0xD7A3))
            else:
                # Decomposed: leading consonant, vowel, optional trailing.
                append_code_point(out, rng.between(0x1100, 0x1112))
                append_code_point(out, rng.between(0x1161, 0x1175))
                if rng.below(2) == 0:
                    append_code_point(out, rng.between(0x11A8, 0x11C2))
        if rng.below(4) == 0:
            out.append(UInt8(0x20))


def gen_combining(mut rng: Rng, mut out: List[UInt8]):
    """Emit base characters carrying stacked combining marks.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    Depth goes well past anything typographically sensible. The two target
    patterns treat marks differently, one keeping them with the preceding
    letter and one not, so this is a place where the encodings genuinely
    diverge from each other and each must be right on its own terms.
    """
    var count = rng.between(1, 8)
    for _ in range(count):
        append_code_point(out, rng.between(0x61, 0x7A))
        var depth = rng.between(0, 10)
        for _ in range(depth):
            append_code_point(out, rng.between(0x0300, 0x036F))
        if rng.below(3) == 0:
            out.append(UInt8(0x20))


def gen_whitespace(mut rng: Rng, mut out: List[UInt8]):
    """Emit long whitespace runs, plain and mixed.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    Whitespace drives four of the eight alternatives in one pattern and
    three of seven in the other, and the differences between them only show
    up at run boundaries and at end of input.
    """
    var segments = rng.between(1, 5)
    for _ in range(segments):
        if rng.below(2) == 0:
            append_text(out, String("word"))
        var run = rng.between(1, 20)
        var kind = rng.below(5)
        for _ in range(run):
            if kind == 0:
                out.append(UInt8(0x20))
            elif kind == 1:
                out.append(UInt8(0x09))
            elif kind == 2:
                out.append(UInt8(0x0A))
            elif kind == 3:
                out.append(UInt8(0x0D))
                out.append(UInt8(0x0A))
            else:
                var pick = rng.below(4)
                if pick == 0:
                    out.append(UInt8(0x20))
                elif pick == 1:
                    out.append(UInt8(0x09))
                elif pick == 2:
                    out.append(UInt8(0x0A))
                else:
                    append_code_point(out, 0x3000)


def gen_truncated(mut rng: Rng, mut out: List[UInt8]):
    """Emit text cut mid whitespace or mid multi-byte sequence.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    The multi-byte truncation deliberately produces invalid UTF-8, which the
    harness routes to the round trip check rather than to the reference.
    Ending mid whitespace is valid text and is compared normally: it is the
    case the whitespace lookahead alternative exists for.
    """
    append_text(out, String("prefix"))
    var mode = rng.below(3)
    if mode == 0:
        var run = rng.between(1, 6)
        for _ in range(run):
            out.append(UInt8(0x20))
    elif mode == 1:
        var run = rng.between(1, 4)
        for _ in range(run):
            out.append(UInt8(0x0A))
    else:
        # A lead byte with its continuation bytes removed.
        var width = rng.between(2, 4)
        if width == 2:
            out.append(UInt8(0xC3))
        elif width == 3:
            out.append(UInt8(0xE2))
            if rng.below(2) == 0:
                out.append(UInt8(0x82))
        else:
            out.append(UInt8(0xF0))
            out.append(UInt8(0x9F))
            if rng.below(2) == 0:
                out.append(UInt8(0x98))


def gen_special(mut rng: Rng, mut out: List[UInt8]):
    """Emit text containing special token literals.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    The literal is placed at the start, in the middle, or at the end, and
    sometimes deliberately malformed so that a near miss is exercised as
    well as an exact one. The harness encodes these with the marker
    disallowed and separately with it allowed.
    """
    var markers: List[String] = [
        String("<|endoftext|>"),
        String("<|endofprompt|>"),
        String("<|fim_prefix|>"),
        String("<|endoftext"),
        String("<|not_a_token|>"),
    ]
    var pieces = rng.between(1, 3)
    for _ in range(pieces):
        if rng.below(2) == 0:
            append_text(out, String("text "))
        append_text(out, markers[rng.below(len(markers))])
        if rng.below(2) == 0:
            append_text(out, String(" more"))


def gen_digits(mut rng: Rng, mut out: List[UInt8]):
    """Emit numeric sequences of every length from 1 to 20.

    Args:
        rng: Seeded generator.
        out: Buffer to append to.

    Digits group into runs of at most three, so a long number becomes
    several pieces. Lengths are swept rather than sampled, because the
    interesting behaviour is exactly at the multiples of three.
    """
    var groups = rng.between(1, 3)
    for _ in range(groups):
        var length = rng.between(1, 20)
        for _ in range(length):
            out.append(UInt8(0x30 + rng.below(10)))
        var separator = rng.below(4)
        if separator == 0:
            out.append(UInt8(0x20))
        elif separator == 1:
            append_text(out, String("abc"))
        elif separator == 2:
            out.append(UInt8(0x2E))


def generate(kind: Int, mut rng: Rng, mut out: List[UInt8]):
    """Dispatch to one generator by kind.

    Args:
        kind: One of the KIND_ constants.
        rng: Seeded generator.
        out: Buffer to append to.

    The concatenation kind calls two to four of the others in sequence,
    which is what exercises the interaction between them. Boundary bugs live
    where one shape meets another far more often than inside either.
    """
    if kind == KIND_RANDOM_BYTES:
        gen_random_bytes(rng, out)
    elif kind == KIND_VALID_UTF8:
        gen_valid_utf8(rng, out)
    elif kind == KIND_EMOJI:
        gen_emoji(rng, out)
    elif kind == KIND_SCRIPTS:
        gen_scripts(rng, out)
    elif kind == KIND_COMBINING:
        gen_combining(rng, out)
    elif kind == KIND_WHITESPACE:
        gen_whitespace(rng, out)
    elif kind == KIND_TRUNCATED:
        gen_truncated(rng, out)
    elif kind == KIND_SPECIAL:
        gen_special(rng, out)
    elif kind == KIND_DIGITS:
        gen_digits(rng, out)
    else:
        var parts = rng.between(2, 4)
        for _ in range(parts):
            generate(rng.below(KIND_COUNT - 1), rng, out)


def kind_name(kind: Int) -> String:
    """Return a human readable name for one generator kind.

    Args:
        kind: One of the KIND_ constants.

    Returns:
        The name, for use in reports.
    """
    if kind == KIND_RANDOM_BYTES:
        return String("random_bytes")
    if kind == KIND_VALID_UTF8:
        return String("valid_utf8")
    if kind == KIND_EMOJI:
        return String("emoji")
    if kind == KIND_SCRIPTS:
        return String("scripts")
    if kind == KIND_COMBINING:
        return String("combining_marks")
    if kind == KIND_WHITESPACE:
        return String("whitespace_runs")
    if kind == KIND_TRUNCATED:
        return String("truncated")
    if kind == KIND_SPECIAL:
        return String("special_literals")
    if kind == KIND_DIGITS:
        return String("digit_runs")
    return String("concatenation")


# =============================================================================
# End of file: tests/fuzz/generators.mojo
# =============================================================================
