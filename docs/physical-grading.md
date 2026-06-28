# Physical color grading — making the grade feel like light, not a filter

Research note. The goal: understand *why* cheap filters look cheap, in terms of the
physics of light and color, and turn that into concrete things the tool can bake in
so its grading reads as "relighting" rather than "a sheet of colored cellophane."

## The physics, briefly

- **Light is a spectrum.** A real color is a continuous spectral power distribution
  (SPD) across ~400–700 nm. The eye samples that spectrum with three cone types;
  "RGB" is just a 3-number stand-in for that integral (tristimulus). Anything we do
  in RGB is an approximation of a spectral truth.
- **Two consequences that matter for grading:**
  1. **Light math is linear.** Real light adds and multiplies in *linear* radiance,
     not in gamma-encoded sRGB. Doing grade math in sRGB is doing physics in the
     wrong units — it's the root cause of muddy darks, hue twists, and harsh clips.
  2. **Brightness and color are coupled.** As a colored light gets intense, cones
     saturate and we perceive it as *whiter* (a bright saturated bulb looks white at
     the core). Film does the same: silver-halide desaturates as more light hits it.
     So in reality, **highlights lose saturation.** Cheap filters keep saturation
     cranked all the way into the highlights → neon, electric, fake.

## Why cheap filters look cheap (the diagnosis)

Every "cheap" tell is a physical wrongness:
- math done in gamma sRGB instead of linear light → hue skews, mud;
- hard channel clipping at 0/1 → blown highlights, posterized gradients;
- saturation held constant into highlights → neon, "video" look;
- "warm" = an orange RGB multiply over everything → tints the neutrals, cellophane;
- 8-bit math with no dithering → visible banding in skies/gradients.

## Seven things to bake in (ranked by impact)

### 1. Grade in linear light, tonemap to display
The single biggest fix. Decode sRGB→linear, do exposure/white-balance/saturation
math there, then apply a display transform. In Godot this substrate already exists
(the renderer is linear; `WorldEnvironment` tonemaps on the way out). The tool's
post-process should match: operate before/with the tonemap, not naively on the
final sRGB pixels.

### 2. Do grade moves in OkLCh, not HSV
The current live filter grades in HSV. HSV "value" and "saturation" are perceptually
crude — shifting hue or saturation in HSV changes apparent brightness and skews
color. **OkLCh** (the polar form of OkLab, which the analyzer already uses) lets you
change hue while holding lightness, and desaturate without darkening. This alone is
a large "cheap → quality" jump and reuses math already in `color_math.gd`.

### 3. Filmic "path to white" — desaturate highlights toward white
This is the most important *look* tell. Modern film tone maps (AgX, ACES, Tony
McMapface) push colors toward white as they brighten, mimicking film and cone
saturation, so bright saturated areas roll off creamy instead of clipping to neon.
A naive **per-channel** curve instead produces the "Notorious 6" hue skews (reds →
orange, etc.) in the highlights. Bake a gentle path-to-white into the grade/LUT:
above a luminance threshold, lerp chroma → 0 along a smooth shoulder. Pair it with a
**toe** so deep shadows don't crush. Off by default / tunable, since a stylized PS1
look (your Patina aesthetic) may *want* flatter response.

### 4. White balance as Kelvin on the Planckian locus + chromatic adaptation
Replace the split-tone "warm/cool" RGB push with a physically real model:
- **Color temperature (Kelvin)** moves the white point along the **Planckian locus**
  — the path a glowing black body traces (≈1900K candle, 3200K tungsten, 5600K
  daylight, 7500K+ shade). Shifts *along* the locus read as natural light; shifts
  *off* it (green/magenta) read as unnatural — that off-axis amount is **tint (Duv)**.
