# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/byte_map.mojo
# Purpose     : Hash map from a borrowed byte range to an integer, with no
#               allocation on lookup.
# Stage       : Shared substrate. See docs/ARCHITECTURE.md
# Depends on  : Nothing. A data structure over bytes and integers.
# Invariants  : Every probe compares the bytes before accepting an entry, so
#               a hash collision costs a comparison and never an answer.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""A map from a byte range to an integer, looked up without allocating.

Two places in Knap need this and neither can afford the obvious version.

The merge loop asks for the rank of a byte range, repeatedly, and the range
is a slice of a buffer the caller already holds. A `Dict[String, Int]` can
answer that, but only by copying those bytes into a fresh String first, and
the merge loop is quadratic in the piece length, so a five byte piece costs
ten allocations before anything is looked up. That was measured: it is where
encode throughput went. See docs/BENCHMARKS.md.

The piece cache asks the same question of the same shape.

So the map is keyed on a borrowed span. Keys are copied once, at insertion,
into a flat arena; a lookup hashes the caller's bytes in place and compares
against the arena. Nothing is allocated to ask a question.

Design notes, all of them deliberate:

  * **Open addressing with linear probing.** The alternative, chaining,
    costs a pointer chase per probe and an allocation per entry.
  * **No growth.** Both callers know their entry count before they build,
    so the table is sized once and never rehashes. That keeps a lookup's
    cost flat and removes the only step that could invalidate an index the
    caller is holding.
  * **An integer payload, not a value type.** The rank table stores a rank.
    The piece cache stores an index into its own arenas. One integer serves
    both, and keeping the map ignorant of what the integer means is what
    lets one structure serve two purposes without a parameter.

Not thread safe for writes. Lookups are read only and safe to share.
"""


comptime HASH_SEED: UInt64 = 0xCBF29CE484222325
"""Starting value for the hash. Any odd constant would do."""

comptime HASH_MULTIPLIER: UInt64 = 0x9E3779B97F4A7C15
"""Mixing multiplier, the 64 bit golden ratio constant.

An odd multiplier with well spread bits, which is what a multiply and shift
mixer needs. The exact value matters only in that it must be odd, so the
multiplication is invertible and no information is thrown away.
"""

comptime HASH_ROTATION: Int = 23
"""Bits to rotate the accumulator by before folding in the next word."""

comptime WORD_BYTES: Int = 8
"""Bytes consumed per iteration of the wide loop."""

comptime MISSING: Int = -1
"""Returned by lookup when a byte range is not in the map."""

comptime EMPTY_SLOT: UInt64 = 0
"""Value of an unused probe cell.

Zero is available as the empty marker because a used cell stores the entry
index plus one, so the smallest used value is one.
"""

comptime ENTRY_MASK: UInt64 = 0xFFFFFFFF
"""Low half of a probe cell, holding the entry index plus one.

