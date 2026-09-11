<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Hugging Face Tokenizer Fixtures

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
| Document | `tests/fixtures/hf/README.md` |
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

## Why this directory is empty

Hugging Face `tokenizer.json` samples are fetched, not committed, for the same
two reasons as the `.tiktoken` vocabularies next door: the files are third
party data under their own terms, and a fetch script records a verifiable URL
and checksum where a committed blob records nothing.

See [tests/fixtures/vocabs/README.md](../vocabs/README.md) for the fuller
explanation.

## The loader these were for does not exist

Read this before assuming the directory is waiting on a download.

**Knap has no Hugging Face `tokenizer.json` loader, and not building one is a
decision rather than a delay.** `src/knap/hf/tokenizer_json.mojo` was in the
original layout, was never written, and now sits on the deferred list in
[docs/ROADMAP.md](../../../docs/ROADMAP.md) with the reasoning. In short: that
format specifies its own pre-tokenizer, its own added token rules, and
vocabularies built by a different pipeline, so a loader for it needs its own
parity corpus and its own reference implementation. Shipping one without
those would put an unverified path inside a library whose entire claim is
verification.

This directory and its fetch path are kept because the analysis behind them
is still correct, and whoever writes that loader will need exactly these
samples. Two properties of real vocabulary files are why the samples have to
be fetched rather than hand written:

| Property | Why a real sample is needed |
| --- | --- |
| File size | Real vocabulary files are tens of megabytes. A parser that is correct on a small document can still fail on a large one, through buffering or recursion limits. |
| Escaped unicode in string values | Token strings arrive as escaped sequences, including surrogate pairs. Getting the unescaping wrong changes token bytes, which changes token ids, silently. |

Both properties were also the acceptance criteria for adopting a third party
JSON parser. That decision was made and is recorded in
[docs/ARCHITECTURE.md](../../../docs/ARCHITECTURE.md).

Nothing about this format is part of the parity claim. Parity is defined
against `tiktoken`, and a `tokenizer.json` model has no `tiktoken`
counterpart to be compared with.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [tests/fixtures/corpus/README.md](../corpus/README.md) |
| Next | [tests/fixtures/vocabs/README.md](../vocabs/README.md) |
| Index | [README.md](../../../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-11 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../../../LICENSE) for the full terms.

<!-- End of document: tests/fixtures/hf/README.md -->
