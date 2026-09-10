# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/cache.mojo
# Purpose     : Bounded map from piece bytes to token ids, for reuse across
#               repeated pre-tokens.
# Stage       : Pipeline stage 4 of 4, see docs/ARCHITECTURE.md
# Depends on  : Nothing. A pure data structure over bytes and integers.
# Invariants  : A hit returns exactly the ids the merge loop would have
#               produced. The cache never changes what is encoded, only how
#               often the merge loop runs.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""A bounded piece cache for the merge loop.

Pre-tokenization produces short pieces, and natural text repeats them
heavily. The merge loop is the expensive stage of the pipeline and it is a
pure function of the piece bytes and the rank table, so a piece seen twice
need only be merged once.

The structure is deliberately plain: open addressing with linear probing,
FNV-1a over the piece bytes, and flat arenas holding the keys and the
values. There is no eviction. A full cache stops accepting new entries and
keeps serving the ones it has, which for a Zipf distributed input is very
nearly as good as eviction and is far easier to reason about. An eviction
policy is a place for a correctness bug to hide, and this structure sits
directly under the parity claim.

Three properties are worth stating, because they are what make the cache
safe rather than merely fast.

  * It is not required. Every public encode path works without it, and the
    uncached path is the reference the cached path is tested against.
  * It cannot change the answer. A miss computes the same ids the uncached
    path would, and a hit copies ids that were computed that way earlier.
    tests/test_cache.mojo asserts this over the whole fixture set rather
    than assuming it.
  * It is owned by the caller. The cache is passed in rather than held
    inside the tokenizer, so a tokenizer stays immutable and shareable, and
    the memory cost is visible at the call site instead of hidden in a
    constructor.

Not thread safe, and it does not need to be yet. Mojo 1.0.0 has no working
task parallelism, so nothing in this repository is concurrent. When that
changes, one cache per worker is the answer rather than a lock: entries are
cheap to recompute, and a contended lock would cost more than the misses it
saved.
"""


comptime FNV_OFFSET_BASIS: UInt64 = 0xCBF29CE484222325
"""The 64 bit FNV-1a offset basis, as published."""

comptime FNV_PRIME: UInt64 = 0x100000001B3
"""The 64 bit FNV-1a prime, as published."""

comptime DEFAULT_MAX_PIECE: Int = 64
"""Longest piece the cache will store, in bytes.

