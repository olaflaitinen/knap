# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_md_headers.py
# Purpose     : Validates Markdown document structure: licence header, metadata
#               table, heading levels, link and anchor resolution, and footer.
# Stage       : Repository standard enforcement, see docs/STYLE.md
# Depends on  : git, for the tracked file list. Python standard library only.
# Invariants  : README.md is the single documented exemption from the metadata
#               table and the document control footer. It still carries SPDX.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Markdown structure gate for the Knap repository.

Section 2.4 of docs/STYLE.md fixes a header, a metadata table, and a document
control footer for every Markdown document except README.md, which is exempt
because a metadata block above the title reads as clutter on a project's front
page. This script enforces that standard.

It also resolves every relative link and every in-document anchor. The
standard requires anchors to be verified rather than guessed, and a guessed
anchor is exactly the kind of defect that survives review and then breaks
silently on the forge.

    python scripts/check_md_headers.py

Exit status is 0 when clean and 1 when any document fails.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Two files are exempt from the metadata table and the document control
# footer. Neither is exempt from the licence header, the heading rules, or the
# link rules. See docs/STYLE.md for the reasoning behind each.
#
#   README.md
#       A metadata block above the title reads as clutter to a first time
#       visitor, and the README is the project's front page.
#   .github/PULL_REQUEST_TEMPLATE.md
#       Its body is copied verbatim into every pull request description, so a
#       metadata table would be reproduced in each one. It is a form rather
#       than a document.
EXEMPT_FROM_TABLE = frozenset(
    {"README.md", ".github/PULL_REQUEST_TEMPLATE.md"}
)

# The licence header every Markdown document opens with, matched loosely so
# that whitespace inside the HTML comment is not load bearing.
SPDX_IDENTIFIER = "SPDX-License-Identifier: EUPL-1.2"
HEADER_MARKER = "Part of the Knap project"

# Metadata table fields, in the order section 2.4 requires. Order is checked
# because a table read out of order is harder to scan across documents.
REQUIRED_TABLE_FIELDS = (
    "Document",
    "Project",
    "Version",
    "Status",
    "Applies to",
    "Author",
    "ORCID",
    "Affiliation",
    "Created",
    "Updated",
    "Licence",
)

# Document control footer fields, in order.
REQUIRED_FOOTER_FIELDS = (
    "Previous",
    "Next",
    "Index",
    "Revision",
    "Last reviewed",
)

FOOTER_HEADING = "## Document control"
END_MARKER_PREFIX = "<!-- End of document:"

# The wordmark, required immediately beneath the first level heading of every
# document that carries a metadata table. Section 2.4 of docs/STYLE.md fixes
# the form; this fixes that the form is actually there.
#
# Checked rather than trusted for the ordinary reason: a rule that lives only
# in a style document is a rule that half the files eventually stop following,
# and the half that stops is never the half anybody looks at.
WORDMARK_LIGHT = "knap_logo_transparent_black.svg"
WORDMARK_DARK = "knap_logo_transparent_white.svg"

# Below this the hairline strokes of the typeface break up. The supplied files
# include the clear space, so the wordmark itself is 86.4 percent of the
# rendered width, and 160 pixels of wordmark needs 186 pixels of image. See
# docs/BRAND.md.
WORDMARK_MINIMUM_WIDTH = 186

# A Contents list is required once a document has this many top level
# sections, and is omitted below that.
CONTENTS_THRESHOLD = 3
CONTENTS_HEADING = "## Contents"

# Markdown constructs.
FENCE_MARKERS = ("```", "~~~")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
TABLE_ROW_PATTERN = re.compile(r"^\|\s*(.+?)\s*\|\s*(.*?)\s*\|\s*$")
LINK_PATTERN = re.compile(r"\[(?:[^\]]*)\]\(([^)]+)\)")

# Fenced code blocks must carry a language tag, so that the forge highlights
# them and so that a reader can tell Mojo from Python at a glance.
FENCE_LANGUAGE_PATTERN = re.compile(r"^(?:```|~~~)\s*([A-Za-z0-9_+-]*)\s*$")


