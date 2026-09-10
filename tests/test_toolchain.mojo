# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : tests/test_toolchain.mojo
# Purpose     : Toolchain smoke test. Proves the pinned compiler builds, runs,
#               and exposes the standard library facilities Knap depends on.
# Stage       : Milestone M0, scaffold. See docs/ROADMAP.md
# Depends on  : std.testing, std.sys. No Knap source, deliberately.
# Invariants  : This file must never import from src/knap. Its whole value is
#               that it fails only when the toolchain itself is broken.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Toolchain smoke test for Knap.

This file exists so that a broken environment is discovered immediately
rather than three modules into real work. It deliberately depends on nothing
in src/knap, so a failure here always means the compiler or the standard
library, never Knap itself.

It also pins the small number of standard library facts that the rest of the
project is built on, notably that the SIMD width is taken from the target
rather than hardcoded.

Run it directly, because Mojo 1.0.0 has no "mojo test" subcommand:

    mojo run tests/test_toolchain.mojo
"""

# Mojo standard library modules import under a "std." prefix. A bare
# "from sys import ..." does not resolve in Mojo 1.0.0.
from std.sys import simd_width_of
from std.testing import assert_equal, assert_true, TestSuite


# -----------------------------------------------------------------------------
# Compilation and execution
#
# The first test is deliberately trivial. Its purpose is not to check that
# addition works, it is to prove that the pinned compiler produced a binary
# that ran to completion and reported a result.
# -----------------------------------------------------------------------------


def test_compiler_builds_and_runs() raises:
    """Prove the toolchain compiles and executes a function.

    Every Mojo function is declared with "def"; the "fn" keyword was removed
    and is now a hard parse error. A function that can raise must say so with
    "raises" before the return arrow, and the assertion helpers below can
    raise, so this test is marked accordingly.

    Raises:
        Error: if the compiled binary does not compute the expected value.
    """
    assert_equal(2 + 2, 4)


def test_string_byte_length() raises:
    """Check byte oriented string access, which Knap relies on throughout.

    Knap is a byte level tokenizer, so it measures strings in bytes and never
    in codepoints. Mojo agrees: byte_length is the byte count, and indexing
    is spelled with a "byte" keyword argument rather than a bare subscript.
    The non-ASCII case is the one that matters, since a codepoint count would
    give a different and wrong answer here.

    Raises:
        Error: if a byte length or codepoint count differs from the
            expected value.
    """
    var ascii_text = String("hello")
    assert_equal(ascii_text.byte_length(), 5)

    # Three ASCII bytes followed by one two-byte UTF-8 sequence. The
    # codepoint is written as an escape because Knap source is ASCII only;
    # the escape produces exactly the same bytes as the literal character.
    var mixed_text = String("abc\u00e9")
    assert_equal(mixed_text.byte_length(), 5)
    assert_equal(mixed_text.count_codepoints(), 4)


def test_simd_width_comes_from_the_target() raises:
    """Check that the SIMD width is a property of the target, not a constant.

    Square brackets carry compile time parameters in Mojo, while parentheses
    carry runtime arguments, so simd_width_of takes its element type as a
    parameter. "comptime" introduces a compile time constant.

    Knap must never hardcode 16, 32, or 64 lanes. Reading the width here
    proves the mechanism the SIMD classifier will use in milestone M5.

    Raises:
        Error: if the target reports a width that is not a positive power
            of two.
    """
    comptime width = simd_width_of[DType.uint8]()
    assert_true(width >= 1)

    # A power of two is assumed by the tail handling in the scanner, so the
    # assumption is asserted rather than left implicit.
    assert_equal(width & (width - 1), 0)


def test_simd_elementwise_comparison_returns_a_mask() raises:
    """Pin the element-wise SIMD comparison spelling used by the classifier.

    This is the one place where Mojo 1.0.0 diverges from what most references
    describe, and getting it wrong produces code that compiles and is wrong.
    On a SIMD vector the "greater than" operator returns a single Bool for
    the whole vector, whereas the "gt" method returns one Bool per lane. The
    byte classifier needs the per lane form.

    See docs/ARCHITECTURE.md for the recorded correction.

    Raises:
        Error: if the element-wise comparison does not yield one Bool per
            lane.
    """
    var values = SIMD[DType.uint8, 4](0x41, 0x42, 0x30, 0x31)
    var threshold = SIMD[DType.uint8, 4](0x40)

    # One lane per byte: True where the byte is above 0x40.
    var mask = values.gt(threshold)
    assert_equal(mask[0], True)
    assert_equal(mask[1], True)
    assert_equal(mask[2], False)
    assert_equal(mask[3], False)

    # Casting the mask to an integer type and summing counts the set lanes,
    # which is how the scanner will turn a class mask into a boundary count.
    assert_equal(Int(mask.cast[DType.uint8]().reduce_add()), 2)


# -----------------------------------------------------------------------------
# Findings that were nearly recorded as limitations
#
# Each of the next two was written down as something Mojo 1.0.0 cannot do,
# doubted, and then checked. Both were the reader's error. They are pinned
# here so that the correction stays correct, and because a compilation of
# toolchain limits that only ever grows is one nobody can trust.
#
# See docs/TOOLCHAIN.md.
# -----------------------------------------------------------------------------


def test_a_file_handle_can_seek_and_read_a_prefix() raises:
    """Pin that seeking works, and that a prefix can be read without the rest.

    The benchmark harness was written to read a whole corpus in order to
    slice a few megabytes out of it, on the assumption that Mojo file
    handles cannot seek. They can. Correcting it took the benchmark's peak
    resident memory from 282.8 MB down to 95.6 MB.

    Raises:
        Error: if seeking to the end does not report the file size, or if a
            bounded read returns something other than the file's prefix.
    """
    var path = String("LICENSE")

    var whole_handle = open(path, "r")
    var whole = whole_handle.read_bytes()
    whole_handle.close()
    assert_true(
        len(whole) > 64, String("LICENSE is too short to test a prefix read")
    )

    var handle = open(path, "r")

    # Whence 2 is the end of the file, so this reports the size.
    var size = handle.seek(0, 2)
    assert_equal(Int(size), len(whole), String("seek to end is not the size"))

    _ = handle.seek(0)
    var prefix = handle.read_bytes(64)
    handle.close()

    assert_equal(
        len(prefix), 64, String("a bounded read returned the wrong count")
    )
    for index in range(64):
        assert_equal(
            prefix[index],
            whole[index],
            String("the prefix is not the start of the file"),
        )


def test_a_kernel_pseudo_file_can_be_read() raises:
    """Pin that the ordinary file interface reads /proc.

    A probe against /proc returned minus one and the conclusion drawn was
    that the Mojo runtime refuses kernel pseudo files. The probe was wrong.
    The distinction matters because these files report a size of zero, so an
    implementation that trusted the size would hand back nothing, and this
    test would catch that change.

    Raises:
        Error: if the file reads as empty or does not contain the field
            every process status carries.
    """
    var handle = open(String("/proc/self/status"), "r")
    var status = handle.read()
    handle.close()

    assert_true(
        status.byte_length() > 0,
        String("/proc/self/status read as empty, so the size was trusted"),
    )
    assert_true(
        String("VmHWM") in status or String("Name:") in status,
        String("/proc/self/status is missing the fields it always carries"),
    )


def test_t_strings_interpolate_into_a_string() raises:
    """Pin the interpolation spelling, which is not the Python one.

    Mojo 1.0.0 has no f-strings. The construct is a t-string, and a t-string
    is not itself a String: it has to be converted. Every message in this
    project that names a value is written this way.

    Raises:
        Error: if interpolation does not produce the expected text.
    """
    var row = 3
    var column = 11
    var message = String(t"row {row} column {column}")
    assert_equal(message, String("row 3 column 11"))


def main() raises:
    """Discover and run every test function in this module.

    Mojo 1.0.0 removed the "mojo test" subcommand, so a test file is an
    ordinary program with a main function that drives a TestSuite.

    Raises:
        Error: if any discovered test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()


# =============================================================================
# End of file: tests/test_toolchain.mojo
# =============================================================================
