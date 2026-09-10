# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/bpe.mojo
# Purpose     : The byte pair merge loop, applied to one pre-token piece.
# Stage       : Pipeline stage 4 of 4, see docs/ARCHITECTURE.md
# Depends on  : ranks.mojo
# Invariants  : Every round strictly reduces the part count by one, so the
#               loop always terminates. The parts always tile the piece.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""The byte pair encoding merge loop.

Each pre-token piece is merged independently of every other, which is what
makes stage 4 embarrassingly parallel in principle and why the pre-tokenizer
matters so much: it decides what the merge loop is even allowed to consider.

The rule. A piece starts as a sequence of single bytes. Each round finds the
adjacent pair with the lowest merge rank and joins it. The loop stops when no
adjacent pair is ranked. Ties cannot happen, because ranks are unique per
merge in both target vocabularies.

Termination is structural rather than argued: every round removes exactly one
boundary, so a piece of n bytes can survive at most n - 1 rounds.

The naive form is quadratic in the piece length, and that is left alone
deliberately. Pre-tokenization bounds pieces to single words, short
whitespace runs, or digit runs of at most three, so n stays small.

What is not left alone is how often the loop runs at all. Two shortcuts
answer before it starts: a single byte is a token by construction, and a
piece that is already a token merges to itself. Measurement said those two
cover most of the work, and docs/BENCHMARKS.md carries the numbers.
"""

from .ranks import RankTable, UNRANKED


struct MergeScratch(Movable):
    """Working space for the merge loop, owned by the caller and reused.

    The merge loop needs three parallel lists per piece, and a piece is a
    word. Allocating them per piece is three million allocations on four
    megabytes of prose, for structures that live a few microseconds each.
    Handing the same scratch back on every call makes that number three.

    A struct rather than three parameters because the number of lists is an
    implementation detail. It has grown from one to three while the encoder
    was being made faster, and each growth would otherwise have been a
    breaking change to a public signature.
    """

    var boundaries: List[Int]
    """Split points of the piece. Part i spans [boundaries[i], [i + 1])."""

    var pair_ranks: List[Int]
    """Rank of joining part i with part i + 1, or UNRANKED when unmergeable.

    Always two shorter than boundaries, so pair i is the byte range
    [boundaries[i], boundaries[i + 2]).
    """

    var part_ids: List[Int]
    """Token id of each part, which is the answer being built."""

    def __init__(out self):
        """Create empty scratch space.

        The lists grow to the longest piece the caller ever passes and then
        stop growing, which is why reusing one instance is worth the
        parameter.
        """
        self.boundaries = List[Int]()
        self.pair_ranks = List[Int]()
        self.part_ids = List[Int]()


def merge_piece_into[
    emit: Bool = True
](
    ranks: RankTable,
    data: Span[UInt8, _],
    start: Int,
    end: Int,
    mut out: List[Int],
    mut scratch: MergeScratch,
) raises -> Int:
    """Merge one piece, and say how many tokens it became.

    Parameters:
        emit: Whether to append the token ids to out. Compile time, so the
            counting path carries no branch and the emitting path carries no
            extra work. Counting a document is the most common thing anyone
            asks a tokenizer to do, and the list of ids is usually thrown
            away immediately after its length is read.

    Args:
        ranks: The merge rank table.
        data: The bytes containing the piece.
        start: Inclusive start offset of the piece.
        end: Exclusive end offset of the piece.
        out: Buffer receiving the token ids, in order. Untouched when emit
            is False.
        scratch: Working space the caller owns and reuses. Cleared on entry
            and meaningless on exit.

    Returns:
        How many tokens this piece became.

    Raises:
        Error: if a single byte piece is not in the vocabulary, which the
            rank table's constructor already refuses to allow.

    Nothing else here can fail. Every part is either one byte, whose id came
    from the single byte array, or a merge whose id is the rank that chose
    it, so a finished part cannot be absent from the vocabulary. That used
    to be checked by looking each finished part up again, which cost one
    hash lookup per output token to confirm something the loop had just
    established. The 110 MB corpus gate is what checks it now.

    The scratch list is the whole point of this entry point. The version
    that allocates its own does one heap allocation per pre-token, which on
    four megabytes of prose is about a million allocations for a structure
    that is a few dozen bytes and dies immediately. Handing the same list
    back on every call makes that number one.

    This is the same shape of waste as the String key the rank table used to
    allocate on every lookup, and that one cost a factor of nearly two. The
    lesson generalises: in a loop this tight, the allocations are the
    algorithm.

    An empty range appends nothing. A single byte is looked up directly,
    skipping the loop entirely, which is worth the special case because
    single byte pieces are common in punctuation heavy text.

    So is a piece that is already a token, and that case is not a rarity.
    Measured over four megabytes of prose, cl100k_base turns 882310 pieces
    into 1223017 tokens, which is 1.39 tokens per piece: most pre-tokens are
    one token and the loop below cannot change them. See the whole piece
    shortcut for why that is sound.
    """
    var length = end - start
    if length <= 0:
        return 0
    if length == 1:
        comptime if emit:
            out.append(ranks.single_byte(data[start]))
        return 1

    # The whole piece shortcut.
    #
    # If the piece is itself a token, the merge loop below is guaranteed to
    # arrive at exactly that token, so asking once is the same answer for a
    # fraction of the work. The guarantee comes from how the vocabulary was
    # built: a token exists because training merged that byte sequence in
    # rank order, and replaying the same lowest rank first rule over the
    # same bytes replays the same merges.
    #
    # This is an assumption about the vocabulary rather than a theorem about
    # the loop, so it is not taken on faith. The 110 MB corpus gate compares
    # 191762320 tokens against tiktoken with this path enabled, and
    # tests/test_bpe.mojo asserts the shortcut and the loop agree on a
    # vocabulary small enough to check by hand.
    var whole = ranks.rank_of(data, start, end)
    if whole != UNRANKED:
        comptime if emit:
            out.append(whole)
        return 1

    # Boundaries hold the split points of the piece, so part i spans
    # [boundaries[i], boundaries[i + 1]). Starting with every byte separate
    # means there are length + 1 boundaries.
    #
    # pair_ranks[i] is the rank of the pair made by joining part i and part
    # i + 1, or UNRANKED when that join is not a token. The invariant is
    # that len(pair_ranks) is always len(boundaries) - 2, so pair i is
    # always the range [boundaries[i], boundaries[i + 2]).
    #
    # Keeping these is the whole point. The loop used to ask the rank table
    # for every adjacent pair on every round, which is a quadratic number of
    # hash lookups in the piece length. A merge changes exactly two pairs:
    # the one it created and the one before it. Everything else is still
    # the answer it was, so it is kept rather than asked for again. That
    # turns the lookups into length plus two per merge, while the scan for
    # the smallest rank stays a walk over integers, which is the cheap half.
    scratch.boundaries.clear()
    for offset in range(length + 1):
        scratch.boundaries.append(start + offset)

    # Every part begins as one byte, and a byte's token id is an array
    # index rather than a hash lookup.
    scratch.part_ids.clear()
    for offset in range(length):
        scratch.part_ids.append(ranks.single_byte(data[start + offset]))

    scratch.pair_ranks.clear()
    for index in range(length - 1):
        scratch.pair_ranks.append(
            ranks.rank_of(
                data, scratch.boundaries[index], scratch.boundaries[index + 2]
            )
        )

    while len(scratch.pair_ranks) > 0:
        var best_rank = UNRANKED
        var best_index = -1

        for index in range(len(scratch.pair_ranks)):
            var rank = scratch.pair_ranks[index]
            if rank == UNRANKED:
                continue
            if best_index == -1 or rank < best_rank:
                best_rank = rank
                best_index = index

        if best_index == -1:
            # No adjacent pair is ranked, so the piece is fully merged.
            break

        # The rank of a pair is the token id of the part it becomes, so the
        # merge already knows the answer that used to be looked up again
        # after the loop finished.
        scratch.part_ids[best_index] = best_rank
        _ = scratch.part_ids.pop(best_index + 1)

        # Joining the pair at best_index means dropping the boundary between
        # its two halves. The pair that started at that boundary goes with
        # it, except when the merge was the last pair, in which case there is
        # no following pair and the list simply gets shorter.
        _ = scratch.boundaries.pop(best_index + 1)
        if best_index + 1 < len(scratch.pair_ranks):
            _ = scratch.pair_ranks.pop(best_index + 1)
        else:
            _ = scratch.pair_ranks.pop()

        # The merged pair and the pair immediately before it are the only
        # two whose bytes changed.
        if best_index < len(scratch.pair_ranks):
            scratch.pair_ranks[best_index] = ranks.rank_of(
                data,
                scratch.boundaries[best_index],
                scratch.boundaries[best_index + 2],
            )
        if best_index > 0:
            scratch.pair_ranks[best_index - 1] = ranks.rank_of(
                data,
                scratch.boundaries[best_index - 1],
                scratch.boundaries[best_index + 1],
            )

    comptime if emit:
        for index in range(len(scratch.part_ids)):
            out.append(scratch.part_ids[index])
    return len(scratch.part_ids)


def merge_piece(
    ranks: RankTable,
    data: Span[UInt8, _],
    start: Int,
    end: Int,
    mut out: List[Int],
) raises:
    """Merge one piece, allocating its own scratch space.

    Args:
        ranks: The merge rank table.
        data: The bytes containing the piece.
        start: Inclusive start offset of the piece.
        end: Exclusive end offset of the piece.
        out: Buffer receiving the token ids, in order.

    Raises:
        Error: if a finished part is not in the vocabulary.

    For callers encoding one piece, where an allocation that happens once
    costs nothing and a scratch parameter would be noise. Anything encoding
    in a loop should use merge_piece_into and hand back the same list.
    """
    var scratch = MergeScratch()
    _ = merge_piece_into(ranks, data, start, end, out, scratch)


def merge_piece_to_list(
    ranks: RankTable, data: Span[UInt8, _], start: Int, end: Int
) raises -> List[Int]:
    """Merge one piece and return its token ids.

    Args:
        ranks: The merge rank table.
        data: The bytes containing the piece.
        start: Inclusive start offset of the piece.
        end: Exclusive end offset of the piece.

    Returns:
        The token ids for that piece.

    Raises:
        Error: if a finished part is not in the vocabulary.

    A convenience wrapper for tests and for callers encoding a single piece.
    The encode path uses merge_piece directly so that one buffer serves the
    whole input.
    """
    var out = List[Int]()
    merge_piece(ranks, data, start, end, out)
    return out^


# =============================================================================
# End of file: src/knap/bpe.mojo
# =============================================================================
