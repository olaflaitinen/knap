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

# A token in the build script that names a path in this repository, rather
# than one inside the installed package. The leading directory is what tells
# them apart: package paths are all written under ${PREFIX}.
SOURCE_PATH_PATTERN = re.compile(
    r"(?<![\w/$}])(?:src|cli|tests|bench|scripts|docs)/[\w./-]+"
)

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


def script_blocks(text: str) -> list[str]:
    """Return the body of every `content: |` block in the recipe.

    Args:
        text: The recipe file, as one string.

    Returns:
        One entry per literal block, each still indented.

    The reader in this file parses the subset of YAML the recipe needs and
    deliberately does not implement literal block scalars, so the scripts are
    taken from the raw text instead. Reading them from the raw text is also
    the honest way round: what matters is what bash will run, not what a
    partial parser made of it.
    """
    lines = text.splitlines()
    blocks: list[str] = []
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if stripped in ("content: |", "content: |-"):
            marker_indent = len(lines[index]) - len(lines[index].lstrip())
            body: list[str] = []
            index += 1
            while index < len(lines):
                line = lines[index]
                if line.strip() and (
                    len(line) - len(line.lstrip()) <= marker_indent
                ):
                    break
                body.append(line)
                index += 1
            blocks.append("\n".join(body))
            continue
        index += 1
    return blocks


def build_script_paths(script: str) -> list[str]:
    """Return the repository paths a recipe script reads.

    Args:
        script: One script from the recipe, as one string.

    Returns:
        Every token that names a path in this repository, in order and
        without duplicates.

    Tokens are matched rather than commands parsed, because parsing bash to
    find an argument is a great deal of machinery for a question a regular
    expression answers. A path is recognised by its leading directory, which
    is the set of directories this repository has, so a token like
    `${PREFIX}/bin/knap` is correctly ignored: it names a path in the
    installed package rather than in the source tree.
    """
    found: list[str] = []
    for match in SOURCE_PATH_PATTERN.finditer(script):
        token = match.group(0)
        if token not in found:
            found.append(token)
    return found


def path_exists_at(revision: str, path: str) -> bool:
    """Report whether a path exists in the tree of a given commit.

    Args:
        revision: A commit this clone holds.
        path: A repository relative path.

    Returns:
        True when the commit's tree contains it, as a file or a directory.
    """
    done = subprocess.run(
        ["git", "cat-file", "-e", f"{revision}:{path}"],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )
    return done.returncode == 0


def is_shallow() -> bool:
    """Report whether this clone has a truncated history.

    Returns:
        True when git says the repository is shallow.

    A shallow clone cannot answer whether a commit exists, only whether it
    is inside the slice that was fetched. Continuous integration checks out
    one commit by default, so this distinction is the difference between a
    useful failure and a confusing one.
    """
    done = subprocess.run(
        ["git", "rev-parse", "--is-shallow-repository"],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    return done.returncode == 0 and done.stdout.strip() == "true"


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


def check(document: dict, raw: str) -> list[str]:
    """Run every check against a parsed recipe.

    Args:
        document: The parsed recipe.
        raw: The recipe file as text, for the parts a subset parser does not
            reach, notably the literal block scripts. Taking it as an
            argument rather than reading the file is what lets the self test
            plant a violation in a copy.

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
                if is_shallow():
                    problems.append(
                        f"source.rev {revision} cannot be verified because "
                        "this is a shallow clone. Fetch the full history, "
                        "which in a workflow means fetch-depth: 0."
                    )
                else:
                    problems.append(
                        f"source.rev {revision} is not a commit in this "
                        "repository. Update it as part of preparing a "
                        "release."
                    )
            else:
                # The check this gate was missing, and the reason it was
                # added. The recipe pins one commit and its build script is
                # edited in another, so the two drift apart and nothing
                # notices until somebody builds the package. That is exactly
                # what happened: shell completions were added to the build
                # script months after the pinned commit, and the build died
                # on `cp cli/completions/knap.bash`.
                for script in script_blocks(raw):
                    for path in build_script_paths(script):
                        if not path_exists_at(revision, path):
                            problems.append(
                                f"a recipe script reads {path}, which does "
                                f"not exist at source.rev {revision[:12]}. "
                                "The recipe pins a commit older than the "
                                "script it runs."
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

def revision_anchor(text: str) -> str:
    """Return the recipe's `rev:` line, whatever commit it currently names.

    Args:
        text: The recipe file as text.

    Returns:
        The line, for the self test to replace.

    Read rather than written down. The two revision cases used to hardcode
    the SHA that happened to be in the recipe when they were written, so
    updating the recipe for a release silently disarmed both of them. A self
    test that stops testing when the file it tests is edited is the failure
    it exists to prevent.
    """
    found = re.search(r"^\s*rev: \S+$", text, re.MULTILINE)
    return found.group(0).strip() if found else "rev: "


def selftest_cases(text: str) -> list[tuple[str, str, str]]:
    """Build the planted violations against the recipe as it stands.

    Args:
        text: The recipe file as text.

    Returns:
        Label, anchor, and replacement for each planted violation.
    """
    revision = revision_anchor(text)
    return [
    (
        "a branch name instead of a commit SHA",
        revision,
        "rev: main",
    ),
    (
        "a well formed SHA that is not a commit here",
        revision,
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
    (
        # The one this gate was missing. A path added to the build script
        # after the pinned commit builds fine on a developer's tree and dies
        # in the package build, which is how the shell completions broke it.
        "a build script path that is not in the pinned commit",
        "cp cli/completions/knap.bash",
        "cp cli/completions/nosuch.bash",
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

    if check(parse_recipe(original), original):
        print("  FAIL  the unmodified recipe was rejected")
        failures += 1
    else:
        print("  PASS  accepts the real recipe")

    for label, before, after in selftest_cases(original):
        if original.count(before) != 1:
            print(f"  FAIL  {label}: the anchor text is not in the recipe")
            failures += 1
            continue
        planted = original.replace(before, after)
        if check(parse_recipe(planted), planted):
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
    problems = check(document, RECIPE.read_text(encoding="utf-8"))

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
