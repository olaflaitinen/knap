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
| Updated | 2026-09-07 |
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

Nothing yet. The next work is milestone M1, vocabulary loading and decode.

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
