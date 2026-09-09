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

Knap is a byte level Byte Pair Encoding tokenizer written in pure Mojo, built
to produce byte identical output to `tiktoken` on arbitrary input.

## Status

All seven milestones are complete. Every claim below was observed rather than
inferred.

| Component | State | Milestone |
| --- | --- | --- |
| Toolchain, standards gates, CI | Working | M0, complete |
| Vocabulary loading and decode | Working, decode parity verified | M1, complete |
| Pre-tokenizer, scalar | Working, boundary parity verified | M2, complete |
| BPE merge and encode | Working, encode parity verified | M3, complete |
| Differential fuzzing against `tiktoken` | 20 million inputs, zero divergences | M4, complete |
| Vectorised classifier | Working, indistinguishable from scalar on the test machine, off by default | M5, complete |
| Piece cache | Working, parity verified, opt in | M5, complete |
| Benchmarks against three baselines | Published, including where they win | M5, complete |
| Conda packaging | Builds and imports without the source tree | M6 Track A, complete |
| Python bindings | Native extension, parity verified through the bindings | M6 Track B, complete |

Two things are deliberately absent. There is no Hugging Face
`tokenizer.json` loader: that format specifies its own pre-tokenizer, so a
loader needs its own parity corpus and its own reference implementation, and
shipping one without those would put an unverified path inside a library
whose whole claim is verification. And batch encoding is single threaded,
which is not a choice: Mojo 1.0.0 has no working task parallelism.

Nothing in this repository is a stub. Every file present is complete and
working, and anything not built is absent rather than faked. See
[docs/ROADMAP.md](docs/ROADMAP.md) for the full deferred list with reasons.

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

The seven encodings reduce to four distinct ordinary behaviours, because
ordinary encoding is decided by the pre-tokenization pattern and the merge
ranks and by nothing else. The corpus gate is therefore run four times
rather than seven, and the encodings that share a behaviour are held to
separate `tiktoken` fixtures instead, which is what catches a loader that
picked the wrong file. Decode is run for all seven, because their special
token registries genuinely differ.

The fuzzing rows are the exception, and they are labelled rather than
rounded up. The differential fuzzer takes all seven encodings and the
nightly job runs all seven, but the reported figures come from the run that
covered two, because that is the run whose report is committed. A number
this project has not observed does not go in this table.

**The fuzzer found a real bug, and that is the most useful thing in this
README.** After 19288 inputs it produced a string where Knap and `tiktoken`
placed a pre-token boundary differently. The cause was that Knap's Unicode
tables came from Python's `unicodedata` module, which answers from Unicode
15.0.0, while the tables `tiktoken` actually behaves as are 16.0.0. About six
hundred code points changed general category between those releases.

Three things about that are worth your attention if you are evaluating this
library:

- The 110 MB corpus did not find it and would not have. Natural language
  barely contains the code points involved. Only uniform generation over the
  code point space reaches them.
- The obvious fix was also wrong. Regenerating against the `regex` module's
  tables moved the divergence instead of removing it.
- What settled it was a measurement, not an argument: inputs constructed so
  that their answer differs between the candidate Unicode versions, handed to
  the reference. It agreed with 16.0.0 on 400 of 400.

The full account is in [docs/UNICODE.md](docs/UNICODE.md), and the
methodology behind every number above is in
[docs/CORRECTNESS.md](docs/CORRECTNESS.md).

## Performance

**Knap is slower than both Rust baselines at encoding, on this machine and
this corpus.** That is the headline because it is the result, and it was the
expected result before anything was measured.

| Implementation | `cl100k_base` | `o200k_base` |
| --- | --- | --- |
| `rs-bpe` | 10.66 MB/s | 10.02 MB/s |
| `tiktoken` | 5.81 MB/s | 8.74 MB/s |
| **Knap** | **3.44 MB/s** | **3.21 MB/s** |

Every baseline was run on the same machine, from the same corpus slice, by
the author, and the ones that win are printed in the same table at the same
size. The full method, the machine, the versions, and the run to run spread
are in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

Two results there are worth more than the table. Removing a single
allocation from the rank lookup nearly doubled encode throughput, and the
vectorised classifier cannot be distinguished from the scalar one on this
machine, which is why it is off by default. Both are measurements. Neither
is a claim about Mojo.

## Installation

Knap targets macOS, Linux, and Windows under WSL. There is no native Windows
build, because Mojo 1.0.0 publishes no Windows wheel.

Both paths below were executed verbatim on a clean Ubuntu 24.04 environment.

With `uv`, which is the primary development environment:

```bash
git clone https://github.com/olaflaitinen/knap.git knap
cd knap
uv sync --group dev
uv run mojo run tests/test_toolchain.mojo
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

A Python binding is built from source rather than installed from a wheel:

```bash
python bindings/python/build.py
python bindings/python/tests/test_bindings.py
```

No wheel is published, and that is deliberate. A wheel is a promise that a
binary keeps working, and the Mojo ABI is not stable, so the binding is
locked to the exact toolchain it was built against. See
[bindings/python/README.md](bindings/python/README.md).

## Command line

The easiest way to use Knap, and the only one that does not need a Mojo
toolchain once the package is installed.

```bash
knap count "how many tokens is this"
cat prompt.txt | knap count
knap encode --format json "hello world" | jq
knap encode "round trip" | knap decode
knap vocab -e o200k_base
knap count -e p50k_base "how many tokens does Codex see"
```

| Command | Does |
| --- | --- |
| `knap count` | Prints one number, so `$(knap count -f x.txt)` works in a shell |
| `knap encode` | Prints token ids, as `space`, `lines`, or `json` |
| `knap decode` | Turns token ids back into the exact bytes they represent |
| `knap vocab` | Prints the size and the special tokens of an encoding |

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
256 byte values in `cli/tests/test_end_to_end.py`.

Vocabularies are not bundled. `knap help` lists the five places the tool
looks for them, in order.

## Quickstart

The encode and decode quickstart arrives with M3. What runs today is the
toolchain smoke test and the repository standards gates:

```mojo
from knap.tokenizer import load_cl100k_base_tokenizer

def main() raises:
    var knap = load_cl100k_base_tokenizer(
        "tests/fixtures/vocabs/cl100k_base.tiktoken"
    )
    var ids = knap.encode_ordinary("Knap tokenizes 1234 bytes.")
    print(knap.decode(ids))
```

Fetch a vocabulary first with `uv run python scripts/fetch_vocabs.py`, then
run it with `uv run mojo run -I src your_program.mojo`.

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

## Supported vocabularies

All seven `tiktoken` encodings are supported, and each was checked against
`tiktoken` itself rather than against another encoding that looks like it.

| Encoding | Used by | Verified against |
| --- | --- | --- |
| `cl100k_base` | GPT-4, GPT-3.5-turbo, `text-embedding-ada-002` | 43529983 tokens over 110 MB, all 100277 ids |
| `o200k_base` | GPT-4o, o1 | 36927147 tokens over 110 MB, all 200019 ids |
| `o200k_harmony` | Open weight harmony format | All 201088 ids, including 1091 special tokens |
| `p50k_base` | Codex, `text-davinci-002` and `003` | 55582056 tokens over 110 MB, all 50281 ids |
| `p50k_edit` | The edit models | All 50284 ids |
| `r50k_base` | GPT-3, `davinci` | 50257 ids |
| `gpt2` | GPT-2 | 55723134 tokens over 110 MB, all 50257 ids |
| Hugging Face `tokenizer.json` | Not supported | Nothing yet |

Seven names, three pre-tokenization patterns, four vocabulary files, and
four distinct ordinary encoding behaviours. `o200k_harmony` shares
`o200k_base`'s merge table and differs only in its special tokens;
`p50k_edit` shares `p50k_base`'s; and `gpt2` has merge ranks byte identical
to `r50k_base`'s, which was checked entry by entry rather than assumed. That
is why the corpus column above is filled in for four rows and not for seven:
running the same 110 MB three more times would produce the same numbers and
prove nothing new, while the per-encoding fixture and decode gates prove the
part that could actually go wrong.

Vocabulary files are downloaded by a script rather than committed, so that no
licence question attaches to this repository and the exact source is recorded
rather than assumed.

## Limitations

- No BPE training. Encoding only.
- No offset mapping, meaning no character spans per token. It is valuable and
  it doubles the correctness surface, so it is deferred.
- No WordPiece, Unigram, or SentencePiece.
- No normalization pipelines. None of the seven encodings normalize, and
  adding a normalizer that is not needed would only create divergence.
- No chat templates and no GPU tokenization.
- A single document is not parallelized across threads. Chunking a byte stream
  and pre-tokenizing chunks independently can change the result, because a
  pattern match may span a chunk boundary. Batches are parallelized instead,
  which is where the throughput is and which is trivially correct.
- The Mojo ABI is not stable, so any Python binding is version locked and must
  be rebuilt for each toolchain release.
- Parity is evidenced, not proved. It rests on 110 MB of corpus, every token
  id in every encoding, and tens of millions of generated inputs. That is
  evidence about the inputs that were tried. It is not a proof about all
  inputs, and this project will not describe it as one.
- Encoding is slower than both Rust baselines. See
  [docs/BENCHMARKS.md](docs/BENCHMARKS.md), where the winners are printed in
  the same table.

## When not to use Knap

If you are running Python and tokenization is not your bottleneck, use
`tiktoken`. It is already Rust underneath, the Python layer is a thin binding
rather than a bottleneck, and it is battle tested in a way this project is
not.

In LLM inference specifically, tokenization is a rounding error next to the
forward pass. Faster tokenization does not give you faster inference, and
Knap will not claim otherwise.

Knap is worth your attention in exactly three cases: you want a Mojo native
tokenizer with no Python interpreter in the process, you want the SIMD
pre-tokenizer as a standalone module, or you are interested in the parity
methodology itself.

## Getting help, and helping

| You want to | Go here |
| --- | --- |
| Ask how to do something, or find out whether a question is already answered | [SUPPORT.md](SUPPORT.md) |
| Report different token ids from `tiktoken` | The parity divergence issue form. It is the highest priority report this project takes. |
| Report a vulnerability | [SECURITY.md](SECURITY.md), privately, not as an issue |
| Contribute code | [CONTRIBUTING.md](CONTRIBUTING.md), then [docs/STYLE.md](docs/STYLE.md) |
| Understand what is expected of participants | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |

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
