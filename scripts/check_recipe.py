# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_recipe.py
# Purpose     : Gate on the conda recipe. Checks the declared version, the
#               pinned compiler, the source revision, and the test files.
# Stage       : Distribution. See docs/PACKAGING.md
# Depends on  : git, for resolving the source revision. Standard library only.
# Invariants  : Every field it reads must be present exactly once. A recipe
#               it cannot parse is a failure, never a pass.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Gate on the conda recipe.

A recipe is the one file in this repository that nothing else exercises
until somebody tries to publish, and by then the mistakes are public. This
checks the parts that go wrong quietly:

  * the declared version agrees with `CITATION.cff`
  * the pinned compiler agrees with `pixi.toml` and `pyproject.toml`
  * the source revision is a full commit SHA that exists in this repository
  * every file the test section names is actually next to the recipe
  * the licence file it names exists

None of that needs a network or a build, so it runs with the other standards
gates on every push rather than at release time when it is too late.

The reader below understands the subset of YAML this recipe uses and refuses
anything else. That is deliberate: a parser that skips what it does not
understand would report a clean result for a recipe it never read.

    python scripts/check_recipe.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RECIPE = REPO_ROOT / "conda.recipe" / "recipe.yaml"

SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")

# Files that declare a version or a compiler pin, and the pattern that finds
# it. Each must match exactly once, so that a second declaration appearing
# somewhere is a failure rather than a silently ignored disagreement.
VERSION_SOURCES = {
    "CITATION.cff": re.compile(r'^version: "([^"]+)"$', re.M),
}
COMPILER_SOURCES = {
    "pixi.toml": re.compile(r'^mojo = "==([0-9][^"]*)"$', re.M),
    "pyproject.toml": re.compile(r'^\s*"mojo==([0-9][^"]*)",$', re.M),
}


# -----------------------------------------------------------------------------
# A reader for the YAML subset this recipe uses
#
# Block mappings, block sequences, scalars, and block scalars whose content is
# skipped rather than interpreted. Flow style, anchors, multi-document files
# and quoted keys are not supported and are reported rather than ignored.
# -----------------------------------------------------------------------------


class RecipeError(Exception):
    """Raised when the recipe cannot be read as the expected shape."""


def strip_comment(line: str) -> str:
    """Remove a trailing comment from a line that has no quoted hash.

    Args:
        line: One line of the recipe.

    Returns:
        The line without its comment.

    The recipe's own comments sit on their own lines. This handles the
    trailing case anyway, and only outside quotes, so a hash inside a value
    survives.
    """
    out: list[str] = []
    quote = ""
    for character in line:
        if quote:
            out.append(character)
            if character == quote:
                quote = ""
            continue
        if character in "\"'":
            quote = character
            out.append(character)
            continue
        if character == "#":
            break
        out.append(character)
    return "".join(out)


def parse_scalar(text: str) -> object:
    """Convert a scalar to a Python value.

    Args:
        text: The scalar as written.

    Returns:
        A string, an integer, or a bool.
    """
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?[0-9]+", text):
        return int(text)
    return text


