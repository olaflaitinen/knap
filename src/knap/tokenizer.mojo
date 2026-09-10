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

from .bpe import MergeScratch, merge_piece_into
from .cache import PieceCache
from .errors import special_token_disallowed
from .pretokenize.scanner import scan_cl100k, scan_gpt2, scan_o200k
from .ranks import RankTable, UNRANKED
from .vocab import (
    Vocabulary,
    load_cl100k_base,
    load_gpt2,
    load_o200k_base,
    load_o200k_harmony,
    load_p50k_base,
    load_p50k_edit,
    load_r50k_base,
)

comptime BYTES_PER_TOKEN: Int = 3
"""A low estimate of how many input bytes one token consumes.

Used only to size the output buffer before encoding. Measured at 3.43 bytes
per token for cl100k_base and 3.84 for o200k_base on prose, so three over
allocates by between fourteen and twenty eight percent and never under
allocates on realistic text.

Deliberately an underestimate. Guessing high leaves the buffer growing, which
means a reallocation and a copy of everything written so far, repeated about
twenty times over a document of a million tokens. Guessing low wastes memory
that is freed immediately. The two mistakes are not the same size.
"""


def estimated_tokens(byte_count: Int) -> Int:
    """Estimate how many tokens a byte count will produce.

    Args:
        byte_count: How many input bytes there are.

    Returns:
        A capacity to reserve, never less than a small floor.

    The floor matters for short input, where a capacity of zero would put
    the first few appends straight back into the growth path this exists to
    avoid.
    """
    return byte_count // BYTES_PER_TOKEN + 16


comptime PATTERN_CL100K: Int = 0
"""Selects the cl100k_base pre-tokenization pattern."""

comptime PATTERN_O200K: Int = 1
"""Selects the o200k_base pre-tokenization pattern.

Shared by o200k_base and o200k_harmony, whose patterns are identical.
"""

comptime PATTERN_GPT2: Int = 2
"""Selects the gpt2 pre-tokenization pattern.

Shared by gpt2, r50k_base, p50k_base and p50k_edit. Four encodings, one
pattern: they differ in their vocabularies and their special tokens, not in
how text is split.
"""


@fieldwise_init
struct PaddedBatch(Movable):
    """A rectangle of token ids, with a mask saying which of them are real.

    Row major: row `r`, column `c` is at `r * width + c`. Flat rather than a
    list of lists because the next thing that happens to this is a copy into
    a tensor, and a list of lists would have to be flattened first.
    """

    var ids: List[Int]
    """Rows times width token ids, row major."""

    var mask: List[UInt8]
    """One per id. One where the id came from the input, zero where it is
    padding.

    **This is the only thing that distinguishes padding from content.** A
    caller is free to pad with an id that is also a real token, and many do,
    because no encoding this library ships defines a padding token and
    reusing the end of text marker is the common workaround. Where that
    happens the ids alone cannot tell the two apart and the mask can.
    """

    var lengths: List[Int]
    """How many real tokens each row holds, before padding."""

    var rows: Int
    """How many documents are in the batch."""

    var width: Int
    """How many columns each row has, which is the longest row."""

    def id_at(self, row: Int, column: Int) raises -> Int:
        """Read one token id.

        Args:
            row: Which document.
            column: Which position in it.

        Returns:
            The token id, which is the padding id past that row's length.

        Raises:
            Error: if either index is outside the rectangle. Out of range is
                raised rather than clamped, because a clamped read returns a
                real looking id from the wrong place.
        """
        if row < 0 or row >= self.rows or column < 0 or column >= self.width:
            raise Error(
                String(
                    t"knap: ({row}, {column}) is outside a batch of"
                    t" {self.rows} by {self.width}"
                )
            )
        return self.ids[row * self.width + column]

    def mask_at(self, row: Int, column: Int) raises -> Int:
        """Read one mask value.

        Args:
            row: Which document.
            column: Which position in it.

        Returns:
            One where the id is real, zero where it is padding.

        Raises:
            Error: if either index is outside the rectangle.
        """
        if row < 0 or row >= self.rows or column < 0 or column >= self.width:
            raise Error(
                String(
                    t"knap: ({row}, {column}) is outside a batch of"
                    t" {self.rows} by {self.width}"
                )
            )
        return Int(self.mask[row * self.width + column])


