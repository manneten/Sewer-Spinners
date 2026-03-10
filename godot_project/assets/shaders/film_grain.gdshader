shader_type canvas_item;

// ── Tweakable parameters ────────────────────────────────────────────────────
// grain_intensity    : darkness of the pitting effect     (lower = brighter, 0 = off)
// grain_size         : UV-space size of each grain clump  (larger = chunkier silver halide)
// luminance_threshold: highlights above this are spared   (lower = grain only in shadows)
// flicker_speed      : how fast the grain pattern shifts
// vignette_power     : corner crush strength              (0 = off, makes edges brighter)
// scene_brightness   : direct multiplier on scene colour  (1.0 = neutral, >1.0 = brighter)

uniform float grain_intensity      : hint_range(0.0, 1.0)   = 0.14;
uniform float grain_size           : hint_range(0.001, 0.05) = 0.004;
uniform float luminance_threshold  : hint_range(0.0, 1.0)   = 0.80;
uniform float flicker_speed        : hint_range(0.0, 20.0)  = 5.0;
uniform float vignette_power       : hint_range(0.0, 4.0)   = 1.2;
uniform float scene_brightness     : hint_range(0.5, 2.0)   = 1.0;

// SCREEN_TEXTURE gives us the fully composited scene beneath this ColorRect.
// hint_nearest keeps grain pixels sharp (no bilinear softening of the noise).
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	// ── 1. Sample the scene colour beneath this overlay ──────────────────────
	vec4 scene = texture(SCREEN_TEXTURE, SCREEN_UV);
	scene.rgb  = clamp(scene.rgb * scene_brightness, 0.0, 1.0);

	// ── 2. Luminance (ITU-R BT.709 weights) ─────────────────────────────────
	float luminance = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));

	// Luminance mask:  shadows/mid-tones get full grain, highlights get none.
	// At luminance == 0          → mask = 1.0  (full grain)
	// At luminance == threshold  → mask = 0.0  (grain gone)
	// Above threshold            → mask = 0.0  (stays clean)
	float lum_mask = clamp(
		(luminance_threshold - luminance) / max(luminance_threshold, 0.001),
		0.0, 1.0
	);

	// ── 3. Organic film-grain noise ──────────────────────────────────────────
	// Snap UV to a coarse grid so adjacent pixels share the same noise value,
	// producing silver-halide clumps instead of 1px TV static.
	float t       = TIME * flicker_speed;
	vec2  uv_snap = floor(SCREEN_UV / grain_size) * grain_size;

	// Two sine-hash passes with different frequencies — breaks up visible tiling.
	float n1 = fract(sin(dot(uv_snap * 127.1 + t * 0.013, vec2(311.7,  74.3))) * 43758.5453);
	float n2 = fract(sin(dot(uv_snap * 269.5 + t * 0.007, vec2(183.3, 197.1))) * 37263.1171);
	float noise = (n1 + n2) * 0.5;   // 0..1 range, average of two passes

	// Subtle projector-lamp brightness flicker (two overlapping sine waves).
	float flicker = 1.0 + sin(TIME * flicker_speed * 0.31) * 0.012
	                    + sin(TIME * flicker_speed * 0.73) * 0.006;

	// ── 4. Luminance-weighted multiplicative darkening ───────────────────────
	// Pits the image downward — no white dust, only darkening pressure.
	// formula: finalColor *= (1.0 - noise * intensity * lum_mask * flicker)
	vec3 grained = scene.rgb * (1.0 - noise * grain_intensity * lum_mask * flicker);

	// ── 5. Vignette (corner crush) ───────────────────────────────────────────
	vec2  v_uv  = SCREEN_UV * 2.0 - 1.0;
	float vign  = pow(dot(v_uv, v_uv), vignette_power * 0.5);
	grained     = mix(grained, vec3(0.0), clamp(vign * vignette_power * 0.15, 0.0, 1.0));

	// ── 6. Output ────────────────────────────────────────────────────────────
	// alpha = 1.0 — this ColorRect fully replaces screen pixels via SCREEN_TEXTURE.
	// The HUD/UI (CanvasLayer < 128) is included in SCREEN_TEXTURE, so the
	// grain and vignette apply to the whole composited image.
	COLOR = vec4(grained, 1.0);
}