@dataclass(frozen=True)
class Problem:
    """One Markdown structure defect.

    Attributes:
        path: Repository relative path of the offending document.
        line: One based line number, or 0 when the defect is whole-file.
        message: What is wrong and what the document should carry instead.
    """

    path: str
    line: int
    message: str

    def render(self) -> str:
        """Format the problem as a single editor-navigable line."""
        return f"{self.path}:{self.line}: {self.message}"


def tracked_files() -> list[str]:
    """Return every repository relative path that git considers in scope."""
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
            f"check_md_headers: cannot list files with git: {exc}"
        ) from exc
    return [line for line in completed.stdout.splitlines() if line]


def slugify(heading_text: str) -> str:
    """Convert heading text to the anchor slug a forge would generate.

    This mirrors the common GitHub rule: lowercase, drop everything that is
    not a word character, a space, or a hyphen, then turn spaces into
    hyphens. Inline code backticks are stripped first because they are markup
    rather than text.

    It is a reimplementation of observed behaviour, not a specification, so a
    document that relies on an exotic heading may need its anchor checked by
    hand. Ordinary headings resolve correctly.
    """
    text = heading_text.replace("`", "")
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE).strip().lower()
    return re.sub(r"[\s]+", "-", text)


def split_code_fences(lines: list[str]) -> list[bool]:
    """Return a per line mask that is True inside a fenced code block.

    Headings, links, and tables inside a fenced block are examples rather
    than structure, so every structural rule consults this mask first.
    """
    inside = False
    marker = ""
    mask: list[bool] = []
    for line in lines:
        stripped = line.lstrip()
        is_fence = stripped.startswith(FENCE_MARKERS)
        if is_fence and not inside:
            inside = True
            marker = stripped[:3]
            mask.append(True)
            continue
        if is_fence and inside and stripped[:3] == marker:
            inside = False
            mask.append(True)
            continue
        mask.append(inside)
    return mask


def parse_two_column_table(
    lines: list[str], start: int, mask: list[bool]
) -> dict[str, tuple[str, int]]:
    """Read a contiguous two column Markdown table starting at or after start.

    Returns a mapping from the first column to the second column paired with
    its line number. Separator rows and the header row are skipped. Reading
    stops at the first line that is not a table row, which is what keeps the
    metadata table and the footer table from merging.
    """
    found: dict[str, tuple[str, int]] = {}
    index = start
    seen_row = False
    while index < len(lines):
        if mask[index]:
            index += 1
            continue
        line = lines[index].strip()
        if not line:
            if seen_row:
                break
            index += 1
            continue
        match = TABLE_ROW_PATTERN.match(line)
        if not match:
            if seen_row:
                break
            index += 1
            continue
        seen_row = True
        key = match.group(1).strip()
        value = match.group(2).strip()
        if set(key) <= set("-: ") and set(value) <= set("-: "):
            index += 1
            continue
        if key.lower() != "field":
            found[key] = (value, index + 1)
        index += 1
    return found


def check_table_fields(
    relative_path: str,
    table: dict[str, tuple[str, int]],
    required: tuple[str, ...],
    label: str,
) -> list[Problem]:
    """Check a metadata or footer table for presence, order, and values."""
    problems: list[Problem] = []
    for field in required:
        if field not in table:
            problems.append(
                Problem(
                    relative_path,
                    1,
                    f"{label} is missing the required row '{field}'",
                )
            )
            continue
        value, line_number = table[field]
        if not value:
            problems.append(
                Problem(
                    relative_path,
                    line_number,
                    f"{label} row '{field}' is present but empty",
                )
            )

    present = [name for name in table if name in set(required)]
    ordered = [name for name in required if name in set(present)]
    if present != ordered:
        problems.append(
            Problem(
                relative_path,
                1,
                f"{label} rows are out of order; expected "
                + ", ".join(ordered),
            )
        )
    return problems