@fieldwise_init
struct TokenWindow(Copyable, ImplicitlyCopyable, Movable, Writable):
    """One window of a document, as a byte range and a token count."""

    var start: Int
    """First byte of the window, inclusive."""

    var end: Int
    """One past the last byte of the window."""

    var tokens: Int
    """How many tokens this window encodes to."""

    def write_to(self, mut writer: Some[Writer]):
        """Write a short description of the window.

        Args:
            writer: Receives the description.
        """
        writer.write("[", self.start, ", ", self.end, ") ")
        writer.write(self.tokens, " tokens")


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
        if (
            pattern != PATTERN_CL100K
            and pattern != PATTERN_O200K
            and pattern != PATTERN_GPT2
        ):
            raise Error(
                String(
                    t"knap: unknown pattern selector {pattern}. Use"
                    t" PATTERN_CL100K, PATTERN_O200K, or PATTERN_GPT2."
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
        elif self.pattern == PATTERN_GPT2:
            scan_gpt2(data, ends)
        else:
            scan_o200k(data, ends)

    def _encode_segment[
        use_cache: Bool, emit: Bool = True
    ](
        self,
        data: Span[UInt8, _],
        mut out: List[Int],
        mut cache: PieceCache,
    ) raises -> Int:
        """Encode a segment that contains no special tokens.

        Parameters:
            use_cache: Whether to consult the piece cache. Compile time, so
                the uncached path carries no branch at all rather than a
                predictable one.
            emit: Whether to append the ids to out. False counts them
                without building the list, which is what every caller who
                only wants a number is asking for.

        Args:
            data: The segment bytes.
            out: Buffer receiving the token ids, in order. Untouched when
                emit is False.
            cache: The piece cache. Ignored entirely when use_cache is
                False, which is why the uncached callers can pass a cache
                built with zero capacity.

        Returns:
            How many tokens the segment became.

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
        var ends = List[Int](capacity=estimated_tokens(len(data)))
        self._scan(data, ends)

        # One scratch buffer for every piece in the segment. Allocating the
        # merge loop's working lists per piece is millions of allocations on
        # four megabytes of prose, for structures that die immediately.
        var scratch = MergeScratch()

        var total = 0
        var start = 0
        for index in range(len(ends)):
            var end = ends[index]

            comptime if use_cache:
                var entry = cache.lookup(data, start, end)
                if entry >= 0:
                    cache.record_hit()
                    comptime if emit:
                        cache.append_value(entry, out)
                    total += cache.value_count(entry)
                    start = end
                    continue

                cache.record_miss()
                # Merged into its own buffer rather than straight into out,
                # because the cache has to store this piece's ids on their
                # own and out already holds everything before it.
                #
                # This one merges with emit on even when the caller is only
                # counting: a miss has to produce the ids so that the cache
                # can store them, and a cache that stored nothing on a miss
                # would never answer a hit.
                var produced = List[Int]()
                total += merge_piece_into(
                    self.ranks, data, start, end, produced, scratch
                )
                cache.insert(data, start, end, Span(produced))
                comptime if emit:
                    for slot in range(len(produced)):
                        out.append(produced[slot])
            else:
                total += merge_piece_into[emit](
                    self.ranks, data, start, end, out, scratch
                )

            start = end
        return total

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
        _ = self._encode_segment[False](data, out, scratch)

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
        _ = self._encode_segment[True](data, out, cache)

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
        # Sized once rather than grown into. A list that doubles holds
        # both the old and the new buffer while it copies, so its peak is
        # about half again its final size, and on eighty megabytes of input
        # that measured as 125 MB of avoidable resident memory. The
        # estimate is deliberately generous, because being a little too
        # large costs one allocation and being too small costs the growth
        # sequence this exists to avoid.
        var out = List[Int](capacity=estimated_tokens(len(data)))
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

    def encode_ordinary_bytes_into(
        self, data: Span[UInt8, _], mut out: List[Int]
    ) raises:
        """Encode bytes into a buffer the caller owns.

        Args:
            data: The bytes to encode.
            out: Buffer receiving the token ids. **Appended to, not
                cleared.** Clear it first if you want only this input's
                tokens.

        Raises:
            Error: if the scanner or the merge loop fails.

        The allocation free entry point. Every other encode method returns a
        fresh list, which means a heap allocation and a growth sequence on
        every call. A caller encoding many documents in a loop can hand the
        same buffer back each time and pay for that once.

        Appending rather than clearing, because clearing is one line the
        caller can write and un-appending is not, and because encoding
        several inputs into one buffer is a real thing to want. The cost is
        that forgetting to clear doubles the output, which is why it is the
        first thing this docstring says.
        """
        self.encode_segment(data, out)

    def encode_ordinary_into(self, text: String, mut out: List[Int]) raises:
        """Encode text into a buffer the caller owns.

        Args:
            text: The text to encode.
            out: Buffer receiving the token ids, appended to rather than
                cleared.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        self.encode_ordinary_bytes_into(text.as_bytes(), out)

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
        var out = List[Int](capacity=estimated_tokens(len(data)))
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

    def _encode_bytes_into[
        use_cache: Bool, emit: Bool = True
    ](
        self,
        data: Span[UInt8, _],
        allowed_special: List[String],
        mut out: List[Int],
        mut cache: PieceCache,
    ) raises -> Int:
        """Encode bytes into a buffer, handling special tokens.

        Parameters:
            use_cache: Whether the segments between markers consult the
                piece cache.
            emit: Whether to append the ids to out. False counts them
                without building the list.

        Args:
            data: The bytes to encode.
            allowed_special: Literal texts of the special tokens permitted in
                the input. Every other special token this encoding defines is
                disallowed, and its presence is an error.
            out: Buffer receiving the token ids. Untouched when emit is
                False.
            cache: The piece cache, ignored when use_cache is False.

        Returns:
            How many tokens the input became.

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

        var total = 0
        var position = 0
        while position < len(data):
            var hit = self._find_special(data, position, allowed_indices)
            if hit[0] == -1:
                total += self._encode_segment[use_cache, emit](
                    data[position : len(data)], out, cache
                )
                break

            if hit[0] > position:
                total += self._encode_segment[use_cache, emit](
                    data[position : hit[0]], out, cache
                )
            comptime if emit:
                out.append(self.vocabulary.specials.id_at(hit[1]))
            total += 1
            var name = self.vocabulary.specials.name_at(hit[1])
            position = hit[0] + name.byte_length()

        return total

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
                the input.
            cache: The piece cache, ignored when use_cache is False.

        Returns:
            The token ids.

        Raises:
            Error: if a disallowed special token appears in the input, or if
                an allowed name is not a special token of this encoding.
        """
        var out = List[Int](capacity=estimated_tokens(len(data)))
        _ = self._encode_bytes_into[use_cache](
            data, allowed_special, out, cache
        )
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
    # Windows, budgets and batches
    #
    # Every one of these is something a caller would otherwise write against
    # the encoder, and would write slightly wrong. Splitting a document into
    # windows of at most N tokens is the usual one: the obvious
    # implementation encodes the whole document, cuts the id list every N
    # ids, and decodes each piece back to text. That produces windows whose
    # boundaries fall inside a token, so decoding them gives back mangled
    # text and re-encoding them gives different ids.
    #
    # These cut on pre-token boundaries instead, which is the coarsest
    # boundary the merge loop cannot cross. That makes a window's encoding
    # exactly the corresponding slice of the whole document's encoding, and
    # tests/test_windows.mojo asserts it rather than assuming it.
    # -------------------------------------------------------------------------

    def piece_token_counts(
        self,
        data: Span[UInt8, _],
        mut ends: List[Int],
        mut counts: List[Int],
    ) raises -> Int:
        """Count the tokens each pre-token becomes.

        Args:
            data: The bytes to walk.
            ends: Receives the exclusive end offset of each pre-token,
                cleared on entry.
            counts: Receives the token count of each pre-token, cleared on
                entry. Always the same length as ends.

        Returns:
            The total number of tokens, which equals count_ordinary_bytes.

        Raises:
            Error: if the scanner or the merge loop fails.

        The primitive the windowing and budget entry points are built on,
        exposed because a caller doing something this file does not
        anticipate should not have to reimplement it. Nothing is emitted, so
        the list of ids is never built.
        """
        ends.clear()
        counts.clear()
        self._scan(data, ends)

        var scratch = MergeScratch()
        var discarded = List[Int]()
        var total = 0
        var start = 0
        for index in range(len(ends)):
            var end = ends[index]
            var produced = merge_piece_into[False](
                self.ranks, data, start, end, discarded, scratch
            )
            counts.append(produced)
            total += produced
            start = end
        return total

    def windows_ordinary_bytes(
        self,
        data: Span[UInt8, _],
        max_tokens: Int,
        overlap_tokens: Int = 0,
    ) raises -> List[TokenWindow]:
        """Split bytes into windows of at most max_tokens tokens each.

        Args:
            data: The bytes to split.
            max_tokens: The largest window, in tokens.
            overlap_tokens: How many tokens of the previous window to repeat
                at the start of the next. Zero for no overlap.

        Returns:
            The windows, in order, covering the input with no gaps. Empty
            input gives no windows.

        Raises:
            Error: if max_tokens is not positive, if overlap_tokens is
                negative or not smaller than max_tokens, or if the scanner
                or the merge loop fails.

        Windows are cut on pre-token boundaries, so the encoding of a window
        is exactly the slice of the whole document's encoding that covers
        it. Cutting anywhere else would not be.

        One consequence is stated rather than hidden: a single pre-token
        that is longer than max_tokens on its own becomes a window that
        exceeds the budget. The alternative would be to cut inside it, which
        would change the tokens. A pre-token is a word or a run of
        whitespace, so this arises for pathological input rather than for
        prose.
        """
        if max_tokens <= 0:
            raise Error(
                String(
                    t"knap: a window of {max_tokens} tokens is not a window."
                    t" max_tokens must be positive."
                )
            )
        if overlap_tokens < 0 or overlap_tokens >= max_tokens:
            raise Error(
                String(
                    t"knap: an overlap of {overlap_tokens} tokens does not"
                    t" fit inside a window of {max_tokens}. The overlap must"
                    t" be zero or more and smaller than the window."
                )
            )

        var windows = List[TokenWindow]()
        var ends = List[Int]()
        var counts = List[Int]()
        _ = self.piece_token_counts(data, ends, counts)
        if len(ends) == 0:
            return windows^

        var first = 0
        while first < len(ends):
            var start_byte = 0
            if first > 0:
                start_byte = ends[first - 1]

            var tokens = 0
            var last = first
            while last < len(ends):
                if last > first and tokens + counts[last] > max_tokens:
                    break
                tokens += counts[last]
                last += 1

            windows.append(TokenWindow(start_byte, ends[last - 1], tokens))
            if last >= len(ends):
                break

            # Step back over whole pre-tokens until the overlap budget is
            # spent. Never back past first + 1, so every window begins later
            # than the one before it and the loop terminates.
            var back = last
            var repeated = 0
            while back > first + 1:
                if repeated + counts[back - 1] > overlap_tokens:
                    break
                back -= 1
                repeated += counts[back]
            first = back

        return windows^

    def windows_ordinary(
        self, text: String, max_tokens: Int, overlap_tokens: Int = 0
    ) raises -> List[TokenWindow]:
        """Split text into windows of at most max_tokens tokens each.

        Args:
            text: The text to split.
            max_tokens: The largest window, in tokens.
            overlap_tokens: How many tokens of the previous window to repeat.

        Returns:
            The windows, in order, as byte ranges into the text.

        Raises:
            Error: if the arguments are out of range, or if the scanner or
                the merge loop fails.
        """
        return self.windows_ordinary_bytes(
            text.as_bytes(), max_tokens, overlap_tokens
        )

    def truncate_ordinary_bytes(
        self, data: Span[UInt8, _], max_tokens: Int
    ) raises -> Int:
        """Find where to cut so that at most max_tokens tokens remain.

        Args:
            data: The bytes to measure.
            max_tokens: The token budget.

        Returns:
            A byte offset. Encoding data up to that offset gives at most
            max_tokens tokens, and it is the largest such offset that falls
            on a pre-token boundary.

        Raises:
            Error: if max_tokens is negative, or if the scanner or the merge
                loop fails.

        Zero is a legitimate answer: it means the first pre-token alone
        exceeds the budget.
        """
        if max_tokens < 0:
            raise Error(
                String(t"knap: a budget of {max_tokens} tokens is negative.")
            )

        var ends = List[Int]()
        var counts = List[Int]()
        _ = self.piece_token_counts(data, ends, counts)

        var tokens = 0
        var cut = 0
        for index in range(len(ends)):
            if tokens + counts[index] > max_tokens:
                break
            tokens += counts[index]
            cut = ends[index]
        return cut

    def truncate_ordinary(self, text: String, max_tokens: Int) raises -> Int:
        """Find where to cut text so that at most max_tokens tokens remain.

        Args:
            text: The text to measure.
            max_tokens: The token budget.

        Returns:
            A byte offset into the text.

        Raises:
            Error: if max_tokens is negative, or if encoding fails.
        """
        return self.truncate_ordinary_bytes(text.as_bytes(), max_tokens)

    def fits_ordinary_bytes(
        self, data: Span[UInt8, _], max_tokens: Int
    ) raises -> Bool:
        """Report whether bytes encode to at most max_tokens tokens.

        Args:
            data: The bytes to check.
            max_tokens: The token budget.

        Returns:
            True when the input is within the budget.

        Raises:
            Error: if the scanner or the merge loop fails.

        Stops as soon as the budget is exceeded rather than counting the
        whole input, which is the difference between checking a hundred
        megabyte document against a context window and tokenizing it.
        """
        var ends = List[Int]()
        self._scan(data, ends)

        var scratch = MergeScratch()
        var discarded = List[Int]()
        var total = 0
        var start = 0
        for index in range(len(ends)):
            var end = ends[index]
            total += merge_piece_into[False](
                self.ranks, data, start, end, discarded, scratch
            )
            if total > max_tokens:
                return False
            start = end
        return True

    def fits_ordinary(self, text: String, max_tokens: Int) raises -> Bool:
        """Report whether text encodes to at most max_tokens tokens.

        Args:
            text: The text to check.
            max_tokens: The token budget.

        Returns:
            True when the input is within the budget.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        return self.fits_ordinary_bytes(text.as_bytes(), max_tokens)

    def encode_ordinary_batch_into(
        self,
        documents: List[String],
        mut out: List[Int],
        mut ends: List[Int],
    ) raises:
        """Encode several documents into one buffer the caller owns.

        Args:
            documents: The documents, in order.
            out: Buffer receiving every document's ids, appended in order.
            ends: Receives one entry per document, the offset in out where
                that document's ids end. Appended to, not cleared.

        Raises:
            Error: if the scanner or the merge loop fails.

        One buffer for the whole batch, and one entry per document saying
        where it stopped, so a caller encoding ten thousand short documents
        pays for one growth sequence rather than ten thousand allocations.

        Nothing here is parallel. Mojo 1.0.0 has no working task
        parallelism, which is a fact about the toolchain rather than a
        design decision, and it is recorded as one in docs/ARCHITECTURE.md.
        """
        for index in range(len(documents)):
            self.encode_ordinary_bytes_into(documents[index].as_bytes(), out)
            ends.append(len(out))

    def encode_ordinary_batch(
        self, documents: List[String]
    ) raises -> List[List[Int]]:
        """Encode several documents, one list of ids each.

        Args:
            documents: The documents, in order.

        Returns:
            One list of token ids per document, in the same order.

        Raises:
            Error: if the scanner or the merge loop fails.

        The convenient form. Anything encoding a large batch should use
        encode_ordinary_batch_into, which allocates once instead of once per
        document.
        """
        var results = List[List[Int]]()
        for index in range(len(documents)):
            results.append(
                self.encode_ordinary_bytes(documents[index].as_bytes())
            )
        return results^

    def pad_ordinary_batch(
        self,
        documents: List[String],
        pad_id: Int,
        max_tokens: Int = 0,
    ) raises -> PaddedBatch:
        """Encode documents into one rectangle, padded and masked.

        Args:
            documents: The documents, in order. One row each.
            pad_id: The id to fill the unused columns with. There is no
                default and there cannot be one: not one of the seven
                encodings this library ships defines a padding token, so any
                value here is the caller's decision about their own model.
            max_tokens: Truncate each row to at most this many tokens. Zero,
                the default, truncates nothing and makes the rectangle as
                wide as the longest document.

        Returns:
            The rectangle, the mask, and each row's real length.

        Raises:
            Error: if pad_id is outside this encoding's id space, if
                max_tokens is negative, or if encoding fails.

        Two decisions in here are worth stating.

        **The padding id is required.** Every other tokenizer that offers
        this has a padding token to default to, because it was built for
        model families that define one. These encodings do not, and picking
        one silently would put an id into a caller's tensor that their model
        was never trained to see there.

        **Truncation is by token and not by pre-token.** A row cut at
        max_tokens keeps exactly that many ids, which may end inside a word.
        That is what a fixed width model input requires and it is the
        opposite of what `windows_ordinary` does, where the point is that a
        window re-encodes to itself. Use windows to split a document for
        retrieval; use this to fill a tensor.

        One cost is worth knowing rather than discovering. A row longer than
        max_tokens is encoded in full and then cut, so padding a batch of
        long documents to a narrow width pays for the part it discards.
        Avoiding that would mean an encoder that stops at a token count,
        which is a third parameterisation of the merge loop, and nothing has
        yet measured that it pays. Callers who know their documents are much
        longer than the width can cut first with `truncate_ordinary`.
        """
        if max_tokens < 0:
            raise Error(
                String(t"knap: a width of {max_tokens} tokens is negative.")
            )
        if pad_id < 0 or pad_id >= self.vocabulary.id_space_size():
            raise Error(
                String(
                    t"knap: padding id {pad_id} is outside this encoding's"
                    t" id space of {self.vocabulary.id_space_size()}."
                )
            )

        var rows = List[List[Int]]()
        var lengths = List[Int]()
        var width = 0
        for index in range(len(documents)):
            var encoded = self.encode_ordinary(documents[index])
            var kept = len(encoded)
            if max_tokens > 0 and kept > max_tokens:
                kept = max_tokens
            lengths.append(kept)
            if kept > width:
                width = kept
            rows.append(encoded^)

        var count = len(documents)
        var ids = List[Int](capacity=count * width)
        var mask = List[UInt8](capacity=count * width)
        for index in range(count):
            var kept = lengths[index]
            for column in range(width):
                if column < kept:
                    ids.append(rows[index][column])
                    mask.append(UInt8(1))
                else:
                    ids.append(pad_id)
                    mask.append(UInt8(0))

        return PaddedBatch(ids^, mask^, lengths^, count, width)

    def token_id_of_bytes(self, data: Span[UInt8, _]) raises -> Int:
        """Look up the id of a byte sequence that may be a single token.

        Args:
            data: The bytes to look up.

        Returns:
            The token id, or minus one when the bytes are not a token of
            this encoding.

        Raises:
            Error: never, in this implementation.

        The inverse of decoding one id, and the question anyone inspecting a
        vocabulary asks first. Not an encoder: it answers whether these
        exact bytes are one token, not what they would encode to.
        """
        return self.ranks.rank_of(data, 0, len(data))

    def token_id_of(self, text: String) raises -> Int:
        """Look up the id of text that may be a single token.

        Args:
            text: The text to look up.

        Returns:
            The token id, or minus one when the text is not a token.

        Raises:
            Error: never, in this implementation.
        """
        return self.token_id_of_bytes(text.as_bytes())

    def token_bytes(self, token_id: Int) raises -> List[UInt8]:
        """Return the bytes one token id decodes to.

        Args:
            token_id: The id to look up.

        Returns:
            That token's bytes.

        Raises:
            Error: if the id is unassigned or out of range.

        A convenience over the vocabulary, so that inspecting one token does
        not require reaching through to the layer below.
        """
        return self.vocabulary.token_bytes(token_id)

    # -------------------------------------------------------------------------
    # Counting
    #
    # Counting is the most common thing anyone asks a tokenizer to do. It is
    # how a prompt is checked against a context window, how a document is
    # priced, and how a corpus is budgeted, and in every one of those the
    # list of ids is built, its length is read, and it is thrown away.
    #
    # These entry points never build it, and what that is worth was measured
    # rather than assumed. It saves memory and it does not save time.
    #
    # On four megabytes of prose, counting and encoding are indistinguishable
    # in throughput and identical in peak memory: the appends are cheap
    # against the merge, and ten megabytes of ids is nothing against the
    # process. On eighty megabytes the peak is 290 MB counting and 611 MB
    # encoding, because the list of ids has grown past everything else.
    #
    # So the honest statement is that this is a memory entry point whose
    # value grows with the input, not a fast path. The expectation when it
    # was written was the other way round, and the measurement is in
    # docs/BENCHMARKS.md.
    # -------------------------------------------------------------------------

    def count_ordinary_bytes(self, data: Span[UInt8, _]) raises -> Int:
        """Count the tokens bytes would become, without building them.

        Args:
            data: The bytes to count.

        Returns:
            How many tokens the input would encode to.

        Raises:
            Error: if the scanner or the merge loop fails.

        The answer is exactly len(encode_ordinary_bytes(data)) and
        tests/test_count.mojo asserts that over every fixture and over the
        110 MB corpus. This is an optimisation, not a second definition of
        what a token is.
        """
        var out = List[Int]()
        var cache = PieceCache(0)
        return self._encode_segment[False, False](data, out, cache)

    def count_ordinary(self, text: String) raises -> Int:
        """Count the tokens text would become, without building them.

        Args:
            text: The text to count.

        Returns:
            How many tokens the input would encode to.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        return self.count_ordinary_bytes(text.as_bytes())

    def count_ordinary_bytes_cached(
        self, data: Span[UInt8, _], mut cache: PieceCache
    ) raises -> Int:
        """Count the tokens bytes would become, consulting a piece cache.

        Args:
            data: The bytes to count.
            cache: The caller's piece cache, updated in place.

        Returns:
            How many tokens the input would encode to.

        Raises:
            Error: if the scanner or the merge loop fails.

        A cache miss still produces the ids, because a cache that stored
        nothing on a miss would never answer a hit. What counting saves here
        is the output list, not the merge.
        """
        var out = List[Int]()
        return self._encode_segment[True, False](data, out, cache)

    def count_ordinary_cached(
        self, text: String, mut cache: PieceCache
    ) raises -> Int:
        """Count the tokens text would become, consulting a piece cache.

        Args:
            text: The text to count.
            cache: The caller's piece cache, updated in place.

        Returns:
            How many tokens the input would encode to.

        Raises:
            Error: if the scanner or the merge loop fails.
        """
        return self.count_ordinary_bytes_cached(text.as_bytes(), cache)

    def count_bytes(
        self, data: Span[UInt8, _], allowed_special: List[String]
    ) raises -> Int:
        """Count tokens with a special token policy, without building them.

        Args:
            data: The bytes to count.
            allowed_special: Literal texts of the special tokens permitted in
                the input. Every other special token this encoding defines is
                disallowed, and its presence is an error.

        Returns:
            How many tokens the input would encode to.

        Raises:
            Error: if a disallowed special token appears in the input.

        The refusal happens here exactly as it does when encoding. Counting
        a document that could not be encoded would be a number nobody can
        act on.
        """
        var out = List[Int]()
        var cache = PieceCache(0)
        return self._encode_bytes_into[False, False](
            data, allowed_special, out, cache
        )

    def count(self, text: String, allowed_special: List[String]) raises -> Int:
        """Count tokens with a special token policy, without building them.

        Args:
            text: The text to count.
            allowed_special: Literal texts of the special tokens permitted in
                the input.

        Returns:
            How many tokens the input would encode to.

        Raises:
            Error: if a disallowed special token appears in the input.
        """
        return self.count_bytes(text.as_bytes(), allowed_special)

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


def load_o200k_harmony_tokenizer(path: String) raises -> Tokenizer:
    """Load an o200k_harmony tokenizer from the o200k_base vocabulary file.

    Args:
        path: Path to o200k_base.tiktoken.

    Returns:
        A tokenizer ready to encode and decode.

    Raises:
        Error: if the vocabulary cannot be loaded.
    """
    var vocabulary = load_o200k_harmony(path)
    return Tokenizer(vocabulary^, PATTERN_O200K)


def load_gpt2_tokenizer(path: String) raises -> Tokenizer:
    """Load a gpt2 tokenizer from the r50k_base vocabulary file.

    Args:
        path: Path to r50k_base.tiktoken.

    Returns:
        A tokenizer ready to encode and decode.

    Raises:
        Error: if the vocabulary cannot be loaded.
    """
    var vocabulary = load_gpt2(path)
    return Tokenizer(vocabulary^, PATTERN_GPT2)


def load_r50k_base_tokenizer(path: String) raises -> Tokenizer:
    """Load an r50k_base tokenizer from its vocabulary file.

    Args:
        path: Path to r50k_base.tiktoken.

    Returns:
        A tokenizer ready to encode and decode.

    Raises:
        Error: if the vocabulary cannot be loaded.
    """
    var vocabulary = load_r50k_base(path)
    return Tokenizer(vocabulary^, PATTERN_GPT2)


def load_p50k_base_tokenizer(path: String) raises -> Tokenizer:
    """Load a p50k_base tokenizer from its vocabulary file.

    Args:
        path: Path to p50k_base.tiktoken.

    Returns:
        A tokenizer ready to encode and decode.

    Raises:
        Error: if the vocabulary cannot be loaded.
    """
    var vocabulary = load_p50k_base(path)
    return Tokenizer(vocabulary^, PATTERN_GPT2)


def load_p50k_edit_tokenizer(path: String) raises -> Tokenizer:
    """Load a p50k_edit tokenizer from the p50k_base vocabulary file.

    Args:
        path: Path to p50k_base.tiktoken.

    Returns:
        A tokenizer ready to encode and decode.

    Raises:
        Error: if the vocabulary cannot be loaded.
    """
    var vocabulary = load_p50k_edit(path)
    return Tokenizer(vocabulary^, PATTERN_GPT2)


# =============================================================================
# End of file: src/knap/tokenizer.mojo
# =============================================================================
