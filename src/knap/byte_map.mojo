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


comptime FNV_OFFSET_BASIS: UInt64 = 0xCBF29CE484222325
"""The 64 bit FNV-1a offset basis, as published."""

comptime FNV_PRIME: UInt64 = 0x100000001B3
"""The 64 bit FNV-1a prime, as published."""

comptime MISSING: Int = -1
"""Returned by lookup when a byte range is not in the map."""


def hash_bytes(data: Span[UInt8, _], start: Int, end: Int) -> UInt64:
    """Hash a byte range with FNV-1a.

    Args:
        data: The buffer holding the range.
        start: First byte offset, inclusive.
        end: One past the last byte offset.

    Returns:
        The 64 bit hash.

    FNV-1a rather than anything stronger. The keys are token byte strings
    and short pre-tokens, not inputs chosen to attack this table, and a
    collision costs one extra comparison rather than a wrong answer, because
    every probe verifies the bytes before it accepts an entry.
    """
    var accumulator = FNV_OFFSET_BASIS
    for index in range(start, end):
        accumulator = accumulator ^ UInt64(Int(data[index]))
        accumulator = accumulator * FNV_PRIME
    return accumulator


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

    var slots: List[Int]
    """Probe table. Each cell holds an entry index, or -1 when empty."""

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
        self.slots = List[Int](capacity=slot_count)
        for _ in range(slot_count):
            self.slots.append(-1)

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
        """
        if self.capacity == 0:
            return MISSING
        var slot = Int(hash_bytes(data, start, end) & UInt64(self.mask))
        while True:
            var entry = self.slots[slot]
            if entry < 0:
                return MISSING
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

        var slot = Int(hash_bytes(data, start, end) & UInt64(self.mask))
        while self.slots[slot] >= 0:
            slot = (slot + 1) & self.mask
        self.slots[slot] = entry
        return True


# =============================================================================
# End of file: src/knap/byte_map.mojo
# =============================================================================
