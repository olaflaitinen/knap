# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/fuzz/run_fuzz.py
# Purpose     : Long running driver for the differential fuzzer. Shards the
#               work, aggregates results, and keeps diverging inputs.
# Stage       : Differential fuzzing. See docs/CORRECTNESS.md
# Depends on  : The compiled fuzzer, tiktoken, and the pinned Mojo compiler.
# Invariants  : Every shard's seed is recorded, so any reported total can be
#               reproduced shard by shard.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Drive the Knap differential fuzzer for a long run.

The fuzzer itself compares one shard of inputs and exits. This drives many
shards, aggregates what they found, and writes a report that names the exact
tiktoken version and every seed used.

Seed bookkeeping is the point of this script. A fuzzing claim of the form
"ten million strings, zero divergences" is worth nothing unless someone else
can run the same ten million strings, so each shard's seed is deterministic
from the base seed and its index, and all of them are written to the report.

Any input that diverges is saved to corpus_seeds/ as hexadecimal and stays
there permanently, even after the bug is fixed. Those files are the
regression corpus: the fuzzer will eventually stop generating a given shape,
but the case that once failed keeps being checked.

    python tests/fuzz/run_fuzz.py --total 10000000
    python tests/fuzz/run_fuzz.py --total 100000 --sanitize address

Exit status is 0 when every shard passed.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FUZZ_DIR = REPO_ROOT / "tests" / "fuzz"
SEED_DIR = FUZZ_DIR / "corpus_seeds"
# One report per sanitizer mode, so the plain run and the sanitizer run do
# not overwrite each other's evidence.
REPORT_TEMPLATE = "last_run{suffix}.json"

SOURCE = FUZZ_DIR / "fuzz_main.mojo"
VOCABS = REPO_ROOT / "tests" / "fixtures" / "vocabs"

# Seven encodings backed by four files. The name is not enough to find the
# file, so the path is passed to the fuzzer explicitly.
VOCABULARIES = {
    "cl100k_base": VOCABS / "cl100k_base.tiktoken",
    "gpt2": VOCABS / "r50k_base.tiktoken",
    "o200k_base": VOCABS / "o200k_base.tiktoken",
    "o200k_harmony": VOCABS / "o200k_base.tiktoken",
    "p50k_base": VOCABS / "p50k_base.tiktoken",
    "p50k_edit": VOCABS / "p50k_base.tiktoken",
    "r50k_base": VOCABS / "r50k_base.tiktoken",
}

# LeakSanitizer reports the embedded interpreter and the reference
# extension on every sanitizer run, because neither frees its tables before
# the process exits. Those leaks are real and they are not Knap's, which was
# established by experiment rather than by reading stack traces. See
# lsan.supp for the evidence, and asan_solo.mojo for the companion run that
# needs no suppressions at all.
LSAN_SUPPRESSIONS = FUZZ_DIR / "lsan.supp"

# Shards keep any single process short, so a crash loses little work and the
# driver can report progress on a long run.
DEFAULT_SHARD = 250_000


def find_mojo() -> Path:
    """Locate the pinned Mojo compiler.

    Returns:
        Path to the compiler.

    Raises:
        SystemExit: when it cannot be found, since there is nothing useful
            to do without it.
    """
    candidate = REPO_ROOT / ".venv" / "bin" / "mojo"
    if candidate.exists():
        return candidate
    raise SystemExit(
        "run_fuzz: no Mojo compiler at .venv/bin/mojo. Run 'uv sync "
        "--group dev' first."
    )


