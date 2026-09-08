<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap

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
| Tokens compared against `tiktoken` over 110 MB | 80457130, both encodings |
| Piece boundaries compared over the same corpus | 54326357 |
| Token ids decoded and compared | 300296, every id in both encodings |
| Unicode code points verified against an independent reference | 1114112 |
| Strings fuzzed against `tiktoken` | 20000000, ten million per encoding |
| Of those, compared token for token | 16661834 |
| Of those, round trip checked because they are not valid UTF-8 | 3338166 |
| Fuzzed again under the address sanitizer | 200000 |
| Divergences outstanding | 0 |
| Divergences found and fixed | 1 class, described below |
| Known divergences | None recorded, see docs/CORRECTNESS.md |

Read that table precisely. Encode and decode parity are both established,
over 110 MB of mixed text covering hundreds of languages and over 20 million
generated inputs including deliberately malformed UTF-8.

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

No benchmark numbers are published, because none have been measured. Knap has
nothing to benchmark until M3 lands an encoder.

When numbers do arrive they will follow the rules in
[docs/ROADMAP.md](docs/ROADMAP.md): encode throughput as the headline in both
MB/s and tokens/s, short string p50 and p99 latency, batch throughput, every
baseline run on the same machine by the author, and any baseline that wins
published in the same table with the same prominence.

Please treat the absence of a performance table as information. Beating the
best Rust implementations on raw merge speed is unlikely, and this project
does not depend on doing so.

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

There is no Python package to install yet. See M6 in
[docs/ROADMAP.md](docs/ROADMAP.md) for the state of that work.

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

## Supported vocabularies

| Vocabulary | State | Verified against |
| --- | --- | --- |
| `cl100k_base` | Encodes and decodes | 43.5 M tokens over 110 MB, all 100277 ids |
| `o200k_base` | Encodes and decodes | 36.9 M tokens over 110 MB, all 200019 ids |
| Hugging Face `tokenizer.json` | Planned, experimental | Nothing yet |

Vocabulary files are downloaded by a script rather than committed, so that no
licence question attaches to this repository and the exact source is recorded
rather than assumed.

## Limitations

- No BPE training. Encoding only.
- No offset mapping, meaning no character spans per token. It is valuable and
  it doubles the correctness surface, so it is deferred.
- No WordPiece, Unigram, or SentencePiece.
- No normalization pipelines. `cl100k_base` and `o200k_base` do not normalize,
  and adding a normalizer that is not needed would only create divergence.
- No chat templates and no GPU tokenization.
- A single document is not parallelized across threads. Chunking a byte stream
  and pre-tokenizing chunks independently can change the result, because a
  pattern match may span a chunk boundary. Batches are parallelized instead,
  which is where the throughput is and which is trivially correct.
- The Mojo ABI is not stable, so any Python binding is version locked and must
  be rebuilt for each toolchain release.
- No adversarial fuzzing has run yet, so parity is evidenced on realistic
  text rather than in general.
- No performance work has been done and no benchmarks are published.

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
