@tool
class_name HelpDialog
extends Window

@onready var close_button = %CloseButton

signal help_close_requested

func _ready():
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)
		
	close_button.pressed.connect(_on_close_button_pressed)

func _on_close_requested():
	_close_window()

func _on_close_button_pressed():
	_close_window()

# Hide and free the window
func _close_window():
	help_close_requested.emit()
	
