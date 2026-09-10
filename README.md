<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="docs/assets/knap_logo_transparent_white.svg">
    <img src="docs/assets/knap_logo_transparent_black.svg"
         alt="Knap" width="420">
  </picture>
</p>

<!--
  Two rows: what is verified, then what this is. Every workflow badge uses
  the ?branch=main form GitHub documents, so a red badge means main is red
  rather than that somebody's pull request was.

  Benchmark smoke is deliberately not badged. It asserts that the benchmark
  suite still runs on a shared runner, and its own workflow says plainly
  that a shared runner cannot produce a comparable number. A green badge
  next to these would be read as "the benchmarks pass", which is not a thing
  that badge would mean.
-->

<p align="center">
  <a href="https://github.com/olaflaitinen/knap/actions/workflows/ci.yml"><img
    src="https://github.com/olaflaitinen/knap/actions/workflows/ci.yml/badge.svg?branch=main"
    alt="CI status"></a>
  <a href="https://github.com/olaflaitinen/knap/actions/workflows/sanitize.yml"><img
    src="https://github.com/olaflaitinen/knap/actions/workflows/sanitize.yml/badge.svg?branch=main"
    alt="Sanitizer status"></a>
  <a href="https://github.com/olaflaitinen/knap/actions/workflows/codeql.yml"><img
    src="https://github.com/olaflaitinen/knap/actions/workflows/codeql.yml/badge.svg?branch=main"
    alt="CodeQL status"></a>
  <a href="https://github.com/olaflaitinen/knap/actions/workflows/corpus.yml"><img
    src="https://github.com/olaflaitinen/knap/actions/workflows/corpus.yml/badge.svg?branch=main"
    alt="Corpus parity gate status"></a>
  <a href="https://github.com/olaflaitinen/knap/actions/workflows/fuzz.yml"><img
    src="https://github.com/olaflaitinen/knap/actions/workflows/fuzz.yml/badge.svg?branch=main"
    alt="Differential fuzzing status"></a>
</p>

<p align="center">
  <a href="LICENSE"><img
    src="https://img.shields.io/github/license/olaflaitinen/knap?color=blue&label=licence"
    alt="Licence EUPL-1.2"></a>
  <a href="https://mojolang.org/"><img
    src="https://img.shields.io/badge/Mojo-1.0.0%20pinned-orange"
    alt="Mojo 1.0.0, pinned exactly"></a>
  <a href="#supported-encodings"><img
    src="https://img.shields.io/badge/tiktoken%20encodings-7%20of%207-blue"
    alt="All seven tiktoken encodings"></a>
  <a href="docs/PACKAGING.md"><img
    src="https://img.shields.io/badge/conda-not%20published%20yet-lightgrey"
    alt="Not published to a conda channel yet"></a>
  <a href="CODE_OF_CONDUCT.md"><img
    src="https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa"
    alt="Contributor Covenant 2.1"></a>
  <a href="https://github.com/olaflaitinen/knap/commits/main"><img
    src="https://img.shields.io/github/last-commit/olaflaitinen/knap?color=informational"
    alt="Last commit"></a>
  <a href="https://knap.lovable.app"><img
    src="https://img.shields.io/badge/website-knap.lovable.app-ff5c1c"
    alt="Website"></a>
</p>

**A byte level Byte Pair Encoding tokenizer, written from scratch in pure
Mojo.**

