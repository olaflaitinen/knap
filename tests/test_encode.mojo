# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_encode.mojo
# Purpose     : Encode parity against tiktoken on the committed fixtures,
#               plus the special token allowed and disallowed paths.
# Stage       : Milestone M3, BPE merge and encode. See docs/ROADMAP.md
# Depends on  : knap.tokenizer
# Invariants  : These need no fetched corpus, so they run on every push. The
#               110 MB encode gate lives in tests/test_encode_corpus.mojo.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Encode parity tests for Knap.

These compare `encode_ordinary` against a reference generated from tiktoken
for each committed fixture, and then exercise the special token paths that
the fixtures cannot reach.

The special token behaviour is the security relevant part. A marker appearing
in untrusted input must not silently become a control token, so the default
is to refuse, and that refusal is asserted here rather than assumed.

Run the generators first:

    python scripts/fetch_vocabs.py
    python scripts/gen_encode_golden.py
    mojo run -I src tests/test_encode.mojo
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

comptime CL100K_GOLDEN = "tests/golden/cl100k_base/encode_expected.jsonl"
"""Reference token ids for cl100k_base over the fixtures."""

comptime O200K_GOLDEN = "tests/golden/o200k_base/encode_expected.jsonl"
"""Reference token ids for o200k_base over the fixtures."""

comptime END_OF_TEXT = "<|endoftext|>"
"""The special token both target encodings define."""


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
        message += " Run 'python scripts/fetch_vocabs.py' and"
        message += " 'python scripts/gen_encode_golden.py' first."
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
        message += " Run 'python scripts/gen_encode_golden.py' first."
        raise Error(message)


def fixture_name_in(line: String) raises -> String:
    """Read the fixture file name from one golden line.

    Args:
        line: A record shaped like a file field then a tokens array.

    Returns:
        The bare file name.

    Raises:
        Error: if the record does not open with a file field.
    """
    var key = String('{"file":"')
    if line.find(key) != 0:
        raise Error(String("golden line does not start with a file field"))

    var bytes = line.as_bytes()
    var start = key.byte_length()
    var position = start
    while position < len(bytes) and bytes[position] != 34:
        position += 1

    var out = List[UInt8](capacity=position - start)
    for index in range(start, position):
        out.append(bytes[index])
    return String(unsafe_from_utf8=Span(out))


def tokens_in(line: String) raises -> List[Int]:
    """Read the token array from one golden line.

    Args:
        line: A record holding a tokens array of decimal integers.

    Returns:
        The token ids, in order.

    Raises:
        Error: if the record has no tokens array.

    Not a JSON parser. The array holds only decimal digits, commas, and the
    closing bracket, so scanning for digits between the opening bracket and
    the closing one is exact for this generator's output.
    """
    var key = String('"tokens":[')
    var at = line.find(key)
    if at < 0:
        raise Error(String("golden line has no tokens array"))

    var bytes = line.as_bytes()
    var position = at + key.byte_length()
    var out = List[Int]()
    var value = 0
    var in_number = False

    while position < len(bytes):
        var byte = bytes[position]
        if byte == 93:
            break
        if byte >= 48 and byte <= 57:
            value = value * 10 + (Int(byte) - 48)
            in_number = True
        else:
            if in_number:
                out.append(value)
            value = 0
            in_number = False
        position += 1

    if in_number:
        out.append(value)
    return out^


def check_fixture_encodings(
    tokenizer: Tokenizer, golden_path: String
) raises -> Int:
    """Compare encode_ordinary against the reference for every fixture.

    Args:
        tokenizer: The loaded tokenizer under test.
        golden_path: Path to that encoding's fixture encode reference.

    Returns:
        The number of tokens compared.

    Raises:
        Error: on the first differing token, naming the fixture and the
            position, or if a fixture is missing.
    """
    var golden = read_text(golden_path)
    var lines = golden.splitlines()
    var compared = 0

    for index in range(len(lines)):
        var line = String(lines[index])
        if line.strip().byte_length() == 0:
            continue

        var name = fixture_name_in(line)
        var expected = tokens_in(line)
        var data = read_bytes(String(FIXTURE_DIR) + name)
        var actual = tokenizer.encode_ordinary_bytes(Span(data))

        var limit = len(actual)
        if len(expected) < limit:
            limit = len(expected)
        for position in range(limit):
            if actual[position] != expected[position]:
                var message = String(t"{name}: token {position} is")
                message += String(
                    t" {actual[position]}, reference says {expected[position]}"
                )
                raise Error(message)

        assert_equal(
            len(actual),
            len(expected),
            String(
                t"{name}: produced {len(actual)} tokens, reference has"
                t" {len(expected)}"
            ),
        )
        compared += len(actual)

    return compared


