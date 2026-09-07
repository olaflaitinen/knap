# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/fetch_vocabs.py
# Purpose     : Downloads the cl100k_base and o200k_base vocabulary files and
#               records where each came from and what it hashed to.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : tiktoken, for the canonical URLs and for verification.
# Invariants  : The download is verified against the ranks tiktoken itself
#               loads. A file that parses but disagrees is rejected.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Fetch the vocabulary files Knap is tested against.

Vocabulary files are fetched rather than committed. That keeps any licence
question with the upstream publisher, and it means the exact source is
recorded rather than assumed. See tests/fixtures/vocabs/README.md.

Two things make this more than a download loop.

First, the URLs are not written here. They are read out of the tiktoken
package's own encoding constructors, so this script cannot drift from the
reference implementation by holding a stale address. If tiktoken changes where
a vocabulary lives, this follows.

Second, every download is verified against the merge ranks tiktoken itself
loads for that encoding. A truncated or substituted file that still parses
would otherwise produce a tokenizer that is subtly and silently wrong, which
is the exact failure mode this project exists to avoid.

    python scripts/fetch_vocabs.py
    python scripts/fetch_vocabs.py --vocab cl100k_base

Exit status is 0 when every requested vocabulary is present and verified.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import inspect
import json
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DESTINATION = REPO_ROOT / "tests" / "fixtures" / "vocabs"

# The vocabularies Knap targets. Anything else tiktoken registers is out of
# scope for version 1, per docs/ROADMAP.md.
WANTED = ("cl100k_base", "o200k_base")

# Provenance for every fetched file is written here so that a later run, or a
# reviewer, can tell exactly what was downloaded and from where.
PROVENANCE = DESTINATION / "provenance.json"

URL_PATTERN = re.compile(r"https?://[^\s\"']+\.tiktoken")

# Downloads are streamed in chunks so that a large vocabulary never has to sit
# in memory twice, once as bytes and once as a hash input.
CHUNK_BYTES = 1 << 16


@dataclass(frozen=True)
class Fetched:
    """One downloaded vocabulary and everything known about it.

    Attributes:
        name: Encoding name, for example cl100k_base.
        url: The address the bytes actually came from.
        path: Where the file was written.
        sha256: Hex digest of the downloaded bytes.
        size: Size in bytes.
        token_count: Number of entries parsed out of the file.
    """

    name: str
    url: str
    path: Path
    sha256: str
    size: int
    token_count: int


def canonical_url(name: str) -> str:
    """Read the vocabulary URL out of tiktoken's own encoding constructor.

    Why this and not a constant: a hardcoded URL is a second source of truth
    that nothing keeps in step. Reading tiktoken's source means the address
    Knap downloads from is by construction the address the reference
    implementation uses.

    Failure modes: if tiktoken restructures its constructors so that no URL is
    visible in the source, this raises rather than falling back to a guess.
    """
    try:
        import tiktoken_ext.openai_public as public
    except ImportError as exc:
        raise SystemExit(
            "fetch_vocabs: tiktoken is not installed. Run 'uv sync "
            "--group dev' first."
        ) from exc

    constructors = getattr(public, "ENCODING_CONSTRUCTORS", None) or {}
    if name not in constructors and not hasattr(public, name):
        raise SystemExit(f"fetch_vocabs: tiktoken does not register '{name}'")

    constructor = constructors.get(name) or getattr(public, name)
    source = inspect.getsource(constructor)
    matches = URL_PATTERN.findall(source)
    if not matches:
        raise SystemExit(
            f"fetch_vocabs: no .tiktoken URL found in the tiktoken "
            f"constructor for '{name}'. The package layout has changed and "
            "this script needs updating rather than working around it."
        )
    return matches[0]


def download(url: str, destination: Path) -> tuple[str, int]:
    """Stream a URL to disk, returning its SHA-256 digest and size.

    The file is written to a temporary name and moved into place only after
    the whole body arrives, so an interrupted run cannot leave a truncated
    vocabulary that a later run would treat as complete.
    """
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".partial")
    digest = hashlib.sha256()
    size = 0

    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            with temporary.open("wb") as handle:
                while True:
                    chunk = response.read(CHUNK_BYTES)
                    if not chunk:
                        break
                    handle.write(chunk)
                    digest.update(chunk)
                    size += len(chunk)
    except (urllib.error.URLError, OSError) as exc:
        temporary.unlink(missing_ok=True)
        raise SystemExit(f"fetch_vocabs: download failed for {url}: {exc}")

    temporary.replace(destination)
    return digest.hexdigest(), size


