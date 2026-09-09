# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : cli/tests/test_end_to_end.py
# Purpose     : Runs the built command line tool and checks it against
#               tiktoken, including through pipes.
# Stage       : Command line interface. See README.md
# Depends on  : The built binary, and tiktoken as the reference.
# Invariants  : Every number the tool prints is compared against the
#               reference. The parser tests prove the flags are read; only
#               this proves the answers are right.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""End to end tests for the Knap command line tool.

tests/test_cli.mojo proves the parser reads the flags. It says nothing about
whether the numbers are right, and a token counter whose numbers are wrong is
worse than no token counter, because somebody will bill against it.

So this builds the binary and runs it, and every count and every id it prints
is compared against tiktoken. It also runs it through pipes, because the
first version of this tool encoded correctly and could not be piped: opening
/dev/stdout works when standard output is a file and fails when it is a pipe.
A unit test would never have found that.

    python cli/tests/test_end_to_end.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE = REPO_ROOT / "cli" / "main.mojo"

CASES = [
    "",
    "hello world",
    "How many tokens is this sentence, exactly?",
    "don't stop believing",
    "  leading and trailing   ",
    "caf\u00e9 na\u00efve",
    "\u4e2d\u6587\u6d4b\u8bd5",
    "\U0001f600 emoji \U0001f680",
    "path/to/file.txt",
    "1234567890",
    "a\r\nb\n\nc",
]

MARKER = "<|endoftext|>"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    """Record a failure without stopping the run.

    Args:
        condition: What must hold.
        message: What to report when it does not.
    """
    if not condition:
        failures.append(message)


