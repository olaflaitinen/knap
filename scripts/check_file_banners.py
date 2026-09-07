# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_file_banners.py
# Purpose     : Verifies the source file banner and closing marker required of
#               every .mojo and .py file in the repository.
# Stage       : Repository standard enforcement, see docs/STYLE.md
# Depends on  : git, for the tracked file list. Python standard library only.
# Invariants  : The File field must equal the file's own repository relative
#               path, so a copied banner cannot silently misname its file.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Source banner gate for the Knap repository.

Mojo is a new language and most readers of this repository will not know it,
so section 2.3 of docs/STYLE.md sets a generous documentation budget and a
fixed banner. A banner that is merely copied between files is worse than none,
because it misdescribes the file it heads. This script therefore checks that
the banner is present, that every field carries a value, and specifically that
the File field matches the path the file actually sits at.

Run with no arguments to check every .mojo and .py file git considers in
scope:

    python scripts/check_file_banners.py

Exit status is 0 when clean and 1 when any file fails.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Both Mojo and Python use "#" for comments, so one banner form serves both.
BANNER_EXTENSIONS = (".mojo", ".py")

# The horizontal rules are 79 characters wide so that the banner matches the
# 80 column default of "mojo format". The check allows any long run rather
# than an exact count, so that reflowing a rule by one character is not a
# build failure, while a visibly wrong rule still is.
RULE_PATTERN = re.compile(r"^# ={40,}$")
THIN_RULE_PATTERN = re.compile(r"^# -{40,}$")

# A banner field line looks like "# Name        : value". Continuation lines
# are indented and carry no colon, which is how the Affiliation field wraps
# onto a second line.
FIELD_PATTERN = re.compile(r"^# ([A-Za-z][A-Za-z ]*?)\s*:\s*(.*)$")

# Every banner carries these, in this order. Order is checked because a
# banner read out of order is harder to scan, which defeats its purpose.
REQUIRED_FIELDS = (
    "Project",
    "File",
    "Purpose",
    "Stage",
    "Depends on",
    "Invariants",
    "Author",
    "ORCID",
    "Affiliation",
)

# Generated files carry three extra fields plus an overwrite warning, so that
# nobody edits them by hand and loses the edit at the next generation run.
# See section 2.3 of docs/STYLE.md.
GENERATED_FIELDS = ("Generator", "Upstream", "Generated")
GENERATED_WARNING = "overwritten"

# The set of files that are generated and committed. Keeping this list here,
# rather than sniffing for a marker, means a generated file cannot quietly
# drop its provenance fields by deleting one line.
GENERATED_PATHS = frozenset(
    {
        "src/knap/pretokenize/pattern.mojo",
        "src/knap/pretokenize/unicode_tables.mojo",
    }
)

SPDX_LINE = "# SPDX-License-Identifier: EUPL-1.2"
COPYRIGHT_PREFIX = "# Copyright "

# How far into the file the banner may extend. A banner longer than this is
# not a banner.
MAX_BANNER_LINES = 40


@dataclass(frozen=True)
class Problem:
    """One banner defect in one file.

    Attributes:
        path: Repository relative path of the offending file.
        line: One based line number, or 0 when the defect is whole-file.
        message: What is wrong and what the file should carry instead.
    """

    path: str
    line: int
    message: str

    def render(self) -> str:
        """Format the problem as a single editor-navigable line."""
        return f"{self.path}:{self.line}: {self.message}"


