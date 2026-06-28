extends Node
## Runs in the PLAYING game (registered as an autoload by the plugin).
## Samples the screen, scores it against a ColorProfile, reports to the editor
## dock, and (optionally) drives the post-process filter.

const ColorMath := preload("res://addons/color_harmonizer/color_math.gd")
const HarmonizerFilter := preload("res://addons/color_harmonizer/harmonizer_filter.gd")
const DEFAULT_PROFILE := "res://addons/color_harmonizer/profiles/default.tres"

# --- Tunables ---
const ANALYZE_W := 96         # downscale width for analysis
const ANALYZE_H := 54         # downscale height
const INTERVAL := 0.5         # seconds between analyses
const SMOOTH := 0.4           # EMA factor (0 = none, 1 = frozen)
const AUTO_APPLY := false     # true => auto-create the filter and grade live

## How to grab the frame so the HUD/UI doesn't poison the palette:
##  ROOT             - whole composited frame (default; includes HUD)
##  GAMEPLAY_VIEWPORT- a SubViewport you render gameplay into (HUD-free, no flicker)
##  ROOT_HIDE_HUD    - root frame with HUD nodes hidden for the capture (flickers)
enum CaptureMode { ROOT, GAMEPLAY_VIEWPORT, ROOT_HIDE_HUD }

var profile: ColorProfile
var capture_mode := CaptureMode.ROOT
var gameplay_viewport: SubViewport = null
var hud_nodes: Array[Node] = []
var _accum := 0.0
var _busy := false
var _filter: CanvasLayer = null
var _smoothed: Dictionary = {}


func _ready() -> void:
	if profile == null:
		profile = load(DEFAULT_PROFILE) if ResourceLoader.exists(DEFAULT_PROFILE) else ColorProfile.new()
	if AUTO_APPLY:
		_filter = HarmonizerFilter.new()
		_filter.strength = profile.grade_strength
		add_child(_filter)


## Recommended HUD exclusion: render gameplay into a SubViewport and point here.
## HUD lives outside it, so the capture is UI-free with zero extra cost or flicker.
func set_gameplay_viewport(vp: SubViewport) -> void:
	gameplay_viewport = vp
	capture_mode = CaptureMode.GAMEPLAY_VIEWPORT


## Universal fallback: hide these nodes (HUD CanvasLayers/Controls) during capture.
## Works for any layout but causes a brief flicker at the capture cadence — keep
## it to diagnostic dev sessions, not shipped grading.
func set_hud_nodes(nodes: Array) -> void:
	hud_nodes.clear()
	for n in nodes:
		if n is Node:
			hud_nodes.append(n)
	capture_mode = CaptureMode.ROOT_HIDE_HUD


func set_capture_mode(m: CaptureMode) -> void:
	capture_mode = m


## Swap profiles at runtime — e.g. call this from a scene/biome/menu for a
## different look without forking the tool.
func use_profile(p: ColorProfile) -> void:
	if p == null:
		return
	profile = p
	if _filter:
		_filter.strength = p.grade_strength
	_smoothed.clear()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < INTERVAL or _busy:
		return
	_accum = 0.0
	_capture_and_analyze()


func _capture_and_analyze() -> void:
	_busy = true
	var img := await _grab_image()
	_busy = false
	if img == null:
		return

	img.resize(ANALYZE_W, ANALYZE_H, Image.INTERPOLATE_BILINEAR)
	var report := ColorMath.analyze(img, profile)
	if report.is_empty():
		return

	report = _smooth(report)

	if EngineDebugger.is_active():
		EngineDebugger.send_message("color_harmonizer:report", [report])

	if _filter:
		_filter.apply_report(report)


func _grab_image() -> Image:
	match capture_mode:
		CaptureMode.GAMEPLAY_VIEWPORT:
			if gameplay_viewport == null:
				return await _grab_root()
			await RenderingServer.frame_post_draw
			var t := gameplay_viewport.get_texture()
			return t.get_image() if t else null
		CaptureMode.ROOT_HIDE_HUD:
			return await _grab_root_hide_hud()
		_:
			return await _grab_root()


func _grab_root() -> Image:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		return null
	var t := vp.get_texture()
	return t.get_image() if t else null


func _grab_root_hide_hud() -> Image:
	var restore: Array = []
	for n in hud_nodes:
		if is_instance_valid(n) and "visible" in n:
			restore.append([n, n.visible])
			n.visible = false
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var t := vp.get_texture() if vp else null
	var img: Image = t.get_image() if t else null
	for pair in restore:
		if is_instance_valid(pair[0]):
			pair[0].visible = pair[1]
	return img


func _smooth(report: Dictionary) -> Dictionary:
	if _smoothed.is_empty():
		_smoothed = report
		return report
	for role in ["dominant", "secondary", "accent"]:
		_smoothed[role]["weight"] = lerp(report[role]["weight"], _smoothed[role]["weight"], SMOOTH)
		_smoothed[role]["chroma"] = lerp(report[role]["chroma"], _smoothed[role]["chroma"], SMOOTH)
		_smoothed[role]["hue"] = report[role]["hue"]
		_smoothed[role]["rgb"] = report[role]["rgb"]
		_smoothed[role]["spread"] = report[role]["spread"]
	_smoothed["neutral_ratio"] = lerp(report["neutral_ratio"], _smoothed["neutral_ratio"], SMOOTH)
	_smoothed["score"] = lerp(report["score"], _smoothed["score"], SMOOTH)
	_smoothed["zone_count"] = report["zone_count"]
	_smoothed["nuance"] = report["nuance"]
	_smoothed["accent_pop"] = lerp(report["accent_pop"], _smoothed.get("accent_pop", report["accent_pop"]), SMOOTH)
	_smoothed["pop_value"] = report["pop_value"]
	_smoothed["pop_chroma"] = report["pop_chroma"]
	_smoothed["pop_temperature"] = report["pop_temperature"]
	_smoothed["pop_isolation"] = report["pop_isolation"]
	_smoothed["accent_coverage"] = report["accent_coverage"]
	_smoothed["accent_blobs"] = report["accent_blobs"]
	_smoothed["accent_pop_axis"] = report["accent_pop_axis"]
	_smoothed["proportion_score"] = report["proportion_score"]
	_smoothed["accent_score"] = report["accent_score"]
	_smoothed["harmony_score"] = report["harmony_score"]
	_smoothed["value_contrast_score"] = report["value_contrast_score"]
	_smoothed["saturation_focus_score"] = report["saturation_focus_score"]
	_smoothed["warnings"] = report["warnings"]
	_smoothed["hue_families"] = report["hue_families"]
	_smoothed["busy_fraction"] = report["busy_fraction"]
	_smoothed["recommend"] = report["recommend"]
	return _smoothed
