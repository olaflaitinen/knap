# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bindings/python/knap_py/tokenizer.py
# Purpose     : Pythonic wrapper over the native extension module.
# Stage       : Python bindings. See bindings/python/README.md
# Depends on  : knap_ext, the extension built from bindings/python/knap_ext.mojo
# Invariants  : decode returns bytes. Turning them into text is the caller's
#               decision, because a token slice need not be valid UTF-8.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""The Python facing tokenizer.

Thin on purpose. Every decision that affects tokens lives in the Mojo side;
this converts between interop types and ordinary Python ones, and turns a
missing extension into a message that says what to run.

The one interface decision worth defending is that decode returns bytes
rather than str. Byte level BPE can decode to a partial UTF-8 sequence when a
caller decodes a slice of a longer token list, so returning str would force a
lossy choice here. decode_text is offered separately for callers who know
their token list is complete.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

BINDINGS_DIR = Path(__file__).resolve().parent.parent

ENCODINGS = (
    "cl100k_base",
    "o200k_base",
    "o200k_harmony",
    "gpt2",
    "r50k_base",
    "p50k_base",
    "p50k_edit",
)

# Seven encodings, four vocabulary files. o200k_harmony shares o200k_base's
# merge table and differs only in its special tokens; p50k_edit shares
# p50k_base's; and gpt2's merge ranks are byte identical to r50k_base's, so
# it loads from that file rather than from the GPT-2 era pair of files Knap
# does not read.
#
# This mapping is advice, not enforcement. The constructor takes whatever
# path it is given, because a caller with a vocabulary somewhere else has a
# reason for it.
VOCABULARY_FILE = {
    "cl100k_base": "cl100k_base.tiktoken",
    "o200k_base": "o200k_base.tiktoken",
    "o200k_harmony": "o200k_base.tiktoken",
    "gpt2": "r50k_base.tiktoken",
    "r50k_base": "r50k_base.tiktoken",
    "p50k_base": "p50k_base.tiktoken",
    "p50k_edit": "p50k_base.tiktoken",
}


class KnapNotBuiltError(ImportError):
    """Raised when the native extension has not been built.

    A distinct type rather than a bare ImportError, so a caller can tell the
    difference between "Knap is not installed" and "Knap is installed but
    needs building for this toolchain".
    """


def _load_extension():
    """Import the native extension, searching the usual build locations.

    Returns:
        The imported extension module.

    Raises:
        KnapNotBuiltError: when it cannot be found, naming the command that
            builds it.

    The search covers the ordinary import path first, so an installed
    package wins, and then the build directory beside this file, which is
    where bindings/python/build.py puts it during development.
    """
    try:
        import knap_ext

        return knap_ext
    except ImportError:
        pass

    candidate = BINDINGS_DIR / "build"
    if candidate.is_dir():
        sys.path.insert(0, str(candidate))
        try:
            import knap_ext

            return knap_ext
        except ImportError:
            pass

    raise KnapNotBuiltError(
        "knap_py: the native extension is not built. Run\n"
        "    python bindings/python/build.py\n"
        "The extension is built against one exact Mojo toolchain and must be "
        "rebuilt whenever that changes, because the Mojo ABI is not stable."
    )


