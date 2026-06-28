extends RefCounted
## Bakes a GradeParams into a 3D LUT (ImageTexture3D) and/or an Adobe/Resolve
## .cube file. The grade math here MUST mirror harmonize.gdshader so a baked LUT
## matches the live preview. Strength is NOT baked in — the LUT holds the full
## grade and the runtime filter fades it with `strength`.


## Apply the grade to a single color. Mirrors fragment() in harmonize.gdshader.
## `wb` is the white-balance matrix rows from ColorGrade.wb_rows (precomputed once).
static func grade_color(c: Color, g: GradeParams, wb: Array) -> Color:
	var lin := ColorGrade.v_srgb_to_linear(Vector3(c.r, c.g, c.b))
	lin = ColorGrade.apply_wb(lin, wb)
	lin = ColorGrade.grade_linear(lin, g)
	var srgb := ColorGrade.v_linear_to_srgb(lin)
	var outc := Color(srgb.x, srgb.y, srgb.z, 1.0)

	if g.split_tone_amount > 0.0:
		var lum := outc.get_luminance()
		var sw := 1.0 - smoothstep(0.0, g.split_balance, lum)
		var hw := smoothstep(g.split_balance, 1.0, lum)
		var amt := g.split_tone_amount
		var r := lerp(outc.r, outc.r * g.shadow_tint.r, sw * amt)
		var gg := lerp(outc.g, outc.g * g.shadow_tint.g, sw * amt)
		var b := lerp(outc.b, outc.b * g.shadow_tint.b, sw * amt)
		r = lerp(r, 1.0 - (1.0 - r) * (1.0 - g.highlight_tint.r), hw * amt)
		gg = lerp(gg, 1.0 - (1.0 - gg) * (1.0 - g.highlight_tint.g), hw * amt)
		b = lerp(b, 1.0 - (1.0 - b) * (1.0 - g.highlight_tint.b), hw * amt)
		outc = Color(clampf(r, 0.0, 1.0), clampf(gg, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0)
	return outc


## Build an ImageTexture3D LUT of edge length `size` (e.g. 33).
static func bake_texture(grade: GradeParams, size: int = 33) -> ImageTexture3D:
	size = maxi(2, size)
	var inv := 1.0 / float(size - 1)
	var wb := ColorGrade.wb_rows(grade.kelvin, grade.tint, grade.wb_strength)
	var images: Array[Image] = []
	for b in size:               # depth slice = blue
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		for gg in size:          # y = green
			for r in size:       # x = red
				var inp := Color(r * inv, gg * inv, b * inv)
				img.set_pixel(r, gg, grade_color(inp, grade, wb))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, size, size, size, false, images)
	return tex


## Serialize the same LUT to Adobe/Resolve .cube text (red varies fastest).
static func to_cube(grade: GradeParams, size: int = 33, title: String = "Color Harmonizer") -> String:
	size = maxi(2, size)
	var inv := 1.0 / float(size - 1)
	var wb := ColorGrade.wb_rows(grade.kelvin, grade.tint, grade.wb_strength)
	var sb := PackedStringArray()
	sb.append("TITLE \"%s\"" % title)
	sb.append("LUT_3D_SIZE %d" % size)
	sb.append("DOMAIN_MIN 0.0 0.0 0.0")
	sb.append("DOMAIN_MAX 1.0 1.0 1.0")
	for b in size:
		for gg in size:
			for r in size:
				var o := grade_color(Color(r * inv, gg * inv, b * inv), grade, wb)
				sb.append("%.6f %.6f %.6f" % [o.r, o.g, o.b])
	return "\n".join(sb) + "\n"


## Write both a .res Texture3D and a .cube next to it. Returns OK or an error.
static func save(grade: GradeParams, size: int, tex_path: String, cube_path: String) -> int:
	var tex := bake_texture(grade, size)
	var err := ResourceSaver.save(tex, tex_path)
	var f := FileAccess.open(cube_path, FileAccess.WRITE)
	if f:
		f.store_string(to_cube(grade, size))
		f.close()
	return err


## Parse a .cube file into an ImageTexture3D (interop / re-import path).
static func from_cube_file(path: String) -> ImageTexture3D:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var size := 0
	var triples: Array = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with("TITLE") \
			or line.begins_with("DOMAIN"):
			continue
		if line.begins_with("LUT_3D_SIZE"):
			var sp := line.split(" ", false)
			size = int(sp[sp.size() - 1])
			continue
		var parts := line.split(" ", false)
		if parts.size() == 3:
			triples.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	f.close()
	if size < 2 or triples.size() < size * size * size:
		return null
	var images: Array[Image] = []
	for b in size:
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		for gg in size:
			for r in size:
				var t: Vector3 = triples[(b * size + gg) * size + r]  # red fastest
				img.set_pixel(r, gg, Color(t.x, t.y, t.z))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, size, size, size, false, images)
	return tex
