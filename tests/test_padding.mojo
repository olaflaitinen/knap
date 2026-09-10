# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_padding.mojo
# Purpose     : Holds the padded batch to the encoder, and holds the mask to
#               the thing it is the only record of.
# Stage       : Milestone M9, caller facing helpers. See docs/ROADMAP.md
# Depends on  : knap.tokenizer
# Invariants  : Every masked in id equals the id the encoder produced at
#               that position. Every masked out id is the padding id.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the padded batch.

Padding is arithmetic, which makes it the kind of code that looks obviously
right and is off by one. The tests here compare every position against the
encoder rather than against a shape: a masked in id must equal what
`encode_ordinary` produced at that position, and a masked out id must be the
padding id.

The case worth writing is padding with an id that is also a real token,
because that is what people do. No encoding this library ships defines a
padding token, so callers reuse the end of text marker, and at that point
the ids alone cannot say which columns are content. The mask is the only
record and the test for it has to use an input where the two disagree.

    mojo run -I src tests/test_padding.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from knap.tokenizer import (
    PaddedBatch,
    Tokenizer,
    load_cl100k_base_tokenizer,
)

comptime CL100K_VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Path to the fetched cl100k_base merge vocabulary."""

comptime END_OF_TEXT_ID = 100257
"""The cl100k_base end of text marker, which callers reuse as padding."""


def sample_documents() -> List[String]:
    """Documents of deliberately different lengths.

    Returns:
        Five documents, including an empty one.

    The empty document is the case that makes a row of pure padding, which
    is where an off by one shows up as a row that is one column short.
    """
    var documents: List[String] = [
        String("hello"),
        String(""),
        String("a somewhat longer document with several words in it"),
        String("two words"),
        String("x"),
    ]
    return documents^


def check_batch_against_encoder(
    tokenizer: Tokenizer,
    documents: List[String],
    batch: PaddedBatch,
    pad_id: Int,
    max_tokens: Int,
) raises:
    """Compare every position in a batch against the encoder.

    Args:
        tokenizer: The loaded tokenizer.
        documents: The documents the batch was built from.
        batch: The batch under test.
        pad_id: The id the batch was padded with.
        max_tokens: The truncation width, or zero for none.

    Raises:
        Error: on the first position that disagrees.
    """
    assert_equal(batch.rows, len(documents), String("wrong number of rows"))
    assert_equal(
        len(batch.ids),
        batch.rows * batch.width,
        String("the id buffer is not rows times width"),
    )
    assert_equal(
        len(batch.mask),
        batch.rows * batch.width,
        String("the mask is not the same size as the ids"),
    )

    var widest = 0
    for row in range(batch.rows):
        var encoded = tokenizer.encode_ordinary(documents[row])
        var kept = len(encoded)
        if max_tokens > 0 and kept > max_tokens:
            kept = max_tokens

        assert_equal(
            batch.lengths[row],
            kept,
            String(t"row {row} records the wrong length"),
        )
        if kept > widest:
            widest = kept

        for column in range(batch.width):
            if column < kept:
                assert_equal(
                    batch.id_at(row, column),
                    encoded[column],
                    String(t"row {row} column {column} is not the encoder's"),
                )
                assert_equal(
                    batch.mask_at(row, column),
                    1,
                    String(t"row {row} column {column} is masked out"),
                )
            else:
                assert_equal(
                    batch.id_at(row, column),
                    pad_id,
                    String(t"row {row} column {column} is not the pad id"),
                )
                assert_equal(
                    batch.mask_at(row, column),
                    0,
                    String(t"row {row} column {column} is masked in"),
                )

    assert_equal(
        batch.width,
        widest,
        String("the batch is not as wide as its longest row"),
    )


def test_a_batch_matches_the_encoder_at_every_position() raises:
    """Check an unpadded width against the encoder, position by position.

    Raises:
        Error: on the first position that disagrees.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var documents = sample_documents()
    var batch = tokenizer.pad_ordinary_batch(documents, END_OF_TEXT_ID)
    check_batch_against_encoder(tokenizer, documents, batch, END_OF_TEXT_ID, 0)
    assert_true(batch.width > 1, String("the sample made a trivial batch"))


