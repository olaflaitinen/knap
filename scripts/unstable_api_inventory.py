# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/unstable_api_inventory.py
# Purpose     : Builds the inventory of unstable standard library APIs that
#               Knap depends on, from the compiler's own JSON diagnostics.
# Stage       : Repository standard enforcement, see docs/ARCHITECTURE.md
# Depends on  : The pinned Mojo compiler. Python standard library only.
# Invariants  : This script reports; it never fails the build. Eliminating
#               unstable API use is not achievable today, so the goal is
#               visible exposure, not a clean result.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Unstable API inventory for Knap.

Mojo standard library APIs are unstable unless explicitly marked stable, and
the stable set is currently small. Knap therefore depends on unstable APIs
whether it wants to or not, and section 3.4 of the project brief is explicit
that trying to eliminate them is not achievable today. What is achievable is
making the exposure visible, so that a breaking change in a future toolchain
maps to a known list rather than a surprise.

Two facts about the compiler shape this script, both verified against Mojo
1.0.0 rather than assumed:

  * Diagnostics with --diagnostic-format json are JSON Lines, one object per
    line, not a single JSON document.
  * --Werror and --warn-on-unstable-apis cannot be combined. Together they
    turn every unstable API use into an error and the build fails. The
    inventory build therefore never passes --Werror, and CI runs it as a
    separate reporting job.

Usage:

    python scripts/unstable_api_inventory.py
    python scripts/unstable_api_inventory.py --format json

Exit status is 0 whenever the compiler ran, regardless of how many unstable
APIs were found.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# The compiler shipped by the pinned environment. uv places it here; the pixi
# environment places it elsewhere, so the path is overridable.
DEFAULT_MOJO = REPO_ROOT / ".venv" / "bin" / "mojo"

# "use of unstable API '<name>'" is the only warning this script consumes.
UNSTABLE_PATTERN = re.compile(r"use of unstable API '([^']+)'")


def discover_targets() -> list[str]:
    """Return every Mojo file worth compiling for the inventory.

    Only files that can be built as programs are useful here, because the
    compiler reports unstable API use at the point of use. Library modules
    are reached transitively through the tests that exercise them, which is
    also the honest measure: an API Knap never calls is not exposure.
    """
    targets = sorted(
        str(path.relative_to(REPO_ROOT))
        for path in (REPO_ROOT / "tests").glob("*.mojo")
    )
    return targets


def collect_diagnostics(mojo: Path, target: str) -> list[dict]:
    """Compile one target and return its parsed JSON Lines diagnostics.

    Failure modes: a target that does not compile yields the compiler's own
    error diagnostics, which are returned unfiltered so the caller can report
    them. A missing compiler is a hard error, since silently reporting an
    empty inventory would understate the exposure.
    """
    if not mojo.exists():
        raise SystemExit(
            f"unstable_api_inventory: no Mojo compiler at {mojo}. "
            "Pass --mojo to point at one."
        )

    completed = subprocess.run(
        [
            str(mojo),
            "build",
            "--warn-on-unstable-apis",
            "--diagnostic-format",
            "json",
            # Tests import the library under src, so the include path
            # is needed for them to compile at all.
            "-I",
            "src",
            "-o",
            "/dev/null",
            target,
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    records: list[dict] = []
    for line in completed.stderr.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            # The compiler emits a Crashpad notice on some hosts. It is not
            # a diagnostic and it is not JSON, so it is skipped silently.
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records


def summarise(
    records_by_target: dict[str, list[dict]]
) -> tuple[Counter, dict[str, set[str]]]:
    """Reduce raw diagnostics to counts per API and the files that use each.

    Occurrences are counted rather than deduplicated per line, because a
    single expression can legitimately touch one unstable API several times.
    The count indicates weight of dependence, not distinct call sites.
    """
    counts: Counter = Counter()
    users: dict[str, set[str]] = defaultdict(set)

    for target, records in records_by_target.items():
        for record in records:
            if record.get("kind") != "warning":
                continue
            match = UNSTABLE_PATTERN.search(record.get("message", ""))
            if not match:
                continue
            api = match.group(1)
            counts[api] += 1
            users[api].add(target)
    return counts, users


def render_markdown(
    counts: Counter, users: dict[str, set[str]], targets: list[str]
) -> str:
    """Render the inventory as the Markdown table docs/ARCHITECTURE.md holds.

    The "what breaks" column is deliberately left as a prompt rather than
    guessed, because only a human who knows the call site can say what a
    change to that API would cost.
    """
    lines: list[str] = []
    total = sum(counts.values())
    lines.append(
        f"Compiled {len(targets)} target(s); {total} unstable API uses "
        f"across {len(counts)} distinct APIs."
    )
    lines.append("")
    lines.append("| Unstable API | Uses | Used by | What breaks if it changes |")
    lines.append("| --- | --- | --- | --- |")
    for api, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        where = ", ".join(sorted(users[api]))
        lines.append(f"| `{api}` | {count} | {where} | |")
    return "\n".join(lines)


def main() -> int:
    """Compile every target and report the unstable APIs they depend on."""
    parser = argparse.ArgumentParser(
        description="Inventory the unstable Mojo APIs that Knap depends on."
    )
    parser.add_argument(
        "--mojo",
        type=Path,
        default=DEFAULT_MOJO,
        help=f"Path to the Mojo compiler. Defaults to {DEFAULT_MOJO}.",
    )
    parser.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="Output format. Defaults to markdown.",
    )
    parser.add_argument(
        "targets",
        nargs="*",
        help="Mojo files to compile. Defaults to every file in tests/.",
    )
    arguments = parser.parse_args()

    targets = arguments.targets or discover_targets()
    if not targets:
        print(
            "unstable_api_inventory: no Mojo targets found; nothing to "
            "report yet."
        )
        return 0

    records_by_target = {
        target: collect_diagnostics(arguments.mojo, target)
        for target in targets
    }
    counts, users = summarise(records_by_target)

    if arguments.format == "json":
        payload = {
            "targets": targets,
            "total_uses": sum(counts.values()),
            "apis": {
                api: {"uses": count, "used_by": sorted(users[api])}
                for api, count in counts.items()
            },
        }
        json.dump(payload, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    print(render_markdown(counts, users, targets))
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/unstable_api_inventory.py
# =============================================================================
