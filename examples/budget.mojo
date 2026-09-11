# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : examples/budget.mojo
# Purpose     : Checks files against a context window without tokenizing
#               the ones that obviously do not fit.
# Stage       : Examples. See examples/README.md
# Depends on  : knap.tokenizer
# Invariants  : Prints only numbers it measured. A file that cannot be read
#               is reported rather than skipped.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Check files against a token budget.

The question this answers is the most common one anyone has for a
tokenizer: does this fit. It is worth an example because the obvious way to
answer it is wasteful in two separate ways, and Knap has an entry point for
each.

The obvious way encodes the document and takes the length of the list. That
builds a list of ids to read one number off it, which on a large document is
hundreds of megabytes of allocation thrown away immediately.
`count_ordinary` walks the same scanner and merge loop and never builds it.

The obvious way also counts the whole document even when the first tenth of
it has already blown the budget. `fits_ordinary` stops as soon as the budget
is exceeded, which is the difference between checking a hundred megabyte
file against a context window and tokenizing it.

    mojo run -I src examples/budget.mojo 2048 LICENSE tests/fixtures/corpus/ascii_en.txt
"""

from std.sys import argv

from knap.tokenizer import load_cl100k_base_tokenizer

comptime VOCAB = "tests/fixtures/vocabs/cl100k_base.tiktoken"
"""Where this example looks for a vocabulary.

Vocabularies are fetched rather than committed. `python
scripts/fetch_vocabs.py` puts them here.
"""


def read_file(path: String) raises -> List[UInt8]:
    """Read a whole file as bytes.

    Args:
        path: The file to read.

    Returns:
        Its contents.

    Raises:
        Error: if it cannot be opened.
    """
    var handle = open(path, "r")
    var data = handle.read_bytes()
    handle.close()
    return data^


def main() raises:
    """Report which of the given files fit in the given budget.

    Raises:
        Error: if the arguments are missing or the vocabulary will not load.
    """
    var args = argv()
    if len(args) < 3:
        raise Error(String("usage: budget <max_tokens> <file> [file ...]"))

    var budget = Int(String(args[1]))
    var tokenizer = load_cl100k_base_tokenizer(String(VOCAB))

    print("budget:", budget, "tokens, encoding cl100k_base")

    for index in range(2, len(args)):
        var path = String(args[index])
        var data: List[UInt8]
        try:
            data = read_file(path)
        except:
            print(path, "could not be read")
            continue

        # The cheap question first. On a file that is far too long this
        # stops early and never counts the rest.
        if not tokenizer.fits_ordinary_bytes(Span(data), budget):
            # It does not fit, so say by how much and where to cut. Both of
            # these walk the document, which is the price of a useful
            # answer rather than a yes or no.
            var total = tokenizer.count_ordinary_bytes(Span(data))
            var cut = tokenizer.truncate_ordinary_bytes(Span(data), budget)
            print(
                path,
                "does not fit:",
                total,
                "tokens, over by",
                total - budget,
                "and fits up to byte",
                cut,
                "of",
                len(data),
            )
            continue

        var total = tokenizer.count_ordinary_bytes(Span(data))
        print(path, "fits:", total, "tokens, with", budget - total, "spare")


# =============================================================================
# End of file: examples/budget.mojo
# =============================================================================
