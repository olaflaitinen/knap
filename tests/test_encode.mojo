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
    load_gpt2_tokenizer,
    load_o200k_base_tokenizer,
    load_o200k_harmony_tokenizer,
    load_p50k_base_tokenizer,
    load_p50k_edit_tokenizer,
    load_r50k_base_tokenizer,
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

comptime R50K_VOCAB = "tests/fixtures/vocabs/r50k_base.tiktoken"
"""Path to the fetched r50k_base merge vocabulary, shared with gpt2."""

comptime P50K_VOCAB = "tests/fixtures/vocabs/p50k_base.tiktoken"
"""Path to the fetched p50k_base vocabulary, shared with p50k_edit."""

comptime HARMONY_GOLDEN = "tests/golden/o200k_harmony/encode_expected.jsonl"
"""Reference token ids for o200k_harmony over the fixtures."""

comptime GPT2_GOLDEN = "tests/golden/gpt2/encode_expected.jsonl"
"""Reference token ids for gpt2 over the fixtures."""

comptime R50K_GOLDEN = "tests/golden/r50k_base/encode_expected.jsonl"
"""Reference token ids for r50k_base over the fixtures."""

comptime P50K_GOLDEN = "tests/golden/p50k_base/encode_expected.jsonl"
"""Reference token ids for p50k_base over the fixtures."""

comptime P50K_EDIT_GOLDEN = "tests/golden/p50k_edit/encode_expected.jsonl"
"""Reference token ids for p50k_edit over the fixtures."""

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


def same_ids(left: List[Int], right: List[Int]) -> Bool:
    """Report whether two token sequences are identical.

    Args:
        left: The first sequence.
        right: The second.

    Returns:
        True when they have the same length and the same ids in order.
    """
    if len(left) != len(right):
        return False
    for index in range(len(left)):
        if left[index] != right[index]:
            return False
    return True


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


def test_o200k_harmony_fixture_encodings_match() raises:
    """The harmony encoding must match the reference over every fixture.

    Raises:
        Error: on the first differing token.

    It shares o200k_base's merge ranks and pattern, so ordinary encoding
    cannot differ. What is actually under test is that the loader picked the
    right vocabulary file and built the 1091 entry special registry without
    disturbing anything, which a shared golden file would hide.
    """
    var tokenizer = load_o200k_harmony_tokenizer(O200K_VOCAB)
    var compared = check_fixture_encodings(tokenizer, HARMONY_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_gpt2_fixture_encodings_match() raises:
    """The gpt2 encoding must match the reference over every fixture.

    Raises:
        Error: on the first differing token.

    The first test of the third pattern. Its contraction group is case
    sensitive and its number runs are unbounded, so a matcher copied from
    cl100k_base rather than written would fail here on any fixture holding
    an uppercase apostrophe form or a long number.
    """
    var tokenizer = load_gpt2_tokenizer(R50K_VOCAB)
    var compared = check_fixture_encodings(tokenizer, GPT2_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_r50k_base_fixture_encodings_match() raises:
    """The r50k_base encoding must match the reference on every fixture.

    Raises:
        Error: on the first differing token.

    Byte for byte the same table gpt2 uses, loaded under its own name.
    """
    var tokenizer = load_r50k_base_tokenizer(R50K_VOCAB)
    var compared = check_fixture_encodings(tokenizer, R50K_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_p50k_base_fixture_encodings_match() raises:
    """The p50k_base encoding must match the reference on every fixture.

    Raises:
        Error: on the first differing token.

    The encoding whose merge ranks are not dense. Rank 50256 is reserved for
    its special token, so this exercises the reserved id path through
    loading, rank table construction, and encoding.
    """
    var tokenizer = load_p50k_base_tokenizer(P50K_VOCAB)
    var compared = check_fixture_encodings(tokenizer, P50K_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_p50k_edit_fixture_encodings_match() raises:
    """The p50k_edit encoding must match the reference on every fixture.

    Raises:
        Error: on the first differing token.

    The same vocabulary file as p50k_base with three more special tokens
    above it.
    """
    var tokenizer = load_p50k_edit_tokenizer(P50K_VOCAB)
    var compared = check_fixture_encodings(tokenizer, P50K_EDIT_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_the_seven_encodings_fall_into_four_ordinary_groups() raises:
    """Encodings sharing a pattern and a table must agree, and others differ.

    Raises:
        Error: if two encodings that should agree do not, or if two that
            should differ happen to agree on this input.

    Ordinary encoding is decided by the pattern and the merge ranks, and by
    nothing else. That gives four groups across seven names, and asserting
    it here means a future change that quietly makes one encoding behave
    like another is caught by a test rather than by a user.

    The negative half matters as much as the positive. If a loader silently
    fell back to cl100k_base, every group would still be internally
    consistent and only the comparison between groups would notice.

    The input is chosen to separate every group, which took measuring. An
    ordinary English sentence does not distinguish gpt2 from p50k_base: the
    two differ by exactly 24 merge tokens and all of them are runs of two to
    twenty five spaces, added so that Codex could tokenise indentation. The
    four spaces before "indented" are the whole reason this assertion has
    any force, and without them the test passed while proving less than it
    claimed.
    """
    var text = String("Hello world 1234567890 don't 'S\n    indented")

    var cl100k = load_cl100k_base_tokenizer(CL100K_VOCAB).encode_ordinary(text)
    var o200k = load_o200k_base_tokenizer(O200K_VOCAB).encode_ordinary(text)
    var harmony = load_o200k_harmony_tokenizer(O200K_VOCAB).encode_ordinary(
        text
    )
    var gpt2 = load_gpt2_tokenizer(R50K_VOCAB).encode_ordinary(text)
    var r50k = load_r50k_base_tokenizer(R50K_VOCAB).encode_ordinary(text)
    var p50k = load_p50k_base_tokenizer(P50K_VOCAB).encode_ordinary(text)
    var p50k_edit = load_p50k_edit_tokenizer(P50K_VOCAB).encode_ordinary(text)

    assert_true(
        same_ids(o200k, harmony),
        String("o200k_base and o200k_harmony should agree"),
    )
    assert_true(same_ids(gpt2, r50k), String("gpt2 and r50k_base should agree"))
    assert_true(
        same_ids(p50k, p50k_edit),
        String("p50k_base and p50k_edit should agree"),
    )

    assert_true(
        not same_ids(cl100k, o200k),
        String("cl100k_base and o200k_base should differ"),
    )
    assert_true(
        not same_ids(cl100k, gpt2),
        String("cl100k_base and gpt2 should differ"),
    )
    assert_true(
        not same_ids(gpt2, p50k), String("gpt2 and p50k_base should differ")
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
