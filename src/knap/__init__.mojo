# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/__init__.mojo
# Purpose     : Public exports for the knap package. No logic lives here.
# Stage       : Package entry point
# Depends on  : flat_vocab.mojo, special.mojo, vocab.mojo
# Invariants  : Re-exports only. Anything that needs a decision belongs in the
#               module that owns it, so this file never grows a code path.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Knap, a pure Mojo byte level BPE tokenizer.

This module re-exports the public surface, so a caller can write
"from knap import Vocabulary" without knowing which file each type lives in.

What exists today is vocabulary loading and decoding. Encoding arrives with
milestone M3; see docs/ROADMAP.md for what is built and what is not.

Import the package by putting the src directory on the include path:

    mojo run -I src your_program.mojo
"""

from .flat_vocab import FlatVocab
from .special import (
    SpecialTokens,
    cl100k_base_specials,
    o200k_base_specials,
)
from .vocab import (
    Vocabulary,
    load_cl100k_base,
    load_o200k_base,
    load_tiktoken,
)

# =============================================================================
# End of file: src/knap/__init__.mojo
# =============================================================================
