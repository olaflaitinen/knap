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
whitespace runs, or digit runs of at most three, so n stays small. Optimising
this loop before measuring would be optimising the wrong thing, and
docs/BENCHMARKS.md is where that argument has to be settled with numbers.
"""

from .ranks import RankTable, UNRANKED


def merge_piece(
    ranks: RankTable,
    data: Span[UInt8, _],
    start: Int,
    end: Int,
    mut out: List[Int],
) raises:
    """Merge one piece and append its token ids to a buffer.

    Args:
        ranks: The merge rank table.
        data: The bytes containing the piece.
        start: Inclusive start offset of the piece.
        end: Exclusive end offset of the piece.
        out: Buffer receiving the token ids, in order.

    Raises:
        Error: if a finished part is not in the vocabulary, which would mean
            the loop stopped early rather than that the input was unusual.

    An empty range appends nothing. A single byte is looked up directly,
    skipping the loop entirely, which is worth the special case because
    single byte pieces are common in punctuation heavy text.
    """
    var length = end - start
    if length <= 0:
        return
    if length == 1:
        out.append(ranks.token_of(data, start, end))
        return

    # Boundaries hold the split points of the piece, so part i spans
    # [boundaries[i], boundaries[i + 1]). Starting with every byte separate
    # means there are length + 1 boundaries.
    var boundaries = List[Int](capacity=length + 1)
    for offset in range(length + 1):
        boundaries.append(start + offset)

    while len(boundaries) > 2:
        # Find the adjacent pair with the lowest rank. Recomputing every
        # rank each round is what makes this quadratic; it is also what
        # makes it obviously correct, which is the trade this project wants
        # until a benchmark says otherwise.
        var best_rank = UNRANKED
        var best_index = -1

        for index in range(len(boundaries) - 2):
            var pair_start = boundaries[index]
            var pair_end = boundaries[index + 2]
            var rank = ranks.rank_of(data, pair_start, pair_end)
            if rank == UNRANKED:
                continue
            if best_index == -1 or rank < best_rank:
                best_rank = rank
                best_index = index

        if best_index == -1:
            # No adjacent pair is ranked, so the piece is fully merged.
            break

        # Joining the pair at best_index means dropping the boundary
        # between its two halves.
        _ = boundaries.pop(best_index + 1)

    for index in range(len(boundaries) - 1):
        out.append(
            ranks.token_of(data, boundaries[index], boundaries[index + 1])
        )


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
