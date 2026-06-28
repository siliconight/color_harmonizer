# Color Harmonizer (60/30/10) — Godot 4 add-on

> First-time setup and a clone-and-run demo are in the **repository root README**.
> This file is the technical reference for the add-on itself.

Scans your **running game** against the 60/30/10 color-composition rule
(60% dominant / 30% secondary / 10% accent), scores it, and can apply a
tunable post-process grade to push the palette toward better balance.

## Install
1. Copy the `color_harmonizer` folder into `res://addons/`.
2. **Project → Project Settings → Plugins →** enable *Color Harmonizer (60/30/10)*.
3. A **Color 60/30/10** dock appears on the right. Press **F5** to play —
   the dock updates live with role swatches, measured proportions vs target,
   a score, and a recommended grade.

## How it fits together
- **`color_analyzer.gd`** — autoload that runs in the playing game. Samples the
  viewport every 0.5s, downscales it, converts to OkLab, k-means clusters the
  palette, assigns dominant/secondary/accent roles, scores it, and sends a
  report to the editor over the debugger channel.
- **`debugger_plugin.gd` + `dock/harmonizer_dock.gd`** — receive and visualize
  the report in the editor.
- **`harmonizer_filter.gd` + `harmonize.gdshader`** — the optional live grade.

## Two modes
- **Diagnostic only (default).** `AUTO_APPLY = false` in `color_analyzer.gd`.
  The tool only measures and reports — nothing alters your scene.
- **Live harmonize.** Set `AUTO_APPLY = true`, or add a `HarmonizerFilter`
  node to your scene and call `apply_report()` yourself. Tune `strength`
  (default 0.5) on the filter.

## Things to know
- **A global grade cannot change color *proportions*** — that's a function of
  geometry, textures, and framing. The filter improves *perceived* balance
  (mute the dominant, harmonize the secondary, pop the accent), not literal
  pixel-area ratios. Use the score as a diagnostic, not a target to force.
- **Feedback loop:** in live mode the analyzer samples the already-graded
  frame. EMA smoothing keeps it stable, but for clean numbers measure with
  `AUTO_APPLY = false` first, then enable the filter.
- **Analysis uses OkLab** (perceptually accurate); the **shader uses HSV**
  (cheap, real-time). That's a deliberate tradeoff.
- The **recommendation constants** in `color_math.gd::analyze()` are starting
  heuristics — tune them to your art direction.

## Tunables (`color_analyzer.gd`)
`ANALYZE_W/H`, `K` (clusters), `INTERVAL`, `SMOOTH` (EMA), `AUTO_APPLY`.

v0.1.0 · GabagoolStudios
