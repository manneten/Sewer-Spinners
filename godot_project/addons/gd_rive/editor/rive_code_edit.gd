@tool
extends CodeEdit


# Called when the node enters the scene tree for the first time.
func _ready():
	add_gutter(0)
	set_gutter_type(0, TextEdit.GUTTER_TYPE_ICON)
	syntax_highlighter = RiveSyntaxHighlighter.new()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
