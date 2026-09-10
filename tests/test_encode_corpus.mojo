# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_encode_corpus.mojo
# Purpose     : Milestone M3 gate. Compares every token Knap emits against
#               tiktoken over the whole 110 MB corpus.
# Stage       : Milestone M3, BPE merge and encode. See docs/ROADMAP.md
# Depends on  : knap.tokenizer
# Invariants  : The reference is decoded as a stream rather than into a list,
#               because 43.5 million ids would otherwise cost hundreds of
#               megabytes for no benefit.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Encode parity over the full corpus.

This is the milestone M3 acceptance gate: for both target encodings, every
token Knap produces from the 110 MB mixed corpus must equal the token
tiktoken produces at the same position.

That is 43529983 tokens for cl100k_base and 36927147 for o200k_base. The
reference is stored as a variable length integer stream, which is about half
what a fixed width encoding would cost, and is walked position by position
rather than expanded into a list.

Run the whole chain first:

    python scripts/fetch_vocabs.py
    python scripts/fetch_corpus.py
    python scripts/gen_encode_golden.py
    mojo run -I src tests/test_encode_corpus.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_gpt2_tokenizer,
    load_o200k_base_tokenizer,
    load_p50k_base_tokenizer,
)

comptime CORPUS = "bench/corpus/mixed.txt"
"""Path to the fetched mixed text corpus."""

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime CL100K_TOKENS = "bench/corpus/cl100k_base_tokens.bin"
"""Packed reference token ids for cl100k_base."""

comptime O200K_TOKENS = "bench/corpus/o200k_base_tokens.bin"
"""Packed reference token ids for o200k_base."""

comptime R50K_VOCAB = "tests/fixtures/vocabs/r50k_base.tiktoken"
"""Path to the fetched r50k_base merge vocabulary, shared with gpt2."""

comptime P50K_VOCAB = "tests/fixtures/vocabs/p50k_base.tiktoken"
"""Path to the fetched p50k_base vocabulary, shared with p50k_edit."""

comptime GPT2_TOKENS = "bench/corpus/gpt2_tokens.bin"
"""Reference token ids for the gpt2 pattern over the whole corpus."""

comptime P50K_TOKENS = "bench/corpus/p50k_base_tokens.bin"
"""Reference token ids for p50k_base over the whole corpus."""

comptime MINIMUM_CORPUS_BYTES = 100 * 1024 * 1024
"""The corpus size the milestone gates require."""


def read_file_bytes(path: String) raises -> List[UInt8]:
    """Read a whole file as raw bytes.

    Args:
        path: Path to read.

    Returns:
        The file contents.

    Raises:
        Error: if the file cannot be opened, naming the commands that create
            it, because a missing corpus is a setup step rather than a
            defect.
    """
    try:
        var handle = open(path, "r")
        var data = handle.read_bytes()
        handle.close()
        return data^
    except:
        var message = String(t"knap tests: cannot open '{path}'.")
        message += " Run 'python scripts/fetch_vocabs.py',"
        message += " 'python scripts/fetch_corpus.py' and"
        message += " 'python scripts/gen_encode_golden.py' first."
        raise Error(message)


def compare_against_packed_reference(
    produced: List[Int], packed: Span[UInt8, _], label: String
) raises:
    """Compare produced token ids against the packed reference stream.

    Args:
        produced: The token ids Knap emitted.
        packed: The reference, as unsigned base 128 varints.
        label: Encoding name, for the failure message.

    Raises:
        Error: on the first differing token, naming its position, or if the
            two disagree in length.

    Decoded as a stream rather than into a list. At 43.5 million ids a list
    would cost several hundred megabytes to hold something each element of
    which is looked at exactly once.

    Reported at the first difference. Token errors cascade, because one
    wrong merge shifts everything after it, so a count would say "millions
    of differences" where the useful fact is the first position.
    """
    var index = 0
    var position = 0

    while index < len(packed):
        # Decode one varint: seven bits per byte, high bit means continue.
        var value = 0
        var shift = 0
        while True:
            if index >= len(packed):
                raise Error(String(t"{label}: reference ends mid varint"))
            var byte = packed[index]
            index += 1
            value |= (Int(byte) & 0x7F) << shift
            if (byte & 0x80) == 0:
                break
            shift += 7

        if position >= len(produced):
            raise Error(
                String(
                    t"{label}: Knap produced only {len(produced)} tokens,"
                    t" the reference has more"
                )
            )
        if produced[position] != value:
            raise Error(
                String(
                    t"{label}: token {position} is {produced[position]},"
                    t" reference says {value}"
                )
            )
        position += 1

    assert_equal(
        position,
        len(produced),
        String(
            t"{label}: Knap produced {len(produced)} tokens, the reference"
            t" has {position}"
        ),
    )


