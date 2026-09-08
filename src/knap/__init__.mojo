# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/__init__.mojo
# Purpose     : Public exports for the knap package. No logic lives here.
# Stage       : Package entry point
# Depends on  : flat_vocab.mojo, ranks.mojo, special.mojo, tokenizer.mojo,
#               vocab.mojo
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
"from knap import Tokenizer" without knowing which file each type lives in.

Encoding and decoding both work, and their output matches tiktoken exactly on
110 MB of mixed text. See docs/CORRECTNESS.md for what that claim covers and,
just as importantly, what it does not.

Import the package by putting the src directory on the include path:

    mojo run -I src your_program.mojo

The shortest useful program:

    from knap import load_cl100k_base_tokenizer

    def main() raises:
        var knap = load_cl100k_base_tokenizer(
            "tests/fixtures/vocabs/cl100k_base.tiktoken"
        )
        print(knap.decode(knap.encode_ordinary("hello world")))
"""

from .flat_vocab import FlatVocab
from .ranks import RankTable
from .special import SpecialTokens
from .tokenizer import (
    PATTERN_CL100K,
    PATTERN_O200K,
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_o200k_base_tokenizer,
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
