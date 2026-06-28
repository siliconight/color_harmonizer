@tool
class_name ColorGrade
extends RefCounted
## Single source of truth for the PHYSICAL grade math. The live shader
## (harmonize.gdshader) mirrors grade_linear() in GLSL; the white balance is
## reduced to one 3x3 matrix here (wb_basis / wb_rows) so the shader only does a
## matrix multiply and can't drift from the baker. Pipeline:
##   sRGB -> linear -> white balance (Bradford CAT) -> OkLCh look + path-to-white
##   -> linear -> sRGB.
## All math is OkLab/OkLCh in linear light — that's the "grade not filter" part.

const TAU := 6.2831853071796

# --- sRGB transfer ---
static func srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)

static func linear_to_srgb(c: float) -> float:
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055

static func v_srgb_to_linear(v: Vector3) -> Vector3:
	return Vector3(srgb_to_linear(v.x), srgb_to_linear(v.y), srgb_to_linear(v.z))

static func v_linear_to_srgb(v: Vector3) -> Vector3:
	return Vector3(
		linear_to_srgb(clampf(v.x, 0.0, 1.0)),
		linear_to_srgb(clampf(v.y, 0.0, 1.0)),
		linear_to_srgb(clampf(v.z, 0.0, 1.0)))

static func _cbrt(x: float) -> float:
	return pow(max(x, 0.0), 1.0 / 3.0)

# --- linear RGB <-> OkLab (Ottosson constants; forward matches color_math.gd) ---
static func lin_to_oklab(c: Vector3) -> Vector3:
	var l := 0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z
	var m := 0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z
	var s := 0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z
	var l_ := _cbrt(l)
	var m_ := _cbrt(m)
	var s_ := _cbrt(s)
	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)

static func oklab_to_lin(lab: Vector3) -> Vector3:
	var l_ := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m_ := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s_ := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
	var l := l_ * l_ * l_
	var m := m_ * m_ * m_
	var s := s_ * s_ * s_
	return Vector3(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)

## OkLab hue ANGLE (radians) of a display-sRGB Color — used for role hues.
static func oklab_hue_of_color(col: Color) -> float:
	var lab := lin_to_oklab(v_srgb_to_linear(Vector3(col.r, col.g, col.b)))
	return atan2(lab.z, lab.y)

static func _ang_dist(a: float, b: float) -> float:
	var d := fmod(abs(a - b), TAU)
	return min(d, TAU - d)

