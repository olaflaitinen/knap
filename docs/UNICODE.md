<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Unicode Tables

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="assets/knap_logo_transparent_white.svg">
    <img src="assets/knap_logo_transparent_black.svg"
         alt="Knap" width="240">
  </picture>
</p>

| Field | Value |
| --- | --- |
| Document | `docs/UNICODE.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-08 |
| Updated | 2026-09-08 |
| Licence | EUPL-1.2 |

---

## Contents

1. [Which properties are needed](#which-properties-are-needed)
2. [Which Unicode version](#which-unicode-version)
3. [One class per code point](#one-class-per-code-point)
4. [Generation procedure](#generation-procedure)
5. [Representation and lookup cost](#representation-and-lookup-cost)
6. [Why the tables are strings](#why-the-tables-are-strings)
7. [Verification](#verification)

---

## Which properties are needed

The two pre-tokenization patterns do not need the same properties, and the
difference is larger than it first appears.

`cl100k_base` needs Letter and Number, which is what the project plan
anticipated. `o200k_base` needs considerably more. Its first two
alternatives distinguish an uppercase-ish run from a lowercase-ish run, and
they spell those out as explicit lists of subcategories rather than using
Letter:

| Pattern element | Categories required |
| --- | --- |
| `\p{L}` | Lu, Ll, Lt, Lm, Lo |
| `\p{N}` | Nd, Nl, No |
| `[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]` | Lu, Lt, Lm, Lo, and all Mark categories |
| `[\p{Ll}\p{Lm}\p{Lo}\p{M}]` | Ll, Lm, Lo, and all Mark categories |

So eight distinct memberships are needed in total, not two. Note also that
the two `o200k_base` classes **overlap** in Lm, Lo, and M. That overlap is
what forces the scanner to backtrack in one alternative, and it is why those
two classes cannot be collapsed.

Whitespace is handled separately. The reference regex module matches exactly
25 code points for `\s` against a text pattern, and that set is enumerated in
the generator rather than derived, because a wrong whitespace set would
change four of the eight alternatives in `cl100k_base` and three of the seven
in `o200k_base`.

| | Value |
| --- | --- |
| Unicode version | 16.0.0, from the Unicode Character Database |
| Code points classified | 145440 of 1114112 |
| Runs after collapsing | 2391 |
| Whitespace code points | 25 |

## Which Unicode version

The tables are built from the Unicode Character Database 16.0.0, downloaded
from `unicode.org` and checked against a recorded digest. They are not built
from the interpreter's `unicodedata` module.

That is not a preference. It is the resolution of a bug, and the reasoning
is recorded here because the obvious choice is the wrong one.

### Three versions in one process

A differential fuzzing run diverged after 19288 inputs. Chasing it turned up
three different opinions about Unicode inside a single process:

| Component | Which Unicode it answers from |
| --- | --- |
| Python `unicodedata`, CPython 3.12 | 15.0.0 |
| The `regex` module | its own bundled tables, not 15.0.0 |
| The tables tiktoken's pre-tokenization actually matches against | 16.0.0 |

The generated tables came from `unicodedata`, so they were 15.0.0. The
reference they were being compared against was not. Roughly six hundred code
points changed general category between the two releases, and every one of
them is a potential pre-token boundary in the wrong place.

### The first fix was also wrong

Regenerating against the `regex` module's view looked obviously correct.
`regex` is what tiktoken uses to compile its pattern, so its tables are the
ones doing the matching. That change moved the divergence instead of
removing it.

The lesson worth keeping: two components agreeing that a third is wrong is
not evidence, and a fix that changes a symptom is not a fix. What was
missing was a measurement.

### How the version was actually established

Every code point whose general category differs between Unicode 15.0.0 and
16.0.0 was enumerated. Each was placed into an input shaped so that its
category alone decides where a boundary falls, the smallest such shape being

$$X \mathbin{+} \texttt{"<a"}$$

because the character after $X$ starts a new alternative only if $X$ is not
a letter. Each input was handed to tiktoken, and the boundary it chose was
compared against the boundary predicted under each candidate version.

| Prediction from | Inputs agreeing |
| --- | --- |
| Unicode 16.0.0 | 400 of 400 |
| Unicode 15.0.0 | fewer, and the disagreements were the changed code points |

That is why the tables are pinned to 16.0.0 and to a digest rather than to
whatever the interpreter happens to ship. The version a dependency reports
is a claim; the version it behaves as is a measurement, and only the second
one decides parity.

### What this costs

The digest is checked on every generation, so an upstream file that changes
under the same URL fails loudly rather than silently regenerating different
tables. When tiktoken eventually moves to a later Unicode, this document and
`scripts/ucd.py` are the two places that change, and the probe above is the
procedure for establishing which version it moved to.

## One class per code point

Rather than eight independent tables, every code point is assigned exactly
one class from a set of eight:

| Value | Class | Meaning |
| --- | --- | --- |
| 0 | OTHER | In none of the categories the patterns test |
| 1 | Lu | Uppercase letter |
| 2 | Ll | Lowercase letter |
| 3 | Lt | Titlecase letter |
| 4 | Lm | Modifier letter |
| 5 | Lo | Other letter |
| 6 | M | Mark, any of Mn, Mc, Me |
| 7 | N | Number, any of Nd, Nl, No |

Every property is then a test on that single value. Letter is the union of
classes 1 through 5, and because those are numbered contiguously, `is_letter`
is a range comparison rather than five equality tests. The two overlapping
`o200k_base` classes are set membership tests over the same value.

This works because the categories are mutually exclusive by construction:
Unicode assigns each code point exactly one general category, so a single
value loses nothing.

## Generation procedure

`scripts/gen_unicode_tables.py` produces
`src/knap/pretokenize/unicode_tables.mojo`. The procedure is deliberately
simple, because a clever generator is a place for bugs to hide.

1. Download `UnicodeData.txt` for the pinned version, verify its SHA-256
   digest, and cache it. A mismatch is a hard failure, because a file that
   changed under the same URL would otherwise regenerate different tables
   without anyone noticing.
2. Parse it, expanding the `First` and `Last` marker pairs. Large blocks
   such as the CJK ideographs and the private use areas appear as two lines
   rather than as one line per code point, and a parser that misses this
   silently loses tens of thousands of letters.
3. Collapse the result into maximal runs of constant class.
4. Discard runs of class OTHER. Unassigned and punctuation code points are
   the majority, and a search that finds no containing run can simply report
   OTHER.
5. Emit the surviving runs as three parallel hex strings, plus a direct
   128 entry table for ASCII.
6. Emit an exhaustive reference of one hex digit per code point, for the
   test to check against.

The Unicode version is recorded in the generated file's banner. A table that
does not name its version cannot be distinguished from one built against a
different version, which is how a silent behaviour change slips in during an
upgrade.

`scripts/check_generated.py` re-runs the generator in check mode and fails
the build if the committed file has drifted.

## Representation and lookup cost

Two representations were built and measured before one was chosen.

Let $R$ be the number of sorted runs and $N$ the number of code points.

A **sorted range array** with binary search costs

$$T_{\text{search}} = O(\log R)$$

comparisons per lookup, and stores two bounds and a class per run.

A **two stage table** costs

$$T_{\text{table}} = O(1)$$

with one index into a block table and one index inside the block, and stores
a stage one entry per block plus the deduplicated blocks themselves.

Measured on Unicode 16.0.0. Two sizes are given because they are not the
same question: the data column is how many bytes the structure holds, and
the source column is how many characters that becomes in the generated file,
which is what the compiler has to chew through. Everything here is emitted
as hex text for the reason in the next section, so source is twice data.

| Representation | Data | Source | Lookup | Detail |
| --- | --- | --- | --- | --- |
| Sorted runs, binary search | 2391 runs, 15542 bytes | 31083 characters | $O(\log 2391)$, at most 12 comparisons | Chosen |
| Two stage, 128 code point blocks | 231 blocks, 38272 bytes | 76544 characters | $O(1)$ | Measured, not chosen |
| Two stage, 256 code point blocks | 141 blocks, 40448 bytes | 80896 characters | $O(1)$ | Worse on size |
| Two stage, 512 code point blocks | 95 blocks, 50816 bytes | 101632 characters | $O(1)$ | Worse still |

The two stage table wins on asymptotic lookup cost and loses on size by a
factor of about two and a half. What settles the choice is a third fact that neither
column shows: **the scanner reaches these tables only on non-ASCII input.**
ASCII resolves through a direct 128 entry table, and real text is dominated
by ASCII. Paying double the memory to speed up the documented slow path is
the wrong trade.

That reasoning is recorded rather than assumed, and it is falsifiable. If a
profile at milestone M5 shows non-ASCII classification consuming meaningful
time on a realistic corpus, the two stage table is already measured and ready
to swap in behind the same interface.

## Why the tables are strings

The tables are emitted as ASCII hex string literals rather than as list
literals. This is a compiler constraint, measured rather than assumed:

| Form | Elements | Compile time |
| --- | --- | --- |
| `List[UInt8]` literal | 34560 | Did not finish within 600 seconds |
| `StaticString` literal | 34560 characters | 5.7 seconds |

A list literal of the size these tables require does not compile in any
tolerable time under Mojo 1.0.0. The string form compiles in seconds, and a
file importing the finished tables builds in under five.

The cost is that the data is decoded at lookup time instead of being a direct
array index. That decoding is four hex digits of arithmetic per comparison,
which is cheap next to the binary search around it, and it is on the non-ASCII
path in any case.

## Verification

The tables are checked exhaustively, not sampled.

`tests/test_unicode_tables.mojo` reads a reference holding one hex digit per
code point and compares **every one of the 1114112 code points** against
`class_of_code_point`. It also verifies the whitespace predicate over the
whole space, in both directions: every code point in the reference set must
be whitespace, and no code point outside it may be.

Exhaustive rather than sampled because the risky step is collapsing per code
point classes into runs. An off by one at a run boundary misclassifies
exactly one code point, which misclassifies exactly one character of input,
which produces a divergence on text nobody thought to test. A sample would
pass with that bug present.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/ARCHITECTURE.md](ARCHITECTURE.md) |
| Next | [docs/CORRECTNESS.md](CORRECTNESS.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-08 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/UNICODE.md -->
