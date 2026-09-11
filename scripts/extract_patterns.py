# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/extract_patterns.py
# Purpose     : Extracts the pre-tokenization patterns from tiktoken and emits
#               them as a generated Mojo source file.
# Stage       : Pre-tokenization. See docs/ARCHITECTURE.md
# Depends on  : tiktoken, as the source of the patterns.
# Invariants  : The pattern is copied verbatim. Nothing here rewrites,
#               normalises, or prettifies it, because a single changed
#               character produces silent divergence on rare inputs.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Extract the pre-tokenization patterns and generate pattern.mojo.

The patterns are never transcribed by hand. Both are long, o200k_base
especially so at 274 characters, and a single wrong character produces a
tokenizer that agrees with the reference on ordinary text and diverges on
rare inputs. So the pattern string is pulled out of the registered encoding
and written to the generated file verbatim.

Knap does not execute these patterns. It reproduces their behaviour with a
hand rolled scanner, which is a far smaller problem than a general regex
engine and the only tractable path to SIMD. The generated constants therefore
serve as a specification and as a drift detector: tests compare the scanner
against the pattern, and scripts/check_generated.py re-runs this script and
fails if the committed output has changed.

    python scripts/extract_patterns.py
    python scripts/extract_patterns.py --check

Exit status is 0 on success, or 1 in check mode when the committed file is
out of date.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "src" / "knap" / "pretokenize" / "pattern.mojo"

# gpt2 is here for its pattern rather than for itself. Four encodings share
# it byte for byte: gpt2, r50k_base, p50k_base and p50k_edit. Extracting it
# once under the name of the oldest is clearer than four identical constants.
WANTED = ("cl100k_base", "o200k_base", "gpt2")

# Characters that must be escaped inside a Mojo string literal. Both are
# referenced by code point so that this file contains no stray backslash of
# its own, which keeps the escaping logic readable.
BACKSLASH = chr(92)
QUOTE = chr(34)


def mojo_string_literal(value: str) -> str:
    """Render a Python string as a Mojo double quoted string literal.

    Args:
        value: The exact string to encode.

    Returns:
        A Mojo source literal that evaluates back to value.

    Raises:
        ValueError: if the string holds a character this simple escaper does
            not handle. Both patterns are printable ASCII, so anything else
            means an assumption has broken and silence would be dangerous.

    Only two escapes are needed, because the patterns are printable ASCII.
    Rather than reach for a general escaper, the unhandled cases raise, so a
    future pattern containing a newline or a tab fails loudly here instead of
    producing a subtly wrong constant.
    """
    out: list[str] = []
    for character in value:
        code = ord(character)
        if character == BACKSLASH:
            out.append(BACKSLASH * 2)
        elif character == QUOTE:
            out.append(BACKSLASH + QUOTE)
        elif 0x20 <= code <= 0x7E:
            out.append(character)
        else:
            raise ValueError(
                f"pattern contains U+{code:04X}, which this escaper does "
                "not handle; extend it deliberately rather than guessing"
            )
    return QUOTE + "".join(out) + QUOTE


def split_alternatives(pattern: str) -> list[str]:
    """Split a pattern into its top level alternatives.

    Args:
        pattern: The regex source.

    Returns:
        The alternatives, in order.

    Alternation order is load bearing. The pattern is tried left to right and
    the first alternative that matches wins, so the scanner must encode that
    ordering explicitly. Splitting here lets the generated file record the
    order as a comment, which is the thing a reader of scanner.mojo needs
    most.

    The split respects escapes, character classes, and group nesting, so a
    vertical bar inside a class or a group is not treated as a separator.
    """
    alternatives: list[str] = []
    current: list[str] = []
    depth = 0
    in_class = False
    index = 0

    while index < len(pattern):
        character = pattern[index]
        if character == BACKSLASH:
            current.append(pattern[index : index + 2])
            index += 2
            continue
        if in_class:
            if character == "]":
                in_class = False
        elif character == "[":
            in_class = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        elif character == "|" and depth == 0:
            alternatives.append("".join(current))
            current = []
            index += 1
            continue
        current.append(character)
        index += 1

    alternatives.append("".join(current))
    return alternatives


def collect() -> dict[str, str]:
    """Read the pattern string for each target encoding.

    Returns:
        A mapping from encoding name to its pattern.

    Raises:
        SystemExit: if tiktoken is missing, or if an encoding stops exposing
            its pattern. The private attribute is not a documented interface,
            so its absence is reported as a real problem rather than worked
            around.
    """
    try:
        import tiktoken
    except ImportError as exc:
        raise SystemExit(
            "extract_patterns: tiktoken is not installed. Run 'uv sync "
            "--group dev' first."
        ) from exc

    patterns: dict[str, str] = {}
    for name in WANTED:
        encoding = tiktoken.get_encoding(name)
        pattern = getattr(encoding, "_pat_str", None)
        if not pattern:
            raise SystemExit(
                f"extract_patterns: encoding '{name}' does not expose a "
                "pattern string. tiktoken's internals have changed and this "
                "script needs updating rather than working around it."
            )
        patterns[name] = pattern
    return patterns


