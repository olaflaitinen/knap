# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_cache.mojo
# Purpose     : Proves the piece cache cannot change what is encoded.
# Stage       : Vectorisation and benchmarks. See docs/BENCHMARKS.md
# Depends on  : knap.cache, knap.tokenizer
# Invariants  : Every cached result is compared against the reference the
#               uncached path is held to, not merely against the uncached
#               path itself. A shared bug would survive the weaker check.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the Knap piece cache.

An optimisation that sits under a parity claim has to be held to the parity
claim, not to a weaker one. So these tests do not simply check that the
cached and uncached paths agree with each other. They check the cached path
against the same tiktoken generated reference the uncached path is checked
against, over every committed fixture. Two paths agreeing is worth little if
they share the bug.

The remaining tests cover the states a cache reaches only when it is under
pressure, which is where a bounded structure goes wrong: full, disabled, and
refusing pieces for being too long. In each of those the answer must still
be right, because a cache that declines to store something must fall back to
computing it rather than to guessing.

Run the generators first:

    python scripts/fetch_vocabs.py
    python scripts/gen_encode_golden.py
    mojo run -I src tests/test_cache.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.cache import PieceCache
from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_gpt2_tokenizer,
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

comptime R50K_VOCAB = "tests/fixtures/vocabs/r50k_base.tiktoken"
"""Path to the fetched r50k_base merge vocabulary, shared with gpt2."""

comptime GPT2_GOLDEN = "tests/golden/gpt2/encode_expected.jsonl"
"""Reference token ids for the gpt2 pattern over the fixtures."""

comptime END_OF_TEXT = "<|endoftext|>"
"""The special token both target encodings define."""

comptime LARGE_CAPACITY = 65536
"""A cache large enough that the fixtures never fill it."""


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


def check_cached_against_reference(
    tokenizer: Tokenizer, golden_path: String
) raises -> Int:
    """Compare the cached encode against the reference for every fixture.

    Args:
        tokenizer: The loaded tokenizer under test.
        golden_path: Path to that encoding's fixture encode reference.

    Returns:
        The number of tokens compared.

    Raises:
        Error: on the first differing token, naming the fixture and the
            position, or if a fixture is missing.

    One cache is used across every fixture rather than a fresh one per
    fixture. That is the harder case and the realistic one: entries from an
    earlier document are still present when a later one is encoded, so a
    key comparison that was subtly wrong would surface here as a wrong token
    rather than staying hidden behind an empty table.
    """
    var golden = read_text(golden_path)
    var cache = PieceCache(LARGE_CAPACITY)
    var compared = 0

    for line_ref in golden.splitlines():
        var line = String(line_ref)
        if line == "":
            continue

        var name = fixture_name_in(line)
        var expected = tokens_in(line)
        var data = read_bytes(FIXTURE_DIR + name)

        var produced = tokenizer.encode_ordinary_bytes_cached(Span(data), cache)

        if len(produced) != len(expected):
            raise Error(
                String(
                    t"cached encode of '{name}' produced {len(produced)}"
                    t" tokens, reference has {len(expected)}"
                )
            )
        for index in range(len(expected)):
            if produced[index] != expected[index]:
                raise Error(
                    String(
                        t"cached encode of '{name}' differs at token"
                        t" {index}: got {produced[index]}, reference says"
                        t" {expected[index]}"
                    )
                )
        compared += len(expected)

    return compared


