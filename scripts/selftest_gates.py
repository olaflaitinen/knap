# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/selftest_gates.py
# Purpose     : Proves each standards gate rejects a deliberately planted
#               violation, and accepts the matching clean control.
# Stage       : Repository standard enforcement, see docs/STYLE.md
# Depends on  : The four gate scripts in this directory. Standard library only.
# Invariants  : Every planted file is written under a temporary directory that
#               is removed on every exit path, including failure.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Self test for the Knap standards gates.

A gate that has never been observed failing is not known to work. A check that
silently passes everything looks exactly like a check that passes because the
repository is clean, and the difference only surfaces on the day it matters.

This script closes that gap. For each gate it writes a file carrying one
specific planted violation, asserts the gate rejects it, then writes a clean
control file and asserts the gate accepts that. Both halves are needed: a gate
that rejects everything is as useless as one that rejects nothing.

    python scripts/selftest_gates.py

Exit status is 0 when every gate behaved correctly and 1 otherwise.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Planted files must live inside the repository, because the gates resolve
# paths relative to the repository root. This directory is git ignored and is
# removed on every exit path.
SANDBOX = REPO_ROOT / ".gate_selftest"

# The em-dash is built from its code point. Writing the character directly
# would make this file fail the very gate it is testing.
EM_DASH = chr(0x2014)

# A banner that satisfies check_file_banners, with the File field left to be
# filled in per planted file.
BANNER_TEMPLATE = """\
# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : {path}
# Purpose     : Temporary fixture written by scripts/selftest_gates.py.
# Stage       : Standards gate self test
# Depends on  : Nothing.
# Invariants  : Deleted before this script exits.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""

FOOTER_TEMPLATE = """\
# =============================================================================
# End of file: {path}
# =============================================================================
"""

# A Markdown document that satisfies check_md_headers in full.
CLEAN_MARKDOWN = """\
<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Self Test Fixture

| Field | Value |
| --- | --- |
| Document | `{path}` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 0.1.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | 0009-0006-5184-0810 |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-07 |
| Updated | 2026-09-07 |
| Licence | EUPL-1.2 |

---

## Body