def render(patterns: dict[str, str]) -> str:
    """Render the generated Mojo source.

    Args:
        patterns: Encoding name to pattern string.

    Returns:
        The complete contents of pattern.mojo.
    """
    import tiktoken

    version = getattr(tiktoken, "__version__", "unknown")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    rule = "# " + "=" * 77
    thin = "# " + "-" * 77

    lines: list[str] = []
    lines.append(rule)
    lines.append("# Project     : Knap, a pure Mojo byte level BPE tokenizer")
    lines.append("# File        : src/knap/pretokenize/pattern.mojo")
    lines.append(
        "# Purpose     : The pre-tokenization patterns, extracted verbatim"
    )
    lines.append("#               from tiktoken as a functional specification.")
    lines.append("# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md")
    lines.append("# Depends on  : Nothing. Constants only.")
    lines.append(
        "# Invariants  : Alternation order is load bearing. The pattern is"
    )
    lines.append(
        "#               tried left to right and the first match wins."
    )
    lines.append(thin)
    lines.append("# Generator   : scripts/extract_patterns.py")
    lines.append(f"# Upstream    : tiktoken {version}, MIT licensed")
    lines.append(f"# Generated   : {today}")
    lines.append(
        "# NOTE        : This file is generated. Manual edits will be"
    )
    lines.append(
        "#               overwritten the next time the generator runs."
    )
    lines.append(thin)
    lines.append(
        "# Author      : Olaf Yunus Laitinen Imanov "
        "<yunus.imanov@metropolia.fi>"
    )
    lines.append("# ORCID       : 0009-0006-5184-0810")
    lines.append(
        "# Affiliation : School of Information and Communication Technology,"
    )
    lines.append("#               Metropolia University of Applied Sciences")
    lines.append(thin)
    lines.append("# SPDX-License-Identifier: EUPL-1.2")
    lines.append("# Copyright 2026 Olaf Yunus Laitinen Imanov")
    lines.append(rule)
    lines.append('"""Pre-tokenization patterns, extracted from tiktoken.')
    lines.append("")
    lines.append(
        "Knap does not execute these patterns. It reproduces their behaviour"
    )
    lines.append(
        "with a hand rolled scanner, and these constants are the"
    )
    lines.append(
        "specification that scanner is written against. A test re-extracts"
    )
    lines.append("them and fails if the committed copy has drifted.")
    lines.append("")
    lines.append(
        "The patterns are reproduced verbatim, including their possessive"
    )
    lines.append(
        "quantifiers. cl100k_base uses them and o200k_base does not, which"
    )
    lines.append(
        "changes matching semantics: a possessive quantifier never gives"
    )
    lines.append(
        "back what it consumed, so an alternative that fails after one"
    )
    lines.append("fails outright rather than retrying a shorter match.")
    lines.append('"""')
    lines.append("")

    for name in WANTED:
        pattern = patterns[name]
        digest = hashlib.sha256(pattern.encode("utf-8")).hexdigest()
        alternatives = split_alternatives(pattern)
        upper = name.upper()

        lines.append("")
        lines.append(thin)
        lines.append(f"# {name}")
        lines.append("#")
        lines.append(
            f"# {len(alternatives)} top level alternatives, tried in this "
            "order:"
        )
        for position, alternative in enumerate(alternatives):
            lines.append(f"#   {position}. {alternative}")
        lines.append(thin)
        lines.append("")
        lines.append(
            f"comptime {upper}_PATTERN: StaticString = "
            f"{mojo_string_literal(pattern)}"
        )
        lines.append(
            f'"""The {name} pre-tokenization pattern, verbatim."""'
        )
        lines.append("")
        lines.append(
            f"comptime {upper}_PATTERN_SHA256: StaticString = "
            f'"{digest}"'
        )
        lines.append(
            f'"""SHA-256 of the {name} pattern, for drift detection."""'
        )
        lines.append("")
        lines.append(
            f"comptime {upper}_ALTERNATIVES: Int = {len(alternatives)}"
        )
        lines.append(
            f'"""Number of top level alternatives in the {name} pattern."""'
        )

    lines.append("")
    lines.append(rule)
    lines.append("# End of file: src/knap/pretokenize/pattern.mojo")
    lines.append(rule)
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    """Generate pattern.mojo, or verify the committed copy is current."""
    parser = argparse.ArgumentParser(
        description="Extract the tiktoken pre-tokenization patterns."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write. Exit non-zero if the committed file is stale.",
    )
    arguments = parser.parse_args()

    patterns = collect()
    rendered = render(patterns)

    if arguments.check:
        if not OUTPUT.exists():
            print(f"extract_patterns: {OUTPUT} does not exist")
            return 1
        current = OUTPUT.read_text(encoding="utf-8")
        # The generation date changes every run, so it is excluded from
        # the comparison. Everything that affects behaviour is compared,
        # against a formatted candidate because the committed file has
        # been through the formatter.
        candidate = formatted_text(rendered)
        if strip_date(current) != strip_date(candidate):
            print(
                "extract_patterns: the committed pattern.mojo differs from "
                "what the generator produces. Re-run "
                "'python scripts/extract_patterns.py'."
            )
            return 1
        print("extract_patterns: committed pattern.mojo is current.")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8")
    format_in_place(OUTPUT)
    for name in WANTED:
        pattern = patterns[name]
        print(
            f"  {name}: {len(pattern)} chars, "
            f"{len(split_alternatives(pattern))} alternatives"
        )
    print(f"extract_patterns: wrote {OUTPUT.relative_to(REPO_ROOT)}")
    return 0


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

    The date records when the file was produced, which is useful provenance
    and useless for drift detection. Comparing it would make check mode fail
    every day for no reason.
    """
    return "\n".join(
        line
        for line in text.splitlines()
        if not line.startswith("# Generated   :")
    )


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/extract_patterns.py
# =============================================================================
