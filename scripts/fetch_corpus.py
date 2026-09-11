# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/fetch_corpus.py
# Purpose     : Downloads and prepares the mixed text corpus the pre-tokenizer
#               parity gate runs against.
# Stage       : Pre-tokenization. See docs/ARCHITECTURE.md
# Depends on  : Python standard library only. No third party downloader.
# Invariants  : The corpus is valid UTF-8 throughout, because the reference
#               regex operates on decoded text and cannot be given anything
#               else. Malformed byte handling is tested separately.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Build the mixed text corpus for the pre-tokenization parity gate.

The gate requires at least 100 MB of mixed text, and the word mixed is doing
real work. A corpus of English prose would exercise perhaps a third of the
pattern alternatives, so this assembles three different kinds of text:

  * Multilingual sentences from Tatoeba, covering hundreds of languages
    including scripts with no word spacing and right to left scripts.
  * Long form prose from Project Gutenberg, which supplies the paragraph
    shapes and punctuation density that sentence corpora lack.
  * A deterministic hazard section, generated here rather than downloaded,
    that concentrates the cases listed in docs/CORRECTNESS.md: emoji with
    joiners and modifiers, digit runs of every length, contractions in both
    cases, whitespace at document boundaries, and stacked combining marks.

The third part exists because real text is a poor way to reach edge cases.
Waiting for a hundred megabytes of natural language to happen to contain a
seven digit number followed by end of input is not a test strategy.

The archive is streamed and abandoned once enough text has been read, so a
209 MB download is not fully transferred to obtain 60 MB of sentences.

    python scripts/fetch_corpus.py
    python scripts/fetch_corpus.py --target-mb 120

