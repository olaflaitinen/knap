<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Toolchain Findings

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
| Document | `docs/TOOLCHAIN.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-10 |
| Updated | 2026-09-10 |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |

---

## Contents

1. [Why this document exists](#why-this-document-exists)
2. [The environment every finding was verified in](#the-environment-every-finding-was-verified-in)
3. [How to read a finding](#how-to-read-a-finding)
4. [Language and syntax](#language-and-syntax)
5. [Types and traits](#types-and-traits)
6. [Standard library and input output](#standard-library-and-input-output)
7. [Compilation, checking and tooling](#compilation-checking-and-tooling)
8. [Concurrency, packaging and distribution](#concurrency-packaging-and-distribution)
9. [Things that were assumed to be limits and are not](#things-that-were-assumed-to-be-limits-and-are-not)
10. [Which of these upstream already acknowledges](#which-of-these-upstream-already-acknowledges)
11. [The three that cost the most](#the-three-that-cost-the-most)
12. [Adding a finding](#adding-a-finding)

---

## Why this document exists

Mojo 1.0.0 is a young language with a large surface, a standard library that
is almost entirely marked unstable, and a body of tutorial material written
against versions that no longer parse. The gap between what a search engine
returns and what the pinned compiler accepts is wide enough that a working
day can disappear into a single line.

Knap is about eleven thousand lines of Mojo, written against one pinned
compiler, with every gate executed rather than assumed. That process
produced a byproduct: a list of assumptions that turned out to be false, each
one found by compiling and each one paid for once. This document is that
list, gathered in one place so that nobody has to pay for it twice.

Two rules govern what is allowed in here.

**Nothing is recorded from memory.** Every row was produced by a compiler
that refused something, or accepted something that was expected to be
refused. Where a finding can be pinned by an executable assertion it is,
and the row names the test.

**Findings that turned out to be wrong are recorded too**, in
[Things that were assumed to be limits and are not](#things-that-were-assumed-to-be-limits-and-are-not).
A compilation of toolchain limits that only ever grows is a compilation
nobody can trust, because the incentive is to add and never to check.

This is not a criticism of Mojo. Several of these are documented behaviour
that the reader simply had not read; several more are acknowledged on
Modular's own roadmap and are scheduled to change. Section
[Which of these upstream already acknowledges](#which-of-these-upstream-already-acknowledges)
separates the two, because a limit that is on someone's plan is a limit to
design around temporarily rather than to work around permanently.

---

## The environment every finding was verified in

| Property | Value |
| --- | --- |
| Mojo | 1.0.0, build `ed45d567` |
| Target triple | `x86_64-unknown-linux-gnu` |
| Target CPU | `znver1`, with AVX2 and without AVX-512 |
| Byte lane width | 32, read from `simd_width_of` rather than hardcoded |
| Host | Ubuntu 24.04.4 under WSL 2 |
| uv environment | Python 3.12.3, tiktoken 0.14.0, tokenizers 0.23.2, regex 2026.9.3 |
| pixi environment | Python 3.14.7, Mojo from the stable `max` channel |

The compiler is pinned exactly in `pyproject.toml`, `pixi.toml` and
`conda.recipe/recipe.yaml`, and a gate checks that all three agree. Mojo
guarantees source level stability only and states that its ABI is not
stable, so a floating version would invalidate both the committed benchmark
figures and any built Python extension.

---

## How to read a finding

Each row has three parts.

- **Assumption.** What a competent programmer arriving from Python, C++ or
  Rust would reasonably expect, or what older Mojo material states.
- **Reality in Mojo 1.0.0.** What the pinned compiler actually does.
- **Pinned by.** Where the repository holds the correct form, so that a
  future toolchain change surfaces as a failure rather than as a surprise.
  `tests/test_toolchain.mojo` is an executable assertion. A source file is
  the working spelling in context. Some rows have neither, because a compile
  error cannot be asserted from inside a program that has to compile.

---

## Language and syntax

| Assumption | Reality in Mojo 1.0.0 | Pinned by |
| --- | --- | --- |
| `fn` declares a function | Removed. `def` is the only function keyword and `fn` is a hard parse error. | Every `.mojo` file |
| `alias X = ...` is obsolete | Still valid. `comptime X = ...` also works and is preferred here as the forward compatible spelling. | `src/knap/ranks.mojo` |
| `@value` generates a constructor | Removed. Use `@fieldwise_init` and declare trait conformance explicitly. | `src/knap/tokenizer.mojo` |
| `@parameter if` selects a branch at compile time | Spelled `comptime if`. It is how one merge loop serves both the encoding and the counting path in `merge_piece_into[emit: Bool]`. | `src/knap/bpe.mojo` |
| Formatted strings are written `f"..."` | They are `t"..."`, and a t-string is not a `String`. `String(t"row {row} column {column}")` is the working form. | `tests/test_toolchain.mojo` |
| `len(s)` works on a `String` | Refused, and rightly: bytes, code points and grapheme clusters are three different answers. Use `s.byte_length()`, `len(s.codepoints())` or `len(s.graphemes())` and say which was meant. | `tests/test_toolchain.mojo` |
| A tuple literal can be iterated | `Tuple` does not implement `__iter__`, so `for x in (a, b, c)` is a compile error. Build a `List`. | Nothing, a compile error |
| Large collection literals are fine | A `List[UInt8]` literal of 34560 elements did not finish compiling in ten minutes. The same data as a `StaticString` compiled in 5.7 seconds, which is why the Unicode tables are strings. | `src/knap/pretokenize/unicode_tables.mojo` |

---

## Types and traits

| Assumption | Reality in Mojo 1.0.0 | Pinned by |
| --- | --- | --- |
| A type is printable once it is `Stringable` | There is no such declaration to conform to. Printing goes through `Writable`, and the method signature is `def write_to(self, mut writer: Some[Writer])`. | `src/knap/tokenizer.mojo` |
| `Copyable` is enough to assign a value | It is not. A small value struct that is passed around by assignment needs `ImplicitlyCopyable` as well, and the error names the missing conformance rather than the assignment. | `src/knap/tokenizer.mojo` |
| SIMD `a > b` yields a lane mask | It yields a single `Bool` for the whole vector. The per lane mask comes from `a.gt(b)`, and likewise `a.eq(b)`. | `tests/test_toolchain.mojo` |
| Mojo has module level global variables | It does not. A registry of loaded tokenizers at module scope is impossible, so exported state has to live inside an exported type. | `bindings/python/knap_ext.mojo` |
| Exporting a type to Python needs only the type | `PythonModuleBuilder.add_type` requires `Writable`, and reflection cannot derive it when a field is not itself `Writable`, so both `write_to` and `write_repr_to` must be written by hand. Without them the failure is a constraint error inside the bindings library that never names your type. | `bindings/python/knap_ext.mojo` |
| A method reached through the automatic downcast pointer can mutate | It cannot. Not a limit for Knap, where every tokenizer method is read only after loading, but it constrains what a binding can expose. | `bindings/python/knap_ext.mojo` |

---

## Standard library and input output

| Assumption | Reality in Mojo 1.0.0 | Pinned by |
| --- | --- | --- |
| Standard library imports are bare | They are not. `from std.sys import ...` resolves and `from sys import ...` does not. | Every `.mojo` file |
| `external_call` lives under `std.sys` | `std.sys.ffi` fails to resolve. The module is `std.ffi`. | `cli/main.mojo` |
| Compiler defines are read through a `std.defines` module | There is no such module, although the compiler's own `-D` help text points at one. The working spelling is `std.sys.is_defined["KEY"]()`, evaluated at compile time. | `src/knap/config.mojo` |
| `open(path, "r").read()` can read any file | Only text. Binary references need `read_bytes()`, and there is no `"rb"` mode. | `cli/main.mojo` |
| `Path.read_text()` returns the file's bytes as text | It applies universal newline translation, silently turning every carriage return and line feed pair into a single line feed. This produced a false failure in the M2 reference generator, where the scanner was right and the reference was wrong. Anything compared byte for byte must use `read_bytes()`. | `scripts/gen_pretoken_golden.py` |
| `/dev/stdout` can always be opened for writing | It cannot. Opening it works when standard output is a file or a terminal and fails when it is a pipe, because the path resolves through `/proc/self/fd` to a pipe node. `FileDescriptor(1).write_bytes` works everywhere. Reading `/dev/stdin` from a pipe does work, which is what makes the asymmetry easy to miss: the tool read piped input correctly and could not write piped output. | `cli/main.mojo` |
| Pointer arithmetic uses `+` | Deprecated. Use `unsafe_offset`. The same applies to `bitcast` and `load`, which are `unsafe_bitcast` and `unsafe_load`. All three still compile and only `--Werror` refuses them, so a deprecated spelling can pass a run and fail a build. | `src/knap/byte_map.mojo` |
| A growing `List` costs only time | It costs peak memory, and on this workload that is the larger number. Pre-sizing the output of `encode_ordinary` with `List[Int](capacity=estimated_tokens(len(data)))` removed 137.7 MB of peak resident memory and left the arithmetic at 7.99 bytes per token. | `src/knap/tokenizer.mojo` |

---

## Compilation, checking and tooling

| Assumption | Reality in Mojo 1.0.0 | Pinned by |
| --- | --- | --- |
| Building and running a module type checks all of it | It does not. Elaboration is lazy, so a name that resolves nowhere sits undetected inside a function nothing calls. A missing import in `scanner.mojo` survived both a build and a full run of a test that imports the module, and only `mojo doc` reported it. | `.github/workflows/ci.yml` |
| `mojo doc` accepts any well formed docstring | It requires a `Raises:` section on every function that can raise, and a docstring on every struct field and every `comptime` constant. Omitting one is an error rather than a warning. That strictness is what makes it the only whole module type check in this project, and why the docstring gate runs over every Mojo file rather than over the library alone. | `.github/workflows/ci.yml` |
| `mojo test` runs test files | The subcommand does not exist. A test file is a program whose `main` drives `TestSuite.discover_tests[__functions_in_module()]().run()`. | Every `tests/test_*.mojo` |
| `mojo format` has a check mode | It does not. It rewrites in place, so CI runs it and then checks that the working tree is unchanged. | `.github/workflows/ci.yml` |
| The formatter leaves generated files alone | It does not. It splits long string literals across lines, so a generator must format its own output or the drift check reports a permanent failure. | `scripts/gen_unicode_tables.py` |
| `--Werror` and `--warn-on-unstable-apis` compose | They do not. Together the build fails, because essentially the whole standard library is unstable. CI runs them as two jobs, one gating and one reporting. | `.github/workflows/ci.yml` |
| A file may be named after the package it imports | A module's name is its file stem, so `cli/knap.mojo` would declare a module called `knap` and the compiler refuses it: a module cannot import itself. The entry point is `cli/main.mojo` and only the built binary is called `knap`. | `cli/main.mojo` |

---

## Concurrency, packaging and distribution

| Assumption | Reality in Mojo 1.0.0 | Pinned by |
| --- | --- | --- |
| Mojo 1.0.0 has working task parallelism | It does not, for this workload. There is no `parallelize`, and `TaskGroup` aborts at runtime with `LLVM ERROR: destroying a non-available AsyncValue is not implemented`. Batch encoding is single threaded because nothing else is available, which is a fact rather than a design choice. | `docs/ARCHITECTURE.md` |
| `mojo precompile` produces a `.mojopkg` | That extension is deprecated in 1.0.0 and warns. The current artefact is `.mojoc`. | `conda.recipe/recipe.yaml` |
| Mojo has a native package manager | It does not. Libraries are distributed as conda packages, built with rattler-build. | `docs/PACKAGING.md` |
| A conda recipe may reference files above its own directory | `license_file: ../LICENSE` fails. The path must resolve inside the recipe directory. | `conda.recipe/recipe.yaml` |
| Mojo ships a Windows wheel | It does not. Windows development goes through WSL, and there is no native Windows build. | `README.md` |
| The ABI is stable enough to ship a built extension | It is explicitly not. Any Python binding is locked to the exact toolchain that built it and has to be rebuilt for each release, which is why no wheel is published. | `bindings/python/README.md` |

---

## Things that were assumed to be limits and are not

Each of these was written down as a limitation, doubted, and then checked.
All four were the reader's error rather than the compiler's, and they are
kept here because a list that only records defeats is a list that quietly
stops being accurate.

| What was assumed | What is actually the case | Pinned by |
| --- | --- | --- |
| Mojo cannot read Linux pseudo files such as `/proc/self/status` | It can. A probe returned minus one and the conclusion drawn was that the runtime refuses `/proc`. The probe was wrong: the file reads correctly through the ordinary file interface. These files report a size of zero, so the test asserts on the content rather than on the length, and would catch a change that started trusting the size. | `tests/test_toolchain.mojo` |
| File handles cannot seek, so a benchmark must read a whole corpus to slice it | They can. `handle.seek(0, 2)` returns the file size and `handle.read_bytes(n)` reads a prefix, which is what took the benchmark harness from 282.8 MB of peak memory down to 95.6 MB. | `tests/test_toolchain.mojo` |
| `alias` was removed along with `fn` and `@value` | It was not. Both spellings work, and `comptime` is preferred here as a style choice rather than a necessity. | `src/knap/ranks.mojo` |
| Counting tokens without building the list would be faster than encoding | It is not, and this one is not about the toolchain at all. The counting path saves memory and no measurable time, which is recorded next to the numbers in [docs/BENCHMARKS.md](BENCHMARKS.md) rather than quietly dropped. | `docs/BENCHMARKS.md` |

---

## Which of these upstream already acknowledges

Every row above was found by compiling. Reading Modular's published roadmap
afterwards is worth the five minutes, because it separates a limit that is
acknowledged and scheduled from one that might be a local mistake. The rows
below are drawn from the roadmap for Mojo 1.0.0 at
<https://mojolang.org/docs/roadmap/>, read on 2026-09-09, and quoted rather
than copied.

| Finding | Upstream status |
| --- | --- |
| No working task parallelism, so batch encoding is single threaded | Phase 2 lists first class `async` support as not started. Acknowledged and scheduled. |
| `mojo test` does not exist | Phase 2 lists the testing framework as in progress. |
| The benchmark harness is written by hand, statistics included | Phase 2 lists the benchmarking framework as in progress. |
| No native package manager | Phase 2 lists packaging and package management as not started. |
| `@value` is gone and `comptime if` replaces `@parameter if` | Phase 1 lists attribute macros as in progress, replacing ad hoc constructs such as `@parameter` and `@value` with traits. |
| Almost the whole standard library is unstable | Phase 1 lists stabilization markers as complete, which is what makes `--warn-on-unstable-apis` able to answer at all. |
| Nothing enforces module boundaries, so the underscore convention is all there is | Phase 2 lists access control features, including `private`, as not started. |

Two consequences follow, and both are decisions to defer rather than work
to do now. The single threaded batch path should be revisited when `async`
lands rather than reworked around today's absence, and the hand written test
and benchmark harnesses should be expected to be replaced rather than
extended.

---

## The three that cost the most

Ordered by the time they took to find, not by how interesting they are.

**Lazy elaboration.** A missing import inside a function nothing called
survived a build, a run, and a full test suite. Nothing in the ordinary
build path looks at code that is never elaborated, so a whole module can
contain a name that resolves nowhere and still ship. The fix was not a code
change but a gate change: `mojo doc` elaborates everything, so the docstring
gate is also the type checker, and it runs over every Mojo file in the
repository rather than over the library alone.

**The SIMD comparison.** `a > b` on two SIMD vectors compiles and returns a
single `Bool`. In a classifier that expects a lane mask, the wrong form
still compiles inside some expressions and silently computes something else,
which is the worst possible failure mode: no error, no warning, wrong
output. `tests/test_toolchain.mojo` pins `a.gt(b)` with an executable
assertion so that a future toolchain change surfaces as a test failure
rather than as a divergence in the encoder.

**Newline translation in `Path.read_text`.** A reference generator compared
scanner output against a file read through `read_text`, and the comparison
failed on inputs containing a carriage return. The scanner was right. The
reference was wrong, because `read_text` had already replaced every carriage
return and line feed pair with a single line feed. Anything compared byte
for byte reads through `read_bytes`.

The common thread is that none of the three announced itself. All three
produced a green build and a wrong answer, which is the category that gates
exist for.

---

## Adding a finding

A row belongs here when all three of the following hold.

1. It was observed against the pinned compiler, by running something. A
   recollection, a forum post, or a plausible inference is not a finding.
2. It contradicts what a careful reader would otherwise assume, so the row
   saves somebody a search.
3. It is stated with the working alternative, not only with what fails.

Where the correct form can be asserted from inside a running program, add
the assertion to `tests/test_toolchain.mojo` and name the test in the
Pinned by column. Where it cannot, because the wrong form does not compile,
name the source file that carries the working spelling in context.

If a finding is later shown to be false, move it to
[Things that were assumed to be limits and are not](#things-that-were-assumed-to-be-limits-and-are-not)
rather than deleting it. The record of having been wrong is the part that
makes the rest of the document worth reading.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/ARCHITECTURE.md](ARCHITECTURE.md) |
| Next | [docs/METHODOLOGY.md](METHODOLOGY.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-10 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/TOOLCHAIN.md -->