def test_cl100k_fixture_encodings_match() raises:
    """Check cl100k_base encode parity on every committed fixture.

    Raises:
        Error: if any token differs from the reference.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var compared = check_fixture_encodings(tokenizer, String(CL100K_GOLDEN))
    assert_true(
        compared > 100,
        String(t"only {compared} tokens compared, the fixtures look empty"),
    )


def test_o200k_fixture_encodings_match() raises:
    """Check o200k_base encode parity on every committed fixture.

    Raises:
        Error: if any token differs from the reference.
    """
    var tokenizer = load_o200k_base_tokenizer(String(O200K_VOCAB))
    var compared = check_fixture_encodings(tokenizer, String(O200K_GOLDEN))
    assert_true(
        compared > 100,
        String(t"only {compared} tokens compared, the fixtures look empty"),
    )


def test_disallowed_special_token_raises() raises:
    """Check that an unpermitted special token in the input is refused.

    Raises:
        Error: if a disallowed marker is encoded instead of rejected.

    This is the security relevant path. Encoding a marker that arrived in
    untrusted input would let that input inject a control token into a
    prompt, so the default is to refuse.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("hi ") + String(END_OF_TEXT) + String(" there")
    var nothing_allowed = List[String]()

    var raised = False
    try:
        var ignored = tokenizer.encode(text, nothing_allowed)
    except:
        raised = True
    assert_true(raised, String("a disallowed special token should raise"))

    # The refusal must not depend on where the marker sits.
    var trailing = String("plain text ") + String(END_OF_TEXT)
    var raised_trailing = False
    try:
        var ignored = tokenizer.encode(trailing, nothing_allowed)
    except:
        raised_trailing = True
    assert_true(
        raised_trailing,
        String("a trailing disallowed special token should raise"),
    )


def test_allowed_special_token_becomes_its_id() raises:
    """Check that a permitted special token encodes to its own id.

    Raises:
        Error: if the marker is not emitted as a single token.

    The surrounding text must encode exactly as it would on its own, so the
    marker acts as a hard split rather than as part of a piece.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var allowed = List[String]()
    allowed.append(String(END_OF_TEXT))

    var text = String("hi ") + String(END_OF_TEXT) + String(" there")
    var ids = tokenizer.encode(text, allowed)

    var marker = tokenizer.vocabulary.specials.id_of(String(END_OF_TEXT))
    var seen = 0
    for index in range(len(ids)):
        if ids[index] == marker:
            seen += 1
    assert_equal(seen, 1, String("the marker should appear exactly once"))

    # Reference behaviour, measured from tiktoken 0.14.0.
    var expected: List[Int] = [6151, 220, 100257, 1070]
    assert_equal(len(ids), len(expected))
    for index in range(len(expected)):
        assert_equal(ids[index], expected[index])


def test_ordinary_encode_treats_markers_as_text() raises:
    """Check that encode_ordinary never emits a special token id.

    Raises:
        Error: if a marker is emitted as its id rather than as characters.

    encode_ordinary is the entry point that never raises on content. A
    marker written out in the input is spelled out in tokens instead.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var text = String("hi ") + String(END_OF_TEXT) + String(" there")
    var ids = tokenizer.encode_ordinary(text)

    var marker = tokenizer.vocabulary.specials.id_of(String(END_OF_TEXT))
    for index in range(len(ids)):
        assert_true(
            ids[index] != marker,
            String("encode_ordinary must not emit a special token id"),
        )

    # Reference behaviour, measured from tiktoken 0.14.0.
    var expected: List[Int] = [6151, 83739, 8862, 728, 428, 91, 29, 1070]
    assert_equal(len(ids), len(expected))
    for index in range(len(expected)):
        assert_equal(ids[index], expected[index])


def test_empty_input_encodes_to_nothing() raises:
    """Check that empty input produces an empty token list, not an error.

    Raises:
        Error: if empty input is rejected or invents a token.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    assert_equal(len(tokenizer.encode_ordinary(String(""))), 0)

    var allowed = List[String]()
    assert_equal(len(tokenizer.encode(String(""), allowed)), 0)


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_encode.mojo
# =============================================================================
