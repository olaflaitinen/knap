# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_toolchain_doc.py
# Purpose     : Verifies that every citation in the toolchain findings
#               document still points at a file this repository has.
# Stage       : Repository standard enforcement, see docs/STYLE.md
# Depends on  : git, for the tracked file list. Python standard library only.
# Invariants  : Every path in the "Pinned by" column of docs/TOOLCHAIN.md
#               resolves, and the compiler version the document states agrees
#               with the version pinned in pyproject.toml.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Gate for the toolchain findings document.

docs/TOOLCHAIN.md is a list of things about Mojo 1.0.0 that are not what a
reader would assume, and most of its rows end by naming the file in this
repository that carries the correct spelling in context. Those citations are
the part of the document that makes it checkable rather than anecdotal, and
they are also the part that rots first: a file gets renamed, the row keeps
pointing at it, and the document quietly becomes a list of claims with no
evidence behind them.

This gate resolves every one of them. It also checks the compiler version
the document states against the version pinned in pyproject.toml, because a
document that says it was verified against a compiler nobody uses any more
is worse than one that says nothing.

Three citation forms are accepted and are not treated as paths:

    Nothing, a compile error   the wrong form does not compile, so nothing
                               inside a running program can assert it
    Every ...                  a repository wide convention rather than one
                               file, for instance the "std." import prefix
    docs/...                   another document, resolved as a path like
                               any other

    python scripts/check_toolchain_doc.py

Exit status is 0 when every citation resolves and 1 otherwise.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

DOCUMENT = REPO_ROOT / "docs" / "TOOLCHAIN.md"
PROJECT_FILE = REPO_ROOT / "pyproject.toml"

# The column whose cells this gate resolves. A table without it is prose,
# such as the environment table or the upstream roadmap table, and is
# skipped.
PINNED_COLUMN = "Pinned by"

# Cells that name a convention rather than a file. Each is allowed because
# there is genuinely nothing to point at, and each is spelled out here so
# that a new unresolvable citation has to be added deliberately.
CONVENTION_PREFIXES = ("Nothing,", "Every ")

CODE_SPAN = re.compile(r"`([^`]+)`")
TABLE_ROW = re.compile(r"^\|(.+)\|\s*$")

# The compiler version, as the document's environment table states it and as
# pyproject.toml pins it.
DOCUMENT_VERSION = re.compile(r"^\|\s*Mojo\s*\|\s*([0-9][^,|]*?)\s*,")
PROJECT_VERSION = re.compile(r'"mojo==([0-9][^"]*)"')


def tracked_paths() -> set[str]:
    """Return every repository relative path git knows about.

    Returns:
        Tracked and untracked but unignored paths.

    Raises:
        SystemExit: if git cannot be run, because a gate that silently
            passes when it cannot check anything is worse than no gate.
    """
    try:
        completed = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(
            f"check_toolchain_doc: cannot list files with git: {exc}"
        ) from exc
    return {line for line in completed.stdout.splitlines() if line}


def split_row(line: str) -> list[str]:
    """Split one Markdown table row into its cells.

    Args:
        line: The raw line, including the leading and trailing pipe.

    Returns:
        The cells, stripped.
    """
    match = TABLE_ROW.match(line)
    if match is None:
        return []
    return [cell.strip() for cell in match.group(1).split("|")]


def citations(lines: list[str]) -> list[tuple[int, str]]:
    """Collect every cell in a "Pinned by" column.

    Args:
        lines: The document, split into lines.

    Returns:
        One entry per data row, giving the line number and the cell.

    Tables are recognised by their header row, so a table without the column
    contributes nothing and a table with it contributes every row below its
    separator until the table ends.
    """
    found: list[tuple[int, str]] = []
    column: int | None = None

    for number, line in enumerate(lines, start=1):
        cells = split_row(line)
        if not cells:
            column = None
            continue

        if PINNED_COLUMN in cells:
            column = cells.index(PINNED_COLUMN)
            continue

        if column is None:
            continue

        # The separator row under a header, which carries no data.
        if all(set(cell) <= set("-: ") for cell in cells if cell):
            continue

        if column < len(cells):
            found.append((number, cells[column]))

    return found


def unresolved(cell: str, tracked: set[str]) -> list[str]:
    """Return the paths in one citation cell that do not resolve.

    Args:
        cell: The cell's text.
        tracked: Every path git knows about.

    Returns:
        The unresolvable paths, empty when the cell is fine.
    """
    if cell.startswith(CONVENTION_PREFIXES):
        return []
    spans = CODE_SPAN.findall(cell)
    if not spans:
        return [cell or "(empty)"]
    return [span for span in spans if span not in tracked]


def version_agreement() -> str | None:
    """Check the document's compiler version against the project's pin.

    Returns:
        A description of the disagreement, or None when the two agree.
    """
    document = DOCUMENT.read_text(encoding="utf-8")
    stated = None
    for line in document.splitlines():
        match = DOCUMENT_VERSION.match(line)
        if match:
            stated = match.group(1)
            break
    if stated is None:
        return "the environment table does not state a Mojo version"

    project = PROJECT_FILE.read_text(encoding="utf-8")
    match = PROJECT_VERSION.search(project)
    if match is None:
        return "pyproject.toml does not pin a mojo version"
    pinned = match.group(1)

    if stated != pinned:
        return (
            f"the document was verified against Mojo {stated} and "
            f"pyproject.toml pins {pinned}"
        )
    return None


def main() -> int:
    """Resolve every citation and report the ones that do not.

    Returns:
        0 when the document is consistent, 1 otherwise.
    """
    if not DOCUMENT.exists():
        print(
            "check_toolchain_doc: docs/TOOLCHAIN.md is missing.",
            file=sys.stderr,
        )
        return 1

    tracked = tracked_paths()
    lines = DOCUMENT.read_text(encoding="utf-8").splitlines()
    cells = citations(lines)

    problems: list[str] = []
    for number, cell in cells:
        for path in unresolved(cell, tracked):
            problems.append(
                f"docs/TOOLCHAIN.md:{number}: cites {path}, which this "
                "repository does not have"
            )

    disagreement = version_agreement()
    if disagreement is not None:
        problems.append(f"docs/TOOLCHAIN.md: {disagreement}")

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(
            f"check_toolchain_doc: {len(problems)} problem(s).",
            file=sys.stderr,
        )
        return 1

    print(
        f"check_toolchain_doc: {len(cells)} citations resolve, and the "
        "compiler version agrees with pyproject.toml."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# =============================================================================
# End of file: scripts/check_toolchain_doc.py
# =============================================================================
