<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Python Bindings

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="../../docs/assets/knap_logo_transparent_white.svg">
    <img src="../../docs/assets/knap_logo_transparent_black.svg"
         alt="Knap" width="240">
  </picture>
</p>

| Field | Value |
| --- | --- |
| Document | `bindings/python/README.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-08 |
| Updated | 2026-09-08 |
| Licence | EUPL-1.2 |

---

## Contents

1. [What this is](#what-this-is)
2. [Building](#building)
3. [Using it](#using-it)
4. [The ABI caveat](#the-abi-caveat)
5. [Design notes](#design-notes)

---

## What this is

A native CPython extension module built from Mojo, plus a thin Python package
over it.

The project plan treated this as an open question, with a `ctypes` wrapper
over a flat C surface as the fallback if native export turned out not to
exist. It does exist: Mojo 1.0.0 builds real extension modules through
`PythonModuleBuilder`. So this takes the native path, and the `capi`
directory the plan sketched was never needed.

Read the honest caveat in [The ABI caveat](#the-abi-caveat) before depending
on this.

## Building

The extension is not committed, because a compiled artefact is valid only for
the exact toolchain that produced it. Build it from the repository root:

```bash
uv sync --group dev
uv run python bindings/python/build.py
```

That writes `bindings/python/build/knap_ext.so` and a stamp file recording
the toolchain version. Running it again with a different toolchain warns and
rebuilds.

Then run the tests, which check the bindings against `tiktoken` rather than
trusting the Mojo side:

```bash
uv run python scripts/fetch_vocabs.py
uv run python bindings/python/tests/test_bindings.py
```

## Using it

```python
import sys
sys.path.insert(0, "bindings/python")

from knap_py import Tokenizer

knap = Tokenizer.cl100k_base("tests/fixtures/vocabs/cl100k_base.tiktoken")

ids = knap.encode_ordinary("Knap tokenizes 1234 bytes.")
print(ids)
print(knap.decode(ids))
print(knap.n_vocab)
```

All seven encodings have a named constructor, and each takes the path to the
vocabulary file that encoding is stored in. Three of them are stored under
another encoding's name, so the path is not always the obvious one:

| Constructor | Vocabulary file |
| --- | --- |
| `Tokenizer.cl100k_base(path)` | `cl100k_base.tiktoken` |
| `Tokenizer.o200k_base(path)` | `o200k_base.tiktoken` |
| `Tokenizer.o200k_harmony(path)` | `o200k_base.tiktoken` |
| `Tokenizer.p50k_base(path)` | `p50k_base.tiktoken` |
| `Tokenizer.p50k_edit(path)` | `p50k_base.tiktoken` |
| `Tokenizer.r50k_base(path)` | `r50k_base.tiktoken` |
| `Tokenizer.gpt2(path)` | `r50k_base.tiktoken` |

`knap_py.tokenizer.VOCABULARY_FILE` holds that mapping if you would rather
look it up than write it out. The general constructor,
`Tokenizer(path, name)`, takes whatever path it is given, because a caller
with a vocabulary somewhere else has a reason for it.

Special tokens follow the same rule as the Mojo API. Nothing is permitted by
default, so a marker in the input is refused:

```python
knap.encode("before <|endoftext|> after", ["<|endoftext|>"])

knap.encode("before <|endoftext|> after")
```

The first returns token ids with the marker as its own id. The second raises,
which is the intended behaviour: encoding a marker that arrived in untrusted
input would let that input inject a control token into a prompt.

| Method | Returns | Notes |
| --- | --- | --- |
| `encode_ordinary(text)` | `list[int]` | Never raises on content. Markers become ordinary characters. |
| `encode(text, allowed_special)` | `list[int]` | Raises on any special token not in the allowed set. |
| `decode_bytes(ids)` | `bytes` | Exact bytes, which may not be valid UTF-8. |
| `decode(ids)` | `str` | Convenience. Raises if the bytes are not valid UTF-8. |
| `n_vocab` | `int` | One past the highest assigned id. Not the count of decodable ids. |

## The ABI caveat

**The Mojo ABI is not stable, and this extension is version locked to the
toolchain that built it.**

That is not a caution about future breakage. It means an extension built with
Mojo 1.0.0 is not valid for any other Mojo release, nothing checks it at
import time, and a mismatch will not necessarily fail in a way that points
back here.

The practical consequences:

- The built `.so` is not committed and is not distributed.
- Every consumer builds it locally, against their own toolchain.
- There is no wheel on PyPI, and there should not be one until the ABI is
  stable, because a wheel is a promise that the binary inside it will keep
  working.

`build.py` records the toolchain version beside the library so a stale build
can at least be recognised.

## Design notes

Three properties of Mojo 1.0.0 shaped the extension, and all three were found
by compiling rather than by reading documentation. They are recorded here
because the next person to touch this file will hit them too.

| Finding | Consequence |
| --- | --- |
| There are no global variables | A module level registry of loaded tokenizers is impossible. State lives in an exported type instead. |
| `add_type` requires `Writable` | Both `write_to` and `write_repr_to` must be written out by hand, because reflection cannot derive them when a field is not itself `Writable`. The failure without them is a constraint error deep inside the bindings library that never names your type. |
| A method reached through the auto downcast pointer cannot mutate | Not a limitation here: every tokenizer method is read only after loading. |

One interface decision is worth defending. `decode_bytes` returns `bytes` and
`decode` is a separate convenience that can raise. Byte level BPE genuinely
can decode to a partial UTF-8 sequence, whenever a caller decodes a slice of a
longer token list, so a single method returning `str` would have to make a
lossy choice on the caller's behalf. Substituting replacement characters
there is exactly how a round trip quietly stops being a round trip.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/ROADMAP.md](../../docs/ROADMAP.md) |
| Next | [README.md](../../README.md) |
| Index | [README.md](../../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-08 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../../LICENSE) for the full terms.

<!-- End of document: bindings/python/README.md -->