def tracked_files() -> list[str]:
    """Return every repository relative path that git considers in scope.

    Identical in intent to the helper in lint_style.py: cover committed,
    staged, and new-but-not-ignored files, and reuse .gitignore rather than
    restating it. A missing git is a hard error, never a silent pass.
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
            f"check_file_banners: cannot list files with git: {exc}"
        ) from exc
    return [line for line in completed.stdout.splitlines() if line]


def parse_banner(lines: list[str]) -> tuple[list[tuple[str, str, int]], int]:
    """Extract banner fields and report where the banner ends.

    Returns a list of (field name, value, line number) triples together with
    the index of the line holding the banner's closing rule. The parse stops
    at the first closing rule that follows at least one field, which is what
    distinguishes the banner's own internal thin rules from its end.

    Failure mode: a file whose first line is not a rule yields an empty field
    list and an end index of -1, which the caller reports as a missing banner.
    """
    if not lines or not RULE_PATTERN.match(lines[0]):
        return [], -1

    fields: list[tuple[str, str, int]] = []
    limit = min(len(lines), MAX_BANNER_LINES)
    for index in range(1, limit):
        line = lines[index]
        if RULE_PATTERN.match(line):
            return fields, index
        if THIN_RULE_PATTERN.match(line):
            continue
        match = FIELD_PATTERN.match(line)
        if match:
            fields.append((match.group(1).strip(), match.group(2).strip(), index + 1))
    return fields, -1


def check_banner_fields(
    relative_path: str, fields: list[tuple[str, str, int]]
) -> list[Problem]:
    """Check that the required fields are present, ordered, and non-empty.

    The File field gets special treatment: it must equal the file's own path.
    That single check is what stops a banner copied from a neighbouring module
    from silently claiming to be that other module.
    """
    problems: list[Problem] = []
    names = [name for name, _, _ in fields]
    values = {name: (value, line) for name, value, line in fields}

    expected = list(REQUIRED_FIELDS)
    if relative_path in GENERATED_PATHS:
        expected.extend(GENERATED_FIELDS)

    for field in expected:
        if field not in values:
            problems.append(
                Problem(
                    relative_path,
                    1,
                    f"banner is missing the required field '{field}'",
                )
            )
            continue
        value, line_number = values[field]
        if not value:
            problems.append(
                Problem(
                    relative_path,
                    line_number,
                    f"banner field '{field}' is present but empty",
                )
            )

    # Order check, applied only to the fields that are actually present so
    # that a missing field is reported once rather than twice.
    present_required = [name for name in names if name in set(expected)]
    ordered_required = [name for name in expected if name in set(present_required)]
    if present_required != ordered_required:
        problems.append(
            Problem(
                relative_path,
                1,
                "banner fields are out of order; expected "
                + ", ".join(ordered_required),
            )
        )

    if "File" in values:
        declared, line_number = values["File"]
        if declared != relative_path:
            problems.append(
                Problem(
                    relative_path,
                    line_number,
                    f"banner File field says '{declared}' but the file is at "
                    f"'{relative_path}'",
                )
            )

    if relative_path in GENERATED_PATHS:
        joined = " ".join(value for _, value, _ in fields).lower()
        if GENERATED_WARNING not in joined:
            problems.append(
                Problem(
                    relative_path,
                    1,
                    "generated file banner must state that manual edits will "
                    "be overwritten",
                )
            )

    return problems


def check_closing_marker(
    relative_path: str, lines: list[str]
) -> list[Problem]:
    """Check the three line closing marker that makes truncation visible.

    A file that is cut short by a failed write or a bad merge looks plausible
    without this. The marker names the file again so that a truncated tail is
    obvious even out of context.
    """
    trimmed = [line for line in lines if line.strip()]
    if len(trimmed) < 3:
        return [
            Problem(relative_path, 0, "file is too short to carry a banner")
        ]

    tail = trimmed[-3:]
    expected_middle = f"# End of file: {relative_path}"
    problems: list[Problem] = []

    if not RULE_PATTERN.match(tail[0]) or not RULE_PATTERN.match(tail[2]):
        problems.append(
            Problem(
                relative_path,
                len(lines),
                "closing marker must be a rule, an End of file line, and a "
                "rule",
            )
        )
    if tail[1].strip() != expected_middle:
        problems.append(
            Problem(
                relative_path,
                len(lines),
                f"closing marker must read '{expected_middle}', found "
                f"'{tail[1].strip()}'",
            )
        )
    return problems


def check_file(relative_path: str) -> list[Problem]:
    """Check one source file's banner, SPDX line, and closing marker."""
    absolute = REPO_ROOT / relative_path
    if not absolute.is_file():
        return []

    try:
        text = absolute.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        # lint_style.py owns the encoding rule and will report this file.
        return []

    lines = text.splitlines()
    problems: list[Problem] = []

    fields, end_index = parse_banner(lines)
    if end_index == -1:
        return [
            Problem(
                relative_path,
                1,
                "file does not open with the required banner; see "
                "docs/STYLE.md section 2.3",
            )
        ]

    problems.extend(check_banner_fields(relative_path, fields))

    banner = lines[: end_index + 1]
    if SPDX_LINE not in banner:
        problems.append(
            Problem(relative_path, 1, f"banner must contain '{SPDX_LINE}'")
        )
    if not any(line.startswith(COPYRIGHT_PREFIX) for line in banner):
        problems.append(
            Problem(relative_path, 1, "banner must contain a Copyright line")
        )

    problems.extend(check_closing_marker(relative_path, lines))
    return problems


def main() -> int:
    """Check every in-scope source file and report each defect."""
    parser = argparse.ArgumentParser(
        description="Source banner gate for the Knap repository."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional explicit paths. Defaults to every git tracked file.",
    )
    arguments = parser.parse_args()

    candidates = arguments.paths or tracked_files()
    targets = [
        path for path in candidates if path.endswith(BANNER_EXTENSIONS)
    ]

    problems: list[Problem] = []
    for relative_path in targets:
        problems.extend(check_file(relative_path))

    if not problems:
        print(
            f"check_file_banners: {len(targets)} source files checked, "
            "all banners valid."
        )
        return 0

    for problem in problems:
        print(problem.render())
    sys.stdout.flush()
    print(
        f"check_file_banners: {len(problems)} banner problems.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/check_file_banners.py
# =============================================================================
