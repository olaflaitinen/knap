# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_roundtrip.mojo
# Purpose     : Encoding then decoding must reproduce the input bytes exactly,
#               including for input that is not valid UTF-8.
# Stage       : Milestone M3, BPE merge and encode. See docs/ROADMAP.md
# Depends on  : knap.tokenizer
# Invariants  : Round tripping is asserted on bytes, never on text. Comparing
#               decoded Strings would compare something weaker.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Round trip tests for Knap.

Encoding a byte sequence and decoding the result must reproduce the input
exactly. This holds for arbitrary bytes, not only for well formed text,
because the pieces tile the input and every byte value is its own token in a
byte level vocabulary.

Round tripping is a weaker property than parity and is never reported as
evidence of it. A tokenizer can round trip perfectly while producing entirely
different tokens from the reference. It is tested because it is what callers
building caches and datasets actually depend on, and because it would catch a
whole class of byte handling mistakes that parity tests on valid text would
not reach.
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_o200k_base_tokenizer,
)

comptime FIXTURE_DIR = "tests/fixtures/corpus/"
"""Directory holding the committed edge case fixtures."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""


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
        message += " Run 'python scripts/fetch_vocabs.py' first."
        raise Error(message)


def assert_round_trips(
    tokenizer: Tokenizer, data: List[UInt8], label: String
) raises:
    """Encode and decode one input, asserting the bytes come back unchanged.

    Args:
        tokenizer: The tokenizer under test.
        data: The input bytes.
        label: Name for the failure message.

    Raises:
        Error: on the first differing byte, or on a length mismatch.
    """
    var ids = tokenizer.encode_ordinary_bytes(Span(data))
    var back = tokenizer.decode_bytes(ids)

    assert_equal(
        len(back),
        len(data),
        String(
            t"{label}: round trip produced {len(back)} bytes from {len(data)}"
        ),
    )
    for index in range(len(data)):
        if back[index] != data[index]:
            raise Error(
                String(
                    t"{label}: byte {index} came back as {back[index]},"
                    t" expected {data[index]}"
                )
            )


def bytes_of(text: String) -> List[UInt8]:
    """Copy a string's bytes into a list.

    Args:
        text: The text to copy.

    Returns:
        Its bytes.
    """
    var raw = text.as_bytes()
    var out = List[UInt8](capacity=len(raw))
    for index in range(len(raw)):
        out.append(raw[index])
    return out^


def test_fixtures_round_trip_under_both_encodings() raises:
    """Check every committed fixture survives an encode and decode.

    Raises:
        Error: if any fixture does not come back byte for byte.

    The malformed byte fixture is included on purpose. It has no reference
    encoding, but it must still round trip, because byte level BPE
    represents every byte value.
    """
    var names: List[String] = [
        String("ascii_en.txt"),
        String("mixed_multilingual.txt"),
        String("code.txt"),
        String("emoji.txt"),
        String("whitespace_edges.txt"),
        String("invalid_utf8.bin"),
    ]

    var cl100k = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var o200k = load_o200k_base_tokenizer(String(O200K_VOCAB))

    for index in range(len(names)):
        var data = read_bytes(String(FIXTURE_DIR) + names[index])
        assert_true(len(data) > 0, String("a fixture is empty"))
        assert_round_trips(cl100k, data, String("cl100k ") + names[index])
        assert_round_trips(o200k, data, String("o200k ") + names[index])


def test_every_single_byte_round_trips() raises:
    """Check that each of the 256 byte values survives on its own.

    Raises:
        Error: if any byte value fails to round trip.

    A byte level vocabulary must represent every byte. Testing all 256
    individually is cheap and catches an off by one in the single byte
    lookup that ordinary text would never reach.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    for value in range(256):
        var data = List[UInt8](capacity=1)
        data.append(UInt8(value))
        assert_round_trips(tokenizer, data, String(t"single byte {value}"))


def test_malformed_sequences_round_trip() raises:
    """Check that deliberately broken UTF-8 survives a round trip.

    Raises:
        Error: if any malformed sequence is altered.

    Knap must neither reject nor replace malformed input. Replacing a bad
    byte with a substitution character would round trip to different bytes,
    which this would catch immediately.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var cases = List[List[UInt8]]()

    var truncated = List[UInt8]()
    truncated.append(UInt8(0xC3))
    cases.append(truncated^)

    var stray = List[UInt8]()
    stray.append(UInt8(0x80))
    stray.append(UInt8(0x81))
    cases.append(stray^)

    var overlong = List[UInt8]()
    overlong.append(UInt8(0xC0))
    overlong.append(UInt8(0x80))
    cases.append(overlong^)

    var surrogate = List[UInt8]()
    surrogate.append(UInt8(0xED))
    surrogate.append(UInt8(0xA0))
    surrogate.append(UInt8(0x80))
    cases.append(surrogate^)

    var mixed = List[UInt8]()
    mixed.append(UInt8(0x41))
    mixed.append(UInt8(0xFF))
    mixed.append(UInt8(0x42))
    mixed.append(UInt8(0xFE))
    cases.append(mixed^)

    for index in range(len(cases)):
        assert_round_trips(
            tokenizer, cases[index], String(t"malformed case {index}")
        )


def test_text_shapes_round_trip() raises:
    """Check a spread of text shapes, including whitespace boundaries.

    Raises:
        Error: if any shape fails to round trip.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var shapes: List[String] = [
        String(""),
        String(" "),
        String("\n"),
        String("   \n   "),
        String("hello world"),
        String("don't stop"),
        String("1234567890"),
        String("caf\u00e9 na\u00efve"),
        String("\u4e2d\u6587\u6d4b\u8bd5"),
        String("a\u0301b\u0301c\u0301"),
        String("path/to/file.txt"),
        String("trailing spaces   "),
        String("\t\ttabs\t\t"),
    ]

    for index in range(len(shapes)):
        var data = bytes_of(shapes[index])
        assert_round_trips(tokenizer, data, String(t"shape {index}"))


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_roundtrip.mojo
# =============================================================================
