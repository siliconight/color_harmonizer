extends Node
## Headless / CI batch analyzer.
##
## Renders each scene into an isolated SubViewport, scores it against a
## ColorProfile, and writes one JSON report per scene plus a summary.
## Exit codes:  0 = all passed   1 = a scene scored below --min-score
##              2 = a scene could not be captured (likely no real renderer)
##
## Launch (needs a REAL renderer — on headless CI wrap with xvfb-run, NOT --headless):
##   godot --path . res://addons/color_harmonizer/batch/batch.tscn -- \
##     --scenes-dir=res://demo --profile=res://addons/color_harmonizer/profiles/default.tres \
##     --out=res://color_reports --min-score=55
##
## Args: --scenes=a.tscn,b.tscn  --scenes-dir=res://levels  --profile=PATH
##       --out=DIR  --min-score=N  --settle=FRAMES  --size=WxH  --analysis=WxH

const ColorMath := preload("res://addons/color_harmonizer/color_math.gd")
const LutBaker := preload("res://addons/color_harmonizer/lut/lut_baker.gd")
const DEFAULT_PROFILE := "res://addons/color_harmonizer/profiles/default.tres"
const SCHEMA_REPORT := "color-harmonizer/report-1"
const SCHEMA_SUMMARY := "color-harmonizer/summary-1"

var capture_size := Vector2i(384, 216)
var analysis_size := Vector2i(96, 54)
var settle_frames := 8
var min_score := 0.0
var out_dir := "res://color_reports"
var profile_path := DEFAULT_PROFILE
var bake_lut_dir := ""        # if set, bake each scene's grade to a LUT here
var lut_size := 33
var grade_path := ""          # optional fixed GradeParams to bake instead of per-scene
var hide_node_paths := PackedStringArray()  # HUD nodes to hide before capture
var fail_on_warn := false     # exit non-zero if any scene raises clash/overload warnings


func _ready() -> void:
	# The live autoload would also poll the viewport; silence it in batch.
	var al := get_node_or_null("/root/ColorHarmonizerAnalyzer")
	if al:
		al.set_process(false)

	var args := _parse_args(OS.get_cmdline_user_args())
	_apply_args(args)

	var scenes := _resolve_scenes(args)
	if scenes.is_empty():
		push_error("[color-harmonizer] No scenes. Use --scenes=a.tscn,b.tscn or --scenes-dir=res://levels")
		print("[color-harmonizer] No scenes given. See --help in the README.")
		get_tree().quit(2)
		return

	await _run(scenes)


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var d := {}
	for a in argv:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		if body.contains("="):
			var kv := body.split("=", true, 1)
			d[kv[0]] = kv[1]
		else:
			d[body] = "true"
	return d


func _apply_args(args: Dictionary) -> void:
	if args.has("profile"):
		profile_path = args["profile"]
	if args.has("out"):
		out_dir = args["out"]
	if args.has("settle"):
		settle_frames = int(args["settle"])
	if args.has("min-score"):
		min_score = float(args["min-score"])
	if args.has("size"):
		capture_size = _parse_size(args["size"], capture_size)
	if args.has("analysis"):
		analysis_size = _parse_size(args["analysis"], analysis_size)
	if args.has("bake-lut"):
		bake_lut_dir = args["bake-lut"]
	if args.has("lut-size"):
		lut_size = int(args["lut-size"])
	if args.has("grade"):
		grade_path = args["grade"]
	if args.has("hide-nodes"):
		hide_node_paths = args["hide-nodes"].split(",", false)
	if args.has("fail-on-warn"):
		fail_on_warn = true


func _parse_size(s: String, fallback: Vector2i) -> Vector2i:
	var parts := s.to_lower().split("x")
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return fallback


func _resolve_scenes(args: Dictionary) -> Array:
	var scenes: Array = []
	if args.has("scenes"):
		for s in args["scenes"].split(","):
			var t: String = s.strip_edges()
			if t != "":
				scenes.append(t)
	if args.has("scenes-dir"):
		scenes.append_array(_scan_dir(args["scenes-dir"]))
	return scenes


