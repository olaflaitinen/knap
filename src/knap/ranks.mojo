# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/ranks.mojo
# Purpose     : Merge rank table: maps a byte sequence to its merge rank,
#               which is also its token id.
# Stage       : Pipeline stage 4 of 4, see docs/ARCHITECTURE.md
# Depends on  : byte_map.mojo, flat_vocab.mojo
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

The table is a hash map keyed on the token's bytes, which is what the
reference implementation does. What differs is the key type, and the reason
is a measurement rather than a preference.

The first version used `Dict[String, Int]`. That is the obvious structure
and it is correct, but a String key has to own its bytes, so every lookup
copied the range being asked about into a fresh allocation before anything
was compared. The merge loop is quadratic in the piece length, so a five
byte piece paid ten allocations to answer ten questions about bytes the
caller already held.

That cost was invisible until the benchmark corpus was fixed. Earlier runs
measured a prefix of the corpus, which is a generated hazard section whose
pieces are about two bytes long, where the quadratic term barely engages. On
prose, where pieces run four to six bytes, throughput was five times lower.
See docs/BENCHMARKS.md for the before and after.

So the keys live in a flat arena inside `ByteMap`, and a lookup hashes the
caller's bytes where they already are. The merge loop itself is unchanged
and is still quadratic, deliberately: it is a clear and obviously correct
algorithm, and removing an allocation is a far smaller claim than replacing
it. If the quadratic term ever becomes the cost, it is the next thing to
look at, and by then there will be a number saying so.

One point about token bytes. They are frequently not valid UTF-8, because a
multi-byte character is routinely split across several tokens. Nothing here
treats them as text, which is one more reason a byte keyed map fits better
than a string keyed one.
"""

from .byte_map import MISSING, ByteMap
from .flat_vocab import FlatVocab

comptime UNRANKED: Int = MISSING
"""Returned when a byte sequence has no merge rank.

Deliberately the same value the map returns for an absent key, so the two
cannot drift apart. Ranks are never negative, so a negative result is
unambiguous.
"""

comptime BYTE_VALUES: Int = 256
"""Number of distinct single byte tokens a byte level vocabulary must hold."""

comptime KEY_BYTES_PER_TOKEN: Int = 8
"""Rough average token length, used only to reserve the key arena.

Being wrong costs one reallocation while loading, and nothing afterwards.
"""


struct RankTable(Movable):
    """Maps a token's bytes to its merge rank.

    Movable and not Copyable on purpose. The table holds a hundred thousand
    keys and their bytes, and an accidental copy would be an expensive thing
    to do silently. Making the compiler refuse one costs less than finding
    it in a profile later.
    """

    var map: ByteMap
    """Byte sequence to rank. The rank is also the token id."""

    var singles: List[Int]
    """Rank of each of the 256 single byte tokens, indexed by byte value.

    A direct array rather than a hash lookup. Every piece starts as one part
    per byte, so this is the most asked question in the encoder, and it has
    exactly 256 possible answers. Building the array costs 256 lookups once
    at load time and removes a hash of every input byte from every piece.
    """

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

        The map is sized from the vocabulary up front, so it never rehashes
        and a lookup costs the same at the end of a document as at the
        start.
        """
        var size = vocabulary.size()
        self.map = ByteMap(size, size * KEY_BYTES_PER_TOKEN)

        for token_id in range(size):
            # A reserved rank has no bytes and nothing to key on. p50k_base
            # has one, at 50256, where its special token sits. Reading it
            # would raise, and inserting an empty key would make the empty
            # string a merge token, which is worse.
            if not vocabulary.is_assigned(token_id):
                continue
            var token = vocabulary.token_bytes(token_id)
            _ = self.map.insert(Span(token), 0, len(token), token_id)

        # Every byte must be representable on its own, and its rank is
        # kept so the encoder never has to hash a single byte again.
        var single = List[UInt8](capacity=1)
        single.append(UInt8(0))
        self.singles = List[Int](capacity=BYTE_VALUES)
        var missing = 0
        for value in range(BYTE_VALUES):
            single[0] = UInt8(value)
            var rank = self.map.lookup(Span(single), 0, 1)
            self.singles.append(rank)
            if rank == UNRANKED:
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

    def single_byte(self, value: UInt8) -> Int:
        """Return the token id of a one byte sequence.

        Args:
            value: The byte.

        Returns:
            Its token id, which is always defined because the constructor
            refuses a vocabulary missing any of the 256.

        No hashing and no comparison, just an index. The merge loop asks
        this once per input byte, which makes it the hottest lookup in the
        encoder and the one most worth not being a hash lookup.
        """
        return self.singles[Int(value)]

    def size(self) -> Int:
        """Return how many ranked sequences the table holds.

        Returns:
            The number of entries.
        """
        return self.map.count()

    def rank_of(self, data: Span[UInt8, _], start: Int, end: Int) raises -> Int:
        """Look up the merge rank of one byte range.

        Args:
            data: The bytes to slice.
            start: Inclusive start offset.
            end: Exclusive end offset.

        Returns:
            The rank, or UNRANKED when the sequence is not a token.

        Raises:
            Error: never, in this implementation. The signature keeps
                `raises` so that callers written against the previous,
                allocating one do not all have to change.

        An unranked pair is not an error. It is the ordinary signal that a
        pair cannot be merged, and the merge loop stops when every remaining
        adjacent pair is unranked.

        Nothing is allocated here. That sentence is the point of this
        module.
        """
        return self.map.lookup(data, start, end)

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
