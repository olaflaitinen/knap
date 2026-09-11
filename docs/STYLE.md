<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Style Standard

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
| Document | `docs/STYLE.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Stable |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-07 |
| Updated | 2026-09-11 |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |

---

## Contents

1. [Purpose and precedence](#purpose-and-precedence)
2. [Character and prose rules](#character-and-prose-rules)
3. [Licensing](#licensing)
4. [Source file standard](#source-file-standard)
5. [Markdown document standard](#markdown-document-standard)
6. [Diagrams and mathematical notation](#diagrams-and-mathematical-notation)
7. [Enforcement scripts](#enforcement-scripts)
8. [When a rule and its script disagree](#when-a-rule-and-its-script-disagree)

---

## Purpose and precedence

This document is the project's own standard, written for a contributor who has
never seen the brief that produced it. Everything here is mechanically
checkable, and every rule names the script that checks it.

The rules exist for one reason. Mojo is a new language and most readers of
this repository will not know it. A generous comment budget and a rigid file
shape are cheaper than the alternative, which is a reader who cannot tell
whether an unfamiliar construct is a language feature or a project invention.

## Character and prose rules

These apply to every tracked file, with exactly four exemptions.

| Rule | Detail |
| --- | --- |
| No em-dash | Not in code, comments, documentation, commit messages, test names, or error strings. Use a comma, a colon, parentheses, or split into two sentences. |
| No emoji | Not in README, commit messages, CLI output, badges, or section headers. |
| ASCII only | Every file is ASCII, subject to the four exemptions below. |
| No exclamation marks | In documentation prose. Code and inline code spans are unaffected. |

The four exemptions, and only these four:

1. `LICENSE`, which holds the official EUPL 1.2 English text. It is a legal
   instrument and it legitimately contains typographic characters. It must
   never be repaired to satisfy an ASCII rule.
2. Test fixture data under `tests/fixtures/`. A byte level BPE tokenizer must
   handle arbitrary bytes, so fixtures deliberately contain multilingual text,
   emoji, and invalid UTF-8. Constraining them would defeat their purpose.
3. LaTeX source inside math spans, for the rare command that requires a
   non-ASCII character. This exemption is applied per span, not per file.
4. Raster artwork under `docs/assets/`. A PNG is not text, so asking whether
   it is valid UTF-8 is a category error rather than a standard. The
   exemption is by file type inside that one directory rather than by
   directory, so the vector artwork beside it is still checked like any other
   text file and a stray non-ASCII SVG would still be caught.

The fourth exemption was added when the project gained a wordmark. It is
recorded as an addition rather than folded in silently, because the previous
three were described as the only three and somebody comparing an old copy of
this document with a new one deserves to see that the count changed and why.

Enforced by `scripts/lint_style.py`.

Writing a banned character in source that must detect it is a real hazard. Use
a code point escape rather than the character itself, for example
`chr(0x2014)` in Python. The gate is not clever enough to know the difference,
and it is right not to be.

## Licensing

Knap is licensed under the European Union Public Licence 1.2. The SPDX
identifier is `EUPL-1.2`.

| Rule | Detail |
| --- | --- |
| `LICENSE` content | Official EUPL 1.2 English text, verbatim. Do not retype, paraphrase, reformat, or correct its punctuation. |
| Source files | Every `.mojo`, `.py`, and `.md` file carries `SPDX-License-Identifier: EUPL-1.2` in its header. |
| `CITATION.cff` | Uses `license: EUPL-1.2`. |
| Third party works | Every external work is recorded in `THIRD_PARTY_NOTICES.md`. |

The licence text in this repository was obtained from the European
Commission's Joinup portal. Two encoding level changes were made and no
others: the UTF-8 byte order mark was removed, and CRLF line endings were
normalised to LF to match the repository wide policy in `.gitattributes`. Not
one character of the legal text was altered. `THIRD_PARTY_NOTICES.md` records
the upstream URL and the checksum of the file as downloaded, so the
normalisation can be verified rather than trusted.

Do not copy source code from `tiktoken`, `rs-bpe`, or Hugging Face
`tokenizers` into this repository. Reimplement from the specification and from
observed behaviour. The regex pattern is extracted programmatically as a
functional specification, and the generated file records its provenance and
the upstream licence.

The EUPL is a reciprocal licence, which has consequences for downstream users.
State that plainly rather than leaving people to discover it. Nothing in this
repository is legal advice.

Enforced by `scripts/check_spdx.py`, which exempts `LICENSE` itself because a
licence does not carry a pointer to itself.

## Source file standard

Every `.mojo` and `.py` file opens with this banner. Both languages use `#`
for comments, so one form serves both. The rules are 79 characters wide so the
banner matches the 80 column default of `mojo format`.