def parse_block(lines: list[str], start: int, indent: int) -> tuple[object, int]:
    """Parse one indented block.

    Args:
        lines: Every line of the file.
        start: Index of the first line of this block.
        indent: Column the block's keys or dashes begin at.

    Returns:
        The parsed value, and the index of the first line after the block.

    Raises:
        RecipeError: on any construct this reader does not support.
    """
    mapping: dict[str, object] = {}
    sequence: list[object] = []
    index = start

    while index < len(lines):
        raw = lines[index]
        if not raw.strip() or raw.lstrip().startswith("#"):
            index += 1
            continue

        current = len(raw) - len(raw.lstrip())
        if current < indent:
            break
        if current > indent:
            raise RecipeError(
                f"line {index + 1}: unexpected indent, "
                f"expected {indent} and found {current}"
            )

        body = strip_comment(raw).strip()

        if body.startswith("- "):
            item = body[2:].strip()
            if ":" in item and not item.startswith(("http", "\"", "'")):
                # A sequence entry that is itself a mapping, written on the
                # same line as the dash. Re-read it as a nested block.
                nested_lines = [" " * (indent + 2) + item]
                consumed = index + 1
                while consumed < len(lines):
                    following = lines[consumed]
                    if not following.strip():
                        consumed += 1
                        continue
                    if len(following) - len(following.lstrip()) <= indent:
                        break
                    nested_lines.append(following)
                    consumed += 1
                value, _ = parse_block(nested_lines, 0, indent + 2)
                sequence.append(value)
                index = consumed
                continue
            sequence.append(parse_scalar(item))
            index += 1
            continue

        if body == "-":
            raise RecipeError(f"line {index + 1}: a bare dash is not supported")

        if ":" not in body:
            raise RecipeError(f"line {index + 1}: expected a key, found {body!r}")

        key, _, rest = body.partition(":")
        key = key.strip()
        rest = rest.strip()

        if rest in ("|", ">", "|-", ">-", "|+", ">+"):
            # A block scalar. Its content is skipped rather than read: this
            # gate has no opinion about the build script's text.
            index += 1
            while index < len(lines):
                following = lines[index]
                if following.strip() and (
                    len(following) - len(following.lstrip()) <= indent
                ):
                    break
                index += 1
            mapping[key] = "<block scalar>"
            continue

        if rest:
            mapping[key] = parse_scalar(rest)
            index += 1
            continue

        # A nested block. Find its indent from the first non-empty line.
        probe = index + 1
        while probe < len(lines) and (
            not lines[probe].strip() or lines[probe].lstrip().startswith("#")
        ):
            probe += 1
        if probe >= len(lines):
            mapping[key] = {}
            index = probe
            continue
        child_indent = len(lines[probe]) - len(lines[probe].lstrip())
        if child_indent <= indent:
            mapping[key] = {}
            index = probe
            continue
        value, index = parse_block(lines, probe, child_indent)
        mapping[key] = value

    if mapping and sequence:
        raise RecipeError(
            f"line {start + 1}: a block holds both keys and sequence entries"
        )
    return (sequence if sequence else mapping), index


def read_recipe(path: Path) -> dict:
    """Read the recipe into nested dictionaries and lists.

    Args:
        path: The recipe file.

    Returns:
        The parsed document.

    Raises:
        SystemExit: if the file is missing or cannot be read as expected.
    """
    if not path.is_file():
        raise SystemExit(
            f"check_recipe: {path.relative_to(REPO_ROOT)} is missing. The "
            "recipe belongs at conda.recipe/recipe.yaml, which is where "
            "rattler-build looks by default."
        )
    return parse_recipe(path.read_text(encoding="utf-8"))


def parse_recipe(text: str) -> dict:
    """Read recipe text into nested dictionaries and lists.

    Args:
        text: The recipe as written.

    Returns:
        The parsed document.

    Raises:
        SystemExit: if it cannot be read as the expected shape.
    """
    try:
        document, _ = parse_block(text.splitlines(), 0, 0)
    except RecipeError as exc:
        raise SystemExit(f"check_recipe: cannot read the recipe: {exc}")
    if not isinstance(document, dict):
        raise SystemExit("check_recipe: the recipe is not a mapping")
    return document


# -----------------------------------------------------------------------------
# The checks
# -----------------------------------------------------------------------------


def read_single(relative: str, pattern: re.Pattern) -> str | None:
    """Read a value that must appear exactly once in a file.

    Args:
        relative: Repository relative path.
        pattern: A pattern with one capturing group.

    Returns:
        The captured value, or None when it does not appear exactly once.
    """
    path = REPO_ROOT / relative
    if not path.is_file():
        return None
    found = pattern.findall(path.read_text(encoding="utf-8"))
    if len(found) != 1:
        return None
    return found[0]


def commit_exists(revision: str) -> bool:
    """Report whether a revision names a commit in this repository.

    Args:
        revision: A full commit SHA.

    Returns:
        True when git resolves it to a commit that this clone holds.
    """
    done = subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )
    return done.returncode == 0


