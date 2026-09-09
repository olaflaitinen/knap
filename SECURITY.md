<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Security Policy

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
| Document | `SECURITY.md` |
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

1. [Why a tokenizer needs one of these](#why-a-tokenizer-needs-one-of-these)
2. [Reporting](#reporting)
3. [What is in scope](#what-is-in-scope)
4. [What is not in scope](#what-is-not-in-scope)
5. [Supported versions](#supported-versions)
6. [What to expect](#what-to-expect)
7. [Disclosure](#disclosure)

---

## Why a tokenizer needs one of these

A tokenizer sits on the boundary between untrusted input and a model prompt.
Everything a user types passes through it, and what comes out the other side
is fed to a system that treats certain token ids as control signals rather
than as content.

That makes two ordinary looking bugs into security bugs.

**Special token handling.** If text containing `<|endoftext|>` encodes to the
control token rather than to the characters that spell it, untrusted input
has injected a control signal into a prompt. Knap's default is to refuse:
`encode` raises unless the marker is explicitly allowed, and
`encode_ordinary` treats every marker as ordinary characters. A bug that
weakens either behaviour is a vulnerability, not a defect.

**Memory safety on the byte paths.** The vocabulary store does raw pointer
arithmetic and the classifier does unaligned vector loads, both driven by
attacker controlled bytes. A memory error there can produce correct output on
one run and corruption on the next.

## Reporting

**Report privately, through GitHub, not as a public issue.**

Use [Report a vulnerability](https://github.com/olaflaitinen/knap/security/advisories/new).
Private vulnerability reporting is enabled on this repository.

If GitHub is unavailable to you, email the author at the address in
[AUTHORS.md](AUTHORS.md), with `knap security` in the subject line.

What to include, in rough order of usefulness:

- The exact input bytes, as lowercase hexadecimal. A report about a byte
  sequence that cannot be reproduced byte for byte cannot be fixed.
- Which of the seven encodings, and which entry point.
- What happened and what should have happened.
- The Knap version or commit, and the Mojo toolchain version.
- Whether it reproduces under `--sanitize address`, and what the sanitizer
  said if so.
- Any suggested fix, though this is optional and never expected.

Please do not open a public issue, a pull request containing an exploit, or a
discussion thread, before the report has been answered.

## What is in scope

| Class | Example |
| --- | --- |
| Special token refusal bypassed | Untrusted text encodes to a control token id when it was not in the allowed set. |
| Special token refusal circumvented by encoding | A marker written in an unusual but decodable form is accepted where the literal form is refused. |
| Memory safety reachable from input | Out of bounds read or write, use after free, or invalid pointer arithmetic driven by the bytes being tokenized. |
| Unbounded resource use | Input of modest size that makes Knap allocate or run without bound. Note that the merge loop is quadratic in the piece length by design, and the pre-tokenizer bounds piece length, so a report here should show that bound being escaped. |
| Parity divergence with a security consequence | A divergence that changes which token ids a prompt boundary falls on, rather than one that merely differs. |
| A build or packaging path that executes attacker controlled input | Anything in `scripts/`, the conda recipe, or the Python bindings that runs downloaded content. |

## What is not in scope

Stated plainly so that a report is not written for nothing.

- **Performance.** Where Knap is slower than a baseline it says so in
  [docs/BENCHMARKS.md](docs/BENCHMARKS.md), with the winner in the same
  table. Slowness is not a vulnerability unless it is unbounded in the sense
  above.
- **A plain parity divergence.** Use the parity divergence issue form. Those
  are the highest priority ordinary bug this project receives, and they are
  handled in public because the fix benefits from the exact bytes being
  visible.
- **Bugs in the reference implementations.** Report those to `tiktoken`,
  `rs-bpe`, or Hugging Face `tokenizers` respectively.
- **Bugs in the Mojo toolchain**, unless Knap can avoid them.
- **Anything requiring local access** to a machine that is already running
  the reporter's own code.
- **Malformed UTF-8 producing unusual output.** The reference implementation
  cannot accept undecodable input, so there is no behaviour to diverge from.
  Knap promises only that encoding then decoding returns the same bytes, and
  a violation of that is an ordinary bug.

## Supported versions

| Version | Supported |
| --- | --- |
| `main` | Yes |
| 1.0.0 | Yes |

There is one line of development and no long term support branch. A fix
lands on `main` and is included in the next release. Backporting to an older
release is possible in principle and has not been necessary.

## What to expect

This is a single author project, not a vendor with a security team. Being
honest about that is more useful than publishing a service level agreement
that will not be met.

| Stage | Target |
| --- | --- |
| Acknowledgement | Within seven days |
| Initial assessment | Within fourteen days |
| Fix or a stated reason there will not be one | Within ninety days |

A report will be answered even when the answer is that it is out of scope or
not reproducible. Silence is not a verdict.

## Disclosure

Coordinated. The preference is to fix first and publish afterwards, with the
reporter credited unless they ask not to be.

If ninety days pass without a fix and without a stated reason, publish. A
project that cannot fix something within ninety days does not gain the right
to keep it quiet indefinitely, and users are better served by knowing.

When a vulnerability is fixed:

- The advisory is published on this repository.
- `CHANGELOG.md` records it under Fixed, and says plainly whether tokenizer
  output changed.
- A regression case is added to `tests/fuzz/corpus_seeds/` and stays there
  permanently, so the fuzzer keeps checking it long after the shape stops
  being generated.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Next | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| Index | [README.md](README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-08 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: SECURITY.md -->
