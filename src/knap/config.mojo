# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/config.mojo
# Purpose     : Compile time build toggles, read from the command line.
# Stage       : Support module, consulted by the hot paths
# Depends on  : std.sys
# Invariants  : Every toggle resolves at compile time, so a disabled feature
#               costs nothing at run time, not even a branch.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Build time configuration for Knap.

Toggles are compile time, not run time. A feature switched off is not
compiled in at all, so it costs nothing on the hot path, not even a
predictable branch. That matters here because the two things these switches
control both sit inside the innermost loops.

Set a toggle on the command line:

    mojo build -D KNAP_SIMD=1 ...

There is one toggle, not two. The piece cache was going to be the second and
is not, because a compile time flag turned out to be the wrong shape for it:
a flag makes it impossible to exercise both paths in one binary, and the
cached path has to be tested against the uncached one in the same test run.
The cache is a type the caller owns instead, knap.cache.PieceCache, passed to
the cached encode entry points. That also puts its memory cost at the call
site rather than hiding it in a build flag.

A note on how this is read, because the compiler's own help is misleading.
The help text for -D says the value is queried "with the std.defines module",
and no such module exists in Mojo 1.0.0. What does exist is
std.sys.is_defined, which reports whether a name was defined at all. That is
enough for a boolean switch, and it is what this file uses. The finding is
recorded in docs/ARCHITECTURE.md alongside the other corrections.
"""

from std.sys import is_defined


comptime SIMD_CLASSIFIER: Bool = is_defined["KNAP_SIMD"]()
"""True when the vectorised classifier is compiled in. Off by default.

Off because it cannot be shown to help, which is a weaker statement than
saying it lost and is the one the measurements support. Over five
repetitions of the pre-tokenization benchmark the scalar path ran at
19.25 MB/s with a standard deviation of 2.20 for cl100k_base, and the
vectorised path at 19.91 with 1.14. For o200k_base the figures are 14.36
against 14.72. The intervals overlap, and single runs of the same benchmark
have placed the vectorised path as much as 29 percent behind and 15 percent
ahead.

An earlier version of this docstring asserted specific losses of two and 52
percent. Those came from a benchmark reading the corpus's generated hazard
section rather than prose, and they were wrong. The correction is recorded
rather than quietly removed, because a confident number from a bad
measurement is worse than no number, and this one survived several
documents.

The structural argument for why a gain is unlikely still stands and is worth
keeping: pre-tokenization produces pieces averaging about four bytes, and a
32 lane vector can only advance when all 32 lanes qualify, so the vector
load and compare almost always fails. That predicts a loss. The machine
cannot resolve one.

The code is kept, compiled, and tested rather than deleted. It is correct,
tests/test_classifier_parity.mojo holds it to the scalar path, and the
measurement is specific to this machine's lane count and this corpus's piece
lengths. Someone with wider pieces or a wider vector unit should re-measure
rather than rewrite. The numbers are in docs/BENCHMARKS.md.
"""

comptime SCALAR_ONLY: Bool = not SIMD_CLASSIFIER
"""True when the vectorised classifier is compiled out, which is the default.

The scalar classifier is the reference implementation and stays in the
repository permanently. It is what tests/test_classifier_parity.mojo
compares the vectorised path against.
"""

# =============================================================================
# End of file: src/knap/config.mojo
# =============================================================================