- Apply the shift as a **chromatic adaptation transform** (Bradford or CAT02): map
  to LMS cone space, scale by the ratio of source/target white, map back. This
  re-balances neutrals like a real lighting change or camera white balance, instead
  of tinting everything uniformly. Expose `kelvin` + `tint` on the profile/GradeParams
  rather than raw RGB offsets — it's the difference between "relight the scene" and
  "drop an orange gel over the lens."

### 5. Kill banding for smooth gradients / nuance
"Smoothing and nuance" is largely a banding-and-precision problem:
- keep intermediate work in float / HDR (don't round-trip through 8-bit mid-grade);
- **dither** right before the final 8-bit quantize — and, per Godot's own pipeline,
  dither in the **nonlinear (display-encoded)** space immediately before quantization,
  not in linear. Ordered (Bayer) or blue-noise dither breaks bands into texture the
  eye reads as smooth.
- bake LUTs at higher resolution (e.g. 33³ → 45³) and sample with **tetrahedral**
  interpolation rather than trilinear to avoid LUT-introduced banding.
- Recommend users enable Godot's **debanding** project setting as the substrate.

### 6. Shape saturation by luminance and existing chroma
Instead of one global saturation knob: gently enrich mid-tones, restrain highlights
(feeds #3) and the deepest shadows, and boost low-chroma less than mid-chroma (avoid
over-saturating already-vivid areas). Note the **Helmholtz–Kohlrausch effect**:
saturated colors read as brighter than their luminance suggests — another reason to
work in OkLCh, which models lightness more faithfully than HSV/luma.

### 7. (Frontier / optional) spectral-ish illuminant mixing
The "deep" version: treat an RGB color as a plausible reflectance spectrum, multiply
by the illuminant's SPD, re-integrate to RGB. This makes temperature shifts and color
mixing behave like real light (e.g. how a warm light actually interacts with a blue
surface). Overkill for a real-time gauge, but it's the genuine frontier of "magic"
color and worth knowing exists. A cheap proxy is #4 (CAT on the white point), which
captures most of the perceptual payoff for far less cost.

## How this maps to the tool

- **`harmonize.gdshader`** — port the live grade from HSV to **OkLCh in linear light**;
  add a path-to-white shoulder (#3) and luminance-shaped saturation (#6).
- **`GradeParams` / LUT baker** — add `kelvin` + `tint` (#4, via Bradford CAT) and the
  path-to-white params so **baked LUTs carry the same physics** as the live preview;
  raise default LUT size and switch to tetrahedral sampling (#5).
- **Final filter output** — add nonlinear-space dithering (#5).
- **Framing** — the engine does the heavy physics (linear pipeline, AgX tonemap,
  debanding). The tool's job is to **measure** (the analyzer) and apply a
  *physically-plausible look* on top — not to reimplement the renderer. Recommend
  AgX + debanding ON in `WorldEnvironment` as the substrate this grade sits on.

## Honest caveats

- This is shader + LUT math; it needs to run in Godot to verify (the standing debt —
  the tool still hasn't executed in a real editor).
- Don't out-engineer the engine: Godot 4.6 already exposes AgX (with `agx_white` /
  `agx_contrast`) and 3D debanding. Most "magic" comes from *using* that substrate
  correctly, then adding a tasteful OkLCh look — not from a heavier post stack.
- Every threshold here (shoulder start, dither strength, Kelvin range, sat curve) is
  eyeball-calibrated against real frames.

## Sources consulted
- AgX / path-to-white: darktable AgX docs; "Vibrant Colors with AgX" (CG Cookie);
  modelviewer.dev PBR Neutral Tone Mapping; Alex Tardif, *Tonemapping*.
- White balance physics: Wikipedia *Planckian locus*; Marcel Patek, *Color and
  Colorimetry*; darktable color-calibration docs; DPReview (Duv/tint).
- Banding / Godot: Godot 4.6 release notes; godot PR #107782 (dither in nonlinear
  space); Mikkel Gjøl, *Banding in Games* (loopit.dk).
- Perceptual space: Björn Ottosson, OkLab/OkLCh.