```text
# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : src/knap/pretokenize/scanner.mojo
# Purpose     : State machine over byte classes, emits pre-token boundaries.
# Stage       : Pipeline stage 2 of 4, see docs/ARCHITECTURE.md
# Depends on  : classifier.mojo, unicode_tables.mojo, pattern.mojo
# Invariants  : Boundaries are byte offsets, always on a UTF-8 lead byte or EOF.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
```

The `File` field must equal the file's own repository relative path. That one
check is what stops a banner copied from a neighbouring module from silently
claiming to be that other module.

Generated files add three fields, `Generator`, `Upstream`, and `Generated`,
and must state that manual edits will be overwritten.

Every file ends with a closing marker, so that truncation by a failed write or
a bad merge is visible rather than plausible:

```text
# =============================================================================
# End of file: src/knap/pretokenize/scanner.mojo
# =============================================================================
```

Comment density rules, in priority order:

1. Every function gets a block comment above it, in addition to its docstring,
   covering what it does, why it exists in this form, its invariants, and its
   failure modes. The docstring serves `mojo doc` consumers, the block comment
   serves the next person reading the source.
2. Every Mojo specific construct is explained the first time it appears in a
   file. One short line each. A reader arriving from Python or Rust should not
   have to leave the file.
3. Every SIMD, pointer arithmetic, bit manipulation, and unsafe line gets an
   inline comment. State what is in each lane, what the mask means, what the
   offset is relative to, and why the bound is safe. These are the lines that
   produce silent corruption, so this is where line by line commenting earns
   its cost.
4. Every non-obvious constant is explained where it is defined, including
   where the number came from.
5. Do not comment self-evident lines. A comment that restates the code is
   worse than no comment, and the absence of one is itself information.

No placeholders. No `pass` with a TODO, no not-implemented exception, no stub
that compiles but does nothing, no lorem ipsum. Every file in the tree is
either complete and working or does not exist yet. Something that cannot be
finished is an explicit entry in `docs/ROADMAP.md`, not a silent hole.

Enforced by `scripts/check_file_banners.py` and, for docstrings,
`mojo doc --Werror --diagnose-missing-doc-strings`. Note that Mojo requires a
`Raises:` section in the docstring of any function declared `raises`.

## Markdown document standard

Every `.md` file except `README.md` carries the metadata table and the
document control footer. `README.md` is the single exception, because a
metadata block above the title reads as clutter to a first time visitor.

`.github/PULL_REQUEST_TEMPLATE.md` is exempt on the same terms, for a
different reason: its body is copied verbatim into every pull request
description, so a metadata table would be reproduced in each one. It is a form
rather than a document.

Both exemptions are from the table and the footer only. Both still carry the
licence header, as an HTML comment that is invisible when rendered, and both
remain subject to every heading and link rule.

The table has twelve fields and the order is checked as well as the presence,
because a table read out of order is harder to scan across documents. The
`Website` row was added late, once nine documents carried it and sixteen did
not, and it is enforced rather than encouraged for the reason every rule here
is enforced: a field most documents have and some do not is worse than one
nobody has, since a reader cannot tell an absence from an oversight.

### The wordmark

Every document listed in `scripts/check_md_headers.py` carries the wordmark
immediately beneath its first level heading, and nothing else may come
between the two. `README.md` renders it at 420 pixels; every other document
at 240.

It is placed as a `<picture>` element with two sources rather than as a plain
image, because the mark is a single colour wordmark on a transparent
background: the ink version disappears on a dark page and the white version
disappears on a light one. The reader's colour scheme chooses.

```text
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="assets/knap_logo_transparent_white.svg">
    <img src="assets/knap_logo_transparent_black.svg"
         alt="Knap" width="240">
  </picture>
</p>
```

The path is relative to the document. The vector files are used rather than
the raster ones wherever a renderer supports them, which on a forge is
everywhere.

`.github/PULL_REQUEST_TEMPLATE.md` does not carry it. Its body is copied into
the description of every pull request, and a mark reproduced there would
appear hundreds of times in places nobody chose to put it.

