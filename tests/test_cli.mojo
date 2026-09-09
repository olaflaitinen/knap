# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_cli.mojo
# Purpose     : Tests the command line parser, formatter, and vocabulary
#               search order.
# Stage       : Command line interface. See README.md
# Depends on  : cli/args.mojo, which is pure by construction.
# Invariants  : Nothing here opens a file or runs a tokenizer. Everything
#               under test is a function of its arguments.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Tests for the Knap command line argument handling.

The parser is the part of a command line tool that is easiest to get subtly
wrong and hardest to notice, because a mistake usually produces a plausible
run rather than a failure. So it is separated from the tool into cli/args.mojo
and tested here directly.

What is checked is mostly the refusals. A parser that accepts a good command
line is the easy half; a parser that quietly accepts a contradictory one and
picks a winner is how a person ends up with a token count they did not ask
for. Every combination that should be refused is asserted to be refused, with
a message rather than a raise, because a usage error is an ordinary outcome
of running a command line tool.

    mojo run -I src -I cli tests/test_cli.mojo
"""

from std.testing import assert_equal, assert_true, TestSuite

from args import (
    COMMAND_COUNT,
    COMMAND_DECODE,
    COMMAND_ENCODE,
    COMMAND_HELP,
    COMMAND_VERSION,
    COMMAND_VOCAB,
    FORMAT_JSON,
    FORMAT_LINES,
    FORMAT_SPACE,
    format_ids,
    is_known_encoding,
    parse_arguments,
    parse_ids,
    usage,
    vocabulary_candidates,
)


def words(*items: String) -> List[String]:
    """Build an argument list.

    Args:
        items: The arguments, in order.

    Returns:
        Them, as a list.
    """
    var out = List[String]()
    for index in range(len(items)):
        out.append(items[index])
    return out^


def test_an_empty_command_line_asks_for_help() raises:
    """Running the tool with no arguments explains itself.

    Raises:
        Error: if it does anything else.

    A tool that reads standard input when invoked bare will appear to hang
    at a prompt. Printing usage is the behaviour that does not look broken.
    """
    var options = parse_arguments(List[String]())
    assert_equal(options.command, COMMAND_HELP)
    assert_equal(options.error, String(""))


def test_each_command_is_recognised() raises:
    """Every documented subcommand parses to its own constant.

    Raises:
        Error: if a command is misread.
    """
    assert_equal(parse_arguments(words("count")).command, COMMAND_COUNT)
    assert_equal(parse_arguments(words("encode")).command, COMMAND_ENCODE)
    assert_equal(parse_arguments(words("decode")).command, COMMAND_DECODE)
    assert_equal(parse_arguments(words("vocab")).command, COMMAND_VOCAB)
    assert_equal(parse_arguments(words("help")).command, COMMAND_HELP)
    assert_equal(parse_arguments(words("version")).command, COMMAND_VERSION)
    assert_equal(parse_arguments(words("--help")).command, COMMAND_HELP)
    assert_equal(parse_arguments(words("-h")).command, COMMAND_HELP)
    assert_equal(parse_arguments(words("--version")).command, COMMAND_VERSION)


def test_an_unknown_command_is_refused() raises:
    """A misspelled command names itself in the error.

    Raises:
        Error: if it is accepted or the message is unhelpful.
    """
    var options = parse_arguments(words("frobnicate"))
    assert_true(options.error != "", String("no error was reported"))
    assert_true(
        options.error.find("frobnicate") >= 0,
        String("the message does not name the command"),
    )


def test_defaults_are_the_documented_ones() raises:
    """An unadorned command uses cl100k_base and the space format.

    Raises:
        Error: if a default has drifted from the documentation.
    """
    var options = parse_arguments(words("count", "hello"))
    assert_equal(options.encoding, String("cl100k_base"))
    assert_equal(options.format, FORMAT_SPACE)
    assert_equal(options.vocabulary, String(""))
    assert_equal(options.input_path, String(""))
    assert_true(options.has_text, String("the text was not recorded"))
    assert_equal(options.text, String("hello"))
    assert_true(not options.strict_special, String("strict was set"))
    assert_equal(len(options.allowed_special), 0)


def test_every_option_that_takes_a_value_is_read() raises:
    """Long and short spellings both land in the right field.

    Raises:
        Error: if a value goes to the wrong field.
    """
    var options = parse_arguments(
        words(
            "encode",
            "-e",
            "o200k_base",
            "--format",
            "json",
            "--vocab",
            "/tmp/v.tiktoken",
            "--allowed-special",
            "<|endoftext|>",
            "--allowed-special",
            "<|fim_prefix|>",
        )
    )
    assert_equal(options.error, String(""))
    assert_equal(options.encoding, String("o200k_base"))
    assert_equal(options.format, FORMAT_JSON)
    assert_equal(options.vocabulary, String("/tmp/v.tiktoken"))
    assert_equal(len(options.allowed_special), 2)
    assert_equal(options.allowed_special[1], String("<|fim_prefix|>"))


def test_a_flag_without_its_value_is_refused() raises:
    """A trailing flag that needs a value is a usage error.

    Raises:
        Error: if it is silently ignored.
    """
    var options = parse_arguments(words("count", "-e"))
    assert_true(options.error != "", String("a bare -e was accepted"))


def test_unknown_names_are_refused() raises:
    """An unknown option, encoding, or format is refused by name.

    Raises:
        Error: if any of the three is accepted.
    """
    assert_true(
        parse_arguments(words("count", "--nope", "x")).error != "",
        String("an unknown option was accepted"),
    )
    assert_true(
        parse_arguments(words("count", "-e", "klingon", "x")).error != "",
        String("an unknown encoding was accepted"),
    )
    assert_true(
        parse_arguments(words("encode", "--format", "yaml", "x")).error != "",
        String("an unknown format was accepted"),
    )


def test_contradictory_command_lines_are_refused() raises:
    """Two inputs, or two special token policies, are refused.

    Raises:
        Error: if either is quietly resolved by picking a winner.

    This is the group that matters. A parser that accepts a contradiction
    and chooses for the caller produces a plausible answer to a question
    nobody asked.
    """
    assert_true(
        parse_arguments(words("count", "one", "two")).error != "",
        String("two positional inputs were accepted"),
    )
    assert_true(
        parse_arguments(words("count", "text", "-f", "file.txt")).error != "",
        String("text and a file together were accepted"),
    )
    assert_true(
        parse_arguments(
            words("count", "--strict-special", "--allowed-special", "x", "y")
        ).error
        != "",
        String("strict and allowed together were accepted"),
    )


def test_the_dash_means_standard_input() raises:
    """A lone dash is accepted and does not become the text.

    Raises:
        Error: if it is treated as input.
    """
    var options = parse_arguments(words("count", "-"))
    assert_equal(options.error, String(""))
    assert_true(not options.has_text, String("the dash became the text"))
    assert_true(
        options.reads_standard_input(),
        String("standard input was not selected"),
    )


def test_empty_text_is_not_standard_input() raises:
    """Encoding the empty string is a real request, not a missing one.

    Raises:
        Error: if an empty argument falls through to standard input.

    The distinction is why Options carries has_text separately from text
    being empty. Without it, `knap count ""` would block on a pipe that
    nobody is writing to.
    """
    var options = parse_arguments(words("count", ""))
    assert_true(options.has_text, String("the empty argument was dropped"))
    assert_true(
        not options.reads_standard_input(),
        String("the empty argument fell through to standard input"),
    )


def test_help_wins_wherever_it_appears() raises:
    """A help flag after a command still asks for help.

    Raises:
        Error: if it is treated as an unknown option.
    """
    var options = parse_arguments(words("count", "--help"))
    assert_equal(options.command, COMMAND_HELP)
    assert_equal(options.error, String(""))


def test_only_the_shipped_encodings_are_known() raises:
    """The encoding check accepts exactly two names.

    Raises:
        Error: if it accepts or rejects the wrong one.
    """
    assert_true(is_known_encoding(String("cl100k_base")), String("cl100k"))
    assert_true(is_known_encoding(String("o200k_base")), String("o200k"))
    assert_true(not is_known_encoding(String("p50k_base")), String("p50k"))
    assert_true(not is_known_encoding(String("")), String("empty"))


def test_ids_render_in_every_shape() raises:
    """Each output format produces what its name promises.

    Raises:
        Error: if any shape is wrong, including for an empty list.
    """
    var ids = List[Int]()
    ids.append(15339)
    ids.append(1917)

    assert_equal(format_ids(ids, FORMAT_SPACE), String("15339 1917"))
    assert_equal(format_ids(ids, FORMAT_LINES), String("15339\n1917"))
    assert_equal(format_ids(ids, FORMAT_JSON), String("[15339,1917]"))

    var empty = List[Int]()
    assert_equal(format_ids(empty, FORMAT_SPACE), String(""))
    assert_equal(format_ids(empty, FORMAT_JSON), String("[]"))


def test_every_output_shape_reads_back() raises:
    """Anything encode prints, decode can parse.

    Raises:
        Error: if a shape does not survive the round trip.

    This is the property that makes `knap encode | knap decode` work
    regardless of which format was chosen, and it is why the id parser
    treats every non digit as a separator rather than expecting one.
    """
    var ids = List[Int]()
    ids.append(0)
    ids.append(15339)
    ids.append(100257)

    # A list rather than a tuple. Mojo 1.0.0 tuples do not implement
    # __iter__, so a literal tuple in a for loop is a compile error.
    var shapes = List[Int]()
    shapes.append(FORMAT_SPACE)
    shapes.append(FORMAT_LINES)
    shapes.append(FORMAT_JSON)

    for shape in shapes:
        var rendered = format_ids(ids, shape)
        var parsed = parse_ids(rendered)
        assert_equal(len(parsed), len(ids))
        for index in range(len(ids)):
            assert_equal(parsed[index], ids[index])


def test_input_with_no_ids_is_refused() raises:
    """Piping the wrong thing into decode fails rather than returning empty.

    Raises:
        Error: if it is accepted.

    An empty token list decodes to an empty document, so accepting text with
    no digits in it would turn a mistake into a silent empty result.
    """
    var refused = False
    try:
        _ = parse_ids(String("this holds no numbers at all"))
    except:
        refused = True
    assert_true(refused, String("digit free input was accepted"))


def test_an_explicit_vocabulary_is_the_only_candidate() raises:
    """Naming a vocabulary stops the search.

    Raises:
        Error: if the search continues past an explicit path.
    """
    var candidates = vocabulary_candidates(
        String("cl100k_base"), String("/tmp/mine.tiktoken")
    )
    assert_equal(len(candidates), 1)
    assert_equal(candidates[0], String("/tmp/mine.tiktoken"))


def test_the_search_ends_where_it_is_documented_to() raises:
    """Without an explicit path, the last two candidates are the fallbacks.

    Raises:
        Error: if the documented search order has changed.

    Checked from the end rather than the start, because the leading entries
    depend on which environment variables happen to be set and the trailing
    ones do not.
    """
    var candidates = vocabulary_candidates(String("o200k_base"), String(""))
    assert_true(len(candidates) >= 2, String("too few candidates"))
    assert_equal(candidates[len(candidates) - 1], String("o200k_base.tiktoken"))
    assert_equal(
        candidates[len(candidates) - 2],
        String("tests/fixtures/vocabs/o200k_base.tiktoken"),
    )


def test_the_usage_text_documents_what_exists() raises:
    """Every command and option appears in the help.

    Raises:
        Error: if something is implemented and undocumented.

    A cheap test that catches the common drift: adding a flag and forgetting
    the help, which leaves a feature that only its author can find.
    """
    var text = usage()
    var expected = List[String]()
    expected.append(String("count"))
    expected.append(String("encode"))
    expected.append(String("decode"))
    expected.append(String("vocab"))
    expected.append(String("--encoding"))
    expected.append(String("--file"))
    expected.append(String("--vocab"))
    expected.append(String("--format"))
    expected.append(String("--allowed-special"))
    expected.append(String("--strict-special"))
    expected.append(String("KNAP_VOCAB_DIR"))

    for index in range(len(expected)):
        var needle = expected[index]
        assert_true(
            text.find(needle) >= 0,
            String(t"the usage text does not mention {needle}"),
        )


def main() raises:
    """Run the command line suite.

    Raises:
        Error: if any test fails, which is how a failing suite becomes a
            failing process.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_cli.mojo
# =============================================================================
