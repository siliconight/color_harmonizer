# Color Harmonizer (60/30/10) — Godot 4

A Godot 4 editor add-on that **scans your running game** against the
60/30/10 color-composition rule (60% dominant, 30% secondary, 10% accent),
scores it live, and can apply a tunable post-process grade to nudge the
palette toward better balance.

![icon](icon.svg)

---

## Quick start — see it working in 60 seconds

**The fastest way to try it: clone this repo and run the demo project.**

1. Clone the repo:
   ```bash
   git clone https://github.com/siliconight/color-harmonizer.git
   ```
2. Open **Godot 4**, click **Import**, and select the `project.godot` in the
   folder you just cloned.
3. Press **F5** (Run Project).
4. Look at the **Color 60/30/10** dock on the right. It fills in within a
   second — three color swatches, each role's measured % vs its target, a
   score out of 100, and a recommended grade.

That's the whole loop: the demo scene gives the analyzer something colorful
to read, and the dock reports what it found.

---

## Add it to your own game

You only need the add-on folder, not the demo.

1. Copy **`addons/color_harmonizer/`** into your project's `res://addons/`
   folder.
2. In Godot: **Project → Project Settings → Plugins**, and enable
   **Color Harmonizer (60/30/10)**.
3. Press **F5**. The dock updates live as you play.

Nothing touches your scene yet — by default the add-on only *measures*.

---

## Reading the dock

| What you see | What it means |
|---|---|
| Three swatches | The detected dominant / secondary / accent colors |
| `Dominant: 64% (target 60%)` | The role's share of the frame vs the 60/30/10 target |
| `Score: 78 / 100` | How close the balance is, blended with how well the accent pops |
| `Recommended grade: …` | Suggested strength for each correction (see below) |

The score is a **diagnostic**, not a target to force — see Caveats.

---

## Turning on the live grade

When you want the add-on to actually push the colors, switch on the filter.

**Easiest:** open `addons/color_harmonizer/color_analyzer.gd` and set
```gdscript
const AUTO_APPLY := true
```
Play again and the grade applies itself, using the recommended values.

**Manual (more control):** add a `HarmonizerFilter` node
(`addons/color_harmonizer/harmonizer_filter.gd`) to your scene and adjust its
exported **`strength`** (0–1, default 0.5). It also exposes a **split-tone**
(cool shadows / warm highlights) section — set `split_tone_amount` above 0 for
the classic graded look. Call `apply_report()` with a report if you want to
drive it yourself, or let the analyzer find and feed it.

---

## Profiles — supporting many games (and many looks)

The rule itself is **data**, not code. Every scoring and grading parameter lives
in a `ColorProfile` resource (`.tres`), so a different game — or a different
scene — just needs a different profile, never a fork.

Four presets ship in `addons/color_harmonizer/profiles/`:

| Profile | Feel | Harmony |
|---|---|---|
| `default` | Balanced 60/30/10 | Any |
| `moody` | Muted base, one strong accent, heavier grade | Complementary |
| `vibrant` | More of the frame counts as color, big accent headroom | Triadic |
| `mono-accent` | Analogous base palette with one punch | Analogous |

**Pick one project-wide:** edit `DEFAULT_PROFILE` in `color_analyzer.gd`, or
duplicate a `.tres`, tweak it in the inspector, and point to it.

**Switch per scene/biome/menu at runtime** for one game with many looks:
```gdscript
ColorHarmonizerAnalyzer.use_profile(load("res://.../moody.tres"))
```

A `ColorProfile` controls target ratios, neutral thresholds, salience weights,
the harmony rule, accent definition, score weights, cluster count, and grade
limits — all inspector-editable.

## Headless reports (CI / GEQA)

Audit the palette of every level without opening the editor. The batch runner
renders each scene offscreen, scores it, and writes JSON.

```bash
# Local (Windows):
./scripts/run_reports.ps1

# CI / Linux (xvfb gives Godot a real renderer headlessly):
./scripts/run_reports.sh
```

Or call it directly:
```bash
godot --path . res://addons/color_harmonizer/batch/batch.tscn -- \
  --scenes-dir=res://levels --profile=res://addons/color_harmonizer/profiles/moody.tres \
  --out=res://color_reports --min-score=60
```

