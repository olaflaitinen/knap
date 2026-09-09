# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : cli/args.mojo
# Purpose     : Argument parsing, vocabulary resolution, and output shaping
#               for the command line tool.
# Stage       : Command line interface. See README.md
# Depends on  : std.os for the environment. Nothing from knap itself.
# Invariants  : Everything here is a pure function of its arguments and the
#               environment. No file is read and nothing is printed, so all
#               of it is testable without a tokenizer or a vocabulary.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Argument handling for the Knap command line tool.

Kept apart from the tool itself so that it can be tested. Everything in this
file is a pure function of its arguments and of the environment: nothing
opens a file, nothing prints, and nothing needs a vocabulary. That is what
lets tests/test_cli.mojo check the parser exhaustively without touching the
filesystem.

The parser is written by hand rather than pulled from a library. It is a few
hundred lines, the surface is small and fixed, and a dependency here would be
a dependency in the one artefact this project wants people to be able to
install without thinking about it.
"""

from std.os import getenv

comptime CLI_VERSION: StaticString = "1.0.0"
"""The version this tool reports. Matches the project version."""

comptime COMMAND_NONE: Int = 0
"""No command was given."""

comptime COMMAND_COUNT: Int = 1
"""Print how many tokens the input becomes."""

comptime COMMAND_ENCODE: Int = 2
"""Print the token ids the input becomes."""

comptime COMMAND_DECODE: Int = 3
"""Turn token ids back into the bytes they represent."""

comptime COMMAND_VOCAB: Int = 4
"""Print what is known about an encoding."""

comptime COMMAND_HELP: Int = 5
"""Print usage."""

comptime COMMAND_VERSION: Int = 6
"""Print the version."""

comptime FORMAT_SPACE: Int = 0
"""Token ids on one line, separated by spaces. The default."""

comptime FORMAT_LINES: Int = 1
"""One token id per line."""

comptime FORMAT_JSON: Int = 2
"""A JSON array of token ids."""

comptime EXIT_OK: Int = 0
"""Everything worked."""

comptime EXIT_FAILURE: Int = 1
"""The command ran and failed: no vocabulary, bad input, refused marker."""

comptime EXIT_USAGE: Int = 2
"""The command line itself was wrong."""

comptime DEFAULT_ENCODING: StaticString = "cl100k_base"
"""Used when no encoding is named.