**Website:** <https://knap.lovable.app>. The same material as a
browsable site: a [runnable example](https://knap.lovable.app/try) you
can start from a button, the [parity and performance
figures](https://knap.lovable.app/verification) read from this README,
and an [index of the documents in
`docs/`](https://knap.lovable.app/docs).

Knap exists so that a Mojo or MAX program can tokenize inside its own
runtime, without a Python interpreter in the process, without a foreign
function boundary, and without having to take the result on trust. It
implements the seven encodings that OpenAI's models use, and it implements
them: the pre-tokenizer is a hand written scanner rather than a regex
engine, the Unicode tables are generated from the Character Database, and
the merge loop, the rank table and the memory layout are this project's own.

`tiktoken` appears throughout this repository as the **reference
implementation**, which is a measuring instrument rather than a parent. An
encoder whose output differs from what a model was trained on is useless
however elegant it is, so the way to know an implementation is right is to
differentially test it against one that is already trusted. That is what the
numbers below are: 191762320 tokens compared over a 110 MB corpus, every
token id in every encoding decoded and compared, and tens of millions of
generated inputs fuzzed. Knap would be a tokenizer without them. It would
just be one nobody had any reason to believe.

## Contents

1. [What Knap is](#what-knap-is)
2. [Installation](#installation)
3. [Quickstart](#quickstart)
4. [Supported encodings](#supported-encodings)
5. [Correctness](#correctness)
6. [Performance](#performance)
7. [How Knap compares](#how-knap-compares)
8. [From Mojo and MAX](#from-mojo-and-max)
9. [Limitations](#limitations)
10. [When not to use Knap](#when-not-to-use-knap)
11. [Project status](#project-status)
12. [Getting help, and helping](#getting-help-and-helping)
13. [Citation](#citation)
14. [Author and contact](#author-and-contact)
15. [Licence](#licence)

## What Knap is

| | |
| --- | --- |
| Language | Mojo 1.0.0, pinned exactly. No Python at run time. |
| Algorithm | Byte level BPE |
| Encodings | The seven that OpenAI's models use |
| Interfaces | Mojo library, `knap` command line tool, Python extension |
| Verification | Byte identical to the reference, measured rather than intended |
| Licence | EUPL-1.2, a reciprocal licence |

Three properties are worth stating before anything else, because they are
what this project is for.

**Correctness is the product.** Speed is secondary, and where a design choice
trades one for the other, correctness wins. Every performance change in this
repository had to pass the 110 MB parity gate before it was kept, and several
were reverted for failing to earn their complexity.

**Nothing here is a stub.** Every file in the tree is complete and working.
Anything not built is absent rather than faked, and
[docs/ROADMAP.md](docs/ROADMAP.md) lists what is deferred together with the
reason for each.

**Claims are labelled.** Where a number comes from a run, this repository
says which run. Where something has not been measured, it says that instead
of rounding up.

## Installation

Knap targets macOS, Linux, and Windows under WSL. There is no native Windows
build, because Mojo 1.0.0 publishes no Windows wheel.

Both paths below were executed verbatim on a clean Ubuntu 24.04 environment.

With `uv`, which is the primary development environment:

```bash
git clone https://github.com/olaflaitinen/knap.git knap
cd knap
uv sync --group dev
uv run python scripts/fetch_vocabs.py
uv run mojo run -I src tests/test_toolchain.mojo
```

With `pixi`, which pulls Mojo from the stable `max` conda channel:

```bash
git clone https://github.com/olaflaitinen/knap.git knap
cd knap
pixi install
pixi run smoke
```

Both pin the compiler to Mojo 1.0.0 exactly. Mojo guarantees source level
stability only, and its ABI is explicitly not stable, so a floating compiler
version would silently invalidate both benchmarks and any built binding.

Vocabulary files are downloaded by `scripts/fetch_vocabs.py` rather than
committed, so no licence question attaches to this repository and the exact
source of each file is recorded rather than assumed.

There is no conda package published yet. The recipe that would produce one
is written, checked on every push, and builds; publishing it is a separate
decision and has not been taken. See [docs/PACKAGING.md](docs/PACKAGING.md)
for what is prepared and what is not.

## Quickstart

### From Mojo

```mojo
from knap.tokenizer import load_cl100k_base_tokenizer

def main() raises:
    var knap = load_cl100k_base_tokenizer(
        "tests/fixtures/vocabs/cl100k_base.tiktoken"
    )
    var ids = knap.encode_ordinary("Knap tokenizes 1234 bytes.")
    print(len(ids), "tokens")
    print(knap.decode(ids))

    # Counting never builds the list. On a large document that is the
    # difference between holding the ids and not: see docs/BENCHMARKS.md.
    print(knap.count_ordinary("How many tokens is this"), "tokens")

    # Split a document into windows of at most 512 tokens, overlapping by
    # 64. The windows are byte ranges, cut on pre-token boundaries, so the
    # encoding of a window is exactly the slice of the whole document's
    # encoding that covers it.
    for window in knap.windows_ordinary(document, 512, 64):
        print(window)
```

Run it with `uv run mojo run -I src your_program.mojo`. The full surface is
in [docs/API.md](docs/API.md), which is generated from the source rather
than written alongside it.

### From the command line

```bash
knap count "how many tokens is this"
cat prompt.txt | knap count
knap encode --format json "hello world" | jq
knap encode "round trip" | knap decode
knap count -e p50k_base "how many tokens does Codex see"
knap vocab -e o200k_harmony
knap vocab " the"
```

| Command | Does |
| --- | --- |
| `knap count` | Prints one number, so `$(knap count -f x.txt)` works in a shell. Never builds the list of ids. |
| `knap encode` | Prints token ids, as `space`, `lines`, or `json` |
| `knap decode` | Turns token ids back into the exact bytes they represent |
| `knap vocab` | Prints the size and the special tokens of an encoding, or looks one word up |

Input comes from an argument, from `--file`, or from standard input. Exit
status is 0 for success, 1 when the command ran and failed, and 2 when the
command line itself was wrong, so a script can tell a bad invocation from a
bad input.

Two behaviours are worth knowing before you rely on them.

**A marker such as `<|endoftext|>` in the input is ordinary text by default.**
It encodes as the characters that spell it, not as the control token, which
is what the reference implementation's ordinary encode does and what is safe
for text somebody else wrote. `--allowed-special <|endoftext|>` opts in.
`--strict-special` makes any marker an error, which is how you check that a
document is free of them.

**`knap encode X | knap decode` returns X byte for byte**, including when X is
not valid UTF-8. Decode writes raw bytes and adds no newline. That is the
property a byte level tokenizer exists to have, and it is checked over all
256 byte values for all seven encodings in `cli/tests/test_end_to_end.py`.

Completions for bash, zsh and fish are in `cli/completions/`, and the conda
package installs them where each shell looks. `cli/tests/test_completions.py`
reads the command, option and encoding lists out of the parser and checks that
all three files offer them, because a completion file is documentation that
runs and nothing else here executes it.

### From Python

```bash
uv run python bindings/python/build.py
```

```python
import sys
sys.path.insert(0, "bindings/python")
from knap_py import Tokenizer

knap = Tokenizer.cl100k_base("tests/fixtures/vocabs/cl100k_base.tiktoken")
print(knap.encode_ordinary("Knap tokenizes 1234 bytes."))
```

No wheel is published, and that is deliberate. A wheel is a promise that a
binary keeps working, and the Mojo ABI is not stable, so the extension is
locked to the exact toolchain that built it. See
[bindings/python/README.md](bindings/python/README.md).

## Supported encodings

All seven `tiktoken` encodings are supported, and each was checked against
`tiktoken` itself rather than against another encoding that resembles it.

| Encoding | Used by | Verified against |
| --- | --- | --- |
| `cl100k_base` | GPT-4, GPT-3.5-turbo, `text-embedding-ada-002` | 43529983 tokens over 110 MB, all 100277 ids |
| `o200k_base` | GPT-4o, o1 | 36927147 tokens over 110 MB, all 200019 ids |
| `o200k_harmony` | The harmony message format | All 201088 ids, including 1091 special tokens |
| `p50k_base` | Codex, `text-davinci-002` and `003` | 55582056 tokens over 110 MB, all 50281 ids |
| `p50k_edit` | The edit models | All 50284 ids |
| `r50k_base` | GPT-3, `davinci` | 50257 ids |
| `gpt2` | GPT-2 | 55723134 tokens over 110 MB, all 50257 ids |
| Hugging Face `tokenizer.json` | Not supported | Nothing yet |

Seven names, three pre-tokenization patterns, four vocabulary files, and four
distinct ordinary encoding behaviours. `o200k_harmony` shares `o200k_base`'s
merge table and differs only in its special tokens; `p50k_edit` shares
`p50k_base`'s; and `gpt2` has merge ranks byte identical to `r50k_base`'s,
which was checked entry by entry rather than assumed. That is why the corpus
column is filled in for four rows and not for seven: running the same 110 MB
three more times would reproduce a file the gate already compares against,
while the per-encoding fixture and decode gates prove the part that could
actually go wrong.

## Correctness

Correctness is the product. Speed is secondary. When a design choice trades
correctness for speed, correctness wins.

| Measure | Value |
| --- | --- |
| Encodings supported, matching `tiktoken` exactly | 7 |
| Tokens compared against `tiktoken` over 110 MB | 191762320 |
| Piece boundaries compared over the same corpus | 83025959 |
| Token ids decoded and compared | 702463, every id in every encoding |
| Unicode code points verified against an independent reference | 1114112 |
| Memory to hold `cl100k_base`, above an empty runtime | 7.9 MB |
| Encodings whose memory is measured against the reference | 7 |
| Strings fuzzed against `tiktoken` | 20000000, ten million each on two encodings |
| Of those, compared token for token | 16661834 |
| Of those, round trip checked because they are not valid UTF-8 | 3338166 |
| Fuzzed again under the address sanitizer | 200000, on the same two |
| Divergences outstanding | 0 |
| Divergences found and fixed | 1 class, described below |
| Known divergences | None recorded, see docs/CORRECTNESS.md |

Read that table precisely. Encode and decode parity are both established,
over 110 MB of mixed text covering hundreds of languages and over 20 million
generated inputs including deliberately malformed UTF-8.

The fuzzing rows are labelled rather than rounded up. The differential fuzzer
takes all seven encodings and the nightly job runs all seven, but the
reported figures come from the run whose report is committed, which covered
two. A number this project has not observed does not go in this table.

**The fuzzer found a real bug, and that is the most useful thing in this
README.** After 19288 inputs it produced a string where Knap and `tiktoken`
placed a pre-token boundary differently. The cause was that Knap's Unicode
tables had been generated from Python's `unicodedata`, which answers from
Unicode 15.0.0, while `tiktoken` behaves as 16.0.0. About six hundred code
points changed general category between those releases, and each one is a
pre-token boundary in the wrong place. A 110 MB corpus of natural language
had not found it and would not have.

The full account, the hazard list, and the methodology behind every number
above is in [docs/CORRECTNESS.md](docs/CORRECTNESS.md).

## Performance

Every figure below comes from one machine in one session, with the
implementations run alternately so that a drift in the machine moves all of
them together. The machine is a modest laptop, the input is 4 MB of prose,
and the full method is in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

**Encode throughput, higher is better:**

| Implementation | `cl100k_base` | `o200k_base` | `gpt2` | `p50k_base` |
| --- | --- | --- | --- | --- |
| `rs-bpe` | **8.75** | **8.83** | not shipped | not shipped |
| **Knap** | **5.98** | 6.32 | **4.90** | **5.62** |
| `tiktoken` | 4.18 | 6.38 | 4.05 | 5.10 |
| Hugging Face `tokenizers` | 0.60 | not run | not run | not run |

Knap is faster than `tiktoken` on `cl100k_base`, `gpt2` and `p50k_base`, and
level with it on `o200k_base`. It is slower than `rs-bpe` everywhere
`rs-bpe` runs, which is two of the four.

That was not true a day earlier, when Knap was between 1.7 and 2.7 times
slower than `tiktoken`. Four changes closed it, measured as a paired run of
the old and new binaries in one session, and none of them is a language
argument:

- The merge loop now asks whether the whole piece is already a token before
  it starts. Over 4 MB of prose `cl100k_base` turns 882310 pieces into
  1223017 tokens, so most pre-tokens are one token and the loop could never
  have changed them.
- The rank of each adjacent pair is kept rather than recomputed. A merge
  changes exactly two pairs, so the number of hash lookups per piece falls
  from quadratic in the piece length to linear.
- The 256 single byte tokens moved into a direct array, and the id of a
  merged part is the rank the merge already found.
- The probe table carries a tag from the key's hash, so a lookup that is
  going to fail usually fails after one load instead of four.

**Memory, which almost nobody measures.** Knap holds every encoding in
between 4.4 and 11.7 times less memory than the reference implementation,
measured in the same run with both empty runtimes reported as controls:

| Encoding | Knap | `tiktoken` |
| --- | --- | --- |
| `gpt2` | **3.1 MB** | 36.4 MB |
| `cl100k_base` | **8.0 MB** | 44.7 MB |
| `o200k_base` | **18.3 MB** | 80.0 MB |
| `o200k_harmony` | **18.4 MB** | 82.5 MB |

All seven are in [docs/BENCHMARKS.md](docs/BENCHMARKS.md). On a machine
deciding how many encodings a process can hold, this is a harder limit than
throughput.

Two further results, each a measurement rather than a claim:

- With the optional piece cache and a workload that re-encodes the same
  document, throughput is 16.58 MB/s, which is above every baseline here.
  That is a cache hit rate result and it is labelled as one.
- Decoding runs at 140.36 MB/s against `tiktoken`'s 52.14. Decode is a
  footnote metric in this project and is deliberately not the headline: it
  is a memory copy, and no one's pipeline is decode bound.

`tiktoken` and Hugging Face `tokenizers` parallelise batches across cores and
Knap does not, because Mojo 1.0.0 has no working task parallelism. On a
multi-core batch workload they will win, and
[docs/BENCHMARKS.md](docs/BENCHMARKS.md) says so.

## How Knap compares

The feature rows below were read from the installed packages and their own
documentation on 2026-09-09, not recalled. `tokenizers` is version 0.23.2,
`tiktoken` 0.14.0, `rs-bpe` 0.1.0.

| | Knap | `tiktoken` | `rs-bpe` | HF `tokenizers` |
| --- | --- | --- | --- | --- |
| Implementation language | Mojo | Rust with a Python API | Rust | Rust with a Python API |
| Runs with no Python interpreter | Yes | No | Yes | Yes |
| `tiktoken` encodings shipped | 7 | 7 | 2 | Through conversion |
| Byte level BPE | Yes | Yes | Yes | Yes |
| WordPiece, Unigram, WordLevel | No | No | No | Yes |
| BPE training | No | No | No | Yes, four trainers |
| `tokenizer.json` loading | No | No | No | Yes |
| Character offsets per token | No | No | Yes | Yes |
| Padding and truncation | No | No | No | Yes |
| Normalizers, NFC and NFKC | No | No | No | Yes |
| Parallel batch encoding | No | Yes | Yes | Yes |
| Published parity evidence | Yes, per encoding | No | No | No |

Read that honestly. Hugging Face `tokenizers` is a far larger library than
Knap and covers work Knap does not attempt: four model families, four
trainers, twelve pre-tokenizers, eleven decoders, normalizers, post
processors, padding, truncation, and character offsets on every token. If you
need any of those, use it.

What Knap offers instead is a narrow claim, held to an unusually high
standard, in a place none of the others reach: a Mojo or MAX program can
tokenize in its own runtime, get output byte identical to `tiktoken`, and
read the evidence for that rather than take it on faith.

## From Mojo and MAX

The reason to write a tokenizer in Mojo rather than bind to a Rust one is
that a Mojo or MAX application can then tokenize without leaving its own
runtime. This section says exactly how far that goes, because the honest
answer is narrower than the pitch usually is.

**What is true.** Knap runs with no Python interpreter in the process. That
is not an assertion, it is a continuous integration job:
`tests/fuzz/asan_solo.mojo` drives the whole encode and decode path over
generated input with nothing imported from Python, and it runs under the
address sanitizer with no suppression file. If an interpreter were being
started, the leaks that CPython never frees would appear and the job would
fail. It does not.

**What that buys.** No subprocess, no serialisation of token ids across a
boundary, and no global interpreter lock between tokenization and whatever
runs next. A serving loop that tokenizes in Python today pays all three on
every request.

**The shape for it.** `encode_ordinary_bytes_into` appends into a buffer the
caller owns rather than returning a fresh list, so the ids can be written
straight into memory that something else already owns:

```mojo
var ids = List[Int](capacity=4096)
for document in batch:
    ids.clear()
    tokenizer.encode_ordinary_bytes_into(document, ids)
    # ids now holds this document's tokens, in a buffer you allocated once.
```

**What does not exist, stated plainly.** There is no MAX graph operation, no
tensor type, and no device transfer. Knap produces token ids in host memory
and stops there. Filling a device tensor, batching with padding, and putting
tokenization inside a graph are all the caller's problem today.

That is a gap rather than a decision, and it is the most useful thing anybody
could add next. It is not built here because building it against an interface
this project has not verified against would be exactly the kind of unchecked
claim the rest of this repository exists to avoid.

## Limitations

- No BPE training. Encoding only.
- No offset mapping, meaning no byte range per individual token. Windows
  are cut on pre-token boundaries and carry byte ranges, which covers
  chunking, but not per token spans. Offsets are valuable and they double
  the correctness surface, so they are deferred.
- No WordPiece, Unigram, or SentencePiece.
- No normalization pipelines. None of the seven encodings normalize, and
  adding a normalizer that is not needed would only create divergence.
- No chat templates and no GPU tokenization.
- A single document is not parallelized across threads. Chunking a byte stream
  and pre-tokenizing chunks independently can change the result, because a
  pattern match may span a chunk boundary. Batches would be parallelized
  instead, and cannot be either: Mojo 1.0.0 has no working task parallelism,
  which Modular's own roadmap lists as not started.
- The Mojo ABI is not stable, so any Python binding is version locked and must
  be rebuilt for each toolchain release.
- Parity is evidenced, not proved. It rests on 110 MB of corpus, every token
  id in every encoding, and tens of millions of generated inputs. That is
  evidence about the inputs that were tried. It is not a proof about all
  inputs, and this project will not describe it as one.
- Encoding is slower than `rs-bpe` on the two encodings `rs-bpe` ships.

## When not to use Knap

If you are running Python and tokenization is not your bottleneck, use
`tiktoken`. It is already Rust underneath, the Python layer is a thin binding
rather than a bottleneck, and it is battle tested in a way this project is
not.

If you need training, offsets, padding, or a format other than `.tiktoken`,
use Hugging Face `tokenizers`. Knap does not attempt any of it.

In LLM inference specifically, tokenization is a rounding error next to the
forward pass. Faster tokenization does not give you faster inference, and
Knap will not claim otherwise.

Knap is worth your attention in exactly three cases: you want a Mojo native
tokenizer with no Python interpreter in the process, you want the
pre-tokenizer as a standalone module, or you are interested in the parity
methodology itself.

## Project status

All nine milestones, M0 through M8, are complete. Every claim was observed
rather than inferred.

| Component | State | Milestone |
| --- | --- | --- |
| Toolchain, standards gates, CI | Working | M0 |
| Vocabulary loading and decode | Working, decode parity verified | M1 |
| Pre-tokenizer, scalar | Working, boundary parity verified | M2 |
| BPE merge and encode | Working, encode parity verified | M3 |
| Differential fuzzing against `tiktoken` | 20 million inputs, zero divergences | M4 |
| Vectorised classifier | Working, no measurable gain, off by default | M5 |
| Piece cache | Working, parity verified, opt in | M5 |
| Benchmarks against three baselines | Published, including where they win | M5 |
| Conda packaging | Builds and imports without the source tree | M6 Track A |
| Python bindings | Native extension, parity verified through them | M6 Track B |
| All seven `tiktoken` encodings | Working, parity verified per encoding | M7 |
| Merge path performance | 1.39 to 1.85 times faster, output unchanged | M8 |

Two things are deliberately absent. There is no Hugging Face
`tokenizer.json` loader: that format specifies its own pre-tokenizer, so a
loader needs its own parity corpus and its own reference implementation, and
shipping one without those would put an unverified path inside a library
whose whole claim is verification. And batch encoding is single threaded,
which is not a choice: Mojo 1.0.0 has no working task parallelism.

## Getting help, and helping

| You want to | Go here |
| --- | --- |
| Ask how to do something, or find out whether a question is already answered | [SUPPORT.md](SUPPORT.md) |
| Report different token ids from `tiktoken` | The parity divergence issue form. It is the highest priority report this project takes. |
| Report a vulnerability | [SECURITY.md](SECURITY.md), privately, not as an issue |
| Contribute code | [CONTRIBUTING.md](CONTRIBUTING.md), then [docs/STYLE.md](docs/STYLE.md) |
| Understand what is expected of participants | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| See what changed and when | [CHANGELOG.md](CHANGELOG.md) |
| Package or repackage Knap | [docs/PACKAGING.md](docs/PACKAGING.md) |
| Read all of this as a website, or run the example without installing anything | <https://knap.lovable.app> |

The issue forms ask for a great deal. That is deliberate. A parity report
without the exact bytes, the reference version, and how the reference output
was obtained cannot be acted on, and asking for those up front costs the
reporter less than a round trip does. Every closed question offers an option
for not knowing, so nothing forces a guess.

## Citation

If you use Knap in academic work, cite it through the `CITATION.cff` file in
this repository, which GitHub renders as a "Cite this repository" control.

Olaf Yunus Laitinen Imanov, School of Information and Communication
Technology, Metropolia University of Applied Sciences.
ORCID [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810).

## Author and contact

| Field | Value |
| --- | --- |
| Name | Olaf Yunus Laitinen Imanov |
| Role | Researcher |
| Unit | School of Information and Communication Technology |
| Institution | Metropolia University of Applied Sciences |
| Email | yunus.imanov@metropolia.fi |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Availability | Monday to Friday, 17:00 to 19:00 EEST (UTC+3) |

The availability window is stated because issue traffic arrives from other
timezones, and an unstated local window reads as unresponsiveness.

## Licence

Knap is licensed under the European Union Public Licence 1.2. See
[LICENSE](LICENSE) for the full terms.

The EUPL is a reciprocal licence. If you distribute a modified version, or
distribute software that incorporates Knap, you are obliged to release that
work under the EUPL or a compatible licence. That is a deliberate choice, and
it is stated here rather than left for you to discover after you depend on it.
Nothing in this repository is legal advice, and licence compatibility
questions should be confirmed with your own institution.

External works this project uses, and the different obligations each carries,
are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
development setup, the style rules, and the rule that no performance change
merges without the parity suite passing.
