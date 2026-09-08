# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/tokenizer.mojo
# Purpose     : Public API. Ties the four pipeline stages together and offers
#               encode and decode.
# Stage       : Public surface, see docs/ARCHITECTURE.md
# Depends on  : vocab.mojo, ranks.mojo, bpe.mojo, pretokenize/scanner.mojo
# Invariants  : Encoding never silently drops input. Every byte of a segment
#               ends up inside exactly one emitted token.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""The Knap tokenizer.

This is the public surface. It owns a vocabulary, a merge rank table, and the
knowledge of which pre-tokenization pattern the encoding uses, and it runs the
four stages in order:

  1. Split out special tokens, emitting their ids directly.
  2. Pre-tokenize each segment into pieces.
  3. Take each piece as raw bytes.
  4. Merge each piece independently and emit token ids.

Two encode entry points, matching the reference implementation's split.
encode_ordinary does no special token handling at all, so a marker written
out in the input encodes as ordinary text. encode takes an allowed set, emits
those markers as their own ids, and refuses input containing any special
token that was not allowed.

That refusal is deliberate and is the security relevant part of this file.
Encoding an unexpected marker as though it were text would let untrusted
input inject control tokens into a prompt, so the default is to raise.
"""

from .bpe import merge_piece
from .cache import PieceCache
from .errors import special_token_disallowed
from .pretokenize.scanner import scan_cl100k, scan_o200k
from .ranks import RankTable
from .vocab import Vocabulary, load_cl100k_base, load_o200k_base

comptime PATTERN_CL100K: Int = 0
"""Selects the cl100k_base pre-tokenization pattern."""

comptime PATTERN_O200K: Int = 1
"""Selects the o200k_base pre-tokenization pattern."""


struct Tokenizer(Movable):
    """A loaded encoding, ready to encode and decode."""

    var vocabulary: Vocabulary
    """Merge tokens and special tokens."""

    var ranks: RankTable
    """Merge rank lookup, built from the merge tokens."""

    var pattern: Int
    """Which pre-tokenization pattern this encoding uses."""

    def __init__(out self, var vocabulary: Vocabulary, pattern: Int) raises:
        """Build a tokenizer from a loaded vocabulary.

        Args:
            vocabulary: The encoding's merge and special tokens.
            pattern: PATTERN_CL100K or PATTERN_O200K.

        Raises:
            Error: if the pattern selector is unknown, or if the vocabulary
                cannot produce a valid rank table.

        Building the rank table costs one allocation per merge token, so
        roughly a hundred thousand for cl100k_base. It is paid once here
        rather than on every encode.
        """
        if pattern != PATTERN_CL100K and pattern != PATTERN_O200K:
            raise Error(
                String(
                    t"knap: unknown pattern selector {pattern}. Use"
                    t" PATTERN_CL100K or PATTERN_O200K."
                )
            )
        self.ranks = RankTable(vocabulary.merges)
        self.vocabulary = vocabulary^
        self.pattern = pattern

    # -------------------------------------------------------------------------
    # Encoding
    # -------------------------------------------------------------------------

    def _scan(self, data: Span[UInt8, _], mut ends: List[Int]) raises:
        """Pre-tokenize one segment with this encoding's pattern.

        Args:
            data: The segment bytes.
            ends: Receives the end offset of each piece.

        Raises:
            Error: if the scanner fails to advance, which is a defect rather
                than a property of the input.
        """
        if self.pattern == PATTERN_CL100K:
            scan_cl100k(data, ends)
        else:
            scan_o200k(data, ends)

    def _encode_segment[
        use_cache: Bool
    ](
        self,
        data: Span[UInt8, _],
        mut out: List[Int],
        mut cache: PieceCache,
    ) raises:
        """Encode a segment that contains no special tokens.

        Parameters:
            use_cache: Whether to consult the piece cache. Compile time, so
                the uncached path carries no branch at all rather than a
                predictable one.

        Args:
            data: The segment bytes.
            out: Buffer receiving the token ids, in order.
            cache: The piece cache. Ignored entirely when use_cache is
                False, which is why the uncached callers can pass a cache
                built with zero capacity.

        Raises:
            Error: if the scanner or the merge loop fails.

        The segment is pre-tokenized once and each piece is merged
        independently. Piece boundaries matter here beyond tidiness: the
        merge loop can only join bytes inside one piece, so the pieces
        determine which merges are even reachable.

        One implementation serves both the cached and the uncached paths on
        purpose. Two copies of this loop would be two places for the piece
        boundary arithmetic to drift, and the cached path would stop being
        testable against the uncached one.
        """
        var ends = List[Int]()
        self._scan(data, ends)

        var start = 0
        for index in range(len(ends)):
            var end = ends[index]

            comptime if use_cache:
                var entry = cache.lookup(data, start, end)
                if entry >= 0:
                    cache.record_hit()
                    cache.append_value(entry, out)
                    start = end
                    continue

                cache.record_miss()
                # Merged into its own buffer rather than straight into out,
                # because the cache has to store this piece's ids on their
                # own and out already holds everything before it.
                var produced = List[Int]()
                merge_piece(self.ranks, data, start, end, produced)
                cache.insert(data, start, end, Span(produced))
                for slot in range(len(produced)):
                    out.append(produced[slot])
            else:
                merge_piece(self.ranks, data, start, end, out)

            start = end

    def encode_segment(self, data: Span[UInt8, _], mut out: List[Int]) raises:
        """Encode a segment that contains no special tokens, without a cache.

        Args:
            data: The segment bytes.
            out: Buffer receiving the token ids, in order.

        Raises:
            Error: if the scanner or the merge loop fails.

        This is the reference path. Every cached result is asserted equal to
        what this produces, in tests/test_cache.mojo.
        """
        var scratch = PieceCache(0)
        self._encode_segment[False](data, out, scratch)

    def encode_segment_cached(
        self,
        data: Span[UInt8, _],
        mut out: List[Int],
        mut cache: PieceCache,
    ) raises:
        """Encode a segment that contains no special tokens, with a cache.

        Args:
            data: The segment bytes.
            out: Buffer receiving the token ids, in order.
            cache: The caller's piece cache, updated in place.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        self._encode_segment[True](data, out, cache)

    def encode_ordinary_bytes(self, data: Span[UInt8, _]) raises -> List[Int]:
        """Encode bytes, treating any special token literal as ordinary text.

        Args:
            data: The bytes to encode.

        Returns:
            The token ids.

        Raises:
            Error: if the scanner or the merge loop fails.

        This is the entry point that never raises on content. A marker
        written out in the input is encoded as the characters that spell it,
        which is exactly what the reference implementation's ordinary encode
        does.
        """
        var out = List[Int]()
        self.encode_segment(data, out)
        return out^

    def encode_ordinary(self, text: String) raises -> List[Int]:
        """Encode text, treating any special token literal as ordinary text.

        Args:
            text: The text to encode.

        Returns:
            The token ids.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        return self.encode_ordinary_bytes(text.as_bytes())

    def encode_ordinary_bytes_cached(
        self, data: Span[UInt8, _], mut cache: PieceCache
    ) raises -> List[Int]:
        """Encode bytes with a piece cache, ignoring special token literals.

        Args:
            data: The bytes to encode.
            cache: The caller's piece cache, updated in place.

        Returns:
            The token ids, identical to what encode_ordinary_bytes returns
            for the same input.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        var out = List[Int]()
        self.encode_segment_cached(data, out, cache)
        return out^

    def encode_ordinary_cached(
        self, text: String, mut cache: PieceCache
    ) raises -> List[Int]:
        """Encode text with a piece cache, ignoring special token literals.

        Args:
            text: The text to encode.
            cache: The caller's piece cache, updated in place.

        Returns:
            The token ids, identical to what encode_ordinary returns for the
            same input.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        return self.encode_ordinary_bytes_cached(text.as_bytes(), cache)

    def _find_special(
        self, data: Span[UInt8, _], from_offset: Int, allowed: List[Int]
    ) raises -> Tuple[Int, Int]:
        """Find the earliest allowed special token at or after an offset.

        Args:
            data: The bytes being encoded.
            from_offset: Where to start looking.
            allowed: Registry indices of the permitted special tokens.

        Returns:
            The byte offset of the earliest match and the registry index
            that matched, or (-1, -1) when none occurs.

        Earliest match wins, and among equal positions the first listed
        wins. Scanning for each marker separately and taking the minimum is
        simple and is not on any hot path: the number of special tokens is
        at most five.
        """
        var best_offset = -1
        var best_index = -1

        for slot in range(len(allowed)):
            var registry_index = allowed[slot]
            var name = self.vocabulary.specials.name_at(registry_index)
            var needle = name.as_bytes()
            var limit = len(data) - len(needle)

            for position in range(from_offset, limit + 1):
                if best_offset != -1 and position >= best_offset:
                    break
                var matched = True
                for offset in range(len(needle)):
                    if data[position + offset] != needle[offset]:
                        matched = False
                        break
                if matched:
                    best_offset = position
                    best_index = registry_index
                    break

        return (best_offset, best_index)

    def _encode_bytes[
        use_cache: Bool
    ](
        self,
        data: Span[UInt8, _],
        allowed_special: List[String],
        mut cache: PieceCache,
    ) raises -> List[Int]:
        """Encode bytes, handling special tokens.

        Parameters:
            use_cache: Whether the segments between markers consult the
                piece cache.

        Args:
            data: The bytes to encode.
            allowed_special: Literal texts of the special tokens permitted in
                the input. Every other special token this encoding defines is
                disallowed, and its presence is an error.
            cache: The piece cache, ignored when use_cache is False.

        Returns:
            The token ids.

        Raises:
            Error: if a disallowed special token appears in the input, or if
                an allowed name is not a special token of this encoding.

        The disallowed check runs first and over the whole input, before any
        encoding happens, so a marker late in a long document is refused
        rather than half encoded.
        """
        # Resolve the allowed names to registry indices, and treat every
        # other special token as disallowed.
        var allowed_indices = List[Int]()
        for slot in range(len(allowed_special)):
            var name = allowed_special[slot]
            var found = self.vocabulary.specials.index_of_id(
                self.vocabulary.specials.id_of(name)
            )
            allowed_indices.append(found)

        var disallowed_indices = List[Int]()
        for index in range(self.vocabulary.specials.count()):
            var permitted = False
            for slot in range(len(allowed_indices)):
                if allowed_indices[slot] == index:
                    permitted = True
            if not permitted:
                disallowed_indices.append(index)

        var offending = self._find_special(data, 0, disallowed_indices)
        if offending[0] != -1:
            raise special_token_disallowed(
                self.vocabulary.specials.name_at(offending[1])
            )

        var out = List[Int]()
        var position = 0
        while position < len(data):
            var hit = self._find_special(data, position, allowed_indices)
            if hit[0] == -1:
                self._encode_segment[use_cache](
                    data[position : len(data)], out, cache
                )
                break

            if hit[0] > position:
                self._encode_segment[use_cache](
                    data[position : hit[0]], out, cache
                )
            out.append(self.vocabulary.specials.id_at(hit[1]))
            var name = self.vocabulary.specials.name_at(hit[1])
            position = hit[0] + name.byte_length()

        return out^

    def encode_bytes(
        self, data: Span[UInt8, _], allowed_special: List[String]
    ) raises -> List[Int]:
        """Encode bytes, handling special tokens, without a cache.

        Args:
            data: The bytes to encode.
            allowed_special: Literal texts of the special tokens permitted in
                the input.

        Returns:
            The token ids.

        Raises:
            Error: if a disallowed special token appears in the input, or if
                an allowed name is not a special token of this encoding.
        """
        var scratch = PieceCache(0)
        return self._encode_bytes[False](data, allowed_special, scratch)

    def encode_bytes_cached(
        self,
        data: Span[UInt8, _],
        allowed_special: List[String],
        mut cache: PieceCache,
    ) raises -> List[Int]:
        """Encode bytes, handling special tokens, with a piece cache.

        Args:
            data: The bytes to encode.
            allowed_special: Literal texts of the special tokens permitted in
                the input.
            cache: The caller's piece cache, updated in place.

        Returns:
            The token ids, identical to what encode_bytes returns for the
            same input.

        Raises:
            Error: if a disallowed special token appears in the input, or if
                an allowed name is not a special token of this encoding.

        The refusal path is shared with the uncached form rather than
        repeated here. A second copy of a security relevant check is a
        second place for it to be weakened by accident.
        """
        return self._encode_bytes[True](data, allowed_special, cache)

    def encode_cached(
        self,
        text: String,
        allowed_special: List[String],
        mut cache: PieceCache,
    ) raises -> List[Int]:
        """Encode text, handling special tokens, with a piece cache.

        Args:
            text: The text to encode.
            allowed_special: Literal texts of the permitted special tokens.
            cache: The caller's piece cache, updated in place.

        Returns:
            The token ids.

        Raises:
            Error: if a disallowed special token appears in the input.
        """
        return self.encode_bytes_cached(text.as_bytes(), allowed_special, cache)

    def encode(
        self, text: String, allowed_special: List[String]
    ) raises -> List[Int]:
        """Encode text, handling special tokens.

        Args:
            text: The text to encode.
            allowed_special: Literal texts of the permitted special tokens.

        Returns:
            The token ids.

        Raises:
            Error: if a disallowed special token appears in the input.
        """
        return self.encode_bytes(text.as_bytes(), allowed_special)

    # -------------------------------------------------------------------------
    # Decoding
    # -------------------------------------------------------------------------

    def decode_bytes(self, token_ids: List[Int]) raises -> List[UInt8]:
        """Decode token ids to the exact bytes they represent.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            The concatenated token bytes.

        Raises:
            Error: if any id is unassigned in this encoding.
        """
        return self.vocabulary.decode_bytes(token_ids)

    def decode(self, token_ids: List[Int]) raises -> String:
        """Decode token ids to text.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            A String holding the decoded bytes, unvalidated.

        Raises:
            Error: if any id is unassigned in this encoding.
        """
        return self.vocabulary.decode(token_ids)


def load_cl100k_base_tokenizer(path: String) raises -> Tokenizer:
    """Load a cl100k_base tokenizer from its vocabulary file.

    Args:
        path: Path to cl100k_base.tiktoken.

    Returns:
        A ready tokenizer.

    Raises:
        Error: if the vocabulary is missing or malformed.
    """
    var vocabulary = load_cl100k_base(path)
    return Tokenizer(vocabulary^, PATTERN_CL100K)


def load_o200k_base_tokenizer(path: String) raises -> Tokenizer:
    """Load an o200k_base tokenizer from its vocabulary file.

    Args:
        path: Path to o200k_base.tiktoken.

    Returns:
        A ready tokenizer.

    Raises:
        Error: if the vocabulary is missing or malformed.
    """
    var vocabulary = load_o200k_base(path)
    return Tokenizer(vocabulary^, PATTERN_O200K)


# =============================================================================
# End of file: src/knap/tokenizer.mojo
# =============================================================================
