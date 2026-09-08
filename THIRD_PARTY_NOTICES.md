<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Third Party Notices

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
| Document | `THIRD_PARTY_NOTICES.md` |
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

1. [How to read this file](#how-to-read-this-file)
2. [Runtime dependencies](#runtime-dependencies)
3. [Development and test dependencies](#development-and-test-dependencies)
4. [Benchmark baselines](#benchmark-baselines)
5. [Reference implementations consulted](#reference-implementations-consulted)
6. [Data sources](#data-sources)
7. [The licence text itself](#the-licence-text-itself)

---

## How to read this file

External works fall into three relationships, and they carry different
obligations. Keeping them apart is the point of this document.

| Relationship | Meaning | Obligation |
| --- | --- | --- |
| Runtime dependency | Shipped with or required by Knap at run time. | Licence compatibility matters directly. |
| Benchmark baseline or development tool | Used to measure or build Knap. Never distributed with it. | No distribution obligation, but the work must still be credited. |
| Reference implementation consulted | Read to understand behaviour. No code copied. | Attribution and a standing rule against copying. |

The third category must never become the first by accident. No source code
from `tiktoken`, `rs-bpe`, or Hugging Face `tokenizers` is copied into this
repository. Behaviour is reimplemented from specification and from observed
output, and the one artefact taken programmatically, the pre-tokenization
pattern, is extracted as a functional specification with its provenance
recorded in the generated file.

## Runtime dependencies

| Work | Upstream | Licence | Version | Use |
| --- | --- | --- | --- | --- |
| Mojo standard library and compiler | <https://www.modular.com/mojo> | Proprietary, `LicenseRef-Modular-Proprietary` for the conda package | 1.0.0, pinned exactly | The language Knap is written in. Required to build and to run. |

Knap has no third party Mojo library dependency. The evaluation that produced
that outcome is recorded in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development and test dependencies

| Work | Upstream | Licence | Version | Use |
| --- | --- | --- | --- | --- |
| `tiktoken` | <https://github.com/openai/tiktoken> | MIT | 0.14.0 | Reference implementation for parity. Generates golden fixtures and drives the differential fuzzer. Also the source of the pre-tokenization pattern, extracted programmatically. |
| Hugging Face `tokenizers` | <https://github.com/huggingface/tokenizers> | Apache-2.0 | 0.23.2 | Benchmark baseline. |
| `rs-bpe` | <https://github.com/github/rs-bpe> | MIT | 0.1.6 | Benchmark baseline. Imported as `rs_bpe.bpe.openai`, not as `rs_bpe.openai`, which the published documentation gives and which does not resolve in the shipped wheel. |
| `regex` | <https://github.com/mrabarnett/mrab-regex> | Apache-2.0 | 2026.9.3 | Generates reference pre-token boundaries. Supports the Unicode property syntax the patterns use, which the standard library `re` module does not. |
| `uv` | <https://github.com/astral-sh/uv> | Apache-2.0 or MIT | 0.12.10 | Primary environment manager. |
| `pixi` | <https://github.com/prefix-dev/pixi> | BSD-3-Clause | 0.80.0 | Alternate environment manager, kept working and tested. |

None of these is distributed with Knap. They are development and measurement
tools only.

## Benchmark baselines

Baselines are run by the author, on the author's machine, against the same
inputs. Numbers are never copied from another project's README.

| Work | Upstream | Licence | Role |
| --- | --- | --- | --- |
| `tiktoken` | <https://github.com/openai/tiktoken> | MIT | Primary baseline and parity reference. |
| Hugging Face `tokenizers` | <https://github.com/huggingface/tokenizers> | Apache-2.0 | Baseline. |
| `rs-bpe` | <https://github.com/github/rs-bpe> | MIT | Baseline, and an algorithmic reference for the merge loop. |

If a baseline wins, that is published in the same table with the same
prominence as any Knap result.

## Reference implementations consulted

| Work | Upstream | Licence | What was taken |
| --- | --- | --- | --- |
| `tiktoken` | <https://github.com/openai/tiktoken> | MIT | Behaviour, and the pre-tokenization pattern string extracted programmatically. No source code. |
| `rs-bpe` | <https://github.com/github/rs-bpe> | MIT | Algorithmic ideas for the merge loop. No source code. |
| Hugging Face `tokenizers` | <https://github.com/huggingface/tokenizers> | Apache-2.0 | Nothing was taken. The `tokenizer.json` format was read while scoping a loader for it, and that loader was deferred rather than written. See [docs/ROADMAP.md](docs/ROADMAP.md). No source code. |
| `atsentia/mojo-tokenizer` | <https://github.com/atsentia/mojo-tokenizer> | See upstream | Prior art in pure Mojo, noted for its published throughput. No source code. |
| `mojo-regex` | <https://github.com/msaelices/mojo-regex> | See upstream | Read for reference only. Rejected as a dependency because it pins a pre-1.0 compiler. No source code. |

## Data sources

| Source | Upstream | Licence | Use |
| --- | --- | --- | --- |
| Unicode Character Database, version 16.0.0 | <https://www.unicode.org/Public/16.0.0/ucd/UnicodeData.txt> | Unicode Licence | Source of every general category range the pre-tokenization patterns test. Downloaded and verified against a recorded SHA-256 digest by `scripts/ucd.py`, not read through Python `unicodedata`. That distinction is not cosmetic: the interpreter answers from Unicode 15.0.0, the reference implementation behaves as 16.0.0, and building the tables from the former produced a real divergence. See [docs/UNICODE.md](docs/UNICODE.md). |
| `cl100k_base` and `o200k_base` vocabularies | Distributed by OpenAI, fetched by `scripts/fetch_vocabs.py` | See upstream | Vocabulary and merge ranks. Fetched at build time and never committed, so no licence question attaches to this repository and the exact source is recorded rather than assumed. |
| Benchmark corpus | Fetched by `scripts/fetch_corpus.py` | Recorded per source in that script | Parity and throughput measurement. Never committed. |

## The licence text itself

`LICENSE` holds the official EUPL 1.2 English text.

| Field | Value |
| --- | --- |
| Source | European Commission Joinup portal |
| URL | <https://joinup.ec.europa.eu/collection/eupl> |
| Retrieved | 2026-09-07 |
| Upstream checksum, SHA-256 | `b1e85ac8fe9487274d9e6b2d7cbe32151de07a7311769b9487ab9955624dd47d` |
| In-repository checksum, SHA-256 | `2adf0b7d57057d68cba170c43834564cc62dab0fb060d7f45022448526f897ca` |

The two checksums differ because exactly two encoding level changes were made
and no others. The UTF-8 byte order mark was removed, and CRLF line endings
were normalised to LF to match the repository wide policy in
`.gitattributes`. No character of the legal text was altered, and the
transformation is reproducible from the upstream file, so the change can be
verified rather than trusted.

`scripts/lint_style.py` exempts `LICENSE` from the ASCII rule explicitly, with
a comment explaining why, so that a future contributor does not remove the
exemption and mangle a legal instrument.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [README.md](README.md) |
| Next | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Index | [README.md](README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-07 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: THIRD_PARTY_NOTICES.md -->
