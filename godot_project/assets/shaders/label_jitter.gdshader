// label_jitter.gdshader
// Applied to Label nodes to make text subtly twitch and vibrate.
// Base layer: per-vertex sine/cosine wave so top/bottom corners move out of
// sync, producing shear/wave.  Every ~3.5 s an "epoch" fires a one-frame
// glitch spike in a random direction, simulating the paper being jolted.
shader_type canvas_item;

// Pixel amplitude of the base jitter at full strength.
uniform float strength : hint_range(0.0, 5.0) = 1.5;
// How fast the base oscillation runs (cycles per second).
uniform float speed    : hint_range(0.0, 30.0) = 9.0;
// Pixel amplitude of the glitch spike.
uniform float glitch_strength : hint_range(0.0, 20.0) = 7.0;
// Seconds between glitch events.
uniform float glitch_interval : hint_range(0.5, 10.0) = 3.5;
// Duration (seconds) of a single glitch spike.
uniform float glitch_duration : hint_range(0.01, 0.3) = 0.07;

void vertex() {
	// -- Base wave --
	float phase_x = VERTEX.y * 0.055;
	float phase_y = VERTEX.x * 0.042;
	VERTEX.x += sin(TIME * speed        + phase_x) * strength;
	VERTEX.y += cos(TIME * speed * 1.37 + phase_y) * strength * 0.65;

	// -- Glitch / hiccup --
	// Epoch index: which glitch interval are we in?
	float epoch     = floor(TIME / glitch_interval);
	// Phase within current epoch (0..1).
	float epoch_t   = fract(TIME / glitch_interval) * glitch_interval;

	// Per-epoch pseudo-random direction using a simple hash.
	float h1 = fract(sin(epoch * 127.1 + 311.7) * 43758.5453);
	float h2 = fract(sin(epoch *  93.9 + 197.3) * 23421.6315);
	vec2  glitch_dir = normalize(vec2(h1 * 2.0 - 1.0, h2 * 2.0 - 1.0));

	// Envelope: sharp rise then decay over glitch_duration.
	float env = max(0.0, 1.0 - epoch_t / glitch_duration);
	env = env * env;   // quadratic falloff feels snappier

	VERTEX.xy += glitch_dir * glitch_strength * env;
}