def check_headings(
    relative_path: str, lines: list[str], mask: list[bool]
) -> tuple[list[Problem], list[str], int]:
    """Check heading structure and collect anchors and section count.

    Returns the problems found, the list of anchor slugs the document
    defines, and the number of second level sections, which decides whether a
    Contents list is required.

    Rules enforced: exactly one first level heading, it comes first, and no
    level is ever skipped on the way down.
    """
    problems: list[Problem] = []
    anchors: list[str] = []
    top_level_count = 0
    section_count = 0
    previous_level = 0
    seen_title = False

    for index, line in enumerate(lines):
        if mask[index]:
            continue
        match = HEADING_PATTERN.match(line)
        if not match:
            continue
        level = len(match.group(1))
        text = match.group(2)
        anchors.append(slugify(text))

        if level == 1:
            top_level_count += 1
            if top_level_count > 1:
                problems.append(
                    Problem(
                        relative_path,
                        index + 1,
                        "a document has exactly one first level heading; "
                        f"'{text}' is an extra one",
                    )
                )
            seen_title = True
        else:
            if not seen_title:
                problems.append(
                    Problem(
                        relative_path,
                        index + 1,
                        f"heading '{text}' appears before the document title",
                    )
                )
            if level == 2:
                section_count += 1
            if previous_level and level > previous_level + 1:
                problems.append(
                    Problem(
                        relative_path,
                        index + 1,
                        f"heading level jumps from {previous_level} to "
                        f"{level} at '{text}'; never skip a level",
                    )
                )
        previous_level = level

    if top_level_count == 0:
        problems.append(
            Problem(relative_path, 1, "document has no first level heading")
        )
    return problems, anchors, section_count


def check_fence_languages(
    relative_path: str, lines: list[str]
) -> list[Problem]:
    """Check that every opening code fence carries a language tag."""
    problems: list[Problem] = []
    inside = False
    marker = ""
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if not stripped.startswith(FENCE_MARKERS):
            continue
        if inside:
            if stripped[:3] == marker:
                inside = False
            continue
        inside = True
        marker = stripped[:3]
        match = FENCE_LANGUAGE_PATTERN.match(stripped)
        if match and not match.group(1):
            problems.append(
                Problem(
                    relative_path,
                    index + 1,
                    "fenced code block has no language tag; use mojo, "
                    "python, bash, toml, json, or text",
                )
            )
    return problems


def blank_inline_code(text: str) -> str:
    """Replace backtick delimited spans with spaces, preserving every offset.

    Args:
        text: One line of Markdown.

    Returns:
        The line with the contents of inline code spans blanked out.

    Offsets are preserved so that a column reported against the blanked line
    still points at the right place in the original.

    This exists because a Mojo signature is full of brackets and parentheses
    and reads to a naive scanner as a link. `ascii_run[kind: Int](data: ...)`
    matched the link pattern and sent the gate looking for a file called
    "data: Span[UInt8], start: Int". Text inside backticks is code, and code
    is not a link. lint_style.py already does the same thing for the
    exclamation rule.
    """
    out = list(text)
    index = 0
    length = len(text)
    while index < length:
        if text[index] != "`":
            index += 1
            continue
        fence = 0
        while index + fence < length and text[index + fence] == "`":
            fence += 1
        closing = text.find("`" * fence, index + fence)
        if closing < 0:
            break
        for position in range(index + fence, closing):
            out[position] = " "
        index = closing + fence
    return "".join(out)


def check_links(
    relative_path: str,
    lines: list[str],
    mask: list[bool],
    anchors: list[str],
) -> list[Problem]:
    """Resolve every relative link target and every in-document anchor.

    External links beginning with a scheme are accepted without a network
    request, since a build gate must not depend on the network. Everything
    else must resolve on disk, and a fragment must match a heading this
    document actually defines.
    """
    problems: list[Problem] = []
    document_dir = (REPO_ROOT / relative_path).parent
    anchor_set = set(anchors)

    for index, line in enumerate(lines):
        if mask[index]:
            continue
        for target in LINK_PATTERN.findall(blank_inline_code(line)):
            target = target.strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue

            path_part, _, fragment = target.partition("#")

            if not path_part:
                # A pure fragment must name a heading in this document.
                if fragment and fragment not in anchor_set:
                    problems.append(
                        Problem(
                            relative_path,
                            index + 1,
                            f"anchor '#{fragment}' does not match any "
                            "heading in this document",
                        )
                    )
                continue

            if path_part.startswith("/"):
                problems.append(
                    Problem(
                        relative_path,
                        index + 1,
                        f"link '{target}' is absolute; in-repo links must be "
                        "relative so the docs work in a clone",
                    )
                )
                continue

            resolved = (document_dir / path_part).resolve()
            if not resolved.exists():
                problems.append(
                    Problem(
                        relative_path,
                        index + 1,
                        f"link target '{path_part}' does not exist",
                    )
                )
    return problems