def test_truncation_cuts_every_row_to_the_width() raises:
    """Check that a width truncates the rows that exceed it.

    Raises:
        Error: if any row is longer than the width, or if a row that fitted
            was cut.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var documents = sample_documents()
    var width = 3
    var batch = tokenizer.pad_ordinary_batch(documents, END_OF_TEXT_ID, width)

    assert_true(
        batch.width <= width,
        String(t"the batch is {batch.width} wide, above the limit {width}"),
    )
    check_batch_against_encoder(
        tokenizer, documents, batch, END_OF_TEXT_ID, width
    )

    var truncated = 0
    for row in range(batch.rows):
        if len(tokenizer.encode_ordinary(documents[row])) > width:
            truncated += 1
    assert_true(
        truncated > 0,
        String(
            "no row was long enough to truncate, so this input did not"
            " exercise the case it was chosen for"
        ),
    )


def test_the_mask_is_the_only_record_when_padding_is_a_real_token() raises:
    """Check the mask on an input where the ids cannot say what is padding.

    Raises:
        Error: if a real token that happens to equal the padding id is
            masked out, or if padding is masked in.

    This is why the mask exists. No encoding here defines a padding token,
    so callers reuse a marker, and then a row whose content genuinely
    contains that id is indistinguishable from padding by id alone.

    The input is built so that the two really do collide: one document
    encodes to a single token whose id is then used as the padding.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var single = String(" the")
    var collide = tokenizer.token_id_of(single)
    assert_true(collide >= 0, String("the fixture word is not a single token"))

    var documents: List[String] = [
        single,
        String("a much longer document than the one above"),
    ]
    var batch = tokenizer.pad_ordinary_batch(documents, collide)

    # Row zero is one real token, then padding, and every column holds the
    # same id. Only the mask separates them.
    assert_equal(batch.lengths[0], 1)
    assert_equal(batch.id_at(0, 0), collide)
    assert_equal(batch.mask_at(0, 0), 1)
    for column in range(1, batch.width):
        assert_equal(
            batch.id_at(0, column),
            collide,
            String("padding should be the id the caller gave"),
        )
        assert_equal(
            batch.mask_at(0, column),
            0,
            String(t"column {column} is padding and is masked in"),
        )

    check_batch_against_encoder(tokenizer, documents, batch, collide, 0)


def test_an_empty_batch_and_an_empty_document() raises:
    """Check the two degenerate shapes.

    Raises:
        Error: if either is refused or produces a malformed batch.

    A batch of no documents has no rows and no width. A batch whose
    documents are all empty has rows and no width, which is a rectangle with
    no columns rather than an error.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))

    var nothing = List[String]()
    var empty_batch = tokenizer.pad_ordinary_batch(nothing, END_OF_TEXT_ID)
    assert_equal(empty_batch.rows, 0)
    assert_equal(empty_batch.width, 0)
    assert_equal(len(empty_batch.ids), 0)

    var blanks: List[String] = [String(""), String("")]
    var blank_batch = tokenizer.pad_ordinary_batch(blanks, END_OF_TEXT_ID)
    assert_equal(blank_batch.rows, 2)
    assert_equal(blank_batch.width, 0)
    assert_equal(len(blank_batch.ids), 0)


def test_impossible_arguments_are_refused() raises:
    """Check that a bad padding id or a negative width raises.

    Raises:
        Error: if either is accepted.

    A padding id outside the id space would put a value into a caller's
    tensor that the model has no embedding for, and the failure would
    surface as a crash somewhere else entirely.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var documents: List[String] = [String("anything")]

    var refused_id = False
    try:
        _ = tokenizer.pad_ordinary_batch(documents, 999999999)
    except:
        refused_id = True
    assert_true(refused_id, String("an out of range padding id was accepted"))

    var refused_negative = False
    try:
        _ = tokenizer.pad_ordinary_batch(documents, END_OF_TEXT_ID, -1)
    except:
        refused_negative = True
    assert_true(refused_negative, String("a negative width was accepted"))


def test_reads_outside_the_rectangle_raise() raises:
    """Check that an out of range read is refused rather than clamped.

    Raises:
        Error: if a read outside the batch returns a value.

    A clamped read returns a real looking id from the wrong place, which is
    the shape of bug that reaches a model as a quietly wrong prompt.
    """
    var tokenizer = load_cl100k_base_tokenizer(String(CL100K_VOCAB))
    var documents: List[String] = [String("hello"), String("world")]
    var batch = tokenizer.pad_ordinary_batch(documents, END_OF_TEXT_ID)

    var refused = False
    try:
        _ = batch.id_at(batch.rows, 0)
    except:
        refused = True
    assert_true(refused, String("a read past the last row was allowed"))

    refused = False
    try:
        _ = batch.mask_at(0, batch.width)
    except:
        refused = True
    assert_true(refused, String("a read past the last column was allowed"))


def main() raises:
    """Discover and run every test function in this module.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_padding.mojo
# =============================================================================
