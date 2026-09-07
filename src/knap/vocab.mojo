# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/vocab.mojo
# Purpose     : Parses .tiktoken vocabulary files, and joins merge tokens with
#               special tokens into one addressable id space.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : flat_vocab.mojo, special.mojo, errors.mojo, std.base64
# Invariants  : Merge ranks must be unique, non-negative, and dense from zero.
#               The combined id space is NOT dense: gaps between merges and
#               specials are real and stay undecodable.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Vocabulary loading for Knap.

A .tiktoken file is a flat text format: one entry per line, holding a base64
encoded token, a single space, and a decimal rank. The rank is the token id.

Loading is strict on purpose. Every way the file can be wrong raises a named
error identifying the line, because a vocabulary that loads with one token
quietly missing produces a tokenizer that is correct on almost every input
and wrong on a few, which is the hardest kind of defect to find.

Vocabulary files are fetched rather than committed. Run
"python scripts/fetch_vocabs.py" before any test that needs one.
"""

from std.base64 import b64decode

from .errors import (
    token_id_out_of_range,
    vocabulary_duplicate_rank,
    vocabulary_file_missing,
    vocabulary_malformed_line,
    vocabulary_rank_out_of_range,
)
from .flat_vocab import FlatVocab
from .special import (
    SpecialTokens,
    cl100k_base_specials,
    o200k_base_specials,
)


# -----------------------------------------------------------------------------
# Loading merge tokens
#
# The load runs in two passes. The first decodes every token into one staging
# buffer while recording where each landed and what rank it claimed. The
# second lays the tokens out in rank order, which is what makes a token id a
# direct index rather than a lookup.
#
# Two passes are used rather than one because the file is not required to be
# sorted by rank. Assuming sorted input would work on both target
# vocabularies today and break silently on any file that is not.
# -----------------------------------------------------------------------------


def load_tiktoken(path: String) raises -> FlatVocab:
    """Load a .tiktoken vocabulary file into a FlatVocab.

    Args:
        path: Path to the .tiktoken file to read.

    Returns:
        A FlatVocab holding every merge token, indexed by its rank.

    Raises:
        Error: if the file cannot be opened, if any line is malformed, if a
            rank repeats, if a rank is negative, or if the ranks do not cover
            zero through the maximum without a gap.

    This loads merge tokens only. Special tokens are not present in a
    .tiktoken file and are registered separately, in special.mojo.
    """
    var text: String
    try:
        var handle = open(path, "r")
        text = handle.read()
        handle.close()
    except:
        raise vocabulary_file_missing(path)

    var lines = text.splitlines()

    # Pass one. Decode each token into a staging buffer and remember the rank
    # it claimed. Parallel arrays are used rather than a list of lists so the
    # whole vocabulary is a handful of allocations rather than one per token.
    var staging = List[UInt8]()
    var stage_offset = List[Int]()
    var stage_length = List[Int]()
    var stage_rank = List[Int]()

    var highest_rank = -1

    for index in range(len(lines)):
        var line = String(lines[index])
        var line_number = index + 1

        # A trailing blank line is normal at end of file and is not an error.
        if line.strip().byte_length() == 0:
            continue

        var parts = line.split(" ")
        if len(parts) != 2:
            raise vocabulary_malformed_line(
                path,
                line_number,
                String(
                    t"expected 2 space separated fields, found {len(parts)}"
                ),
            )

        var encoded = String(parts[0])
        var rank_text = String(parts[1]).strip()

        var token: List[UInt8]
        try:
            # validate=True rejects anything that is not well formed base64,
            # rather than decoding it to arbitrary bytes.
            token = b64decode[validate=True](encoded)
        except:
            raise vocabulary_malformed_line(
                path, line_number, String("token is not valid base64")
            )

        var rank: Int
        try:
            rank = Int(rank_text)
        except:
            raise vocabulary_malformed_line(
                path,
                line_number,
                String(t"rank '{rank_text}' is not a decimal integer"),
            )

        if rank < 0:
            raise vocabulary_rank_out_of_range(path, line_number, rank)

        stage_offset.append(len(staging))
        stage_length.append(len(token))
        stage_rank.append(rank)
        for byte_index in range(len(token)):
            staging.append(token[byte_index])

        if rank > highest_rank:
            highest_rank = rank

    if highest_rank < 0:
        raise vocabulary_malformed_line(
            path, 0, String("file contains no vocabulary entries")
        )

    # Pass two. Map rank to the staging entry that claimed it, so that gaps
    # and repeats are both detected before any bytes are copied.
    var vocabulary_size = highest_rank + 1
    var source_of_rank = List[Int](capacity=vocabulary_size)
    for _ in range(vocabulary_size):
        source_of_rank.append(-1)

    for entry in range(len(stage_rank)):
        var rank = stage_rank[entry]
        if source_of_rank[rank] != -1:
            raise vocabulary_duplicate_rank(path, entry + 1, rank)
        source_of_rank[rank] = entry

    for rank in range(vocabulary_size):
        if source_of_rank[rank] == -1:
            raise vocabulary_malformed_line(
                path,
                0,
                String(
                    t"rank {rank} has no token, but ranks up to"
                    t" {highest_rank} are present. Merge ranks must be dense."
                ),
            )

    # Lay the tokens out in rank order. Offsets are a running total, so the
    # result is one contiguous buffer with no padding between tokens.
    var data = List[UInt8](capacity=len(staging))
    var offsets = List[Int](capacity=vocabulary_size)
    var lengths = List[Int](capacity=vocabulary_size)

    for rank in range(vocabulary_size):
        var entry = source_of_rank[rank]
        var start = stage_offset[entry]
        var length = stage_length[entry]

        offsets.append(len(data))
        lengths.append(length)
        for byte_index in range(length):
            data.append(staging[start + byte_index])

    return FlatVocab(data^, offsets^, lengths^)


# -----------------------------------------------------------------------------
# The full vocabulary
#
# A .tiktoken file holds merge tokens only. The complete token id space an
# encoding exposes is wider, and it is not contiguous:
#
#     cl100k_base   merges 0 to 100255, specials 100257 to 100276,
#                   and 16 ids in between assigned to nothing
#     o200k_base    merges 0 to 199997, specials 199999 and 200018,
#                   and 19 ids assigned to nothing
#
# Those gaps are real. tiktoken raises when asked to decode one, and so does
# Knap. Returning empty bytes instead would look tidier and would diverge
# from the reference on exactly the inputs where a caller needs to be told
# that something upstream is wrong.
# -----------------------------------------------------------------------------


struct Vocabulary(Copyable, Movable):
    """A complete encoding: merge tokens, special tokens, and its name."""

    var merges: FlatVocab
    """The merge tokens, indexed by rank."""

    var specials: SpecialTokens
    """The special tokens, which sit above the merge ranks."""

    var name: String
    """The encoding name, used in diagnostics."""

    def __init__(
        out self,
        var merges: FlatVocab,
        var specials: SpecialTokens,
        var name: String,
    ) raises:
        """Combine merge tokens and special tokens into one vocabulary.

        Args:
            merges: Loaded merge tokens.
            specials: Registered special tokens.
            name: Encoding name, used in diagnostics.

        Raises:
            Error: if a special token id collides with a merge rank, which
                would make that id ambiguous.
        """
        var merge_count = merges.size()
        for index in range(specials.count()):
            var special_id = specials.id_at(index)
            if special_id < merge_count:
                var text = specials.name_at(index)
                var message = String(
                    t"knap: special token '{text}' claims id {special_id},"
                )
                message += String(
                    t" which is already a merge rank in a vocabulary of"
                )
                message += String(t" {merge_count} merges.")
                raise Error(message)

        self.merges = merges^
        self.specials = specials^
        self.name = name^

    def merge_count(self) -> Int:
        """Return how many merge tokens this vocabulary holds.

        Returns:
            The count of merge tokens, so merge ranks run from zero to this
            value minus one.
        """
        return self.merges.size()

    def id_space_size(self) -> Int:
        """Return one past the highest assigned token id.

        Returns:
            The size of the id space, matching what tiktoken calls n_vocab.

        This is not the number of decodable ids. The space contains gaps, so
        the count of assigned ids is strictly smaller than this value.
        """
        var highest_special = self.specials.highest_id()
        if highest_special < self.merges.size():
            return self.merges.size()
        return highest_special + 1

    def is_assigned(self, token_id: Int) -> Bool:
        """Report whether a token id decodes to anything.

        Args:
            token_id: The id to test.

        Returns:
            True when the id is a merge rank or a registered special token.

        Callers that want to skip unassigned ids rather than handle an error
        should test with this first, so the error path stays reserved for
        genuine mistakes.
        """
        if token_id < 0:
            return False
        if token_id < self.merges.size():
            return True
        return self.specials.index_of_id(token_id) != -1

    def append_token(self, token_id: Int, mut out: List[UInt8]) raises:
        """Append one token's bytes to a caller supplied buffer.

        Args:
            token_id: The id to append.
            out: Buffer to append into. "mut" marks it a mutable reference,
                so the caller sees the appended bytes.

        Raises:
            Error: if the id is unassigned, which covers both the gaps
                between merge ranks and specials, and anything past the end.

        A special token decodes to its own literal text, so the end of text
        marker decodes to the characters that spell it rather than to
        anything hidden.
        """
        if token_id >= 0 and token_id < self.merges.size():
            self.merges.append_token(token_id, out)
            return

        var position = self.specials.index_of_id(token_id)
        if position == -1:
            raise token_id_out_of_range(token_id, self.id_space_size())

        var text = self.specials.name_at(position)
        var text_bytes = text.as_bytes()
        for index in range(len(text_bytes)):
            out.append(text_bytes[index])

    def token_bytes(self, token_id: Int) raises -> List[UInt8]:
        """Return a copy of one token's bytes.

        Args:
            token_id: The id to look up.

        Returns:
            A newly allocated list holding that token's bytes.

        Raises:
            Error: if the id is unassigned.
        """
        var out = List[UInt8]()
        self.append_token(token_id, out)
        return out^

    def decode_bytes(self, token_ids: List[Int]) raises -> List[UInt8]:
        """Decode a sequence of token ids to the exact bytes they represent.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            The concatenated token bytes.

        Raises:
            Error: if any id is unassigned. Nothing is returned in that case,
                so a caller never receives a partial decode that looks whole.

        Empty input returns an empty list rather than an error.
        """
        var out = List[UInt8]()
        for index in range(len(token_ids)):
            self.append_token(token_ids[index], out)
        return out^

    def decode(self, token_ids: List[Int]) raises -> String:
        """Decode a sequence of token ids to text.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            A String holding the decoded bytes, unvalidated.

        Raises:
            Error: if any id is unassigned.

        The result is not checked for well formed UTF-8, because byte level
        BPE can legitimately produce a partial sequence when a caller decodes
        a slice of a longer token list.
        """
        var raw = self.decode_bytes(token_ids)
        return String(unsafe_from_utf8=Span(raw))


def load_cl100k_base(path: String) raises -> Vocabulary:
    """Load the cl100k_base encoding from its .tiktoken file.

    Args:
        path: Path to cl100k_base.tiktoken.

    Returns:
        The complete vocabulary, merges and specials together.

    Raises:
        Error: if the file is missing or malformed.
    """
    var merges = load_tiktoken(path)
    var specials = cl100k_base_specials()
    return Vocabulary(merges^, specials^, String("cl100k_base"))


def load_o200k_base(path: String) raises -> Vocabulary:
    """Load the o200k_base encoding from its .tiktoken file.

    Args:
        path: Path to o200k_base.tiktoken.

    Returns:
        The complete vocabulary, merges and specials together.

    Raises:
        Error: if the file is missing or malformed.
    """
    var merges = load_tiktoken(path)
    var specials = o200k_base_specials()
    return Vocabulary(merges^, specials^, String("o200k_base"))


# =============================================================================
# End of file: src/knap/vocab.mojo
# =============================================================================
