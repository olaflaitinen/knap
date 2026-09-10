# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : cli/main.mojo
# Purpose     : The command line tool. Counts, encodes, and decodes.
# Stage       : Command line interface. See README.md
# Depends on  : args.mojo for parsing, knap.tokenizer for the work.
# Invariants  : Decoded output is written as raw bytes, never through a text
#               conversion, because byte level BPE can decode to a partial
#               UTF-8 sequence and a lossy write would break a round trip.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""The Knap command line tool.

Named main.mojo rather than knap.mojo, which is what it wanted to be. A Mojo
file's module name is its stem, so cli/knap.mojo declares a module called
knap, and the compiler refuses it: a module cannot import itself, and this
one imports knap.tokenizer. The binary is still called knap; only the source
file is not.

Counting tokens is the most common thing anyone does with a tokenizer, and
until now doing it meant having a Mojo toolchain and writing a program. This
is one binary that anyone can run.

    knap count "how many tokens is this"
    cat prompt.txt | knap count
    knap encode --format json "hello" | jq
    knap encode "hello" | knap decode

Three things about the design are worth stating, because each one is a
decision rather than an accident.

**Decoded output is raw bytes.** It is written to /dev/stdout without any
text conversion. Byte level BPE genuinely can decode to a partial UTF-8
sequence, whenever a caller decodes a slice of a longer token list, and a
tool that substituted replacement characters there would quietly stop being
a round trip. `knap encode X | knap decode` returns X, byte for byte,
including when X is not valid UTF-8.

**Markers are text by default.** A `<|endoftext|>` written in the input
encodes as the characters that spell it, not as the control token. That is
what the reference implementation's ordinary encode does, and it is the
right default for a tool that will mostly be pointed at text somebody else
wrote. Naming a marker with --allowed-special opts in.

