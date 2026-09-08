# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/ucd.py
# Purpose     : Loads the pinned Unicode Character Database and builds the
#               character classes the reference pattern needs.
# Stage       : Shared by the table and boundary generators, see docs/UNICODE.md
# Depends on  : Network access on first use, then a local cache.
# Invariants  : One pinned Unicode version, used by every generator, so the
#               tables and the reference boundaries cannot drift apart.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Pinned Unicode data, shared by the generators that need it.

This module exists because two generators must agree about Unicode, and an
earlier version of this project found out the hard way what happens when they
do not.

The story is worth keeping. The Unicode tables were built from Python's
unicodedata, and the reference piece boundaries were built with the regex
module. Both looked reasonable. Neither matched tiktoken, which carries a
third database inside its Rust core, and the three disagree about thousands
of code points. The 110 MB corpus gate passed anyway, because natural
language does not contain them. The differential fuzzer found it in under
twenty thousand generated inputs.

The version below was identified by probing tiktoken directly, on an input
shape where the piece boundary is visible in the token output. Unicode 16.0.0
matched 400 of 400 disputed code points; 15.1.0 matched 214, the regex module
204, and unicodedata 196.

So: one pinned version, one loader, used by everything.
"""

from __future__ import annotations

import hashlib
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

UNICODE_VERSION = "16.0.0"
"""The Unicode version the reference implementation uses."""

UCD_URL = "https://www.unicode.org/Public/{version}/ucd/UnicodeData.txt"

# Cached rather than committed, for the same reason vocabularies are: the
# data is third party, and its provenance should be a recorded download
# rather than an unexplained blob in the tree.
UCD_CACHE = REPO_ROOT / "tests" / "fixtures" / "ucd"

MAX_CODE_POINT = 0x110000

_CATEGORIES: dict[int, str] | None = None


def load_categories() -> dict[int, str]:
    """Fetch and parse the pinned Unicode Character Database.

    Returns:
        A mapping from code point to its general category.

    Raises:
        SystemExit: if the database cannot be fetched or looks truncated.

    UnicodeData.txt abbreviates large blocks with a First and Last pair
    rather than listing every code point. Expanding those is not optional:
    missing it silently drops the CJK and Hangul blocks, which are the two
    largest letter ranges in the standard.

    The result is cached in module state, because both generators ask for it
    and parsing three hundred thousand lines twice is pointless.
    """
    global _CATEGORIES
    if _CATEGORIES is not None:
        return _CATEGORIES

    UCD_CACHE.mkdir(parents=True, exist_ok=True)
    path = UCD_CACHE / f"UnicodeData-{UNICODE_VERSION}.txt"

    if not path.exists():
        url = UCD_URL.format(version=UNICODE_VERSION)
        print(f"  fetching {url}")
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                body = response.read()
        except (urllib.error.URLError, OSError) as exc:
            raise SystemExit(f"ucd: could not fetch {url}: {exc}")
        path.write_bytes(body)

    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()

    categories: dict[int, str] = {}
    pending: tuple[int, str] | None = None
    for line in raw.decode("utf-8").splitlines():
        fields = line.split(";")
        if len(fields) < 3:
            continue
        code_point = int(fields[0], 16)
        name = fields[1]
        category = fields[2]

        if name.endswith(", First>"):
            pending = (code_point, category)
            continue
        if name.endswith(", Last>") and pending is not None:
            for value in range(pending[0], code_point + 1):
                categories[value] = pending[1]
            pending = None
            continue
        categories[code_point] = category

    if len(categories) < 100000:
        raise SystemExit(
            f"ucd: only {len(categories)} code points parsed from "
            "UnicodeData.txt, which cannot be right"
        )

    print(f"  UnicodeData {UNICODE_VERSION}, sha256 {digest[:16]}")
    _CATEGORIES = categories
    return categories


def code_points_in(prefix: str) -> list[int]:
    """Return every code point whose general category starts with a prefix.

    Args:
        prefix: A category or category prefix, such as "L", "Lu", or "M".

    Returns:
        The matching code points, in ascending order.
    """
    categories = load_categories()
    return sorted(
        code_point
        for code_point, category in categories.items()
        if category.startswith(prefix)
    )


def as_ranges(code_points: list[int]) -> list[tuple[int, int]]:
    """Collapse a sorted code point list into inclusive ranges.

    Args:
        code_points: Ascending code points.

    Returns:
        Inclusive (first, last) pairs.
    """
    ranges: list[tuple[int, int]] = []
    for code_point in code_points:
        if ranges and code_point == ranges[-1][1] + 1:
            ranges[-1] = (ranges[-1][0], code_point)
        else:
            ranges.append((code_point, code_point))
    return ranges


def escape(code_point: int) -> str:
    """Render one code point as a regex escape.

    Args:
        code_point: The code point to render.

    Returns:
        A backslash escape safe inside a character class.

    Escapes rather than literal characters, because a class member such as a
    closing bracket, a caret, a hyphen, or a backslash would otherwise change
    the meaning of the class it sits in.
    """
    if code_point <= 0xFFFF:
        return "\\u%04x" % code_point
    return "\\U%08x" % code_point


def class_body(prefix: str) -> str:
    """Build the inside of a character class for one category prefix.

    Args:
        prefix: A category or category prefix.

    Returns:
        Range expressions suitable for placing inside square brackets.

    Returned without brackets so the result can be spliced either into an
    existing class or wrapped into a new one, which is what the pattern
    rewriting needs.
    """
    parts: list[str] = []
    for first, last in as_ranges(code_points_in(prefix)):
        if first == last:
            parts.append(escape(first))
        else:
            parts.append(f"{escape(first)}-{escape(last)}")
    return "".join(parts)

# =============================================================================
# End of file: scripts/ucd.py
# =============================================================================
