# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : examples/chunker.mojo
# Purpose     : Splits a document into overlapping windows and pads them
#               into the rectangle a model takes.
# Stage       : Examples. See examples/README.md
# Depends on  : knap.tokenizer
# Invariants  : Windows are byte ranges into the original document, so the
#               text can be recovered without decoding anything.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Split a document for retrieval, then pad the pieces for a model.

This is the shape of the work in front of most embedding pipelines, and it
is where the obvious implementation goes wrong. The obvious one encodes the
document, cuts the id list every N ids, and decodes each piece back to text.
Those pieces begin and end inside tokens: they decode to mangled text and
they re-encode to different ids, and every step of the program succeeds.

`windows_ordinary` cuts on pre-token boundaries instead, and hands back byte
ranges rather than text. Two things follow. The original bytes are still
there, so a retrieval hit can point at the source rather than at a copy. And
the encoding of a window is exactly the slice of the whole document's
encoding that covers it, which is what makes the pieces and the whole
consistent.

The second half pads those windows into a rectangle, which is what a model
takes. That is a different operation with a different rule: it truncates by
token, not by pre-token, because a fixed width input needs exactly that many
columns.

    mojo run -I src examples/chunker.mojo LICENSE 128 16
"""

from std.sys import argv

from knap.tokenizer import load_cl100k_base_tokenizer

comptime VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Where this example looks for a vocabulary."""

comptime END_OF_TEXT_ID = 100257
"""The cl100k_base marker, reused as padding.

No encoding this library ships defines a padding token, so a caller has to
choose one. Reusing the end of text marker is the common choice, and the
attention mask is what tells padding from content.
"""

comptime PREVIEW_BYTES = 48
"""How much of each window to print."""


def main() raises:
    """Window a document, then pad the windows into a rectangle.

    Raises:
        Error: if the arguments are missing, the file cannot be read, or the
            vocabulary will not load.
    """
    var args = argv()
    if len(args) < 3:
        raise Error(
            String("usage: chunker <file> <window_tokens> [overlap_tokens]")
        )

    var path = String(args[1])
    var window_tokens = Int(String(args[2]))
    var overlap_tokens = 0
    if len(args) > 3:
        overlap_tokens = Int(String(args[3]))

    var handle = open(path, "r")
    var data = handle.read_bytes()
    handle.close()

    var tokenizer = load_cl100k_base_tokenizer(String(VOCAB))
    var windows = tokenizer.windows_ordinary_bytes(
        Span(data), window_tokens, overlap_tokens
    )

    print(
        len(data),
        "bytes into",
        len(windows),
        "windows of at most",
        window_tokens,
        "tokens, overlapping by",
        overlap_tokens,
    )

    # The windows are byte ranges, so the text comes from the original
    # buffer. Nothing is decoded and nothing is copied except the preview.
    var texts = List[String]()
    for index in range(len(windows)):
        var window = windows[index]
        var end = window.start + PREVIEW_BYTES
        if end > window.end:
            end = window.end
        var preview = String(unsafe_from_utf8=Span(data)[window.start : end])
        print("  ", window, " ", preview.replace("\n", " "), sep="")

        texts.append(
            String(unsafe_from_utf8=Span(data)[window.start : window.end])
        )

    if len(texts) == 0:
        print("nothing to pad")
        return

    # And the rectangle a model takes. Padded to the longest window, with a
    # mask saying which columns are real.
    var batch = tokenizer.pad_ordinary_batch(texts, END_OF_TEXT_ID)
    var real = 0
    for index in range(len(batch.mask)):
        if batch.mask[index] != 0:
            real += 1

    print(
        "padded to",
        batch.rows,
        "by",
        batch.width,
        "with",
        real,
        "real tokens and",
        len(batch.ids) - real,
        "padding",
    )


# =============================================================================
# End of file: examples/chunker.mojo
# =============================================================================
