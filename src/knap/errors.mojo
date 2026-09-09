# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/errors.mojo
# Purpose     : Error constructors for every failure Knap reports, so that
#               messages are consistent and locate the problem precisely.
# Stage       : Support module, used by every pipeline stage
# Depends on  : Nothing outside the Mojo standard library.
# Invariants  : Every constructor names what was expected and what was found.
#               Nothing here is called on a successful encode or decode, so
#               these allocate only on a path that is already failing.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Error construction for Knap.

Knap must not panic on user input. A malformed vocabulary file, an out of
range token id, or a disallowed special token is a condition the caller can
handle, so each returns an error rather than aborting the process.

The constructors live together in one module for a single reason: error text
is part of the interface. When a vocabulary fails to load, the message is
often all the user has, so the wording is written once here rather than
improvised at each raise site.

Nothing in this module is reached during a successful encode or decode. The
"no allocation on the hot path" rule in docs/STYLE.md is satisfied by these
functions never being called on that path, not by avoiding allocation inside
them.

A note on message construction. A "t" prefixed string is a template string,
interpolating the expressions inside its braces. Unlike ordinary literals,
template strings do not concatenate by adjacency, so a message that spans
several lines is built by appending to a String rather than by writing two
literals next to each other.
"""


# -----------------------------------------------------------------------------
# Vocabulary loading
#
# These four cover every way a .tiktoken file can be wrong. Each names the
# line number, because a vocabulary has a hundred thousand lines and
# "invalid vocabulary" is not an actionable message.
# -----------------------------------------------------------------------------


def vocabulary_file_missing(path: String) -> Error:
    """Build the error for a vocabulary file that cannot be opened.

    Args:
        path: The path that was attempted.

    Returns:
        An Error naming the path and pointing at the fetch script, because a
        missing vocabulary is nearly always a setup step that has not been
        run rather than a defect in Knap.
    """
    var message = String(t"knap: cannot open vocabulary file '{path}'.")
    message += " Vocabulary files are fetched, not committed: run"
    message += " 'python scripts/fetch_vocabs.py' first."
    return Error(message)


def vocabulary_malformed_line(path: String, line: Int, reason: String) -> Error:
    """Build the error for a vocabulary line that does not parse.

    Args:
        path: The vocabulary file being read.
        line: One based line number of the offending line, or 0 when the
            problem is with the file as a whole.
        reason: What specifically was wrong.

    Returns:
        An Error naming the file, the line, and the reason.
    """
    var message = String(t"knap: {path} line {line} is malformed: {reason}.")
    message += " A vocabulary line is a base64 token, a space, then a"
    message += " decimal rank."
    return Error(message)


def vocabulary_duplicate_rank(path: String, line: Int, rank: Int) -> Error:
    """Build the error for a rank that appears twice in one vocabulary.

    Args:
        path: The vocabulary file being read.
        line: One based line number where the repeat was found.
        rank: The rank that was already assigned.

    Returns:
        An Error naming the repeated rank.

    A duplicate rank is worth its own error rather than a silent overwrite.
    Two tokens claiming one id would make decoding ambiguous, and it would
    shift nothing visible until the affected token appeared in real input.
    """
    var message = String(t"knap: {path} line {line} reuses rank {rank},")
    message += " which is already assigned to another token. Ranks must be"
    message += " unique."
    return Error(message)


def vocabulary_rank_out_of_range(path: String, line: Int, rank: Int) -> Error:
    """Build the error for a negative rank.

    Args:
        path: The vocabulary file being read.
        line: One based line number of the offending line.
        rank: The value that was read.

    Returns:
        An Error naming the offending rank.
    """
    var message = String(t"knap: {path} line {line} has rank {rank},")
    message += " which is negative. Ranks index the vocabulary and cannot be"
    message += " below zero."
    return Error(message)


# -----------------------------------------------------------------------------
# Decoding
# -----------------------------------------------------------------------------


def token_id_out_of_range(token_id: Int, vocabulary_size: Int) -> Error:
    """Build the error for a token id with no entry in the vocabulary.

    Args:
        token_id: The id that was requested.
        vocabulary_size: How many ids the loaded vocabulary defines.

    Returns:
        An Error naming both the id and the valid range.

    This is raised rather than clamped or skipped. A caller decoding an id
    the vocabulary does not define has a bug upstream, and silently dropping
    the token would hide it while changing the output.
    """
    var last = vocabulary_size - 1
    var message = String(t"knap: token id {token_id} is out of range for a")
    message += String(t" vocabulary of {vocabulary_size} tokens.")
    message += String(t" Valid ids are 0 to {last}.")
    return Error(message)


# -----------------------------------------------------------------------------
# Special tokens
# -----------------------------------------------------------------------------


def special_token_disallowed(name: String) -> Error:
    """Build the error for a disallowed special token found in input.

    Args:
        name: The literal special token text that was found.

    Returns:
        An Error naming the token and how to permit it.

    Matching tiktoken, a special token literal that the caller has not
    allowed is an error rather than something to encode as ordinary text.
    Encoding it silently would let untrusted input inject control tokens
    into a prompt.
    """
    var message = String(t"knap: the special token '{name}' appears in the")
    message += " input but is not in the allowed set. Pass it in"
    message += " allowed_special to permit it, or remove it from the input."
    return Error(message)


def special_token_unknown(name: String) -> Error:
    """Build the error for a special token the vocabulary does not define.

    Args:
        name: The special token text that was requested.

    Returns:
        An Error naming the unknown token.
    """
    return Error(
        String(t"knap: '{name}' is not a special token in this vocabulary.")
    )


def token_id_unassigned(token_id: Int) -> Error:
    """Build the error for an id that is reserved rather than assigned.

    Args:
        token_id: The id that was asked for.

    Returns:
        An error naming the id.

    Distinct from an out of range id, because the two mean different things
    to a caller. Out of range says the id cannot exist in this encoding.
    This says it exists in the space and nothing was put there.

    Two different things reach this. The merge table raises it for a
    reserved rank, which happens once, at p50k_base's 50256. A vocabulary
    raises it for an id that is neither an assigned merge nor a special,
    which is the sixteen holes in cl100k_base and the nineteen in
    o200k_base. p50k_base's 50256 is not one of those: its special token
    fills the hole, so the merge table refuses the rank and the vocabulary
    answers with the marker.
    """
    return Error(
        String(
            t"knap: token id {token_id} is reserved and has no bytes. It is"
            t" inside the id space but nothing is assigned to it."
        )
    )


# =============================================================================
# End of file: src/knap/errors.mojo
# =============================================================================