**Standard input is only read when it is not a terminal.** Running `knap
count` with no argument at a prompt prints usage rather than appearing to
hang, which is what a naive read would do.
"""

from std.ffi import external_call
from std.io import FileDescriptor
from std.sys import argv, exit

from args import (
    COMMAND_COUNT,
    COMMAND_DECODE,
    COMMAND_ENCODE,
    COMMAND_HELP,
    COMMAND_VERSION,
    COMMAND_VOCAB,
    CLI_VERSION,
    EXIT_FAILURE,
    EXIT_OK,
    EXIT_USAGE,
    Options,
    format_ids,
    parse_arguments,
    parse_ids,
    usage,
    vocabulary_candidates,
)
from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_gpt2_tokenizer,
    load_o200k_base_tokenizer,
    load_o200k_harmony_tokenizer,
    load_p50k_base_tokenizer,
    load_p50k_edit_tokenizer,
    load_r50k_base_tokenizer,
)


def is_terminal(descriptor: Int) -> Bool:
    """Report whether a file descriptor is attached to a terminal.

    Args:
        descriptor: 0 for standard input, 1 for standard output.

    Returns:
        True when a person is on the other end.

    Used for one thing only: refusing to block on standard input when nobody
    is piping anything in. A tool that hangs silently at a prompt looks
    broken even when it is behaving exactly as documented.
    """
    return Int(external_call["isatty", Int32](Int32(descriptor))) == 1


def read_all(path: String) raises -> List[UInt8]:
    """Read a whole file as raw bytes.

    Args:
        path: The file to read.

    Returns:
        Its contents.

    Raises:
        Error: if it cannot be opened, naming the path.

    Bytes rather than text, and this matters more than it looks. Reading as
    text applies newline translation, which would silently rewrite every
    carriage return and line feed pair before the tokenizer saw it, and
    change the answer. That exact bug has already cost this project a day.
    """
    try:
        var handle = open(path, "r")
        var data = handle.read_bytes()
        handle.close()
        return data^
    except:
        raise Error(String(t"knap: cannot read '{path}'"))


def write_bytes(data: Span[UInt8, _]) raises:
    """Write raw bytes to standard output.

    Args:
        data: The bytes to write.

    Raises:
        Error: if the write fails.

    Through a file descriptor rather than a file handle, and the reason was
    found by testing rather than by reasoning. Opening /dev/stdout works when
    standard output is a file or a terminal and fails when it is a pipe,
    because that path resolves through /proc/self/fd to a pipe node. A
    tokenizer whose decode cannot be piped is not much use, and
    `knap encode X | knap decode` is the round trip this tool most wants to
    be able to demonstrate.

    No trailing newline is added. The output of decode is the bytes the
    tokens represent and nothing else, so a round trip through a pipe is
    byte exact even when those bytes are not valid UTF-8.
    """
    var out = FileDescriptor(1)
    out.write_bytes(data)


def resolve_vocabulary(options: Options) raises -> String:
    """Find the vocabulary file for the requested encoding.

    Args:
        options: The parsed command line.

    Returns:
        A path that exists.

    Raises:
        Error: naming every path that was tried, when none exists.
    """
    var candidates = vocabulary_candidates(options.encoding, options.vocabulary)
    for index in range(len(candidates)):
        try:
            var handle = open(candidates[index], "r")
            handle.close()
            return candidates[index]
        except:
            continue

    var message = String(
        t"knap: no vocabulary found for {options.encoding}. Looked at:"
    )
    for index in range(len(candidates)):
        message += String(t"\n  {candidates[index]}")
    message += String(
        "\nFetch one with 'python scripts/fetch_vocabs.py' from a checkout,"
        " or point --vocab at a .tiktoken file."
    )
    raise Error(message)


def load(options: Options) raises -> Tokenizer:
    """Load the tokenizer the command line asked for.

    Args:
        options: The parsed command line.

    Returns:
        The loaded tokenizer.

    Raises:
        Error: if no vocabulary can be found or it will not load.
    """
    var path = resolve_vocabulary(options)
    if options.encoding == "o200k_base":
        return load_o200k_base_tokenizer(path)
    if options.encoding == "o200k_harmony":
        return load_o200k_harmony_tokenizer(path)
    if options.encoding == "gpt2":
        return load_gpt2_tokenizer(path)
    if options.encoding == "r50k_base":
        return load_r50k_base_tokenizer(path)
    if options.encoding == "p50k_base":
        return load_p50k_base_tokenizer(path)
    if options.encoding == "p50k_edit":
        return load_p50k_edit_tokenizer(path)
    return load_cl100k_base_tokenizer(path)


def gather_input(options: Options) raises -> List[UInt8]:
    """Collect the input bytes from wherever they are coming from.

    Args:
        options: The parsed command line.

    Returns:
        The input bytes.

    Raises:
        Error: if a named file cannot be read, or if standard input was the
            only source and a person is sitting at it.
    """
    if options.has_text:
        var out = List[UInt8]()
        var bytes = options.text.as_bytes()
        for index in range(len(bytes)):
            out.append(bytes[index])
        return out^

    if options.input_path != "":
        return read_all(options.input_path)

    if is_terminal(0):
        raise Error(
            String(
                "knap: no input. Give text as an argument, name a file with"
                " --file, or pipe something in."
            )
        )
    return read_all(String("/dev/stdin"))


def encode_input(
    tokenizer: Tokenizer, options: Options, data: Span[UInt8, _]
) raises -> List[Int]:
    """Encode the input under the special token policy the caller asked for.

    Args:
        tokenizer: The loaded tokenizer.
        options: The parsed command line.
        data: The input bytes.

    Returns:
        The token ids.

    Raises:
        Error: if a refused special token is present, or if a name given to
            --allowed-special is not a special token of this encoding.

    Three policies, and the default is the cautious one. Without any flag a
    marker in the input is ordinary text, which can never fail and never
    injects a control token. With --allowed-special the named markers become
    their own ids. With --strict-special any marker at all is an error,
    which is how a caller validates that text is free of them.
    """
    if options.strict_special:
        var none = List[String]()
        return tokenizer.encode_bytes(data, none)

    if len(options.allowed_special) > 0:
        return tokenizer.encode_bytes(data, options.allowed_special)

    return tokenizer.encode_ordinary_bytes(data)


def count_input(
    tokenizer: Tokenizer, options: Options, data: Span[UInt8, _]
) raises -> Int:
    """Count the input under the same policy encode_input would apply.

    Args:
        tokenizer: The loaded tokenizer.
        options: The parsed command line.
        data: The input bytes.

    Returns:
        How many tokens the input becomes.

    Raises:
        Error: exactly where encode_input would raise, and for the same
            reasons. A count of a document that could not be encoded is a
            number nobody can act on.

    The same three policies, answered without building the list of ids. On a
    four megabyte document that list is over a million appends into a buffer
    that grows to about ten megabytes and is then dropped to print one
    number.
    """
    if options.strict_special:
        var none = List[String]()
        return tokenizer.count_bytes(data, none)

    if len(options.allowed_special) > 0:
        return tokenizer.count_bytes(data, options.allowed_special)

    return tokenizer.count_ordinary_bytes(data)


def show_vocabulary(tokenizer: Tokenizer, options: Options) raises:
    """Print what is known about the loaded encoding.

    Args:
        tokenizer: The loaded tokenizer.
        options: The parsed command line.

    Raises:
        Error: if the special token registry cannot be read.
    """
    var merges = tokenizer.vocabulary.merges.size()
    var past_specials = tokenizer.vocabulary.specials.highest_id() + 1
    var n_vocab = merges
    if past_specials > n_vocab:
        n_vocab = past_specials

    print("encoding:", options.encoding)
    # One past the highest assigned id, which is not always the count of
    # decodable ids. cl100k_base and o200k_base leave holes, because their
    # special tokens do not sit flush against the merge ranks. The other
    # five have none.
    print("n_vocab:", n_vocab)
    print("merge tokens:", merges)
    print("merge ranks:", tokenizer.ranks.size())
    print("special tokens:", tokenizer.vocabulary.specials.count())
    for index in range(tokenizer.vocabulary.specials.count()):
        print(
            "  ",
            tokenizer.vocabulary.specials.id_at(index),
            " ",
            tokenizer.vocabulary.specials.name_at(index),
            sep="",
        )


def run(options: Options) raises -> Int:
    """Carry out one command.

    Args:
        options: The parsed command line.

    Returns:
        The process exit status.

    Raises:
        Error: on any failure that should stop the run, which main turns
            into a message and a non zero status.
    """
    if options.command == COMMAND_HELP:
        print(usage())
        return EXIT_OK

    if options.command == COMMAND_VERSION:
        print(CLI_VERSION)
        return EXIT_OK

    if options.command == COMMAND_VOCAB:
        var tokenizer = load(options)
        show_vocabulary(tokenizer, options)
        return EXIT_OK

    var data = gather_input(options)

    if options.command == COMMAND_DECODE:
        var text = String(unsafe_from_utf8=Span(data))
        var ids = parse_ids(text)
        var tokenizer = load(options)
        var bytes = tokenizer.decode_bytes(ids)
        write_bytes(Span(bytes))
        return EXIT_OK

    var tokenizer = load(options)

    if options.command == COMMAND_COUNT:
        print(count_input(tokenizer, options, Span(data)))
        return EXIT_OK

    var ids = encode_input(tokenizer, options, Span(data))

    if options.command == COMMAND_ENCODE:
        print(format_ids(ids, options.format))
        return EXIT_OK

    return EXIT_USAGE


def main():
    """Parse the command line, run it, and report."""
    var raw = argv()
    var arguments = List[String]()
    for index in range(1, len(raw)):
        arguments.append(String(raw[index]))

    var options = parse_arguments(arguments)
    if options.error != "":
        print("knap:", options.error)
        exit(EXIT_USAGE)

    try:
        exit(run(options))
    except error:
        print(error)
        exit(EXIT_FAILURE)


# =============================================================================
# End of file: cli/main.mojo
# =============================================================================
