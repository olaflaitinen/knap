# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/gen_unicode_tables.py
# Purpose     : Emits the Unicode general category tables the pre-tokenizer
#               needs, as a generated Mojo source file.
# Stage       : Milestone M2, pre-tokenizer. See docs/UNICODE.md
# Depends on  : Python unicodedata, as the source of the category data.
# Invariants  : Runs are sorted, non overlapping, and exclude the OTHER class,
#               so binary search over them is well defined.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Generate the Unicode property tables for the pre-tokenizer.

Both target patterns need general category membership tests. cl100k_base
needs Letter and Number. o200k_base needs considerably more: the five letter
subcategories separately, plus Mark, because its first two alternatives
distinguish uppercase-ish runs from lowercase-ish runs.

Rather than eight independent tables, every code point is assigned one class
from a set of eight. Every property either patterns needs is then a test on
that single value, and Letter is simply the union of the five letter classes.

Two representation decisions, both measured rather than assumed. They are
written up in docs/UNICODE.md.

  * The data is emitted as ASCII string literals, not as list literals. A
    list literal of 34560 elements did not finish compiling in ten minutes,
    while the same data as one string literal compiled in under six seconds.
    That is a property of the compiler, not a style preference.
  * Lookup is a binary search over sorted runs, with a direct 128 entry
    table for ASCII. The alternative, a two stage table, was measured at 135
    unique blocks and 43264 bytes with O(1) lookup, against 2342 runs and
    roughly 21 kilobytes here. The ASCII fast path is what settles it: the
    scanner reaches these tables only on non-ASCII input, which is the
    documented slow path.

It also writes tests/golden/unicode_classes.txt, one hex digit per code
point, so that tests/test_unicode_tables.mojo can check every one of the
1114112 code points rather than a sample.

    python scripts/gen_unicode_tables.py
    python scripts/gen_unicode_tables.py --check
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "src" / "knap" / "pretokenize" / "unicode_tables.mojo"

# An exhaustive reference: one hex digit per code point, in order. The Mojo
# table is verified against this for every code point rather than for a
# sample, because the run collapsing in build_runs is exactly the kind of
# logic that is correct on a sample and wrong at a boundary.
GOLDEN = REPO_ROOT / "tests" / "golden" / "unicode_classes.txt"

MAX_CODE_POINT = sys.maxunicode + 1

# One class per code point. Every property both patterns need is a test on
# this value, and Letter is the union of classes 1 through 5.
CLASS_OTHER = 0
CLASS_LU = 1
CLASS_LL = 2
CLASS_LT = 3
CLASS_LM = 4
CLASS_LO = 5
CLASS_M = 6
CLASS_N = 7

LETTER_CLASSES = {"Lu": CLASS_LU, "Ll": CLASS_LL, "Lt": CLASS_LT,
                  "Lm": CLASS_LM, "Lo": CLASS_LO}

# The whitespace set the regex module matches for a str pattern. Enumerated
# rather than derived: it is 25 code points, and a wrong set would silently
# change every whitespace alternative in both patterns.
WHITESPACE = (
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680,
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
    0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
)

ASCII_LIMIT = 128


def class_of(code_point: int) -> int:
    """Return the Knap class for one code point.

    Args:
        code_point: The code point to classify.

    Returns:
        One of the CLASS_ constants above.
    """
    category = unicodedata.category(chr(code_point))
    if category in LETTER_CLASSES:
        return LETTER_CLASSES[category]
    if category.startswith("M"):
        return CLASS_M
    if category.startswith("N"):
        return CLASS_N
    return CLASS_OTHER


def build_classes() -> bytearray:
    """Classify every code point once.

    Returns:
        A byte per code point, holding its class.
    """
    classes = bytearray(MAX_CODE_POINT)
    for code_point in range(MAX_CODE_POINT):
        classes[code_point] = class_of(code_point)
    return classes


