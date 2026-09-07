# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_spdx.py
# Purpose     : Verifies that every tracked source file declares the project
#               SPDX licence identifier near the top of the file.
# Stage       : Repository standard enforcement, see docs/STYLE.md
# Depends on  : git, for the tracked file list. Python standard library only.
# Invariants  : The identifier must appear within the first HEADER_LINES lines,
#               so that it is visible without scrolling and cannot hide in a
#               footer that a truncated copy would lose.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""SPDX licence identifier gate for the Knap repository.

Knap is distributed under the European Union Public Licence 1.2, which is a
reciprocal licence. Section 2.2 of docs/STYLE.md therefore requires every
source file, script, and Markdown document to carry the SPDX identifier, so
that a file separated from the repository still states its terms.

This check is deliberately independent of check_file_banners.py. The banner
check knows about Mojo and Python only, while licence obligations attach to
every text file the project ships.

    python scripts/check_spdx.py

Exit status is 0 when clean and 1 when any file is missing the identifier.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# The exact identifier every file must carry. The comment syntax around it
# differs by file type, so only the identifier itself is matched.
SPDX_IDENTIFIER = "SPDX-License-Identifier: EUPL-1.2"

# File types that carry the identifier. Every one of these supports comments.
CHECKED_EXTENSIONS = (
    ".mojo",
    ".py",
    ".md",
    ".toml",
    ".yml",
    ".yaml",
    ".sh",
    ".cff",
    ".h",
)

# How far into a file the identifier may appear. Generated file banners are
# the longest in the project, so this is set above their height.
HEADER_LINES = 45

# LICENSE is the licence itself and does not carry a pointer to itself.
# Fixtures are opaque test data and carry no comments at all. These are the
# same first two exemptions that lint_style.py applies, for the same reasons.
EXEMPT_PATHS = frozenset({"LICENSE"})
EXEMPT_PREFIXES = ("tests/fixtures/", "tests/golden/")


def tracked_files() -> list[str]:
    """Return every repository relative path that git considers in scope.

    A missing git is treated as a hard error rather than an empty result,
    because an empty result would report success while checking nothing.
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
            f"check_spdx: cannot list files with git: {exc}"
        ) from exc
    return [line for line in completed.stdout.splitlines() if line]


def is_exempt(relative_path: str) -> bool:
    """Report whether a path is outside the SPDX requirement."""
    if relative_path in EXEMPT_PATHS:
        return True
    # Fixture and golden *data* is exempt. Documentation stored beside it is
    # not, so a README in those trees still declares its licence.
    if relative_path.endswith(".md"):
        return False
    return relative_path.startswith(EXEMPT_PREFIXES)


def has_identifier(relative_path: str) -> bool:
    """Report whether the file declares the identifier in its header region.

    Reads only the header region rather than the whole file, which keeps the
    check fast on the large generated tables in src/knap/pretokenize.

    Failure mode: a file that is not valid UTF-8 cannot be checked here.
    lint_style.py owns that rule and reports it, so this returns True to
    avoid a duplicate and less specific complaint.
    """
    absolute = REPO_ROOT / relative_path
    try:
        with absolute.open("r", encoding="utf-8") as handle:
            for index, line in enumerate(handle):
                if index >= HEADER_LINES:
                    return False
                if SPDX_IDENTIFIER in line:
                    return True
    except (OSError, UnicodeDecodeError):
        return True
    return False


def main() -> int:
    """Check every in-scope file and report those missing the identifier."""
    parser = argparse.ArgumentParser(
        description="SPDX licence identifier gate for the Knap repository."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional explicit paths. Defaults to every git tracked file.",
    )
    arguments = parser.parse_args()

    candidates = arguments.paths or tracked_files()
    targets = [
        path
        for path in candidates
        if path.endswith(CHECKED_EXTENSIONS) and not is_exempt(path)
    ]

    missing = [path for path in targets if not has_identifier(path)]

    if not missing:
        print(
            f"check_spdx: {len(targets)} files checked, all declare "
            f"{SPDX_IDENTIFIER}."
        )
        return 0

    for path in missing:
        print(
            f"{path}:1: missing '{SPDX_IDENTIFIER}' within the first "
            f"{HEADER_LINES} lines"
        )
    sys.stdout.flush()
    print(
        f"check_spdx: {len(missing)} files missing the SPDX identifier.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/check_spdx.py
# =============================================================================
