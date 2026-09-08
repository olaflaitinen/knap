# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/__init__.mojo
# Purpose     : Public exports for the pre-tokenization stage. No logic here.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : pattern.mojo, scanner.mojo
# Invariants  : Re-exports only. The scanner owns every decision, so this
#               file never grows a code path of its own.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Pre-tokenization for Knap.

Stage 2 of the encoding pipeline. Splits a byte sequence into the pieces the
BPE merge loop then processes independently.

The scanners here are hand written matchers for two specific patterns, not a
regex engine. The pattern constants they were written against are exported
alongside them, so a test can confirm the two have not drifted apart.

Non-ASCII input is the slow path by design, and that is fine: real text is
dominated by ASCII, and the ASCII path never consults a Unicode table.
"""

from .pattern import (
    CL100K_BASE_ALTERNATIVES,
    CL100K_BASE_PATTERN,
    CL100K_BASE_PATTERN_SHA256,
    O200K_BASE_ALTERNATIVES,
    O200K_BASE_PATTERN,
    O200K_BASE_PATTERN_SHA256,
)
from .scanner import scan_cl100k, scan_o200k

# =============================================================================
# End of file: src/knap/pretokenize/__init__.mojo
# =============================================================================