| Arg | Purpose |
|---|---|
| `--scenes=a.tscn,b.tscn` | Explicit scene list |
| `--scenes-dir=res://levels` | Recursively scan a folder for `.tscn` |
| `--profile=PATH` | Which `ColorProfile` to score against |
| `--out=DIR` | Where to write reports (default `res://color_reports`) |
| `--min-score=N` | CI gate threshold |
| `--settle=FRAMES` | Frames to wait before capture (default 8) |
| `--size=WxH` / `--analysis=WxH` | Capture / analysis resolution |
| `--hide-nodes=A,B` | Hide these nodes (HUD) before capture |
| `--bake-lut=DIR` | Also bake each scene's grade to a LUT in DIR |
| `--fail-on-warn` | Exit non-zero if any scene trips a clash/overload rule |

**Exit codes:** `0` all passed · `1` a scene scored below `--min-score` ·
`2` a scene couldn't be captured. Wire that straight into a CI step.

> **Important:** capture needs a *real* renderer. Don't use Godot's `--headless`
> (dummy driver renders nothing) — on a headless CI box use `xvfb-run` as the
> helper script does.

**Output** is one `<scene>.json` per scene plus `_summary.json`. The schema is
stable and versioned (`color-harmonizer/report-1`), so **GEQA** (or any tool)
can read `_summary.json` for per-level pass/fail and the per-scene files for the
full palette breakdown. Each report embeds the scene path, profile, engine
version, and the same analysis block the live dock shows.

## Bake to a 3D LUT (fast path)

The live `HarmonizerFilter` runs per-pixel HSV math every frame — great for
*finding* a look. Once it's locked, **bake it to a 3D LUT**: the runtime cost
drops to one texture fetch, which matters most when several viewports are graded
at once (split-screen co-op).

**Bake during a CI/batch pass** — emits `<scene>.lut.res` + `<scene>.cube` per
scene, from each scene's recommended grade:
```bash
godot --path . res://addons/color_harmonizer/batch/batch.tscn -- \
  --scenes-dir=res://levels --bake-lut=res://luts --lut-size=33
```
Add `--grade=res://addons/color_harmonizer/lut/example_grade.tres` to bake one
fixed authored grade for every scene instead.

**Bake / preview in-engine:**
```gdscript
var lut := preload("res://addons/color_harmonizer/lut/lut_baker.gd")
var grade := load("res://addons/color_harmonizer/lut/example_grade.tres")
var tex := lut.bake_texture(grade, 33)   # ImageTexture3D
```

**Apply at runtime** (replaces `HarmonizerFilter` once the look is fixed):
```gdscript
var f := preload("res://addons/color_harmonizer/lut/lut_filter.gd").new()
add_child(f)
f.load_lut("res://luts/levels_arena.cube")   # or the .lut.res (faster load)
f.strength = 0.5
```

The `.cube` files interoperate with DaVinci Resolve / Premiere, and
`LutBaker.from_cube_file()` imports one back. A `GradeParams` resource holds the
frozen grade (author by hand, or `GradeParams.from_report()` from an analysis).

## Excluding the HUD

UI colors (health bars, crosshair, minimap) would otherwise count toward the
palette and skew the score. Three ways to keep them out:

**Best — capture a gameplay viewport (no flicker, free).** If you render your
world into a `SubViewport` with the HUD as a sibling, point the analyzer at it:
```gdscript
ColorHarmonizerAnalyzer.set_gameplay_viewport($GameViewport)
```
The HUD lives outside that viewport, so the capture is UI-free.

**Universal fallback — hide HUD nodes during capture (flickers).** Works for any
layout; briefly hides the listed nodes each capture, so keep it to dev sessions:
```gdscript
ColorHarmonizerAnalyzer.set_hud_nodes([$HUD, $Minimap])
```

