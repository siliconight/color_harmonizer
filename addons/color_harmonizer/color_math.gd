extends RefCounted
## Pure, stateless color analysis. No engine side effects so it can be unit-tested.
##
## Pipeline: pixels -> OkLab -> drop neutrals -> salience-weighted k-means
## -> roles -> score (proportion + accent contrast + harmony) -> recommend a grade.
## Everything tunable lives in the ColorProfile passed in.

const HUE_30 := 1.0 / 12.0   # 30 degrees in [0,1] hue space
const L_BINS := 64           # lightness histogram resolution for value-contrast


# --- sRGB -> linear ---
static func _srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _cbrt(x: float) -> float:
	return pow(max(x, 0.0), 1.0 / 3.0)


# --- sRGB Color -> OkLab (Vector3: L, a, b) ---
static func color_to_oklab(col: Color) -> Vector3:
	var r := _srgb_to_linear(col.r)
	var g := _srgb_to_linear(col.g)
	var b := _srgb_to_linear(col.b)
	var l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	var l_ := _cbrt(l)
	var m_ := _cbrt(m)
	var s_ := _cbrt(s)
	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
	)


static func oklab_chroma(lab: Vector3) -> float:
	return sqrt(lab.y * lab.y + lab.z * lab.z)


static func _hue(rgb: Array) -> float:
	return Color(rgb[0], rgb[1], rgb[2]).h


static func _hue_dist(a: float, b: float) -> float:
	var d: float = abs(a - b)
	return min(d, 1.0 - d)


# --- salience-weighted k-means (++ seeding, weighted Lloyd) ---
static func _wkmeans(pts: Array, weights: PackedFloat32Array, k: int, iters: int) -> Dictionary:
	var n := pts.size()
	var centroids: Array = []
	centroids.append(pts[randi() % n])
	var d2 := PackedFloat32Array()
	d2.resize(n)
	for i in n:
		d2[i] = INF
	while centroids.size() < k:
		var last: Vector3 = centroids[centroids.size() - 1]
		var sum := 0.0
		for i in n:
			var dd: float = pts[i].distance_squared_to(last)
			if dd < d2[i]:
				d2[i] = dd
			sum += d2[i] * weights[i]
		if sum <= 0.0:
			centroids.append(pts[randi() % n])
			continue
		var r := randf() * sum
		var acc := 0.0
		var chosen := n - 1
		for i in n:
			acc += d2[i] * weights[i]
			if acc >= r:
				chosen = i
				break
		centroids.append(pts[chosen])

	var labels := PackedInt32Array()
	labels.resize(n)
	var wsum := PackedFloat32Array()
	wsum.resize(k)
	for _it in iters:
		var vsum: Array = []
		vsum.resize(k)
		for c in k:
			vsum[c] = Vector3.ZERO
			wsum[c] = 0.0
		for i in n:
			var best := 0
			var bd := INF
			for c in k:
				var dd: float = pts[i].distance_squared_to(centroids[c])
				if dd < bd:
					bd = dd
					best = c
			labels[i] = best
			vsum[best] += pts[i] * weights[i]
			wsum[best] += weights[i]
		for c in k:
			if wsum[c] > 0.0:
				centroids[c] = vsum[c] / wsum[c]

	return {"centroids": centroids, "labels": labels, "wsum": wsum}


# Ideal hue offsets (from the dominant) for each harmony rule: [secondary, accent].
static func _harmony_offsets(rule: int) -> Vector2:
	match rule:
		ColorProfile.Harmony.ANALOGOUS:
			return Vector2(HUE_30, HUE_30 * 2.0)
		ColorProfile.Harmony.COMPLEMENTARY:
			return Vector2(HUE_30, 0.5)
		ColorProfile.Harmony.TRIADIC:
			return Vector2(1.0 / 3.0, 1.0 / 3.0)
		ColorProfile.Harmony.SPLIT_COMPLEMENTARY:
			return Vector2(HUE_30, 0.5 - HUE_30)
		_:
			return Vector2(HUE_30 * 5.0, HUE_30 * 5.0)  # ANY: no strong constraint


