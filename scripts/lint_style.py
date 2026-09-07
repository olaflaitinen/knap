# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/lint_style.py
# Purpose     : Character level style gate. Rejects em-dashes, emoji,
#               non-ASCII bytes, and exclamation marks in documentation prose.
# Stage       : Repository standard enforcement, see docs/STYLE.md
# Depends on  : git, for the tracked file list. Python standard library only.
# Invariants  : Exactly three exemptions exist (LICENSE, tests/fixtures, LaTeX
#               math spans). Adding a fourth changes docs/STYLE.md as well.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Character level style gate for the Knap repository.

Knap's prose rules are mechanical, so they are enforced mechanically rather
than by review. This script is the enforcing half of section 2.1 of
docs/STYLE.md. When this script and that document disagree, docs/STYLE.md is
authoritative and this script has the bug.

Run with no arguments to check every file git considers in scope:

    python scripts/lint_style.py

Exit status is 0 when clean and 1 when any violation is found.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# The em-dash is written as an escape rather than as itself, because this file
# is subject to the very rule it enforces. U+2014 is EM DASH.
EM_DASH = chr(0x2014)

# -----------------------------------------------------------------------------
# The three exemptions
#
# These are the only three exemptions permitted by docs/STYLE.md section 2.1.
# Each is named and explained here so a future reader sees why it exists
# before deciding to remove it. Removing the LICENSE exemption in particular
# would mangle a legal instrument.
# -----------------------------------------------------------------------------

# Exemption 1. LICENSE holds the official EUPL 1.2 English text, verbatim.
# That text is a legal instrument published by the European Union and it
# legitimately contains typographic characters, including dashes and curly
# quotation marks. It must never be repaired to satisfy an ASCII rule, so the
# path is skipped in full.
EXEMPT_LICENCE = "LICENSE"

# Exemption 2. Test fixture data is input to the tokenizer under test. A byte
# level BPE tokenizer must handle arbitrary bytes, so fixtures deliberately
# contain multilingual text, emoji, and invalid UTF-8. Constraining them to
# ASCII would defeat their entire purpose.
EXEMPT_FIXTURE_PREFIX = "tests/fixtures/"

# Exemption 3. LaTeX inside math spans. This one is applied per span rather
# than per file, by strip_math_spans below, for the rare command that needs a
# non-ASCII character. Ordinary LaTeX is ASCII and is unaffected.

# -----------------------------------------------------------------------------
# Emoji ranges
#
# Unicode has no single "is emoji" property that is both simple and accurate,
# so this is a deliberately broad list of the blocks emoji are drawn from. It
# exists only to produce a precise diagnostic, saying "emoji" instead of
# "non-ASCII byte", since the ASCII rule already rejects every one of these.
# Being slightly over-broad is harmless: anything caught here is banned anyway.
# -----------------------------------------------------------------------------
EMOJI_RANGES = (
    (0x1F300, 0x1F5FF),  # Miscellaneous symbols and pictographs
    (0x1F600, 0x1F64F),  # Emoticons
    (0x1F680, 0x1F6FF),  # Transport and map symbols
    (0x1F700, 0x1F77F),  # Alchemical symbols
    (0x1F900, 0x1F9FF),  # Supplemental symbols and pictographs
    (0x1FA70, 0x1FAFF),  # Symbols and pictographs extended-A
    (0x2600, 0x26FF),    # Miscellaneous symbols
    (0x2700, 0x27BF),    # Dingbats
    (0x1F1E6, 0x1F1FF),  # Regional indicators, used for flag sequences
    (0xFE0F, 0xFE0F),    # Variation selector-16, the emoji presentation mark
    (0x200D, 0x200D),    # Zero width joiner, used to build emoji sequences
)

# Markdown fence markers. Both are legal in CommonMark and both appear in the
# wild, so both are tracked.
FENCE_MARKERS = ("```", "~~~")


@dataclass(frozen=True)
class Finding:
    """One style violation, located precisely enough to fix without searching.

    Attributes:
        path: Repository relative path of the offending file.
        line: One based line number.
        column: One based column number, counted in characters.
        rule: Short rule identifier, used to group the summary output.
        message: Human readable explanation, including the suggested fix.
    """

    path: str
    line: int
    column: int
    rule: str
    message: str

    def render(self) -> str:
        """Format the finding as a single editor-navigable line."""
        return (
            f"{self.path}:{self.line}:{self.column}: "
            f"[{self.rule}] {self.message}"
        )


# -----------------------------------------------------------------------------
# File discovery
# -----------------------------------------------------------------------------


