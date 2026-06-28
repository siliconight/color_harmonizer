extends CanvasLayer
## Full-screen post-process. Add it to a scene, or let the analyzer create it
## (AUTO_APPLY). Reads a report and feeds the harmonize shader (physical grade).
##
## NOTE: if the analyzer samples the *graded* frame you create a feedback loop.
## The analyzer's EMA smoothing + small steps keep it stable, but for a clean
## separation, measure with AUTO_APPLY = false and enable the filter manually
## once you are happy with the recommended values.

const SHADER := preload("res://addons/color_harmonizer/harmonize.gdshader")

@export_range(0.0, 1.0) var strength := 0.5
@export var enabled := true
@export_range(0.05, 3.1416) var hue_falloff := 0.8

@export_group("White balance (physical)")
@export_range(2000.0, 12000.0) var kelvin := 6500.0   ## 6500 = neutral
@export_range(-1.0, 1.0) var tint := 0.0
@export_range(0.0, 1.0) var wb_strength := 1.0

@export_group("Path to white (filmic)")
@export_range(0.0, 1.0) var path_to_white := 0.0
@export_range(0.0, 1.0) var path_to_white_start := 0.75

@export_group("Split-tone (shadows/highlights)")
@export var shadow_tint := Color(0.42, 0.55, 0.85)
@export var highlight_tint := Color(1.0, 0.86, 0.62)
@export_range(0.0, 1.0) var split_tone_amount := 0.0
@export_range(0.0, 1.0) var split_balance := 0.5

@export_group("Banding")
@export_range(0.0, 2.0) var dither_strength := 1.0

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 128  # draw on top of everything
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = enabled


func apply_report(report: Dictionary) -> void:
	if not enabled or _mat == null:
		return
	var rec: Dictionary = report.get("recommend", {})
	_mat.set_shader_parameter("dominant_hue", ColorGrade.oklab_hue_of_color(_col(report["dominant"]["rgb"])))
	_mat.set_shader_parameter("secondary_hue", ColorGrade.oklab_hue_of_color(_col(report["secondary"]["rgb"])))
	_mat.set_shader_parameter("accent_hue", ColorGrade.oklab_hue_of_color(_col(report["accent"]["rgb"])))
	_mat.set_shader_parameter("secondary_target_hue", ColorGrade.oklab_hue_of_color(Color.from_hsv(rec.get("secondary_target_hue", 0.0), 0.9, 0.7)))
	_mat.set_shader_parameter("dominant_desat", rec.get("dominant_desat", 0.0))
	_mat.set_shader_parameter("accent_boost", rec.get("accent_boost", 0.0))
	_mat.set_shader_parameter("secondary_shift", rec.get("secondary_shift", 0.0))
	_mat.set_shader_parameter("hue_falloff", hue_falloff)
	_mat.set_shader_parameter("wb_matrix", ColorGrade.wb_basis(kelvin, tint, wb_strength))
	_mat.set_shader_parameter("path_to_white", path_to_white)
	_mat.set_shader_parameter("path_to_white_start", path_to_white_start)
	_mat.set_shader_parameter("shadow_tint", Vector3(shadow_tint.r, shadow_tint.g, shadow_tint.b))
	_mat.set_shader_parameter("highlight_tint", Vector3(highlight_tint.r, highlight_tint.g, highlight_tint.b))
	_mat.set_shader_parameter("split_tone_amount", split_tone_amount)
	_mat.set_shader_parameter("split_balance", split_balance)
	_mat.set_shader_parameter("dither_strength", dither_strength)
	_mat.set_shader_parameter("strength", strength)


func _col(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])