static func _harmony_score(dom_h: float, sec_h: float, acc_h: float, rule: int) -> float:
	if rule == ColorProfile.Harmony.ANY:
		return 1.0
	var ideal := _harmony_offsets(rule)
	var sec_off := _hue_dist(sec_h, dom_h)
	var acc_off := _hue_dist(acc_h, dom_h)
	var sec_err: float = abs(sec_off - ideal.x) / 0.5
	var acc_err: float = abs(acc_off - ideal.y) / 0.5
	return clampf(1.0 - 0.5 * (sec_err + acc_err), 0.0, 1.0)


static func _salience(px: float, py: float, lum: float, contrast: float, p: ColorProfile) -> float:
	if not p.use_salience:
		return 1.0
	var sal := 1.0
	# center bias: 1.0 at center, falls off toward edges
	var cx := px - 0.5
	var cy := py - 0.5
	var dist := sqrt(cx * cx + cy * cy) / 0.707
	var center_term := clampf(1.0 - dist, 0.0, 1.0)
	sal *= lerp(1.0, center_term, p.center_bias)
	sal *= lerp(1.0, clampf(contrast, 0.0, 1.0), p.contrast_bias)
	sal *= lerp(1.0, clampf(lum, 0.0, 1.0), p.luminance_bias)
	return maxf(sal, 0.0001)


static func _empty_role() -> Dictionary:
	return {"rgb": [0.5, 0.5, 0.5], "weight": 0.0, "chroma": 0.0, "hue": 0.0, "spread": 0.0}


# Targeted "why it isn't popping" advice per weakest axis.
static func _pop_fix(axis: String) -> String:
	match axis:
		"value":
			return "put a value break behind it (darken the field or lighten/rim-light the accent)"
		"chroma":
			return "raise accent saturation or desaturate its surroundings"
		"temperature":
			return "make the accent warmer or cooler than the field"
		"isolation":
			return "consolidate the accent into one focal area"
		_:
			return "give it more local contrast"


# Connected-component count + largest-blob fraction (by pixel count, 4-connectivity).
static func _flood_fill_blobs(mask: PackedByteArray, w: int, h: int) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(mask.size())
	var blobs := 0
	var largest := 0
	var total := 0
	var stack := PackedInt32Array()
	for start in mask.size():
		if mask[start] == 0 or visited[start] == 1:
			continue
		blobs += 1
		var size := 0
		stack.clear()
		stack.push_back(start)
		visited[start] = 1
		while stack.size() > 0:
			var idx := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			total += 1
			var x := idx % w
			var y := idx / w
			if x > 0:
				var na := idx - 1
				if mask[na] == 1 and visited[na] == 0:
					visited[na] = 1
					stack.push_back(na)
			if x < w - 1:
				var nb := idx + 1
				if mask[nb] == 1 and visited[nb] == 0:
					visited[nb] = 1
					stack.push_back(nb)
			if y > 0:
				var nc := idx - w
				if mask[nc] == 1 and visited[nc] == 0:
					visited[nc] = 1
					stack.push_back(nc)
			if y < h - 1:
				var nd := idx + w
				if mask[nd] == 1 and visited[nd] == 0:
					visited[nd] = 1
					stack.push_back(nd)
		if size > largest:
			largest = size
	var frac := float(largest) / float(total) if total > 0 else 0.0
	return {"blobs": blobs, "largest_frac": frac}


# Lightness-down-weighted OkLab distance: chromatic difference matters more than
# lightness, so a value gradient on one material reads as a single zone.
static func _zone_dist(a: Vector3, b: Vector3, l_weight: float) -> float:
	var dl := (a.x - b.x) * l_weight
	var da := a.y - b.y
	var db := a.z - b.z
	return sqrt(dl * dl + da * da + db * db)