Never resize the mark below 160 pixels of wordmark width. The typeface is
hairline weight and the strokes break up below that. The full brand
specification, including clear space and the colour values, is in
[BRAND.md](BRAND.md).

The header, in this order:

```text
<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Document Title

| Field | Value |
| --- | --- |
| Document | `docs/ARCHITECTURE.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft, Review, or Stable |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | 0009-0006-5184-0810 |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | YYYY-MM-DD |
| Updated | YYYY-MM-DD |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |
```

The footer, in this order, at the end of every non-README document:

```text
## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/UNICODE.md](UNICODE.md) |
| Next | [docs/BENCHMARKS.md](BENCHMARKS.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | YYYY-MM-DD |
```

followed by the licence paragraph and the end of document marker. No content
may follow that marker.

Additional rules:

| Rule | Detail |
| --- | --- |
| One `#` heading | At the top. Everything below is `##` or deeper. Never skip a level. |
| Contents list | Required at three or more body sections, omitted below that. Anchors must resolve, not be guessed. |
| Relative links | For in-repo targets, so the docs work in a clone as well as on the forge. |
| Language tags | Every fenced code block carries one: `mojo`, `python`, `bash`, `toml`, `json`, `text`. |
| Tables for facts | Prose for reasoning, tables for anything with more than two parallel attributes. |

Enforced by `scripts/check_md_headers.py`, which validates presence, field
completeness, ordering, the README exemption, heading levels, fence language
tags, and link and anchor resolution.

## Diagrams and mathematical notation

Documentation must render, not describe. A reader should never meet a formula
written as prose or a diagram written as an indented list.

Diagrams use Mermaid fenced blocks, which render on the forge. Mathematics
uses LaTeX in Markdown math blocks, single dollars inline and double dollars
displayed. Never a code fence, never an image, and never ASCII art for an
equation. Define every symbol in the surrounding prose.

## Enforcement scripts

Nine scripts refuse something. The first five are the prose and structure
gates this document is about; the other four are listed because a reader
asking what can refuse a commit should find the whole answer in one place.

| Script | Enforces |
| --- | --- |
| `scripts/lint_style.py` | Em-dash, emoji, ASCII, exclamation marks, with the four exemptions. |
| `scripts/check_file_banners.py` | Source banner fields, field order, path match, and closing marker. |
| `scripts/check_md_headers.py` | Markdown header, metadata table, headings, fences, links, footer. |
| `scripts/check_spdx.py` | SPDX identifier in every tracked source, script, and document. |
| `scripts/check_toolchain_doc.py` | Every file `docs/TOOLCHAIN.md` cites exists, and the compiler version it was verified against is the one still pinned. |
| `scripts/check_generated.py` | The four committed generated files match what their generators produce now. |
| `scripts/check_fuzz_claims.py` | Every fuzzing figure quoted in prose appears in a committed run report. |
| `scripts/check_reference.py` | Each fetched vocabulary matches the digest recorded when it was fetched, and the reference version matches what the documents quote. |
| `scripts/check_recipe.py` | The conda recipe agrees with `CITATION.cff`, `pixi.toml` and `pyproject.toml`, and its source revision is a commit this repository has. |

All nine run in CI on every push, and the first four were wired in from the
first commit. Standards that arrive after the code never get applied
retroactively.

The first five accept explicit paths for a fast local check of one file, and
default to every file git considers in scope. That set is deliberately
`--cached --others --exclude-standard`, so a file that is written but not yet
added is checked, while build outputs and fetched vocabularies never are.

**A gate that has never been observed failing is not known to work.**
`scripts/selftest_gates.py` plants one specific violation per gate, asserts
it is rejected, then feeds the same gate a clean control and asserts that is
accepted. Both halves are needed, because a gate that rejects everything is
exactly as useless as one that rejects nothing and only the second half
catches it. It currently runs seven planted violations across those five
gates, and `scripts/check_recipe.py --selftest` plants seven more for the
recipe gate. Adding a gate without adding its planted violation is how a
gate quietly stops working.

## When a rule and its script disagree

This document is authoritative and the script has the bug.

That direction is chosen deliberately. A script is easier to change than a
standard, so if the script were authoritative the standard would drift
silently toward whatever the script happened to implement. Fix the script,
and add the case that was mishandled to whatever tests the script has.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/CORRECTNESS.md](CORRECTNESS.md) |
| Next | [docs/ROADMAP.md](ROADMAP.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-11 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/STYLE.md -->
