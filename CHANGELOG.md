<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Changelog

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

Milestones M1 and M2. Nothing here has been tagged or published, so it stays
under Unreleased rather than claiming a version.

No entry below changes tokenizer output, because Knap did not produce output
before these milestones.

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

- The docstring gate now covers `src/knap` as well as `tests`.
- Both generators format their own output. Without that the formatter splits
  long string literals and the drift check reports permanent failure.
- CI generates every reference before running tests, and the 110 MB corpus
  gate moved to its own scheduled workflow.

### Fixed

- `scripts/gen_pretoken_golden.py` read the corpus with `read_text`, which
  applies universal newline translation and silently rewrote every carriage
  return and line feed pair before the reference pattern saw it. The scanner
  was right and the reference was wrong. Found by the 110 MB gate on its
  first run.
- `scripts/check_file_banners.py` expected the generated provenance fields in
  the wrong position and looked for the overwrite warning only in field
  values, so it could not be satisfied by a wrapped warning line.

### Removed

- Nothing.

### Verified

- **Decode parity.** Every token id in both encodings decodes byte
  identically to `tiktoken.decode_single_token_bytes`: 300296 ids in total.
- **Pre-tokenization parity.** Every piece boundary matches the reference
  regex across a 110 MB corpus: 28075654 pieces for `cl100k_base` and
  26250703 for `o200k_base`.
- **Unicode tables.** All 1114112 code points match an independent
  reference, and the whitespace predicate is exact in both directions.
- The suite passes under `--sanitize address`.
- EmberJson was evaluated and passed both acceptance criteria. It is not yet
  a dependency, because nothing imports it until the Hugging Face loader
  exists.

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