def get(document: dict, *path: str) -> object:
    """Read a nested value, returning None when any step is missing.

    Args:
        document: The parsed recipe.
        path: Keys to follow, in order.

    Returns:
        The value, or None.
    """
    current: object = document
    for key in path:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def check(document: dict) -> list[str]:
    """Run every check against a parsed recipe.

    Args:
        document: The parsed recipe.

    Returns:
        A list of problems, empty when the recipe is consistent.
    """
    problems: list[str] = []

    version = get(document, "context", "version")
    mojo_version = get(document, "context", "mojo_version")

    if not isinstance(version, str):
        problems.append("context.version is missing or is not a string")
    else:
        for relative, pattern in VERSION_SOURCES.items():
            declared = read_single(relative, pattern)
            if declared is None:
                problems.append(
                    f"{relative} does not declare a version exactly once, so "
                    "the recipe's version cannot be checked against it"
                )
            elif declared != version:
                problems.append(
                    f"context.version is {version!r} and {relative} says "
                    f"{declared!r}"
                )

    if not isinstance(mojo_version, str):
        problems.append("context.mojo_version is missing or is not a string")
    else:
        for relative, pattern in COMPILER_SOURCES.items():
            declared = read_single(relative, pattern)
            if declared is None:
                problems.append(
                    f"{relative} does not pin the compiler exactly once, so "
                    "the recipe's pin cannot be checked against it"
                )
            elif declared != mojo_version:
                problems.append(
                    f"context.mojo_version is {mojo_version!r} and "
                    f"{relative} pins {declared!r}"
                )

    if get(document, "package", "name") != "knap":
        problems.append("package.name is not 'knap'")
    if get(document, "package", "version") != "${{ version }}":
        problems.append("package.version does not reference context.version")

    source = document.get("source")
    if not isinstance(source, list) or not source:
        problems.append("source is missing or is not a list")
    else:
        entry = source[0]
        if not isinstance(entry, dict):
            problems.append("the first source entry is not a mapping")
        else:
            revision = entry.get("rev")
            if isinstance(revision, int):
                # A commit SHA made only of digits reads as a number, in
                # this reader and in a real YAML parser alike. It is a one
                # in a hundred million shape and the fix is a quoted value,
                # so say that rather than reporting a malformed SHA.
                problems.append(
                    "source.rev parsed as a number. A commit SHA made only "
                    "of digits has to be quoted."
                )
            elif not isinstance(revision, str) or not SHA_PATTERN.match(
                revision
            ):
                problems.append(
                    "source.rev is not a full forty character commit SHA. A "
                    "branch or a tag can move; a SHA cannot."
                )
            elif not commit_exists(revision):
                problems.append(
                    f"source.rev {revision} is not a commit in this "
                    "repository. Update it as part of preparing a release."
                )
            url = entry.get("git")
            repository = get(document, "about", "repository")
            if url != repository:
                problems.append(
                    f"source.git is {url!r} and about.repository is "
                    f"{repository!r}; they should name the same repository"
                )

    number = get(document, "build", "number")
    if not isinstance(number, int) or number < 0:
        problems.append("build.number is missing or is not a whole number")

    pin = f"mojo-compiler =={mojo_version}" if mojo_version else None
    pin_template = "mojo-compiler ==${{ mojo_version }}"
    for section in ("build", "host", "run"):
        entries = get(document, "requirements", section)
        if not isinstance(entries, list) or not entries:
            problems.append(f"requirements.{section} is missing or empty")
            continue
        if pin_template not in entries and (pin is None or pin not in entries):
            problems.append(
                f"requirements.{section} does not pin the compiler exactly. "
                "A precompiled Mojo package is tied to the compiler that "
                "produced it, so a range would be a promise it cannot keep."
            )

    tests = document.get("tests")
    if not isinstance(tests, list) or not tests:
        problems.append("tests is missing or empty")
    else:
        named = get(tests[0], "files", "recipe") if isinstance(
            tests[0], dict
        ) else None
        if not isinstance(named, list) or not named:
            problems.append(
                "the test section names no files, so nothing from the recipe "
                "directory reaches the test environment"
            )
        else:
            for name in named:
                if not (RECIPE.parent / str(name)).is_file():
                    problems.append(
                        f"the test section names {name!r}, which is not next "
                        "to the recipe"
                    )

    licence = get(document, "about", "license")
    if licence != "EUPL-1.2":
        problems.append(f"about.license is {licence!r}, expected 'EUPL-1.2'")
    licence_file = get(document, "about", "license_file")
    if not isinstance(licence_file, str):
        problems.append("about.license_file is missing")
    elif not (REPO_ROOT / licence_file).is_file():
        problems.append(
            f"about.license_file names {licence_file!r}, which is not at the "
            "repository root where the git source puts it"
        )

    maintainers = get(document, "extra", "maintainers")
    if not isinstance(maintainers, list) or not maintainers:
        problems.append("extra.maintainers is missing or empty")

    return problems


