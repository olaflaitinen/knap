# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_vocab.mojo
# Purpose     : Tests the .tiktoken loader, especially every way a vocabulary
#               file can be malformed.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : knap.vocab
# Invariants  : Every fixture is written to a temporary path by the test
#               itself, so these run without any fetched file.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the .tiktoken vocabulary loader.

The happy path is covered by tests/test_decode.mojo, which loads both real
vocabularies and checks all three hundred thousand tokens. This file covers
the opposite: every way a vocabulary file can be wrong.

That emphasis is deliberate. A loader that silently tolerates a malformed
line produces a tokenizer that is correct on almost every input and wrong on
a few, and the wrongness surfaces as a mysterious divergence months later
rather than as a loading error now.

Each test writes its own fixture to a temporary file, so nothing here depends
on a fetched vocabulary.
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.vocab import load_tiktoken


def write_fixture(path: String, contents: String) raises:
    """Write a synthetic vocabulary file for one test.

    Args:
        path: Where to write it.
        contents: The exact file contents.

    Raises:
        Error: if the file cannot be written.
    """
    var handle = open(path, "w")
    handle.write(contents)
    handle.close()


def loading_fails(path: String, contents: String) raises -> Bool:
    """Write a fixture and report whether loading it raises.

    Args:
        path: Where to write the fixture.
        contents: The file contents to test.

    Returns:
        True when the loader rejected the file.

    Raises:
        Error: if the fixture cannot be written, which is a problem with the
            test rather than with the loader.
    """
    write_fixture(path, contents)
    try:
        var ignored = load_tiktoken(path)
        return False
    except:
        return True


def test_loads_a_well_formed_file() raises:
    """Check the loader accepts a minimal valid vocabulary.

    Raises:
        Error: if a valid file fails to load or loads incorrectly.

    The fixture holds base64 for "a", "b", and "ab" at ranks 0, 1, and 2.
    """
    var path = String("/tmp/knap_test_valid.tiktoken")
    write_fixture(path, String("YQ== 0\nYg== 1\nYWI= 2\n"))

    var vocabulary = load_tiktoken(path)
    assert_equal(vocabulary.size(), 3)
    assert_equal(vocabulary.decode([0]), String("a"))
    assert_equal(vocabulary.decode([1]), String("b"))
    assert_equal(vocabulary.decode([2]), String("ab"))
    assert_equal(vocabulary.decode([0, 1, 2]), String("abab"))


def test_ranks_may_arrive_out_of_order() raises:
    """Check that a file is not required to be sorted by rank.

    Raises:
        Error: if an unsorted file loads to the wrong layout.

    The loader uses two passes precisely so it does not depend on ordering.
    Assuming sorted input would work on both real vocabularies today and
    break silently on any file that is not.
    """
    var path = String("/tmp/knap_test_unsorted.tiktoken")
    write_fixture(path, String("YWI= 2\nYQ== 0\nYg== 1\n"))

    var vocabulary = load_tiktoken(path)
    assert_equal(vocabulary.size(), 3)
    assert_equal(vocabulary.decode([0]), String("a"))
    assert_equal(vocabulary.decode([2]), String("ab"))


def test_trailing_blank_lines_are_tolerated() raises:
    """Check that blank lines at end of file are not an error.

    Raises:
        Error: if a trailing newline causes a spurious failure.

    A file ending in a newline is normal, and rejecting it would make the
    loader fail on correct input.
    """
    var path = String("/tmp/knap_test_blank.tiktoken")
    write_fixture(path, String("YQ== 0\nYg== 1\n\n\n"))

    var vocabulary = load_tiktoken(path)
    assert_equal(vocabulary.size(), 2)


def test_missing_file_is_reported() raises:
    """Check that an absent vocabulary file raises rather than crashing.

    Raises:
        Error: if opening a missing file does not raise.
    """
    var raised = False
    try:
        var ignored = load_tiktoken(
            String("/tmp/knap_test_does_not_exist.tiktoken")
        )
    except:
        raised = True
    assert_true(raised, String("a missing vocabulary file should raise"))


def test_malformed_files_are_rejected() raises:
    """Check that every shape of malformed line is refused.

    Raises:
        Error: if the loader accepts a file it should reject.

    Each case below is a distinct failure mode, and each would produce a
    quietly wrong tokenizer if tolerated.
    """
    # A line with one field instead of two.
    assert_true(
        loading_fails(
            String("/tmp/knap_test_one_field.tiktoken"), String("YQ==\n")
        ),
        String("a line with no rank should be rejected"),
    )

    # A line with three fields.
    assert_true(
        loading_fails(
            String("/tmp/knap_test_three.tiktoken"), String("YQ== 0 extra\n")
        ),
        String("a line with a trailing field should be rejected"),
    )

    # A token that is not valid base64.
    assert_true(
        loading_fails(
            String("/tmp/knap_test_b64.tiktoken"), String("not!base64 0\n")
        ),
        String("an invalid base64 token should be rejected"),
    )

    # A rank that is not an integer.
    assert_true(
        loading_fails(
            String("/tmp/knap_test_rank.tiktoken"), String("YQ== zero\n")
        ),
        String("a non numeric rank should be rejected"),
    )

    # A negative rank.
    assert_true(
        loading_fails(
            String("/tmp/knap_test_negative.tiktoken"), String("YQ== -1\n")
        ),
        String("a negative rank should be rejected"),
    )

    # An empty file.
    assert_true(
        loading_fails(String("/tmp/knap_test_empty.tiktoken"), String("")),
        String("a file with no entries should be rejected"),
    )


def test_duplicate_rank_is_rejected() raises:
    """Check that two tokens cannot claim the same id.

    Raises:
        Error: if a duplicate rank is silently accepted.

    A silent overwrite would make one token unreachable and would make decode
    ambiguous, shifting nothing visible until the affected token appeared in
    real input.
    """
    assert_true(
        loading_fails(
            String("/tmp/knap_test_dup.tiktoken"),
            String("YQ== 0\nYg== 0\n"),
        ),
        String("a duplicate rank should be rejected"),
    )


def test_gap_in_ranks_is_rejected() raises:
    """Check that merge ranks must be dense from zero.

    Raises:
        Error: if a gap in the merge ranks is accepted.

    A hole in the merge ranks would leave a token id that indexes into the
    vocabulary and decodes to nothing. Note that the combined id space of a
    full encoding does have holes, between the merges and the specials, but
    the merge ranks themselves must be contiguous.
    """
    assert_true(
        loading_fails(
            String("/tmp/knap_test_gap.tiktoken"),
            String("YQ== 0\nYg== 2\n"),
        ),
        String("a gap in the merge ranks should be rejected"),
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_vocab.mojo
# =============================================================================
