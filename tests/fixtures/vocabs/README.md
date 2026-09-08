<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Vocabulary Fixtures

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
| Document | `tests/fixtures/vocabs/README.md` |
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

## Why this directory is empty

Vocabulary files are fetched, not committed. `cl100k_base.tiktoken` and
`o200k_base.tiktoken` are downloaded into this directory by
`scripts/fetch_vocabs.py` and are excluded by `.gitignore`.

There are two reasons, and both matter:

1. **Licensing.** The vocabularies are third party data distributed under
   their own terms. Not committing them means no licence question attaches to
   this repository, and the terms that apply are whatever the upstream
   publisher states rather than something implied by redistribution here.
2. **Provenance.** A fetch script records the exact URL and the checksum of
   what it downloaded. A committed blob records only that somebody once added
   a file. The first can be verified, the second has to be trusted.

The files are large as well, but that is the least important of the reasons.

## How to fetch them

The fetch script arrives with milestone M1, together with the vocabulary
loader it feeds. Until then this directory stays empty, because a fixture that
nothing reads is not a fixture.

Once it exists the command will be, from the repository root:

```bash
uv run python scripts/fetch_vocabs.py
```

Tests that need a vocabulary skip with a clear message when the files are
absent, rather than failing. A missing download is a setup step that has not
been run, not a defect in Knap.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [tests/fixtures/hf/README.md](../hf/README.md) |
| Next | [docs/CORRECTNESS.md](../../../docs/CORRECTNESS.md) |
| Index | [README.md](../../../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-07 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../../../LICENSE) for the full terms.

<!-- End of document: tests/fixtures/vocabs/README.md -->