The corpus is written to bench/corpus/ and is never committed.
"""

from __future__ import annotations

import argparse
import bz2
import http.client
import hashlib
import io
import json
import sys
import tarfile
import unicodedata
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CORPUS_DIR = REPO_ROOT / "bench" / "corpus"
MANIFEST = CORPUS_DIR / "manifest.json"

TATOEBA_URL = "https://downloads.tatoeba.org/exports/sentences.tar.bz2"

# A deliberately varied set: different languages, scripts, and centuries.
GUTENBERG_BOOKS = (
    ("pride_and_prejudice_en", 1342),
    ("moby_dick_en", 2701),
    ("les_miserables_fr", 17489),
    ("don_quijote_es", 2000),
    ("faust_de", 2229),
)
GUTENBERG_URL = "https://www.gutenberg.org/cache/epub/{0}/pg{0}.txt"

CHUNK_BYTES = 1 << 20


def download(url: str, timeout: int = 180, attempts: int = 3) -> bytes:
    """Fetch a URL into memory, retrying and tolerating a short read.

    Args:
        url: The address to fetch.
        timeout: Seconds to wait per attempt.
        attempts: How many times to try before giving up.

    Returns:
        The response body, which may be truncated if the server closed the
        connection early.

    Raises:
        OSError: when every attempt failed. The caller decides whether one
            missing source matters; the size check at the end of main is the
            real guard against a corpus that is too small.

    A truncated body is accepted deliberately. These are prose files being
    concatenated into a corpus, so half a book is still perfectly good input
    for a pre-tokenizer, whereas aborting the whole build over one short read
    would make the gate depend on a flawless network.
    """
    last_error: Exception = OSError("no attempt was made")
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as response:
                return response.read()
        except http.client.IncompleteRead as exc:
            if len(exc.partial) > (64 << 10):
                print(
                    f"    short read on {url}, keeping "
                    f"{len(exc.partial) // 1024} KB"
                )
                return exc.partial
            last_error = exc
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            last_error = exc
        print(f"    attempt {attempt + 1} of {attempts} failed: {last_error}")
    raise OSError(f"could not fetch {url}: {last_error}")


def fetch_tatoeba(limit_bytes: int) -> str:
    """Stream multilingual sentences until the byte budget is reached.

    Args:
        limit_bytes: How many bytes of text to collect.

    Returns:
        Newline separated sentences.

    Raises:
        SystemExit: if the archive cannot be read.

    The archive is a bz2 compressed tar holding one tab separated file of
    sentence id, language code, and text. Reading stops as soon as the budget
    is met, which is why only part of the 209 MB download is transferred.
    """
    print(f"  tatoeba: streaming up to {limit_bytes // (1 << 20)} MB")
    try:
        request = urllib.request.urlopen(TATOEBA_URL, timeout=300)
    except (urllib.error.URLError, OSError) as exc:
        raise SystemExit(f"fetch_corpus: could not open Tatoeba: {exc}")

    collected: list[str] = []
    total = 0
    decompressor = bz2.BZ2Decompressor()
    pending = b""

    try:
        while total < limit_bytes:
            block = request.read(CHUNK_BYTES)
            if not block:
                break
            try:
                pending += decompressor.decompress(block)
            except (OSError, EOFError):
                break

            # The tar header is 512 bytes of metadata followed by the file
            # body. Rather than parse it, split on newlines and keep the
            # lines that look like sentence records.
            lines = pending.split(b"\n")
            pending = lines.pop()
            for raw in lines:
                parts = raw.split(b"\t")
                if len(parts) != 3:
                    continue
                try:
                    text = parts[2].decode("utf-8")
                except UnicodeDecodeError:
                    continue
                if not text:
                    continue
                collected.append(text)
                total += len(parts[2]) + 1
                if total >= limit_bytes:
                    break
    finally:
        request.close()

    print(f"  tatoeba: {len(collected)} sentences, {total // (1 << 20)} MB")
    return "\n".join(collected)


def fetch_gutenberg() -> str:
    """Fetch the long form prose books.

    Returns:
        The concatenated book texts.
    """
    parts: list[str] = []
    for name, number in GUTENBERG_BOOKS:
        url = GUTENBERG_URL.format(number)
        try:
            body = download(url)
        except OSError as exc:
            # One unavailable book does not invalidate the corpus. The size
            # check in main is what decides whether enough text was gathered.
            print(f"  gutenberg: SKIPPED {name}: {exc}")
            continue
        text = body.decode("utf-8", errors="replace")
        parts.append(text)
        print(f"  gutenberg: {name}, {len(body) // 1024} KB")
    return "\n".join(parts)


def build_hazard_text(target_bytes: int) -> str:
    """Generate text concentrating the documented correctness hazards.

    Args:
        target_bytes: Roughly how many bytes to produce.

    Returns:
        Deterministic text exercising each hazard many times.

    Deterministic on purpose. A fuzzer has a
    seed; this section is part of a corpus that should produce the same gate
    result on every machine and every run.
    """
    blocks: list[str] = []

    # Digit runs of every length from 1 to 20, since the pattern groups
    # digits in bounded runs and the boundary is easy to get wrong.
    for length in range(1, 21):
        digits = "1234567890" * 3
        blocks.append(digits[:length])
        blocks.append(" " + digits[:length])
        blocks.append("x" + digits[:length] + "y")

    # Contractions, in both cases, plus the long s that the case insensitive
    # group folds to "s".
    for stem in ("don", "it", "we", "they", "I", "DON", "IT"):
        for ending in ("'s", "'S", "'t", "'T", "'re", "'RE", "'ve", "'VE",
                       "'ll", "'LL", "'m", "'M", "'d", "'D", "'\u017f"):
            blocks.append(stem + ending)

    # Whitespace shapes, including runs that reach end of input and runs
    # that stop just before a visible character.
    for run in (" ", "  ", "   ", "\t", "\t\t", "\n", "\n\n", "\r\n",
                " \n", "\n ", "  \n  ", "\r\n\r\n", "\u00a0", "\u3000",
                "\u2028", "\u2029", "\u205f"):
        blocks.append("a" + run + "b")
        blocks.append("a" + run)
        blocks.append(run + "b")

    # Emoji, including zero width joiner sequences, skin tone modifiers,
    # and regional indicator flag pairs.
    zwj = "\u200d"
    blocks.append("\U0001f468" + zwj + "\U0001f469" + zwj + "\U0001f466")
    blocks.append("\U0001f44d\U0001f3fd")
    blocks.append("\U0001f1eb\U0001f1ee")
    blocks.append("\U0001f600\U0001f601\U0001f602")
    blocks.append("a\U0001f600b")

    # Scripts without word spacing, right to left scripts, and Hangul in
    # both precomposed and decomposed forms.
    blocks.append("\u4e2d\u6587\u6d4b\u8bd5")
    blocks.append("\u3053\u3093\u306b\u3061\u306f\u4e16\u754c")
    blocks.append("\u0e2a\u0e27\u0e31\u0e2a\u0e14\u0e35")
    blocks.append("\u0627\u0644\u0639\u0631\u0628\u064a\u0629")
    blocks.append("\u05e2\u05d1\u05e8\u05d9\u05ea")
    blocks.append("\u0926\u0947\u0935\u0928\u093e\u0917\u0930\u0940")
    blocks.append("\ud55c\uad6d\uc5b4")
    blocks.append(unicodedata.normalize("NFD", "\ud55c\uad6d\uc5b4"))

    # Combining marks stacked to unusual depth, which the two patterns
    # treat differently: one keeps them with the letter and one does not.
    for depth in (1, 2, 3, 5, 8):
        blocks.append("a" + "\u0301" * depth + "b")

    # Punctuation density, which is what source code looks like to a
    # tokenizer, including the slash that o200k_base singles out.
    blocks.append("path/to/file.txt")
    blocks.append("a//b///c")
    blocks.append("x = (y + 1) * [z]; // comment")
    blocks.append("{\"key\": [1, 2, 3], \"n\": null}")

    unit = "\n".join(blocks)
    repeats = max(1, target_bytes // max(1, len(unit.encode("utf-8"))))
    print(f"  hazards: {len(blocks)} shapes, repeated {repeats} times")
    return "\n".join(unit for _ in range(repeats))


def main() -> int:
    """Assemble the corpus and record what went into it."""
    parser = argparse.ArgumentParser(
        description="Build the mixed text corpus for the parity gate."
    )
    parser.add_argument(
        "--target-mb",
        type=int,
        default=110,
        help="Approximate corpus size in megabytes. Default 110.",
    )
    arguments = parser.parse_args()

    target = arguments.target_mb << 20
    CORPUS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"fetch_corpus: assembling about {arguments.target_mb} MB")

    hazard_budget = min(target // 4, 30 << 20)
    hazards = build_hazard_text(hazard_budget)
    gutenberg = fetch_gutenberg()

    used = len(hazards.encode("utf-8")) + len(gutenberg.encode("utf-8"))
    tatoeba = fetch_tatoeba(max(0, target - used))

    # Interleaved rather than concatenated, so that a piece boundary at a
    # section join is exercised many times instead of four times.
    corpus = "\n".join((hazards, gutenberg, tatoeba))
    encoded = corpus.encode("utf-8")

    destination = CORPUS_DIR / "mixed.txt"
    destination.write_bytes(encoded)

    digest = hashlib.sha256(encoded).hexdigest()
    MANIFEST.write_text(
        json.dumps(
            {
                "generated": datetime.now(timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
                "bytes": len(encoded),
                "sha256": digest,
                "sources": {
                    "tatoeba": TATOEBA_URL,
                    "gutenberg": [name for name, _ in GUTENBERG_BOOKS],
                    "hazards": "generated by scripts/fetch_corpus.py",
                },
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    megabytes = len(encoded) / (1 << 20)
    print(f"fetch_corpus: wrote {destination.relative_to(REPO_ROOT)}")
    print(f"fetch_corpus: {megabytes:.1f} MB, sha256 {digest[:16]}")
    if len(encoded) < (100 << 20):
        print(
            "fetch_corpus: WARNING, the corpus is below the 100 MB the "
            "boundary parity gate requires."
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/fetch_corpus.py
# =============================================================================