# Agglomeratively merge clusters whose centroids are within `tolerance`.
static func _merge_zones(clusters: Array, tolerance: float, l_weight: float) -> Array:
	var zones := clusters.duplicate(true)
	while zones.size() > 1:
		var bi := -1
		var bj := -1
		var bd := tolerance
		for i in zones.size():
			for j in range(i + 1, zones.size()):
				var d := _zone_dist(zones[i]["oklab"], zones[j]["oklab"], l_weight)
				if d <= bd:
					bd = d
					bi = i
					bj = j
		if bi < 0:
			break
		var a: Dictionary = zones[bi]
		var b: Dictionary = zones[bj]
		var wa: float = a["weight"]
		var wb: float = b["weight"]
		var w: float = wa + wb
		var oa: Vector3 = a["oklab"]
		var ob: Vector3 = b["oklab"]
		var ok: Vector3 = (oa * wa + ob * wb) / w
		var ra: Array = a["rgb"]
		var rb: Array = b["rgb"]
		var rgb := [
			(ra[0] * wa + rb[0] * wb) / w,
			(ra[1] * wa + rb[1] * wb) / w,
			(ra[2] * wa + rb[2] * wb) / w,
		]
		# Combine spreads (parallel-axis): each zone's variance plus its shift to
		# the new centre. Merging a gradient keeps that gradient as nuance.
		var da := oa.distance_to(ok)
		var db2 := ob.distance_to(ok)
		var var_a: float = a["spread"] * a["spread"] + da * da
		var var_b: float = b["spread"] * b["spread"] + db2 * db2
		var spread := sqrt((wa * var_a + wb * var_b) / w)
		var merged := {
			"oklab": ok, "rgb": rgb, "weight": w,
			"chroma": oklab_chroma(ok), "spread": spread,
		}
		zones.remove_at(bj)
		zones.remove_at(bi)
		zones.append(merged)
	return zones


static func _degenerate(neutral_ratio: float, p: ColorProfile) -> Dictionary:
	return {
		"dominant": _empty_role(), "secondary": _empty_role(), "accent": _empty_role(),
		"neutral_ratio": neutral_ratio, "score": 0.0,
		"proportion_score": 0.0, "accent_score": 0.0, "harmony_score": 0.0,
		"accent_pop": 0.0, "pop_value": 0.0, "pop_chroma": 0.0, "pop_temperature": 0.0,
		"pop_isolation": 0.0, "accent_coverage": 0.0, "accent_blobs": 0, "accent_pop_axis": "none",
		"value_contrast_score": 0.0, "saturation_focus_score": 0.0,
		"value_iqr": 0.0, "hi_chroma_frac": 0.0,
		"hue_families": 0, "zone_count": 0, "nuance": 0.0,
		"busy_fraction": 0.0, "warnings": [],
		"harmony_rule": p.harmony_rule,
		"targets": [p.target_dominant, p.target_secondary, p.target_accent],
		"recommend": {"dominant_desat": 0.0, "accent_boost": 0.0,
			"secondary_shift": 0.0, "secondary_target_hue": 0.0},
	}


# Quantile p (0..1) of a weighted lightness histogram, returned in [0,1].
static func _weighted_percentile(hist: PackedFloat32Array, total: float, p: float) -> float:
	if total <= 0.0:
		return 0.0
	var target := total * p
	var acc := 0.0
	var bins := hist.size()
	for i in bins:
		acc += hist[i]
		if acc >= target:
			return float(i) / float(bins - 1)
	return 1.0