def check_wordmark(
    relative_path: str, lines: list[str], title_index: int
) -> list[Problem]:
    """Check that the wordmark sits directly beneath the title.

    Args:
        relative_path: The document being checked.
        lines: Its lines, without line endings.
        title_index: Index of the first level heading.

    Returns:
        Any problems found.

    Three things are checked and each has failed somewhere in some project.
    That the mark is present at all. That the paths resolve from this
    document, since the correct relative prefix differs between the
    repository root, docs, and bindings. And that it is not rendered below
    the size at which a hairline typeface stops being legible, which is the
    one a reviewer never notices because it looks fine on their screen.
    """
    problems: list[Problem] = []

    # The block sits between the title and whatever follows it. Read a
    # generous window rather than a fixed offset, so reformatting the block
    # does not become a failure.
    window = "\n".join(lines[title_index : title_index + 14])

    if WORDMARK_LIGHT not in window or WORDMARK_DARK not in window:
        problems.append(
            Problem(
                relative_path,
                title_index + 1,
                "the wordmark must follow the title, as a picture element "
                f"naming both {WORDMARK_LIGHT} and {WORDMARK_DARK}",
            )
        )
        return problems

    for asset in (WORDMARK_LIGHT, WORDMARK_DARK):
        for line in lines[title_index : title_index + 14]:
            if asset not in line:
                continue
            start = line.find('"', line.find(asset) - 200)
            reference = line[line.find('"', 0) + 1 : line.rfind('"')]
            if asset not in reference:
                reference = asset
            target = (REPO_ROOT / relative_path).parent / reference
            if not target.is_file():
                problems.append(
                    Problem(
                        relative_path,
                        title_index + 1,
                        f"the wordmark path '{reference}' does not resolve "
                        "from this document",
                    )
                )
            break

    for line in lines[title_index : title_index + 14]:
        if "width=" not in line:
            continue
        digits = "".join(c for c in line.split("width=")[1] if c.isdigit())
        if digits and int(digits) < WORDMARK_MINIMUM_WIDTH:
            problems.append(
                Problem(
                    relative_path,
                    title_index + 1,
                    f"the wordmark is rendered at {digits} pixels; below "
                    f"{WORDMARK_MINIMUM_WIDTH} the hairline strokes break "
                    "up. See docs/BRAND.md.",
                )
            )
        break

    return problems


