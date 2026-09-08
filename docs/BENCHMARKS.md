<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Benchmarks

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
| Document | `docs/BENCHMARKS.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 0.1.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-08 |
| Updated | 2026-09-08 |
| Licence | EUPL-1.2 |

---

## Contents

1. [The short version](#the-short-version)
2. [The machine](#the-machine)
3. [What is measured, and how](#what-is-measured-and-how)
4. [Encode throughput](#encode-throughput)
5. [What the allocation cost](#what-the-allocation-cost)
6. [The piece cache](#the-piece-cache)
7. [The vectorised classifier](#the-vectorised-classifier)
8. [Short string latency](#short-string-latency)
9. [Batch encoding](#batch-encoding)
10. [Decode](#decode)
11. [What these numbers do not mean](#what-these-numbers-do-not-mean)
12. [Reproducing this](#reproducing-this)

---

## The short version

**Knap is slower than both Rust baselines at encoding, on this machine and
this corpus.** That is the headline, it is stated first, and it was the
expected result before anything was measured.

| Implementation | `cl100k_base` | `o200k_base` |
| --- | --- | --- |
| `rs-bpe` | 10.66 MB/s | 10.02 MB/s |
| `tiktoken` | 5.81 MB/s | 8.74 MB/s |
| **Knap** | **3.44 MB/s** | **3.21 MB/s** |
| Hugging Face `tokenizers` | 0.70 MB/s, approximate | not run |

Three secondary results, each of which is a measurement rather than a claim:

- Removing one allocation from the rank lookup nearly doubled encode
  throughput. See [What the allocation cost](#what-the-allocation-cost).
- The optional piece cache roughly doubles throughput on a workload that
  reuses it across documents, at a cost of about nine megabytes.
- The vectorised classifier cannot be distinguished from the scalar one on
  this machine. It is off by default for that reason, which is a weaker and
  more accurate statement than the one this document used to make.

## The machine

Every figure here comes from one machine, in one session. It is a laptop,
and a modest one, which matters for how the numbers should be read.

| Property | Value |
| --- | --- |
| CPU | AMD Ryzen 5 3500U with Radeon Vega Mobile Gfx |
| Logical cores | 8 |
| Memory | 2949352 kB available to the guest |
| Kernel | Linux 6.6.87.2-microsoft-standard-WSL2 |
| Target triple | `x86_64-unknown-linux-gnu` |
| Target CPU | `znver1`, with AVX2 and without AVX-512 |
| Mojo | 1.0.0, build `ed45d567` |
| Python | 3.12.3 |
| `tiktoken` | 0.14.0 |
| `tokenizers` | 0.23.2 |
| `rs-bpe` | 0.1.0 |

The input is 4194296 bytes of prose taken from the mixed corpus at byte
offset 30408704, which is past the corpus's generated hazard section. The
corpus is 115343371 bytes with SHA-256
`cbcf49647ddbf333590224687d095b3cbafba06a9dec6971adac781310203fb9`.

That offset is not incidental. See
[What these numbers do not mean](#what-these-numbers-do-not-mean).

## What is measured, and how

Every figure in this document comes from `bench/run_all.sh` on the machine
described above. Nothing is copied from another project's README, and
nothing is remembered from an earlier run.

### The quantities

For $n$ timed iterations with durations $t_1 \dots t_n$ in nanoseconds, the
harness reports the sample mean

$$\mu = \frac{1}{n}\sum_{i=1}^{n} t_i$$

the sample standard deviation, with the $n - 1$ denominator because these
are a sample of the machine's behaviour rather than its whole population,

$$\sigma = \sqrt{\frac{1}{n-1}\sum_{i=1}^{n}\left(t_i - \mu\right)^2}$$

and the coefficient of variation

$$c_v = \frac{\sigma}{\mu}$$

which is the number to read first. It is dimensionless, so it compares
across measurements of very different sizes, and it says whether a
difference being claimed is larger than the noise it was measured in.

Throughput is derived from the mean rather than from the best run:

$$T_{\text{bytes}} = \frac{B}{\mu}, \qquad
T_{\text{tokens}} = \frac{N}{\mu}$$

for $B$ input bytes and $N$ tokens produced. The best run is the machine's
luckiest moment and nobody's experience of the library.

The compression ratio is reported alongside, because a tokenizer that emits
fewer tokens per byte does more work per token, and a bytes per second
figure alone hides that:

$$r = \frac{B}{N}$$

Latency percentiles use the nearest-rank definition. For a sorted sample
$t_{(1)} \le \dots \le t_{(n)}$ and a fraction $p$, the reported value is

$$P_p = t_{(\lceil p\,n \rceil)}$$

so a reported percentile is always an observation that actually happened,
never an interpolation between two that did not.

### Rules the suite follows

- **One machine, one session, all implementations.** Every baseline is run
  by the author on the machine above, against the same bytes. A comparison
  against a number from someone else's hardware is not a comparison.
- **The same input.** The Mojo benchmarks and the Python baselines read the
  corpus through the same slicing rule, and `run_all.sh` refuses to start if
  the two copies of the offset disagree.
- **Start up excluded.** Reading the corpus, loading the vocabulary, and
  building the rank table are start up costs paid once. Timing them would
  understate the steady state a caller actually experiences.
- **Pre-tokenization and merging together.** Splitting the encode timing in
  two would produce a faster looking number for each half that nobody could
  act on.
- **A warm up iteration before every measurement**, untimed, so the first
  pass does not charge page faults to the tokenizer.
- **An idle machine.** An earlier run of this suite was taken while a
  fuzzing job held the cores and came back with $c_v$ above 0.2, large
  enough that the differences it was measuring were smaller than its noise.
  Those numbers were discarded rather than published.

## Encode throughput

Five timed iterations of 4194296 bytes, per implementation, per encoding.

### `cl100k_base`

| Implementation | MB/s | Tokens/s | $c_v$ | Bytes per token |
| --- | --- | --- | --- | --- |
| `rs-bpe` | 10.66 | 3259482 | 0.124 | 3.4295 |
| `tiktoken` | 5.81 | 1775781 | 0.058 | 3.4295 |
| Knap | 3.44 | 1051002 | 0.110 | 3.4295 |
| Knap, piece cache shared across documents | 8.01 | 2429008 | 0.455 | 3.4574 |
| Hugging Face `tokenizers` | 0.70 | 341813 | 0.091 | 2.1523 |

### `o200k_base`

| Implementation | MB/s | Tokens/s | $c_v$ | Bytes per token |
| --- | --- | --- | --- | --- |
| `rs-bpe` | 10.02 | 2734784 | 0.051 | 3.8416 |
| `tiktoken` | 8.74 | 2385771 | 0.021 | 3.8416 |
| Knap | 3.21 | 877040 | 0.047 | 3.8416 |
| Knap, piece cache shared across documents | 7.32 | 1890985 | 0.493 | 4.0581 |

### Reading these

`rs-bpe` and `tiktoken` produce token for token identical output to Knap on
this input, which is what makes the comparison meaningful. The `rs-bpe`
harness asserts it on every run and reports `note=identical_to_tiktoken`.

The Hugging Face row does not. Its compression ratio is 2.15 bytes per token
against 3.43 for the other three, which is the signature of a different
vocabulary rather than of a different implementation of the same one. It is
reported as `note=approximate` and it should not be read as a like for like
comparison. It is included because leaving out the slowest baseline would be
as dishonest as leaving out the fastest.

The cached rows carry a high $c_v$ by construction rather than from machine
noise. Each of their timed iterations encodes a different document and the
cache is warming across them, so the spread is the warm up curve. See
[The piece cache](#the-piece-cache).

**Knap is between 1.7 and 2.7 times slower than `tiktoken` and about 3.1
times slower than `rs-bpe`.** With the piece cache in a workload that reuses
it, Knap sits between the two. Without it, Knap is last of the three exact
implementations.

## What the allocation cost

The largest single performance result in this project came from deleting one
allocation, and it is recorded here because the way it was found matters
more than the number.

The rank table was a `Dict[String, Int]`. A `String` key owns its bytes, so
every lookup copied the byte range being asked about into a fresh
allocation before anything was compared. The merge loop is quadratic in the
piece length, so a five byte piece paid ten allocations to ask ten questions
about bytes the caller already held.

| Encoding | Before, `Dict[String, Int]` | After, byte keyed map | Ratio |
| --- | --- | --- | --- |
| `cl100k_base` | 1.79 MB/s | 3.44 MB/s | 1.92 |
| `o200k_base` | 1.90 MB/s | 3.21 MB/s | 1.69 |

The 110 MB encode parity gate fell from 208.5 seconds to 105.8 seconds over
the same 80.5 million tokens, with byte identical output.

**This was invisible until the benchmark corpus was fixed.** Every earlier
run measured a prefix of the mixed corpus, which is a generated hazard
section: its first two megabytes contain 205 distinct whitespace separated
words, and its pieces are about two bytes long, so the quadratic term barely
engages and the allocation barely shows. On prose, where pieces run four to
six bytes, it dominated.

The merge loop itself is unchanged and is still quadratic in the piece
length. That is deliberate. It is a clear and obviously correct algorithm,
removing an allocation is a far smaller claim than replacing it, and if the
quadratic term ever becomes the cost there will be a number saying so.

## The piece cache

The cache is optional, owned by the caller, and off unless asked for. It maps
a pre-token's bytes to the ids it encodes to, so a piece seen twice is merged
once.

Four measurements, because one would mislead. The input is divided into five
documents of 838859 bytes each.

### `cl100k_base`

| Measurement | MB/s | $c_v$ | Hit rate | Entries | Bytes held |
| --- | --- | --- | --- | --- | --- |
| Uncached | 3.56 | 0.103 | not applicable | 0 | 0 |
| Cold cache, fresh per document | 4.54 | 0.316 | 0.839 | 26616 | 5824003 |
| Shared cache, across new documents | 8.01 | 0.455 | 0.927 | 77633 | 8901142 |
| One document repeated, an upper bound | 18.70 | 0.044 | 0.977 | 25235 | 5593405 |

### `o200k_base`

| Measurement | MB/s | $c_v$ | Hit rate | Entries | Bytes held |
| --- | --- | --- | --- | --- | --- |
| Uncached | 3.33 | 0.127 | not applicable | 0 | 0 |
| Cold cache, fresh per document | 5.71 | 0.261 | 0.839 | 26673 | 5707610 |
| Shared cache, across new documents | 7.32 | 0.493 | 0.927 | 77705 | 8668502 |
| One document repeated, an upper bound | 17.54 | 0.007 | 0.977 | 25235 | 5555043 |

### Which row to believe

**The shared cache row.** It is the only one that describes a process
encoding documents it has not seen before, which is what a long running
service does.

The last row is included and labelled as a bound because it is what a
benchmark reports when it re-encodes the same document, and this benchmark
used to do exactly that and call it the service case. It is not. A cache
that answers 97.7 percent of lookups from text it has already seen tells you
about the benchmark, not about the workload.

The high $c_v$ on the two middle rows is signal rather than noise. Each
timed iteration encodes a different document, and for the shared cache the
table is filling as it goes, so successive samples are genuinely not drawn
from the same distribution. The first document of a shared cache run pays
nearly the cold price and the fifth pays nearly none.

The memory column exists because a throughput gain bought with an unbounded
table is a deferred problem rather than a gain. Nine megabytes for four
megabytes of text is a real cost, and it is why the cache is off by default
and why its capacity is the caller's decision.

## The vectorised classifier

This is a negative result, and it is not the negative result this document
previously reported.

The classifier assigns a byte class to each input byte, and a vectorised
version processes 32 bytes per iteration on this target. The cost model in
[docs/ARCHITECTURE.md](ARCHITECTURE.md) predicted it would lose, because it
is handed a pre-token rather than a document and pre-tokens average about
four bytes, so a 32 lane vector can rarely advance.

Measured over five repetitions of the pre-tokenization benchmark, which is
the stage the classifier actually affects:

| Classifier | `cl100k_base` MB/s | `o200k_base` MB/s |
| --- | --- | --- |
| Scalar, the default | 19.25, $\sigma$ 2.20, $c_v$ 0.114 | 14.36, $\sigma$ 2.21, $c_v$ 0.154 |
| Vectorised, `-D KNAP_SIMD=1` | 19.91, $\sigma$ 1.14, $c_v$ 0.057 | 14.72, $\sigma$ 1.44, $c_v$ 0.098 |

**The two are indistinguishable.** The vectorised path is nominally 3.4 and
2.5 percent faster, which is well inside one standard deviation of either
measurement, and single runs of the same benchmark have put it as much as 29
percent behind and 15 percent ahead. The honest reading is that this machine
cannot resolve the difference.

That correction is worth stating plainly, because earlier versions of this
project asserted specific losses of 5 to 7 percent, and of 52 percent for
`o200k_base`. Both came from the hazard section of the corpus, before the
slicing bug was found. Both were wrong. A confident number from a bad
measurement is worse than no number, and it survived several documents
before anyone re-ran it.

The classifier stays off by default. Not because it lost, but because it
cannot be shown to have won, and an unmeasurable gain does not justify a
second implementation of a load bearing function. It stays compiled and
tested rather than deleted, because
`tests/test_classifier_parity.mojo` holds it to the scalar one and because a
machine with a longer vector, or a corpus with longer pieces, would be
measuring something different.

## Short string latency

Two thousand samples per size class, nearest-rank percentiles, nanoseconds.

| Size class | Implementation | p50 | p90 | p99 | Mean | $c_v$ |
| --- | --- | --- | --- | --- | --- | --- |
| About 10 tokens | `tiktoken` | 5561 | 6893 | 8577 | 5768 | 0.410 |
| About 10 tokens | Knap | 8136 | 21120 | 28354 | 10978 | 0.608 |
| About 50 tokens | `tiktoken` | 19928 | 23385 | 43322 | 20598 | 0.232 |
| About 50 tokens | Knap | 30438 | 145227 | 203007 | 56122 | 0.926 |
| About 200 tokens | `tiktoken` | 70514 | 95943 | 160526 | 76216 | 0.272 |
| About 200 tokens | Knap | 112524 | 478302 | 625793 | 200037 | 0.888 |

**Knap loses on latency and loses worse in the tail than at the median.**
The median is 1.5 to 1.6 times the reference across all three classes, which
tracks the throughput result. The 99th percentile is 3.3 to 4.7 times the
reference, which does not.

That gap between median and tail is the interesting part and it is not
explained here, because it has not been investigated. The candidates are
allocation in the output buffer, which grows without a size hint, and the
merge loop's boundary list, which is allocated per piece. Neither has been
profiled. Recording the question is more useful than guessing at it.

## Batch encoding

Two thousand documents of 2048 bytes each, encoded in sequence.

| Measurement | Value |
| --- | --- |
| Throughput | 3.26 MB/s |
| Tokens per second | 998798 |
| $c_v$ | 0.110 |
| Bytes per token | 3.4246 |
| Threads | 1 |

**One thread, and not by choice.** Mojo 1.0.0 has no working task
parallelism: there is no `parallelize`, and `TaskGroup` aborts at runtime
with `LLVM ERROR: destroying a non-available AsyncValue is not implemented`.
Batching across documents is trivially parallel and trivially correct, since
each document is independent, so this figure should be read as a floor that
a working scheduler would lift by close to the core count. The constraint is
recorded in [docs/ARCHITECTURE.md](ARCHITECTURE.md) so that it is not
mistaken for a design decision.

Note that batch throughput is essentially the same as single document
throughput, which is what it should be. A batch of 2 KB documents is not a
different workload from one 4 MB document, only a differently shaped one.

## Decode

**Decode throughput is a footnote and is presented as one.** Decoding is a
table lookup and a copy. It is not where a tokenizer's difficulty lives, no
serving system is bottlenecked on it, and leading with it would be choosing
the metric that flatters rather than the one that matters.

| Implementation | MB/s | Tokens/s | $c_v$ |
| --- | --- | --- | --- |
| Knap | 125.09 | 38244485 | 0.103 |
| `tiktoken` | 78.12 | 23887003 | 0.075 |

Knap is about 1.6 times faster here. That is a real measurement and it is
worth roughly nothing, which is why it is in the last section rather than
the first.

## What these numbers do not mean

Read this section before quoting anything above.

**They are one machine.** An AMD Ryzen 5 3500U is a 2019 mobile part, and it
is running under WSL 2 with under three gigabytes of memory. A server class
processor would change every absolute figure here and could change the
ordering, because the implementations differ in how much they lean on memory
bandwidth. The machine is named at the top of this document so that a reader
can discount it, not as decoration.

**They are one corpus.** Prose in Latin script, from the books section of
the mixed corpus. Text that is mostly CJK, mostly punctuation, or mostly
digits produces different piece lengths, and piece length is the variable
this pipeline is most sensitive to. The clearest evidence is in this
project's own history: the same benchmarks against the corpus's generated
hazard section reported encode figures five times higher and a cache hit
rate of 99.99 percent from 127 distinct pieces. They were measuring
repetition, not tokenization, and they were believed for a while.

**They are one input size.** Throughput is not flat in input size on this
machine. A sixteen megabyte run measured roughly five times lower per byte
than a four megabyte one, on the same corpus at the same offset, which on a
machine with this much memory is most likely paging rather than anything
about the algorithm. Every figure here attaches to its stated input size.

**They do not describe your workload.** The piece cache numbers in
particular depend on how much text a process sees and how much of it
repeats. A service tokenizing many short similar messages will do better
than the shared cache figure. A one shot job over unrelated documents will
do worse, and should probably not enable the cache at all.

**They are not a claim to be fastest.** Knap is slower than both Rust
baselines at encoding and the tables say so in the first section. That was
the expected result: the merge loop is inherently serial, it does not
vectorise, and those implementations have had far more attention. What this
project offers is verified parity. The performance work exists so that the
parity is usable, not so that it can be advertised.

**Latency variance is high and is not hidden.** The coefficient of variation
on Knap's short string measurements is above 0.6 for every size class, which
means a long tail rather than a tight centre. The percentiles are reported
for exactly that reason. A mean latency alone would be a misleading summary
of this distribution, and quoting one would be a choice to mislead.

## Reproducing this

```bash
uv sync --group dev
uv run python scripts/fetch_vocabs.py
uv run python scripts/fetch_corpus.py
bash bench/run_all.sh 4
```

The suite writes one file per run to `bench/results/`, named by timestamp,
recording the machine, the versions, the effective build target, the corpus
digest, and the corpus offset alongside every measurement. The run behind
this document is committed there.

`bash bench/run_all.sh` with no argument uses 16 megabytes, which on this
machine takes long enough to be worth starting deliberately.

There is a `.github/workflows/bench.yml` that runs the same suite on a
schedule. **Its numbers are not publishable and it says so.** It exists to
catch a benchmark that has stopped compiling, a corpus slice that no longer
resolves, or the offsets in the Mojo harness and the Python baselines
drifting apart. A shared runner cannot produce a comparable measurement.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/CORRECTNESS.md](CORRECTNESS.md) |
| Next | [docs/ROADMAP.md](ROADMAP.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-08 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/BENCHMARKS.md -->
