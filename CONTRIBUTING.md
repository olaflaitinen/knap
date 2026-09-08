<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Contributing to Knap

| Field | Value |
| --- | --- |
| Document | `CONTRIBUTING.md` |
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

1. [Development setup](#development-setup)
2. [Running the checks](#running-the-checks)
3. [Running the tests](#running-the-tests)
4. [Running the fuzzer](#running-the-fuzzer)
5. [Style rules](#style-rules)
6. [Pull request rules](#pull-request-rules)

---

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

Four scripts enforce the repository standard. They run in CI on every push,
and you should run them before opening a pull request:

```bash
uv run python scripts/lint_style.py
uv run python scripts/check_file_banners.py
uv run python scripts/check_md_headers.py
uv run python scripts/check_spdx.py
```

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
uv run mojo run tests/test_toolchain.mojo
```

The pointer heavy paths must also pass under the address sanitizer, and the
parallel batch encode paths under the thread sanitizer:

```bash
uv run mojo build --sanitize address -o /tmp/t tests/test_toolchain.mojo && /tmp/t
```

A failure found under a sanitizer is a different and more urgent class of bug
than a plain failure, because a memory error can produce correct output on one
run and corruption on the next. Say which mode found it.

## Running the fuzzer

The differential fuzzer arrives at M4 and is not yet present. When it lands it
will drive Knap and `tiktoken` in one process, which is possible because Mojo
installs as an ordinary Python package and both live in the same environment.

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
| ASCII only | Except `LICENSE`, `tests/fixtures/`, and LaTeX math spans. |
| No exclamation marks | In documentation prose. |
| Banner and closing marker | On every `.mojo` and `.py` file. The `File` field must match the real path. |
| Markdown header and footer | On every `.md` file except `README.md`. |
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

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |
| Next | [AUTHORS.md](AUTHORS.md) |
| Index | [README.md](README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-07 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](LICENSE) for the full terms.

<!-- End of document: CONTRIBUTING.md -->