def build(destination: Path) -> Path:
    """Compile the command line tool.

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
            "test_end_to_end: no Mojo compiler at .venv/bin/mojo. Run "
            "'uv sync --group dev' first."
        )

    done = subprocess.run(
        [
            str(mojo),
            "build",
            "--Werror",
            "-I",
            "src",
            "-I",
            "cli",
            "-o",
            str(destination),
            str(SOURCE.relative_to(REPO_ROOT)),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        print(done.stdout)
        print(done.stderr, file=sys.stderr)
        raise SystemExit("test_end_to_end: the tool did not compile")
    return destination


def run(
    binary: Path, arguments: list[str], stdin: bytes = b""
) -> tuple[int, bytes, str]:
    """Run the tool once.

    Args:
        binary: The built tool.
        arguments: Arguments after the program name.
        stdin: Bytes to write to standard input.

    Returns:
        The exit status, standard output as raw bytes, and standard error.

    Output is kept as bytes rather than decoded, because decode is allowed
    to emit sequences that are not valid UTF-8 and that is the case worth
    testing.
    """
    done = subprocess.run(
        [str(binary)] + arguments,
        cwd=REPO_ROOT,
        input=stdin,
        capture_output=True,
        check=False,
    )
    return done.returncode, done.stdout, done.stderr.decode("utf-8", "replace")


def main() -> int:
    """Build the tool and check it against the reference."""
    try:
        import tiktoken
    except ImportError:
        raise SystemExit(
            "test_end_to_end: tiktoken is required. Run 'uv sync --group dev'."
        )

    for name in ("cl100k_base", "o200k_base"):
        vocabulary = (
            REPO_ROOT / "tests" / "fixtures" / "vocabs" / f"{name}.tiktoken"
        )
        if not vocabulary.exists():
            raise SystemExit(
                f"test_end_to_end: {vocabulary} is missing. Run "
                "'python scripts/fetch_vocabs.py' first."
            )

    with tempfile.TemporaryDirectory() as scratch:
        binary = build(Path(scratch) / "knap")
        checked = 0

        for name in ("cl100k_base", "o200k_base"):
            reference = tiktoken.get_encoding(name)

            for text in CASES:
                expected = reference.encode_ordinary(text)

                # As an argument.
                status, out, err = run(
                    binary, ["count", "-e", name, text]
                )
                check(
                    status == 0 and out.decode().strip() == str(len(expected)),
                    f"{name}: count of {text!r} gave {out!r} {err}",
                )

                status, out, err = run(
                    binary, ["encode", "-e", name, "--format", "json", text]
                )
                produced = out.decode().strip()
                wanted = "[" + ",".join(str(i) for i in expected) + "]"
                check(
                    status == 0 and produced == wanted,
                    f"{name}: encode of {text!r} gave {produced}, reference "
                    f"gave {wanted}",
                )

                # Through standard input. The same text has to give the same
                # answer whichever way it arrives.
                status, out, err = run(
                    binary, ["count", "-e", name], stdin=text.encode("utf-8")
                )
                check(
                    status == 0 and out.decode().strip() == str(len(expected)),
                    f"{name}: count of {text!r} from stdin gave {out!r} {err}",
                )
                checked += 1

            # Special tokens. Three policies, and the default is the one that
            # must never encode a marker it was not asked to.
            with_marker = f"before {MARKER} after"

            status, out, _ = run(
                binary, ["encode", "-e", name, "--format", "json", with_marker]
            )
            ordinary = reference.encode_ordinary(with_marker)
            check(
                status == 0
                and out.decode().strip()
                == "[" + ",".join(str(i) for i in ordinary) + "]",
                f"{name}: a marker was not treated as text by default",
            )

            status, out, _ = run(
                binary,
                [
                    "encode",
                    "-e",
                    name,
                    "--format",
                    "json",
                    "--allowed-special",
                    MARKER,
                    with_marker,
                ],
            )
            allowed = reference.encode(with_marker, allowed_special={MARKER})
            check(
                status == 0
                and out.decode().strip()
                == "[" + ",".join(str(i) for i in allowed) + "]",
                f"{name}: an allowed marker did not become its id",
            )

            status, _, _ = run(
                binary, ["encode", "-e", name, "--strict-special", with_marker]
            )
            check(
                status == 1,
                f"{name}: --strict-special did not refuse a marker",
            )

        # Round trips, including bytes that are not valid UTF-8. This is the
        # property a byte level tokenizer exists to have, and the pipe is the
        # part that was broken once.
        for payload in (
            b"hello world",
            b"caf\xc3\xa9",
            b"A\x80B\xff",
            b"\xf0\x9f\x98\x80 partial: \xf0\x9f",
            bytes(range(256)),
        ):
            status, ids, err = run(binary, ["encode", "-f", "/dev/stdin"], payload)
            check(status == 0, f"encode of {payload!r} failed: {err}")
            status, back, err = run(binary, ["decode"], ids)
            check(
                status == 0 and back == payload,
                f"round trip of {payload!r} returned {back!r} {err}",
            )
            checked += 1

        # Usage errors are status 2, runtime failures are status 1. A caller
        # scripting this needs the two to be distinguishable.
        for arguments, wanted in (
            (["frobnicate"], 2),
            (["count", "--nope", "x"], 2),
            (["count", "-e"], 2),
            (["count", "-e", "klingon", "x"], 2),
            (["count", "one", "two"], 2),
            (["count", "text", "-f", "some.txt"], 2),
            (["count", "--strict-special", "--allowed-special", "x", "y"], 2),
            (["count", "-f", "/no/such/file"], 1),
            (["decode", "no digits here"], 1),
            (["help"], 0),
            (["version"], 0),
        ):
            status, _, _ = run(binary, arguments)
            check(
                status == wanted,
                f"{arguments} exited {status}, expected {wanted}",
            )

        print(f"test_end_to_end: checked {checked} inputs and every exit path")

    if failures:
        print()
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"test_end_to_end: {len(failures)} failures", file=sys.stderr)
        return 1

    print("test_end_to_end: the tool agrees with tiktoken everywhere")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: cli/tests/test_end_to_end.py
# =============================================================================