Thirty two bits caps the map at just over four billion entries. The largest
vocabulary this project loads has two hundred thousand.
"""

comptime TAG_SHIFT: UInt64 = 32
"""Bits to shift the hash tag by when packing it into a probe cell."""


def hash_bytes(data: Span[UInt8, _], start: Int, end: Int) -> UInt64:
    """Hash a byte range, eight bytes at a time.

    Args:
        data: The buffer holding the range.
        start: First byte offset, inclusive.
        end: One past the last byte offset.

    Returns:
        The 64 bit hash.

    Not a cryptographic hash and not trying to be. The keys are token byte
    strings and short pre-tokens, not inputs chosen to attack this table,
    and a collision costs one extra comparison rather than a wrong answer,
    because every probe verifies the bytes before it accepts an entry.

    This used to be FNV-1a, which is a byte at a time: one exclusive or and
    one multiply for every byte of every key. The encoder asks this question
    several times per word, so the loop trip count was the cost. Reading
    eight bytes at once turns a key of eight bytes from eight multiplies
    into one.

    The read is deliberately unaligned. A pre-token starts wherever the
    previous one ended, so alignment is not available, and x86-64 loads
    unaligned words at no cost. The wide loop only runs while a whole word
    remains inside the range, so it never reads past the end.

    The length is folded in at the start. Without it the tail packing would
    give the same value to a key and to that key followed by zero bytes,
    which is a collision that costs nothing but is free to avoid.
    """
    var accumulator = HASH_SEED ^ UInt64(end - start)
    var pointer = data.unsafe_ptr()
    var index = start

    while index + WORD_BYTES <= end:
        var word = (
            pointer.unsafe_offset(index).unsafe_bitcast[UInt64]().unsafe_load()
        )
        accumulator = _rotate_left(accumulator, HASH_ROTATION) ^ word
        accumulator = accumulator * HASH_MULTIPLIER
        index += WORD_BYTES

    # The tail is at most seven bytes, packed low to high into one word.
    var tail = UInt64(0)
    var shift = UInt64(0)
    while index < end:
        tail = tail | (UInt64(Int(data[index])) << shift)
        shift += 8
        index += 1
    accumulator = _rotate_left(accumulator, HASH_ROTATION) ^ tail
    accumulator = accumulator * HASH_MULTIPLIER

    # Final avalanche. The map takes the low bits of this value as a slot
    # index, and a multiply alone leaves the low bits weakly mixed.
    accumulator = accumulator ^ (accumulator >> 32)
    accumulator = accumulator * HASH_MULTIPLIER
    return accumulator ^ (accumulator >> 29)


def _rotate_left(value: UInt64, amount: Int) -> UInt64:
    """Rotate a 64 bit value left.

    Args:
        value: The value to rotate.
        amount: How many bits, which must be between 1 and 63.

    Returns:
        The rotated value.

    A rotation rather than a shift so that no bit is discarded between one
    word and the next.
    """
    return (value << UInt64(amount)) | (value >> UInt64(64 - amount))


struct ByteMap(Movable):
    """A fixed capacity map from a byte range to an integer."""

    var key_data: List[UInt8]
    """Arena holding every key's bytes, back to back."""

    var key_start: List[Int]
    """Offset into key_data where each entry's key begins."""

    var key_length: List[Int]
    """Length in bytes of each entry's key."""

    var payload: List[Int]
    """The integer stored against each entry."""

    var slots: List[UInt64]
    """Probe table, one packed word per cell.

    Zero means the cell is empty. Otherwise the high thirty two bits are a
    tag taken from the key's hash and the low thirty two bits are the entry
    index plus one, so that a used cell is never zero.

    Packed into one word rather than kept in two parallel arrays because the
    point is the number of cache lines a probe touches. A tag that lived in
    its own array would be a second miss and would undo half the reason for
    having it.
    """

    var mask: Int
    """One less than the slot count, which is always a power of two."""

    var capacity: Int
    """Most entries this map will hold. Zero makes every lookup a miss."""

    def __init__(out self, capacity: Int, key_bytes_hint: Int = 0):
        """Build a map sized for a known number of entries.

        Args:
            capacity: Most entries the map will hold. Zero builds a map that
                stores nothing and answers every lookup with MISSING, which
                is how a caller can hold a disabled map without a special
                case.
            key_bytes_hint: Expected total size of all keys, used to reserve
                the arena. Wrong is harmless; it only costs a reallocation.

        The probe table is the next power of two at or above twice the
        capacity, so the load factor never exceeds one half and probe runs
        stay short.
        """
        self.key_data = List[UInt8](capacity=key_bytes_hint)
        self.key_start = List[Int]()
        self.key_length = List[Int]()
        self.payload = List[Int]()
        self.capacity = capacity if capacity > 0 else 0

        var slot_count = 1
        if self.capacity > 0:
            var wanted = self.capacity * 2
            while slot_count < wanted:
                slot_count *= 2
        self.mask = slot_count - 1
        self.slots = List[UInt64](capacity=slot_count)
        for _ in range(slot_count):
            self.slots.append(EMPTY_SLOT)

    def count(self) -> Int:
        """Report how many entries the map holds.

        Returns:
            The entry count.
        """
        return len(self.key_start)

    def full(self) -> Bool:
        """Report whether the map has reached its capacity.

        Returns:
            True when no further entry can be inserted.
        """
        return len(self.key_start) >= self.capacity

    def _matches(
        self, entry: Int, data: Span[UInt8, _], start: Int, end: Int
    ) -> Bool:
        """Compare one stored key against a byte range.

        Args:
            entry: Index of the stored entry.
            data: The buffer holding the range.
            start: First byte offset, inclusive.
            end: One past the last byte offset.

        Returns:
            True when the bytes are identical.

        This is what makes a hash collision a cost rather than a defect.
        Removing it to save a comparison would turn a collision into a wrong
        merge rank, which is a wrong token, which is a parity failure on
        input nobody would think to test.
        """
        var length = end - start
        if self.key_length[entry] != length:
            return False
        var base = self.key_start[entry]
        for offset in range(length):
            if self.key_data[base + offset] != data[start + offset]:
                return False
        return True

    def find(self, data: Span[UInt8, _], start: Int, end: Int) -> Int:
        """Find the entry index for a byte range.

        Args:
            data: The buffer holding the range.
            start: First byte offset, inclusive.
            end: One past the last byte offset.

        Returns:
            The entry index, or MISSING when the range is not stored.

        The tag comparison is the whole point. Only when the top half of the
        cell matches the top half of the hash does this touch the key
        arrays, so a probe that is going to fail usually fails after a
        single load. The bytes are still compared before an entry is
        accepted, because a tag is thirty two bits and equal tags are not
        equal keys.
        """
        if self.capacity == 0:
            return MISSING
        var hash = hash_bytes(data, start, end)
        var tag = hash >> TAG_SHIFT
        var slot = Int(hash & UInt64(self.mask))
        while True:
            var cell = self.slots[slot]
            if cell == EMPTY_SLOT:
                return MISSING
            if (cell >> TAG_SHIFT) == tag:
                var entry = Int(cell & ENTRY_MASK) - 1
                if self._matches(entry, data, start, end):
                    return entry
            slot = (slot + 1) & self.mask

    def lookup(self, data: Span[UInt8, _], start: Int, end: Int) -> Int:
        """Look up the integer stored against a byte range.

        Args:
            data: The buffer holding the range.
            start: First byte offset, inclusive.
            end: One past the last byte offset.

        Returns:
            The stored integer, or MISSING when the range is not stored.

        A caller that stores MISSING as a payload cannot tell the two apart.
        Neither caller in this project does, and neither should: MISSING is
        negative and both payloads are indices or ranks.
        """
        var entry = self.find(data, start, end)
        if entry == MISSING:
            return MISSING
        return self.payload[entry]

    def payload_at(self, entry: Int) -> Int:
        """Read the integer stored against one entry.

        Args:
            entry: Index of the entry, as returned by find.

        Returns:
            The stored integer.
        """
        return self.payload[entry]

    def insert(
        mut self, data: Span[UInt8, _], start: Int, end: Int, value: Int
    ) -> Bool:
        """Store an integer against a byte range.

        Args:
            data: The buffer holding the range.
            start: First byte offset, inclusive.
            end: One past the last byte offset.
            value: The integer to store.

        Returns:
            True when the entry was stored, False when the map is full or
            disabled.

        Does not check for an existing entry with the same key. Both callers
        insert each key once by construction, and paying for a lookup on
        every insertion would double the cost of building a hundred thousand
        entry rank table for a case that cannot arise.
        """
        if self.capacity == 0 or len(self.key_start) >= self.capacity:
            return False

        var entry = len(self.key_start)
        self.key_start.append(len(self.key_data))
        self.key_length.append(end - start)
        for index in range(start, end):
            self.key_data.append(data[index])
        self.payload.append(value)

        var hash = hash_bytes(data, start, end)
        var slot = Int(hash & UInt64(self.mask))
        while self.slots[slot] != EMPTY_SLOT:
            slot = (slot + 1) & self.mask
        self.slots[slot] = ((hash >> TAG_SHIFT) << TAG_SHIFT) | UInt64(
            entry + 1
        )
        return True


# =============================================================================
# End of file: src/knap/byte_map.mojo
# =============================================================================
