# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/special.mojo
# Purpose     : Special token registry: the literal texts and the token ids
#               that sit outside the merge vocabulary.
# Stage       : Pipeline stage 1 of 4, see docs/ARCHITECTURE.md
# Depends on  : errors.mojo
# Invariants  : Special token ids never overlap merge ranks, and the id space
#               between the two is not contiguous. Gaps are real and must
#               stay undecodable.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Special token registry for Knap.

Special tokens are not in the .tiktoken file. They are defined by the
encoding, they sit above the merge ranks, and they decode to their own
literal text.

The important and easily missed property is that the token id space has
**gaps**. In cl100k_base the merge ranks run from 0 to 100255 and the
specials occupy 100257 to 100276, but only five of those twenty ids are
assigned. Sixteen ids in the range are defined by nothing and tiktoken
raises when asked to decode them.

Knap reproduces that exactly. A tokenizer that helpfully returned empty
bytes for an unassigned id would diverge from the reference on precisely the
inputs where a caller most needs to be told it has a bug.

The definitions below are written out rather than parsed from anywhere,
because nothing distributes them as data. They were read from tiktoken
0.14.0, and tests/test_special.mojo checks every one of them against a
fixture generated from tiktoken, so a mistake here fails the build rather
than shipping.
"""

from .errors import special_token_unknown


# -----------------------------------------------------------------------------
# Registry
#
# Backed by two parallel lists rather than a dictionary. Both target
# vocabularies define at most five special tokens, so a linear scan is faster
# than hashing and the contents stay trivially inspectable in a debugger.
# -----------------------------------------------------------------------------


struct SpecialTokens(Copyable, Movable):
    """The special tokens an encoding defines."""

    var names: List[String]
    """Literal text of each special token, such as the end of text marker."""

    var ids: List[Int]
    """Token id of each special token, parallel to names."""

    def __init__(out self):
        """Create an empty registry.

        "out self" marks self as an uninitialized slot this function fills.
        """
        self.names = List[String]()
        self.ids = List[Int]()

    def add(mut self, name: String, token_id: Int) raises:
        """Register one special token.

        Args:
            name: The literal text, including its delimiters.
            token_id: The id this token encodes to and decodes from.

        Raises:
            Error: if the name or the id is already registered.

        Both directions are checked because either kind of duplicate makes
        the registry ambiguous, and an ambiguous registry produces a
        tokenizer that is wrong only sometimes.
        """
        for index in range(len(self.names)):
            if self.names[index] == name:
                raise Error(
                    String(
                        t"knap: special token '{name}' is already registered."
                    )
                )
            if self.ids[index] == token_id:
                raise Error(
                    String(
                        t"knap: special token id {token_id} is already"
                        t" registered as '{self.names[index]}'."
                    )
                )
        self.names.append(name)
        self.ids.append(token_id)

    def count(self) -> Int:
        """Return how many special tokens are registered.

        Returns:
            The number of registered special tokens.
        """
        return len(self.ids)

    def id_of(self, name: String) raises -> Int:
        """Look up the id of a special token by its literal text.

        Args:
            name: The literal text to look up.

        Returns:
            The token id.

        Raises:
            Error: if this encoding defines no such special token.
        """
        for index in range(len(self.names)):
            if self.names[index] == name:
                return self.ids[index]
        raise special_token_unknown(name)

    def index_of_id(self, token_id: Int) -> Int:
        """Find the registry position holding a token id.

        Args:
            token_id: The id to search for.

        Returns:
            The index into names and ids, or -1 when the id is not a special
            token in this encoding.

        Returning -1 rather than raising keeps this usable as a test in the
        decode path, which asks "is this a special token" about every id it
        cannot find among the merges.
        """
        for index in range(len(self.ids)):
            if self.ids[index] == token_id:
                return index
        return -1

    def name_at(self, index: Int) raises -> String:
        """Return the literal text at a registry position.

        Args:
            index: Position previously returned by index_of_id.

        Returns:
            The literal text of that special token.

        Raises:
            Error: if the index is outside the registry.
        """
        if index < 0 or index >= len(self.names):
            raise Error(
                String(
                    t"knap: special token index {index} is out of range for"
                    t" a registry of {len(self.names)} entries."
                )
            )
        return self.names[index]

    def id_at(self, index: Int) raises -> Int:
        """Return the token id at a registry position.

        Args:
            index: Position in the registry.

        Returns:
            The token id at that position.

        Raises:
            Error: if the index is outside the registry.
        """
        if index < 0 or index >= len(self.ids):
            raise Error(
                String(
                    t"knap: special token index {index} is out of range for"
                    t" a registry of {len(self.ids)} entries."
                )
            )
        return self.ids[index]

    def highest_id(self) -> Int:
        """Return the largest registered special token id.

        Returns:
            The largest id, or -1 when nothing is registered.

        Used to size the full id space, which runs from zero to this value
        inclusive and contains gaps along the way.
        """
        var highest = -1
        for index in range(len(self.ids)):
            if self.ids[index] > highest:
                highest = self.ids[index]
        return highest


# -----------------------------------------------------------------------------
# Encoding definitions
#
# Source: tiktoken 0.14.0, read from the encoding objects themselves rather
# than from documentation. tests/test_special.mojo verifies each entry against
# a fixture regenerated from tiktoken, so drift fails the build.
# -----------------------------------------------------------------------------


def cl100k_base_specials() raises -> SpecialTokens:
    """Build the special token registry for cl100k_base.

    Returns:
        A registry holding the five special tokens cl100k_base defines.

    Raises:
        Error: never in practice, since the table below is fixed and free of
            duplicates. The registry's add method validates regardless.

    Merge ranks occupy 0 to 100255. The ids below are not contiguous with
    those and not contiguous with each other: 100256 and 100261 through
    100275 are assigned to nothing at all.
    """
    var specials = SpecialTokens()
    specials.add(String("<|endoftext|>"), 100257)
    specials.add(String("<|fim_prefix|>"), 100258)
    specials.add(String("<|fim_middle|>"), 100259)
    specials.add(String("<|fim_suffix|>"), 100260)
    specials.add(String("<|endofprompt|>"), 100276)
    return specials^


def o200k_base_specials() raises -> SpecialTokens:
    """Build the special token registry for o200k_base.

    Returns:
        A registry holding the two special tokens o200k_base defines.

    Raises:
        Error: never in practice. See cl100k_base_specials.

    Merge ranks occupy 0 to 199997. As with cl100k_base the id space has
    gaps: 199998 and 200000 through 200017 are unassigned.
    """
    var specials = SpecialTokens()
    specials.add(String("<|endoftext|>"), 199999)
    specials.add(String("<|endofprompt|>"), 200018)
    return specials^


# =============================================================================
# End of file: src/knap/special.mojo
# =============================================================================