class Tokenizer:
    """A loaded Knap tokenizer."""

    def __init__(self, vocabulary_path: str | os.PathLike, encoding: str):
        """Load a vocabulary.

        Args:
            vocabulary_path: Path to the .tiktoken vocabulary file.
            encoding: One of the seven names in ENCODINGS.

        Raises:
            KnapNotBuiltError: if the native extension is not built.
            ValueError: if the encoding name is not one Knap supports.
            Exception: if the vocabulary will not load. The Mojo side raises
                with a message naming the file and the reason.

        Loading builds the merge rank table, which costs roughly a hundred
        milliseconds and a hundred megabytes for cl100k_base. Load once and
        keep the object.
        """
        if encoding not in ENCODINGS:
            raise ValueError(
                f"knap_py: unknown encoding {encoding!r}. "
                f"Supported: {', '.join(ENCODINGS)}."
            )
        extension = _load_extension()
        self._encoding = encoding
        self._inner = extension.KnapTokenizer(str(vocabulary_path), encoding)

    @classmethod
    def cl100k_base(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the cl100k_base encoding.

        Args:
            vocabulary_path: Path to cl100k_base.tiktoken.

        Returns:
            The loaded tokenizer.
        """
        return cls(vocabulary_path, "cl100k_base")

    @classmethod
    def o200k_base(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the o200k_base encoding.

        Args:
            vocabulary_path: Path to o200k_base.tiktoken.

        Returns:
            The loaded tokenizer.
        """
        return cls(vocabulary_path, "o200k_base")

    @classmethod
    def o200k_harmony(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the o200k_harmony encoding.

        Args:
            vocabulary_path: Path to o200k_base.tiktoken, which is the file
                this encoding is stored in.

        Returns:
            A ready tokenizer.

        Ordinary encoding is identical to o200k_base. What differs is the
        special token registry: 1091 entries against two, which fill every
        gap o200k_base leaves in its id space and continue to 201087.
        """
        return cls(vocabulary_path, "o200k_harmony")

    @classmethod
    def gpt2(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the gpt2 encoding.

        Args:
            vocabulary_path: Path to r50k_base.tiktoken. The two encodings
                have byte identical merge ranks, and Knap does not read the
                GPT-2 era pair of files gpt2 is otherwise distributed as.

        Returns:
            A ready tokenizer.
        """
        return cls(vocabulary_path, "gpt2")

    @classmethod
    def r50k_base(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the r50k_base encoding.

        Args:
            vocabulary_path: Path to r50k_base.tiktoken.

        Returns:
            A ready tokenizer.
        """
        return cls(vocabulary_path, "r50k_base")

    @classmethod
    def p50k_base(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the p50k_base encoding.

        Args:
            vocabulary_path: Path to p50k_base.tiktoken.

        Returns:
            A ready tokenizer.

        The only shipped encoding whose merge ranks are not dense. Rank
        50256 holds no merge token because the special token sits there.
        """
        return cls(vocabulary_path, "p50k_base")

    @classmethod
    def p50k_edit(cls, vocabulary_path: str | os.PathLike) -> "Tokenizer":
        """Load the p50k_edit encoding.

        Args:
            vocabulary_path: Path to p50k_base.tiktoken, which is the file
                this encoding is stored in.

        Returns:
            A ready tokenizer.

        p50k_base with three fill in the middle markers stacked above it.
        """
        return cls(vocabulary_path, "p50k_edit")

    @property
    def encoding(self) -> str:
        """Return the encoding name this tokenizer was loaded with."""
        return self._encoding

    @property
    def n_vocab(self) -> int:
        """Return one past the highest assigned token id.

        This is the size of the id space, matching what tiktoken calls
        n_vocab. It is not always the number of decodable ids. cl100k_base
        leaves sixteen gaps and o200k_base nineteen, and decoding an id in
        one of them raises. The other five have no gaps at all.
        """
        return int(self._inner.n_vocab())

    def encode_ordinary(self, text: str) -> list[int]:
        """Encode text, treating special token literals as ordinary text.

        Args:
            text: The text to encode.

        Returns:
            The token ids.

        This never raises on content. A marker written out in the input is
        encoded as the characters that spell it.
        """
        return [int(value) for value in self._inner.encode_ordinary(text)]

    def encode(
        self, text: str, allowed_special: "list[str] | tuple[str, ...] | set[str] | None" = None
    ) -> list[int]:
        """Encode text, permitting only the listed special tokens.

        Args:
            text: The text to encode.
            allowed_special: Literal texts of the special tokens permitted in
                the input. Defaults to none permitted.

        Returns:
            The token ids.

        Raises:
            Exception: if a special token appears that was not permitted.

        The default is to permit nothing, which means any marker in the input
        is refused. That is deliberate: encoding an unexpected marker would
        let untrusted input inject a control token into a prompt.
        """
        permitted = sorted(allowed_special) if allowed_special else []
        return [int(value) for value in self._inner.encode(text, permitted)]

    def decode_bytes(self, token_ids) -> bytes:
        """Decode token ids to the exact bytes they represent.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            The decoded bytes, which may not be valid UTF-8.

        Raises:
            Exception: if any id is unassigned in this encoding.
        """
        return bytes(self._inner.decode_bytes(list(token_ids)))

    def decode(self, token_ids) -> str:
        """Decode token ids to text.

        Args:
            token_ids: The ids to decode, in order.

        Returns:
            The decoded text.

        Raises:
            Exception: if any id is unassigned in this encoding.
            UnicodeDecodeError: if the bytes are not valid UTF-8, which
                happens when a token list is a slice of a longer one.

        Use decode_bytes when the token list might be a fragment. This
        method deliberately does not replace malformed sequences, because
        silently substituting characters is how a round trip stops being a
        round trip.
        """
        return self.decode_bytes(token_ids).decode("utf-8")

    def __repr__(self) -> str:
        """Return a short description naming the encoding."""
        return f"Tokenizer({self._encoding!r})"

# =============================================================================
# End of file: bindings/python/knap_py/tokenizer.py
# =============================================================================