Temporary fixture written by the standards gate self test.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [README.md](../README.md) |
| Next | [README.md](../README.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-07 |

Knap is licensed under the European Union Public Licence 1.2.

<!-- End of document: {path} -->
"""


@dataclass(frozen=True)
class Case:
    """One gate, one planted violation, and one clean control.

    Attributes:
        gate: Script name under scripts/ that should judge the files.
        label: Human readable description of the planted violation.
        bad_name: File name to write the violating content to.
        bad_text: Content that must be rejected.
        good_name: File name to write the conforming content to.
        good_text: Content that must be accepted.
    """

    gate: str
    label: str
    bad_name: str
    bad_text: str
    good_name: str
    good_text: str


def build_cases() -> list[Case]:
    """Construct the four cases the M0 gate requires to be demonstrated.

    Each case pairs a violation with a control that differs only in the one
    property under test. Keeping the difference minimal is what makes a pass
    meaningful: if the control also failed, the gate would be rejecting the
    fixture rather than the violation.
    """
    bad_py = ".gate_selftest/planted_em_dash.py"
    good_py = ".gate_selftest/clean_module.py"
    nobanner_py = ".gate_selftest/planted_no_banner.py"
    nospdx_py = ".gate_selftest/planted_no_spdx.py"
    bad_md = ".gate_selftest/planted_no_footer.md"
    good_md = ".gate_selftest/clean_document.md"

    clean_py = (
        BANNER_TEMPLATE.format(path=good_py)
        + '"""Temporary fixture written by the standards gate self test."""\n'
        + FOOTER_TEMPLATE.format(path=good_py)
    )

    # Violation 1: an em-dash in a comment. Everything else conforms.
    em_dash_py = (
        BANNER_TEMPLATE.format(path=bad_py)
        + '"""Temporary fixture written by the standards gate self test."""\n'
        + f"\n# This comment contains an em-dash {EM_DASH} which is banned.\n"
        + FOOTER_TEMPLATE.format(path=bad_py)
    )

    # Violation 2: no banner at all, though the SPDX line is present so that
    # the banner gate is what rejects it rather than the SPDX gate.
    no_banner_py = (
        "# SPDX-License-Identifier: EUPL-1.2\n"
        '"""Temporary fixture with no banner."""\n'
    )

    # Violation 3: a full banner with the SPDX line removed.
    no_spdx_py = (
        BANNER_TEMPLATE.format(path=nospdx_py).replace(
            "# SPDX-License-Identifier: EUPL-1.2\n", ""
        )
        + '"""Temporary fixture with no SPDX identifier."""\n'
        + FOOTER_TEMPLATE.format(path=nospdx_py)
    )

    # Violation 4: a Markdown document with its document control footer and
    # end marker removed.
    clean_md = CLEAN_MARKDOWN.format(path=good_md)
    no_footer_md = CLEAN_MARKDOWN.format(path=bad_md).split(
        "## Document control"
    )[0]

    return [
        Case(
            gate="lint_style.py",
            label="em-dash in a source comment",
            bad_name=bad_py,
            bad_text=em_dash_py,
            good_name=good_py,
            good_text=clean_py,
        ),
        Case(
            gate="check_file_banners.py",
            label="source file with no banner",
            bad_name=nobanner_py,
            bad_text=no_banner_py,
            good_name=good_py,
            good_text=clean_py,
        ),
        Case(
            gate="check_md_headers.py",
            label="Markdown document with no footer",
            bad_name=bad_md,
            bad_text=no_footer_md,
            good_name=good_md,
            good_text=clean_md,
        ),
        Case(
            gate="check_spdx.py",
            label="source file with no SPDX line",
            bad_name=nospdx_py,
            bad_text=no_spdx_py,
            good_name=good_py,
            good_text=clean_py,
        ),
    ]


def run_gate(gate: str, relative_path: str) -> tuple[int, str]:
    """Run one gate against one explicit path and return status and output.

    Explicit paths are used rather than the default git listing so that each
    case is isolated: a violation planted for one gate cannot make a different
    gate's result ambiguous.
    """
    completed = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / gate), relative_path],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.returncode, completed.stdout + completed.stderr


def write(relative_path: str, text: str) -> None:
    """Write one planted or control file inside the sandbox."""
    absolute = REPO_ROOT / relative_path
    absolute.parent.mkdir(parents=True, exist_ok=True)
    absolute.write_text(text, encoding="utf-8")


def main() -> int:
    """Plant each violation, confirm rejection, confirm the control passes."""
    failures = 0
    try:
        SANDBOX.mkdir(exist_ok=True)
        for case in build_cases():
            write(case.bad_name, case.bad_text)
            write(case.good_name, case.good_text)

            bad_status, bad_output = run_gate(case.gate, case.bad_name)
            good_status, good_output = run_gate(case.gate, case.good_name)

            rejected = bad_status != 0
            accepted = good_status == 0

            if rejected and accepted:
                print(f"  PASS  {case.gate:<24} rejects {case.label}")
            else:
                failures += 1
                print(f"  FAIL  {case.gate:<24} {case.label}")
                if not rejected:
                    print("        planted violation was NOT rejected")
                    print(f"        gate said: {bad_output.strip()[:200]}")
                if not accepted:
                    print("        clean control was wrongly rejected")
                    print(f"        gate said: {good_output.strip()[:200]}")
    finally:
        shutil.rmtree(SANDBOX, ignore_errors=True)

    if failures:
        sys.stdout.flush()
        print(
            f"selftest_gates: {failures} gate(s) did not behave correctly.",
            file=sys.stderr,
        )
        return 1

    print("selftest_gates: all gates reject their violation and accept the control.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/selftest_gates.py
# =============================================================================
