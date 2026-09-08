<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Roadmap

| Field | Value |
| --- | --- |
| Document | `docs/ROADMAP.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 0.1.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-07 |
| Updated | 2026-09-07 |
| Licence | EUPL-1.2 |

---

## Contents

1. [Milestone gates](#milestone-gates)
2. [Current position](#current-position)
3. [Files not yet written](#files-not-yet-written)
4. [Deferred beyond version 1](#deferred-beyond-version-1)
5. [Toolchain constraints](#toolchain-constraints)
6. [Release and archiving](#release-and-archiving)

---

## Milestone gates

A gate is not passed until its condition has actually been run and observed.
Reasoning that the code looks right does not pass a gate.

```mermaid
flowchart TD
    M0[M0 Scaffold<br/>toolchain, standards, CI] --> M1
    M1[M1 Vocabulary and decode] --> M2
    M2[M2 Pre-tokenizer, scalar] --> M3
    M3[M3 BPE merge and encode] --> M4
    M4[M4 Differential fuzzing] --> M5
    M5[M5 SIMD and benchmarks] --> M6A
    M5 --> M6B
    M6A[M6 Track A<br/>Mojo packaging]
    M6B[M6 Track B<br/>Python bindings]
```

Two orderings are binding and cannot be traded away:

- **Scalar before SIMD.** The scalar scanner must be correct and its golden
  test passing before any SIMD classifier is written. The scalar path is not
  scaffolding to be discarded. It stays forever as the reference that the SIMD
  path is differentially tested against.
- **Parity before optimization.** M4 must be green before any M5 work lands.
  Optimising against an unverified baseline produces fast wrong answers.

M6 splits into two independent tracks because one may succeed while the other
does not. Track A should succeed. Track B depends on a capability that has not
been verified to exist.

## Current position

M0, M1, and M2 are complete. Every condition below was observed, not
inferred.

M2 delivered the generated pattern constants, the Unicode tables, the UTF-8
decoder, the scalar classifier, and the two scanners. Its gate, matching the
reference regex over at least 100 MB of mixed text, passes for both patterns
across 54.3 million pieces.

| M2 condition | Evidence |
| --- | --- |
| Pattern extracted, not transcribed | `scripts/extract_patterns.py`, with the committed constant checked for drift. |
| Unicode tables generated | Unicode 15.0.0, 2342 runs, verified against all 1114112 code points. |
| Scalar scanner correct | 28075654 and 26250703 piece boundaries identical to the reference over 110 MB. |
| Both representations measured | Sorted runs against a two stage table, written up in `docs/UNICODE.md`. |
| Suite under ASan | Passes, including the scanner over the full corpus. |

The M1 conditions, for the record:

M1 delivered vocabulary loading, the flat token store, decode over the full
id space, and the special token registry. Its gate, decoding every token id
in both vocabularies byte identically against `tiktoken`, passes for all
300296 ids. See [docs/CORRECTNESS.md](CORRECTNESS.md).

| M1 condition | Evidence |
| --- | --- |
| `.tiktoken` loader | `src/knap/vocab.mojo`, strict on every malformed shape, 7 rejection tests. |
| FlatVocab | `src/knap/flat_vocab.mojo`, spans validated once at construction. |
| Decode | Byte exact over both encodings, including the gaps, which raise. |
| Special token registry | `src/knap/special.mojo`, ids cross checked by decoding each to its own literal text. |
| EmberJson evaluated | Passed both acceptance criteria. Decision recorded in `docs/ARCHITECTURE.md`. |
| Suite under ASan | All 26 tests pass with `--sanitize address`. |

The M0 conditions, for the record:

| M0 condition | Evidence |
| --- | --- |
| Agent skills installed | Four Mojo skills installed from the Modular repository. |
| Mojo VS Code extension installed | Version 26.6.1. |
| Toolchain pinned and working | Mojo 1.0.0 build `ed45d567`, installed by uv and independently by pixi. |
| A Mojo file compiles and runs | `tests/test_toolchain.mojo`, four tests, all passing. |
| Test runner wired up | Standard library `TestSuite`, since `mojo test` does not exist in 1.0.0. |
| Standards scripts written and passing | Four scripts, each demonstrated to fail on a planted violation. |
| Unstable API inventory captured | 108 uses across 22 APIs, recorded in `docs/ARCHITECTURE.md`. |
| Sanitizer job proven | `--sanitize address` builds and runs the suite clean. |

## Files not yet written

The repository brief asked for the complete directory tree to be created up
front with stub files, and separately forbade placeholders in committed files.
Those two instructions conflict, and the conflict is resolved here in favour
of the no-placeholder rule, which is listed as a hard constraint.

Every directory in the layout exists. Files that cannot yet be complete are
absent rather than stubbed, and are listed below with the milestone that
creates them. A stub that compiles but does nothing would pass every gate in
this repository while providing nothing, which is precisely the failure mode
the no-placeholder rule exists to prevent.

| Path | Created at |
| --- | --- |
| `src/knap/tokenizer.mojo`, `ranks.mojo`, `bpe.mojo`, `cache.mojo`, `config.mojo` | M3, with the cache measured at M5 |
| `src/knap/pretokenize/classifier_simd.mojo` | M5 |
| `src/knap/hf/tokenizer_json.mojo` | After M3, experimental |
| `tests/test_*.mojo` beyond the toolchain smoke test | Alongside the code each one tests |
| `tests/fuzz/*` | M4 |
| `bench/*` | M5 |
| `encode_expected.jsonl` output from `scripts/gen_encode_golden.py` | M3, when there is an encoder to compare |
| `bindings/python/*` | M6 Track B, if it proves viable |
| `docs/BENCHMARKS.md` | M5, when there are real numbers to publish |
| `.github/workflows/bench.yml` | M5, when there is something to benchmark |

`.github/workflows/bench.yml` is absent for the same reason as
`docs/BENCHMARKS.md`. A manually dispatched workflow that runs no benchmarks
would report success while measuring nothing.

Two files exist that the original layout did not list. Both are additions
rather than substitutions, and neither creates a parallel directory:

| Path | Why it exists |
| --- | --- |
| `tests/test_toolchain.mojo` | The layout had no slot for the toolchain smoke test that M0 requires. It deliberately imports nothing from `src/knap`, so a failure there always means the compiler rather than Knap. |
| `scripts/selftest_gates.py` | M0 requires each standards gate to be observed failing on a planted violation. Doing that once by hand proves it once. This makes it repeatable and runs it in CI, so a gate that silently stops working is caught. |

`docs/BENCHMARKS.md` is deliberately absent rather than present and empty. A
benchmarks document with no benchmarks in it invites exactly the kind of
unsupported claim this project is trying to avoid.

## Deferred beyond version 1

Each of these is a decision, not an oversight.

| Item | Why deferred |
| --- | --- |
| BPE training | Knap encodes. Training is a different program with a different correctness story and no shared hot path. |
| Offset mapping, character spans per token | Genuinely valuable, and it doubles the correctness surface. Every parity test would need a second dimension. Revisit once encode parity is established and stable. |
| WordPiece, Unigram, SentencePiece | Different algorithms, not variations on this one. Each would need its own parity corpus and its own reference implementation. |
| Normalization pipelines, NFC and NFKC | `cl100k_base` and `o200k_base` do not normalize. Adding a normalizer that is not needed can only introduce divergence. |
| Chat templates | A serving concern layered above tokenization, not part of it. |
| GPU tokenization | The merge loop does not vectorize on a CPU and will not on a GPU. The pre-tokenizer might, but the transfer cost would dominate at realistic input sizes. |
| Single document parallelism | A pattern match may span a chunk boundary, so independent chunks can produce different tokens. Reproducing the boundary adjustment logic correctly is a project of its own. See `docs/ARCHITECTURE.md`. |
| Additional vocabularies beyond the two targeted | Each additional vocabulary multiplies the fuzzing and golden fixture cost. Add them only when the parity methodology has proven itself on two. |

## Toolchain constraints

These are limits of the current toolchain rather than choices, and each one
should be revisited when the toolchain moves.

| Constraint | Consequence |
| --- | --- |
| Mojo publishes no Windows wheel | Windows development requires WSL. There is no native Windows build and the README says so. |
| The Mojo ABI is not stable | Any Python binding is version locked to the exact toolchain and must be rebuilt per release. |
| Almost the entire standard library is unstable | The unstable API inventory is a record of exposure, not an action list. See `docs/ARCHITECTURE.md`. |
| `--Werror` and `--warn-on-unstable-apis` cannot be combined | CI runs them as separate jobs, one gating and one reporting. |
| `mojo format` has no check mode | CI formats in place and then verifies the working tree is unchanged. |
| No native Mojo package manager | Libraries are distributed as conda packages. Release targets the `modular-community` channel. |
| Whether Mojo can export an importable Python extension module is unverified | M6 Track B is designed around a flat C compatible surface so the `--emit shared-lib` fallback stays open regardless of the answer. |

## Release and archiving

Once there is a tagged release, archiving it through Zenodo would produce a
citable DOI, which pairs naturally with the ORCID already recorded in
`CITATION.cff`. This is very likely wanted, and it is not done unprompted
because it is the author's decision to make.

`CITATION.cff` version and release date are updated in the same commit as the
`CHANGELOG.md` entry for that release.

One release rule specific to this project: any change to tokenizer output is a
breaking change, even when the public API is untouched. Consumers pin token
ids into caches, datasets, and evaluation results, so an output change breaks
them just as thoroughly as a signature change would.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/STYLE.md](STYLE.md) |
| Next | [README.md](../README.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-07 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/ROADMAP.md -->
