# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_special.mojo
# Purpose     : Tests the special token registry and the two built in
#               encoding definitions.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : knap.special, knap.vocab
# Invariants  : The registry tests need no fetched file. The definition
#               tests load a real vocabulary and are the check that keeps the
#               hand written id table honest.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the special token registry.

Special token ids are the one part of Knap that is written out by hand rather
than parsed from data, because nothing distributes them as data. That makes
them the most likely place for a transcription mistake, and a wrong id here
would be invisible until someone encoded a document containing that marker.

The defence is the self consistency check in
test_special_tokens_decode_to_their_own_text: every registered special token
must decode to exactly the characters that spell it. The expected bytes come
from the tiktoken generated golden fixture by way of the vocabulary loader,
so a mistyped id fails rather than ships.
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.special import (
    SpecialTokens,
    cl100k_base_specials,
    o200k_base_specials,
)
from knap.vocab import load_cl100k_base, load_o200k_base

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""


def test_registry_add_and_lookup() raises:
    """Check the basic registry operations.

    Raises:
        Error: if a registered token cannot be found again.
    """
    var registry = SpecialTokens()
    assert_equal(registry.count(), 0)
    assert_equal(registry.highest_id(), -1)

    registry.add(String("<|a|>"), 10)
    registry.add(String("<|b|>"), 20)

    assert_equal(registry.count(), 2)
    assert_equal(registry.id_of(String("<|a|>")), 10)
    assert_equal(registry.id_of(String("<|b|>")), 20)
    assert_equal(registry.highest_id(), 20)
    assert_equal(registry.index_of_id(20), 1)
    assert_equal(registry.index_of_id(999), -1)
    assert_equal(registry.name_at(0), String("<|a|>"))
    assert_equal(registry.id_at(1), 20)


def test_registry_rejects_duplicates() raises:
    """Check that neither a repeated name nor a repeated id is accepted.

    Raises:
        Error: if a duplicate registration is allowed.

    Both directions matter. Either kind of duplicate makes the registry
    ambiguous, and an ambiguous registry produces a tokenizer that is wrong
    only sometimes.
    """
    var registry = SpecialTokens()
    registry.add(String("<|a|>"), 10)

    var repeated_name = False
    try:
        registry.add(String("<|a|>"), 11)
    except:
        repeated_name = True
    assert_true(repeated_name, String("a repeated name should raise"))

    var repeated_id = False
    try:
        registry.add(String("<|b|>"), 10)
    except:
        repeated_id = True
    assert_true(repeated_id, String("a repeated id should raise"))

    assert_equal(registry.count(), 1)


def test_registry_reports_unknown_names() raises:
    """Check that looking up an unregistered token raises.

    Raises:
        Error: if an unknown name is resolved instead of reported.
    """
    var registry = SpecialTokens()
    registry.add(String("<|a|>"), 10)

    var raised = False
    try:
        var ignored = registry.id_of(String("<|missing|>"))
    except:
        raised = True
    assert_true(raised, String("an unknown special token should raise"))


def test_builtin_definitions_have_expected_shape() raises:
    """Check the counts and ids of the two built in encodings.

    Raises:
        Error: if a definition has drifted.

    These figures come from tiktoken 0.14.0. They are asserted rather than
    trusted so that a change in either the table or the reference is caught
    at build time.
    """
    var cl100k = cl100k_base_specials()
    assert_equal(cl100k.count(), 5)
    assert_equal(cl100k.id_of(String("<|endoftext|>")), 100257)
    assert_equal(cl100k.id_of(String("<|fim_prefix|>")), 100258)
    assert_equal(cl100k.id_of(String("<|fim_middle|>")), 100259)
    assert_equal(cl100k.id_of(String("<|fim_suffix|>")), 100260)
    assert_equal(cl100k.id_of(String("<|endofprompt|>")), 100276)
    assert_equal(cl100k.highest_id(), 100276)

    var o200k = o200k_base_specials()
    assert_equal(o200k.count(), 2)
    assert_equal(o200k.id_of(String("<|endoftext|>")), 199999)
    assert_equal(o200k.id_of(String("<|endofprompt|>")), 200018)
    assert_equal(o200k.highest_id(), 200018)


def test_special_tokens_decode_to_their_own_text() raises:
    """Check every special token decodes to the characters that spell it.

    Raises:
        Error: if any special token decodes to something else, which would
            mean its id is wrong.

    This is the check that keeps the hand written id table honest. A special
    token decodes to its own literal text, so comparing the decode against
    the registered name catches a mistyped id without needing a separate
    fixture.
    """
    var cl100k = load_cl100k_base(String(CL100K_VOCAB))
    for index in range(cl100k.specials.count()):
        var name = cl100k.specials.name_at(index)
        var token_id = cl100k.specials.id_at(index)
        assert_equal(
            cl100k.decode([token_id]),
            name,
            String(t"cl100k_base id {token_id} should decode to '{name}'"),
        )

    var o200k = load_o200k_base(String(O200K_VOCAB))
    for index in range(o200k.specials.count()):
        var name = o200k.specials.name_at(index)
        var token_id = o200k.specials.id_at(index)
        assert_equal(
            o200k.decode([token_id]),
            name,
            String(t"o200k_base id {token_id} should decode to '{name}'"),
        )


def test_special_ids_sit_above_the_merge_ranks() raises:
    """Check that no special token collides with a merge rank.

    Raises:
        Error: if a special token id falls inside the merge range.

    A collision would make that id ambiguous. The Vocabulary constructor
    rejects it, and this asserts the real definitions do not trip that check.
    """
    var cl100k = load_cl100k_base(String(CL100K_VOCAB))
    for index in range(cl100k.specials.count()):
        assert_true(
            cl100k.specials.id_at(index) >= cl100k.merge_count(),
            String("a cl100k_base special token overlaps a merge rank"),
        )

    # The gaps either side of the specials are genuine and must stay
    # unassigned, which is what makes them undecodable.
    assert_true(
        not cl100k.is_assigned(100256),
        String("id 100256 should be unassigned in cl100k_base"),
    )
    assert_true(
        not cl100k.is_assigned(100275),
        String("id 100275 should be unassigned in cl100k_base"),
    )
    assert_true(
        cl100k.is_assigned(100276),
        String("id 100276 should be assigned in cl100k_base"),
    )


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_special.mojo
# =============================================================================