**In headless batch (no flicker — it's offscreen):**
```bash
godot --path . res://addons/color_harmonizer/batch/batch.tscn -- \
  --scenes-dir=res://levels --hide-nodes=HUD,Minimap
```
(`--hide-nodes` paths are relative to each scene's root.)

## Clash & overload rules (what shouldn't go together)

Beyond the score, the analyzer flags specific "don't" rules as **warnings** —
shown in the dock, written into the JSON, and gateable in CI. They codify the
common ways color goes wrong:

| Warning | Fires when | Why |
|---|---|---|
| `saturation_overload` | too much of the frame is high-chroma | saturation should be a spotlight, not wallpaper |
| `too_many_hues` | too many competing saturated hue families | many unrelated hues read as chaos |
| `no_resting_space` | too few neutrals | the eye needs somewhere to rest / a focal point |
| `busy_everywhere` | high local contrast across the frame | contrast everywhere cancels the focal point |
| `saturated_clash` | a saturated near-complementary pair, both large | full-saturation complements vibrate |

Every threshold lives on the `ColorProfile` (Clash & overload limits group), so
a vibrant game and a moody one can disagree about what counts as "too much."

In CI, add `--fail-on-warn` to fail the build when any scene trips a rule:
```bash
godot --path . res://addons/color_harmonizer/batch/batch.tscn -- \
  --scenes-dir=res://levels --fail-on-warn
```

## Accent pop (does the "10" actually pop?)

An accent pops by **contrasting with what's around it**, not by being 10% of the
frame. So the analyzer measures the accent against its **local surround** on three
axes — value (`|ΔL|`), chroma (how much more saturated), temperature (warm/cool) —
and weights the result by **spatial isolation** (one focal blob vs scattered
confetti, via flood fill). A scattered accent never fully pops, however saturated.

The dock shows `Accent pop: NN/100 (weak: <axis>) · coverage NN%`, and the report
carries `accent_pop` plus the per-axis breakdown and the **weakest axis**. Two
warnings join the set: `accent_buried` (the accent exists but doesn't pop — with a
targeted fix for the failing axis) and `accent_oversized` (too big to read as an
accent). The grade can only raise the chroma axis; value, temperature and
isolation are reported as art/lighting actions. See `docs/accent-pop-spec.md`.

## Nuance zones (handling thousands of colors)

A 3D frame isn't painted with three flat colors — it's thousands of values, but
they live on **gradients** (lighting ramps, atmospheric falloff, material
variation). The tool manages that volume as a reduction cascade:

1. **Downsample** the frame (≈96×54) — millions of pixels → a few thousand.
2. **Salience-weight + drop neutrals** — keep what the eye actually weighs.
3. **Quantize** with k-means in OkLab — thousands of colors → a handful of
   centroids (bounded, resolution-independent).
4. **Merge into nuance zones** — a zone is a *chromatic family* that may span a
   lightness gradient, using a lightness-down-weighted OkLab distance. A wall
   that ramps shadow→light is one zone, not ten "colors".

Each zone carries a **spread** (how much gradient/nuance it holds) and a
**weight**. This separates two things that the flat-color model confused:

- **Nuance** (spread *within* a zone) — gradients, good, what makes 3D look rich.
- **Proliferation** (the *number* of zones) — too many unrelated families, bad
  (that's the `too_many_hues` rule).

So the dock reports `zones: N · nuance: X` alongside the roles — you're not
aiming for 3 flat colors, you're aiming for ~3 gradient *families* with rich
internal nuance. Tune `nuance_tolerance` (how wide a family is) and
`nuance_lightness_weight` (how much a value ramp counts as "still one color") per
profile.

## Physical grade (not a cheap filter)

The grade works the way light does, so it reads as *relighting* rather than a tint
overlay. Both the live shader and the baked LUTs share one pipeline
(`lut/color_grade.gd`, mirrored in `harmonize.gdshader`):

1. decode sRGB → **linear light**;
2. **white balance** by `kelvin` (Planckian locus) + `tint` (Duv), via a Bradford
   chromatic-adaptation matrix — neutrals re-balance like a real light source;
3. the role look in **OkLCh** — mute the dominant, enrich the accent, nudge the
   secondary's hue — perceptual, so lightness holds while chroma/hue move;
4. optional **path to white** — highlights desaturate toward white as they brighten,
   the way film and the eye behave (no neon clipping);
5. encode → sRGB, then optional split-tone and a **dither** pass to kill banding.

All of the new physics defaults to neutral/off (`kelvin` 6500, `path_to_white` 0),
so enabling it is opt-in. The engine still does the heavy lifting — for best results
run with `WorldEnvironment` AgX tonemapping and the **debanding** project setting on;
this grade is the *look* on top, not a replacement for the renderer. See
`docs/physical-grading.md`.

## How it works

- **`color_analyzer.gd`** (autoload, runs in the playing game) samples the
  viewport every 0.5s, downscales it, converts to **OkLab**, drops neutral
  pixels, **salience-weights** the rest (center / contrast / luminance),
  **k-means** clusters the palette, **merges clusters into perceptual nuance
  zones** (a zone is a chromatic family that may span a lightness gradient, so a
  lit-and-shadowed wall stays one "color"), assigns dominant/secondary/accent
  roles, scores it against the active **`ColorProfile`**, and sends the result to
  the editor. The score blends five things: **proportion** (60/30/10), **accent
  contrast**, **hue harmony**, **value contrast** (is there a value hierarchy?),
  and **saturation focus** (is chroma a spotlight or wallpaper?). 60/30/10 is one
  lever among several — value structure and saturation discipline usually move
  perceived quality more, which is why they're weighted in.
- **`debugger_plugin.gd` + `dock/harmonizer_dock.gd`** receive and display
  that report — which is why the dock can show *runtime* data even though the
  game is a separate process.
- **`harmonize.gdshader` + `harmonizer_filter.gd`** are the optional grade:
  mute the dominant so it recedes, push the accent's saturation so the 10%
  pops, nudge the secondary's hue toward a harmonious target.
- **`color_math.gd`** holds all the math with no engine dependencies, so it's
  easy to test and tune.

---

## Tuning

In `color_analyzer.gd`:

| Constant | Default | Purpose |
|---|---|---|
| `ANALYZE_W` / `ANALYZE_H` | 96 × 54 | Downscale size for analysis (bigger = slower, more precise) |
| `K` | 6 | Number of palette clusters |
| `INTERVAL` | 0.5 | Seconds between analyses |
| `SMOOTH` | 0.4 | Smoothing so the dock doesn't flicker (0 = none) |
| `AUTO_APPLY` | false | Auto-create and drive the live grade |

The recommendation constants inside `color_math.gd::analyze()` are honest
starting heuristics — tune them to your art direction.

---

## Caveats (read once)

- **A global grade can't change color *proportions*.** If geometry and
  textures make blue cover 75% of the frame, no full-screen filter makes it
  60% — proportion is a function of art and framing. The grade improves
  *perceived* balance, not literal pixel-area ratios.
- **Feedback loop in live mode:** the analyzer samples the already-graded
  frame. Smoothing keeps it stable, but for clean numbers measure with
  `AUTO_APPLY = false` first, then enable the grade.
- **Analysis is OkLab (accurate); the shader is HSV (cheap).** Deliberate
  tradeoff for a real-time pass.
- Works the same for 2D or 3D games — the demo is 2D only because it's the
  simplest thing to hand the analyzer.

---

## Project layout

```
color-harmonizer/
├── addons/color_harmonizer/   ← the add-on (copy this into your project)
│   ├── plugin.cfg / plugin.gd
│   ├── color_analyzer.gd      ← in-game analyzer (autoload)
│   ├── color_math.gd          ← OkLab + neutrals + salience + k-means + scoring
│   ├── color_profile.gd       ← ColorProfile resource (the rule, as data)
│   ├── profiles/*.tres        ← default / moody / vibrant / mono-accent
│   ├── harmonizer_filter.gd   ← live grade controller
│   ├── harmonize.gdshader     ← the grade shader
│   ├── lut/                   ← 3D-LUT bake + fast runtime apply + .cube I/O
│   ├── batch/                 ← headless CI / GEQA report + LUT bake runner
│   ├── debugger_plugin.gd     ← runtime→editor channel
│   └── dock/harmonizer_dock.gd← the diagnostic dock
├── demo/                      ← clone-and-run demo + level_a/level_b
├── scripts/                   ← run_reports.ps1 / run_reports.sh
├── project.godot              ← demo project (plugin pre-enabled)
└── README.md
```

---

## Pushing this to GitHub

```bash
cd color-harmonizer
git init
git add .
git commit -m "Color Harmonizer (60/30/10) v0.1.0"
git branch -M main
git remote add origin https://github.com/siliconight/color-harmonizer.git
git push -u origin main
```

---

## License

MIT (see `LICENSE`). The copyright holder is set to GabagoolStudios as a
default — change it or the license to whatever you prefer.

Targets Godot 4.7 (works on 4.x). · v0.10.0 · GabagoolStudios
