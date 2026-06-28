# Spec: Spatial Accent-Pop Analyzer (target v0.9.0)

Status: design / not yet built. This is the analyzer's **first spatial measurement**;
everything before it is global-statistical.

## 1. Problem

The accent (the "10") pops because it **contrasts with what's immediately
around it**, not because it's 10% of the frame. Today `accent_score` is purely
global chroma-vs-dominant: it can't tell a red dot on a green field (pops) from a
red dot among reds (doesn't), because it never looks at *where* the accent sits.

We want a score that measures the accent against its **local surround** across the
axes that actually drive pop — value, chroma, temperature, and spatial isolation —
plus a **diagnosis** ("saturated but same value as the wall behind it") and a
**targeted recommendation**.

## 2. Definitions

- **Accent zone**: the accent role from the existing zone analysis (OkLab centroid,
  chroma, hue). Already computed.
- **Accent mask**: downsampled pixels whose OkLab distance to the accent centroid
  is within `accent_zone_tolerance` (reuse the nuance metric, lightness-down-weighted).
- **Local surround** of an accent pixel: the mean OkLab of *non-accent* pixels in a
  window of radius `surround_radius` around it. This is the "background it sits on."
- **Warmth scalar** (temperature proxy): `warmth = a + b` in OkLab (red + yellow
  positive, blue/green negative). Documented proxy; tunable later.

## 3. Algorithm

Operates on the existing downsampled (~96×54), salience-weighted OkLab buffers.

**A. Build the accent mask.** For each pixel, `in_accent = _zone_dist(lab,
accent_centroid, nuance_lightness_weight) <= accent_zone_tolerance`. Track accent
salience weight `accent_w` and `accent_coverage = accent_w / all_w`.

**B. Local surround.** For each accent pixel, average OkLab of non-accent pixels in
the `surround_radius` window (naive window is fine at this resolution; separable box
blur over the masked image is the optimization). If a pixel has no non-accent
neighbours, skip it.

**C. Per-pixel pop, three axes** (each normalized to 0..1 by a profile ref scale,
clamped):
- value:  `vΔ = |L_i − L_s|`                         → `/ pop_value_ref`
- chroma: `cΔ = max(0, C_i − C_s)`                    → `/ pop_chroma_ref`
- temp:   `tΔ = |warmth_i − warmth_s|`               → `/ pop_temp_ref`

Salience-weight and average each axis over the accent mask →
`pop_value`, `pop_chroma`, `pop_temperature` (each 0..1).

**D. Spatial isolation.** Flood-fill (4-connectivity) the accent mask into blobs.
- `accent_blobs` = component count.
- `pop_isolation = largest_blob_weight / accent_w` (1 = one focal blob, →0 = confetti).

**E. Composite.**
```
pop_contrast = (wv·pop_value + wc·pop_chroma + wt·pop_temperature) / (wv+wc+wt)
accent_pop   = pop_contrast * lerp(0.5, 1.0, pop_isolation)
```
(Isolation can only attenuate — a scattered accent never fully pops.)

## 4. Report additions

```
accent_pop            float 0..1   # composite — the headline
pop_value             float 0..1
pop_chroma            float 0..1
pop_temperature       float 0..1
pop_isolation         float 0..1
accent_coverage       float 0..1   # share of frame in the accent zone
accent_blobs          int
accent_pop_axis       string       # weakest axis: "value" | "chroma" | "temperature" | "isolation"
```
Keep the old `accent_score` (chroma-vs-dominant) as a sub-signal for continuity.
The 5-way score's accent term switches from `accent_score` to `accent_pop`
(weight `w_accent`, unchanged name).

## 5. Diagnosis → recommendation

Pick the lowest-scoring axis and emit advice (advisory; most fixes are art/lighting,
not gradeable):

| Weakest axis | Diagnosis | Recommendation |
|---|---|---|
| value | accent same lightness as its surround | put a value break behind it — darken the field or lighten/rim-light the accent |
| chroma | accent no more saturated than surround | raise accent saturation or desaturate the surround |
| temperature | accent same temperature as surround | make the accent warmer (or cooler) than the field |
| isolation | accent scattered across the frame | consolidate to one focal area |

Plus two warnings (join the existing clash/overload set):
- `accent_buried` — accent exists but `accent_pop < accent_pop_min`.
- `accent_oversized` — `accent_coverage > max_accent_coverage` (too big to read as accent).

The grade side can only help `chroma` (the harmonizer already boosts accent
chroma); value/temperature/isolation are reported as art/lighting actions.

## 6. Profile parameters (new `ColorProfile` group "Accent pop")

```
accent_zone_tolerance   0.12    # mask width around accent centroid
surround_radius         4       # px in analysis resolution
pop_value_weight        0.5     # axis weights (normalized)
pop_chroma_weight       0.3
pop_temp_weight         0.2
pop_value_ref           0.30    # normalization scales (OkLab units)
pop_chroma_ref          0.15
pop_temp_ref            0.20
accent_pop_min          0.35    # accent_buried threshold
max_accent_coverage     0.20    # accent_oversized threshold
min_accent_isolation    0.40    # advisory
```

## 7. Integration points

- `color_profile.gd` — add the "Accent pop" group above.
- `color_math.gd` — after roles: build mask, surround, pop axes, isolation, composite;
  add report fields; add `accent_buried` / `accent_oversized` warnings; switch the
  score's accent term to `accent_pop`. Add `_flood_fill_blobs()` helper.
- `color_analyzer.gd` — pass new fields through `_smooth` (no smoothing on the string/int).
- `dock/harmonizer_dock.gd` — show `pop XX (weak: <axis>)` and `accent NN%`.
- `_degenerate()` — add the new keys (pop 0, axis "value", coverage 0, blobs 0).
- README + CHANGELOG — document; bump to v0.9.0.
- Batch/JSON — automatic (fields ride the report); `--fail-on-warn` covers the new warnings.

## 8. Performance

One extra masked box-blur pass + one flood fill over ~5k px every 0.5s. Negligible.
Use the separable box blur if profiling ever shows it.

## 9. Edge cases

- No accent zone / `accent_coverage ≈ 0` → `accent_pop = 0`, no `accent_buried`
  (can't bury what isn't there); emit a soft "no distinct accent" note instead.
- accent == dominant (single-zone frame) → `accent_pop = 0`.
- accent everywhere (`coverage` high) → `accent_oversized`, low isolation.
- Accent pixels with no non-accent neighbours (accent fills the window) → excluded
  from the surround average (they're interior, not edges).

## 10. Acceptance tests (synthetic scenes, like the demo levels)

| Scene | Setup | Expected |
|---|---|---|
| pop_clean | small saturated red on a desaturated green field | high accent_pop; all axes decent |
| pop_value_fail | saturated accent, same L as background | low pop_value, weak="value", `accent_buried` |
| pop_chroma_fail | accent hue present but no more saturated than field | low pop_chroma, weak="chroma" |
| pop_scattered | accent color sprinkled as confetti | low pop_isolation, weak="isolation", many blobs |
| pop_oversized | accent color covers ~40% | `accent_oversized` |

Wire these as batch scenes; assert on `accent_pop`, `accent_pop_axis`, and warnings.

## 11. Open questions / calibration (need real frames)

- `surround_radius` and the three `*_ref` scales are eyeball-calibrated, not theoretical.
- Warmth proxy (`a + b`) is crude; revisit if temperature pop reads wrong.
- Whether `pop_isolation` should attenuate the composite or be a separate axis.
- Whether to weight pop by salience of the *surround* too (a pop in the periphery
  matters less than one at the focal center).

## 12. Out of scope (for now)

- True saliency/object detection (we approximate focal pull with center+contrast).
- Temporal pop (does the accent pop *over time* / motion). Possible later.
- Multi-accent frames (assumes one accent role).
