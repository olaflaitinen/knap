# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : cli/tests/test_completions.py
# Purpose     : Holds the shell completions to the parser they complete.
# Stage       : Command line interface. See README.md
# Depends on  : cli/args.mojo, the completion files. Standard library only.
# Invariants  : Every command, option, encoding and format the parser
#               accepts must appear in every completion file, and nothing
#               else may.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Check that the shell completions describe the tool that exists.

A completion file is documentation that runs, and it rots the same way
documentation does: an option is renamed, the parser and its tests are
updated, and the completion keeps offering the old name until somebody
presses tab and gets nothing. Nothing else in this repository would notice,
because completions are not executed by any test.

So this reads the lists out of `cli/args.mojo` itself, which is where the
parser decides what it accepts, and checks that each completion file offers
all of them. A missing entry is a tab that does nothing.

The reverse direction, an entry the parser would refuse, is worse: the shell
has told the user something exists and the tool then rejects it. That check
runs for **encodings only**, because an encoding name has a recognisable
shape and a stray one can be spotted without knowing what the surrounding
line means. A format or a command offered wrongly would not be caught, and
that gap is stated here rather than left for a reader to assume otherwise.

    python cli/tests/test_completions.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ARGS = REPO_ROOT / "cli" / "args.mojo"
COMPLETIONS = REPO_ROOT / "cli" / "completions"

FILES = {
    "bash": COMPLETIONS / "knap.bash",
    "zsh": COMPLETIONS / "_knap",
    "fish": COMPLETIONS / "knap.fish",
}

# What the parser accepts, read from the file that decides it. Each pattern
# is anchored on the function that makes the decision rather than on any
# mention of the string, because the parser names commands, formats and
# encodings in the same shape and a loose pattern collects all three.
ENCODING_FUNCTION = re.compile(
    r"def is_known_encoding.*?\n\n\ndef ", re.S
)
FORMAT_FUNCTION = re.compile(r"def format_from.*?\n\n\ndef ", re.S)
NAME_PATTERN = re.compile(r'name == "([a-z0-9_]+)"')
OPTION_PATTERN = re.compile(r'"(--[a-z-]+|-[a-zA-Z])"', re.M)

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    """Record a failure without stopping the run.

    Args:
        condition: What must hold.
        message: What to report when it does not.
    """
    if not condition:
        failures.append(message)


def parser_text() -> str:
    """Read the parser source.

    Returns:
        The contents of cli/args.mojo.

    Raises:
        SystemExit: if it is missing, since there is nothing to check
            against without it.
    """
    if not ARGS.is_file():
        raise SystemExit(f"test_completions: {ARGS} is missing")
    return ARGS.read_text(encoding="utf-8")


def names_in(source: str, pattern: re.Pattern, label: str) -> set[str]:
    """Read the names one parser function compares against.

    Args:
        source: The parser source.
        pattern: A pattern matching that function's whole body.
        label: The function name, for the failure message.

    Returns:
        The names it accepts.

    Raises:
        SystemExit: if the function cannot be found, because an empty set
            would make every check below pass while checking nothing.
    """
    match = pattern.search(source)
    if match is None:
        raise SystemExit(
            f"test_completions: cannot find {label} in cli/args.mojo, so "
            "there is nothing to check the completions against"
        )
    return set(NAME_PATTERN.findall(match.group(0)))


def offers_option(shell: str, text: str, option: str) -> bool:
    """Report whether one completion file offers one option.

    Args:
        shell: Which shell the file is for.
        text: The completion file's contents.
        option: The option as the parser spells it, with its dashes.

    Returns:
        True when the file offers it.

    fish spells options without their dashes, as `-s e` and `-l encoding`,
    so a substring search for the parser's spelling finds nothing there.
    Loosening the check for every shell would have hidden a real gap in the
    other two, so the check knows about fish instead.
    """
    if shell != "fish":
        return option in text
    if option.startswith("--"):
        return f"-l {option[2:]}" in text
    return f"-s {option[1:]}" in text


def main() -> int:
    """Check every completion file against the parser."""
    source = parser_text()

    encodings = names_in(source, ENCODING_FUNCTION, "is_known_encoding")
    formats = names_in(source, FORMAT_FUNCTION, "format_from")
    options = set(OPTION_PATTERN.findall(source))
    commands = {"count", "encode", "decode", "vocab", "help", "version"}

    # The parser mentions each command name as a string somewhere, so this
    # is a check that the set above is still the set the parser knows,
    # rather than a list this test invented.
    for command in commands:
        check(
            f'"{command}"' in source,
            f"the parser does not mention the command {command!r}, so this "
            "test is checking against a list that has gone stale",
        )

    check(len(encodings) == 7, f"expected 7 encodings, the parser names {sorted(encodings)}")
    check(len(formats) == 3, f"expected 3 formats, the parser names {sorted(formats)}")

    for shell, path in FILES.items():
        if not path.is_file():
            failures.append(f"{shell}: {path.relative_to(REPO_ROOT)} is missing")
            continue
        text = path.read_text(encoding="utf-8")

        for command in sorted(commands):
            check(
                re.search(rf"\b{re.escape(command)}\b", text) is not None,
                f"{shell}: the command {command!r} is not offered",
            )
        for encoding in sorted(encodings):
            check(
                encoding in text,
                f"{shell}: the encoding {encoding!r} is not offered",
            )
        for shape in sorted(formats):
            check(shape in text, f"{shell}: the format {shape!r} is not offered")
        for option in sorted(options):
            check(
                offers_option(shell, text, option),
                f"{shell}: the option {option!r} is not offered",
            )

        # Nothing the parser does not accept, for encodings. Their names
        # have a shape this can recognise without parsing shell syntax,
        # which formats and commands do not, so this half of the check is
        # narrower than the half above. See the module docstring.
        for candidate in re.findall(r"\b[a-z0-9]+_(?:base|harmony|edit)\b", text):
            check(
                candidate in encodings,
                f"{shell}: offers {candidate!r}, which the parser refuses",
            )

    if failures:
        print()
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"test_completions: {len(failures)} failures", file=sys.stderr)
        return 1

    print(
        f"test_completions: {len(FILES)} shells offer "
        f"{len(commands)} commands, {len(options)} options, "
        f"{len(encodings)} encodings and {len(formats)} formats, and nothing "
        "the parser refuses"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: cli/tests/test_completions.py
# =============================================================================
