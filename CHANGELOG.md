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
| Applies to | Knap 0.1.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-07 |
| Updated | 2026-09-08 |
| Licence | EUPL-1.2 |

---

## Contents

1. [Format](#format)
2. [Unreleased](#unreleased)
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

## Unreleased

Milestones M1 through M6. Nothing here has been tagged or published, so it
stays under Unreleased rather than claiming a version.

One entry below changes tokenizer output, and it is the Unicode version fix
under Fixed. Everything else either adds a capability or leaves behaviour
untouched.

### Added, milestone M6, distribution

- `recipe/recipe.yaml`, a conda recipe targeting the `modular-community`
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
  encodings, of which 16661834 were compared against `tiktoken` token for
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
| Last reviewed | 2026-09-07 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: CHANGELOG.md -->
