<!--
  SPDX-License-Identifier: EUPL-1.2
  Copyright 2026 Olaf Yunus Laitinen Imanov
  Part of the Knap project. See LICENSE for terms.
-->

# Knap Brand

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
| Document | `docs/BRAND.md` |
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

1. [Overview](#overview)
2. [Proportions](#proportions)
3. [Clear space](#clear-space)
4. [Colour](#colour)
5. [Minimum size](#minimum-size)
6. [Files](#files)
7. [File structure](#file-structure)
8. [Usage](#usage)
9. [Typeface licensing](#typeface-licensing)

---

## Overview

| | |
| --- | --- |
| Wordmark | knap |
| Type | Lowercase wordmark, text only, no icon |
| Typeface | Nordic Alternative, Regular |
| Case | Lowercase. The typeface is unicase, so lowercase letters render as geometric capital-like forms. |
| Tracking | Plus 0.10 em, which is plus 100 units on a 1000 unit em scale |
| Construction | Letterforms converted to outlines. The font is not required to display the logo. |

## Proportions

| Measurement | Value |
| --- | --- |
| Artboard | 3274 by 1093 pixels |
| Artboard aspect ratio | 2.995 to 1, near enough 3 to 1 |
| Wordmark ink area | 2829 by 649 pixels |
| Wordmark aspect ratio | 4.359 to 1 |
| Stroke weight | 47 pixels, which is 1.7 percent of the wordmark width and 7.2 percent of its height |

The wordmark height equals the cap height. Nothing ascends or descends past
it, which is why the mark sits optically level with a line of text beside it
without any manual nudging.

## Clear space

Minimum clear space on all four sides is 223 pixels at artboard scale, which
is 0.34 of the wordmark height, or roughly one third.

That margin is already built into every supplied file. Do not crop into it,
and add more where the layout allows.

To scale the rule to any size:

$$\text{clear space} = 0.34 \times \text{wordmark height}$$

## Colour

| Role | Hex | RGB | Print equivalent |
| --- | --- | --- | --- |
| Ink, primary | `#111111` | 17, 17, 17 | 100 percent K |
| Reverse, knockout | `#FFFFFF` | 255, 255, 255 | Paper, 0 percent |

The ink is a soft near black rather than pure `#000000`. It sits more
comfortably on screen and avoids the harshness of absolute black against
white.

Single colour mark. No gradients and no secondary colours. If a brand colour
is introduced later, apply it to the whole wordmark rather than to individual
letters.

## Minimum size

The typeface is hairline weight, so the strokes are the limiting factor.

| Medium | Minimum wordmark width | Resulting stroke |
| --- | --- | --- |
| Screen | 160 pixels | about 2.7 pixels |
| Screen, absolute floor | 120 pixels | about 2 pixels |
| Print | 25 mm, one inch | about 0.42 mm |
| Print, absolute floor | 15 mm | about 0.25 mm |

Below these the thin strokes break up, especially in print and on low density
screens.

Note that the supplied files include the clear space, so the wordmark is 86.4
percent of the rendered width. A file rendered at 240 pixels wide, which is
what every document in this repository except the README uses, puts the
wordmark at 207 pixels, comfortably above the floor. The README renders at
420 pixels, giving a 363 pixel wordmark.

For favicons and app icons at very small sizes, use a single letter or a
redrawn heavier variant rather than shrinking the full wordmark.

## Files

Each variant ships as a vector SVG and a raster PNG, in `docs/assets/`.

| Variant | SVG | PNG | Use |
| --- | --- | --- | --- |
| Ink on transparent | `knap_logo_transparent_black.svg` | `knap_logo_transparent_black.png` | Light backgrounds. Start here for new exports. |
| White on transparent | `knap_logo_transparent_white.svg` | `knap_logo_transparent_white.png` | Dark backgrounds |
| Ink on white | `knap_logo_black_on_white.svg` | `knap_logo_black_on_white.png` | Contexts requiring an opaque background |
| White on ink | `knap_logo_white_on_black.svg` | `knap_logo_white_on_black.png` | Inverse lockup |

All four SVGs share the same `viewBox="0 0 7449.2 2488.8"` and identical
outline geometry, so the variants are interchangeable. Each holds four
`<path>` elements, one per letter, inside a single `<g>`. Recolour by editing
the fill on that group. The two opaque variants carry a full bleed `<rect>`
behind it.

That structure was verified rather than taken on trust, because a brand
asset whose variants have drifted apart is a problem that shows up only after
publication.

All PNGs are 3274 by 1093 pixels, RGBA.

Prefer the SVG wherever the medium supports it. Every document in this
repository uses the vector files. For a raster size that is not supplied,
export from the SVG rather than upscaling a PNG.

## File structure

Each SVG is an `<svg>` element, one `<g>`, and four `<path>` elements, one
per letter. Nothing else. The two opaque variants add a single full bleed
`<rect>` behind the group, which is the whole of the 68 byte difference
between them.

| Variant | SVG bytes | PNG bytes |
| --- | --- | --- |
| Ink on transparent | 2279 | 123219 |
| White on transparent | 2279 | 105471 |
| Ink on white | 2347 | 147374 |
| White on ink | 2347 | 147166 |

Each PNG carries only the chunks a PNG needs: `IHDR`, the `IDAT` image data,
and `IEND`.

The files as originally exported carried an embedded content credential: a
signed provenance record in a `<metadata>` element in the vector files, and
an ancillary `caBX` chunk in the raster ones. It accounted for 7736 bytes of
every SVG, which were 10015 and 10083 bytes before, and a 5758 byte chunk,
5770 with its framing, in every PNG. It was removed. A brand asset in a
source repository should be the artwork and nothing else, and metadata that
travels with a logo into every place the logo is used is a liability rather
than a feature.

Anyone re-exporting these should check what their tool embeds before
committing the result.

## Usage

Do:

- Scale proportionally, from the SVG where possible.
- Use the white variant on dark or busy backgrounds.
- Keep the full clear space around the mark.
- Place it on flat, high contrast backgrounds.

Do not:

- Stretch, condense, or skew the proportions.
- Alter the letterspacing.
- Add outlines, shadows, glows, or bevels.
- Rotate the wordmark.
- Recolour individual letters.
- Place it over photography without a solid or heavily darkened backing panel.
- Recreate the mark by retyping it. The tracking will not match.

Where the mark appears inside this repository, and at what size, is fixed by
the Markdown document standard in [STYLE.md](STYLE.md) and checked by
`scripts/check_md_headers.py`.

## Typeface licensing

Nordic Alternative is a third party typeface. The letterforms have been
converted to outlines, so the logo files neither embed nor redistribute the
font, and nothing in this repository depends on it being installed.

Even so, confirm that the font's licence permits logo and commercial use
before deploying the mark publicly. Some free display faces restrict exactly
that, and the restriction usually applies to the mark rather than to the
outlines, so converting to outlines does not settle it.

This is an open item rather than a resolved one. It is recorded here so that
it is a decision somebody makes rather than one that is made by default at
publication.

---

## Document control

| Field | Value |
| --- | --- |
| Previous | [docs/STYLE.md](STYLE.md) |
| Next | [README.md](../README.md) |
| Index | [README.md](../README.md) |
| Revision | 1.0.0 |
| Last reviewed | 2026-09-08 |

Knap is licensed under the European Union Public Licence 1.2.
Copyright 2026 Olaf Yunus Laitinen Imanov, Metropolia University of Applied
Sciences. See [LICENSE](../LICENSE) for the full terms.

<!-- End of document: docs/BRAND.md -->
