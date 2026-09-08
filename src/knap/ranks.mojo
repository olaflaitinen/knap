# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/ranks.mojo
# Purpose     : Merge rank table: maps a byte sequence to its merge rank,
#               which is also its token id.
# Stage       : Pipeline stage 4 of 4, see docs/ARCHITECTURE.md
# Depends on  : flat_vocab.mojo
# Invariants  : Every single byte value from 0 to 255 must be present, since
#               byte level BPE starts from individual bytes and the merge
#               loop's final lookup must always succeed.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Merge rank lookup for Knap.

The merge loop asks one question over and over: what is the rank of this
byte sequence, and is it ranked at all. This module answers it.

The table is a hash map keyed on the token's bytes, which is what tiktoken
does. Starting anywhere more clever would be optimising before measuring,
and docs/BENCHMARKS.md is where that decision belongs.

One point about the key type. Token byte strings are frequently not valid
UTF-8, because a multi-byte character is routinely split across several
tokens. Mojo's String is used purely as a byte container here: it is built
without validation and compared by bytes, so a lone continuation byte is a
perfectly good key. It is never printed or treated as text.
"""

from .flat_vocab import FlatVocab

comptime UNRANKED: Int = -1
"""Returned when a byte sequence has no merge rank."""

comptime BYTE_VALUES: Int = 256
"""Number of distinct single byte tokens a byte level vocabulary must hold."""


def bytes_key(data: Span[UInt8, _], start: Int, end: Int) -> String:
    """Build a lookup key from a byte range.

    Args:
        data: The bytes to slice.
        start: Inclusive start offset.
        end: Exclusive end offset.

    Returns:
        A String holding exactly those bytes, unvalidated.

    This allocates, which is the single largest cost in the merge loop and
    the obvious first target if encode throughput ever needs improving. It
    is left alone for now because correctness comes first and because the
    right fix is a map keyed on a borrowed span, which is a larger change
    than it looks.
    """
    var out = List[UInt8](capacity=end - start)
    for index in range(start, end):
        out.append(data[index])
    return String(unsafe_from_utf8=Span(out))


struct RankTable(Copyable, Movable):
    """Maps a token's bytes to its merge rank."""

    var table: Dict[String, Int]
    """Byte sequence to rank. The rank is also the token id."""

    def __init__(out self, vocabulary: FlatVocab) raises:
        """Build the rank table from a loaded vocabulary.

        Args:
            vocabulary: The merge tokens, indexed by rank.

        Raises:
            Error: if any single byte value is missing. Byte level BPE
                begins by treating every input byte as its own token, so a
                vocabulary without all 256 of them could not encode some
                inputs at all, and the failure would appear as a crash deep
                in the merge loop rather than as a loading error.

        Building costs one String allocation per token, so roughly a hundred
        thousand for cl100k_base. That is paid once at load time.
        """
        self.table = Dict[String, Int]()

        var size = vocabulary.size()
        for token_id in range(size):
            var token = vocabulary.token_bytes(token_id)
            self.table[String(unsafe_from_utf8=Span(token))] = token_id

        # Every byte must be representable on its own.
        var missing = 0
        for value in range(BYTE_VALUES):
            var single = List[UInt8](capacity=1)
            single.append(UInt8(value))
            if String(unsafe_from_utf8=Span(single)) not in self.table:
                missing += 1
        if missing != 0:
            var message = String(
                t"knap: the vocabulary is missing {missing} of the 256"
            )
            message += String(
                " single byte tokens. A byte level vocabulary must be able"
            )
            message += String(" to represent every byte on its own.")
            raise Error(message)

    def size(self) -> Int:
        """Return how many ranked sequences the table holds.

        Returns:
            The number of entries.
        """
        return len(self.table)

    def rank_of(self, data: Span[UInt8, _], start: Int, end: Int) raises -> Int:
        """Look up the merge rank of one byte range.

        Args:
            data: The bytes to slice.
            start: Inclusive start offset.
            end: Exclusive end offset.

        Returns:
            The rank, or UNRANKED when the sequence is not a token.

        Raises:
            Error: never in normal operation. The signature carries raises
                because building the key can, in principle, fail.

        An unranked pair is not an error. It is the ordinary signal that a
        pair cannot be merged, and the merge loop stops when every remaining
        adjacent pair is unranked.
        """
        var key = bytes_key(data, start, end)
        var found = self.table.get(key)
        if found:
            return found.value()
        return UNRANKED

    def token_of(
        self, data: Span[UInt8, _], start: Int, end: Int
    ) raises -> Int:
        """Look up the token id of a byte range that must be a token.

        Args:
            data: The bytes to slice.
            start: Inclusive start offset.
            end: Exclusive end offset.

        Returns:
            The token id.

        Raises:
            Error: if the range is not a token at all. Every piece the merge
                loop finishes with must be in the vocabulary, so reaching
                this means the loop stopped somewhere it should not have.
        """
        var rank = self.rank_of(data, start, end)
        if rank == UNRANKED:
            raise Error(
                String(
                    t"knap: the byte range [{start}, {end}) is not a token."
                    t" The merge loop should not have produced it."
                )
            )
        return rank


# =============================================================================
# End of file: src/knap/ranks.mojo
# =============================================================================
