<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Corpus Fixtures

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="../../../docs/assets/knap_logo_transparent_white.svg">
    <img src="../../../docs/assets/knap_logo_transparent_black.svg"
         alt="Knap" width="240">
  </picture>
</p>

| Field | Value |
| --- | --- |
| Document | `tests/fixtures/corpus/README.md` |
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

## Fixtures against corpus

This directory holds small, hand written edge case files, and those **are**
committed. The large benchmark and parity corpus is a different thing
entirely: it is fetched by `scripts/fetch_corpus.py` into `bench/corpus/` and
is never committed.

The distinction matters because the two have opposite requirements.

| | Fixtures, here | Corpus, fetched |
| --- | --- | --- |
| Size | Bytes to kilobytes | 100 MB and up |
| Committed | Yes | No |
| Purpose | Pin one specific behaviour | Measure aggregate parity and throughput |
| Stability | Exact bytes must never change | May be regenerated or replaced |

A fixture whose bytes drift silently stops testing what it was written to
test, so these files are treated as binary by `.gitattributes` and are exempt
from the repository ASCII rule. They deliberately contain multilingual text,
emoji, and invalid UTF-8, because a byte level BPE tokenizer must handle
arbitrary bytes.

## The fixtures

All six arrived at milestone M2, alongside the scalar pre-tokenizer they
exercise, and the test suite reads them on every push. Until they had
content they were absent rather than empty, because a fixture with no content
would pass every test that reads it while proving nothing.

| File | Exercises |
| --- | --- |
| `ascii_en.txt` | The ASCII fast path, which dominates real text. |
| `mixed_multilingual.txt` | Multi-byte sequence handling across scripts. |
| `code.txt` | Punctuation density and long non-word runs. |
| `emoji.txt` | Zero width joiner sequences, skin tone modifiers, flags. |
| `whitespace_edges.txt` | The whitespace lookahead hazard, including text that ends mid whitespace. |
| `invalid_utf8.bin` | The byte level contract. Invalid input is neither rejected nor replaced. |

The hazards each of these targets are listed in
[docs/CORRECTNESS.md](../../../docs/CORRECTNESS.md).

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/CORRECTNESS.md](../../../docs/CORRECTNESS.md) |
| Next | [tests/fixtures/hf/README.md](../hf/README.md) |
| Index | [README.md](../../../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-10 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../../../LICENSE) for the full terms.

<!-- End of document: tests/fixtures/corpus/README.md -->
