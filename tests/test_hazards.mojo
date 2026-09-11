# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_hazards.mojo
# Purpose     : One test per correctness hazard listed in docs/CORRECTNESS.md.
# Stage       : BPE merge and encode. See docs/ARCHITECTURE.md
# Depends on  : knap.tokenizer
# Invariants  : Every expected token list below was measured from tiktoken
#               0.14.0, never recalled.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Correctness hazard tests for Knap.

docs/CORRECTNESS.md lists the places where tokenizer implementations diverge
silently. Each gets a test here, with the expected tokens measured from the
reference rather than reasoned about.

These duplicate coverage the corpus gate already provides, and that is the
point. When the corpus gate fails it says "token 19384712 differs", which is
true and nearly useless. When one of these fails it says which hazard broke.
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.tokenizer import Tokenizer, load_cl100k_base_tokenizer

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""


def assert_encodes_to(
    tokenizer: Tokenizer, text: String, expected: List[Int], label: String
) raises:
    """Check that ordinary encoding of one input matches an expected list.

    Args:
        tokenizer: The tokenizer under test.
        text: The input text.
        expected: Token ids measured from the reference implementation.
        label: Hazard name, for the failure message.

    Raises:
        Error: on the first differing token, or on a length mismatch.
    """
    var actual = tokenizer.encode_ordinary(text)
    var limit = len(actual)
    if len(expected) < limit:
        limit = len(expected)
    for index in range(limit):
        if actual[index] != expected[index]:
            raise Error(
                String(
                    t"{label}: token {index} is {actual[index]}, reference"
                    t" says {expected[index]}"
                )
            )
    assert_equal(
        len(actual),
        len(expected),
        String(
            t"{label}: produced {len(actual)} tokens, reference has"
            t" {len(expected)}"
        ),
    )


def test_hazard_alternation_order() raises:
    """The pattern's alternatives are ordered and the first match wins.

    Raises:
        Error: if the contraction alternative does not take priority.

    In "'lla" two alternatives could match at the apostrophe. The contraction
    alternative is listed first and matches "'ll", leaving "a" behind. The
    letter alternative, tried second, would have taken "'lla" whole. An
    implementation that reordered them for convenience would produce
    different tokens here and agree everywhere else.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var expected: List[Int] = [3358, 64]
    assert_encodes_to(
        tokenizer, String("'lla"), expected, String("alternation order")
    )


def test_hazard_contraction_handling() raises:
    """Contractions apply to specific letter sequences, not to apostrophes.

    Raises:
        Error: if contraction handling differs from the reference.

    The rule is case insensitive and covers a fixed set of endings. It is
    not a general apostrophe rule: "'x" is not a contraction, and it splits
    differently as a result.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var lower: List[Int] = [15357, 956]
    assert_encodes_to(
        tokenizer, String("don't"), lower, String("contraction lower")
    )

    var upper: List[Int] = [85741, 17773]
    assert_encodes_to(
        tokenizer, String("DON'T"), upper, String("contraction upper")
    )

    # Not a contraction ending, so the apostrophe attaches differently.
    var not_a_contraction: List[Int] = [6, 87]
    assert_encodes_to(
        tokenizer, String("'x"), not_a_contraction, String("non contraction")
    )


def test_hazard_digit_run_limits() raises:
    """Digits are grouped in bounded runs, so long numbers split.

    Raises:
        Error: if a digit run is not bounded at three.

    A four digit number is two pieces and a seven digit number is three.
    This is the hazard most likely to be missed, because it looks like a bug
    and is not.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var four: List[Int] = [4513, 19]
    assert_encodes_to(tokenizer, String("1234"), four, String("four digits"))

    var seven: List[Int] = [4513, 10961, 22]
    assert_encodes_to(
        tokenizer, String("1234567"), seven, String("seven digits")
    )


def test_hazard_whitespace_lookahead() raises:
    """Trailing whitespace is treated differently from interior whitespace.

    Raises:
        Error: if whitespace at a document boundary is handled wrongly.

    The pattern distinguishes whitespace followed by a visible character
    from whitespace running to the end of input. Errors here appear only at
    document boundaries, which is exactly where they are least likely to be
    noticed by hand.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var trailing: List[Int] = [64, 293, 256]
    assert_encodes_to(
        tokenizer, String("a b  "), trailing, String("trailing whitespace")
    )

    var to_end: List[Int] = [13997, 2355]
    assert_encodes_to(
        tokenizer, String("abc  \n"), to_end, String("whitespace to end")
    )

    var before_visible: List[Int] = [64, 256, 293]
    assert_encodes_to(
        tokenizer,
        String("a   b"),
        before_visible,
        String("whitespace before a visible character"),
    )


def test_hazard_invalid_utf8_is_neither_rejected_nor_replaced() raises:
    """Arbitrary bytes encode and decode without alteration.

    Raises:
        Error: if malformed input is rejected or altered.

    There is no reference for this case, because tiktoken takes decoded text
    and cannot be given undecodable input. What is asserted is Knap's own
    documented policy: the bytes come back exactly, so nothing was rejected,
    replaced, or dropped.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var data = List[UInt8]()
    data.append(UInt8(0x41))
    data.append(UInt8(0xC3))
    data.append(UInt8(0xFF))
    data.append(UInt8(0x80))
    data.append(UInt8(0x42))

    var ids = tokenizer.encode_ordinary_bytes(Span(data))
    assert_true(len(ids) > 0, String("malformed input produced no tokens"))

    var back = tokenizer.decode_bytes(ids)
    assert_equal(len(back), len(data), String("byte count changed"))
    for index in range(len(data)):
        assert_equal(
            back[index],
            data[index],
            String(t"byte {index} was altered"),
        )


def test_hazard_empty_input() raises:
    """Empty input is an empty token list, never an error.

    Raises:
        Error: if empty input raises or invents a token.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var expected = List[Int]()
    assert_encodes_to(tokenizer, String(""), expected, String("empty input"))

    var allowed = List[String]()
    assert_equal(len(tokenizer.encode(String(""), allowed)), 0)

    var no_ids = List[Int]()
    assert_equal(len(tokenizer.decode_bytes(no_ids)), 0)


def test_hazard_special_token_substrings() raises:
    """A special token literal in text follows the allowed and disallowed sets.

    Raises:
        Error: if the marker is mishandled in any of the three modes.

    Three behaviours, one input. Ordinary encoding spells the marker out as
    characters. Encoding with it allowed emits its id. Encoding with it
    disallowed raises, which is the default and the reason this hazard
    matters: untrusted input must not be able to inject a control token.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var marker = String("<|endoftext|>")

    # Spelled out as ordinary characters.
    var as_text: List[Int] = [27, 91, 8862, 728, 428, 91, 29]
    assert_encodes_to(
        tokenizer, marker, as_text, String("marker as ordinary text")
    )

    # Emitted as its own id when permitted.
    var allowed = List[String]()
    allowed.append(marker)
    var permitted = tokenizer.encode(marker, allowed)
    assert_equal(len(permitted), 1)
    assert_equal(permitted[0], 100257)

    # Refused when not permitted.
    var nothing_allowed = List[String]()
    var raised = False
    try:
        var ignored = tokenizer.encode(marker, nothing_allowed)
    except:
        raised = True
    assert_true(raised, String("a disallowed marker must raise, not encode"))


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_hazards.mojo
# =============================================================================
