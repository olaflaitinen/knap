# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_reference.py
# Purpose     : Gate on the reference implementation. Catches a vocabulary
#               or a reference version that moved under the documents.
# Stage       : Repository standard enforcement, see docs/CORRECTNESS.md
# Depends on  : tests/fixtures/vocabs/provenance.json. Standard library only.
# Invariants  : Every fetched vocabulary is checked against the digest that
#               was recorded when it was fetched. A missing file is skipped
#               and said to be skipped; a changed file is a failure.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Gate on the thing every number in this repository is measured against.

Every parity figure here is a comparison against a reference implementation
and a set of vocabulary files. Both can move. A vocabulary can be refetched
from a URL whose contents changed, and the reference can be upgraded by a
dependency resolver without anybody deciding to upgrade it. Either would
invalidate the golden fixtures, the corpus references and the published
counts, and neither would fail a test: the fixtures would simply be
regenerated from the new reference and everything would agree with itself.

That is the failure this exists to catch. It checks three things:

  * every fetched vocabulary matches the digest recorded when it was
    fetched, byte for byte
  * the token counts recorded alongside those digests still hold
  * the installed reference version matches the one the documents quote

The digests are the important part. A vocabulary that changed is not a
smaller problem than a code change, it is a larger one, because it changes
the output of a library whose entire claim is that its output does not
change.

    python scripts/check_reference.py
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VOCAB_DIR = REPO_ROOT / "tests" / "fixtures" / "vocabs"
PROVENANCE = VOCAB_DIR / "provenance.json"

# Documents that quote the reference version, and the pattern that finds it.
# Each must agree with the version recorded in provenance.json.
VERSION_QUOTES = {
    "THIRD_PARTY_NOTICES.md": re.compile(r"`tiktoken` \|[^|]*\|[^|]*\| ([0-9][0-9.]*) \|"),
    "docs/ARCHITECTURE.md": re.compile(r"tiktoken ([0-9][0-9.]*),"),
}


def digest(path: Path) -> str:
    """Compute the SHA-256 of a file.

    Args:
        path: The file to read.

    Returns:
        The digest, as lowercase hexadecimal.
    """
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(block)
    return hasher.hexdigest()


def count_tokens(path: Path) -> int:
    """Count the ranked entries in a .tiktoken file.

    Args:
        path: The vocabulary file.

    Returns:
        How many non empty lines it holds, which is one per merge token.
    """
    total = 0
    with path.open("rb") as handle:
        for line in handle:
            if line.strip():
                total += 1
    return total


def check_vocabularies(recorded: dict) -> tuple[list[str], int]:
    """Check every fetched vocabulary against its recorded digest.

    Args:
        recorded: The vocabularies section of provenance.json.

    Returns:
        The problems found, and how many files were actually checked.

    A vocabulary that is not present is skipped rather than failed, because
    they are fetched rather than committed and a fresh checkout has none.
    The count of what was checked is returned so that the caller can say
    plainly how much of the gate ran.
    """
    problems: list[str] = []
    checked = 0

    for name in sorted(recorded):
        expected = recorded[name]
        path = VOCAB_DIR / f"{name}.tiktoken"
        if not path.is_file():
            continue

        checked += 1
        size = path.stat().st_size
        if size != expected["bytes"]:
            problems.append(
                f"{name}.tiktoken is {size} bytes, provenance records "
                f"{expected['bytes']}"
            )
            continue

        actual = digest(path)
        if actual != expected["sha256"]:
            problems.append(
                f"{name}.tiktoken has digest {actual[:16]}, provenance "
                f"records {expected['sha256'][:16]}. The vocabulary this "
                "repository was verified against is not the one on disk."
            )
            continue

        tokens = count_tokens(path)
        if tokens != expected["tokens"]:
            problems.append(
                f"{name}.tiktoken holds {tokens} entries, provenance "
                f"records {expected['tokens']}"
            )

    return problems, checked


def check_documents(version: str) -> list[str]:
    """Check that the documents quote the recorded reference version.

    Args:
        version: The version recorded in provenance.json.

    Returns:
        The problems found.

    A document quoting a version the fixtures were not generated from is a
    figure attributed to the wrong thing, which is the quietest kind of
    wrong a document can be.
    """
    problems: list[str] = []
    for relative, pattern in VERSION_QUOTES.items():
        path = REPO_ROOT / relative
        if not path.is_file():
            problems.append(f"{relative} is missing")
            continue
        found = set(pattern.findall(path.read_text(encoding="utf-8")))
        if not found:
            problems.append(
                f"{relative} does not quote a reference version where one "
                "was expected, so it cannot be checked"
            )
        elif found != {version}:
            quoted = ", ".join(sorted(found))
            problems.append(
                f"{relative} quotes reference version {quoted} and the "
                f"vocabularies were fetched with {version}"
            )
    return problems


def check_installed(version: str) -> list[str]:
    """Check the installed reference against the recorded version.

    Args:
        version: The version recorded in provenance.json.

    Returns:
        The problems found. An absent reference is not a problem, because
        the standards job runs without the development environment.
    """
    try:
        import tiktoken
    except ImportError:
        return []

    installed = getattr(tiktoken, "__version__", None)
    if installed is None:
        return ["the installed reference does not report a version"]
    if installed != version:
        return [
            f"the installed reference is {installed} and the vocabularies "
            f"were fetched with {version}. Regenerate the fixtures or pin "
            "the reference back."
        ]
    return []


def main() -> int:
    """Check the reference and the vocabularies, and report."""
    if not PROVENANCE.is_file():
        raise SystemExit(
            f"check_reference: {PROVENANCE.relative_to(REPO_ROOT)} is "
            "missing. Run 'python scripts/fetch_vocabs.py' first."
        )

    try:
        recorded = json.loads(PROVENANCE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"check_reference: cannot read the provenance: {exc}")

    version = recorded.get("tiktoken_version")
    if not isinstance(version, str):
        raise SystemExit(
            "check_reference: the provenance records no reference version"
        )

    problems, checked = check_vocabularies(recorded.get("vocabularies", {}))
    problems += check_documents(version)
    problems += check_installed(version)

    if problems:
        print("check_reference: the reference has moved under the documents")
        for problem in problems:
            print(f"  {problem}")
        return 1

    total = len(recorded.get("vocabularies", {}))
    if checked == 0:
        print(
            f"check_reference: reference {version}, documents agree, and no "
            f"vocabulary is present to check. {total} are recorded; fetch "
            "them with 'python scripts/fetch_vocabs.py'."
        )
        return 0

    print(
        f"check_reference: reference {version}, {checked} of {total} "
        "vocabularies present and byte identical to what was recorded."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/check_reference.py
# =============================================================================