def run_gate(
    tokenizer: Tokenizer, reference_path: String, label: String
) raises -> Int:
    """Encode the whole corpus and compare it against the reference.

    Args:
        tokenizer: The loaded tokenizer under test.
        reference_path: Path to that encoding's packed reference.
        label: Encoding name, for failure messages.

    Returns:
        The number of tokens compared.

    Raises:
        Error: on the first differing token, or if an input is missing.
    """
    var corpus = read_file_bytes(String(CORPUS))
    assert_true(
        len(corpus) >= MINIMUM_CORPUS_BYTES,
        String(
            t"the corpus is {len(corpus)} bytes, below the 100 MB the"
            t" milestone gates require"
        ),
    )

    var produced = tokenizer.encode_ordinary_bytes(Span(corpus))
    var packed = read_file_bytes(reference_path)
    compare_against_packed_reference(produced, Span(packed), label)

    # The counting path walks the same scanner and the same merge loop and
    # simply does not append. Holding it to the encode it optimises, over
    # the same 110 MB, is the strongest statement available that it is an
    # optimisation rather than a second opinion.
    var counted = tokenizer.count_ordinary_bytes(Span(corpus))
    assert_equal(
        counted,
        len(produced),
        String(
            t"{label}: counting gave {counted} tokens over the corpus and"
            t" encoding gave {len(produced)}"
        ),
    )

    return len(produced)


def test_cl100k_encode_matches_over_the_corpus() raises:
    """Check cl100k_base encode parity across the whole corpus.

    Raises:
        Error: if any token differs from the reference.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var compared = run_gate(
        tokenizer, String(CL100K_TOKENS), String("cl100k_base")
    )
    assert_true(
        compared > 40000000,
        String(t"only {compared} tokens compared, the corpus looks short"),
    )


def test_o200k_encode_matches_over_the_corpus() raises:
    """Check o200k_base encode parity across the whole corpus.

    Raises:
        Error: if any token differs from the reference.
    """
    var tokenizer = load_o200k_base_tokenizer(String(O200K_VOCAB))
    var compared = run_gate(
        tokenizer, String(O200K_TOKENS), String("o200k_base")
    )
    assert_true(
        compared > 30000000,
        String(t"only {compared} tokens compared, the corpus looks short"),
    )


def test_gpt2_encode_matches_over_the_corpus() raises:
    """Check gpt2 encode parity across the whole corpus.

    Raises:
        Error: if any token differs from the reference.

    The third pre-tokenization pattern, and the one whose contraction group
    is case sensitive. Over 115 MB of mixed text there are tens of thousands
    of uppercase apostrophe forms, so a matcher that quietly folded case
    would fail here even though it passes on a page of prose.
    """
    var tokenizer = load_gpt2_tokenizer(String(R50K_VOCAB))
    var compared = run_gate(tokenizer, String(GPT2_TOKENS), String("gpt2"))
    assert_true(
        compared > 50000000,
        String(t"only {compared} tokens compared, the corpus looks short"),
    )


def test_p50k_base_encode_matches_over_the_corpus() raises:
    """Check p50k_base encode parity across the whole corpus.

    Raises:
        Error: if any token differs from the reference.

    Same pattern as gpt2, different merge table: p50k_base adds exactly
    twenty four tokens on top of r50k_base's, and every one of them is a run
    of between two and twenty five spaces. They exist for indented source
    code, so the difference between this gate and the one above lives almost
    entirely in the corpus's code sections.
    """
    var tokenizer = load_p50k_base_tokenizer(String(P50K_VOCAB))
    var compared = run_gate(tokenizer, String(P50K_TOKENS), String("p50k_base"))
    assert_true(
        compared > 50000000,
        String(t"only {compared} tokens compared, the corpus looks short"),
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_encode_corpus.mojo
# =============================================================================