static func _ang_diff(target: float, h: float) -> float:
	var d := fmod(target - h + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI

## The look, applied to WHITE-BALANCED linear RGB. Mirrors harmonize.gdshader.
static func grade_linear(rgb_lin: Vector3, g: GradeParams) -> Vector3:
	var lab := lin_to_oklab(rgb_lin)
	var ll := lab.x
	var cc := sqrt(lab.y * lab.y + lab.z * lab.z)
	var hh := atan2(lab.z, lab.y)
	var fall: float = max(g.hue_falloff, 0.001)
	var w_dom := 1.0 - smoothstep(0.0, fall, _ang_dist(hh, g.dominant_hue))
	var w_sec := 1.0 - smoothstep(0.0, fall, _ang_dist(hh, g.secondary_hue))
	var w_acc := 1.0 - smoothstep(0.0, fall, _ang_dist(hh, g.accent_hue))
	cc *= 1.0 - g.dominant_desat * w_dom          # mute the base
	cc *= 1.0 + g.accent_boost * w_acc            # enrich the accent (multiplicative in OkLCh)
	hh += _ang_diff(g.secondary_target_hue, hh) * g.secondary_shift * w_sec
	if g.path_to_white > 0.0:                      # desaturate highlights toward white
		cc *= 1.0 - smoothstep(g.path_to_white_start, 1.0, ll) * g.path_to_white
	var out := oklab_to_lin(Vector3(ll, cc * cos(hh), cc * sin(hh)))
	return Vector3(max(out.x, 0.0), max(out.y, 0.0), max(out.z, 0.0))

# --- White balance: Kelvin on the Planckian locus + Duv tint, via Bradford CAT ---
static func _xyy_to_xyz(x: float, y: float, big_y: float) -> Vector3:
	if y <= 0.0:
		return Vector3.ZERO
	return Vector3(x * big_y / y, big_y, (1.0 - x - y) * big_y / y)

static func _planckian_xy(t: float) -> Vector2:
	t = clampf(t, 1667.0, 25000.0)
	var t2 := t * t
	var t3 := t2 * t
	var x := 0.0
	if t < 4000.0:
		x = -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
	else:
		x = -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390
	var x2 := x * x
	var x3 := x2 * x
	var y := 0.0
	if t < 2222.0:
		y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683
	elif t < 4000.0:
		y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867
	else:
		y = 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483
	return Vector2(x, y)

static func _apply_tint(xy: Vector2, tint: float) -> Vector2:
	if absf(tint) < 1e-5:
		return xy
	var denom := -2.0 * xy.x + 12.0 * xy.y + 3.0
	var u := 4.0 * xy.x / denom
	var v := 6.0 * xy.y / denom
	v += tint * 0.05  # tint in -1..1 -> Duv ~ ±0.05 (green/magenta)
	var d2 := 2.0 * u - 8.0 * v + 4.0
	return Vector2(3.0 * u / d2, 2.0 * v / d2)

static func _matmul_rows(a: Array, b: Array) -> Array:
	var bc0 := Vector3(b[0].x, b[1].x, b[2].x)
	var bc1 := Vector3(b[0].y, b[1].y, b[2].y)
	var bc2 := Vector3(b[0].z, b[1].z, b[2].z)
	return [
		Vector3(a[0].dot(bc0), a[0].dot(bc1), a[0].dot(bc2)),
		Vector3(a[1].dot(bc0), a[1].dot(bc1), a[1].dot(bc2)),
		Vector3(a[2].dot(bc0), a[2].dot(bc1), a[2].dot(bc2)),
	]

## The full linear-sRGB -> linear-sRGB white-balance matrix as 3 row Vector3s.
## Identity at kelvin 6500 / tint 0. strength blends toward identity.
static func wb_rows(kelvin: float, tint: float, strength: float) -> Array:
	var ident := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	if strength <= 0.0 or (absf(kelvin - 6500.0) < 1.0 and absf(tint) < 1e-4):
		return ident
	var xy := _apply_tint(_planckian_xy(kelvin), tint)
	var src := _xyy_to_xyz(0.31272, 0.32903, 1.0)  # D65
	var dst := _xyy_to_xyz(xy.x, xy.y, 1.0)
	# Bradford cone-response matrix and its inverse.
	var ba := [Vector3(0.8951, 0.2664, -0.1614), Vector3(-0.7502, 1.7135, 0.0367), Vector3(0.0389, -0.0685, 1.0296)]
	var bi := [Vector3(0.9869929, -0.1470543, 0.1599627), Vector3(0.4323053, 0.5183603, 0.0492912), Vector3(-0.0085287, 0.0400428, 0.9684867)]
	var src_lms := Vector3(ba[0].dot(src), ba[1].dot(src), ba[2].dot(src))
	var dst_lms := Vector3(ba[0].dot(dst), ba[1].dot(dst), ba[2].dot(dst))
	var d := Vector3(dst_lms.x / src_lms.x, dst_lms.y / src_lms.y, dst_lms.z / src_lms.z)
	var dba := [ba[0] * d.x, ba[1] * d.y, ba[2] * d.z]  # diag(d) * Bradford
	var cat := _matmul_rows(bi, dba)                     # XYZ -> XYZ adaptation
	# Fold sRGB<->XYZ (D65) so the result maps linear RGB -> linear RGB.
	var xr := [Vector3(0.4123908, 0.3575843, 0.1804808), Vector3(0.2126390, 0.7151687, 0.0721923), Vector3(0.0193308, 0.1191948, 0.9505322)]
	var rx := [Vector3(3.2409699, -1.5373832, -0.4986108), Vector3(-0.9692436, 1.8759675, 0.0415551), Vector3(0.0556301, -0.2039770, 1.0569715)]
	var m := _matmul_rows(rx, _matmul_rows(cat, xr))
	return [ident[0].lerp(m[0], strength), ident[1].lerp(m[1], strength), ident[2].lerp(m[2], strength)]

## Same matrix as a Basis for the shader (Basis * v == wb_rows · v).
static func wb_basis(kelvin: float, tint: float, strength: float) -> Basis:
	var r := wb_rows(kelvin, tint, strength)
	return Basis(
		Vector3(r[0].x, r[1].x, r[2].x),
		Vector3(r[0].y, r[1].y, r[2].y),
		Vector3(r[0].z, r[1].z, r[2].z))

static func apply_wb(rgb_lin: Vector3, rows: Array) -> Vector3:
	return Vector3(rows[0].dot(rgb_lin), rows[1].dot(rgb_lin), rows[2].dot(rgb_lin))
