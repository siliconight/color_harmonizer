@tool
extends VBoxContainer
## Diagnostic dock. Updates live while the game runs (F5) via the debugger plugin.

const HARMONY_NAMES := ["Any", "Analogous", "Complementary", "Triadic", "Split-comp"]

var _score_label: Label
var _breakdown_label: Label
var _neutral_label: Label
var _rows: Dictionary = {}
var _rec_label: Label
var _warn_label: Label


func _ready() -> void:
	name = "Color 60/30/10"
	custom_minimum_size = Vector2(230, 0)
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Color Balance — 60/30/10"
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	_score_label = Label.new()
	_score_label.text = "Score: --   (press F5 to play)"
	add_child(_score_label)

	_breakdown_label = Label.new()
	_breakdown_label.add_theme_font_size_override("font_size", 11)
	_breakdown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_breakdown_label.text = "proportion -- · accent -- · harmony --"
	add_child(_breakdown_label)

	_neutral_label = Label.new()
	_neutral_label.add_theme_font_size_override("font_size", 11)
	_neutral_label.text = "Neutrals (excluded): --%"
	add_child(_neutral_label)

	add_child(HSeparator.new())

	_add_role("dominant", "Dominant", 60)
	_add_role("secondary", "Secondary", 30)
	_add_role("accent", "Accent", 10)

	add_child(HSeparator.new())

	_rec_label = Label.new()
	_rec_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rec_label.add_theme_font_size_override("font_size", 11)
	_rec_label.text = "Recommended grade: --"
	add_child(_rec_label)

	add_child(HSeparator.new())

	_warn_label = Label.new()
	_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn_label.add_theme_font_size_override("font_size", 11)
	_warn_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	_warn_label.text = "Clashes: --"
	add_child(_warn_label)


func _add_role(key: String, role_title: String, target_pct: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = Color(0.2, 0.2, 0.2)
	row.add_child(swatch)
	var label := Label.new()
	label.text = "%s: --%%  (target %d%%)" % [role_title, target_pct]
	row.add_child(label)
	add_child(row)
	_rows[key] = {"swatch": swatch, "title": role_title, "target": target_pct, "label": label}


func update_report(report: Dictionary) -> void:
	if report.is_empty():
		return
	_score_label.text = "Score: %d / 100" % int(round(report.get("score", 0.0)))
	_breakdown_label.text = "proportion %d · accent %d · harmony %d · value %d · saturation %d (%s)" % [
		int(round(report.get("proportion_score", 0.0) * 100.0)),
		int(round(report.get("accent_score", 0.0) * 100.0)),
		int(round(report.get("harmony_score", 0.0) * 100.0)),
		int(round(report.get("value_contrast_score", 0.0) * 100.0)),
		int(round(report.get("saturation_focus_score", 0.0) * 100.0)),
		HARMONY_NAMES[clampi(int(report.get("harmony_rule", 0)), 0, HARMONY_NAMES.size() - 1)],
	]
	_neutral_label.text = "Neutrals: %d%% · zones: %d · nuance: %.2f\nAccent pop: %d/100 (weak: %s) · coverage %d%%" % [
		int(round(report.get("neutral_ratio", 0.0) * 100.0)),
		int(report.get("zone_count", 0)),
		report.get("nuance", 0.0),
		int(round(report.get("accent_pop", 0.0) * 100.0)),
		str(report.get("accent_pop_axis", "none")),
		int(round(report.get("accent_coverage", 0.0) * 100.0)),
	]

	# Targets come from the active profile, so reflect them in the labels.
	var targets: Array = report.get("targets", [0.6, 0.3, 0.1])
	var keys := ["dominant", "secondary", "accent"]
	for i in keys.size():
		var key: String = keys[i]
		if not report.has(key):
			continue
		var r: Dictionary = _rows[key]
		var data: Dictionary = report[key]
		var rgb: Array = data["rgb"]
		r["swatch"].color = Color(rgb[0], rgb[1], rgb[2])
		r["label"].text = "%s: %d%%  (target %d%%)" % [
			r["title"], int(round(data["weight"] * 100.0)), int(round(float(targets[i]) * 100.0))
		]

	var rec: Dictionary = report.get("recommend", {})
	_rec_label.text = "Recommend — desat dominant %.2f · boost accent %.2f · shift secondary %.2f" % [
		rec.get("dominant_desat", 0.0), rec.get("accent_boost", 0.0), rec.get("secondary_shift", 0.0)
	]

	var warns: Array = report.get("warnings", [])
	if warns.is_empty():
		_warn_label.text = "Clashes: none flagged"
	else:
		var lines := PackedStringArray()
		for wdict in warns:
			lines.append("⚠ " + str(wdict.get("message", "")))
		_warn_label.text = "\n".join(lines)
