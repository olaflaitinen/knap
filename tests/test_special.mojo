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
    gpt2_specials,
    o200k_base_specials,
    o200k_harmony_specials,
    p50k_base_specials,
    p50k_edit_specials,
)
from knap.vocab import load_cl100k_base, load_o200k_base, load_p50k_base

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime O200K_VOCAB = "tests/fixtures/vocabs/o200k_base.tiktoken"
"""Path to the fetched o200k_base merge vocabulary."""

comptime P50K_VOCAB = "tests/fixtures/vocabs/p50k_base.tiktoken"
"""Path to the fetched p50k_base vocabulary, shared with p50k_edit."""


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


def test_registry_rejects_a_repeated_name() raises:
    """A name may map to one id and no more.

    Raises:
        Error: if a second id is accepted for a name already registered.

    This half of the rule is absolute. Encoding a name that maps to two ids
    would have to choose, and either choice is wrong half the time.
    """
    var registry = SpecialTokens()
    registry.add(String("<|a|>"), 10)

    var refused = False
    try:
        registry.add(String("<|a|>"), 11)
    except:
        refused = True
    assert_true(refused, String("a repeated name should raise"))
    assert_equal(registry.count(), 1)


def test_registry_accepts_a_repeated_id_and_keeps_the_first_name() raises:
    """An id may carry several names, and the first one decodes.

    Raises:
        Error: if a second name for one id is refused, or if the wrong one
            wins.

    This is not a hypothetical. o200k_harmony gives id 200018 both
    `<|endofprompt|>` and `<|reserved_200018|>`, and the reference
    implementation decodes it to the first. Encoding either name is
    unambiguous, so there is nothing to refuse.

    The registry was stricter than this until the seventh encoding was
    implemented, and refusing here would have made o200k_harmony
    unrepresentable rather than merely unusual.
    """
    var registry = SpecialTokens()
    registry.add(String("<|first|>"), 10)
    registry.add(String("<|second|>"), 10)

    assert_equal(registry.count(), 2)
    assert_equal(registry.id_of(String("<|first|>")), 10)
    assert_equal(registry.id_of(String("<|second|>")), 10)

    # Decoding has to choose, and it chooses the first registration.
    assert_equal(
        registry.name_at(registry.index_of_id(10)), String("<|first|>")
    )


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
    """Check the counts and ids of the seven built in registries.

    Raises:
        Error: if a definition has drifted.

    These figures come from tiktoken 0.14.0. They are asserted rather than
    trusted so that a change in either the table or the reference is caught
    at build time.

    The counts alone are worth asserting. o200k_harmony's registry is built
    by naming ten tokens and then sweeping a range, and a sweep that skipped
    one id too many or too few would still produce a plausible looking
    registry that this catches immediately.
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

    var harmony = o200k_harmony_specials()
    assert_equal(harmony.count(), 1091)
    assert_equal(harmony.id_of(String("<|startoftext|>")), 199998)
    assert_equal(harmony.id_of(String("<|endoftext|>")), 199999)
    assert_equal(harmony.id_of(String("<|return|>")), 200002)
    assert_equal(harmony.id_of(String("<|constrain|>")), 200003)
    assert_equal(harmony.id_of(String("<|channel|>")), 200005)
    assert_equal(harmony.id_of(String("<|start|>")), 200006)
    assert_equal(harmony.id_of(String("<|end|>")), 200007)
    assert_equal(harmony.id_of(String("<|message|>")), 200008)
    assert_equal(harmony.id_of(String("<|call|>")), 200012)
    assert_equal(harmony.id_of(String("<|endofprompt|>")), 200018)
    assert_equal(harmony.highest_id(), 201087)

    var gpt2 = gpt2_specials()
    assert_equal(gpt2.count(), 1)
    assert_equal(gpt2.id_of(String("<|endoftext|>")), 50256)
    assert_equal(gpt2.highest_id(), 50256)

    var p50k = p50k_base_specials()
    assert_equal(p50k.count(), 1)
    assert_equal(p50k.id_of(String("<|endoftext|>")), 50256)
    assert_equal(p50k.highest_id(), 50256)

    var p50k_edit = p50k_edit_specials()
    assert_equal(p50k_edit.count(), 4)
    assert_equal(p50k_edit.id_of(String("<|endoftext|>")), 50256)
    assert_equal(p50k_edit.id_of(String("<|fim_prefix|>")), 50281)
    assert_equal(p50k_edit.id_of(String("<|fim_middle|>")), 50282)
    assert_equal(p50k_edit.id_of(String("<|fim_suffix|>")), 50283)
    assert_equal(p50k_edit.highest_id(), 50283)


def test_special_tokens_decode_to_their_own_text() raises:
    """Check every special token decodes to the characters that spell it.

    Raises:
        Error: if any special token decodes to something else, which would
            mean its id is wrong.

    This is the check that keeps the hand written id table honest. A special
    token decodes to its own literal text, so comparing the decode against
    the registered name catches a mistyped id without needing a separate
    fixture.

    Three registries are checked here rather than all seven, because
    tests/test_decode.mojo already decodes every id in every encoding
    against a tiktoken fixture and would catch a misplaced name there.
    What that gate does not isolate is the lookup path, and p50k_base is
    the one encoding whose special token is reached by a different route:
    its id sits on a reserved merge rank rather than above the merges.
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

    # p50k_base's marker sits at 50256, which is a hole in its merge table
    # rather than an id above it. The lookup used to test the merge range
    # instead of asking the merge table whether the rank was assigned, so it
    # found the hole and refused to decode the one special token this
    # encoding has. Every caller decoding a p50k_base document that ends in
    # a marker would have hit it.
    var p50k = load_p50k_base(String(P50K_VOCAB))
    assert_equal(p50k.merge_count(), 50281)
    assert_true(
        p50k.is_assigned(50256),
        String("p50k_base id 50256 is its end of text marker"),
    )
    for index in range(p50k.specials.count()):
        var name = p50k.specials.name_at(index)
        var token_id = p50k.specials.id_at(index)
        assert_equal(
            p50k.decode([token_id]),
            name,
            String(t"p50k_base id {token_id} should decode to '{name}'"),
        )


def test_special_ids_never_take_an_assigned_merge_rank() raises:
    """Check that no special token takes an id a merge token already holds.

    Raises:
        Error: if a special token id names an assigned merge rank.

    A collision would make that id ambiguous. The Vocabulary constructor
    rejects it, and this asserts the real definitions do not trip that check.

    This test used to assert something stronger and simpler: that special
    ids sit above the merge ranks. That was true of the two encodings
    shipped when it was written and is false of p50k_base, whose marker is
    at 50256 while its merge ranks run to 50280. The weaker statement is the
    one that holds for all seven, and it is also the one the constructor
    actually enforces, so the test now says what the code means.
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

    # p50k_base is the counterexample the old wording did not survive. Its
    # special token id is inside the merge range and below merge_count, and
    # that is legal precisely because the rank it lands on is reserved.
    var p50k = load_p50k_base(String(P50K_VOCAB))
    assert_equal(p50k.specials.count(), 1)
    assert_equal(p50k.specials.id_at(0), 50256)
    assert_true(
        p50k.specials.id_at(0) < p50k.merge_count(),
        String("p50k_base's marker is inside the merge range, not above it"),
    )
    assert_true(
        p50k.is_assigned(50255) and p50k.is_assigned(50257),
        String("the merge ranks either side of 50256 are assigned"),
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
