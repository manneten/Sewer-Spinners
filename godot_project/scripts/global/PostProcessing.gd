extends CanvasLayer

# Fullscreen film grain + vignette overlay.
# Autoloaded at layer 100 — sits above all gameplay without intercepting input.

const SHADER_PATH: String = "res://assets/shaders/post_process.gdshader"

func _ready() -> void:
	layer = 100

	var PostProcess_Rect := ColorRect.new()
	PostProcess_Rect.name = "PostProcess_Rect"
	PostProcess_Rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	PostProcess_Rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PostProcess_Rect.color = Color.TRANSPARENT

	if ResourceLoader.exists(SHADER_PATH):
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER_PATH)
		mat.set_shader_parameter("grain_strength",    0.045)
		mat.set_shader_parameter("vignette_strength", 0.52)
		mat.set_shader_parameter("vignette_radius",   0.72)
		PostProcess_Rect.material = mat

	add_child(PostProcess_Rect)