def build_runs(classes: bytearray) -> list[tuple[int, int, int]]:
    """Collapse the per code point classes into maximal constant runs.

    Args:
        classes: One class byte per code point.

    Returns:
        Sorted, non overlapping (start, end, class) triples, excluding runs
        of the OTHER class.

    Dropping the OTHER runs is what keeps the table small: unassigned and
    punctuation code points are the majority, and a binary search that finds
    no containing run can simply report OTHER.
    """
    runs: list[tuple[int, int, int]] = []
    start = 0
    current = classes[0]
    for code_point in range(1, MAX_CODE_POINT):
        if classes[code_point] != current:
            if current != CLASS_OTHER:
                runs.append((start, code_point - 1, current))
            start = code_point
            current = classes[code_point]
    if current != CLASS_OTHER:
        runs.append((start, MAX_CODE_POINT - 1, current))
    return runs


def hex_field(value: int, width: int) -> str:
    """Render an integer as fixed width lowercase hex.

    Args:
        value: The value to render.
        width: Number of hex digits.

    Returns:
        The hex string.

    Raises:
        ValueError: if the value does not fit, which would silently corrupt
            the table.
    """
    if value < 0 or value >= 16 ** width:
        raise ValueError(f"{value} does not fit in {width} hex digits")
    return format(value, f"0{width}x")


