<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Changelog

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="docs/assets/knap_logo_transparent_white.svg">
    <img src="docs/assets/knap_logo_transparent_black.svg"
         alt="Knap" width="240">
  </picture>
</p>

| Field | Value |
| --- | --- |
| Document | `CHANGELOG.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Stable |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-07 |
| Updated | 2026-09-10 |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |

---

## Contents

1. [Format](#format)
2. [1.0.0, not yet released](#100-not-yet-released)
3. [0.1.0, 2026-09-07](#010-2026-09-07)

---

## Format

This file follows the Keep a Changelog convention, newest first, with
`Added`, `Changed`, `Fixed`, and `Removed` sections.

One rule is specific to this project and overrides the usual reading of
semantic versioning. **Any change to tokenizer output is a breaking change,
even when the public API is untouched.** Consumers pin token ids into caches,
datasets, and evaluation results, so an output change breaks them as
thoroughly as a changed signature would. Entries that change output are marked
`OUTPUT CHANGE` in bold, however small the change.

No entry in this file changes tokenizer output yet, because Knap does not
produce output yet.

## 1.0.0, not yet released

Milestones M1 through M9. The version number is declared, the tag and the
GitHub release are not, and the heading says so rather than implying
otherwise. It becomes a dated release heading on the day the tag is created.

Why 1.0.0 rather than another 0.x. The public interface is settled, every
milestone gate has been run and observed, and the parity claim rests on 110
MB of corpus and twenty million fuzzed inputs rather than on intention. Under
the rule in [Format](#format) that makes any output change breaking, calling
this 0.x would understate what a consumer can rely on.

What it does not promise: the Mojo ABI is not stable and the compiler is
pinned exactly, so a Knap 1.0.0 built against one toolchain is not
interchangeable with one built against another. That constraint belongs to
the language rather than to this library, and it is why no wheel is
published.

One entry below changes tokenizer output, and it is the Unicode version fix
under Fixed. Everything else either adds a capability or leaves behaviour
untouched.

### Fixed, a documentation audit that found stale figures in eight documents

Every Markdown file in the repository was read against the code it describes.
What follows is what disagreed, because a list of corrections is more useful
than a claim that everything is current.

- **The unstable API inventory was three milestones out of date.**
  `docs/ARCHITECTURE.md` reported M6: 14 targets, 17220 uses, 78 distinct
  APIs. It now reports M9: 19 targets, 35957 uses, 86 APIs, with the top of
  the per API table regenerated and the closing analysis rewritten around the
  real numbers. The reading has not changed and is worth repeating: the rise
  measures how much code was written, not how much risk was added, since the
  newcomers since M6 are `UInt64` for the packed hash slots and the assertion
  helpers of three new test files.
- **`docs/ARCHITECTURE.md` said two files are generated and committed.**
  There are four. The table and the diagram now name all four with their
  generators, and the section states why each must be deterministic and why
  the drift check runs before the generators rather than after.
- **`docs/CORRECTNESS.md` said Knap is at M8.** It is at M9, and the status
  table was missing counting, windowing, padding and the size of the test
  suite. All four are now rows, and padding has a section explaining why the
  mask is where correctness lives.
- **`docs/ROADMAP.md` said the suite is 26 tests.** It is 138 across 19
  files, 131 of them on every push. The M0 record keeps its original figures,
  which is the point of a record, but each row that has since moved now says
  what it moved to.
- **`docs/STYLE.md` listed four enforcement scripts.** There are nine. All
  nine are now in the table with what each refuses, and the exemption count
  in one row said three where the document itself says four.
- **`CONTRIBUTING.md` said the differential fuzzer is not yet present.** It
  has been present since M4. That section now says how to run it, what the
  nightly job does, and why widening a fuzzing claim means committing the run
  rather than editing the sentence. The test section had also acquired a
  thread sanitizer instruction for a parallel path that does not exist,
  because Mojo 1.0.0 has no working task parallelism.
- **`tests/fixtures/corpus/README.md` called six committed fixtures
  planned.** They arrived at M2.
- **`tests/fixtures/hf/README.md` described a loader as experimental in
  Knap.** No such loader exists, and not writing one is a decision rather
  than a delay. That file now says so first and explains why the directory is
  kept anyway.
- **The `Website` row was in nine documents and missing from sixteen.** It is
  now in all twenty-three that carry a metadata table, and
  `scripts/check_md_headers.py` requires it, because a field most documents
  have and some do not is worse than one nobody has.
- **Every document was redated.** `Updated` and `Last reviewed` now say
  2026-09-10 in each one, which is when each was actually read.

### Added, two gates for the two ways a document rots quietly

- **`scripts/check_md_headers.py` now checks that a Contents list matches the
  document.** Every top level section must be listed, and every entry must
  name a real heading. This is the failure that cannot be seen by reading the
  document, because a reader trusts the list and stops scrolling. Three
  documents were wrong and are fixed, and `docs/API.md` now nests its module
  index under the two sections it had been omitting.
- **`scripts/check_toolchain_doc.py` accepts an explicit path**, which is
  what lets `scripts/selftest_gates.py` plant a violation and watch the gate
  reject it. The self test now runs seven planted violations across five
  gates rather than five across four, and both new cases are for gates added
  this week.

### Added, milestone M9, counting and memory

- **A counting entry point that never builds the list of ids.**
  `count_ordinary`, `count_ordinary_bytes`, `count`, `count_bytes` and their
  cached forms, on the tokenizer, and `knap count` now uses them. One
  implementation serves counting and encoding, through a compile time
  parameter on the merge loop and the segment encoder: two merge loops that
  had to agree would be a correctness hazard rather than an optimisation.
- `tests/test_count.mojo`, six tests. Every one compares a count against the
  length of the encode of the same input rather than against a number
  written by hand, because a hand written count would still pass if both
  paths were wrong in the same way. The 110 MB corpus gate now asserts it
  too, for each of the four distinct encode behaviours.
- **`bench/memory.py` and `bench/mem_probe.mojo`**, a peak resident memory
  measurement with one child process per stage and the empty runtime
  reported as a control every time.

### Added, milestone M9, memory measured across every encoding

- `bench/memory.py` now surveys all seven encodings on both sides in one
  run, each in its own child process with its own language's empty runtime
  as the control. **Knap holds every encoding in between 4.4 and 11.7 times
  less memory than the reference implementation**, from 3.1 MB against
  36.4 MB for `gpt2` to 18.4 MB against 82.5 MB for `o200k_harmony`.
- One row in that table is not ours and is reported rather than explained.
  The reference's `gpt2` costs 9 MB more than its `r50k_base` although the
  two merge tables are identical, which `scripts/diff_vocabs.py` confirms
  token for token and rank for rank.

### Changed, milestone M9, two things the memory measurement found

- **The output list was grown into rather than sized.** A list that doubles
  holds both buffers while it copies, so its peak is about half again its
  final size, and encoding 80 MB peaked at 13.2 bytes per token when a
  token id is eight. Sizing it once from the input length removed 137.7 MB
  of peak and brought the arithmetic back to 7.99 bytes per token. The
  110 MB parity gate passed unchanged, because a capacity hint cannot
  change an answer.
- **The benchmark harness read 115 MB to hand back four.** It read the
  whole corpus and indexed into it. It now seeks and reads the slice plus a
  bound on how far the first line boundary can be. The encode benchmark's
  peak fell from 282.8 MB to 95.6 MB, which matters on a machine where the
  thing being measured was competing with the measurement for page cache.
  The Mojo and Python sides changed together and produce byte identical
  slices at 1, 4 and 16 MB.

### Added, milestone M9, the helpers a caller would otherwise write

Each of these is something people write against a tokenizer, and write
slightly wrong.

- **`windows_ordinary`**, which splits a document into windows of at most N
  tokens with an optional overlap. The obvious implementation encodes the
  document, cuts the id list every N ids, and decodes each piece back to
  text; its windows begin and end inside tokens, so they decode to mangled
  text and re-encode to different ids, and nothing notices. These cut on
  pre-token boundaries, which is the coarsest boundary the merge loop cannot
  cross, so a window's encoding is exactly the slice of the whole document's
  encoding that covers it. `tests/test_windows.mojo` asserts that at six
  window sizes rather than arguing for it.
- **`truncate_ordinary`** and **`fits_ordinary`**, for a token budget.
  `fits_ordinary` stops as soon as the budget is exceeded, which is the
  difference between checking a hundred megabyte document against a context
  window and tokenizing it.
- **`encode_ordinary_batch`** and **`encode_ordinary_batch_into`**. The
  second writes every document into one buffer and records where each one
  ends, so a batch of ten thousand short documents pays for one growth
  sequence rather than ten thousand allocations.
- **`token_id_of`** and **`token_bytes`** on the tokenizer, and
  `piece_token_counts`, the primitive the windowing is built on, exposed
  because a caller doing something this library did not anticipate should
  not have to reimplement it.
- **`TokenWindow`**, a byte range and a token count, `Writable` so that it
  prints.

- **`scripts/diff_vocabs.py`**, which compares two encodings and
  characterises the difference from the tokens rather than from an
  expectation. This repository claims that `gpt2` and `r50k_base` share a
  table byte for byte and that `p50k_base` adds exactly twenty four tokens,
  all runs of two to twenty five spaces. Both were observations. They are
  now repeatable, and running the tool reproduces them exactly.
- **`scripts/check_reference.py`**, which gates on the thing every number
  here is measured against: each fetched vocabulary against the digest
  recorded when it was fetched, the token counts alongside it, and the
  reference version against what the documents quote. A vocabulary that
  changed under the fixtures would not fail a test, because the fixtures
  would be regenerated from it and agree with themselves.

### Added, milestone M9, padding and attention masks

- **`pad_ordinary_batch`** and **`PaddedBatch`**: one row per document,
  padded to the longest row, row major so that the next thing that happens
  to it is a copy into a tensor rather than a flattening. It carries the
  ids, a mask, and each row's real length, with `id_at` and `mask_at` that
  raise on an index outside the rectangle rather than clamping, because a
  clamped read returns a real looking id from the wrong place.
- **The padding id is required and there is no default.** Not one of the
  seven encodings defines a padding token, so any value is the caller's
  decision about their own model, and choosing one silently would put an id
  into a tensor that the model was never trained to see in that position.
- **Truncation here is by token, not by pre-token**, which is the opposite
  of what `windows_ordinary` does and is deliberate. A window has to
  re-encode to itself; a fixed width model input needs exactly that many
  columns and will cut inside a word.
- `tests/test_padding.mojo`, six tests, each comparing every position in the
  batch against the encoder. One of them pads with the id of a real token so
  that the ids alone cannot separate content from padding, which is the case
  the mask exists for and the only one that distinguishes a working mask
  from a decorative one.

### Added, examples that are executed rather than illustrated

- **`examples/budget.mojo`**, which answers the question every tokenizer
  gets asked first and shows why the obvious answer is wasteful twice over:
  it allocates a list of ids to read one number off it, and it counts all of
  a document that the first tenth has already overflowed.
- **`examples/chunker.mojo`**, which windows a document and pads the result,
  so that the two truncation rules sit next to each other and the difference
  is visible.
- **`examples/README.md`**, which states what each one is for. Every figure
  quoted in it is output that was observed on this repository.
- Both run in CI against real repository files, and both are built under
  `--Werror`. Nothing else in the repository executes an example, so without
  that step they rot at the first signature change and the first person to
  find out is a reader following the README.

### Added, two documents that are useful without Knap

- **`docs/TOOLCHAIN.md`**, the compilation of everything about Mojo 1.0.0
  that is not what a careful reader would assume. Thirty-five findings, each
  verified by compiling, each naming what pins the correct spelling in this
  repository. It includes a section for the four assumptions that turned out
  to be the reader's error rather than the compiler's, because a list of
  limitations that only ever grows is one nobody can trust. Moved out of
  `docs/ARCHITECTURE.md`, which now points at it rather than carrying it.
- **`docs/METHODOLOGY.md`**, how the numbers in this repository were
  measured and how the correctness claims were established, written so that
  it can be applied to a project that is not this one. Paired benchmarking
  and why anything under ten percent needs it, one process per stage for
  memory with a control reported every time, and the practice of writing a
  prediction down before testing it.
- **`scripts/check_toolchain_doc.py`**, which resolves every file the
  toolchain document cites and checks the compiler version it was verified
  against is the one still pinned. A document that is mostly citations rots
  at the first rename, silently. Observed rejecting both a planted bad
  citation and a planted version disagreement.
- `tests/test_toolchain.mojo` gained three pins: that a file handle can seek
  and read a prefix, that the ordinary file interface reads `/proc`, and the
  t-string interpolation spelling. The first two were each written down as
  toolchain limitations before being checked, and neither was one.

### Added, a bill of materials

- **`sbom.cdx.json`**, CycloneDX 1.6, generated from `uv.lock` and
  `pyproject.toml` by `scripts/gen_sbom.py` and gated for drift by
  `scripts/check_generated.py` alongside the other generated files.
- It answers one question: when the next advisory lands, does it reach a
  consumer through Knap. Ten components are required to build, twenty-three
  are development only and marked with CycloneDX scope `excluded`, and the
  distributed artefact's runtime dependency set is empty. That last fact is
  recorded as a property on the root component rather than left to be
  inferred from an absence, because a bill of materials that lists a
  compiler as though the compiled output still depended on it is the most
  common way these documents mislead.
- The document carries no timestamp and its serial number is derived from
  the project name and version, so regenerating an unchanged tree reproduces
  it byte for byte and the drift check means something.

### Fixed, milestone M9, a silently ignored argument

- `knap vocab " the"` took the argument and printed the summary, which is
  the worst of both: the caller believes a question was answered. It now
  answers it, saying whether the text is a single token and what it becomes
  if it is not.

### Changed, milestone M9, what the measurements said

- **Counting is not faster than encoding.** It was written expecting to be,
  and over 4 MB of prose the two are indistinguishable in throughput: the
  appends are cheap against a merge loop doing hash lookups. The prediction
  is recorded as refuted rather than removed.
- **Counting uses less than half the memory on a large input.** 270 MB
  against 584 MB above the control for 80 MB of text, because at that size
  the list of ids is the largest thing in the process. At 4 MB the two are
  identical. The entry point is documented as a memory entry point rather
  than a fast path.
- **Knap holds `cl100k_base` in 7.9 MB where the reference implementation
  needs 44.7 MB**, both measured above their own empty runtime in the same
  run. That is 5.7 times less and it had never been measured.

### Fixed, milestone M9

- The first version of the memory measurement reported 290 MB for a loaded
  tokenizer and would have been published as Knap using six times the memory
  the reference does. The 290 MB was the benchmark harness reading the whole
  115 MB corpus to take a 4 MB slice. A control and a per stage split caught
  it before it went anywhere.

### Changed, how this library describes itself

- The one line description, the citation abstract, and the opening of the
  README, the architecture document and the correctness document all led
  with parity against `tiktoken`, which reads as though the library were an
  appendix to it. It is not. Knap is an independent implementation: the
  pre-tokenizer is a hand written scanner, the Unicode tables are generated
  from the Character Database, and the merge loop, the rank table and the
  memory layout are its own. `tiktoken` is the reference implementation it
  is differentially tested against, which is a measuring instrument. That
  distinction is now made in each of those places.

### Added, packaging preparation

Everything up to publishing, and nothing beyond it. No tag, no release, and
no pull request to the modular-community repository: those are one decision
and it is the author's to take. See [docs/PACKAGING.md](docs/PACKAGING.md).

- The recipe moved from `recipe/recipe.yaml` to `conda.recipe/recipe.yaml`,
  which is where rattler-build looks by default and where
  `rattler-build-action` expects it.
- The recipe builds from a git URL and a full commit SHA rather than a local
  path. A path source cannot be built by anyone but the author, and the
  modular-community repository holds only the recipe, so it could not have
  built the package at all.
- `conda.recipe/smoke.mojo`, the package acceptance test, is a real file
  named by the recipe's test section rather than a heredoc inside it. The
  CI job that imports the precompiled package now runs the same file, so
  the two cannot drift.
- `scripts/check_recipe.py` gates the recipe on every push: the version
  against `CITATION.cff`, the compiler pin against `pixi.toml` and
  `pyproject.toml`, the source revision against the commits in this
  repository, the named test files against the recipe directory, and the
  licence file against the tree. It reads the YAML subset the recipe uses
  and refuses anything else, because a parser that skipped what it did not
  understand would report a clean result for a recipe it never read.
- `python scripts/check_recipe.py --selftest` plants seven violations
  against the real recipe and confirms each is rejected. That is the
  standard every other gate here is held to, and it runs in CI.
- `.github/workflows/codeql.yml`. The modular-community channel requires
  CodeQL scanning of any package containing a language other than Mojo, and
  a badge in the README. Knap contains a good deal of Python. CodeQL has no
  Mojo analysis, so what it covers is stated rather than implied.
- A CI job that builds the package with rattler-build. It is not a required
  check, because it builds the commit the recipe names rather than the
  commit under test, which makes it a rehearsal of publishing rather than a
  test of the branch.

### Fixed, packaging preparation

- The CI packaging job wrote a `.mojopkg`, an extension deprecated in Mojo
  1.0.0 that warns. It writes a `.mojoc` now, which is what the recipe
  produces.

### Changed, milestone M8, the merge path

**Encode is between 1.39 and 1.85 times faster, with byte identical
output.** That took Knap past `tiktoken` on three of the four distinct
encode behaviours and level with it on the fourth, on the published machine.
`rs-bpe` still leads on the two encodings it ships. Numbers, method and the
baselines that win are in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

The work started with a measurement rather than a guess: pre-tokenization
takes 184 ms of a 987 ms encode of four megabytes, so four fifths of the
time was in the merge path and the other fifth was not worth touching.

- **The merge loop asks whether the whole piece is already a token before it
  splits anything.** Over four megabytes of prose `cl100k_base` turns 882310
  pieces into 1223017 tokens, which is 1.39 tokens per pre-token, so most
  pieces are a single token and the loop could never have changed them.
- **The rank of each adjacent pair is kept rather than recomputed.** A merge
  changes exactly two pairs, so the hash lookups per piece fall from
  quadratic in the piece length to linear.
- **The 256 single byte tokens moved into a direct array, and the id of a
  merged part is the rank the merge already found.** One lookup per input
  byte and one per output token disappear. Measured on its own this was
  faster on three encodings and slower on one, and the machine could not
  resolve it; it is kept because it strictly removes lookups.
- **The probe table carries a tag from the key's hash.** A failing probe used
  to touch four arrays before it could reject a slot; now it usually rejects
  after one load. The hash changed at the same time from FNV-1a to a mixer
  that reads eight bytes per iteration.
- `merge_piece_into` now takes a `MergeScratch` rather than a list. The
  number of working lists is an implementation detail and it grew from one
  to three during this work, which would otherwise have been three breaking
  changes to a public signature.

### Changed, milestone M8, results that moved under it

- **The piece cache is now slower than the uncached path on `cl100k_base`:**
  5.58 MB/s against 6.15, at a 92.7 percent hit rate. A cache is a bet that
  recomputing is expensive, and the recomputation got cheap. `o200k_base`
  still gains, 7.50 against 6.06, because its table is twice the size.
- **The vectorised classifier measured clearly slower in this run**, 46
  percent on `cl100k_base`, where the previous run could not tell it apart
  from the scalar one. Two runs of the same benchmark on the same machine
  with no source change between them now disagree. Both are recorded. The
  decision does not move: it stays off by default.
- Short string latency at about ten tokens is now level with `tiktoken` at
  the median. The tail is still worse and is still unexplained, and a second
  hypothesis has now been eliminated: removing three quarters of the merge
  loop's lookups did not improve it in proportion.

### Added, milestone M7, the remaining five encodings

- `o200k_harmony`, `gpt2`, `r50k_base`, `p50k_base` and `p50k_edit`, taking
  Knap from two `tiktoken` encodings to all seven. Each is compared against
  `tiktoken` itself rather than against a sibling that resembles it.
- `scan_gpt2`, the third pre-tokenization pattern. Four of the seven
  encodings share it, and it differs from the other two in five measured
  ways: its contractions are case sensitive, its digit runs are unbounded
  and take a leading space, a word may be preceded only by a literal space,
  its punctuation runs take no trailing line breaks, and it has no
  alternative for a whitespace run that ends at a line break.
- Loaders, special token registries, and command line, Python binding and
  fuzzer support for all seven names. Four vocabulary files serve them:
  `o200k_harmony` shares `o200k_base`'s merge table, `p50k_edit` shares
  `p50k_base`'s, and `gpt2` loads from `r50k_base.tiktoken` because their
  merge ranks are byte identical, which was checked entry by entry.
- `tests/test_encode.mojo` now asserts the grouping itself: the seven names
  produce four distinct ordinary outputs, the ones that should agree do, and
  the ones that should differ are shown to differ. Finding an input that
  separates every group took measuring. `gpt2` and `p50k_base` agree on
  ordinary English; p50k adds exactly twenty four tokens to r50k's table and
  every one of them is a run of two to twenty five spaces, added so that
  Codex could tokenise indentation.
- Corpus gates over 110 MB for the four distinct encode behaviours,
  191762320 tokens in total, and for the third pattern, 28699602 piece
  boundaries. Decode is checked for all seven, 702463 ids.

### Fixed, milestone M7

- **A special token sitting on a reserved merge rank could not be decoded.**
  `p50k_base` puts its end of text marker at 50256, which is a hole in its
  merge table rather than an id above it. Every other shipped encoding
  stacks its specials above the merges, so decode tested whether an id was
  inside the merge range instead of asking whether that rank was assigned,
  found the hole, and refused. Any caller decoding a `p50k_base` document
  containing the marker would have hit it. Found by the decode gate on the
  day the encoding was added, which is the argument for adding encodings
  after the gates rather than before them.
- **The decode gate held a loose assertion that checked nothing on four of
  the seven encodings.** It required a golden fixture to contain at least
  one undecodable id. That was true of both encodings shipped when it was
  written and is false of `gpt2`, `r50k_base`, `p50k_base` and `p50k_edit`,
  whose id spaces are completely full, and of `o200k_harmony`, whose 1091
  special tokens fill every hole `o200k_base` leaves. The gate now asserts
  the exact count for each encoding, read off the reference.
- `tests/test_special.mojo` claimed that special ids sit above the merge
  ranks. True of two encodings, false of seven. The test now asserts what
  the `Vocabulary` constructor actually enforces, which is the weaker and
  correct statement that no special takes an id an assigned merge rank
  already holds.
- `tests/test_flat_vocab.mojo` claimed that empty tokens occur in real
  vocabularies. Measured across all seven: none do, and the shortest token
  is one byte in every one of them. Zero length now means a reserved id,
  which is what `p50k_base` needs.
- The README's performance section said that no benchmarks had been
  measured and its limitations said that no fuzzing had run. Both were true
  when written and had been false since M4 and M5. The headline table, the
  losing result, and the pointer to the winners are now in the README where
  a reader meets them first.

### Added, allocation control

- `Tokenizer.encode_ordinary_into` and `encode_ordinary_bytes_into`, which
  append to a buffer the caller owns instead of returning a fresh list. A
  caller encoding many documents in a loop can now hand back the same buffer
  and pay for it once. Mojo exists to give control over allocation, and a
  library offering only allocating entry points does not pass that control
  on.
- `merge_piece_into`, which takes the merge loop's scratch space from the
  caller. `merge_piece` remains for single piece callers and allocates its
  own.

### Added, the command line tool

- `cli/`, a `knap` command with `count`, `encode`, `decode` and `vocab`.
  Counting tokens is the most common thing anyone does with a tokenizer and
  it previously required a Mojo toolchain and a program. Input comes from an
  argument, a file, or standard input; exit status separates a bad command
  line from a bad input.
- `tests/test_cli.mojo`, nineteen tests over the parser. Most of them assert
  refusals, because a parser that accepts a good command line is the easy
  half and one that quietly resolves a contradiction is how somebody gets a
  token count they did not ask for.
- `cli/tests/test_end_to_end.py`, which builds the binary and checks every
  count and every id against `tiktoken`, through arguments and through
  pipes, and round trips all 256 byte values.
- The conda package now installs the binary, so the package gives a working
  command rather than a library to write a program against.

### Added, milestone M6, distribution

- `conda.recipe/recipe.yaml`, a conda recipe targeting the
  `modular-community`
  channel. The compiler is pinned exactly in both build and run
  requirements, so a consumer on a different toolchain gets a solver error
  rather than a link error deep in their build.
- `bindings/python/`, a native CPython extension built from Mojo through
  `PythonModuleBuilder`, plus a thin Python package over it. The `ctypes`
  fallback the plan allowed for was not needed and was not written.
- `bindings/python/tests/test_bindings.py`, which checks the bindings
  against `tiktoken` rather than trusting the Mojo tests. A binding can lose
  or reorder values in translation and the Mojo tests would never see it.
- CI jobs that build the conda package and import it without the source
  tree, and that build and test the Python extension.

### Added, milestone M5, vectorisation, caching and benchmarks

- `src/knap/pretokenize/classifier_simd.mojo`, a vectorised byte classifier,
  and `tests/test_classifier_parity.mojo`, which holds it to the scalar one.
  It is compiled and tested but switched off. See Changed.
- `src/knap/byte_map.mojo`, a hash map from a borrowed byte range to an
  integer, with open addressing, FNV-1a, and keys in a flat arena. Shared by
  the rank table and the piece cache, both of which ask the same question of
  a range inside a buffer they do not own.
- `src/knap/cache.mojo`, a bounded piece cache: open addressing, FNV-1a over
  the piece bytes, flat arenas, no eviction. Owned by the caller rather than
  held inside the tokenizer, so a tokenizer stays immutable and the memory
  cost is visible at the call site.
- Cached encode entry points on `Tokenizer`. The cached and uncached paths
  share one implementation selected at compile time, so neither carries a
  branch for the other and the two cannot drift apart.
- `tests/test_cache.mojo`, which holds the cached path to the same tiktoken
  reference the uncached path is held to, over every fixture, and covers the
  states a bounded structure only reaches under pressure.
- `bench/`, a benchmark suite with a harness reporting mean, sample standard
  deviation, coefficient of variation and nearest-rank percentiles, plus
  baselines for `tiktoken`, `rs-bpe` and Hugging Face `tokenizers`.
- `docs/BENCHMARKS.md`, from a real run on a described machine.
- `.github/workflows/bench.yml`, a smoke run that asserts the suite still
  runs and states plainly that its numbers are not publishable, because a
  shared runner cannot produce a comparable one.

### Added, milestone M4, differential fuzzing

- `tests/fuzz/`, a differential fuzzer running Knap and `tiktoken` in one
  process, with ten generator kinds and a driver that shards the work and
  records every seed.
- `tests/fuzz/asan_solo.mojo`, which drives Knap over the same generators
  with no interpreter in the process, so a sanitizer run needs no
  suppressions and any leak it reports has exactly one owner.
- `tests/fuzz/lsan.supp`, suppressing the reference implementation's own
  allocations by module name and nothing else, with the experiment that
  established whose they are written into the file.
- `.github/workflows/fuzz.yml`, a nightly run, and a second address
  sanitizer job in `sanitize.yml` for the solo driver.
- `scripts/ucd.py`, which downloads and digest checks the Unicode Character
  Database rather than reading the interpreter's copy.

### Added, milestone M3, BPE merge and encode

- `src/knap/ranks.mojo`, the merge rank table. It refuses a vocabulary that
  is missing any of the 256 single byte tokens, because byte level BPE starts
  from individual bytes and the omission would surface as a crash deep in the
  merge loop rather than as a loading error.
- `src/knap/bpe.mojo`, the merge loop. Each round joins the globally lowest
  ranked adjacent pair, not the leftmost, which is the distinction that
  separates a correct loop from a plausible one.
- `src/knap/tokenizer.mojo`, the public API: `encode_ordinary`, `encode` with
  an allowed special token set, and `decode`.
- `tests/test_bpe.mojo`, unit tests over a synthetic vocabulary small enough
  to work through by hand.
- `tests/test_encode.mojo` and `tests/test_encode_corpus.mojo`, the fast
  fixture parity tests and the full corpus gate.
- `tests/test_hazards.mojo`, one test per hazard in `docs/CORRECTNESS.md`,
  with every expected token measured from tiktoken rather than recalled.
- `tests/test_roundtrip.mojo`, including every one of the 256 byte values and
  deliberately malformed sequences.
- Encode references from `scripts/gen_encode_golden.py`: readable JSON Lines
  for the fixtures, and a packed varint stream for the corpus.

### Added, milestone M2, pre-tokenizer

- `scripts/extract_patterns.py`, which pulls both pre-tokenization patterns
  out of tiktoken and emits them as a generated Mojo constant. The pattern is
  never transcribed by hand: `o200k_base` is 274 characters and one wrong
  character would diverge only on rare input.
- `scripts/gen_unicode_tables.py`, emitting Unicode 15.0.0 general category
  data as 2342 sorted runs with a direct table for ASCII.
- `src/knap/pretokenize/utf8.mojo`, with a defined policy for malformed
  input: consumed one byte at a time, never rejected and never replaced.
- `src/knap/pretokenize/classifier.mojo`, the scalar classifier, which stays
  permanently as the reference the M5 SIMD classifier is tested against.
- `src/knap/pretokenize/scanner.mojo`, hand written matchers for both
  patterns, including the one alternative that genuinely backtracks.
- `scripts/fetch_corpus.py` and `scripts/gen_pretoken_golden.py`, which
  assemble a 110 MB mixed corpus and its reference boundaries.
- `scripts/check_generated.py`, failing the build when a committed generated
  file no longer matches its generator.
- `.github/workflows/corpus.yml`, running the full 110 MB gate on a schedule.
- The committed edge case fixtures under `tests/fixtures/corpus`.
- 13 further tests, including an exhaustive check of all 1114112 Unicode code
  points.

### Added, milestone M1, vocabulary and decode

- `.tiktoken` vocabulary loading, strict on every malformed shape.
- `FlatVocab`, contiguous token bytes with parallel offset and length arrays.
- Decode over the full token id space, byte exact.
- The special token registry for both encodings.
- `scripts/fetch_vocabs.py` and `scripts/gen_encode_golden.py`.

### Changed

- **The merge loop no longer allocates per pre-token**, and the output
  buffer is sized before encoding rather than grown. Measured with a paired
  comparison over twelve alternating runs: plus 5.8 percent for
  `cl100k_base` at 3.4 sigma and plus 5.4 percent for `o200k_base` at 4.5
  sigma. Small, and worth recording next to the rank table result below,
  which removed a comparable number of allocations and returned ninety
  percent. The two differ by a factor of seventeen.
- **The rank table is keyed on a borrowed byte range rather than on a
  `String`.** A `String` key owns its bytes, so every lookup allocated a copy
  of the range being asked about, and the merge loop is quadratic in the
  piece length. Encode throughput went from 1.79 to 3.44 MB/s for
  `cl100k_base` and from 1.90 to 3.21 for `o200k_base`, and the 110 MB parity
  gate from 208.5 to 105.8 seconds, with byte identical output. The merge
  loop itself is unchanged and still quadratic, deliberately.
- **`RankTable` is no longer `Copyable`.** It holds a hundred thousand keys
  and their bytes, and an accidental copy is an expensive thing to do
  silently. Making the compiler refuse one costs less than finding it in a
  profile.
- **The vectorised classifier is off by default.** Not because it lost, but
  because it cannot be shown to have won: scalar and vectorised differ by
  less than one standard deviation over five repetitions. Kept behind
  `-D KNAP_SIMD=1`, compiled and tested rather than deleted, because the
  measurement is specific to this machine's lane count and this corpus's
  piece lengths. Numbers in `docs/BENCHMARKS.md`.
- **The piece cache is a type rather than a compile time flag.** A flag was
  written first and removed, because it makes it impossible to exercise both
  paths in one binary, and the cached path has to be tested against the
  uncached one in the same test run.
- **Every throughput benchmark now reads past the generated hazard section.**
  It reads a prefix of the corpus no longer, because the corpus opens with a
  large generated section whose first two megabytes hold 205 distinct
  whitespace separated words. Measured there, the piece cache reported a
  99.99 percent hit rate from 127 distinct pieces, which says nothing about
  real text. The Mojo harness and the Python baselines each hold the offset
  and `bench/run_all.sh` refuses to run if they disagree.
- Batch encoding is documented as single threaded. Mojo 1.0.0 has no working
  task parallelism: there is no `parallelize`, and `TaskGroup` aborts at
  runtime. This is a toolchain limitation recorded as one, not a design
  choice presented as one.
- `comptime if` replaces the deprecated `@parameter if`.
- The docstring gate now covers `src/knap` as well as `tests`.
- Both generators format their own output. Without that the formatter splits
  long string literals and the drift check reports permanent failure.
- CI generates every reference before running tests. Both 110 MB corpus
  gates moved to their own scheduled workflow, which together take about
  ten minutes and are too slow for every push.

### Fixed

- **The command line tool could not be piped.** It encoded correctly and
  `knap encode X | knap decode` failed with a write error, because opening
  `/dev/stdout` works when standard output is a file or a terminal and fails
  when it is a pipe. Reading `/dev/stdin` from a pipe does work, which is
  what made the asymmetry easy to miss. Found by running the tool rather
  than by testing the parser, which is why `cli/tests/test_end_to_end.py`
  exists at all.
- **The Unicode tables were built from the wrong Unicode version, and this
  changed tokenizer output.** They were generated from Python `unicodedata`,
  which answers from 15.0.0, while the tables `tiktoken` behaves as are
  16.0.0. Roughly six hundred code points changed general category between
  those releases and each is a pre-token boundary in the wrong place. Found
  by the fuzzer after 19288 inputs; a 110 MB corpus of natural language had
  not found it and would not have. The first attempted fix, regenerating
  against the `regex` module's tables, was also wrong. What settled it was a
  probe over the code points that differ between the two versions, which
  agreed with 16.0.0 on 400 of 400 inputs. Tables and the reference pattern
  are now pinned to UCD 16.0.0 and to a digest.
- **The fuzzing driver reported a clean run that had covered half its
  inputs.** LeakSanitizer exits with status 23 when it reports anything, and
  the driver treated any non-zero exit as a shard failure, stopped after the
  first shard, and printed a divergence count of zero taken from the
  counters that shard had already reported. It now separates a divergence
  from an abort and reports the two differently.
- `scripts/gen_pretoken_golden.py` read the corpus with `read_text`, which
  applies universal newline translation and silently rewrote every carriage
  return and line feed pair before the reference pattern saw it. The scanner
  was right and the reference was wrong. Found by the 110 MB gate on its
  first run.
- `scripts/check_file_banners.py` expected the generated provenance fields in
  the wrong position and looked for the overwrite warning only in field
  values, so it could not be satisfied by a wrapped warning line.

### Removed

- The `KNAP_PIECE_CACHE` compile time flag, which was declared before the
  cache existed and which nothing read. Replaced by `knap.cache.PieceCache`.
  A flag nothing reads is a placeholder, and this repository does not keep
  those.

### Verified

- **Encode parity survived the merge path rewrite.** All four corpus gates,
  191762320 tokens, byte identical to `tiktoken` after each of the four
  changes rather than once at the end. The decode, round trip, cache,
  hazard and fixture suites were re-run after each as well.
- **Encode parity across seven encodings.** Every token Knap emits matches
  `tiktoken` at the same position across a 110 MB corpus, for each of the
  four distinct encode behaviours the seven names reduce to: 43529983
  tokens for `cl100k_base`, 36927147 for `o200k_base`, 55723134 for `gpt2`
  and 55582056 for `p50k_base`, 191762320 in total. Every one of the seven
  is separately compared against its own `tiktoken` fixture, which is what
  catches a loader reading the wrong file.
- **Decode parity across seven encodings.** All 702463 ids, with the number
  of undecodable ids asserted exactly for each rather than loosely for all.
- **Pre-tokenization parity across three patterns.** 83025959 piece
  boundaries over the same corpus, adding 28699602 for `gpt2`.
- **Round tripping across seven encodings.** Every committed fixture and
  every one of the 256 byte values, under each encoding in turn, because
  round tripping exercises decode and decode is where the seven differ.
- **The command line tool and the Python bindings agree with `tiktoken` on
  all seven.** 112 inputs through the built binary, including through
  pipes, and every case through the native extension.
- **What M7 did not verify, stated rather than implied.** The differential
  fuzzer, its driver and the sanitizer harness all take seven encodings and
  the nightly job runs seven, but the committed report covers the two that
  were fuzzed, and the figures quoted in this file are that report's.
  Likewise the benchmark harness measures four encode behaviours and
  `docs/BENCHMARKS.md` publishes the two measured on an idle machine.
  Widening either claim ahead of the run would be the unearned figure that
  `scripts/check_fuzz_claims.py` exists to refuse.
- **Encode parity.** Every token Knap emits matches `tiktoken` at the same
  position across a 110 MB corpus: 43529983 tokens for `cl100k_base` and
  36927147 for `o200k_base`, 80.5 million in total. This is the first end to
  end parity result the project has, and it covers the whole pipeline.
- **Decode parity.** Every token id in both encodings decodes byte
  identically to `tiktoken.decode_single_token_bytes`: 300296 ids in total.
- **Pre-tokenization parity.** Every piece boundary matches the reference
  regex across the same corpus: 28075654 pieces for `cl100k_base` and
  26250703 for `o200k_base`.
- **Round tripping.** Every byte value, every fixture, and deliberately
  malformed sequences come back unchanged.
- **Unicode tables.** All 1114112 code points match an independent
  reference, and the whitespace predicate is exact in both directions.
- **Differential fuzzing.** 20000000 generated inputs across the two
  encodings shipped at the time, of which 16661834 were compared against `tiktoken` token for
  token and 3338166 were round trip checked because they are not valid
  UTF-8. Zero divergences. Every shard seed is recorded in
  `tests/fuzz/last_run.json`.
- **Under the address sanitizer.** 200000 of those inputs again, zero
  divergences, with the reference implementation's own leaks suppressed by
  module name and the reasoning recorded. Separately, 40000 inputs through
  `asan_solo.mojo` with no interpreter in the process and no suppression
  file at all, which is the run that shows Knap does not leak.
- **The byte keyed rank table preserves parity.** The full suite, both
  classifier builds, and both 110 MB corpus gates pass unchanged after the
  rank lookup was rewritten: 28075654 and 26250703 piece boundaries, and
  43529983 and 36927147 tokens, all byte identical to the reference.
- **The piece cache preserves parity.** Every cached result over every
  fixture matches the same tiktoken reference the uncached path is held to,
  for both encodings, including when the cache is full, disabled, or
  refusing pieces for being too long.
- The suite passes under `--sanitize address`.
- EmberJson was evaluated and passed both acceptance criteria. It is not a
  dependency, and now will not become one in this version: the Hugging Face
  loader that would have imported it is deferred by decision rather than
  pending. See `docs/ROADMAP.md`.

## 0.1.0, 2026-09-07

Never tagged. Recorded here because the work happened and the date is
accurate, not because an artefact under this number was ever published.

Milestone M0, scaffold. The toolchain, the repository standard, and the
machinery that enforces it. No tokenizer functionality.

### Added

- Pinned Mojo 1.0.0 toolchain, installable two ways. `pyproject.toml` drives
  the primary `uv` environment and `pixi.toml` the alternate, and both were
  installed and run from clean rather than only written.
- A single environment holding the Mojo compiler, `tiktoken`, and Hugging Face
  `tokenizers`, which is what lets the M4 differential fuzzer run both
  implementations in one process with no subprocess boundary.
- `tests/test_toolchain.mojo`, a four test suite that proves the compiler
  builds and runs, and that pins the standard library behaviour Knap depends
  on, including the element-wise SIMD comparison spelling.
- `scripts/lint_style.py`, enforcing the em-dash, emoji, ASCII, and
  exclamation mark rules with exactly three exemptions.
- `scripts/check_file_banners.py`, enforcing the source banner, its field
  order, the path match, and the closing marker.
- `scripts/check_md_headers.py`, enforcing Markdown headers, metadata tables,
  heading levels, fence language tags, link and anchor resolution, and
  document control footers.
- `scripts/check_spdx.py`, enforcing the SPDX identifier across every source,
  script, and document.
- `scripts/unstable_api_inventory.py`, which builds the unstable API inventory
  from the compiler's own JSON diagnostics.
- Continuous integration running the standards gates, the formatter check, the
  docstring gate, the test suite, and a separate address sanitizer job.
- `LICENSE`, the official EUPL 1.2 English text from the European Commission
  Joinup portal, with its upstream checksum recorded in
  `THIRD_PARTY_NOTICES.md`.
- Project documentation: `docs/ARCHITECTURE.md`, `docs/CORRECTNESS.md`,
  `docs/STYLE.md`, and `docs/ROADMAP.md`, plus `README.md`,
  `CONTRIBUTING.md`, `AUTHORS.md`, `CITATION.cff`, and
  `THIRD_PARTY_NOTICES.md`.

### Changed

- Nothing. This is the first entry.

### Fixed

- `scripts/lint_style.py` no longer reports the exclamation mark inside an
  HTML comment opener as prose. Every Markdown document in this project is
  required to open with an HTML comment carrying the licence header, so the
  rule as first written made the required header impossible to satisfy.

### Removed

- Nothing. This is the first entry.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [AUTHORS.md](AUTHORS.md) |
| Next | [README.md](README.md) |
| Index | [README.md](README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-10 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: CHANGELOG.md -->
