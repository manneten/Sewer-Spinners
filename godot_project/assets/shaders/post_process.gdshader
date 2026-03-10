shader_type canvas_item;

// Film grain + vignette overlay.
// Applied to a full-screen ColorRect on CanvasLayer 100.
// Outputs black with varying alpha — composites cleanly over gameplay.

uniform float grain_strength    : hint_range(0.0, 0.3)  = 0.045;
uniform float vignette_strength : hint_range(0.0, 1.0)  = 0.52;
uniform float vignette_radius   : hint_range(0.1, 2.0)  = 0.72;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Vignette: smooth dark overlay that grows toward screen edges.
	vec2 uv_c = UV - 0.5;
	float d    = length(uv_c) / vignette_radius;
	float vig  = smoothstep(0.3, 1.0, d) * vignette_strength;

	// Film grain: per-pixel random noise, animated each frame.
	float grain = hash(UV + fract(TIME * 13.7));
	grain = (grain - 0.5) * grain_strength;

	// Output pure black with alpha = vignette + grain contribution.
	float alpha = clamp(vig + abs(grain) * 0.4, 0.0, 0.88);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
