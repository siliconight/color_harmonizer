@tool
class_name GradeParams
extends Resource
## A frozen grade to bake into a 3D LUT. Mirrors the live harmonize shader so a
## baked LUT matches the real-time preview. The grade is PHYSICAL: white balance
## via Bradford chromatic adaptation, and the role look in OkLCh (linear light).
## Author one by hand, or derive it from a report with GradeParams.from_report().
##
## NOTE: role hues are OkLab hue ANGLES in radians (-PI..PI), not HSV 0..1.

@export_group("Roles (OkLab hue, radians)")
@export_range(-3.1416, 3.1416) var dominant_hue := 0.0
@export_range(-3.1416, 3.1416) var secondary_hue := 0.0
@export_range(-3.1416, 3.1416) var accent_hue := 0.0
@export_range(-3.1416, 3.1416) var secondary_target_hue := 0.0

@export_group("Adjustments")
@export_range(0.0, 1.0) var dominant_desat := 0.0   ## mute the base
@export_range(0.0, 1.0) var accent_boost := 0.0     ## enrich the accent (x chroma)
@export_range(0.0, 1.0) var secondary_shift := 0.0  ## rotate secondary hue
@export_range(0.05, 3.1416) var hue_falloff := 0.8  ## role band half-width (rad)

@export_group("White balance (physical)")
## Kelvin on the Planckian locus - 6500 is neutral; lower = warmer, higher = cooler.
@export_range(2000.0, 12000.0) var kelvin := 6500.0
## Green/magenta tint off the locus (Duv). 0 = on the locus.
@export_range(-1.0, 1.0) var tint := 0.0
@export_range(0.0, 1.0) var wb_strength := 1.0

@export_group("Path to white (filmic)")
## Desaturate highlights toward white as they brighten (film/cone behavior).
@export_range(0.0, 1.0) var path_to_white := 0.0    ## 0 = off
@export_range(0.0, 1.0) var path_to_white_start := 0.75

@export_group("Split-tone (shadows/highlights)")
@export var shadow_tint := Color(0.42, 0.55, 0.85)
@export var highlight_tint := Color(1.0, 0.86, 0.62)
@export_range(0.0, 1.0) var split_tone_amount := 0.0   ## 0 = off
@export_range(0.0, 1.0) var split_balance := 0.5

@export_group("Runtime")
@export_range(0.0, 1.0) var strength := 0.5


static func from_report(report: Dictionary) -> GradeParams:
	var g := GradeParams.new()
	var rec: Dictionary = report.get("recommend", {})
	if report.has("dominant"):
		g.dominant_hue = ColorGrade.oklab_hue_of_color(_col(report["dominant"].get("rgb", [0.5, 0.5, 0.5])))
		g.secondary_hue = ColorGrade.oklab_hue_of_color(_col(report["secondary"].get("rgb", [0.5, 0.5, 0.5])))
		g.accent_hue = ColorGrade.oklab_hue_of_color(_col(report["accent"].get("rgb", [0.5, 0.5, 0.5])))
	# The analyzer's target hue is an HSV-style hue 0..1; map it through a
	# representative saturated color to an OkLab angle so it matches role hues.
	g.secondary_target_hue = ColorGrade.oklab_hue_of_color(Color.from_hsv(rec.get("secondary_target_hue", 0.0), 0.9, 0.7))
	g.dominant_desat = rec.get("dominant_desat", 0.0)
	g.accent_boost = rec.get("accent_boost", 0.0)
	g.secondary_shift = rec.get("secondary_shift", 0.0)
	return g


static func _col(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])
