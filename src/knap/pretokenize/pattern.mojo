# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/pattern.mojo
# Purpose     : The pre-tokenization patterns, extracted verbatim
#               from tiktoken as a functional specification.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : Nothing. Constants only.
# Invariants  : Alternation order is load bearing. The pattern is
#               tried left to right and the first match wins.
# -----------------------------------------------------------------------------
# Generator   : scripts/extract_patterns.py
# Upstream    : tiktoken 0.14.0, MIT licensed
# Generated   : 2026-09-08
# NOTE        : This file is generated. Manual edits will be
#               overwritten the next time the generator runs.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Pre-tokenization patterns, extracted from tiktoken.

Knap does not execute these patterns. It reproduces their behaviour
with a hand rolled scanner, and these constants are the
specification that scanner is written against. A test re-extracts
them and fails if the committed copy has drifted.

The patterns are reproduced verbatim, including their possessive
quantifiers. cl100k_base uses them and o200k_base does not, which
changes matching semantics: a possessive quantifier never gives
back what it consumed, so an alternative that fails after one
fails outright rather than retrying a shorter match.
"""


# -----------------------------------------------------------------------------
# cl100k_base
#
# 8 top level alternatives, tried in this order:
#   0. '(?i:[sdmt]|ll|ve|re)
#   1. [^\r\n\p{L}\p{N}]?+\p{L}++
#   2. \p{N}{1,3}+
#   3.  ?[^\s\p{L}\p{N}]++[\r\n]*+
#   4. \s++$
#   5. \s*[\r\n]
#   6. \s+(?!\S)
#   7. \s
# -----------------------------------------------------------------------------

comptime CL100K_BASE_PATTERN: StaticString = (
    "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+|"
    " ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"
)
"""The cl100k_base pre-tokenization pattern, verbatim."""

comptime CL100K_BASE_PATTERN_SHA256: StaticString = (
    "f021c3d976978e62ee64cdad150cc3405c2e3d6e3b40407850bb9e8d9eb65899"
)
"""SHA-256 of the cl100k_base pattern, for drift detection."""

comptime CL100K_BASE_ALTERNATIVES: Int = 8
"""Number of top level alternatives in the cl100k_base pattern."""

# -----------------------------------------------------------------------------
# o200k_base
#
# 7 top level alternatives, tried in this order:
#   0. [^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?
#   1. [^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?
#   2. \p{N}{1,3}
#   3.  ?[^\s\p{L}\p{N}]+[\r\n/]*
#   4. \s*[\r\n]+
#   5. \s+(?!\S)
#   6. \s+
# -----------------------------------------------------------------------------

comptime O200K_BASE_PATTERN: StaticString = (
    "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\\p{N}{1,3}|"
    " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
)
"""The o200k_base pre-tokenization pattern, verbatim."""

comptime O200K_BASE_PATTERN_SHA256: StaticString = (
    "2d1b8dc11e89af71459b36004f698ab3693f59fd84f63e8ec2b49564ab857420"
)
"""SHA-256 of the o200k_base pattern, for drift detection."""

comptime O200K_BASE_ALTERNATIVES: Int = 7
"""Number of top level alternatives in the o200k_base pattern."""

# =============================================================================
# End of file: src/knap/pretokenize/pattern.mojo
# =============================================================================
