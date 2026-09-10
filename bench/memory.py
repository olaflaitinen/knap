# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/memory.py
# Purpose     : Measures peak resident memory per stage, with the empty
#               runtime as the control, and against tiktoken.
# Stage       : Benchmarking. See docs/BENCHMARKS.md
# Depends on  : bench/mem_probe.mojo, the Mojo compiler, tiktoken.
# Invariants  : One child process per stage, so a high water mark belongs
#               to one thing. The control is always reported.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Peak resident memory, per stage, with the control that makes it readable.

Throughput is measured everywhere and memory is measured almost nowhere,
which is odd, because on a serving machine the number of tokenizers you can
hold is a harder limit than how fast one of them runs.

Two rules make these figures mean something.

**One stage per process.** Peak resident memory is a high water mark. A
process that loads a vocabulary and then encodes reports one number for
both, so each stage runs in its own child and `os.wait4` reads that child's
peak rather than a running maximum.

**The control is always reported.** An empty Mojo program and an empty
Python interpreter are measured in the same run. Without them a reader
cannot tell how much of a figure belongs to the library and how much to the
language, and the first draft of this measurement was off by a factor of
twenty for exactly that reason.

    python bench/memory.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROBE = REPO_ROOT / "bench" / "mem_probe.mojo"
CORPUS = REPO_ROOT / "bench" / "corpus" / "mixed.txt"
VOCAB = REPO_ROOT / "tests" / "fixtures" / "vocabs" / "cl100k_base.tiktoken"

# Stage name, and what it adds to the stage before it.
STAGES = [
    ("empty", "the Mojo runtime and nothing else"),
    ("file", "the vocabulary file read into memory"),
    ("vocabulary", "the parsed vocabulary"),
    ("tokenizer", "the vocabulary and the rank table"),
    ("count", "80 MB of input counted"),
    ("encode", "80 MB of input encoded to a list of ids"),
]

# The same stages on the Python side, as source to run with -c.
PYTHON_STAGES = [
    ("empty", "pass", "the Python interpreter and nothing else"),
    (
        "tokenizer",
        "import tiktoken; e = tiktoken.get_encoding('cl100k_base');"
        " e.encode_ordinary('x')",
        "tiktoken with cl100k_base loaded",
    ),
]


def peak_kilobytes(command: list[str]) -> tuple[int, str]:
    """Run a command and return its peak resident memory.

    Args:
        command: The command and its arguments.

    Returns:
        Peak resident set size in kilobytes, and the child's first line of
        output.

    Raises:
        SystemExit: if the child fails, because a stage that did not finish
            has a peak that means nothing.

    `os.wait4` reports the resource usage of one child. `getrusage` with
    RUSAGE_CHILDREN would report a running maximum across every child this
    process has ever reaped, which is the mistake this function exists to
    avoid making.
    """
    child = subprocess.Popen(
        command,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    output = child.stdout.read() if child.stdout else ""
    _, status, usage = os.wait4(child.pid, 0)
    if status != 0:
        raise SystemExit(
            f"memory: {' '.join(command)} exited with status {status}"
        )
    first = output.strip().splitlines()
    return usage.ru_maxrss, first[0] if first else ""


def build(destination: Path) -> Path:
    """Compile the probe.

    Args:
        destination: Where to write the binary.

    Returns:
        The path to it.

    Raises:
        SystemExit: if the compiler is missing or the build fails.
    """
    mojo = REPO_ROOT / ".venv" / "bin" / "mojo"
    if not mojo.exists():
        raise SystemExit(
            "memory: no Mojo compiler at .venv/bin/mojo. Run "
            "'uv sync --group dev' first."
        )
    done = subprocess.run(
        [
            str(mojo),
            "build",
            "-I",
            "src",
            "-I",
            "bench",
            "-o",
            str(destination),
            str(PROBE.relative_to(REPO_ROOT)),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        print(done.stdout)
        print(done.stderr, file=sys.stderr)
        raise SystemExit("memory: the probe did not compile")
    return destination


def main() -> int:
    """Measure every stage and print a table."""
    for required in (CORPUS, VOCAB):
        if not required.exists():
            raise SystemExit(
                f"memory: {required.relative_to(REPO_ROOT)} is missing. Run "
                "the fetch scripts first."
            )

    print("# peak resident memory, one child process per stage")
    print(f"# probe: {PROBE.relative_to(REPO_ROOT)}")

    with tempfile.TemporaryDirectory() as scratch:
        binary = build(Path(scratch) / "mem_probe")

        baseline = 0
        for stage, description in STAGES:
            peak, note = peak_kilobytes([str(binary), stage])
            if stage == "empty":
                baseline = peak
            above = peak - baseline
            print(
                f"MEM name=knap_{stage} kind=peak_rss peak_kb={peak} "
                f"above_control_kb={above} note={note or description}"
            )

    python = REPO_ROOT / ".venv" / "bin" / "python"
    if not python.exists():
        print("# tiktoken not measured: no .venv/bin/python")
        return 0

    baseline = 0
    for stage, source, description in PYTHON_STAGES:
        peak, _ = peak_kilobytes([str(python), "-c", source])
        if stage == "empty":
            baseline = peak
        above = peak - baseline
        print(
            f"MEM name=tiktoken_{stage} kind=peak_rss peak_kb={peak} "
            f"above_control_kb={above} note={description}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: bench/memory.py
# =============================================================================