def tracked_files() -> list[str]:
    """Return every repository relative path that git considers in scope.

    Why this form: the gate must cover files that are committed, staged, or
    newly written but not yet added, while never covering build outputs or
    fetched vocabularies. The cached plus others minus ignored set is exactly
    that, and it reuses .gitignore instead of duplicating those rules here.

    Failure modes: if git is missing, or this is not a repository, an empty
    list would silently pass the gate. That case is turned into a hard error.
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
            f"lint_style: cannot list files with git in {REPO_ROOT}: {exc}"
        ) from exc
    return [line for line in completed.stdout.splitlines() if line]


def is_exempt_path(relative_path: str) -> bool:
    """Report whether an entire file sits outside the character rules.

    Only exemptions 1 and 2 are whole-file. Exemption 3 is per span and is
    applied inside check_text instead.
    """
    if relative_path == EXEMPT_LICENCE:
        return True
    # The exemption covers fixture *data*, not documentation that happens to
    # live beside it. A README in the fixture tree is prose and is checked
    # like any other prose.
    if relative_path.endswith(".md"):
        return False
    return relative_path.startswith(EXEMPT_FIXTURE_PREFIX)


# -----------------------------------------------------------------------------
# Span masking
#
# Two rules need to ignore regions of a Markdown file: the non-ASCII rule
# ignores math spans, and the exclamation rule ignores code. Rather than parse
# Markdown, each masking function replaces the characters it wants ignored
# with spaces. Offsets are preserved exactly, so a reported column still
# points at the real character in the original line.
# -----------------------------------------------------------------------------


def strip_math_spans(text: str) -> str:
    """Blank out LaTeX math spans, preserving every offset.

    Handles displayed math delimited by a doubled dollar sign and inline math
    delimited by a single one. An unmatched dollar sign is left alone, which
    is the safe direction: it keeps the rest of the line under check rather
    than blanking to end of file.
    """
    out = list(text)
    index = 0
    length = len(text)
    while index < length:
        if text[index] != "$":
            index += 1
            continue
        # A doubled dollar opens displayed math, a single one opens inline.
        delimiter = "$$" if text.startswith("$$", index) else "$"
        close = text.find(delimiter, index + len(delimiter))
        if close == -1:
            index += 1
            continue
        end = close + len(delimiter)
        for position in range(index, end):
            if out[position] != "\n":
                out[position] = " "
        index = end
    return "".join(out)


def strip_inline_code(text: str) -> str:
    """Blank out backtick delimited inline code, preserving every offset.

    Used only by the exclamation rule. An exclamation mark inside a shell
    snippet is code, not prose, and flagging it would be a false positive.
    """
    out = list(text)
    index = 0
    length = len(text)
    while index < length:
        if text[index] != "`":
            index += 1
            continue
        # Count the opening run so that doubled-backtick spans close properly.
        run = 0
        while index + run < length and text[index + run] == "`":
            run += 1
        fence = "`" * run
        close = text.find(fence, index + run)
        if close == -1:
            index += run
            continue
        end = close + run
        for position in range(index, end):
            if out[position] != "\n":
                out[position] = " "
        index = end
    return "".join(out)


def strip_html_comments(text: str) -> str:
    """Blank out HTML comments, preserving every offset.

    Used only by the exclamation rule. Every Markdown document in this
    project opens with an HTML comment carrying the licence header, and
    the comment opener itself contains an exclamation mark. That mark is
    markup rather than prose, so flagging it would make the required
    header impossible to write.

    An unterminated comment is left alone, which keeps the rest of the
    file under check rather than blanking to end of file.
    """
    out = list(text)
    index = 0
    length = len(text)
    while index < length:
        start = text.find("<!--", index)
        if start == -1:
            break
        close = text.find("-->", start + 4)
        if close == -1:
            break
        end = close + 3
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = " "
        index = end
    return "".join(out)


def is_emoji(character: str) -> bool:
    """Report whether a character falls in one of the emoji ranges above."""
    code_point = ord(character)
    return any(low <= code_point <= high for low, high in EMOJI_RANGES)


# -----------------------------------------------------------------------------
# The rules
# -----------------------------------------------------------------------------


def check_characters(
    relative_path: str, line_number: int, line: str
) -> list[Finding]:
    """Apply the em-dash, emoji, and ASCII rules to one already-masked line.

    Reporting order matters for usability. A single em-dash would otherwise
    produce both an em-dash finding and a non-ASCII finding for the same
    character, so the specific rule wins and the generic one is suppressed.
    """
    findings: list[Finding] = []
    for column, character in enumerate(line, start=1):
        if character == EM_DASH:
            findings.append(
                Finding(
                    relative_path,
                    line_number,
                    column,
                    "em-dash",
                    "em-dash is banned; use a comma, a colon, parentheses, "
                    "or split into two sentences",
                )
            )
        elif is_emoji(character):
            findings.append(
                Finding(
                    relative_path,
                    line_number,
                    column,
                    "emoji",
                    f"emoji U+{ord(character):04X} is banned anywhere in "
                    "the repository",
                )
            )
        elif ord(character) > 0x7F:
            findings.append(
                Finding(
                    relative_path,
                    line_number,
                    column,
                    "non-ascii",
                    f"non-ASCII character U+{ord(character):04X}; only "
                    "LICENSE, tests/fixtures, and LaTeX math are exempt",
                )
            )
    return findings


def check_text(relative_path: str, text: str) -> list[Finding]:
    """Apply every character rule to one file's decoded text.

    Markdown files have fenced code blocks tracked, because the exclamation
    rule applies to prose only. The character rules apply everywhere,
    including on fence delimiter lines, so they run before the fence check
    short-circuits the loop.
    """
    findings: list[Finding] = []
    is_markdown = relative_path.endswith(".md")

    # Math spans are exempt from the ASCII rule in the file types that can
    # carry them, which in this repository means Markdown. Splitting both the
    # original and the masked text once keeps this linear rather than
    # quadratic in the number of lines.
    ascii_source = strip_math_spans(text) if is_markdown else text
    # The exclamation rule reads a second, separately masked copy: HTML
    # comments are markup, and the licence header this project requires is
    # itself an HTML comment.
    prose_source = strip_html_comments(text) if is_markdown else text
    raw_lines = text.splitlines()
    ascii_lines = ascii_source.splitlines()
    prose_lines = prose_source.splitlines()

    in_fence = False
    fence_marker = ""

    for index, raw_line in enumerate(raw_lines):
        line_number = index + 1
        ascii_line = ascii_lines[index] if index < len(ascii_lines) else ""

        findings.extend(
            check_characters(relative_path, line_number, ascii_line)
        )

        if not is_markdown:
            continue

        stripped = raw_line.lstrip()
        if stripped.startswith(FENCE_MARKERS):
            marker = stripped[:3]
            if not in_fence:
                in_fence = True
                fence_marker = marker
            elif marker == fence_marker:
                in_fence = False
            # A fence delimiter line carries no prose, so nothing further.
            continue

        if in_fence:
            continue

        prose_line = prose_lines[index] if index < len(prose_lines) else ""
        prose = strip_inline_code(prose_line)
        for column, character in enumerate(prose, start=1):
            if character == "!":
                findings.append(
                    Finding(
                        relative_path,
                        line_number,
                        column,
                        "exclamation",
                        "exclamation mark in documentation prose",
                    )
                )

    return findings


def check_file(relative_path: str) -> list[Finding]:
    """Check one file, resolving exemptions and undecodable bytes.

    A file that is not valid UTF-8 is not itself a style failure. Fixtures are
    the only place invalid bytes are expected and those are already exempt, so
    anything else undecodable is reported as its own finding rather than
    crashing the gate.
    """
    if is_exempt_path(relative_path):
        return []

    absolute = REPO_ROOT / relative_path
    if not absolute.is_file():
        return []

    raw = absolute.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        return [
            Finding(
                relative_path,
                1,
                1,
                "encoding",
                f"file is not valid UTF-8 ({exc.reason} at byte {exc.start}); "
                "only tests/fixtures may hold raw bytes",
            )
        ]
    return check_text(relative_path, text)


def main() -> int:
    """Check every in-scope file and report findings grouped by rule."""
    parser = argparse.ArgumentParser(
        description="Character level style gate for the Knap repository."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional explicit paths. Defaults to every git tracked file.",
    )
    arguments = parser.parse_args()

    targets = arguments.paths or tracked_files()

    findings: list[Finding] = []
    for relative_path in targets:
        findings.extend(check_file(relative_path))

    if not findings:
        print(f"lint_style: {len(targets)} files checked, no violations.")
        return 0

    for finding in findings:
        print(finding.render())

    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.rule] = counts.get(finding.rule, 0) + 1
    summary = ", ".join(
        f"{rule}={count}" for rule, count in sorted(counts.items())
    )
    # stdout is block buffered when piped while stderr is not, so the summary
    # would otherwise appear above the findings it summarises.
    sys.stdout.flush()
    print(
        f"lint_style: {len(findings)} violations ({summary}).",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/lint_style.py
# =============================================================================