def parse_tiktoken_file(path: Path) -> dict[bytes, int]:
    """Parse a .tiktoken file into a mapping from token bytes to rank.

    The format is one entry per line: a base64 encoded token, a space, then a
    decimal rank. This mirrors what the Mojo loader in src/knap/vocab.mojo
    must do, and parsing it here in Python is what lets the two be compared.

    Failure modes: a malformed line raises with its line number rather than
    being skipped, because a silently dropped token shifts nothing visible
    but changes the tokenizer.
    """
    ranks: dict[bytes, int] = {}
    with path.open("rb") as handle:
        for number, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 2:
                raise SystemExit(
                    f"fetch_vocabs: {path.name} line {number} has "
                    f"{len(parts)} fields, expected 2"
                )
            try:
                token = base64.b64decode(parts[0], validate=True)
                rank = int(parts[1])
            except (ValueError, base64.binascii.Error) as exc:
                raise SystemExit(
                    f"fetch_vocabs: {path.name} line {number} is malformed: "
                    f"{exc}"
                )
            ranks[token] = rank
    return ranks


def verify_against_tiktoken(name: str, ranks: dict[bytes, int]) -> None:
    """Check the downloaded ranks equal the ones tiktoken loads.

    This is the check that makes the download trustworthy. A file can be
    well formed, parse cleanly, and still be the wrong file. Comparing
    against the reference implementation's own view is the only way to tell.

    Failure modes: any difference in size or content raises, and the message
    names a differing token so the problem can be investigated rather than
    merely retried.
    """
    import tiktoken

    encoding = tiktoken.get_encoding(name)
    reference = encoding._mergeable_ranks

    if len(reference) != len(ranks):
        raise SystemExit(
            f"fetch_vocabs: {name} has {len(ranks)} entries but tiktoken "
            f"loads {len(reference)}"
        )

    for token, rank in reference.items():
        if ranks.get(token) != rank:
            raise SystemExit(
                f"fetch_vocabs: {name} disagrees with tiktoken on token "
                f"{token!r}: file says {ranks.get(token)}, tiktoken says "
                f"{rank}"
            )


def fetch(name: str, force: bool) -> Fetched:
    """Download, parse, and verify one vocabulary."""
    url = canonical_url(name)
    path = DESTINATION / f"{name}.tiktoken"

    if path.exists() and not force:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        size = path.stat().st_size
        print(f"  {name}: already present, {size} bytes")
    else:
        print(f"  {name}: downloading from {url}")
        digest, size = download(url, path)
        print(f"  {name}: {size} bytes")

    ranks = parse_tiktoken_file(path)
    verify_against_tiktoken(name, ranks)
    print(f"  {name}: verified against tiktoken, {len(ranks)} tokens")

    return Fetched(
        name=name,
        url=url,
        path=path,
        sha256=digest,
        size=size,
        token_count=len(ranks),
    )


def write_provenance(results: list[Fetched]) -> None:
    """Record what was fetched, from where, and what it hashed to."""
    import tiktoken

    payload = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tiktoken_version": getattr(tiktoken, "__version__", "unknown"),
        "vocabularies": {
            item.name: {
                "url": item.url,
                "sha256": item.sha256,
                "bytes": item.size,
                "tokens": item.token_count,
            }
            for item in results
        },
    }
    PROVENANCE.parent.mkdir(parents=True, exist_ok=True)
    PROVENANCE.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"  provenance written to {PROVENANCE.relative_to(REPO_ROOT)}")


def main() -> int:
    """Fetch every requested vocabulary and record its provenance."""
    parser = argparse.ArgumentParser(
        description="Fetch the vocabulary files Knap is tested against."
    )
    parser.add_argument(
        "--vocab",
        action="append",
        choices=WANTED,
        help="Fetch only this vocabulary. Repeatable. Defaults to all.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Download again even if the file is already present.",
    )
    arguments = parser.parse_args()

    wanted = tuple(arguments.vocab) if arguments.vocab else WANTED
    print(f"fetch_vocabs: fetching {', '.join(wanted)}")

    results = [fetch(name, arguments.force) for name in wanted]
    write_provenance(results)

    total = sum(item.token_count for item in results)
    print(f"fetch_vocabs: {len(results)} vocabularies, {total} tokens total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/fetch_vocabs.py
# =============================================================================