# -----------------------------------------------------------------------------
# Self test
#
# The M0 standard requires every gate to be observed rejecting a planted
# violation rather than assumed to work. This does that in memory, against
# the real recipe, so it needs no fixture files and cannot drift away from
# the file it is supposed to be checking.
# -----------------------------------------------------------------------------

SELFTEST_CASES = [
    (
        "a branch name instead of a commit SHA",
        "rev: eebb252a41a6416bd73e1c300d5b3e0551e3e733",
        "rev: main",
    ),
    (
        "a well formed SHA that is not a commit here",
        "rev: eebb252a41a6416bd73e1c300d5b3e0551e3e733",
        'rev: "0000000000000000000000000000000000000000"',
    ),
    (
        "a version that disagrees with CITATION.cff",
        'version: "1.0.0"\n  mojo_version:',
        'version: "1.0.1"\n  mojo_version:',
    ),
    (
        "a compiler pin that disagrees with pixi.toml",
        'mojo_version: "1.0.0"',
        'mojo_version: "1.0.1"',
    ),
    (
        "a test file that is not next to the recipe",
        "- smoke.mojo",
        "- nosuch.mojo",
    ),
    (
        "a licence file that does not exist",
        "license_file: LICENSE",
        "license_file: COPYING",
    ),
    (
        "an empty maintainer list",
        "  maintainers:\n    - olaflaitinen",
        "  maintainers: []",
    ),
]


def selftest() -> int:
    """Plant each violation in turn and confirm the gate rejects it.

    Returns:
        0 when every violation is rejected and the unmodified recipe is
        accepted, 1 otherwise.
    """
    original = RECIPE.read_text(encoding="utf-8")
    failures = 0

    if check(parse_recipe(original)):
        print("  FAIL  the unmodified recipe was rejected")
        failures += 1
    else:
        print("  PASS  accepts the real recipe")

    for label, before, after in SELFTEST_CASES:
        if original.count(before) != 1:
            print(f"  FAIL  {label}: the anchor text is not in the recipe")
            failures += 1
            continue
        planted = original.replace(before, after)
        if check(parse_recipe(planted)):
            print(f"  PASS  rejects {label}")
        else:
            print(f"  FAIL  accepts {label}")
            failures += 1

    if failures:
        print(f"check_recipe: {failures} self test failures")
        return 1
    print("check_recipe: the gate rejects every planted violation")
    return 0


def main() -> int:
    """Check the recipe and report what is wrong with it."""
    if "--selftest" in sys.argv[1:]:
        return selftest()

    document = read_recipe(RECIPE)
    problems = check(document)

    if problems:
        print("check_recipe: the conda recipe is not ready")
        for problem in problems:
            print(f"  {problem}")
        return 1

    version = get(document, "context", "version")
    mojo_version = get(document, "context", "mojo_version")
    source = document["source"][0]
    print(
        f"check_recipe: knap {version} against Mojo {mojo_version}, "
        f"source {source['rev'][:12]}, recipe consistent."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/check_recipe.py
# =============================================================================
