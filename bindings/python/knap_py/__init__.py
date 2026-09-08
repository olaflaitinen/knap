# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bindings/python/knap_py/__init__.py
# Purpose     : Public Python surface. Re-exports only, no logic.
# Stage       : Milestone M6 Track B, Python consumers. See docs/ROADMAP.md
# Depends on  : tokenizer.py
# Invariants  : Importing this package must not build or load anything. The
#               extension is located lazily, when a tokenizer is created.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Knap for Python.

A thin, Pythonic layer over the native extension module built from Mojo. The
extension does the work; this package exists so that callers get bytes and
lists rather than raw interop types, and a clear error rather than an import
failure when the extension has not been built.

    from knap_py import Tokenizer

    knap = Tokenizer.cl100k_base("tests/fixtures/vocabs/cl100k_base.tiktoken")
    ids = knap.encode_ordinary("hello world")
    text = knap.decode(ids)

The extension must be built first, and rebuilt whenever the Mojo toolchain
changes, because the Mojo ABI is not stable:

    python bindings/python/build.py
"""

from .tokenizer import Tokenizer, KnapNotBuiltError

__all__ = ["Tokenizer", "KnapNotBuiltError"]

# =============================================================================
# End of file: bindings/python/knap_py/__init__.py
# =============================================================================
