# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bindings/python/build.py
# Purpose     : Builds the native extension module from Mojo.
# Stage       : Milestone M6 Track B, Python consumers. See docs/ROADMAP.md
# Depends on  : The pinned Mojo compiler.
# Invariants  : Records the toolchain version beside the built library, so a
#               stale build can be recognised rather than guessed at.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Build the Knap native extension for Python.

One command, because the alternative is a README instruction nobody runs
correctly:

    python bindings/python/build.py

The Mojo ABI is not stable. An extension built against one toolchain is not
valid for another, and nothing detects the mismatch at import time: it either
works or it fails in a way that will not obviously point here. So this writes
a small stamp file naming the toolchain that produced the build, and warns
when it finds an existing build from a different one.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

BINDINGS_DIR = Path(__file__).resolve().parent
REPO_ROOT = BINDINGS_DIR.parent.parent

SOURCE = BINDINGS_DIR / "knap_ext.mojo"
BUILD_DIR = BINDINGS_DIR / "build"
LIBRARY = BUILD_DIR / "knap_ext.so"
STAMP = BUILD_DIR / "build_info.json"


def find_mojo() -> Path:
    """Locate the pinned Mojo compiler.

    Returns:
        Path to the compiler.

    Raises:
        SystemExit: when it cannot be found.
    """
    candidate = REPO_ROOT / ".venv" / "bin" / "mojo"
    if candidate.exists():
        return candidate
    raise SystemExit(
        "build: no Mojo compiler at .venv/bin/mojo. Run 'uv sync "
        "--group dev' from the repository root first."
    )


def toolchain_version(mojo: Path) -> str:
    """Return the compiler's version string.

    Args:
        mojo: Path to the compiler.

    Returns:
        The version line, or the word unknown.
    """
    completed = subprocess.run(
        [str(mojo), "--version"], capture_output=True, text=True, check=False
    )
    return completed.stdout.strip() or "unknown"


def main() -> int:
    """Build the extension and record the toolchain that produced it."""
    mojo = find_mojo()
    version = toolchain_version(mojo)

    if STAMP.exists():
        try:
            previous = json.loads(STAMP.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            previous = {}
        if previous.get("toolchain") not in (None, version):
            print(
                "build: the existing build came from a different toolchain,\n"
                f"       was: {previous.get('toolchain')}\n"
                f"       now: {version}\n"
                "       rebuilding, which is required because the Mojo ABI "
                "is not stable."
            )

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    print(f"build: compiling {SOURCE.relative_to(REPO_ROOT)}")

    completed = subprocess.run(
        [
            str(mojo),
            "build",
            "--emit",
            "shared-lib",
            "-I",
            "src",
            "-o",
            str(LIBRARY),
            str(SOURCE.relative_to(REPO_ROOT)),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit("build: the extension did not compile")

    STAMP.write_text(
        json.dumps(
            {
                "toolchain": version,
                "built": datetime.now(timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
                "source": str(SOURCE.relative_to(REPO_ROOT)),
                "library": str(LIBRARY.relative_to(REPO_ROOT)),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    size = LIBRARY.stat().st_size
    print(f"build: wrote {LIBRARY.relative_to(REPO_ROOT)}, {size} bytes")
    print(f"build: toolchain {version}")
    print(
        "build: import it with 'from knap_py import Tokenizer' once "
        "bindings/python is on the path"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: bindings/python/build.py
# =============================================================================
