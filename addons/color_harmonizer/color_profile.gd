@tool
class_name ColorProfile
extends Resource
## A data-driven description of "good color balance" for one game, scene, or mood.
## Save variants as .tres files and assign per project or per scene — the scorer
## reads everything from here, so supporting N games means N profiles, not N forks.

enum Harmony { ANY, ANALOGOUS, COMPLEMENTARY, TRIADIC, SPLIT_COMPLEMENTARY }

@export_group("Target ratios")
@export_range(0.0, 1.0) var target_dominant := 0.6
@export_range(0.0, 1.0) var target_secondary := 0.3
@export_range(0.0, 1.0) var target_accent := 0.1

@export_group("Neutral separation")
## Pixels below this OkLab chroma are neutral (greys) and excluded from the color story.
@export_range(0.0, 0.2) var neutral_chroma_max := 0.04
## Pixels darker than this OkLab lightness are treated as neutral shadow.
@export_range(0.0, 1.0) var neutral_value_min := 0.08
## Pixels brighter than this are treated as neutral highlight.
@export_range(0.0, 1.0) var neutral_value_max := 0.96

@export_group("Salience weighting")
## Weight pixels by where the eye actually looks, not raw area.
@export var use_salience := true
@export_range(0.0, 1.0) var center_bias := 0.5      ## center pixels count more
@export_range(0.0, 1.0) var contrast_bias := 0.5    ## high local-contrast pixels count more
@export_range(0.0, 1.0) var luminance_bias := 0.2   ## brighter pixels count slightly more

@export_group("Harmony")
@export var harmony_rule: Harmony = Harmony.ANY

@export_group("Accent")
## Accent must be at least this much more chromatic than the dominant to "pop".
@export_range(0.0, 0.5) var accent_min_contrast := 0.08

@export_group("Value structure")
## Interpercentile (P10..P90) lightness range below this reads as flat/muddy.
@export_range(0.0, 1.0) var value_contrast_min := 0.12
## ...and at/above this it scores full marks (a clear value hierarchy).
@export_range(0.0, 1.0) var value_contrast_good := 0.35

@export_group("Saturation focus")
## OkLab chroma above this counts as a "saturated" pixel.
@export_range(0.0, 0.5) var chroma_hi_threshold := 0.12
## Ideal fraction of the (salient) frame that is saturated — chroma as a
## spotlight, not wallpaper. Higher fractions are penalized.
@export_range(0.0, 1.0) var target_hi_chroma_frac := 0.12

@export_group("Accent pop")
## Pixels within this OkLab distance of the accent centroid count as the accent.
@export_range(0.0, 0.5) var accent_zone_tolerance := 0.12
## Window radius (analysis-resolution px) for the local surround.
@export_range(1, 12) var surround_radius := 4
## Axis weights for the pop composite (normalized internally).
@export_range(0.0, 1.0) var pop_value_weight := 0.5
@export_range(0.0, 1.0) var pop_chroma_weight := 0.3
@export_range(0.0, 1.0) var pop_temp_weight := 0.2
## Normalization scales (OkLab units) — a full-strength contrast on each axis.
@export_range(0.01, 1.0) var pop_value_ref := 0.30
@export_range(0.01, 1.0) var pop_chroma_ref := 0.15
@export_range(0.01, 1.0) var pop_temp_ref := 0.20
## accent_buried fires below this pop; accent_oversized above this coverage.
@export_range(0.0, 1.0) var accent_pop_min := 0.35
@export_range(0.0, 1.0) var max_accent_coverage := 0.20

@export_group("Nuance zones")
## A "zone" is a chromatic family that may span a lightness gradient (lighting).
## Clusters closer than this OkLab distance merge into one zone.
@export_range(0.0, 0.5) var nuance_tolerance := 0.10
## How much lightness counts toward zone distance. Below 1 so a material that
## ramps from shadow to light (big ΔL, small Δhue) stays a single zone.
@export_range(0.0, 1.0) var nuance_lightness_weight := 0.3

@export_group("Score weights")
@export_range(0.0, 1.0) var w_proportion := 0.5
@export_range(0.0, 1.0) var w_accent := 0.25
@export_range(0.0, 1.0) var w_harmony := 0.25
@export_range(0.0, 1.0) var w_value_contrast := 0.2
@export_range(0.0, 1.0) var w_saturation_focus := 0.15

@export_group("Clustering")
@export_range(2, 12) var clusters := 6

@export_group("Grade limits")
@export_range(0.0, 1.0) var max_dominant_desat := 0.6
@export_range(0.0, 1.0) var max_accent_boost := 0.6
@export_range(0.0, 1.0) var max_secondary_shift := 0.4
@export_range(0.0, 1.0) var grade_strength := 0.5

@export_group("Clash & overload limits")
## Emit warnings when the frame breaks these "don't" rules.
@export var enable_warnings := true
## Too many competing saturated hue families reads as chaos.
@export_range(1, 8) var max_hue_families := 4
## The eye needs somewhere to rest — flag too few neutrals.
@export_range(0.0, 1.0) var min_neutral_ratio := 0.12
## Saturation overload ceiling (fraction of frame that's high-chroma).
@export_range(0.0, 1.0) var max_hi_chroma_frac := 0.4
## Per-pixel local contrast above this counts as "busy".
@export_range(0.0, 1.0) var busy_contrast_threshold := 0.4
## Contrast-everywhere ceiling — too much busy area means no value rest.
@export_range(0.0, 1.0) var max_busy_fraction := 0.55
## A saturated pair at a near-complementary interval (this hue-distance band),
## both above this weight, vibrates (simultaneous contrast).
@export_range(0.0, 0.5) var clash_min_weight := 0.2
@export_range(0.0, 0.5) var clash_band_lo := 0.4
@export_range(0.0, 0.5) var clash_band_hi := 0.5
