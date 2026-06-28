shader_type canvas_item;
// PHYSICAL grade - mirrors ColorGrade.gd. Pipeline:
//   sRGB -> linear -> white balance (Bradford CAT, supplied as wb_matrix)
//   -> OkLCh role look + path-to-white -> linear -> sRGB, then optional
//   split-tone and a hash dither. Perceptual ops in linear light = a grade,
//   not a per-channel filter. The *analysis* also uses OkLab.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float dominant_hue = 0.0;          // OkLab hue angle, radians
uniform float secondary_hue = 0.0;
uniform float accent_hue = 0.0;
uniform float secondary_target_hue = 0.0;

uniform float dominant_desat : hint_range(0.0, 1.0) = 0.0;
uniform float accent_boost   : hint_range(0.0, 1.0) = 0.0;
uniform float secondary_shift: hint_range(0.0, 1.0) = 0.0;
uniform float hue_falloff    : hint_range(0.05, 3.1416) = 0.8;
uniform float strength       : hint_range(0.0, 1.0) = 0.5;

uniform mat3 wb_matrix = mat3(1.0);        // linear-RGB white balance (Bradford CAT)

uniform float path_to_white : hint_range(0.0, 1.0) = 0.0;
uniform float path_to_white_start : hint_range(0.0, 1.0) = 0.75;

uniform vec3 shadow_tint = vec3(0.42, 0.55, 0.85);
uniform vec3 highlight_tint = vec3(1.0, 0.86, 0.62);
uniform float split_tone_amount : hint_range(0.0, 1.0) = 0.0;
uniform float split_balance : hint_range(0.0, 1.0) = 0.5;

uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

const float TAU = 6.2831853071796;
const float PI_ = 3.14159265358979;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 linear_to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 lin_to_oklab(vec3 c) {
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	float l_ = pow(max(l, 0.0), 1.0 / 3.0);
	float m_ = pow(max(m, 0.0), 1.0 / 3.0);
	float s_ = pow(max(s, 0.0), 1.0 / 3.0);
	return vec3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
}
vec3 oklab_to_lin(vec3 lab) {
	float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
	float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
	float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
	float l = l_ * l_ * l_;
	float m = m_ * m_ * m_;
	float s = s_ * s_ * s_;
	return vec3(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}
float ang_dist(float a, float b) {
	float d = mod(abs(a - b), TAU);
	return min(d, TAU - d);
}
float ang_diff(float target, float h) {
	float d = mod(target - h + PI_, TAU);
	return d - PI_;
}
float role_w(float h, float role_h) {
	return 1.0 - smoothstep(0.0, max(hue_falloff, 0.001), ang_dist(h, role_h));
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 lin = wb_matrix * srgb_to_linear(src);

	vec3 lab = lin_to_oklab(lin);
	float L = lab.x;
	float C = length(lab.yz);
	float h = atan(lab.z, lab.y);

	C *= 1.0 - dominant_desat * role_w(h, dominant_hue);
	C *= 1.0 + accent_boost * role_w(h, accent_hue);
	h += ang_diff(secondary_target_hue, h) * secondary_shift * role_w(h, secondary_hue);
	if (path_to_white > 0.0) {
		C *= 1.0 - smoothstep(path_to_white_start, 1.0, L) * path_to_white;
	}

	vec3 graded_lin = max(oklab_to_lin(vec3(L, C * cos(h), C * sin(h))), vec3(0.0));
	vec3 graded = linear_to_srgb(graded_lin);

	if (split_tone_amount > 0.0) {
		float lum = dot(graded, vec3(0.2126, 0.7152, 0.0722));
		float sw = 1.0 - smoothstep(0.0, split_balance, lum);
		float hw = smoothstep(split_balance, 1.0, lum);
		graded = mix(graded, graded * shadow_tint, sw * split_tone_amount);
		graded = mix(graded, vec3(1.0) - (vec3(1.0) - graded) * (vec3(1.0) - highlight_tint), hw * split_tone_amount);
	}

	vec3 outc = mix(src, graded, strength);
	// Hash dither in display space, just before 8-bit quantization, to kill banding.
	float dt = fract(sin(dot(SCREEN_UV * vec2(1920.0, 1080.0), vec2(12.9898, 78.233))) * 43758.5453);
	outc += (dt - 0.5) * (dither_strength / 255.0);
	COLOR = vec4(outc, 1.0);
}
