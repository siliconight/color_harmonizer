extends CanvasLayer
## Cheap, fixed-grade post-process: applies a baked 3D LUT in one fetch.
## Use this instead of HarmonizerFilter once a look is locked — no per-frame
## analysis, no HSV math, and it scales cleanly across multiple viewports.

const SHADER := preload("res://addons/color_harmonizer/lut/lut_apply.gdshader")
const LutBaker := preload("res://addons/color_harmonizer/lut/lut_baker.gd")

@export var lut: Texture3D
@export_range(0.0, 1.0) var strength := 1.0
@export var enabled := true

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 128
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	_refresh()


func set_lut(t: Texture3D) -> void:
	lut = t
	_refresh()


func load_lut(path: String) -> void:
	if path.get_extension().to_lower() == "cube":
		lut = LutBaker.from_cube_file(path)
	elif ResourceLoader.exists(path):
		lut = load(path)
	_refresh()


## Bake a grade and apply it immediately (handy for previewing an authored grade).
func bake_and_apply(grade: GradeParams, size: int = 33) -> void:
	lut = LutBaker.bake_texture(grade, size)
	_refresh()


func _refresh() -> void:
	if _mat == null:
		return
	_rect.visible = enabled and lut != null
	if lut != null:
		_mat.set_shader_parameter("lut", lut)
		_mat.set_shader_parameter("lut_size", float(lut.get_width()))
		_mat.set_shader_parameter("strength", strength)
