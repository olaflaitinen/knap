<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Summary

Describe what became true, not which files changed. The diff already says
which files changed.

<!-- Two or three sentences. What can a caller now do, or rely on, that they
     could not before. If this is a fix, what was wrong. -->

## What kind of change is this

Tick every one that applies.

- [ ] Bug fix, no change to tokenizer output
- [ ] Bug fix that corrects tokenizer output
- [ ] New capability
- [ ] Performance change
- [ ] Refactoring with no behavioural change
- [ ] Documentation only
- [ ] Test or fixture only
- [ ] Build, packaging, or continuous integration
- [ ] Dependency change
- [ ] Revert of an earlier change
- [ ] Something else, described above

## Does this change tokenizer output

- [ ] No, output is byte for byte identical.
- [ ] Yes. **This is a breaking change**, even if the public API is untouched,
      and it is marked as such in `CHANGELOG.md`.
- [ ] Only for input that previously raised an error.
- [ ] Only when a new opt in flag or entry point is used.

Consumers pin token ids into caches, datasets, and evaluation results, so an
output change breaks them as thoroughly as a changed signature would.

If output changes, say which inputs change, how many token ids differ across
the 110 MB corpus, and which of the two encodings are affected:

<!-- Answer here. -->

## Evidence

State what you ran and what you observed. **A gate is not passed until its
condition has actually been run and observed. Reasoning that the code looks
right does not pass a gate**, and neither does a tick added in anticipation.

### Standards gates

- [ ] `python scripts/lint_style.py`
- [ ] `python scripts/check_file_banners.py`
- [ ] `python scripts/check_md_headers.py`
- [ ] `python scripts/check_spdx.py`
- [ ] `python scripts/check_generated.py`
- [ ] `python scripts/selftest_gates.py`
- [ ] `mojo format .` leaves the working tree unchanged
- [ ] `mojo doc --Werror --diagnose-missing-doc-strings` is clean

### Tests

- [ ] Every test file runs green with `mojo run -I src`
- [ ] Every test file runs green with `--Werror`
- [ ] Every test file runs green with `-D KNAP_SIMD=1`
- [ ] The suite passes under `mojo build --sanitize address`
- [ ] `tests/test_pretokenize_corpus.mojo` passes over the 110 MB corpus
- [ ] `tests/test_encode_corpus.mojo` passes over the 110 MB corpus
- [ ] `python bindings/python/build.py`, then the binding tests

### Fuzzing

Required whenever anything on the encode path changed, including the
scanner, the classifier, the merge loop, the rank table, or the cache. The
corpus is natural language and the fuzzer is not, and the one real divergence
class this project has had was found by the fuzzer on input no corpus would
contain.

- [ ] `python tests/fuzz/run_fuzz.py` completed with zero divergences
- [ ] `python tests/fuzz/run_fuzz.py --sanitize address` completed
- [ ] `tests/fuzz/asan_solo.mojo` ran clean with no suppression file
- [ ] Not applicable, nothing on the encode path changed

Totals and seeds, copied from `tests/fuzz/last_run.json`:

<!-- For example: 10000000 per encoding, base seed 20260908, zero
     divergences, tiktoken 0.14.0. -->

## If this is a performance change

- [ ] The parity suite passes. No performance change merges without it,
      because optimising against an unverified baseline produces fast wrong
      answers.
- [ ] The scalar reference path is still present. Scalar paths are never
      deleted in favour of a vectorised one.
- [ ] Numbers were produced by `bench/run_all.sh` on one machine, in one
      session, with the effective build target recorded.
- [ ] The machine was idle, and the coefficient of variation is reported.
- [ ] The measurement is on prose rather than on the corpus's generated
      hazard section. A prefix of the corpus is not prose, and measuring one
      has already produced two wrong claims in this project.
- [ ] Every baseline was re-run in the same session rather than compared
      against a remembered number.
- [ ] If a baseline wins, it is published in the same table with the same
      prominence.
- [ ] If the idea did not survive its benchmark, the negative result is
      recorded in `docs/BENCHMARKS.md` rather than quietly dropped.
- [ ] `docs/BENCHMARKS.md` is updated, including any figure this change
      invalidates elsewhere in the repository.

Before and after, with the spread:

<!-- For example: cl100k_base encode, 1.79 MB/s cv 0.11 before, 3.44 MB/s
     cv 0.11 after, five iterations, 4194296 bytes at corpus offset
     30408704. -->

## If this changes a public interface

- [ ] The change is additive.
- [ ] The change is breaking, and `CHANGELOG.md` says so under Changed or
      Removed.
- [ ] Docstrings updated, including their `Raises:` sections.
- [ ] `bindings/python/README.md` updated if the exported surface moved.
- [ ] Not applicable.

## Documentation

- [ ] `docs/CORRECTNESS.md` updated if parity evidence changed.
- [ ] `docs/BENCHMARKS.md` updated if any number changed.
- [ ] `docs/ARCHITECTURE.md` updated if a design decision or a toolchain
      finding changed.
- [ ] `docs/ROADMAP.md` updated if something was deferred or completed, with
      the reason.
- [ ] `docs/UNICODE.md` updated if the tables or their source version moved.
- [ ] `THIRD_PARTY_NOTICES.md` updated if a dependency or reference changed.
- [ ] `CHANGELOG.md` entry added.
- [ ] Every new file carries the banner and the closing marker required by
      `docs/STYLE.md`.
- [ ] No placeholders. Every file added is complete and working, or absent.
- [ ] ASCII only, no em dash and no emoji, outside the three documented
      exemptions.

## What you decided not to do

<!-- Anything you considered and rejected, and why. This is the most useful
     part of a description six months later, and the part that is always
     missing. -->

## What you are unsure about

<!-- Say it here rather than hoping review catches it. A stated doubt is
     cheap. An unstated one that turns out to be right is not. -->

## Risk

- [ ] Low. Isolated, well covered by existing tests.
- [ ] Medium. Touches a shared path, but the parity gates cover it.
- [ ] High. Touches the encode path, the refusal logic, or generated data.
- [ ] Unknown, explained above.

## Related issues

<!-- Closes #, Refs #, or none. -->
