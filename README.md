<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap

Knap is a byte level Byte Pair Encoding tokenizer written in pure Mojo, built
to produce byte identical output to `tiktoken` on arbitrary input.

## Status

Knap is at milestone M0, scaffold. Read this section before anything else,
because most of what this README describes is planned rather than built.

| Component | State | Milestone |
| --- | --- | --- |
| Toolchain, standards gates, CI | Working | M0, complete |
| Vocabulary loading and decode | Working, decode parity verified | M1, complete |
| Pre-tokenizer, scalar | Working, boundary parity verified | M2, complete |
| BPE merge and encode | Working, encode parity verified | M3, complete |
| Differential fuzzing against `tiktoken` | Not started | M4 |
| SIMD classifier and benchmarks | Not started | M5 |
| Packaging and Python bindings | Not started | M6 |

Knap encodes and decodes today, and its output matches `tiktoken` exactly on
110 MB of mixed text. What is missing is the adversarial testing in M4, the
performance work in M5, and any packaging at all.

Nothing in this repository is a stub. Every file present is complete and
working, and the files listed above as not started are absent rather than
faked. See [docs/ROADMAP.md](docs/ROADMAP.md) for the full deferred list.

## Correctness

Correctness is the product. Speed is secondary. When a design choice trades
correctness for speed, correctness wins.

| Measure | Value |
| --- | --- |
| Tokens compared against `tiktoken` over 110 MB | 80457130, both encodings |
| Piece boundaries compared over the same corpus | 54326357 |
| Token ids decoded and compared | 300296, every id in both encodings |
| Unicode code points verified against an independent reference | 1114112 |
| Divergences found | 0 |
| Strings fuzzed against `tiktoken` | 0, M4 not started |
| Known divergences | None recorded, see docs/CORRECTNESS.md |

Read that table precisely. End to end encode parity **is** established, on
110 MB of mixed text covering hundreds of languages. That is real evidence
and it is the reason to take this library seriously.

It is also not the same claim as "correct in general". The corpus is natural
language, prose, and a generated hazard section. Adversarial input has a very
different distribution, and the fuzzing that covers it is milestone M4, which
has not run. Until it does, read the numbers above as verified on realistic
text rather than as verified everywhere.

The zeros are honest rather than placeholders. The methodology that will fill
them is in [docs/CORRECTNESS.md](docs/CORRECTNESS.md).

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
git clone <repository-url> knap
cd knap
uv sync --group dev
uv run mojo run tests/test_toolchain.mojo
```

With `pixi`, which pulls Mojo from the stable `max` conda channel:

```bash
git clone <repository-url> knap
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
