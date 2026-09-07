<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Summary

Describe what became true, not which files changed.

## Does this change tokenizer output

- [ ] No, output is byte for byte identical.
- [ ] Yes. **This is a breaking change**, even if the public API is untouched,
      and it is marked as such in `CHANGELOG.md`.

Consumers pin token ids into caches, datasets, and evaluation results, so an
output change breaks them as thoroughly as a changed signature would.

## Gates

Tick only what you have actually run and observed. Reasoning that the code
looks right does not pass a gate.

- [ ] `python scripts/lint_style.py`
- [ ] `python scripts/check_file_banners.py`
- [ ] `python scripts/check_md_headers.py`
- [ ] `python scripts/check_spdx.py`
- [ ] `mojo format .` leaves the working tree unchanged
- [ ] `mojo doc --Werror --diagnose-missing-doc-strings` is clean
- [ ] Every test file runs green with `mojo run`
- [ ] The suite passes under `mojo build --sanitize address`

## If this is a performance change

- [ ] The parity suite passes. No performance change merges without it,
      because optimising against an unverified baseline produces fast wrong
      answers.
- [ ] The scalar reference path is still present. Scalar paths are never
      deleted in favour of a SIMD path.
- [ ] Benchmark numbers were produced by `bench/run_all.sh` on one machine,
      with the effective target recorded.
- [ ] If a baseline wins, it is published in the same table with the same
      prominence.
- [ ] If the idea did not survive its benchmark, the code is deleted and the
      negative result is recorded in `docs/BENCHMARKS.md`.

## Documentation

- [ ] `docs/CORRECTNESS.md` updated if parity evidence changed.
- [ ] `docs/ROADMAP.md` updated if something was deferred, with the reason.
- [ ] `CHANGELOG.md` entry added.
- [ ] No placeholders. Every file added is complete and working, or absent.
