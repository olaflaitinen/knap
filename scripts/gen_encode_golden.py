# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/gen_encode_golden.py
# Purpose     : Generates the tiktoken derived golden fixtures Knap is
#               verified against.
# Stage       : Milestone M1, vocabulary and decode. See docs/ROADMAP.md
# Depends on  : tiktoken, as the reference implementation.
# Invariants  : One JSON object per line, written with no spaces, so that the
#               strict reader in tests/test_decode.mojo can parse it without
#               a general JSON parser.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Generate the tiktoken derived golden fixtures.

This writes decode_single_tokens.jsonl for each target vocabulary: one line
per token id across the whole id space, holding the exact bytes tiktoken
returns from decode_single_token_bytes.

Unassigned ids are recorded, not skipped. The id space of both target
encodings has holes, because the special tokens do not sit flush against the
merge ranks. cl100k_base leaves 16 ids assigned to nothing and o200k_base
leaves 19. tiktoken raises for those, and a golden file that simply omitted
them would let Knap return anything at all for an id the reference refuses.
Each hole is therefore written with a null, and the test asserts Knap raises.

The companion fixture encode_expected.jsonl is not written here yet. It
requires a corpus to encode and an encoder to compare against, so it arrives
with milestone M3.

    python scripts/gen_encode_golden.py
    python scripts/gen_encode_golden.py --vocab cl100k_base

Exit status is 0 when every requested fixture is written.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GOLDEN_ROOT = REPO_ROOT / "tests" / "golden"

WANTED = ("cl100k_base", "o200k_base")

# The reader on the Mojo side is deliberately not a JSON parser. It relies on
# these exact key names, on the absence of whitespace, and on base64 never
# containing a quotation mark or a backslash. Changing the shape of a line
# here means changing that reader too.
SEPARATORS = (",", ":")


def generate_decode_golden(name: str) -> tuple[Path, int, int]:
    """Write decode_single_tokens.jsonl for one encoding.

    Args:
        name: Encoding name, for example cl100k_base.

    Returns:
        The path written, the number of assigned ids, and the number of
        unassigned ids.

    Raises:
        SystemExit: if tiktoken is not installed.

    Every id from zero up to n_vocab is probed. An id that decodes is
    recorded with its bytes in base64; an id that raises is recorded with a
    null, which is what makes the holes in the id space testable rather than
    invisible.
    """
    try:
        import tiktoken
    except ImportError as exc:
        raise SystemExit(
            "gen_encode_golden: tiktoken is not installed. Run "
            "'uv sync --group dev' first."
        ) from exc

    encoding = tiktoken.get_encoding(name)
    destination = GOLDEN_ROOT / name / "decode_single_tokens.jsonl"
    destination.parent.mkdir(parents=True, exist_ok=True)

    assigned = 0
    unassigned = 0

    with destination.open("w", encoding="ascii", newline="\n") as handle:
        for token_id in range(encoding.n_vocab):
            try:
                raw = encoding.decode_single_token_bytes(token_id)
            except Exception:
                # tiktoken raises KeyError for an id nothing defines. The
                # exception type is not part of its documented interface, so
                # the catch is deliberately broad: what matters is that the
                # reference refuses, not how it refuses.
                record = {"id": token_id, "b64": None}
                unassigned += 1
            else:
                record = {
                    "id": token_id,
                    "b64": base64.b64encode(raw).decode("ascii"),
                }
                assigned += 1
            handle.write(json.dumps(record, separators=SEPARATORS) + "\n")

    return destination, assigned, unassigned


def write_manifest(entries: dict[str, dict[str, int]]) -> None:
    """Record which reference produced these fixtures.

    Args:
        entries: Per encoding counts to record.

    A golden file that does not name the version that produced it is not a
    reference. When a future tiktoken changes behaviour, this manifest is
    what distinguishes a real Knap regression from an intended upstream
    change.
    """
    import tiktoken

    manifest = GOLDEN_ROOT / "manifest.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator": "scripts/gen_encode_golden.py",
        "tiktoken_version": getattr(tiktoken, "__version__", "unknown"),
        "encodings": entries,
    }
    manifest.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"  manifest written to {manifest.relative_to(REPO_ROOT)}")


def main() -> int:
    """Generate the decode goldens for every requested vocabulary."""
    parser = argparse.ArgumentParser(
        description="Generate tiktoken derived golden fixtures for Knap."
    )
    parser.add_argument(
        "--vocab",
        action="append",
        choices=WANTED,
        help="Generate for this vocabulary only. Repeatable.",
    )
    arguments = parser.parse_args()

    wanted = tuple(arguments.vocab) if arguments.vocab else WANTED
    print(f"gen_encode_golden: generating for {', '.join(wanted)}")

    entries: dict[str, dict[str, int]] = {}
    for name in wanted:
        path, assigned, unassigned = generate_decode_golden(name)
        total = assigned + unassigned
        print(
            f"  {name}: {total} ids, {assigned} assigned, "
            f"{unassigned} unassigned -> {path.relative_to(REPO_ROOT)}"
        )
        entries[name] = {
            "id_space": total,
            "assigned": assigned,
            "unassigned": unassigned,
        }

    write_manifest(entries)
    return 0


if __name__ == "__main__":
    sys.exit(main())

# =============================================================================
# End of file: scripts/gen_encode_golden.py
# =============================================================================