cl100k_base rather than o200k_base because it is what most existing tooling
and most published token counts assume. A default that surprises people is
worse than a default that is merely older.
"""


def is_known_encoding(name: String) -> Bool:
    """Report whether an encoding name is one this tool ships.

    Args:
        name: The name to check.

    Returns:
        True when the name is supported.
    """
    return name == "cl100k_base" or name == "o200k_base"


struct Options(Movable):
    """Everything the command line said, after parsing.

    An invalid command line produces an Options with a non empty error rather
    than raising. The caller decides what to do about it, which keeps the
    parser testable and keeps the usage message in one place.
    """

    var command: Int
    """Which subcommand, as one of the COMMAND constants."""

    var encoding: String
    """The encoding name, defaulted if not given."""

    var vocabulary: String
    """An explicit vocabulary path, or empty to search."""

    var input_path: String
    """A path to read input from, or empty."""

    var text: String
    """Input given directly on the command line."""

    var has_text: Bool
    """Whether text was given on the command line at all.

    Separate from text being empty, because encoding the empty string is a
    legitimate request that must produce zero tokens rather than a read from
    standard input.
    """

    var format: Int
    """How to shape the token ids, as one of the FORMAT constants."""

    var allowed_special: List[String]
    """Special token literals the input is permitted to contain."""

    var strict_special: Bool
    """Whether any special token in the input is an error."""

    var error: String
    """A usage problem, or empty when the command line was well formed."""

    def __init__(out self):
        """Build the default options, before any argument is read."""
        self.command = COMMAND_NONE
        self.encoding = String(DEFAULT_ENCODING)
        self.vocabulary = String("")
        self.input_path = String("")
        self.text = String("")
        self.has_text = False
        self.format = FORMAT_SPACE
        self.allowed_special = List[String]()
        self.strict_special = False
        self.error = String("")

    def reads_input(self) -> Bool:
        """Report whether this command consumes input at all.

        Returns:
            True for the commands that read text or token ids.
        """
        return (
            self.command == COMMAND_COUNT
            or self.command == COMMAND_ENCODE
            or self.command == COMMAND_DECODE
        )

    def reads_standard_input(self) -> Bool:
        """Report whether input will come from standard input.

        Returns:
            True when the command needs input and none was given another way.
        """
        return (
            self.reads_input() and not self.has_text and self.input_path == ""
        )


def command_from(name: String) -> Int:
    """Map a subcommand name to its constant.

    Args:
        name: The word given as the first argument.

    Returns:
        The command constant, or COMMAND_NONE when unrecognised.
    """
    if name == "count":
        return COMMAND_COUNT
    if name == "encode":
        return COMMAND_ENCODE
    if name == "decode":
        return COMMAND_DECODE
    if name == "vocab":
        return COMMAND_VOCAB
    if name == "help" or name == "--help" or name == "-h":
        return COMMAND_HELP
    if name == "version" or name == "--version" or name == "-V":
        return COMMAND_VERSION
    return COMMAND_NONE


def format_from(name: String) -> Int:
    """Map a format name to its constant.

    Args:
        name: The value given to the format option.

    Returns:
        The format constant, or -1 when unrecognised.
    """
    if name == "space":
        return FORMAT_SPACE
    if name == "lines":
        return FORMAT_LINES
    if name == "json":
        return FORMAT_JSON
    return -1


def needs_value(flag: String) -> Bool:
    """Report whether a flag takes a following value.

    Args:
        flag: The flag as written, including its dashes.

    Returns:
        True when the next argument belongs to this flag.
    """
    return (
        flag == "-e"
        or flag == "--encoding"
        or flag == "-f"
        or flag == "--file"
        or flag == "--vocab"
        or flag == "--format"
        or flag == "--allowed-special"
    )


def parse_arguments(arguments: List[String]) -> Options:
    """Parse a whole command line.

    Args:
        arguments: The arguments after the program name.

    Returns:
        The parsed options, with a non empty error when the line was wrong.

    Deliberately does not raise. A usage error is an ordinary outcome of
    running a command line tool, and returning it as data keeps the parser
    free of control flow that a test would have to catch.
    """
    var options = Options()

    if len(arguments) == 0:
        options.command = COMMAND_HELP
        return options^

    options.command = command_from(arguments[0])
    if options.command == COMMAND_NONE:
        options.error = String(
            t"unknown command '{arguments[0]}'. Try 'knap help'."
        )
        return options^

    var index = 1
    while index < len(arguments):
        var argument = arguments[index]

        if needs_value(argument):
            if index + 1 >= len(arguments):
                options.error = String(t"'{argument}' needs a value")
                return options^
            var value = arguments[index + 1]
            index += 2

            if argument == "-e" or argument == "--encoding":
                if not is_known_encoding(value):
                    options.error = String(
                        t"unknown encoding '{value}'. This tool ships"
                        t" cl100k_base and o200k_base."
                    )
                    return options^
                options.encoding = value
            elif argument == "-f" or argument == "--file":
                options.input_path = value
            elif argument == "--vocab":
                options.vocabulary = value
            elif argument == "--format":
                var shape = format_from(value)
                if shape < 0:
                    options.error = String(
                        t"unknown format '{value}'. Use space, lines, or json."
                    )
                    return options^
                options.format = shape
            else:
                options.allowed_special.append(value)
            continue

        if argument == "--strict-special":
            options.strict_special = True
            index += 1
            continue

        if argument == "-h" or argument == "--help":
            options.command = COMMAND_HELP
            return options^

        if argument == "--version" or argument == "-V":
            options.command = COMMAND_VERSION
            return options^

        if argument == "-":
            # The conventional spelling of "read standard input". Accepted
            # so that a script can be explicit rather than relying on the
            # absence of an argument meaning something.
            index += 1
            continue

        # byte_length rather than len. Mojo refuses len on a string,
        # because bytes, code points and grapheme clusters are three
        # different answers and it will not guess which one was meant.
        if argument.byte_length() > 1 and argument.startswith("-"):
            options.error = String(
                t"unknown option '{argument}'. Try 'knap help'."
            )
            return options^

        if options.has_text:
            options.error = String(
                "more than one input was given on the command line. Use one"
                " argument, or --file, or standard input."
            )
            return options^
        options.text = argument
        options.has_text = True
        index += 1

    if options.has_text and options.input_path != "":
        options.error = String("both text and --file were given. Choose one.")
        return options^

    if options.strict_special and len(options.allowed_special) > 0:
        options.error = String(
            "--strict-special refuses every special token, so it cannot be"
            " combined with --allowed-special."
        )
        return options^

    return options^


def vocabulary_candidates(encoding: String, explicit: String) -> List[String]:
    """List the paths that will be tried for a vocabulary, in order.

    Args:
        encoding: The encoding name.
        explicit: A path given with the vocabulary option, or empty.

    Returns:
        Paths to try, most specific first.

    Returned as a list rather than resolved here so that the failure message
    can name every place that was looked at. A tool that says "not found"
    without saying where it looked wastes the reader's time.
    """
    var candidates = List[String]()
    var name = encoding + String(".tiktoken")

    if explicit != "":
        candidates.append(explicit)
        return candidates^

    var directory = getenv("KNAP_VOCAB_DIR")
    if directory != "":
        candidates.append(directory + String("/") + name)

    var cache = getenv("XDG_CACHE_HOME")
    if cache != "":
        candidates.append(cache + String("/knap/") + name)
    else:
        var home = getenv("HOME")
        if home != "":
            candidates.append(home + String("/.cache/knap/") + name)

    # A checkout of the repository, so the tool works during development
    # without any setup at all.
    candidates.append(String("tests/fixtures/vocabs/") + name)

    # The working directory, which is where a person who downloaded one file
    # will have put it.
    candidates.append(name)

    return candidates^


def format_ids(ids: List[Int], shape: Int) -> String:
    """Render token ids in the requested shape.

    Args:
        ids: The token ids.
        shape: One of the FORMAT constants.

    Returns:
        The rendered text, without a trailing newline.
    """
    var out = String("")

    if shape == FORMAT_JSON:
        out += "["
        for index in range(len(ids)):
            if index > 0:
                out += ","
            out += String(ids[index])
        out += "]"
        return out^

    var separator = String(" ")
    if shape == FORMAT_LINES:
        separator = String("\n")

    for index in range(len(ids)):
        if index > 0:
            out += separator
        out += String(ids[index])
    return out^


def parse_ids(text: String) raises -> List[Int]:
    """Read token ids out of text.

    Args:
        text: Digits separated by anything that is not a digit.

    Returns:
        The ids, in order.

    Raises:
        Error: if the text holds no digits at all, which almost always means
            the wrong thing was piped in.

    Deliberately permissive about separators, so that the output of
    `knap encode` in any of its three formats can be piped straight back
    into `knap decode`. Commas, spaces, newlines and brackets are all just
    not-digits.
    """
    var bytes = text.as_bytes()
    var ids = List[Int]()
    var value = 0
    var in_number = False

    for index in range(len(bytes)):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            value = value * 10 + (Int(byte) - 48)
            in_number = True
        else:
            if in_number:
                ids.append(value)
            value = 0
            in_number = False

    if in_number:
        ids.append(value)

    if len(ids) == 0:
        raise Error(
            String(
                "knap decode: the input holds no token ids. It expects"
                " decimal numbers, in any of the formats knap encode"
                " produces."
            )
        )
    return ids^


def usage() -> String:
    """Return the usage text.

    Returns:
        The whole help message, without a trailing newline.
    """
    var out = String("knap ") + String(CLI_VERSION)
    out += "\nA byte level BPE tokenizer with verified tiktoken parity.\n"
    out += "\nUSAGE\n"
    out += "  knap <command> [options] [text]\n"
    out += "\nCOMMANDS\n"
    out += "  count     Print how many tokens the input becomes\n"
    out += "  encode    Print the token ids the input becomes\n"
    out += "  decode    Turn token ids back into the bytes they represent\n"
    out += "  vocab     Print what is known about an encoding\n"
    out += "  help      Print this message\n"
    out += "  version   Print the version\n"
    out += "\nINPUT\n"
    out += "  Given as an argument, with --file, or on standard input.\n"
    out += "  A lone - means standard input, spelled out.\n"
    out += "\nOPTIONS\n"
    out += "  -e, --encoding NAME   cl100k_base or o200k_base."
    out += " Default cl100k_base.\n"
    out += "  -f, --file PATH       Read the input from a file.\n"
    out += "      --vocab PATH      Use this vocabulary file.\n"
    out += "      --format SHAPE    space, lines, or json. Default space.\n"
    out += "      --allowed-special NAME\n"
    out += "                        Permit this special token in the input."
    out += " Repeatable.\n"
    out += "      --strict-special  Refuse any special token in the input.\n"
    out += "  -h, --help            Print this message\n"
    out += "  -V, --version         Print the version\n"
    out += "\nSPECIAL TOKENS\n"
    out += "  By default a marker such as <|endoftext|> written in the input"
    out += " is\n  treated as ordinary characters, which is what the"
    out += " reference\n  implementation's ordinary encode does and what is"
    out += " safe for text that\n  came from somewhere else. Naming a marker"
    out += " with --allowed-special makes\n  it encode as its own id."
    out += " --strict-special makes any marker an error.\n"
    out += "\nVOCABULARIES\n"
    out += "  Not bundled. They are looked for, in order, at:\n"
    out += "    the path given to --vocab\n"
    out += "    $KNAP_VOCAB_DIR/<encoding>.tiktoken\n"
    out += "    $XDG_CACHE_HOME/knap/<encoding>.tiktoken,"
    out += " or ~/.cache/knap/\n"
    out += "    tests/fixtures/vocabs/<encoding>.tiktoken\n"
    out += "    <encoding>.tiktoken in the working directory\n"
    out += "\nEXIT STATUS\n"
    out += "  0  success\n"
    out += "  1  the command ran and failed\n"
    out += "  2  the command line was wrong\n"
    return out^


# =============================================================================
# End of file: cli/args.mojo
# =============================================================================
