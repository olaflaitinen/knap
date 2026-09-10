<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Getting Help With Knap

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
| Document | `SUPPORT.md` |
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

1. [Where to go](#where-to-go)
2. [Read these first](#read-these-first)
3. [Questions that already have answers](#questions-that-already-have-answers)
4. [What this project does not promise](#what-this-project-does-not-promise)

---

## Where to go

| You want to | Go here |
| --- | --- |
| Report different token ids from the reference | The [parity divergence](https://github.com/olaflaitinen/knap/issues/new?template=01-parity-divergence.yml) issue form. This is the highest priority report the project takes. |
| Report a crash, hang, or build failure | The [bug report](https://github.com/olaflaitinen/knap/issues/new?template=02-bug-report.yml) form. |
| Report something slow | The [performance report](https://github.com/olaflaitinen/knap/issues/new?template=03-performance-report.yml) form. Read [docs/BENCHMARKS.md](docs/BENCHMARKS.md) first. |
| Propose a feature | The [feature request](https://github.com/olaflaitinen/knap/issues/new?template=04-feature-request.yml) form. Read the deferred list in [docs/ROADMAP.md](docs/ROADMAP.md) first. |
| Report a documentation error | The [documentation](https://github.com/olaflaitinen/knap/issues/new?template=05-documentation.yml) form. A document asserting something false is treated as seriously here as code computing something false. |
| Ask how to do something | [Discussions](https://github.com/olaflaitinen/knap/discussions). |
| Report a vulnerability | Privately. See [SECURITY.md](SECURITY.md). Not an issue, not a discussion. |

The issue forms ask for a lot. That is deliberate: a report missing the exact
bytes, the versions, and how the reference output was obtained has to be sent
back for them, which costs the reporter another round trip. Every closed
question has an option for not knowing, so nothing forces a guess.

## Read these first

Most questions are answered in one of these documents, and each of them is
written to be read rather than skimmed.

| Document | Answers |
| --- | --- |
| [README.md](README.md) | What Knap is, what is verified, what is not, and when not to use it. |
| [docs/CORRECTNESS.md](docs/CORRECTNESS.md) | What parity means here, exactly what has been checked, and the one divergence class the project has had. |
| [docs/BENCHMARKS.md](docs/BENCHMARKS.md) | Every published number, the machine it came from, and a section on what the numbers do not mean. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the four stages work, and why each design decision went the way it did. |
| [docs/ROADMAP.md](docs/ROADMAP.md) | What is deliberately not built, with the reason for each. |
| [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) | Everything about Mojo 1.0.0 that is not what you would assume. Useful whether or not you use Knap. |
| [docs/METHODOLOGY.md](docs/METHODOLOGY.md) | How the numbers above were measured, and how to measure your own without fooling yourself. |
| [examples/README.md](examples/README.md) | Two working programs, and the two places callers of every tokenizer write the same wrong code. |

## Questions that already have answers

**Is Knap faster than tiktoken?** On the published machine, yes on three of
the four distinct encode behaviours and level on the fourth. It is still 28
to 32 percent slower than `rs-bpe` on the two encodings `rs-bpe` ships, and
it is single threaded where both `tiktoken` and Hugging Face `tokenizers`
parallelise a batch across cores. The numbers, the machine, and the
baselines that win are all in
[docs/BENCHMARKS.md](docs/BENCHMARKS.md) with the same prominence.

That answer changed on 2026-09-09 and the previous one is worth keeping in
view: Knap was between 1.7 and 2.7 times slower than `tiktoken` a day
earlier. Four changes to the merge path closed it, none of them a language
argument, and all four are described in that document.

**Which encodings are supported?** All seven that `tiktoken` ships:
`cl100k_base`, `o200k_base`, `o200k_harmony`, `p50k_base`, `p50k_edit`,
`r50k_base` and `gpt2`. Each was checked against `tiktoken` itself rather
than against a sibling encoding that resembles it. They are served from four
vocabulary files, because three of the seven share a merge table with
another, and `scripts/fetch_vocabs.py` downloads all four.

**Can I use it from Python?** Yes, through a native extension you build
locally. See [bindings/python/README.md](bindings/python/README.md). There is
no wheel on PyPI and there should not be one until the Mojo ABI is stable,
because a wheel is a promise that the binary inside it keeps working.

**Does it support Hugging Face `tokenizer.json`?** No, and this is a decision
rather than a gap. That format specifies its own pre-tokenizer, so a loader
needs its own parity corpus and its own reference implementation. Shipping
one without those would put an unverified path inside a library whose whole
claim is verification.

**Why is batch encoding single threaded?** Because Mojo 1.0.0 has no working
task parallelism. There is no `parallelize`, and `TaskGroup` aborts at
runtime. It is a toolchain limitation recorded as one rather than a design
choice presented as one.

**Why is the SIMD classifier off by default?** Because it cannot be shown to
help. On the published machine it differs from the scalar path by less than
one standard deviation. That is a weaker claim than saying it lost, and it is
the one the measurements support.

**Which Unicode version does it use?** 16.0.0, from the Unicode Character
Database, pinned to a digest. Not the interpreter's `unicodedata`, which
answers from 15.0.0. The difference produced a real divergence, and
[docs/UNICODE.md](docs/UNICODE.md) tells that story because it is the most
useful thing in the repository for anyone building something similar.

## What this project does not promise

Knap is a single author project written as part of academic work. There is no
company behind it and no support contract.

- **No response time guarantee** on issues or discussions, other than the
  security targets in [SECURITY.md](SECURITY.md), which are stated because a
  vulnerability report deserves a stated target even from one person.
- **No commitment to add a feature** because it was requested. The deferred
  list in [docs/ROADMAP.md](docs/ROADMAP.md) exists so that a request can be
  checked against a decision that has already been reasoned through.
- **No consulting or integration help.** The documentation is the support.

What the project does promise is that every claim in it can be checked.
Every gate has been run and observed, every number names the machine it came
from, and every correction is recorded rather than quietly applied. If you
find a claim that does not survive checking, that is a documentation defect
and there is a form for it.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| Next | [README.md](README.md) |
| Index | [README.md](README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-08 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: SUPPORT.md -->
