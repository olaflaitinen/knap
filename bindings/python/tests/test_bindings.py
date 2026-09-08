# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bindings/python/tests/test_bindings.py
# Purpose     : Checks the Python bindings against tiktoken, end to end.
# Stage       : Milestone M6 Track B, Python consumers. See docs/ROADMAP.md
# Depends on  : knap_py, the built extension, and tiktoken as the reference.
# Invariants  : The bindings are compared against the same reference the Mojo
#               tests use. A binding that loses parity in translation would
#               otherwise go unnoticed.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the Knap Python bindings.

These check the whole path: Python calls into the extension, the extension
calls into Knap, and the result comes back as ordinary Python values. Parity
is asserted against tiktoken here too, not assumed from the Mojo tests,
because a binding can lose or reorder values in translation and the Mojo
tests would never see it.

Run them after building the extension:

    python bindings/python/build.py
    python bindings/python/tests/test_bindings.py
"""

from __future__ import annotations

import sys
from pathlib import Path

BINDINGS_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = BINDINGS_DIR.parent.parent
sys.path.insert(0, str(BINDINGS_DIR))

VOCABULARIES = {
    "cl100k_base": REPO_ROOT
    / "tests"
    / "fixtures"
    / "vocabs"
    / "cl100k_base.tiktoken",
    "o200k_base": REPO_ROOT
    / "tests"
    / "fixtures"
    / "vocabs"
    / "o200k_base.tiktoken",
}

CASES = [
    "",
    "hello world",
    "Knap tokenizes 1234 bytes.",
    "don't stop believing",
    "  leading and trailing   ",
    "caf\u00e9 na\u00efve",
    "\u4e2d\u6587\u6d4b\u8bd5",
    "\U0001f600 emoji \U0001f680",
    "path/to/file.txt",
    "1234567890",
    "a\r\nb\n\nc",
]

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    """Record a failure without stopping the run.

    Args:
        condition: What must hold.
        message: What to report when it does not.

    Collected rather than raised, so one run reports every problem instead
    of only the first.
    """
    if not condition:
        failures.append(message)


def main() -> int:
    """Run every binding test and report what failed."""
    try:
        import tiktoken
    except ImportError:
        raise SystemExit(
            "test_bindings: tiktoken is required. Run 'uv sync --group dev'."
        )

    try:
        from knap_py import KnapNotBuiltError, Tokenizer
    except ImportError as exc:
        raise SystemExit(f"test_bindings: cannot import knap_py: {exc}")

    for name, path in VOCABULARIES.items():
        if not path.exists():
            raise SystemExit(
                f"test_bindings: {path} is missing. Run "
                "'python scripts/fetch_vocabs.py' first."
            )

    for name, path in VOCABULARIES.items():
        try:
            knap = Tokenizer(path, name)
        except KnapNotBuiltError as exc:
            raise SystemExit(str(exc))

        reference = tiktoken.get_encoding(name)

        check(
            knap.encoding == name,
            f"{name}: encoding property is {knap.encoding!r}",
        )
        check(
            knap.n_vocab == reference.n_vocab,
            f"{name}: n_vocab is {knap.n_vocab}, reference says "
            f"{reference.n_vocab}",
        )

        for text in CASES:
            mine = knap.encode_ordinary(text)
            theirs = reference.encode_ordinary(text)
            check(
                mine == theirs,
                f"{name}: encode_ordinary({text!r}) gave {mine}, reference "
                f"gave {theirs}",
            )

            if mine:
                check(
                    knap.decode(mine) == text,
                    f"{name}: round trip failed for {text!r}",
                )
                check(
                    knap.decode_bytes(mine) == text.encode("utf-8"),
                    f"{name}: decode_bytes differed for {text!r}",
                )

        # Special tokens. The default refuses, which is the security
        # relevant behaviour and the one worth testing explicitly.
        marker = "<|endoftext|>"
        with_marker = f"before {marker} after"

        allowed = knap.encode(with_marker, [marker])
        expected = reference.encode(with_marker, allowed_special={marker})
        check(
            allowed == expected,
            f"{name}: allowed special token gave {allowed}, reference gave "
            f"{expected}",
        )

        refused = False
        try:
            knap.encode(with_marker)
        except Exception:
            refused = True
        check(refused, f"{name}: a disallowed special token was not refused")

        as_text = knap.encode_ordinary(with_marker)
        check(
            as_text == reference.encode_ordinary(with_marker),
            f"{name}: encode_ordinary mishandled a marker",
        )

        print(f"  {name}: checked {len(CASES)} inputs and the special paths")

    if failures:
        print()
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"test_bindings: {len(failures)} failures", file=sys.stderr)
        return 1

    print("test_bindings: all binding tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: bindings/python/tests/test_bindings.py
# =============================================================================