func _scan_dir(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		push_error("[color-harmonizer] Could not open dir: " + dir_path)
		return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if d.current_is_dir():
			if entry != "." and entry != "..":
				out.append_array(_scan_dir(full))
		elif entry.get_extension().to_lower() == "tscn":
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()
	return out


func _run(scenes: Array) -> void:
	var profile: ColorProfile = load(profile_path) if ResourceLoader.exists(profile_path) else ColorProfile.new()
	var profile_name := profile_path.get_file().get_basename()

	var sv := SubViewport.new()
	sv.size = capture_size
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var records: Array = []
	var any_capture_fail := false
	var any_below := false
	var any_warn := false

	var fixed_grade: GradeParams = null
	if grade_path != "" and ResourceLoader.exists(grade_path):
		fixed_grade = load(grade_path)
	if bake_lut_dir != "":
		DirAccess.make_dir_recursive_absolute(bake_lut_dir)

	for path in scenes:
		var rec := await _analyze_scene(sv, path, profile, profile_name)
		records.append(rec)
		if not rec["captured"]:
			any_capture_fail = true
		else:
			if float(rec["analysis"].get("score", 0.0)) < min_score:
				any_below = true
			if (rec["analysis"].get("warnings", []) as Array).size() > 0:
				any_warn = true
		if bake_lut_dir != "" and rec["captured"]:
			var grade: GradeParams = fixed_grade if fixed_grade != null else GradeParams.from_report(rec["analysis"])
			var stem := path.trim_prefix("res://").replace("/", "_").get_basename()
			LutBaker.save(grade, lut_size, bake_lut_dir.path_join(stem + ".lut.res"), bake_lut_dir.path_join(stem + ".cube"))
			print("[color-harmonizer] baked LUT: %s" % bake_lut_dir.path_join(stem + ".cube"))

	_write_reports(records, profile_name)
	_print_summary(records)

	var code := 0
	if any_capture_fail:
		code = 2
	elif any_below or (fail_on_warn and any_warn):
		code = 1
	print("[color-harmonizer] Done. Exit code %d." % code)
	get_tree().quit(code)


func _analyze_scene(sv: SubViewport, path: String, profile: ColorProfile, profile_name: String) -> Dictionary:
	var base := {
		"schema": SCHEMA_REPORT,
		"scene": path,
		"engine": Engine.get_version_info().get("string", ""),
		"profile": profile_name,
		"capture_size": [capture_size.x, capture_size.y],
		"analysis_size": [analysis_size.x, analysis_size.y],
		"timestamp": Time.get_datetime_string_from_system(),
		"captured": false,
		"warning": "",
	}

	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		base["warning"] = "could not load as PackedScene"
		return base

	var inst: Node = (packed as PackedScene).instantiate()
	sv.add_child(inst)
	for hp in hide_node_paths:
		var hn := inst.get_node_or_null(NodePath(hp.strip_edges()))
		if hn != null and "visible" in hn:
			hn.visible = false
	for _i in settle_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var tex := sv.get_texture()
	var img: Image = tex.get_image() if tex else null

	sv.remove_child(inst)
	inst.queue_free()
	await get_tree().process_frame

	if img == null:
		base["warning"] = "null image — no real renderer? Run with a display (xvfb-run), not --headless."
		return base
	if _is_blank(img):
		base["warning"] = "blank frame — dummy renderer or scene has no camera/visible content."
		return base

	img.resize(analysis_size.x, analysis_size.y, Image.INTERPOLATE_BILINEAR)
	base["captured"] = true
	base["analysis"] = ColorMath.analyze(img, profile)
	return base


func _is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var lo := 9.0
	var hi := -9.0
	var sx := maxi(1, w / 48)
	var sy := maxi(1, h / 48)
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var v := img.get_pixel(x, y).get_luminance()
			if v < lo:
				lo = v
			if v > hi:
				hi = v
			x += sx
		y += sy
	return (hi - lo) < 0.02


func _write_reports(records: Array, profile_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scenes_summary: Array = []
	var captured := 0
	var passed := 0
	for rec in records:
		var fname := rec["scene"].trim_prefix("res://").replace("/", "_").get_basename() + ".json"
		var f := FileAccess.open(out_dir.path_join(fname), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(rec, "\t"))
			f.close()
		var score := 0.0
		if rec["captured"]:
			score = float(rec["analysis"].get("score", 0.0))
		var ok: bool = rec["captured"] and score >= min_score
		if rec["captured"]:
			captured += 1
		if ok:
			passed += 1
		var warn_count := 0
		if rec["captured"]:
			warn_count = (rec["analysis"].get("warnings", []) as Array).size()
		scenes_summary.append({
			"scene": rec["scene"], "captured": rec["captured"],
			"score": score, "passed": ok, "warnings": warn_count, "warning": rec["warning"],
		})

	var summary := {
		"schema": SCHEMA_SUMMARY,
		"generated": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info().get("string", ""),
		"profile": profile_name,
		"min_score": min_score,
		"count": records.size(),
		"captured": captured,
		"passed": passed,
		"overall_pass": captured == records.size() and passed == records.size(),
		"scenes": scenes_summary,
	}
	var sf := FileAccess.open(out_dir.path_join("_summary.json"), FileAccess.WRITE)
	if sf:
		sf.store_string(JSON.stringify(summary, "\t"))
		sf.close()


func _print_summary(records: Array) -> void:
	print("[color-harmonizer] ---- batch report ----")
	for rec in records:
		if rec["captured"]:
			var wc := (rec["analysis"].get("warnings", []) as Array).size()
			var tag := "  ⚠%d" % wc if wc > 0 else "    "
			print("  %5d%s  %s" % [int(round(float(rec["analysis"]["score"]))), tag, rec["scene"]])
			for wdict in rec["analysis"].get("warnings", []):
				print("           - %s" % str(wdict.get("message", "")))
		else:
			print("   skip      %s  (%s)" % [rec["scene"], rec["warning"]])
	print("[color-harmonizer] reports written to %s" % out_dir)
