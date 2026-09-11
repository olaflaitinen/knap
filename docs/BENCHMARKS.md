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
| Status | Stable |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-08 |
| Updated | 2026-09-11 |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |

---

## Contents

1. [The short version](#the-short-version)
2. [The machine](#the-machine)
3. [What is measured, and how](#what-is-measured-and-how)
4. [Encode throughput](#encode-throughput)
5. [Counting](#counting)
6. [How the merge loop got faster](#how-the-merge-loop-got-faster)
7. [What the allocation cost](#what-the-allocation-cost)
8. [The piece cache](#the-piece-cache)
9. [The vectorised classifier](#the-vectorised-classifier)
10. [Short string latency](#short-string-latency)
11. [Batch encoding](#batch-encoding)
12. [Decode](#decode)
13. [Memory](#memory)
14. [What these numbers do not mean](#what-these-numbers-do-not-mean)
15. [Reproducing this](#reproducing-this)

---

## The short version

**Knap is faster than `tiktoken` on three of the four distinct encode
behaviours and level with it on the fourth. It is slower than `rs-bpe`
everywhere `rs-bpe` runs.** Every figure comes from one run of
`bench/run_all.sh`, recorded in
`bench/results/run-20260909T155954Z.txt`, with the implementations run one
after another in the same session.

| Implementation | `cl100k_base` | `o200k_base` | `gpt2` | `p50k_base` |
| --- | --- | --- | --- | --- |
| `rs-bpe` | **8.75 MB/s** | **8.83 MB/s** | not shipped | not shipped |
| **Knap** | **5.98 MB/s** | 6.32 MB/s | **4.90 MB/s** | **5.62 MB/s** |
| `tiktoken` | 4.18 MB/s | 6.38 MB/s | 4.05 MB/s | 5.10 MB/s |
| Hugging Face `tokenizers` | 0.60 MB/s, approximate | not run | not run | not run |

Four encodings, not seven. Knap ships seven and they reduce to four distinct
encode behaviours, because ordinary encoding is decided by the
pre-tokenization pattern and the merge ranks and by nothing else. A fifth
row would repeat one of these. `rs-bpe` ships two of the seven, so two of
the four rows have one fewer baseline to lose to, and that is why those
cells say "not shipped" rather than being left blank.

**Do not compare these numbers with the ones this document carried on
2026-09-08.** The whole table moved, in both directions, because the machine
was in a different state. `rs-bpe` reads 8.75 here and read 10.66 then, and
nothing about `rs-bpe` changed. Only figures taken in the same session are
comparable, which is why the improvement below is reported as a paired run
rather than as a difference between two published tables.

Four secondary results, each a measurement rather than a claim:

- Encode is between 1.39 and 1.85 times faster than it was a day earlier,
  measured by running the old and new binaries alternately in one session.
  See [How the merge loop got faster](#how-the-merge-loop-got-faster).
- Removing one allocation from the rank lookup nearly doubled encode
  throughput before that. See
  [What the allocation cost](#what-the-allocation-cost).
- The optional piece cache is now worth less than it was, and on
  `cl100k_base` it is worth nothing at all. Making the uncached path faster
  moved the break even point. See [The piece cache](#the-piece-cache).
- The vectorised classifier measured clearly slower than the scalar one in
  this run, where a previous run could not tell them apart. It stays off by
  default either way.

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
- **A paired comparison for anything under about ten percent.** Two binaries
  built from the same tree, run alternately in one session, and the
  difference taken per pair rather than between two averages. The run to run
  spread on this machine is around five percent, so a five percent effect
  measured across sessions is indistinguishable from the machine's mood. The
  allocation result below was invisible, and briefly appeared negative, until
  it was measured this way.

## Encode throughput

Five timed iterations of 4194296 bytes, per implementation, per encoding.

### `cl100k_base`

| Implementation | MB/s | Tokens/s | $c_v$ | Bytes per token |
| --- | --- | --- | --- | --- |
| `rs-bpe` | 8.75 | 2673847 | 0.237 | 3.4295 |
| Knap | 5.98 | 1827596 | 0.134 | 3.4295 |
| Knap, piece cache shared across documents | 5.58 | 1690879 | 0.217 | 3.4574 |
| `tiktoken` | 4.18 | 1277955 | 0.097 | 3.4295 |
| Hugging Face `tokenizers` | 0.60 | 290492 | 0.066 | 2.1523 |

### `o200k_base`

| Implementation | MB/s | Tokens/s | $c_v$ | Bytes per token |
| --- | --- | --- | --- | --- |
| `rs-bpe` | 8.83 | 2410968 | 0.126 | 3.8416 |
| Knap, piece cache shared across documents | 7.50 | 1938110 | 0.339 | 4.0581 |
| `tiktoken` | 6.38 | 1741672 | 0.045 | 3.8416 |
| Knap | 6.32 | 1725701 | 0.091 | 3.8416 |

### `gpt2`

Shared with `r50k_base`. `rs-bpe` does not ship this encoding.

| Implementation | MB/s | Tokens/s | $c_v$ | Bytes per token |
| --- | --- | --- | --- | --- |
| Knap | 4.90 | 1947835 | 0.130 | 2.6364 |
| `tiktoken` | 4.05 | 1610701 | 0.069 | 2.6364 |

### `p50k_base`

Shared with `p50k_edit`. `rs-bpe` does not ship this encoding.

| Implementation | MB/s | Tokens/s | $c_v$ | Bytes per token |
| --- | --- | --- | --- | --- |
| Knap | 5.62 | 2233632 | 0.088 | 2.6384 |
| `tiktoken` | 5.10 | 2027328 | 0.068 | 2.6384 |

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

**Knap is faster than `tiktoken` by 43 percent on `cl100k_base`, 21 percent
on `gpt2` and 10 percent on `p50k_base`, and one percent slower on
`o200k_base`, which is inside the noise of both measurements.** It is 28 to
32 percent slower than `rs-bpe` on the two encodings `rs-bpe` ships, which is
the same gap read the other way as `rs-bpe` being 40 to 46 percent faster.

`o200k_base` is the encoding where Knap does least well relative to the
others, and the reason is visible in the pre-tokenization figures below:
that pattern costs 15.56 MB/s against `cl100k_base`'s 19.89, because it has
two word alternatives whose character classes overlap and one of them
genuinely backtracks. The merge side is not the problem there.

## Counting

`count_ordinary` walks the same scanner and the same merge loop as
`encode_ordinary` and simply does not append the ids. It was written on the
expectation that it would be faster, because counting is the most common
thing anyone asks a tokenizer to do and the list of ids is usually thrown
away immediately after its length is read.

**It is not faster.** Measured in one run, on the same input, immediately
after the encode rows:

| Encoding | Encode | Count |
| --- | --- | --- |
| `cl100k_base` | 2.99 MB/s | 3.11 MB/s |
| `o200k_base` | 3.10 MB/s | 2.85 MB/s |
| `gpt2` | 3.09 MB/s | 3.24 MB/s |
| `p50k_base` | 2.98 MB/s | 2.93 MB/s |

Two rows up, two down, all inside the spread. Those figures are lower than
the headline table because the machine was in a worse state that afternoon,
which is exactly why the comparison is against the encode rows from the same
run and not against the published ones.

The reason is straightforward once measured. Appending an integer to a list
is a store and an increment, and there are 1.2 million of them against a
merge loop that is doing hash lookups. The list is not where the time goes.

**Where it does pay is memory, and only once the input is large.** See
[Memory](#memory): counting 80 MB peaks at 270 MB above the control and
encoding the same input peaks at 584 MB, because the ids have become the
largest thing in the process. At 4 MB the two are identical.

So the entry point is kept, and it is documented as a memory entry point
rather than a fast path. The prediction that it would save time is recorded
here as refuted rather than removed, because the reasoning that produced it
was the same reasoning that produced the allocation result below, and one of
the two was right.

## How the merge loop got faster

Four changes to the merge path, in the order they were made, each kept only
after the 110 MB parity gate passed with byte identical output.

Measured by building the binary from before the four changes and the binary
from after them, then running the two alternately five times in one session
and taking the median of each. A paired run rather than two published
tables, because this machine's absolute figures drift between sessions by
more than the effect being measured.

| Encoding | Before | After | Ratio |
| --- | --- | --- | --- |
| `cl100k_base` | 4.18 MB/s | 6.68 MB/s | 1.60 |
| `o200k_base` | 3.80 MB/s | 7.01 MB/s | 1.85 |
| `gpt2` | 4.74 MB/s | 6.58 MB/s | 1.39 |
| `p50k_base` | 4.74 MB/s | 6.59 MB/s | 1.39 |

### Ask whether the whole piece is already a token

The loop used to start splitting every piece longer than one byte. Over 4 MB
of prose `cl100k_base` turns 882310 pieces into 1223017 tokens, which is 1.39
tokens per piece, so most pre-tokens are a single token and the loop could
never have changed them. Asking the rank table once, before the loop starts,
answers them in one hash lookup instead of a quadratic number.

It is sound because a token exists in the vocabulary only because training
merged that byte sequence in rank order, and replaying the same lowest rank
first rule over the same bytes replays the same merges. That is an
assumption about the vocabulary rather than a theorem about the loop, which
is why the 110 MB gate is the thing that checks it.

### Keep the rank of each pair rather than asking again

Finding the lowest ranked adjacent pair used to ask the rank table for every
pair on every round, which is a quadratic number of hash lookups in the
piece length. A merge changes exactly two pairs: the one it created and the
one before it. Everything else still has the rank it had.

Keeping them turns the lookups into the piece length plus two per merge,
while the scan for the smallest rank becomes a walk over integers, which is
the cheap half of what the loop was doing.

### Stop hashing what is already known

The 256 single byte tokens moved into a direct array indexed by the byte, so
starting a piece costs no hashing at all. And the rank of a pair is the
token id of the part it becomes, so the walk that writes the answer out no
longer looks each finished part up to confirm what the merge already
established.

This one is the least certain of the four. Measured on its own it was faster
on three encodings and slower on `cl100k_base`, and the machine could not
resolve which. It is kept because it strictly removes lookups, and because
the stack it belongs to measured faster than the stack without it.

### Put a tag from the hash in the probe table

A probe used to touch four arrays before it could reject a slot: the slot
table, the key length, the key start, and the key bytes. On `o200k_base`'s
two hundred thousand entry table that is four chances to miss the cache in
order to answer no.

Packing thirty two bits of the hash into the same word as the entry index
means the usual answer arrives after one load. The bytes are still compared
before an entry is accepted, because a tag is thirty two bits and equal tags
are not equal keys.

The hash itself changed at the same time, from FNV-1a to a mixer that reads
eight bytes per iteration. Those two were measured together and are not
separated here.

### What was not done

The merge loop is still quadratic in the piece length in the worst case: the
scan for the smallest rank walks every remaining pair on every round. That
scan is now a walk over integers rather than a walk over hash lookups, which
is why it stopped being the cost. Replacing it with a heap would be a larger
claim and there is no measurement asking for one.

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

### The second allocation, and why it is a different story

The merge loop also allocated a small list of split points for every
pre-token. On four megabytes of prose that is about a million allocations of
a structure that lives for a few microseconds. Moving it to a scratch buffer
the caller owns and reuses makes that number one.

The result is real and it is small:

| Encoding | Before | After | Change | Confidence |
| --- | --- | --- | --- | --- |
| `cl100k_base` | 3.609 MB/s | 3.818 MB/s | plus 5.8 percent | 3.4 $\sigma$ |
| `o200k_base` | 3.325 MB/s | 3.504 MB/s | plus 5.4 percent | 4.5 $\sigma$ |

**Five percent, from removing a million allocations.** The rank table fix
removed a comparable number and returned ninety percent. Both were the same
shape of mistake and they differ by a factor of seventeen in what they were
worth, which is worth writing down: "allocations are the cost" is a useful
prior and not a law. The rank table allocation also copied bytes and hashed
a fresh String; this one asks the allocator for a few dozen bytes and gives
them straight back, which is close to the cheapest thing an allocator does.

The measurement is a paired one, and that matters at this size. Two binaries
were built from the same tree with and without the change, run alternately
twelve times each in one session, and the difference taken per pair. Compared
across sessions the change is invisible: the spread between runs on this
machine is larger than five percent, and the first unpaired comparison put
the change on the wrong side of zero for one of the two encodings. A five
percent effect measured by comparing two numbers taken an hour apart is not a
measurement.

### A prediction this refuted

Knap's tail latency in [Short string latency](#short-string-latency) is
several times the reference at the 99th percentile while the median is close
to it. The obvious explanation was allocation spikes, and it was written
down as such before being tested.

It is wrong. With the per-piece allocation gone, the percentiles do not move.
The figures below are from the 2026-09-08 run, which is the pair that tested
this specific hypothesis:

| Size class | p50 before | p50 after | p99 before | p99 after |
| --- | --- | --- | --- | --- |
| About 10 tokens | 6693 | 6743 | 23344 | 27503 |
| About 50 tokens | 29446 | 26581 | 158852 | 161868 |
| About 200 tokens | 110361 | 116522 | 763926 | 761862 |

Every figure is inside the run to run spread. Whatever produces that tail, it
is not this.

A second hypothesis has since been eliminated the same way. The merge
path work
removed roughly three quarters of the merge loop's hash lookups, and the
tail did not improve in proportion either. Two of the obvious candidates are
now gone and the cause is an open question in
[docs/ARCHITECTURE.md](ARCHITECTURE.md) rather than a third guess.

## The piece cache

The cache is optional, owned by the caller, and off unless asked for. It maps
a pre-token's bytes to the ids it encodes to, so a piece seen twice is merged
once.

Four measurements, because one would mislead. The input is divided into five
documents of 838859 bytes each.

### `cl100k_base`

| Measurement | MB/s | $c_v$ | Hit rate | Entries | Bytes held |
| --- | --- | --- | --- | --- | --- |
| Uncached | 6.15 | 0.135 | not applicable | 0 | 0 |
| Cold cache, fresh per document | 6.78 | 0.157 | 0.839 | 26616 | 5824003 |
| Shared cache, across new documents | 5.58 | 0.217 | 0.927 | 77633 | 8901142 |
| One document repeated, an upper bound | 16.58 | 0.067 | 0.977 | 25235 | 5593405 |

### `o200k_base`

| Measurement | MB/s | $c_v$ | Hit rate | Entries | Bytes held |
| --- | --- | --- | --- | --- | --- |
| Uncached | 6.06 | 0.154 | not applicable | 0 | 0 |
| Cold cache, fresh per document | 6.88 | 0.187 | 0.839 | 26673 | 5707610 |
| Shared cache, across new documents | 7.50 | 0.339 | 0.927 | 77705 | 8668502 |
| One document repeated, an upper bound | 15.93 | 0.096 | 0.977 | 25235 | 5555043 |

### Which row to believe

**The shared cache row.** It is the only one that describes a process
encoding documents it has not seen before, which is what a long running
service does.

**And on `cl100k_base` that row now says the cache is not worth having.**
5.58 MB/s cached against 6.15 uncached, with a hit rate of 92.7 percent. The
cache is doing what it was built to do and the answer is still slower,
because the work it saves became cheap. A hit is a hash of the piece and a
copy of its ids; a miss is that plus the merge. When the merge was a
quadratic number of hash lookups, saving it was worth the hash. Now that
most pieces are answered by a single lookup of the whole piece, the cache is
largely paying a hash to avoid a hash.

`o200k_base` still gains, 7.50 against 6.06, because its table is twice the
size and a lookup in it costs more.

This is the second time a measurement has moved under this feature and it is
worth saying why that is not embarrassing. A cache is a bet that recomputing
is expensive. Making the computation cheaper is supposed to make the bet
worse. The number changing is the system working.

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
| Scalar, the default | 19.89, $c_v$ 0.086 | 15.56, $c_v$ 0.157 |
| Vectorised, `-D KNAP_SIMD=1` | 10.78, $c_v$ 0.184 | 12.28, $c_v$ 0.222 |

**In this run the vectorised path lost, and lost clearly:** 46 percent slower
on `cl100k_base` and 21 percent on `o200k_base`, both well outside the
spread of either measurement.

That is not what the previous run said. On 2026-09-08 the two were 19.25
against 19.91 and 14.36 against 14.72, which is indistinguishable. Two runs
of the same benchmark on the same machine have now produced "cannot tell"
and "clearly worse", and no source change stands between them.

Both readings are recorded rather than one being chosen, because that
disagreement is itself the result. What survives it is the decision, which
was already the conservative one: the vectorised classifier is off by
default, and nothing in either run argues for turning it on.

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
| About 10 tokens | Knap | 7063 | 19347 | 28094 | 9312 | 0.844 |
| About 10 tokens | `tiktoken` | 7354 | 12594 | 36400 | 8776 | 0.803 |
| About 50 tokens | Knap | 40748 | 119838 | 306825 | 62043 | 1.805 |
| About 50 tokens | `tiktoken` | 22694 | 29116 | 72047 | 24923 | 0.483 |
| About 200 tokens | Knap | 121702 | 310231 | 607739 | 155775 | 0.869 |
| About 200 tokens | `tiktoken` | 85693 | 130879 | 238906 | 95098 | 0.350 |

**Knap now wins the smallest size class at the median and loses the other
two.** At about ten tokens the two medians are 7063 and 7354 nanoseconds,
which is a difference of four percent between two measurements whose
coefficients of variation are above 0.8, so the honest reading is that they
are the same. At fifty and two hundred tokens Knap's median is 1.4 to 1.8
times the reference.

**The tail is still the open question.** Knap's 99th percentile is 0.8, 4.3
and 2.5 times the reference across the three classes, and its coefficient of
variation reaches 1.8. The obvious explanation was allocation, and that
explanation has now been eliminated twice: once when the per-piece
allocation was removed, and again in this round when three quarters of the
merge loop's hash lookups went away without the tail improving in
proportion. Whatever it is, it is not the number of allocations and it is
not the number of lookups. It has not been profiled, and recording the
question honestly is worth more than guessing at it again.

## Batch encoding

Two thousand documents of 2048 bytes each, encoded in sequence.

| Measurement | Value |
| --- | --- |
| Throughput | 5.14 MB/s |
| Tokens per second | 1572418 |
| $c_v$ | 0.144 |
| Bytes per token | 3.4246 |
| Threads | 1 |

**One thread, and not by choice.** Mojo 1.0.0 has no working task
parallelism: there is no `parallelize`, and `TaskGroup` aborts at runtime
with `LLVM ERROR: destroying a non-available AsyncValue is not implemented`.
Batching across documents is trivially parallel and trivially correct, since
each document is independent, so this figure should be read as a floor that
a working scheduler would lift by close to the core count. The constraint is
recorded in [docs/ARCHITECTURE.md](ARCHITECTURE.md) so that it is not
mistaken for a design decision, and Modular's own roadmap lists first class
`async` support as not started, which is the same constraint seen from
upstream.

`tiktoken` and Hugging Face `tokenizers` both parallelise batches across
cores. On a batch workload with cores to spare they will win, and no
single threaded implementation is going to argue otherwise.

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
| Knap | 140.36 | 42913857 | 0.072 |
| `tiktoken` | 52.14 | 15942109 | 0.273 |

Knap is about 2.7 times faster here. That is a real measurement and it is
worth roughly nothing, which is why it is in the last section rather than
the first. A tokenizer that led with its decode number would be choosing the
metric that flatters it.

## Memory

Throughput is measured everywhere and memory almost nowhere, which is odd:
on a serving machine, how many tokenizers you can hold is a harder limit
than how fast one of them runs.

Two rules make these figures mean something. **One stage per process**,
because peak resident memory is a high water mark and a process that loads a
vocabulary and then encodes reports one number for both. And **the control
is always reported**, because without it a reader cannot separate the
library from the language runtime.

### Every encoding, ready to encode

The survey, and the part nobody publishes. One child process per encoding,
each loaded to the point where it can encode, with the empty runtime of its
own language as the control.

| Encoding | Knap | `tiktoken` | Ratio |
| --- | --- | --- | --- |
| `gpt2` | **3.1 MB** | 36.4 MB | 11.7 |
| `r50k_base` | **3.3 MB** | 27.3 MB | 8.3 |
| `p50k_base` | **3.3 MB** | 27.4 MB | 8.4 |
| `p50k_edit` | **3.4 MB** | 27.4 MB | 8.1 |
| `cl100k_base` | **8.0 MB** | 44.7 MB | 5.6 |
| `o200k_base` | **18.3 MB** | 80.0 MB | 4.4 |
| `o200k_harmony` | **18.4 MB** | 82.5 MB | 4.5 |

Both controls are about 13 MB, an empty Mojo binary and an empty Python
interpreter, and both are subtracted. Quoting the raw peaks would have
flattered nobody: it would have made a 12 times difference look like 3.

**Knap holds every encoding in between 4.4 and 11.7 times less memory than
the reference implementation.** On a serving machine that is the number that
decides how many encodings a process can hold, and it is a harder limit than
throughput.

One row is odd and it is not ours. `tiktoken`'s `gpt2` costs 9 MB more than
its `r50k_base` although the two merge tables are identical, which
`scripts/diff_vocabs.py` confirms token for token and rank for rank. Knap
loads both from the same file and pays the same 3 MB either way. Something
in how `gpt2` is distributed accounts for the difference; nothing visible
from here says what, and it is reported rather than explained.

### The stage ladder

`cl100k_base`, one stage at a time, so that a peak belongs to one thing.

| Stage | Peak | Above control |
| --- | --- | --- |
| An empty Mojo program | 13.0 MB | control |
| The vocabulary file read into memory | 15.4 MB | 2.4 MB |
| The parsed vocabulary | 20.6 MB | 7.6 MB |
| **The vocabulary and the rank table, ready to encode** | **20.9 MB** | **7.9 MB** |
| 80 MB of input counted | 217.7 MB | 204.7 MB |
| 80 MB of input encoded to a list of ids | 426.5 MB | 413.5 MB |

The last two rows are the counting result seen from the memory side. The
difference between them is 208.8 MB for 27372826 tokens, which is 7.99 bytes
per token, and a token id is eight bytes. The list of ids is the whole
difference and there is nothing else in it.

**That last sentence was not true when this table was first measured.** The
difference was 343.7 MB, which is 13.2 bytes per token, because the output
list was grown into rather than sized: a list that doubles holds both
buffers while it copies, so its peak is about half again its final size.
Sizing it once from the input length removed 137.7 MB of peak on this input
and brought the arithmetic back to eight bytes a token. The 110 MB parity
gate passed unchanged, because a capacity hint cannot change an answer.

### Two things this measurement caught

**A number that was nearly published wrong.** The first version ran the
tokenizer inside the throughput harness and reported 290 MB, which would
have been a claim that Knap uses six times the memory `tiktoken` does. The
290 MB was the corpus. The control and the per stage split are the only
reason a wrong number did not go out, and that is why they are in the
harness rather than in a notebook.

**A benchmark harness reading 115 MB to hand back four.** It read the whole
corpus and indexed into it. It now seeks, and reads the slice plus a bound
on how far the first line boundary can be. The encode benchmark's peak fell
from 282.8 MB to 95.6 MB, which matters on a machine with 2.8 GB where the
thing being measured was competing with the measurement for page cache.
Both the Mojo and the Python side changed together and produce byte
identical slices at 1, 4 and 16 MB, which `bench/run_all.sh` checks before
it will run at all.

Run it with `python bench/memory.py`.

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
| Last reviewed | 2026-09-11 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/BENCHMARKS.md -->
