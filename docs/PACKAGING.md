<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Packaging

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
| Document | `docs/PACKAGING.md` |
| Project | Knap, a pure Mojo byte level BPE tokenizer |
| Version | 1.0.0 |
| Status | Draft |
| Applies to | Knap 1.0.0, Mojo 1.0.0 |
| Author | Olaf Yunus Laitinen Imanov |
| ORCID | [0009-0006-5184-0810](https://orcid.org/0009-0006-5184-0810) |
| Affiliation | School of Information and Communication Technology, Metropolia University of Applied Sciences |
| Created | 2026-09-09 |
| Updated | 2026-09-10 |
| Licence | EUPL-1.2 |
| Website | <https://knap.lovable.app> |

---

## Contents

1. [What is prepared, and what is not](#what-is-prepared-and-what-is-not)
2. [Where the recipe lives](#where-the-recipe-lives)
3. [What the recipe declares](#what-the-recipe-declares)
4. [The recipe gate](#the-recipe-gate)
5. [Building the package](#building-the-package)
6. [What the package contains](#what-the-package-contains)
7. [The bill of materials](#the-bill-of-materials)
8. [CodeQL, which the channel requires](#codeql-which-the-channel-requires)
9. [The release checklist](#the-release-checklist)
10. [Consuming the package](#consuming-the-package)

---

## What is prepared, and what is not

Everything up to the point of publishing is in place. Publishing is not
done, and the difference is deliberate.

| Step | State |
| --- | --- |
| A recipe at the conventional path | Done |
| The recipe checked mechanically on every push | Done |
| A package acceptance test that runs against the installed artefact | Done |
| CodeQL scanning, which the channel requires of any package containing Python | Done |
| Building a `.conda` file locally | Done, and its own test run |
| A git tag and a GitHub release | **Not done** |
| A pull request to the modular-community repository | **Not done** |

The last two are one decision, not two, and the decision is the author's.
Publishing a package puts a name in a shared namespace and invites people to
depend on it, which is a different kind of act from writing the file that
would make it possible.

## Where the recipe lives

`conda.recipe/recipe.yaml`.

That path is a convention rather than a preference: `rattler-build` looks
there by default, and `rattler-build-action` expects it. The recipe used to
sit at `recipe/recipe.yaml`, which worked when it was built by hand and
would have needed a flag everywhere else.

Two files live in that directory:

| File | Role |
| --- | --- |
| `recipe.yaml` | The recipe |
| `smoke.mojo` | The package acceptance test, run by the recipe's test section |

## What the recipe declares

Four things in it are worth explaining, because each is a decision that
could reasonably have gone the other way.

**The source is a git URL and a full commit SHA, not a local path.** A path
source cannot be built by anyone but the author, and the modular-community
repository holds only the recipe, so it could not build the package at all.
A SHA is also reproducible in a way a branch or a tag is not: a tag can be
moved and a branch always is.

**The compiler is pinned exactly, and `pin_compatible` is not used.**
`pin_compatible` derives a version range from whatever resolved at build
time, and a range is exactly what a precompiled Mojo artefact cannot
honour. The compiler's own documentation says a `.mojoc` file may not be
compatible with another compiler version, and the ABI is explicitly not
stable. An exact pin turns that into a solver error at install time, which
is a better failure than a link error deep in somebody's build.

**The build writes into `$PREFIX/lib/mojo`.** That path is what makes the
package discoverable by the compiler without an include flag. Anything the
build script places under `$PREFIX` becomes part of the package.

**The package installs a binary as well as a library.** Counting tokens is
the most common thing anyone does with a tokenizer, and it should not
require writing a program. `knap count`, `encode`, `decode` and `vocab` all
work from a shell after `pixi add knap`.

## The recipe gate

`scripts/check_recipe.py` runs with the other standards gates on every push.
It needs no network and no build, and it checks the things that otherwise go
wrong quietly:

- the declared version agrees with `CITATION.cff`
- the pinned compiler agrees with `pixi.toml` and `pyproject.toml`
- the source revision is a full commit SHA that exists in this repository
- every file the test section names is next to the recipe
- the licence file it names exists
- the compiler pin is exact in all three requirement sections

It reads the subset of YAML the recipe uses and refuses anything else,
rather than skipping what it does not understand. A parser that skipped
would report a clean result for a recipe it never read.

`python scripts/check_recipe.py --selftest` plants each violation in turn
against the real recipe and confirms the gate rejects it. That is the same
standard every other gate in this repository is held to, and it runs in CI
next to the check itself.

## Building the package

Install `rattler-build`:

```bash
curl -fsSL https://pixi.sh/install.sh | sh
pixi global install rattler-build
```

Build from the repository root:

```bash
rattler-build build \
  --recipe conda.recipe/recipe.yaml \
  -c conda-forge \
  -c https://conda.modular.com/max \
  -c https://repo.prefix.dev/modular-community
```

The three channels are needed in that order: `conda-forge` for general
tooling, the Modular channel for `mojo-compiler`, and modular-community for
any Mojo package a recipe depends on. Knap depends on no community package
today and the channel is listed anyway, because a build that works only on
the author's channel list is a build that works only for the author.

The result appears under `output/`, named by platform and by a hash that
`rattler-build` derives from the build configuration. That directory is not
committed: the artefact is reproducible from the recipe, tied to one
platform and one compiler version, and a committed binary invites somebody
to use a stale one.

Run on 2026-09-09 with rattler-build 0.76.0, this produced:

| Field | Value |
| --- | --- |
| Artefact | `output/linux-64/knap-1.0.0-hb0f4dca_0.conda` |
| Size | 312.13 KiB |
| Compiler resolved | `mojo-compiler 1.0.0 release`, from the Modular channel |
| Run requirement recorded in the package | `mojo-compiler ==1.0.0` |

Then `rattler-build test --package-file` against that file, which installs
it into a fresh environment with nothing else from this repository present:

```text
+ test -f $PREFIX/lib/mojo/knap.mojoc
+ test -x $PREFIX/bin/knap
+ $PREFIX/bin/knap version
1.0.0
+ mojo run -I $PREFIX/lib/mojo smoke.mojo
knap package smoke test: import and decode both work
```

**One warning, recorded rather than silenced:** rattler-build reports
`Overlinking against "libc.so.6" for "bin/knap"`. The binary links the C
library without the recipe declaring a C compiler dependency, which is what
a Mojo build produces and what the linter has no rule for. It is left
visible rather than added to an allowlist, because an allowlist entry is a
claim that somebody looked and it was fine, and the honest state is that
nobody has yet needed it to be.

If a build fails, `rattler-build debug shell` opens a shell with `$PREFIX`
and `$SRC_DIR` set and the build environment activated.

## What the package contains

| Path | What it is |
| --- | --- |
| `$PREFIX/lib/mojo/knap.mojoc` | The precompiled library, discoverable without an include flag |
| `$PREFIX/bin/knap` | The command line tool |
| `$PREFIX/share/bash-completion/completions/knap` | Completions for bash |
| `$PREFIX/share/zsh/site-functions/_knap` | Completions for zsh |
| `$PREFIX/share/fish/vendor_completions.d/knap.fish` | Completions for fish |

`.mojoc` rather than `.mojopkg`. The latter extension is deprecated in Mojo
1.0.0 and warns.

The package does not contain a vocabulary. Vocabulary files are third party
data under their own terms, and bundling them would attach a licence
question to this package that fetching them does not. `knap help` lists the
five places the tool looks for one.

## The bill of materials

`sbom.cdx.json` at the repository root is a CycloneDX 1.6 document
describing what Knap is built from. It is generated by
`scripts/gen_sbom.py` out of `uv.lock` and `pyproject.toml`, and
`scripts/check_generated.py` refuses a commit where the committed copy has
drifted from the lock file, which is the same treatment the pattern
constants and the Unicode tables get.

The document answers one question: when the next advisory lands against some
package, does it reach a consumer through Knap. Its shape is the answer.

| Component set | Scope | Count |
| --- | --- | --- |
| The pinned Mojo toolchain and what it pulls in | `required` | 10 |
| Test and benchmark dependencies, present in the development environment and in nothing that ships | `excluded` | 23 |
| Anything the distributed artefact needs at run time | none, recorded as a property on the root component | 0 |

That last row is the one worth reading twice. The compiled library links no
Python, embeds no vocabulary, and calls out to nothing, so a consumer's
runtime exposure through Knap is empty rather than small. A bill of
materials that listed the compiler as though the compiled output still
depended on it would say the opposite, which is the most common way these
documents mislead, so the runtime set is stated outright instead of being
left to be inferred from an absence.

The document carries no timestamp and its serial number is derived from the
project name and version rather than drawn at random. Both are deliberate:
CycloneDX makes the timestamp optional, and a field that changed on every
run would make the drift check permanently red for no information.

## CodeQL, which the channel requires

The modular-community channel requires CodeQL scanning on the source
repository of any package containing a language other than Mojo, and a badge
for it in the README. Knap contains a good deal of Python: the generators,
the standards gates, the fuzzing driver, the benchmark baselines, and the
Python bindings.

`.github/workflows/codeql.yml` scans Python and the workflow files
themselves, on every push, on every pull request, and weekly. The weekly run
is the one that matters after the code stops changing, because an advisory
can be published against code that has not been touched.

**CodeQL has no Mojo analysis, so the library itself is not scanned by it.**
That is stated here rather than left for a reader to infer from a green
badge. The library is held to the address sanitizer instead, over generated
input and with no interpreter in the process, in `sanitize.yml`.

## The release checklist

Not yet executed. Each step is one the author decides to take.

1. Confirm the working tree is clean and every gate is green, including the
   110 MB corpus gates, which do not run on every push.
2. Set `version` and `date-released` in `CITATION.cff`.
3. Turn the `1.0.0, not yet released` heading in `CHANGELOG.md` into a dated
   release heading.
4. Set `context.version` in the recipe to match, and reset `build.number` to
   zero.
5. Commit those together, then set `source.rev` in the recipe to that
   commit's full SHA and commit again. `python scripts/check_recipe.py`
   refuses a revision that is not a commit in this repository, so this step
   cannot be half done.
6. Tag the release and push the tag.
7. Build the package locally and run its tests.
8. Open a pull request against the modular-community repository adding
   `recipes/knap/recipe.yaml`.
9. Archive the tagged release through Zenodo for a citable DOI, which pairs
   with the ORCID already in `CITATION.cff`.

Republishing the same version, for instance to pick up a new Mojo compiler
release, increments `build.number` instead of changing the version.

## Consuming the package

Once published, with `pixi`:

```toml
[workspace]
channels = [
  "https://conda.modular.com/max",
  "https://repo.prefix.dev/modular-community",
  "conda-forge",
]

[dependencies]
knap = "==1.0.0"
```

Then `import knap` in Mojo with no include flag, and `knap count` in a
shell.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/ROADMAP.md](ROADMAP.md) |
| Next | [docs/BRAND.md](BRAND.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-10 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/PACKAGING.md -->
