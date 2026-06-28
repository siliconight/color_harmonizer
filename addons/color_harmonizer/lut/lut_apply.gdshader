shader_type canvas_item;
// Fixed grade via one 3D-LUT fetch — far cheaper than the per-pixel HSV grade in
// harmonize.gdshader. Ideal for shipping and for multiple viewports (split-screen).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler3D lut : filter_linear;
uniform float lut_size = 33.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	// Map [0,1] to texel centers so the lookup samples the baked entries exactly.
	vec3 uvw = clamp(col, 0.0, 1.0) * ((lut_size - 1.0) / lut_size) + (0.5 / lut_size);
	vec3 graded = texture(lut, uvw).rgb;
	vec3 outc = mix(col, graded, strength);
	// Hash dither just before 8-bit quantization to break LUT/gradient banding.
	float dt = fract(sin(dot(SCREEN_UV * vec2(1920.0, 1080.0), vec2(12.9898, 78.233))) * 43758.5453);
	outc += (dt - 0.5) * (dither_strength / 255.0);
	COLOR = vec4(outc, 1.0);
}