def render(runs: list[tuple[int, int, int]], classes: bytearray) -> str:
    """Render the generated Mojo source.

    Args:
        runs: The sorted class runs.
        classes: Per code point classes, used for the ASCII table.

    Returns:
        The complete contents of unicode_tables.mojo.
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    rule = "# " + "=" * 77
    thin = "# " + "-" * 77

    starts = "".join(hex_field(run[0], 6) for run in runs)
    ends = "".join(hex_field(run[1], 6) for run in runs)
    run_classes = "".join(hex_field(run[2], 1) for run in runs)
    ascii_table = "".join(
        hex_field(classes[code_point], 1) for code_point in range(ASCII_LIMIT)
    )
    whitespace = "".join(hex_field(cp, 6) for cp in WHITESPACE)

    out: list[str] = []
    add = out.append

    add(rule)
    add("# Project     : Knap, a pure Mojo byte level BPE tokenizer")
    add("# File        : src/knap/pretokenize/unicode_tables.mojo")
    add("# Purpose     : Unicode general category classes for the")
    add("#               pre-tokenizer, as sorted runs with an ASCII table.")
    add("# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md")
    add("# Depends on  : Nothing. Constants and pure lookups only.")
    add("# Invariants  : Runs are sorted, non overlapping, and never carry")
    add("#               the OTHER class, so binary search is well defined.")
    add(thin)
    add("# Generator   : scripts/gen_unicode_tables.py")
    add(
        "# Upstream    : Unicode Character Database "
        f"{unicodedata.unidata_version}, via Python unicodedata"
    )
    add(f"# Generated   : {today}")
    add("# NOTE        : This file is generated. Manual edits will be")
    add("#               overwritten the next time the generator runs.")
    add(thin)
    add(
        "# Author      : Olaf Yunus Laitinen Imanov "
        "<yunus.imanov@metropolia.fi>"
    )
    add("# ORCID       : 0009-0006-5184-0810")
    add(
        "# Affiliation : School of Information and Communication Technology,"
    )
    add("#               Metropolia University of Applied Sciences")
    add(thin)
    add("# SPDX-License-Identifier: EUPL-1.2")
    add("# Copyright 2026 Olaf Yunus Laitinen Imanov")
    add(rule)
    add('"""Unicode general category tables for the Knap pre-tokenizer.')
    add("")
    add("Every code point carries one class. Letter is the union of the five")
    add("letter classes, which is why both patterns can be served from a")
    add("single table rather than from eight independent ones.")
    add("")
    add("The tables are ASCII hex strings rather than list literals. That is")
    add("a compiler constraint, not a preference: a list literal of this size")
    add("did not finish compiling in ten minutes, while the same data as a")
    add("string literal compiled in under six seconds. See docs/UNICODE.md.")
    add("")
    add("Lookup is O(1) for ASCII through a direct table, and a binary search")
    add("over sorted runs above that. The scanner reaches the binary search")
    add("only on non-ASCII input, which is the documented slow path.")
    add('"""')
    add("")
    add("")
    add(thin)
    add("# Class constants")
    add("#")
    add("# One value per code point. Letter is classes 1 through 5, which")
    add("# lets is_letter be a range test rather than five comparisons.")
    add(thin)
    add("")
    add(f"comptime CLASS_OTHER: UInt8 = {CLASS_OTHER}")
    add('"""Code point in no category the patterns care about."""')
    add("")
    add(f"comptime CLASS_LU: UInt8 = {CLASS_LU}")
    add('"""Uppercase letter, Unicode general category Lu."""')
    add("")
    add(f"comptime CLASS_LL: UInt8 = {CLASS_LL}")
    add('"""Lowercase letter, Unicode general category Ll."""')
    add("")
    add(f"comptime CLASS_LT: UInt8 = {CLASS_LT}")
    add('"""Titlecase letter, Unicode general category Lt."""')
    add("")
    add(f"comptime CLASS_LM: UInt8 = {CLASS_LM}")
    add('"""Modifier letter, Unicode general category Lm."""')
    add("")
    add(f"comptime CLASS_LO: UInt8 = {CLASS_LO}")
    add('"""Other letter, Unicode general category Lo."""')
    add("")
    add(f"comptime CLASS_M: UInt8 = {CLASS_M}")
    add('"""Mark, any of the Unicode general categories Mn, Mc, and Me."""')
    add("")
    add(f"comptime CLASS_N: UInt8 = {CLASS_N}")
    add('"""Number, any of the Unicode general categories Nd, Nl, and No."""')
    add("")
    add(
        f'comptime UNICODE_VERSION: StaticString = '
        f'"{unicodedata.unidata_version}"'
    )
    add('"""Version of the Unicode Character Database these tables came from."""')
    add("")
    add(f"comptime RUN_COUNT: Int = {len(runs)}")
    add('"""Number of sorted class runs in the tables below."""')
    add("")
    add(f"comptime WHITESPACE_COUNT: Int = {len(WHITESPACE)}")
    add('"""Number of code points the patterns treat as whitespace."""')
    add("")
    add("")
    add(thin)
    add("# Encoded tables")
    add("#")
    add("# Each run contributes six hex digits of start, six of end, and one")
    add("# of class, held in three parallel strings. The ASCII table is one")
    add("# hex digit per code point, indexed directly.")
    add(thin)
    add("")
    add(f'comptime RUN_STARTS: StaticString = "{starts}"')
    add('"""First code point of each run, six hex digits each."""')
    add("")
    add(f'comptime RUN_ENDS: StaticString = "{ends}"')
    add('"""Last code point of each run, six hex digits each."""')
    add("")
    add(f'comptime RUN_CLASSES: StaticString = "{run_classes}"')
    add('"""Class of each run, one hex digit each."""')
    add("")
    add(f'comptime ASCII_CLASSES: StaticString = "{ascii_table}"')
    add('"""Class of each of the 128 ASCII code points, one hex digit each."""')
    add("")
    add(f'comptime WHITESPACE_CODE_POINTS: StaticString = "{whitespace}"')
    add('"""Whitespace code points, six hex digits each."""')
    add("")
    add("")
    add(thin)
    add("# Decoding")
    add(thin)
    add("")
    add("")
    add("def _hex_value(digit: UInt8) -> Int:")
    add('    """Convert one ASCII hex digit to its value.')
    add("")
    add("    Args:")
    add("        digit: An ASCII byte holding a lowercase hex digit.")
    add("")
    add("    Returns:")
    add("        The value 0 through 15.")
    add("")
    add("    The tables are generated by this project and contain only")
    add("    lowercase hex, so this does no validation. A malformed table is")
    add("    a bug in the generator, not user input.")
    add('    """')
    add("    # ASCII '0' is 48 and 'a' is 97.")
    add("    if digit <= 57:")
    add("        return Int(digit) - 48")
    add("    return Int(digit) - 97 + 10")
    add("")
    add("")
    add("def _decode_field(table: StaticString, index: Int, width: Int) -> Int:")
    add('    """Read one fixed width hex field out of an encoded table.')
    add("")
    add("    Args:")
    add("        table: The encoded table.")
    add("        index: Which field to read, counting from zero.")
    add("        width: Number of hex digits per field.")
    add("")
    add("    Returns:")
    add("        The decoded integer.")
    add('    """')
    add("    var bytes = table.as_bytes()")
    add("    var start = index * width")
    add("    var value = 0")
    add("    for offset in range(width):")
    add("        value = value * 16 + _hex_value(bytes[start + offset])")
    add("    return value")
    add("")
    add("")
    add(thin)
    add("# Lookup")
    add(thin)
    add("")
    add("")
    add("def class_of_code_point(code_point: Int) -> UInt8:")
    add('    """Return the Knap class of one code point.')
    add("")
    add("    Args:")
    add("        code_point: The code point to classify.")
    add("")
    add("    Returns:")
    add("        One of the CLASS_ constants.")
    add("")
    add("    ASCII resolves through a direct table, which is the case that")
    add("    matters because real text is dominated by it. Everything else")
    add("    binary searches the sorted runs, and a code point in no run is")
    add("    OTHER.")
    add('    """')
    add("    if code_point < 0:")
    add("        return CLASS_OTHER")
    add("    if code_point < 128:")
    add("        # Direct index. One hex digit per ASCII code point.")
    add("        return UInt8(")
    add("            _hex_value(ASCII_CLASSES.as_bytes()[code_point])")
    add("        )")
    add("")
    add("    var low = 0")
    add("    var high = RUN_COUNT - 1")
    add("    while low <= high:")
    add("        var middle = (low + high) // 2")
    add("        var start = _decode_field(RUN_STARTS, middle, 6)")
    add("        if code_point < start:")
    add("            high = middle - 1")
    add("            continue")
    add("        var end = _decode_field(RUN_ENDS, middle, 6)")
    add("        if code_point > end:")
    add("            low = middle + 1")
    add("            continue")
    add("        return UInt8(_decode_field(RUN_CLASSES, middle, 1))")
    add("    return CLASS_OTHER")
    add("")
    add("")
    add("def is_letter(code_point: Int) -> Bool:")
    add('    """Report whether a code point is in Unicode category L.')
    add("")
    add("    Args:")
    add("        code_point: The code point to test.")
    add("")
    add("    Returns:")
    add("        True for any of the five letter classes.")
    add('    """')
    add("    var value = class_of_code_point(code_point)")
    add("    return value >= CLASS_LU and value <= CLASS_LO")
    add("")
    add("")
    add("def is_number(code_point: Int) -> Bool:")
    add('    """Report whether a code point is in Unicode category N.')
    add("")
    add("    Args:")
    add("        code_point: The code point to test.")
    add("")
    add("    Returns:")
    add("        True for Nd, Nl, and No.")
    add('    """')
    add("    return class_of_code_point(code_point) == CLASS_N")
    add("")
    add("")
    add("def is_mark(code_point: Int) -> Bool:")
    add('    """Report whether a code point is in Unicode category M.')
    add("")
    add("    Args:")
    add("        code_point: The code point to test.")
    add("")
    add("    Returns:")
    add("        True for Mn, Mc, and Me.")
    add('    """')
    add("    return class_of_code_point(code_point) == CLASS_M")
    add("")
    add("")
    add("def is_whitespace(code_point: Int) -> Bool:")
    add('    """Report whether a code point is whitespace for these patterns.')
    add("")
    add("    Args:")
    add("        code_point: The code point to test.")
    add("")
    add("    Returns:")
    add("        True for the 25 code points the reference regex treats as")
    add("        whitespace.")
    add("")
    add("    The set is small and enumerated, so this is a linear scan with")
    add("    an ASCII short circuit rather than a table lookup.")
    add('    """')
    add("    # The ASCII cases cover almost all real input.")
    add("    if code_point == 32:")
    add("        return True")
    add("    if code_point >= 9 and code_point <= 13:")
    add("        return True")
    add("    if code_point < 128:")
    add("        return False")
    add("    for index in range(WHITESPACE_COUNT):")
    add("        if _decode_field(WHITESPACE_CODE_POINTS, index, 6) == code_point:")
    add("            return True")
    add("    return False")
    add("")
    add(rule)
    add("# End of file: src/knap/pretokenize/unicode_tables.mojo")
    add(rule)
    add("")
    return "\n".join(out)