def test_cl100k_cached_encode_matches_the_reference() raises:
    """The cached path must match tiktoken, not merely match the scalar path.

    Raises:
        Error: on any divergence from the reference.
    """
    var tokenizer = load_cl100k_base_tokenizer(CL100K_VOCAB)
    var compared = check_cached_against_reference(tokenizer, CL100K_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_o200k_cached_encode_matches_the_reference() raises:
    """The same claim for the second pattern.

    Raises:
        Error: on any divergence from the reference.
    """
    var tokenizer = load_o200k_base_tokenizer(O200K_VOCAB)
    var compared = check_cached_against_reference(tokenizer, O200K_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_gpt2_cached_encode_matches_the_reference() raises:
    """The same claim for the third pattern, which produces longer pieces.

    Raises:
        Error: on any divergence from the reference.

    Worth its own test rather than assumed from the other two. The cache is
    keyed on the bytes of a piece, and the gpt2 pattern makes longer pieces
    than either of the others: its digit runs are unbounded, so a number
    that becomes four pieces under cl100k_base is a single cache key here.
    """
    var tokenizer = load_gpt2_tokenizer(R50K_VOCAB)
    var compared = check_cached_against_reference(tokenizer, GPT2_GOLDEN)
    assert_true(compared > 0, String("no fixtures were compared"))


def test_a_disabled_cache_stores_nothing_and_still_encodes() raises:
    """A zero capacity cache is the uncached path, and must behave as one.

    Raises:
        Error: if it stores anything or changes the answer.

    This case is not academic. Every uncached public entry point runs
    through the shared implementation with a zero capacity cache, so if this
    were wrong the whole library would be.
    """
    var tokenizer = load_cl100k_base_tokenizer(CL100K_VOCAB)
    var text = String("the cache is off, and the answer is the same")

    var expected = tokenizer.encode_ordinary(text)
    var cache = PieceCache(0)
    var produced = tokenizer.encode_ordinary_cached(text, cache)

    assert_equal(len(produced), len(expected))
    for index in range(len(expected)):
        assert_equal(produced[index], expected[index])

    assert_true(not cache.enabled(), String("a zero cache reports enabled"))
    assert_equal(cache.count(), 0)
    assert_equal(cache.hits, 0)


def test_a_repeated_document_hits_every_piece_the_second_time() raises:
    """A second pass over identical text must be served entirely from cache.

    Raises:
        Error: if the accounting or the tokens are wrong.

    This is the test that would fail if lookup silently never found
    anything. A cache that always misses returns correct answers forever,
    so correctness alone cannot detect it. Only the hit count can.
    """
    var tokenizer = load_cl100k_base_tokenizer(CL100K_VOCAB)
    var text = String("Knap tokenizes repeated text, repeatedly and well.")
    var cache = PieceCache(LARGE_CAPACITY)

    var first = tokenizer.encode_ordinary_cached(text, cache)
    var pieces = cache.misses
    assert_true(pieces > 0, String("the first pass looked nothing up"))
    assert_equal(cache.hits, 0)

    var second = tokenizer.encode_ordinary_cached(text, cache)
    assert_equal(cache.hits, pieces)
    assert_equal(cache.misses, pieces)
    assert_true(
        cache.hit_rate() > 0.49, String("the hit rate did not reach one half")
    )

    assert_equal(len(second), len(first))
    for index in range(len(first)):
        assert_equal(second[index], first[index])


def test_a_full_cache_keeps_encoding_correctly() raises:
    """When the table fills, further pieces must be computed, not guessed.

    Raises:
        Error: if a full cache changes the answer.
    """
    var tokenizer = load_cl100k_base_tokenizer(CL100K_VOCAB)
    var text = String(
        "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        " mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega"
    )

    var expected = tokenizer.encode_ordinary(text)
    var cache = PieceCache(4)
    var produced = tokenizer.encode_ordinary_cached(text, cache)

    assert_equal(cache.count(), 4)
    assert_true(cache.rejected > 0, String("the cache never filled"))
    assert_equal(len(produced), len(expected))
    for index in range(len(expected)):
        assert_equal(produced[index], expected[index])


def test_pieces_longer_than_the_limit_are_not_stored() raises:
    """An overlong piece must be encoded normally and left out of the table.

    Raises:
        Error: if a long piece is stored or encodes differently.
    """
    var tokenizer = load_cl100k_base_tokenizer(CL100K_VOCAB)
    var text = String("supercalifragilisticexpialidocious")

    var expected = tokenizer.encode_ordinary(text)
    var cache = PieceCache(LARGE_CAPACITY, 4)
    var produced = tokenizer.encode_ordinary_cached(text, cache)

    assert_equal(cache.count(), 0)
    assert_true(cache.rejected > 0, String("nothing was rejected"))
    assert_equal(len(produced), len(expected))
    for index in range(len(expected)):
        assert_equal(produced[index], expected[index])


def test_the_special_token_paths_are_unchanged_by_a_cache() raises:
    """Allowed markers still emit their id and disallowed ones still raise.

    Raises:
        Error: if the cache alters either behaviour.

    The refusal is the security relevant behaviour in this library, and an
    optimisation that reaches into the encode path has to be shown not to
    have weakened it.
    """
    var tokenizer = load_cl100k_base_tokenizer(CL100K_VOCAB)
    var text = String("before ") + END_OF_TEXT + String(" after")

    var allowed = List[String]()
    allowed.append(String(END_OF_TEXT))

    var expected = tokenizer.encode(text, allowed)
    var cache = PieceCache(LARGE_CAPACITY)
    var produced = tokenizer.encode_cached(text, allowed, cache)

    assert_equal(len(produced), len(expected))
    for index in range(len(expected)):
        assert_equal(produced[index], expected[index])

    var refused = False
    var empty = List[String]()
    try:
        _ = tokenizer.encode_cached(text, empty, cache)
    except:
        refused = True
    assert_true(refused, String("a disallowed marker was not refused"))


def test_an_empty_cache_reports_no_hit_rate() raises:
    """A cache that has never been asked anything reports zero, not a fault.

    Raises:
        Error: if the accounting divides by zero or reports nonsense.
    """
    var cache = PieceCache(16)
    assert_equal(cache.hits, 0)
    assert_equal(cache.misses, 0)
    assert_equal(cache.count(), 0)
    assert_true(cache.hit_rate() == 0.0, String("empty hit rate is not zero"))
    assert_true(cache.enabled(), String("a sized cache reports disabled"))


def main() raises:
    """Run the piece cache suite.

    Raises:
        Error: if any test fails, which is how a failing suite becomes a
            failing process.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_cache.mojo
# =============================================================================
