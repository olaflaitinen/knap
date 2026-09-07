# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/flat_vocab.mojo
# Purpose     : Contiguous token byte storage with parallel offset and length
#               arrays, and the decode path that reads from it.
# Stage       : Pipeline support, used by decode and by stage 4
# Depends on  : errors.mojo
# Invariants  : offsets and lengths have one entry per token id, and every
#               offset plus length stays within data. Checked at construction,
#               so no read after that point needs a bounds test.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Flat vocabulary storage for Knap.

Every token's byte string is concatenated into one buffer, with an offset and
a length recorded per token id. Decoding a token is then a copy from a known
position rather than a pointer chase through a hundred thousand separately
allocated strings.

This layout is standard practice and is not presented as an innovation. It is
also the reason decode is fast in every implementation, which is precisely
why docs/BENCHMARKS.md will not headline a decode number.

One deliberate choice about types. Token byte strings are arbitrary bytes and
are frequently not valid UTF-8 on their own, because a multi-byte character
is often split across several tokens. Everything here therefore works in
List[UInt8], and conversion to String is offered separately and explicitly.
"""

from .errors import token_id_out_of_range


struct FlatVocab(Copyable, Movable):
    """Contiguous storage for every token byte string in a vocabulary.

    The three lists are parallel: offsets and lengths always have the same
    number of entries, and that count is the vocabulary size.
    """

    var data: List[UInt8]
    """Every token's bytes, concatenated in token id order."""

    var offsets: List[Int]
    """Start index into data for each token id."""

    var lengths: List[Int]
    """Byte length for each token id."""

    # -------------------------------------------------------------------------
    # Construction
    #
    # The constructor takes ownership of finished lists rather than offering
    # an append API. Building the buffer needs two passes over the parsed
    # tokens (lengths first, then a copy into place), and that work belongs to
    # the loader in vocab.mojo which already holds the parsed data.
    # -------------------------------------------------------------------------

    def __init__(
        out self,
        var data: List[UInt8],
        var offsets: List[Int],
        var lengths: List[Int],
    ) raises:
        """Take ownership of the three parallel arrays and validate them.

        Args:
            data: Concatenated token bytes.
            offsets: Start index per token id.
            lengths: Byte length per token id.

        Raises:
            Error: if the arrays disagree in length, or if any token's span
                falls outside data.

        The validation runs once here so that every later read is known to be
        in bounds without testing. Skipping it would move the cost to the
        decode loop and would turn a construction time mistake into a silent
        out of bounds read.

        "out self" marks self as an uninitialized slot this function must
        fill. "var" on an argument means the function takes ownership of it,
        and the caret operator transfers that ownership onward.
        """
        if len(offsets) != len(lengths):
            raise Error(
                String(
                    t"knap: FlatVocab offsets has {len(offsets)} entries but"
                    t" lengths has {len(lengths)}; they must be parallel."
                )
            )

        var total = len(data)
        for token_id in range(len(offsets)):
            var start = offsets[token_id]
            var length = lengths[token_id]
            if start < 0 or length < 0 or start + length > total:
                raise Error(
                    String(
                        t"knap: FlatVocab entry {token_id} spans"
                        t" [{start}, {start + length}) which is outside a"
                        t" buffer of {total} bytes."
                    )
                )

        self.data = data^
        self.offsets = offsets^
        self.lengths = lengths^

    # -------------------------------------------------------------------------
    # Queries
    # -------------------------------------------------------------------------

    def size(self) -> Int:
        """Return the number of token ids this vocabulary defines.

        Returns:
            The count of token ids, so valid ids are 0 up to this minus one.
        """
        return len(self.offsets)

    def token_length(self, token_id: Int) raises -> Int:
        """Return the byte length of one token.

        Args:
            token_id: The id to measure.

        Returns:
            The number of bytes the token occupies.

        Raises:
            Error: if the id is outside the vocabulary.

        Useful before decoding, so a caller can size an output buffer in one
        pass instead of growing it repeatedly.
        """
        if token_id < 0 or token_id >= len(self.lengths):
            raise token_id_out_of_range(token_id, len(self.lengths))
        return self.lengths[token_id]

    def token_bytes(self, token_id: Int) raises -> List[UInt8]:
        """Return a copy of one token's bytes.

        Args:
            token_id: The id to look up.

        Returns:
            A newly allocated list holding that token's bytes.

        Raises:
            Error: if the id is outside the vocabulary.

        This copies, so it belongs in tests and in caller convenience code
        rather than in a decode loop. The loop uses append_token, which writes
        straight into the caller's buffer.
        """
        if token_id < 0 or token_id >= len(self.offsets):
            raise token_id_out_of_range(token_id, len(self.offsets))

        var start = self.offsets[token_id]
        var length = self.lengths[token_id]
        var out = List[UInt8](capacity=length)
        for index in range(length):
            out.append(self.data[start + index])
        return out^

    # -------------------------------------------------------------------------
    # Decoding
    #
    # append_token is the primitive and decode is a loop over it. Keeping the
    # single token case separate means a caller decoding a stream does not
    # have to allocate one list per token.
    # -------------------------------------------------------------------------

    def append_token(self, token_id: Int, mut out: List[UInt8]) raises:
        """Append one token's bytes to a caller supplied buffer.

        Args:
            token_id: The id to append.
            out: Buffer to append into. "mut" marks it as a mutable
                reference, so the caller sees the appended bytes.

        Raises:
            Error: if the id is outside the vocabulary.

        The bounds check here is on the token id only. The span itself was
        validated at construction, so the copy below cannot run off the end
        of data.
        """
        if token_id < 0 or token_id >= len(self.offsets):
            raise token_id_out_of_range(token_id, len(self.offsets))

        var start = self.offsets[token_id]
        var length = self.lengths[token_id]
        for index in range(length):
            out.append(self.data[start + index])

    def decode_bytes(self, token_ids: List[Int]) raises -> List[UInt8]:
        """Decode a sequence of token ids to the exact bytes they represent.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            The concatenated token bytes, exactly as stored.

        Raises:
            Error: if any id is outside the vocabulary. Nothing is returned
                in that case, so a caller never receives a partial decode
                that looks complete.

        This is the byte exact interface and the one parity is defined
        against. The result may not be valid UTF-8, because a multi-byte
        character can be split across tokens and a caller may decode a slice
        of a longer sequence.

        An empty input returns an empty list rather than an error.
        """
        # Size the output in one pass so the append loop never reallocates.
        # Bounds are checked here rather than inside the copy loop.
        var total = 0
        for index in range(len(token_ids)):
            var token_id = token_ids[index]
            if token_id < 0 or token_id >= len(self.lengths):
                raise token_id_out_of_range(token_id, len(self.lengths))
            total += self.lengths[token_id]

        var out = List[UInt8](capacity=total)
        for index in range(len(token_ids)):
            var token_id = token_ids[index]
            var start = self.offsets[token_id]
            var length = self.lengths[token_id]
            for offset in range(length):
                out.append(self.data[start + offset])
        return out^

    def decode(self, token_ids: List[Int]) raises -> String:
        """Decode a sequence of token ids to text.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            A String holding the decoded bytes.

        Raises:
            Error: if any id is outside the vocabulary.

        The returned String carries the decoded bytes unchanged and is not
        validated as UTF-8, because byte level BPE can legitimately produce a
        partial sequence. Callers that need a guarantee of well formed text
        should decode a complete token sequence, or work with decode_bytes
        and validate for themselves.
        """
        var raw = self.decode_bytes(token_ids)
        # Span borrows the list rather than copying it. The String constructor
        # is named "unsafe_from_utf8" because it performs no validation, which
        # is exactly the behaviour required here.
        return String(unsafe_from_utf8=Span(raw))


# =============================================================================
# End of file: src/knap/flat_vocab.mojo
# =============================================================================