# -----------------------------------------------------------------------------
# Formatter agreement
#
# The generated file is passed through "mojo format" before it is written.
# Without this the formatter and the generator disagree: the formatter splits
# a long string literal across lines, which changes the file without changing
# its meaning, and scripts/check_generated.py then reports permanent drift.
# Formatting here makes the generator's output a fixed point of the
# formatter, so both gates agree.
# -----------------------------------------------------------------------------


def find_mojo() -> Path | None:
    """Locate the pinned Mojo compiler.

    Returns:
        Path to the compiler, or None when it cannot be found.

    The uv environment is checked first because it is the primary one. A
    missing compiler is not fatal: the file is still written, and the
    formatting gate in CI will report the difference.
    """
    candidate = REPO_ROOT / ".venv" / "bin" / "mojo"
    if candidate.exists():
        return candidate
    found = shutil.which("mojo")
    if found:
        return Path(found)
    return None


def format_in_place(path: Path) -> None:
    """Run the canonical formatter over a generated file.

    Args:
        path: The file to format.
    """
    mojo = find_mojo()
    if mojo is None:
        print(
            "  note: no Mojo compiler found, generated file left unformatted"
        )
        return
    subprocess.run(
        [str(mojo), "format", str(path)],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )


def formatted_text(rendered: str) -> str:
    """Return what the formatter would make of rendered source.

    Args:
        rendered: Freshly generated source.

    Returns:
        The formatted equivalent, or the input unchanged when no compiler is
        available.

    Used by check mode so that the committed file, which is formatted, is
    compared against a formatted candidate rather than against raw generator
    output.
    """
    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory) / "candidate.mojo"
        scratch.write_text(rendered, encoding="utf-8")
        format_in_place(scratch)
        return scratch.read_text(encoding="utf-8")


