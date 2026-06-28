# Changelog

## v0.10.0
- **Physical grade — filter → grade.** The live shader and the LUT baker now grade
  in **linear light** and do role ops in **OkLCh** instead of HSV, so hue/chroma
  moves stay perceptual and smooth. Shared math lives in `lut/color_grade.gd`
  (mirrored in `harmonize.gdshader`) so the live preview and baked LUTs match.
  - **White balance** is now physical: `kelvin` on the Planckian locus + `tint`
    (Duv), applied as a Bradford chromatic-adaptation matrix — re-balances neutrals
    like a real light, instead of an RGB tint overlay. 6500 K = neutral.
  - **Path to white**: optional filmic highlight desaturation (`path_to_white` /
    `path_to_white_start`) — bright colors roll off toward white like film/cones.
  - **Dithering** added to both display shaders (live + LUT apply), just before
    8-bit quantization, to kill gradient banding.
  - Role hues are now OkLab hue angles (radians); `GradeParams.from_report` and the
    filter compute them from role colors. New params default to neutral/off, so the
    prior look is preserved until you turn the physics on. Implements
    `docs/physical-grading.md`.

## v0.9.0
- **Accent pop — first spatial measurement.** Instead of judging the accent
  globally, the analyzer now measures it against its **local surround** across
  value, chroma and temperature, and weights the result by **spatial isolation**
  (flood-fill blobs — a scattered accent can't fully pop). The score's accent
  term now uses `accent_pop` instead of the old global chroma contrast.
  - Report adds `accent_pop`, `pop_value`, `pop_chroma`, `pop_temperature`,
    `pop_isolation`, `accent_coverage`, `accent_blobs`, `accent_pop_axis`
    (the weakest axis).
  - New warnings: `accent_buried` (exists but doesn't pop, with a per-axis fix)
    and `accent_oversized` (too large to read as an accent).
  - New `ColorProfile` group "Accent pop"; dock shows pop + weakest axis +
    coverage. Implements `docs/accent-pop-spec.md`.
  - Calibration pending on real frames: `surround_radius`, the `*_ref` scales,
    and the warmth proxy (`a + b`).

## v0.8.0
- **Nuance zones.** A 3D frame isn't 3 flat colors — it's thousands on
  gradients. Clusters now merge into perceptual *zones*: a zone is a chromatic
  family that may span a lightness gradient (lighting), using a
  lightness-down-weighted OkLab distance so a material ramping from shadow to
  light stays one zone instead of fracturing into many "colors".
  - Per-zone **spread** (RMS perceptual radius) measures gradient richness;
    reported per role and as an overall **nuance** value.
  - **zone_count** (true number of perceptual families) reported and shown in
    the dock. Roles and the `too_many_hues` rule now operate on zones.
  - `nuance_tolerance` and `nuance_lightness_weight` are per-profile.

## v0.7.0
- **Clash & overload rules** — codified "what shouldn't go together" as explicit
  warnings (not just a score), surfaced in the dock, JSON reports, and CI:
  - `saturation_overload` — too much of the frame is high-chroma.
  - `too_many_hues` — too many competing saturated hue families.
  - `no_resting_space` — too few neutrals; nowhere for the eye to rest.
  - `busy_everywhere` — high local contrast across the frame; no value rest.
  - `saturated_clash` — a saturated near-complementary pair that vibrates.
- All thresholds are per-profile (`ColorProfile` → Clash & overload limits).
- Batch `--fail-on-warn` makes CI fail when any scene raises a warning; summary
  and console list per-scene warnings.

## v0.6.0
- **Scores "better," not just "balanced."** Two structural metrics added to the
  blend (profile-weighted):
  - **Value contrast** — interpercentile (P10..P90) lightness range; rewards a
    real value hierarchy over a muddy mid-tone frame. Value reads before hue.
  - **Saturation focus** — fraction of the salient frame that's high-chroma;
    rewards chroma used as a spotlight and penalizes over-saturation.
- **Split-tone grade** — cool shadows / warm highlights (multiply shadows,
  screen highlights), the classic "looks graded" move. Available on the live
  `HarmonizerFilter`, in `GradeParams`, and baked into LUTs. Off by default.
- Dock shows the value/saturation sub-scores; JSON reports include them.
- Preset profiles tuned on the new axes (moody favors value contrast,
  vibrant tolerates more saturation, mono-accent rewards a single pop).

## v0.5.0
- **HUD exclusion** so UI colors no longer poison the palette:
  - Live analyzer capture modes: `ROOT` (default), `GAMEPLAY_VIEWPORT`
    (capture a SubViewport you render gameplay into — UI-free, no flicker,
    recommended), and `ROOT_HIDE_HUD` (hide listed HUD nodes during capture;
    universal but flickers). Set via `set_gameplay_viewport()` / `set_hud_nodes()`.
  - Batch runner `--hide-nodes=A,B` hides those nodes before each offscreen
    capture (no flicker, since nothing is displayed).

## v0.4.0
- **3D LUT bake:** `GradeParams` resource + `lut/lut_baker.gd` evaluate a frozen
  grade across an RGB cube into an `ImageTexture3D` and/or an Adobe/Resolve
  `.cube` file. Bake math mirrors `harmonize.gdshader`.
- **Fast runtime path:** `lut/lut_filter.gd` + `lut_apply.gdshader` apply the
  grade as a single 3D-texture fetch — much cheaper than the per-pixel HSV grade,
  and scales cleanly across multiple viewports (split-screen).
- **Bake in CI:** batch runner `--bake-lut=DIR` writes a `.lut.res` + `.cube`
  per scene (from each scene's recommended grade, or a fixed `--grade=PATH`).
  `--lut-size` controls cube resolution (default 33).
- `.cube` import via `LutBaker.from_cube_file()` for round-tripping with NLEs.

## v0.3.0
- **Headless batch reports:** `batch/batch_runner.gd` renders each scene into an
  isolated SubViewport, scores it, and writes one JSON report per scene plus a
  `_summary.json`. Designed for CI gating and to feed GEQA.
- CI-friendly exit codes (0 pass / 1 below --min-score / 2 capture failed) and a
  stable, versioned JSON schema (`color-harmonizer/report-1`, `summary-1`).
- Args: `--scenes`, `--scenes-dir`, `--profile`, `--out`, `--min-score`,
  `--settle`, `--size`, `--analysis`.
- Helper scripts (`scripts/run_reports.ps1`, `scripts/run_reports.sh` with xvfb)
  and two demo levels (good + failing) to exercise the gate.

## v0.2.0
- **Profile-driven:** all scoring/grading params now live in a `ColorProfile`
  resource (.tres). Ships 4 presets: default, moody, vibrant, mono-accent.
  Supports N games as N profiles, and per-scene swapping via `use_profile()`.
- **Neutral separation:** greys/near-black/near-white are excluded from the
  60/30/10 math and reported separately, so a big floor no longer counts as
  "the dominant color."
- **Salience weighting:** pixels are weighted by center-bias, local contrast,
  and luminance instead of raw area, so the score reflects visual pull.
- **Harmony scoring:** score now blends proportion + accent contrast + hue
  harmony (per the profile's rule).
- Grade recommendations are clamped to per-profile limits. Warm-start clusters
  via EMA smoothing for stability.

## v0.1.0
- Initial scaffold.
- In-game analyzer: viewport capture → OkLab → k-means → role assignment → 60/30/10 score.
- Editor dock fed over the debugger channel (live while the game runs).
- Optional post-process grade (CanvasLayer + HSV shader) driven by the analysis.
- Demo project for clone-and-run.
