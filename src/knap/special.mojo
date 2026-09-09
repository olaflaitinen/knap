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
            Error: if the name is already registered.

        A repeated name is refused and a repeated id is not, and the
        asymmetry is deliberate.

        One name mapping to two ids is unresolvable. Encoding that name
        would have to pick, and either choice is wrong half the time.

        One id carrying two names is merely unusual, and it occurs in a
        shipped encoding: o200k_harmony gives 200018 both `<|endofprompt|>`
        and `<|reserved_200018|>`. Encoding either name yields 200018, which
        is unambiguous. Decoding 200018 has to choose, and the choice is the
        first registration, which is what the reference implementation does.
        Registries must therefore add their named tokens before any
        generated sweep, and o200k_harmony_specials does.

        This rule was stricter until the seventh encoding was implemented.
        It rejected a repeated id on the argument that either kind of
        duplicate is ambiguous. Half of that argument was wrong, and the
        half that was wrong is recorded here rather than quietly deleted.
        """
        for index in range(len(self.names)):
            if self.names[index] == name:
                raise Error(
                    String(
                        t"knap: special token '{name}' is already registered."
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


def gpt2_specials() raises -> SpecialTokens:
    """Build the special token registry for gpt2 and r50k_base.

    Returns:
        A registry holding the one special token both encodings define.

    Raises:
        Error: never in practice. The registry validates regardless.

    Two encodings share this because they share everything: gpt2 and
    r50k_base have byte identical merge ranks, which was checked rather than
    assumed. gpt2 is distributed as a pair of GPT-2 era files and r50k_base
    as a .tiktoken file, and the two decode to the same table.

    Merge ranks occupy 0 to 50255. The single special sits directly above
    them with no gap, which is unlike every later encoding.
    """
    var specials = SpecialTokens()
    specials.add(String("<|endoftext|>"), 50256)
    return specials^


def p50k_base_specials() raises -> SpecialTokens:
    """Build the special token registry for p50k_base.

    Returns:
        A registry holding the one special token p50k_base defines.

    Raises:
        Error: never in practice. The registry validates regardless.

    Merge ranks occupy 0 to 50279, and the special sits at 50256, which is
    inside that range rather than above it. p50k_base extends r50k_base by
    adding ranks after the point where r50k_base had stopped, and the
    special token stayed where it was.
    """
    var specials = SpecialTokens()
    specials.add(String("<|endoftext|>"), 50256)
    return specials^


def p50k_edit_specials() raises -> SpecialTokens:
    """Build the special token registry for p50k_edit.

    Returns:
        A registry holding the four special tokens p50k_edit defines.

    Raises:
        Error: never in practice. The registry validates regardless.

    The same vocabulary file as p50k_base with three fill in the middle
    markers added above it.
    """
    var specials = SpecialTokens()
    specials.add(String("<|endoftext|>"), 50256)
    specials.add(String("<|fim_prefix|>"), 50281)
    specials.add(String("<|fim_middle|>"), 50282)
    specials.add(String("<|fim_suffix|>"), 50283)
    return specials^


def o200k_harmony_specials() raises -> SpecialTokens:
    """Build the special token registry for o200k_harmony.

    Returns:
        A registry holding all 1091 names o200k_harmony defines.

    Raises:
        Error: never in practice. The registry validates regardless.

    The largest registry by a wide margin: ten named tokens and 1081
    reserved ones, over 1090 distinct ids.

    The counts do not add up, and that is not an error. Id 200018 carries
    two names, `<|endofprompt|>` and `<|reserved_200018|>`, so there are
    1091 names over 1090 ids. It is the only such id in any shipped
    encoding, and it is why SpecialTokens.add accepts a repeated id.

    **The order below is load bearing.** The named tokens are registered
    first and the reserved sweep second, so decoding 200018 yields
    `<|endofprompt|>`, which is what the reference implementation returns.
    Reversing the two would produce a tokenizer that encodes correctly and
    decodes one id wrong, which no corpus of natural language would ever
    surface.

    The seven ids skipped by the sweep are the named tokens inside its
    range that have no reserved name. 200018 is deliberately not among them.
    """
    var specials = SpecialTokens()

    specials.add(String("<|startoftext|>"), 199998)
    specials.add(String("<|endoftext|>"), 199999)
    specials.add(String("<|return|>"), 200002)
    specials.add(String("<|constrain|>"), 200003)
    specials.add(String("<|channel|>"), 200005)
    specials.add(String("<|start|>"), 200006)
    specials.add(String("<|end|>"), 200007)
    specials.add(String("<|message|>"), 200008)
    specials.add(String("<|call|>"), 200012)
    specials.add(String("<|endofprompt|>"), 200018)

    for token_id in range(200000, 201088):
        if (
            token_id == 200002
            or token_id == 200003
            or token_id == 200005
            or token_id == 200006
            or token_id == 200007
            or token_id == 200008
            or token_id == 200012
        ):
            continue
        specials.add(
            String("<|reserved_") + String(token_id) + String("|>"), token_id
        )

    return specials^


# =============================================================================
# End of file: src/knap/special.mojo
# =============================================================================
