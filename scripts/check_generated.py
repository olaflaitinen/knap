# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/check_generated.py
# Purpose     : Re-runs every generator and fails when a committed generated
#               file no longer matches its generator's output.
# Stage       : Repository standard enforcement, see docs/ARCHITECTURE.md
# Depends on  : extract_patterns.py, gen_unicode_tables.py, and their inputs.
# Invariants  : This never rewrites a file. It only reports drift, so a
#               failing build is fixed by re-running the generator on
#               purpose rather than by a check quietly repairing itself.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Verify that committed generated files are current.

Four files in this repository are generated and committed: the pattern
constants, the Unicode tables, the API reference, and the bill of materials.
Committing them keeps the build free of a network dependency and makes each
one reviewable in a diff, but it also creates a way for the committed copy
to drift from what the generator would produce now, after a dependency
upgrade.

Drift matters here more than in most projects. If the pre-tokenization
pattern changes upstream and the committed constant does not, Knap keeps
matching a pattern the reference implementation no longer uses, and the
divergence appears as mysteriously wrong tokens rather than as a build
failure.

Each generator implements its own check mode, because only the generator
knows which parts of its output are meaningful. The generation date, for
instance, changes on every run and is deliberately excluded.

    python scripts/check_generated.py

Exit status is 0 when every generated file is current.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Each entry is a generator and the file it owns. The generator is invoked
# with --check, which must exit non-zero when its committed output is stale.
GENERATORS = (
    ("scripts/extract_patterns.py", "src/knap/pretokenize/pattern.mojo"),
    (
        "scripts/gen_unicode_tables.py",
        "src/knap/pretokenize/unicode_tables.mojo",
    ),
    ("scripts/gen_api_reference.py", "docs/API.md"),
    ("scripts/gen_sbom.py", "sbom.cdx.json"),
)


def run_check(generator: str) -> tuple[bool, str]:
    """Run one generator in check mode.

    Args:
        generator: Repository relative path to the generator.

    Returns:
        Whether the committed output is current, and the generator's output.

    A generator that cannot run at all, because a dependency is missing, is
    reported as a failure rather than as a pass. Silently skipping the check
    would defeat its purpose on exactly the machine where it matters, which
    is a continuous integration runner with an unexpected environment.
    """
    completed = subprocess.run(
        [sys.executable, str(REPO_ROOT / generator), "--check"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    output = (completed.stdout + completed.stderr).strip()
    return completed.returncode == 0, output


def main() -> int:
    """Check every generated file and report any that has drifted."""
    stale = 0
    print("check_generated: verifying committed generated files")

    for generator, target in GENERATORS:
        path = REPO_ROOT / target
        if not path.exists():
            print(f"  MISSING  {target}")
            print(f"           run 'python {generator}' to create it")
            stale += 1
            continue

        current, output = run_check(generator)
        if current:
            print(f"  CURRENT  {target}")
        else:
            stale += 1
            print(f"  STALE    {target}")
            for line in output.splitlines():
                print(f"           {line}")

    if stale:
        sys.stdout.flush()
        print(
            f"check_generated: {stale} generated file(s) are stale or "
            "missing.",
            file=sys.stderr,
        )
        return 1

    print(f"check_generated: {len(GENERATORS)} generated files are current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/check_generated.py
# =============================================================================