def strip_date(text: str) -> str:
    """Remove the generation date line so comparisons ignore it.

    Args:
        text: Generated file contents.

    Returns:
        The same text with the Generated line removed.
    """
    return "\n".join(
        line
        for line in text.splitlines()
        if not line.startswith("# Generated   :")
    )


def main() -> int:
    """Generate unicode_tables.mojo, or verify the committed copy."""
    parser = argparse.ArgumentParser(
        description="Generate the Unicode tables for the Knap pre-tokenizer."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write. Exit non-zero if the committed file is stale.",
    )
    arguments = parser.parse_args()

    classes = build_classes()
    runs = build_runs(classes)
    rendered = render(runs, classes)

    if arguments.check:
        if not OUTPUT.exists():
            print(f"gen_unicode_tables: {OUTPUT} does not exist")
            return 1
        candidate = formatted_text(rendered)
        if strip_date(OUTPUT.read_text(encoding="utf-8")) != strip_date(
            candidate
        ):
            print(
                "gen_unicode_tables: the committed unicode_tables.mojo "
                "differs from what the generator produces. Re-run "
                "'python scripts/gen_unicode_tables.py'."
            )
            return 1
        print("gen_unicode_tables: committed unicode_tables.mojo is current.")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8")
    format_in_place(OUTPUT)

    GOLDEN.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN.write_text(
        "".join(hex_field(value, 1) for value in classes), encoding="ascii"
    )

    assigned = sum(1 for value in classes if value != CLASS_OTHER)
    print(
        f"  Unicode {unicodedata.unidata_version}: {assigned} classified "
        f"code points in {len(runs)} runs"
    )
    print(f"  encoded table size: {len(rendered)} characters of source")
    print(f"gen_unicode_tables: wrote {OUTPUT.relative_to(REPO_ROOT)}")
    print(f"gen_unicode_tables: wrote {GOLDEN.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/gen_unicode_tables.py
# =============================================================================