Pieces longer than this are encoded normally and never cached. They are
rare in natural text, they are the ones that would dominate the key arena,
and a long piece is the case where the merge loop's own cost is large
enough that hashing the whole piece stops being negligible beside it.
"""


def hash_piece(data: Span[UInt8, _], start: Int, end: Int) -> UInt64:
    """Hash a byte range with FNV-1a.

    Args:
        data: The buffer holding the piece.
        start: First byte offset, inclusive.
        end: One past the last byte offset.

    Returns:
        The 64 bit hash.

    FNV-1a rather than anything stronger. The keys are short pre-tokens
    drawn from text rather than inputs chosen to attack this table, and a
    collision costs one extra comparison rather than a wrong answer, because
    every probe verifies the bytes before it accepts an entry.
    """
    var accumulator = FNV_OFFSET_BASIS
    for index in range(start, end):
        accumulator = accumulator ^ UInt64(Int(data[index]))
        accumulator = accumulator * FNV_PRIME
    return accumulator


struct PieceCache(Movable):
    """A bounded map from piece bytes to the token ids they encode to.

    Open addressing with linear probing. Keys and values live in flat
    arenas, so one entry costs no separate allocation. That matters because
    entries are small and numerous, and a per entry allocation would cost
    more than the merge loop the cache exists to avoid.
    """

    var key_data: List[UInt8]
    """Arena holding every stored key's bytes, back to back."""

    var key_start: List[Int]
    """Offset into key_data where each entry's key begins."""

    var key_length: List[Int]
    """Length in bytes of each entry's key."""

    var value_data: List[Int]
    """Arena holding every stored value's token ids, back to back."""

    var value_start: List[Int]
    """Offset into value_data where each entry's ids begin."""

    var value_length: List[Int]
    """Count of token ids in each entry."""

    var slots: List[Int]
    """Probe table. Each cell holds an entry index, or -1 when empty."""

    var mask: Int
    """One less than the slot count, which is always a power of two."""

    var capacity: Int
    """Most entries this cache will hold. Zero disables it entirely."""

    var max_piece: Int
    """Longest piece in bytes that will be stored."""

    var hits: Int
    """Lookups that were served from the table."""

    var misses: Int
    """Lookups that were not, and so ran the merge loop."""

    var rejected: Int
    """Pieces not offered to the table, being too long or the cache full."""

    def __init__(out self, capacity: Int, max_piece: Int = DEFAULT_MAX_PIECE):
        """Build a cache that will hold at most capacity entries.

        Args:
            capacity: Most entries to store. Zero builds a cache that never
                stores anything, which is how the uncached paths share one
                implementation without paying for a table.
            max_piece: Longest piece in bytes to store.

        The probe table is sized to the next power of two at or above twice
        the capacity, so the load factor never exceeds one half and linear
        probing stays short. Sizing it from the capacity up front rather
        than growing on demand means the table never rehashes, which keeps
        the cost of a lookup flat for the life of the cache.
        """
        self.key_data = List[UInt8]()
        self.key_start = List[Int]()
        self.key_length = List[Int]()
        self.value_data = List[Int]()
        self.value_start = List[Int]()
        self.value_length = List[Int]()
        self.capacity = capacity if capacity > 0 else 0
        self.max_piece = max_piece
        self.hits = 0
        self.misses = 0
        self.rejected = 0

        var slot_count = 1
        if self.capacity > 0:
            var wanted = self.capacity * 2
            while slot_count < wanted:
                slot_count *= 2
        self.mask = slot_count - 1
        self.slots = List[Int](capacity=slot_count)
        for _ in range(slot_count):
            self.slots.append(-1)

    def enabled(self) -> Bool:
        """Report whether this cache will ever store anything.

        Returns:
            True when the capacity is positive.
        """
        return self.capacity > 0

    def count(self) -> Int:
        """Report how many entries are stored.

        Returns:
            The entry count.
        """
        return len(self.key_start)

    def _matches(
        self, entry: Int, data: Span[UInt8, _], start: Int, end: Int
    ) -> Bool:
        """Compare one stored key against a byte range.

        Args:
            entry: Index of the stored entry.
            data: The buffer holding the piece.
            start: First byte offset, inclusive.
            end: One past the last byte offset.

        Returns:
            True when the bytes are identical.

        Every probe calls this, and this is what makes a hash collision a
        cost rather than a defect. Removing it to save a comparison would
        turn a collision into a wrong token sequence.
        """
        var length = end - start
        if self.key_length[entry] != length:
            return False
        var base = self.key_start[entry]
        for offset in range(length):
            if self.key_data[base + offset] != data[start + offset]:
                return False
        return True

    def lookup(self, data: Span[UInt8, _], start: Int, end: Int) -> Int:
        """Find the entry for a piece.

        Args:
            data: The buffer holding the piece.
            start: First byte offset, inclusive.
            end: One past the last byte offset.

        Returns:
            The entry index, or -1 when the piece is not stored.

        Does not count a hit or a miss. The caller does that, because only
        the caller knows whether it went on to run the merge loop.
        """
        if self.capacity == 0:
            return -1
        var slot = Int(hash_piece(data, start, end) & UInt64(self.mask))
        while True:
            var entry = self.slots[slot]
            if entry < 0:
                return -1
            if self._matches(entry, data, start, end):
                return entry
            slot = (slot + 1) & self.mask

    def value_count(self, entry: Int) -> Int:
        """Return how many ids are stored against one entry.

        Args:
            entry: Index of a stored entry, as returned by lookup.

        Returns:
            The number of token ids.

        The counting path needs this and nothing else from a cache hit.
        Appending the ids in order to take their length would defeat the
        point of not building the list.
        """
        return self.value_length[entry]

    def append_value(self, entry: Int, mut out: List[Int]):
        """Append a stored entry's token ids to a buffer.

        Args:
            entry: Index of the stored entry, as returned by lookup.
            out: Buffer receiving the ids, in order.
        """
        var base = self.value_start[entry]
        for offset in range(self.value_length[entry]):
            out.append(self.value_data[base + offset])

    def insert(
        mut self,
        data: Span[UInt8, _],
        start: Int,
        end: Int,
        ids: Span[Int, _],
    ):
        """Store the ids a piece encodes to, if there is room for them.

        Args:
            data: The buffer holding the piece.
            start: First byte offset, inclusive.
            end: One past the last byte offset.
            ids: The token ids the merge loop produced for it.

        Silently declines in three cases: the cache is disabled, it is
        already full, or the piece is longer than max_piece. Declining is
        not an error, and it is counted apart from a miss, because the two
        mean different things when reading a hit rate.
        """
        var length = end - start
        if self.capacity == 0 or length > self.max_piece:
            self.rejected += 1
            return
        if len(self.key_start) >= self.capacity:
            self.rejected += 1
            return

        var entry = len(self.key_start)
        self.key_start.append(len(self.key_data))
        self.key_length.append(length)
        for offset in range(length):
            self.key_data.append(data[start + offset])

        self.value_start.append(len(self.value_data))
        self.value_length.append(len(ids))
        for index in range(len(ids)):
            self.value_data.append(ids[index])

        var slot = Int(hash_piece(data, start, end) & UInt64(self.mask))
        while self.slots[slot] >= 0:
            slot = (slot + 1) & self.mask
        self.slots[slot] = entry

    def record_hit(mut self):
        """Count one lookup that was served from the table."""
        self.hits += 1

    def record_miss(mut self):
        """Count one lookup that had to run the merge loop."""
        self.misses += 1

    def hit_rate(self) -> Float64:
        """Report the fraction of lookups served from the table.

        Returns:
            Hits divided by lookups, or zero when there were none.

        Reported rather than inferred from the entry count. A cache holding
        many entries and serving none of them is a memory cost with no
        benefit, and only this number tells the two apart.
        """
        var lookups = self.hits + self.misses
        if lookups == 0:
            return 0.0
        return Float64(self.hits) / Float64(lookups)


# =============================================================================
# End of file: src/knap/cache.mojo
# =============================================================================
