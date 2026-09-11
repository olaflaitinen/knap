<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Contributing to Knap

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
| Document | `CONTRIBUTING.md` |
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

## Contents

1. [Before you start](#before-you-start)
2. [Development setup](#development-setup)
3. [Running the checks](#running-the-checks)
4. [Running the tests](#running-the-tests)
5. [Running the fuzzer](#running-the-fuzzer)
6. [Style rules](#style-rules)
7. [Pull request rules](#pull-request-rules)

---

## Before you start

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Its
one project specific section is worth reading even if you have read the
Contributor Covenant a hundred times: this repository asks for evidence
rather than reasoning, so being told that a claim does not survive checking
is the project working, not an attack.

If you have found a security problem rather than a bug, stop here and read
[SECURITY.md](SECURITY.md). A tokenizer sits between untrusted input and a
model prompt, and a special token that encodes when it should have been
refused is prompt injection rather than a defect.

If you are not sure your change is wanted, [SUPPORT.md](SUPPORT.md) says
where to ask, and the deferred list in [docs/ROADMAP.md](docs/ROADMAP.md)
records what has already been decided against and why.

## Development setup

Knap targets macOS, Linux, and Windows under WSL. Mojo publishes no Windows
wheel, so there is no native Windows path. On Windows, install a WSL
distribution and work inside it.

The primary environment is `uv`:

```bash
git clone https://github.com/olaflaitinen/knap.git knap
cd knap
uv sync --group dev
```

The alternate environment is `pixi`, which pulls Mojo from the stable `max`
conda channel:

```bash
git clone https://github.com/olaflaitinen/knap.git knap
cd knap
pixi install
```

Both are kept working and both are tested. An install path that is documented
but never executed is an install path that is broken.

The compiler is pinned to Mojo 1.0.0 exactly. Do not float it and do not build
against nightly. Mojo guarantees source level stability only, and its ABI is
explicitly not stable.

Install the Mojo VS Code extension, `modular-mojotools.vscode-mojo`, so the
language server surfaces errors and API signatures while you work.

## Running the checks

These scripts enforce the repository standard. They run in CI on every push,
and you should run them before opening a pull request:

```bash
uv run python scripts/lint_style.py
uv run python scripts/check_file_banners.py
uv run python scripts/check_md_headers.py
uv run python scripts/check_spdx.py
uv run python scripts/check_toolchain_doc.py
uv run python scripts/check_generated.py
```

The last one covers the four generated files that are committed: the
pattern constants, the Unicode tables, `docs/API.md`, and `sbom.cdx.json`.
If it reports drift, run the generator it names rather than editing the file
it names.

Under pixi, the same set runs as one task:

```bash
pixi run standards
```

Each script also accepts explicit paths, which is much faster while iterating
on a single file:

```bash
uv run python scripts/lint_style.py src/knap/bpe.mojo
```

Formatting is not negotiable and not a house style. Run the canonical
formatter and commit what it produces:

```bash
uv run mojo format .
```

Note that `mojo format` has no check mode. CI formats in place and then
verifies that the working tree is unchanged, so an unformatted file fails the
build.

## Running the tests

Mojo 1.0.0 removed the `mojo test` subcommand. A test file is an ordinary
program whose `main` drives a `TestSuite`, so tests are run directly:

```bash
uv run mojo run -I src -I cli tests/test_toolchain.mojo
```

The suite is 19 files and 138 tests. Two of them, `tests/test_encode_corpus.mojo`
and `tests/test_pretokenize_corpus.mojo`, need the 110 MB corpus and run on a
schedule in `corpus.yml` rather than on every push. The rest run in a loop:

```bash
uv run python scripts/fetch_vocabs.py
for f in tests/*.mojo; do
  case "$f" in *_corpus.mojo) continue ;; esac
  uv run mojo run -I src -I cli "$f"
done
```

The examples are executed too, because nothing else in the repository runs
them and an example that is never run rots at the first signature change:

```bash
uv run mojo run -I src examples/budget.mojo 2048 LICENSE CODE_OF_CONDUCT.md
uv run mojo run -I src examples/chunker.mojo LICENSE 128 16
```

The pointer heavy paths must also pass under the address sanitizer:

```bash
uv run mojo build --sanitize address -I src -o /tmp/t tests/test_toolchain.mojo && /tmp/t
```

There is no thread sanitizer job, and the reason is worth knowing rather
than rediscovering: Mojo 1.0.0 has no working task parallelism, so there is
no multi threaded path to sanitize. See [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md).

A failure found under a sanitizer is a different and more urgent class of bug
than a plain failure, because a memory error can produce correct output on one
run and corruption on the next. Say which mode found it.

## Running the fuzzer

The differential fuzzer drives Knap and `tiktoken` in one process, which is
possible because Mojo installs as an ordinary Python package and both live in
the same environment. No subprocess boundary means no ambiguity about which
reference version produced a token list.

```bash
uv run python tests/fuzz/run_fuzz.py --total 1000000
uv run python tests/fuzz/run_fuzz.py --total 100000 --sanitize address
```

It takes every encoding, and the nightly job in `fuzz.yml` runs all seven at
ten million inputs each. The reports committed to this repository are the
narrower pair that the documents quote, and
`scripts/check_fuzz_claims.py` fails the build if prose quotes a figure the
committed reports do not contain. That is why widening a fuzzing claim means
committing the run that supports it, not editing the sentence.

Report every fuzz run with its seed and the exact `tiktoken` version. A run
without a seed cannot be reproduced and is not evidence. Any input that once
diverged is kept in `tests/fuzz/corpus_seeds/` as a regression seed, even
after the fix.

## Style rules

The full standard is [docs/STYLE.md](docs/STYLE.md). The rules most likely to
catch you out:

| Rule | Detail |
| --- | --- |
| No em-dash | Anywhere, including commit messages and error strings. |
| No emoji | Anywhere. |
| ASCII only | Except `LICENSE`, `tests/fixtures/`, LaTeX math spans, and raster artwork under `docs/assets/`. |
| No exclamation marks | In documentation prose. |
| Banner and closing marker | On every `.mojo` and `.py` file. The `File` field must match the real path. |
| Markdown header and footer | On every `.md` file except `README.md` and `.github/PULL_REQUEST_TEMPLATE.md`. |
| Metadata table | Twelve fields in a fixed order, ending `Licence` then `Website`. |
| No placeholders | Every committed file is complete and working, or it does not exist. |

If you need to write a banned character in code that must detect it, use a
code point escape such as `chr(0x2014)` rather than the character itself.

Comment density is generous by design, because Mojo is new and most readers
will not know it. But a comment that restates the code is worse than no
comment. Explain why, not what, except on SIMD, pointer, and bit manipulation
lines, where explaining exactly what is in each lane is the whole point.

## Pull request rules

| Rule | Reason |
| --- | --- |
| No performance change merges without the parity suite passing. | Optimising against an unverified baseline produces fast wrong answers. |
| Scalar paths are never deleted in favour of a SIMD path. | The scalar implementation is the reference the SIMD one is differentially tested against. |
| Any change to tokenizer output is a breaking change, even when the API is untouched. | Consumers pin token ids into caches, datasets, and evaluation results. Mark it clearly in `CHANGELOG.md`. |
| A negative result is worth keeping. | If a performance idea does not survive a benchmark, delete the code and record the result in `docs/BENCHMARKS.md`. |
| Prefer a smaller correct library over a larger fast one. | Correctness is the product. |
| A gate is not passed until it has been run and observed. | Reasoning that the code looks right does not pass a gate. |

Commit messages describe what became true, not which files changed. They are
subject to the character rules like everything else.

### What the branch protection actually enforces

`main` carries two rulesets, and the split between them is the whole design.

| Ruleset | Bypass |
| --- | --- |
| `main integrity, no bypass for anyone` | None. Not the maintainer, not anyone. |
| `main, bypassable by the maintainer` | Repository admin. |

| Rule | Ruleset | Effect |
| --- | --- | --- |
| Deletion blocked | Integrity | `main` cannot be deleted. |
| Force push blocked | Integrity | `main` cannot be rewritten, by anyone, including the maintainer. |
| Pull request required | Bypassable | Direct pushes to `main` are refused for everyone except the maintainer. |
| Status checks required | Bypassable | A pull request cannot merge until all eight jobs pass. |

The eight are `Repository standards`, `Build and test`, `Both classifier
builds agree`, `Python bindings`, `Mojo package builds and imports`,
`Command line tool`, `Address sanitizer, full suite`, and `Address sanitizer,
no interpreter present`. A required check is named by its **job** name rather
than by the workflow that contains it, which is easy to get wrong and quiet
when you do: one of these was originally listed under a name no job has, and
a check that does not exist can never report, so it would have blocked every
merge with no explanation. Renaming a job means updating this list.

`Unstable API inventory (reporting only)` is deliberately not required. It
measures rather than judges.

Extra approval for unattributed changes is switched off. It is on by default
and it means that a change GitHub cannot attribute to a known account, which
includes every Dependabot commit, needs an approval on top of the normal
requirement. With one maintainer and no required approvals there is nobody to
give it, so every dependency update would need an administrator bypass. That
would make bypassing routine, and a bypass that is routine is not a bypass,
it is the default with extra steps.

Approvals are not required, and that is deliberate rather than an oversight.
There is one maintainer, GitHub does not let anyone approve their own pull
request, and a rule requiring approval would leave every pull request from
the maintainer permanently unmergeable. `.github/CODEOWNERS` exists so that
the requirement can be turned on the moment there is a second reviewer.

Two rulesets rather than one, because a bypass in GitHub applies to a whole
ruleset rather than to a rule. Putting all four rules in one bypassable set
would have exempted the maintainer from the force push block as well, which
is exactly backwards: in a single maintainer repository the realistic
accident is a stray `--force`, not a malicious push, and the person most
likely to make it is the person the bypass would exempt.

So the split is: convenience where a mistake is cheap and recoverable,
no exception at all where it is neither.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |
| Next | [AUTHORS.md](AUTHORS.md) |
| Index | [README.md](README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-11 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: CONTRIBUTING.md -->