def build(sanitize: str | None) -> Path:
    """Compile the fuzzer once, optionally under a sanitizer.

    Args:
        sanitize: A sanitizer name, or None for an ordinary build.

    Returns:
        Path to the built binary.

    Raises:
        SystemExit: if compilation fails.

    Building once and running many shards keeps compilation out of the
    measured loop. A sanitizer build is a separate binary because it is
    several times slower and is run over a smaller sample.
    """
    mojo = find_mojo()
    suffix = f".{sanitize}" if sanitize else ""
    output = Path("/tmp") / f"knap_fuzz{suffix}"

    command = [str(mojo), "build", "-I", "src", "-I", "tests/fuzz"]
    if sanitize:
        command += ["--sanitize", sanitize]
    command += ["-o", str(output), str(SOURCE.relative_to(REPO_ROOT))]

    print(f"run_fuzz: building{' with ' + sanitize if sanitize else ''}")
    completed = subprocess.run(
        command, cwd=REPO_ROOT, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        raise SystemExit(
            "run_fuzz: the fuzzer did not compile:\n" + completed.stderr
        )
    return output


def parse_result(text: str) -> dict[str, int]:
    """Extract the machine readable summary from one shard's output.

    Args:
        text: Everything the shard printed.

    Returns:
        The counts it reported, or an empty mapping when no summary was
        found.

    The summary is one line of key equals value pairs, so the driver never
    has to parse the human readable part of the output.
    """
    for line in text.splitlines():
        if not line.startswith("RESULT "):
            continue
        found: dict[str, int] = {}
        for pair in line[len("RESULT "):].split():
            if "=" not in pair:
                continue
            key, _, value = pair.partition("=")
            try:
                found[key] = int(value)
            except ValueError:
                continue
        return found
    return {}


def save_divergence(output: str, encoding: str, seed: int) -> Path | None:
    """Persist a diverging input as a regression seed.

    Args:
        output: The shard's output, holding the hexadecimal input.
        encoding: Which encoding was being fuzzed.
        seed: The shard seed, so the case can be replayed.

    Returns:
        The file written, or None when no hexadecimal line was found.

    Saved even after the bug is fixed. The fuzzer will eventually stop
    producing this shape, and the case that once failed should keep being
    checked regardless.
    """
    hex_line = None
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("hex "):
            hex_line = stripped.split(":", 1)[1].strip()
            break
    if hex_line is None:
        return None

    SEED_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = SEED_DIR / f"{encoding}-seed{seed}-{stamp}.hex"
    path.write_text(hex_line + "\n", encoding="ascii")
    return path


def run_shard(
    binary: Path, seed: int, count: int, encoding: str, sanitize: str | None
) -> tuple[int, dict[str, int], str]:
    """Run one shard and return its exit status, counts, and output.

    Args:
        binary: The built fuzzer.
        seed: This shard's seed.
        count: How many inputs to generate.
        encoding: Which encoding to fuzz.
        sanitize: The sanitizer this binary was built with, or None.

    Returns:
        The process exit status, the counts it reported, and its full
        output.

    The exit status is returned rather than a pass or fail flag, because
    those are not the same question. A shard can exit non zero without
    having found a divergence: LeakSanitizer alone exits with status 23 when
    it reports anything. Collapsing the two here is exactly the bug that
    once made a sanitizer run stop after its first shard while still
    printing a divergence count of zero, which is a comfortable thing for a
    fuzzer to print and a dishonest one.

    The shard is run through uv so that the interpreter it embeds can import
    tiktoken. A bare binary would start, fail to find the module, and look
    like a fuzzing failure rather than an environment one.
    """
    environment = dict(os.environ)
    if sanitize == "address" and LSAN_SUPPRESSIONS.exists():
        existing = environment.get("LSAN_OPTIONS", "")
        option = f"suppressions={LSAN_SUPPRESSIONS}"
        environment["LSAN_OPTIONS"] = (
            f"{existing}:{option}" if existing else option
        )

    completed = subprocess.run(
        [
            "uv",
            "run",
            str(binary),
            str(seed),
            str(count),
            str(VOCABULARIES[encoding]),
            encoding,
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env=environment,
    )
    output = completed.stdout + completed.stderr
    return completed.returncode, parse_result(output), output


def main() -> int:
    """Run the requested number of inputs and report what was found."""
    parser = argparse.ArgumentParser(
        description="Drive the Knap differential fuzzer."
    )
    parser.add_argument(
        "--total",
        type=int,
        default=10_000_000,
        help=(
            "Inputs per encoding. Default ten million, so the default run "
            "is seventy million inputs in total."
        ),
    )
    parser.add_argument(
        "--shard",
        type=int,
        default=DEFAULT_SHARD,
        help=f"Inputs per shard. Default {DEFAULT_SHARD}.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1,
        help="Base seed. Shard seeds are derived from it deterministically.",
    )
    parser.add_argument(
        "--encoding",
        action="append",
        choices=sorted(VOCABULARIES),
        help="Encoding to fuzz. Repeatable. Defaults to all seven.",
    )
    parser.add_argument(
        "--sanitize",
        choices=("address", "thread"),
        help="Build under a sanitizer. Much slower, so use a smaller total.",
    )
    arguments = parser.parse_args()

    encodings = arguments.encoding or sorted(VOCABULARIES)
    for name in encodings:
        if not VOCABULARIES[name].exists():
            raise SystemExit(
                f"run_fuzz: {VOCABULARIES[name]} is missing. Run "
                "'python scripts/fetch_vocabs.py' first."
            )

    try:
        import tiktoken

        reference_version = getattr(tiktoken, "__version__", "unknown")
    except ImportError:
        raise SystemExit(
            "run_fuzz: tiktoken is not installed. Run 'uv sync --group dev'."
        )

    binary = build(arguments.sanitize)

    totals = {
        "generated": 0,
        "compared": 0,
        "round_tripped": 0,
        "divergences": 0,
    }
    seeds_used: list[int] = []
    failures: list[str] = []
    # Kept apart from divergences on purpose. A shard that exits non zero
    # because the leak checker found something is a different fact from a
    # shard that found the two implementations disagreeing, and a report
    # that merges them tells the reader neither.
    aborts: list[str] = []
    started = time.perf_counter()

    for encoding in encodings:
        done = 0
        shard_index = 0
        print(f"run_fuzz: fuzzing {encoding}, target {arguments.total}")
        while done < arguments.total:
            count = min(arguments.shard, arguments.total - done)
            # Deterministic from the base seed, so the whole run replays.
            seed = arguments.seed + shard_index * 1_000_003
            seeds_used.append(seed)

            status, counts, output = run_shard(
                binary, seed, count, encoding, arguments.sanitize
            )
            for key in totals:
                totals[key] += counts.get(key, 0)

            diverged = counts.get("divergences", 0) > 0 or (
                "DIVERGENCE" in output
            )
            if diverged:
                saved = save_divergence(output, encoding, seed)
                failures.append(output.strip())
                print(f"run_fuzz: DIVERGENCE in {encoding}, seed {seed}")
                if saved:
                    print(f"          saved to {saved.relative_to(REPO_ROOT)}")
                print(output.strip()[:2000])
                break

            if status != 0:
                # No disagreement was found, so the shard's inputs were all
                # checked. Something else made the process fail, and under a
                # sanitizer that is almost always the sanitizer itself. The
                # run stops, because continuing would accumulate a total
                # that nobody watched, but it is not reported as parity
                # having failed, because it did not.
                aborts.append(output.strip())
                print(
                    f"run_fuzz: shard exited {status} without a divergence, "
                    f"{encoding}, seed {seed}"
                )
                print(output.strip()[-2000:])
                break

            done += count
            shard_index += 1
            elapsed = time.perf_counter() - started
            rate = totals["generated"] / elapsed if elapsed else 0
            print(
                f"  {encoding}: {done} of {arguments.total}, "
                f"{rate:.0f} inputs per second"
            )

        if failures or aborts:
            break

    elapsed = time.perf_counter() - started
    report = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tiktoken_version": reference_version,
        "sanitizer": arguments.sanitize or "none",
        "encodings": encodings,
        "base_seed": arguments.seed,
        "shard_size": arguments.shard,
        "shard_seeds": seeds_used,
        "totals": totals,
        "elapsed_seconds": round(elapsed, 1),
        "divergences": len(failures),
        "aborted_shards": len(aborts),
        "lsan_suppressions": (
            str(LSAN_SUPPRESSIONS.relative_to(REPO_ROOT))
            if arguments.sanitize == "address" and LSAN_SUPPRESSIONS.exists()
            else None
        ),
    }
    report_path = FUZZ_DIR / REPORT_TEMPLATE.format(
        suffix=f".{arguments.sanitize}" if arguments.sanitize else ""
    )
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    print()
    print(f"run_fuzz: {totals['generated']} inputs generated")
    print(f"          {totals['compared']} compared against tiktoken")
    print(f"          {totals['round_tripped']} round tripped only")
    print(f"          {totals['divergences']} divergences")
    if aborts:
        print(f"          {len(aborts)} shards aborted without a divergence")
    print(f"          tiktoken {reference_version}, {elapsed:.0f} seconds")
    print(f"          report written to {report_path.relative_to(REPO_ROOT)}")

    if failures:
        print("run_fuzz: FAILED, parity was lost", file=sys.stderr)
        return 1
    if aborts:
        print(
            "run_fuzz: FAILED, a shard aborted with parity intact",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: tests/fuzz/run_fuzz.py
# =============================================================================