def check_document(relative_path: str) -> list[Problem]:
    """Check one Markdown document against the whole section 2.4 standard."""
    absolute = REPO_ROOT / relative_path
    if not absolute.is_file():
        return []

    try:
        text = absolute.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []

    lines = text.splitlines()
    if not lines:
        return [Problem(relative_path, 0, "document is empty")]

    mask = split_code_fences(lines)
    problems: list[Problem] = []

    # Licence header. Required of every document including README.md.
    head = "\n".join(lines[:12])
    if SPDX_IDENTIFIER not in head:
        problems.append(
            Problem(
                relative_path,
                1,
                f"document must open with an HTML comment carrying "
                f"'{SPDX_IDENTIFIER}'",
            )
        )
    if HEADER_MARKER not in head:
        problems.append(
            Problem(
                relative_path,
                1,
                f"licence header must state '{HEADER_MARKER}'",
            )
        )

    heading_problems, anchors, section_count = check_headings(
        relative_path, lines, mask
    )
    problems.extend(heading_problems)
    problems.extend(check_fence_languages(relative_path, lines))
    problems.extend(check_links(relative_path, lines, mask, anchors))

    if relative_path in EXEMPT_FROM_TABLE:
        return problems

    # Metadata table, read from just after the title.
    title_index = next(
        (
            index
            for index, line in enumerate(lines)
            if not mask[index] and line.startswith("# ")
        ),
        None,
    )
    if title_index is not None:
        problems.extend(check_wordmark(relative_path, lines, title_index))
        table = parse_two_column_table(lines, title_index + 1, mask)
        problems.extend(
            check_table_fields(
                relative_path, table, REQUIRED_TABLE_FIELDS, "metadata table"
            )
        )
        declared = table.get("Document", ("", 0))[0].strip("`")
        if declared and declared != relative_path:
            problems.append(
                Problem(
                    relative_path,
                    table["Document"][1],
                    f"metadata Document row says '{declared}' but the file "
                    f"is at '{relative_path}'",
                )
            )

    # Contents list, required once the document has enough sections. The
    # Contents and Document control headings are themselves sections, so they
    # are discounted before comparing against the threshold.
    body_sections = section_count
    if any(line.strip() == CONTENTS_HEADING for line in lines):
        body_sections -= 1
    if any(line.strip() == FOOTER_HEADING for line in lines):
        body_sections -= 1
    has_contents = any(line.strip() == CONTENTS_HEADING for line in lines)
    if body_sections >= CONTENTS_THRESHOLD and not has_contents:
        problems.append(
            Problem(
                relative_path,
                1,
                f"document has {body_sections} sections so it requires a "
                f"'{CONTENTS_HEADING}' list",
            )
        )

    # Document control footer.
    footer_index = next(
        (
            index
            for index, line in enumerate(lines)
            if not mask[index] and line.strip() == FOOTER_HEADING
        ),
        None,
    )
    if footer_index is None:
        problems.append(
            Problem(
                relative_path,
                len(lines),
                f"document must end with a '{FOOTER_HEADING}' section",
            )
        )
    else:
        footer_table = parse_two_column_table(lines, footer_index + 1, mask)
        problems.extend(
            check_table_fields(
                relative_path,
                footer_table,
                REQUIRED_FOOTER_FIELDS,
                "document control table",
            )
        )

    # End marker, and nothing after it.
    end_lines = [
        index
        for index, line in enumerate(lines)
        if line.strip().startswith(END_MARKER_PREFIX)
    ]
    if not end_lines:
        problems.append(
            Problem(
                relative_path,
                len(lines),
                f"document must end with '{END_MARKER_PREFIX} "
                f"{relative_path} -->'",
            )
        )
    else:
        marker_index = end_lines[-1]
        expected = f"{END_MARKER_PREFIX} {relative_path} -->"
        if lines[marker_index].strip() != expected:
            problems.append(
                Problem(
                    relative_path,
                    marker_index + 1,
                    f"end marker must read '{expected}'",
                )
            )
        trailing = [
            line for line in lines[marker_index + 1 :] if line.strip()
        ]
        if trailing:
            problems.append(
                Problem(
                    relative_path,
                    marker_index + 2,
                    "no content may follow the end of document marker",
                )
            )

    return problems


def main() -> int:
    """Check every in-scope Markdown document and report each defect."""
    parser = argparse.ArgumentParser(
        description="Markdown structure gate for the Knap repository."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional explicit paths. Defaults to every git tracked file.",
    )
    arguments = parser.parse_args()

    candidates = arguments.paths or tracked_files()
    # Every Markdown document is checked. There is no path exemption: the
    # fixture exemption in the other gates covers data, not prose.
    targets = [path for path in candidates if path.endswith(".md")]

    problems: list[Problem] = []
    for relative_path in targets:
        problems.extend(check_document(relative_path))

    if not problems:
        print(
            f"check_md_headers: {len(targets)} documents checked, "
            "all conform."
        )
        return 0

    for problem in problems:
        print(problem.render())
    sys.stdout.flush()
    print(
        f"check_md_headers: {len(problems)} document problems.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/check_md_headers.py
# =============================================================================