## Analyze a (small, already-downscaled) image against a ColorProfile.
static func analyze(image: Image, profile: ColorProfile) -> Dictionary:
	var p := profile if profile != null else ColorProfile.new()
	var w := image.get_width()
	var h := image.get_height()
	var n_all := w * h

	# Pass 1: OkLab + luminance buffer.
	var lab_all: Array = []
	var rgb_all: Array = []
	var lum := PackedFloat32Array()
	lab_all.resize(n_all)
	rgb_all.resize(n_all)
	lum.resize(n_all)
	for y in h:
		for x in w:
			var idx := y * w + x
			var px := image.get_pixel(x, y)
			var lab := color_to_oklab(px)
			lab_all[idx] = lab
			rgb_all[idx] = Vector3(px.r, px.g, px.b)
			lum[idx] = lab.x

	# Pass 2: local contrast (vs 4-neighbour mean).
	var contrast := PackedFloat32Array()
	contrast.resize(n_all)
	for y in h:
		for x in w:
			var idx := y * w + x
			var acc := 0.0
			var cnt := 0
			if x > 0:
				acc += lum[idx - 1]
				cnt += 1
			if x < w - 1:
				acc += lum[idx + 1]
				cnt += 1
			if y > 0:
				acc += lum[idx - w]
				cnt += 1
			if y < h - 1:
				acc += lum[idx + w]
				cnt += 1
			contrast[idx] = clampf(abs(lum[idx] - acc / float(maxi(cnt, 1))) * 4.0, 0.0, 1.0)

	# Pass 3: split neutral vs chromatic, weight by salience.
	# Also accumulate whole-frame value (lightness) histogram + hi-chroma weight
	# for the value-structure and saturation-focus metrics.
	var pts: Array = []
	var rgb_pts: Array = []
	var weights := PackedFloat32Array()
	var neutral_w := 0.0
	var chroma_w := 0.0
	var all_w := 0.0
	var hi_chroma_w := 0.0
	var busy_w := 0.0
	var l_hist := PackedFloat32Array()
	l_hist.resize(L_BINS)
	for y in h:
		for x in w:
			var idx := y * w + x
			var lab: Vector3 = lab_all[idx]
			var c := oklab_chroma(lab)
			var sal := _salience(float(x) / float(w), float(y) / float(h), lab.x, contrast[idx], p)
			all_w += sal
			var bin := clampi(int(clampf(lab.x, 0.0, 1.0) * (L_BINS - 1)), 0, L_BINS - 1)
			l_hist[bin] += sal
			if c >= p.chroma_hi_threshold:
				hi_chroma_w += sal
			if contrast[idx] >= p.busy_contrast_threshold:
				busy_w += sal
			var is_neutral := c < p.neutral_chroma_max \
				or lab.x < p.neutral_value_min or lab.x > p.neutral_value_max
			if is_neutral:
				neutral_w += sal
			else:
				pts.append(lab)
				rgb_pts.append(rgb_all[idx])
				weights.append(sal)
				chroma_w += sal

	# Value-structure score: interpercentile (P10..P90) lightness range.
	var iqr := _weighted_percentile(l_hist, all_w, 0.9) - _weighted_percentile(l_hist, all_w, 0.1)
	var span := maxf(p.value_contrast_good - p.value_contrast_min, 0.001)
	var value_contrast_score := clampf((iqr - p.value_contrast_min) / span, 0.0, 1.0)

	# Saturation-focus score: reward some pop, penalize over-saturation.
	var hi_frac := hi_chroma_w / all_w if all_w > 0.0 else 0.0
	var sat_target := maxf(p.target_hi_chroma_frac, 0.001)
	var saturation_focus_score := 0.0
	if hi_frac <= sat_target:
		saturation_focus_score = lerp(0.6, 1.0, hi_frac / sat_target)
	else:
		saturation_focus_score = clampf(1.0 - (hi_frac - sat_target) / 0.4, 0.0, 1.0)

	var total_w := neutral_w + chroma_w
	var neutral_ratio := neutral_w / total_w if total_w > 0.0 else 1.0
	if pts.size() < 3 or chroma_w <= 0.0:
		return _degenerate(neutral_ratio, p)

	# Salience-weighted clustering.
	var km := _wkmeans(pts, weights, p.clusters, 8)
	var centroids: Array = km["centroids"]
	var labels: PackedInt32Array = km["labels"]
	var wsum: PackedFloat32Array = km["wsum"]

	var rgb_wsum: Array = []
	var sq_wsum := PackedFloat32Array()
	rgb_wsum.resize(p.clusters)
	sq_wsum.resize(p.clusters)
	for c in p.clusters:
		rgb_wsum[c] = Vector3.ZERO
	for i in pts.size():
		var lc: int = labels[i]
		rgb_wsum[lc] += rgb_pts[i] * weights[i]
		sq_wsum[lc] += weights[i] * (pts[i] as Vector3).distance_squared_to(centroids[lc])

	var clusters: Array = []
	for c in p.clusters:
		if wsum[c] <= 0.0:
			continue
		var oklab: Vector3 = centroids[c]
		var avg_rgb: Vector3 = rgb_wsum[c] / wsum[c]
		clusters.append({
			"oklab": oklab,
			"rgb": [avg_rgb.x, avg_rgb.y, avg_rgb.z],
			"weight": wsum[c] / chroma_w,        # share of the chromatic content
			"chroma": oklab_chroma(oklab),
			"spread": sqrt(sq_wsum[c] / wsum[c]),  # RMS perceptual radius = nuance/gradient
		})
	if clusters.is_empty():
		return _degenerate(neutral_ratio, p)

	# Merge clusters into perceptual "nuance zones". A zone is a chromatic family
	# that may span a lightness gradient (lighting), so value ramps on one
	# material stay a single zone instead of fracturing into many "colors".
	var zones := _merge_zones(clusters, p.nuance_tolerance, p.nuance_lightness_weight)
	zones.sort_custom(func(a, b): return a["weight"] > b["weight"])
	var zone_count := zones.size()
	var nuance := 0.0
	for z in zones:
		nuance += z["weight"] * z["spread"]

	# Roles.
	var dominant: Dictionary = zones[0]
	var accent: Dictionary = zones[zones.size() - 1]
	var best_pop := -1.0
	for cl in zones:
		if cl == dominant:
			continue
		var pop: float = cl["chroma"] * (cl["oklab"] as Vector3).distance_to(dominant["oklab"])
		if pop > best_pop:
			best_pop = pop
			accent = cl
	var secondary: Dictionary = dominant
	for cl in zones:
		if cl == dominant or cl == accent:
			continue
		secondary = cl
		break

	# Collapse every zone into the 3 roles.
	var roles := [dominant, secondary, accent]
	var role_w := [0.0, 0.0, 0.0]
	for cl in zones:
		var best := 0
		var bd := INF
		for ri in 3:
			var dd: float = (cl["oklab"] as Vector3).distance_to(roles[ri]["oklab"])
			if dd < bd:
				bd = dd
				best = ri
		role_w[best] += cl["weight"]
	var tot: float = role_w[0] + role_w[1] + role_w[2]
	if tot <= 0.0:
		tot = 1.0
	var dw: float = role_w[0] / tot
	var sw: float = role_w[1] / tot
	var aw: float = role_w[2] / tot

	# --- Accent pop: local-surround contrast (the analyzer's first spatial pass) ---
	var acc_centroid: Vector3 = accent["oklab"]
	var accent_mask := PackedByteArray()
	accent_mask.resize(n_all)
	var accent_w_total := 0.0
	for y in h:
		for x in w:
			var idx := y * w + x
			var lab: Vector3 = lab_all[idx]
			if _zone_dist(lab, acc_centroid, p.nuance_lightness_weight) <= p.accent_zone_tolerance:
				accent_mask[idx] = 1
				accent_w_total += _salience(float(x) / float(w), float(y) / float(h), lab.x, contrast[idx], p)
	var accent_coverage := accent_w_total / all_w if all_w > 0.0 else 0.0

	var pop_value := 0.0
	var pop_chroma := 0.0
	var pop_temp := 0.0
	var pop_wsum := 0.0
	var sr := p.surround_radius
	for y in h:
		for x in w:
			var idx := y * w + x
			if accent_mask[idx] == 0:
				continue
			var surr_l := 0.0
			var surr_a := 0.0
			var surr_b := 0.0
			var surr_n := 0
			for dy in range(-sr, sr + 1):
				var yy := y + dy
				if yy < 0 or yy >= h:
					continue
				for dx in range(-sr, sr + 1):
					var xx := x + dx
					if xx < 0 or xx >= w:
						continue
					var nidx := yy * w + xx
					if accent_mask[nidx] == 1:
						continue
					var nl: Vector3 = lab_all[nidx]
					surr_l += nl.x
					surr_a += nl.y
					surr_b += nl.z
					surr_n += 1
			if surr_n == 0:
				continue  # interior accent pixel — no background in window
			var inv := 1.0 / float(surr_n)
			var bl := surr_l * inv
			var ba := surr_a * inv
			var bb := surr_b * inv
			var lab_i: Vector3 = lab_all[idx]
			var sal := _salience(float(x) / float(w), float(y) / float(h), lab_i.x, contrast[idx], p)
			var v_d := absf(lab_i.x - bl) / maxf(p.pop_value_ref, 0.001)
			var c_i := sqrt(lab_i.y * lab_i.y + lab_i.z * lab_i.z)
			var c_s := sqrt(ba * ba + bb * bb)
			var c_d := maxf(0.0, c_i - c_s) / maxf(p.pop_chroma_ref, 0.001)
			var t_d := absf((lab_i.y + lab_i.z) - (ba + bb)) / maxf(p.pop_temp_ref, 0.001)
			pop_value += sal * clampf(v_d, 0.0, 1.0)
			pop_chroma += sal * clampf(c_d, 0.0, 1.0)
			pop_temp += sal * clampf(t_d, 0.0, 1.0)
			pop_wsum += sal
	if pop_wsum > 0.0:
		pop_value /= pop_wsum
		pop_chroma /= pop_wsum
		pop_temp /= pop_wsum

	var iso := _flood_fill_blobs(accent_mask, w, h)
	var accent_blobs: int = iso["blobs"]
	var pop_isolation: float = iso["largest_frac"]

	var pw := p.pop_value_weight + p.pop_chroma_weight + p.pop_temp_weight
	if pw <= 0.0:
		pw = 1.0
	var pop_contrast := (p.pop_value_weight * pop_value + p.pop_chroma_weight * pop_chroma \
		+ p.pop_temp_weight * pop_temp) / pw
	var accent_pop := pop_contrast * lerp(0.5, 1.0, pop_isolation)

	var accent_pop_axis := "value"
	var weakest := pop_value
	if pop_chroma < weakest:
		weakest = pop_chroma
		accent_pop_axis = "chroma"
	if pop_temp < weakest:
		weakest = pop_temp
		accent_pop_axis = "temperature"
	if pop_isolation < weakest:
		accent_pop_axis = "isolation"
	if accent_coverage <= 0.001:
		accent_pop = 0.0
		accent_pop_axis = "none"

	# Scores.
	var err := absf(dw - p.target_dominant) + absf(sw - p.target_secondary) + absf(aw - p.target_accent)
	var prop_score := 1.0 - clampf(err / 2.0, 0.0, 1.0)
	var accent_contrast: float = accent["chroma"] - dominant["chroma"]
	var accent_score := clampf(accent_contrast / maxf(p.accent_min_contrast, 0.001), 0.0, 1.0)

	var dom_hue := _hue(dominant["rgb"])
	var sec_hue := _hue(secondary["rgb"])
	var acc_hue := _hue(accent["rgb"])
	var harmony := _harmony_score(dom_hue, sec_hue, acc_hue, p.harmony_rule)

	var sw_total := p.w_proportion + p.w_accent + p.w_harmony + p.w_value_contrast + p.w_saturation_focus
	if sw_total <= 0.0:
		sw_total = 1.0
	var score := (p.w_proportion * prop_score + p.w_accent * accent_pop + p.w_harmony * harmony \
		+ p.w_value_contrast * value_contrast_score + p.w_saturation_focus * saturation_focus_score) \
		/ sw_total * 100.0

	# Recommendation, clamped to the profile's grade limits.
	var ideal := _harmony_offsets(p.harmony_rule)
	var sec_target_hue := fposmod(dom_hue + ideal.x, 1.0)
	var dominant_desat := clampf((dw - p.target_dominant) / 0.4, 0.0, 1.0) \
		* clampf(dominant["chroma"] / 0.12, 0.0, 1.0)
	var accent_boost := clampf(1.0 - accent_score, 0.0, 1.0)
	var secondary_shift := 0.0
	if p.harmony_rule != ColorProfile.Harmony.ANY:
		secondary_shift = clampf(_hue_dist(sec_hue, sec_target_hue) / 0.25, 0.0, 1.0)

	# --- Clash & overload warnings (the "don't" rules) ---
	var busy_frac := busy_w / all_w if all_w > 0.0 else 0.0
	var fam := {}
	for cl in zones:
		if cl["chroma"] >= p.chroma_hi_threshold and cl["weight"] >= 0.06:
			fam[int(_hue(cl["rgb"]) * 12.0) % 12] = true
	var hue_families := fam.size()
	var warnings: Array = []
	if p.enable_warnings:
		if hi_frac > p.max_hi_chroma_frac:
			warnings.append({"code": "saturation_overload",
				"message": "Saturation overload — %d%% of the frame is high-chroma; reserve saturation for focal points." % int(round(hi_frac * 100.0))})
		if hue_families > p.max_hue_families:
			warnings.append({"code": "too_many_hues",
				"message": "Too many competing colors (%d saturated families) — consolidate the palette." % hue_families})
		if neutral_ratio < p.min_neutral_ratio:
			warnings.append({"code": "no_resting_space",
				"message": "Little neutral resting space (%d%%) — the eye has nowhere to rest." % int(round(neutral_ratio * 100.0))})
		if busy_frac > p.max_busy_fraction:
			warnings.append({"code": "busy_everywhere",
				"message": "High contrast everywhere (%d%%) — no value rest; reserve contrast for the focal point." % int(round(busy_frac * 100.0))})
		var hd_da := _hue_dist(dom_hue, acc_hue)
		if dominant["chroma"] >= p.chroma_hi_threshold and accent["chroma"] >= p.chroma_hi_threshold \
			and dw >= p.clash_min_weight and aw >= p.clash_min_weight \
			and hd_da >= p.clash_band_lo and hd_da <= p.clash_band_hi:
			warnings.append({"code": "saturated_clash",
				"message": "Saturated near-complementary clash (dominant vs accent) — vibrating; desaturate one side."})
		if accent_coverage > 0.001 and accent_pop < p.accent_pop_min:
			warnings.append({"code": "accent_buried",
				"message": "Accent doesn't pop (%d/100, weak on %s) — %s." % [int(round(accent_pop * 100.0)), accent_pop_axis, _pop_fix(accent_pop_axis)]})
		if accent_coverage > p.max_accent_coverage:
			warnings.append({"code": "accent_oversized",
				"message": "Accent is %d%% of the frame — too large to read as an accent." % int(round(accent_coverage * 100.0))})

	return {
		"dominant": {"rgb": dominant["rgb"], "weight": dw, "chroma": dominant["chroma"], "hue": dom_hue, "spread": dominant["spread"]},
		"secondary": {"rgb": secondary["rgb"], "weight": sw, "chroma": secondary["chroma"], "hue": sec_hue, "spread": secondary["spread"]},
		"accent": {"rgb": accent["rgb"], "weight": aw, "chroma": accent["chroma"], "hue": acc_hue, "spread": accent["spread"]},
		"neutral_ratio": neutral_ratio,
		"score": score,
		"proportion_score": prop_score,
		"accent_score": accent_score,
		"accent_pop": accent_pop,
		"pop_value": pop_value,
		"pop_chroma": pop_chroma,
		"pop_temperature": pop_temp,
		"pop_isolation": pop_isolation,
		"accent_coverage": accent_coverage,
		"accent_blobs": accent_blobs,
		"accent_pop_axis": accent_pop_axis,
		"harmony_score": harmony,
		"value_contrast_score": value_contrast_score,
		"saturation_focus_score": saturation_focus_score,
		"value_iqr": iqr,
		"hi_chroma_frac": hi_frac,
		"hue_families": hue_families,
		"zone_count": zone_count,
		"nuance": nuance,
		"busy_fraction": busy_frac,
		"warnings": warnings,
		"harmony_rule": p.harmony_rule,
		"targets": [p.target_dominant, p.target_secondary, p.target_accent],
		"recommend": {
			"dominant_desat": minf(dominant_desat, p.max_dominant_desat),
			"accent_boost": minf(accent_boost, p.max_accent_boost),
			"secondary_shift": minf(secondary_shift, p.max_secondary_shift),
			"secondary_target_hue": sec_target_hue,
		},
	}
