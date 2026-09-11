<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Methodology

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="assets/knap_logo_transparent_white.svg">
    <img src="assets/knap_logo_transparent_black.svg"
         alt="Knap" width="240">
  </picture>
</p>

| Field | Value |
| --- | --- |
| Document | `docs/METHODOLOGY.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Stable |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-10 |
| Updated | 2026-09-11 |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |

---

## Contents

1. [The claim this document supports](#the-claim-this-document-supports)
2. [The one rule](#the-one-rule)
3. [Correctness first, and why the order matters](#correctness-first-and-why-the-order-matters)
4. [Measuring time without fooling yourself](#measuring-time-without-fooling-yourself)
5. [Measuring memory, which almost nobody does](#measuring-memory-which-almost-nobody-does)
6. [Predictions, written down before they are tested](#predictions-written-down-before-they-are-tested)
7. [Gates that check the gates](#gates-that-check-the-gates)
8. [Four times this process caught something](#four-times-this-process-caught-something)
9. [What it costs](#what-it-costs)
10. [Applying this elsewhere](#applying-this-elsewhere)

---

## The claim this document supports

Knap publishes numbers. It says it encodes faster than the reference
implementation on three of four distinct encode behaviours, that it decodes
about 2.7 times faster, and that it holds a loaded encoding in between 4.4
and 11.7 times less memory. Those are the kind of claims a reader is right
to distrust, because most of them are wrong most of the time, and the usual
reason is not dishonesty. It is that measuring a tokenizer is easy to do
badly and the bad measurement looks exactly like the good one.

This document is the method behind the numbers in
[docs/BENCHMARKS.md](BENCHMARKS.md) and the correctness claims in
[docs/CORRECTNESS.md](CORRECTNESS.md). It is written to be reused. Nothing in
it is specific to tokenization, and most of it is not specific to Mojo.

---

## The one rule

**A gate is not passed until its condition has been run and observed.**

Everything else here follows from that sentence. It sounds like a truism and
it is not, because the ordinary way software gets built violates it
constantly and invisibly. A check is written, the build goes green, and
nobody ever establishes that the check would have gone red. A benchmark is
run once, the number is copied into a document, and the code underneath it
changes four times.

The rule has two practical consequences that are worth stating separately.

**A claim carries its evidence.** The verification record in
[docs/ROADMAP.md](ROADMAP.md) is a set of tables of conditions, and each
condition names the file, the test, or the run that satisfies it. A
condition whose evidence column says "by inspection" is not satisfied.

**An unobserved gate is treated as a broken gate.** `scripts/selftest_gates.py`
plants a specific violation for each standards gate, asserts the gate rejects
it, then feeds the gate a clean control and asserts it accepts that. Both
halves matter: a gate that rejects everything is exactly as useless as one
that rejects nothing, and only the second half catches it.

---

## Correctness first, and why the order matters

Knap reached byte identical parity with the reference implementation before
a single line was written for speed. That ordering is not tidiness. It is
what makes optimisation possible at all.

An optimisation is a change that is supposed to preserve behaviour. Without
a gate that can refuse a change, there is no way to distinguish a fast
implementation from a wrong one, and the person making the change is the
last person able to tell the difference. With the parity gate in place, every
one of the four changes in the merge loop was checked against 191,762,320
tokens over a 110 MB corpus, after each change rather than once at the end.
Three of the four survived unmodified. The fourth was kept with its ambiguity
recorded, because the machine could not resolve whether it helped.

Parity itself rests on three independent mechanisms, which is deliberate:
each of the three fails in a way the others do not.

| Mechanism | What it covers | What it misses |
| --- | --- | --- |
| Golden fixtures, generated from the reference and committed | Exact expected output for inputs chosen to be adversarial: control characters, lone surrogates, contractions, scripts without spaces | Only the inputs somebody thought of |
| A corpus parity run, every token compared | Real text at volume, across all seven encodings and all four distinct encode behaviours | Only text that occurs in the corpus |
| Differential fuzzing against the reference in one process | Inputs nobody would think of, at a rate no human can review | Only what the generator can produce |

The fuzzer runs the reference implementation in the same process rather than
through a subprocess, so there is no ambiguity about which version produced
a reference token list, and every shard's seed is written into the report.
A fuzzing claim of the form "twenty million inputs, zero divergences" is
worth nothing unless a reader can run the same twenty million inputs, so
the seeds are part of the claim. `scripts/check_fuzz_claims.py` refuses a
document that quotes a number the report does not contain, which is also
what keeps the claim narrow: the committed report covers two encodings, so
the documents say two encodings.

Any input that ever diverged is kept in `tests/fuzz/corpus_seeds/`
permanently, after the bug is fixed. A generator eventually stops producing
a given shape; the case that once failed keeps being checked.

---

## Measuring time without fooling yourself

The single most useful thing to know about a benchmark machine is its noise
floor, and it is the thing least often reported. On the machine these
figures come from, the run to run spread is around five percent. That has a
blunt consequence: **any effect below about ten percent cannot be measured
by running A, then running B, and comparing the two numbers.** The difference
between the two runs is mostly the machine's mood.

The answer is a paired measurement. Two binaries built from the same tree,
run alternately in a single session, and the difference taken per pair
rather than between two averages. The allocation result in
[docs/BENCHMARKS.md](BENCHMARKS.md) was invisible under the naive method and
briefly appeared negative; paired, it is a clean effect.

Five other rules the suite follows, each of which exists because it was
needed:

- **One machine, one session, every implementation.** Baselines are re-run in
  the same session as the thing they are compared against, never quoted from
  an earlier run. A comparison against a number from someone else's hardware
  is not a comparison.
- **The same bytes.** The Mojo harness and the Python baselines read the
  corpus through the same slicing rule, and the runner refuses to start if
  the two implementations of that rule disagree. This is checked rather than
  assumed because the two were written months apart.
- **Start up excluded.** Reading the corpus, loading the vocabulary and
  building the rank table are paid once. Timing them understates the steady
  state a caller experiences.
- **A warm up iteration before every measurement**, untimed, so the first
  pass does not charge page faults to the code under test.
- **An idle machine, verified after the fact.** An earlier run of the suite
  was taken while a fuzzing job held the cores, and came back with a
  coefficient of variation above 0.2, which is larger than most of the
  effects it was measuring. Those numbers were discarded rather than
  published. The coefficient of variation is reported for every figure so a
  reader can apply the same test.

---

## Measuring memory, which almost nobody does

Throughput is the number every tokenizer publishes. Peak resident memory is
the number that decides whether a service fits in its container, and it is
almost never reported by anyone.

Measuring it correctly requires one idea: **one thing per process.** Peak
resident memory is a high water mark, so a process that does two things
reports the larger of them and attributes it to both. The measurement here
spawns a separate child process per stage, reads its peak through the
operating system's own accounting when it exits, and walks a ladder: an
empty runtime, then reading a file, then loading a vocabulary, then building
a tokenizer, then counting, then encoding. Each rung's cost is the difference
from the rung below.

The empty runtime is reported every time. It is the control, and without it
every figure in the table is an unknown constant plus the thing being
measured. It is also what caught the worst error this project made, which is
described below.

---

## Predictions, written down before they are tested

Before a change is made, the expected result is written down. Afterwards the
outcome is published next to it, including when the prediction was wrong.

This is the cheapest discipline in the whole document and the one with the
best return, because it converts a wasted afternoon into a permanent result.
Three predictions this project recorded and then refuted:

| Prediction | Outcome |
| --- | --- |
| Counting tokens without building the list of ids would be faster than encoding | It is not. It saves a great deal of memory and no measurable time. Published next to the counting figures rather than dropped. |
| The tail latency at the 99th percentile is caused by allocation spikes | It is not. With the per piece allocation removed, the percentiles do not move. A second hypothesis, that it was hash lookups in the merge loop, was eliminated the same way. The cause is now an open question rather than a third guess. |
| A pure ASCII fast path for whole documents would pay | It would not. Only 45.5 percent of lines in the corpus are pure ASCII, so the branch would be taken on barely half the input and would have to be paid for on all of it. Rejected before being written, on a measurement rather than an intuition. |

The last of those is the pattern worth copying. The cheapest optimisation is
the one that gets measured out of existence before anybody implements it.

---

## Gates that check the gates

The most dangerous failure in a project run this way is not a gate that
fails. It is a gate that passes for the wrong reason, because it produces
exactly the same green output as a gate that works.

Two real examples from this repository.

**A drift check that compared files against themselves.** Continuous
integration ran the generators for the committed generated files, and then
ran the check that those committed files were current. Since the generators
had just written them, the check compared each file against what had been
produced seconds earlier and always passed. A hand edit to a generated file
survived three consecutive runs. The first attempt at a fix removed the
generators from the job and broke the test suite, because one generator also
writes a fixture the tests read. The correct fix was ordering: run the check
before the generators, not instead of them.

**An assertion that was true by construction.** A decode test asserted that
each encoding's id space contains at least one unassigned rank. For three of
the seven encodings that is a real property. For the other four it is
vacuously satisfied by an id space with no holes at all, so the assertion
could never fail for them and was checking nothing. It was replaced with the
exact expected hole count per encoding, which is a claim that can be wrong.

The general form: **ask what input would make this check fail.** If the
answer is hard to construct, the check is probably not checking. Where the
answer is easy to construct, construct it, and keep it. That is what the
gate self test does, and it is why `scripts/check_recipe.py` ships a
`--selftest` mode that plants seven distinct violations rather than merely
running clean.

---

## Four times this process caught something

Method is worth what it catches. Four cases, each of which would otherwise
have shipped.

**A memory claim that was wrong by an order of magnitude.** The first
version of the memory measurement reported 290 MB for Knap and would have
published the claim that Knap uses six times what the reference does. The
290 MB was the benchmark harness reading the entire corpus into memory
before the tokenizer was even built. The control and the per stage split are
what separated the harness from the thing being measured. The corrected
figures run from 3.1 MB to 18.4 MB, and the harness itself was then fixed to
seek rather than read, which took its own peak from 282.8 MB to 95.6 MB.

**A defect that two encodings could not expose.** Adding the five remaining
encodings surfaced a bug in code that had passed every gate for two of them:
a special token whose id sits on a rank that the merge table leaves
unassigned could not be decoded, because the code tested a range instead of
testing assignment. Nothing about the algorithm was wrong. The assumption
was.

**A test that agreed with itself.** A test asserted that two encodings
produce different output on a sample of plain English. They do not. The
sample was not discriminating, and the honest fix was to find an input where
the two genuinely differ, which turned out to be indentation, rather than to
weaken the assertion until it passed.

**A deprecation that only one build mode reported.** Three pointer spellings
used in the hash table are deprecated in the pinned compiler. All three run
correctly and only `--Werror` refuses them, so a deprecated spelling passes
a run and fails a build. The finding is recorded in
[docs/TOOLCHAIN.md](TOOLCHAIN.md) with the working spelling next to it.

---

## What it costs

It would be dishonest to present this as free.

The parity corpus run takes several minutes and has to be re-run after every
change to the encode path. The paired benchmark method requires building and
keeping two binaries and running them alternately, which roughly triples the
time to answer a question about a small optimisation. Writing a prediction
down before testing it feels like ceremony every single time. The gate self
test is a piece of software whose only purpose is to make other software
fail.

Against that: every claim in this repository has an execution behind it, the
four defects above were caught before release rather than by a user, and
three optimisations were rejected on measurement before anyone spent a day
implementing them. On this project the method has been cheaper than the
alternative, and the balance would be similar for anything whose output is
compared byte for byte against a reference.

The place it would not pay is a project without a reference implementation to
be correct against. Half of what is described here depends on there being a
second implementation to disagree with.

---

## Applying this elsewhere

Reduced to the smallest set that still works:

1. Establish correctness against something external before optimising
   anything, and make it a gate that can refuse a change.
2. Measure the noise floor of the machine before believing any effect, and
   pair the measurement for anything smaller than twice that floor.
3. Report a control alongside every absolute figure.
4. Write the prediction down first, and publish it when it is refuted.
5. For every check, construct the input that makes it fail. If that is hard,
   the check is not checking.
6. Keep the record of having been wrong. It is the only part of a claim a
   reader cannot verify for themselves and the only part that makes the rest
   credible.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/TOOLCHAIN.md](TOOLCHAIN.md) |
| Next | [docs/BENCHMARKS.md](BENCHMARKS.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-11 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/METHODOLOGY.md -->
