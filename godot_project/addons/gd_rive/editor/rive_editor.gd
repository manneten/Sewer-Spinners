@tool
extends VBoxContainer

@onready var file_selector: OptionButton = %FileSelector
@onready var load_button: Button = %LoadButton
@onready var save_button: Button = %SaveButton
@onready var test_input: LineEdit = %TestInput
@onready var test_button: Button = %TestButton
@onready var text_edit: CodeEdit = %TextEdit
@onready var output_label: RichTextLabel = %OutputLabel
@onready var generate_button = $TopBar/GenerateButton
@onready var topic_list = %TopicList
@onready var topic_tree = %TopicTree
@onready var vis_button = %VisButton
@onready var help_button = %HelpButton
@onready var file_icon = %File
@onready var file_title_label = %FileTitleLabel
@onready var rive_selector = %RiveSelector
@onready var rive = %Rive

var current_file_path: String = ""
var rive_engine = preload("res://addons/gd_rive/engine/rive_engine.gd").new()
var save_dialog: EditorFileDialog

var is_persona: bool = true

const VIS_OFF_ICON = preload("res://addons/gd_rive/resources/icons/icon_visibility_off.png")
const VIS_ON_ICON = preload("res://addons/gd_rive/resources/icons/icon_visibility.png")
const PERSONA_ICON = preload("res://addons/gd_rive/resources/icons/icon_persona.png")
const BRAIN_ICON = preload("res://addons/gd_rive/resources/icons/icon_brain.png")

signal help_requested(requested: bool)

func _ready():
	load_button.pressed.connect(_on_load_pressed)
	save_button.pressed.connect(_on_save_pressed)
	test_button.pressed.connect(_on_test_pressed)
	generate_button.pressed.connect(_ensure_required_directories)
	load_persona_file_list()
	#_create_editor_save_file_dialog()

func show_save_dialog():
	save_dialog.popup_centered_ratio(0.5)

func load_persona_file_list():
	_load_file_list("personas")

func load_brain_file_list():
	_load_file_list("rive")

func _create_editor_save_file_dialog():
	var save_dialog = EditorFileDialog.new()
	save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.set_filters(["*.txt ; Text Files"])
	save_dialog.title = "Save Your File"
	save_dialog.file_selected.connect(_on_file_selected)
	add_child(save_dialog)
	self.save_dialog = save_dialog

func _on_file_selected(path: String) -> void:
	# Example content to save — replace with your actual data
	var content = text_edit.text
	
	if is_persona:
		save_dialog.set_current_dir("res://data/personas")
		save_dialog.set_current_file("new_persona.txt")
	else:
		save_dialog.set_current_dir("res://data/rive")
		save_dialog.set_current_file("new_brain.txt")
		
	# Open the file for writing (this overwrites existing files)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
	
		if is_persona:
			load_persona_file_list()
		else:
			load_brain_file_list()
		
	else:
		push_error("Could not open file for writing: " + path)

func _ensure_required_directories():
	var target_dirs = {
		"res://data": null,
		"res://data/rive": "res://addons/gd_rive/templates/rive",
		"res://data/personas": "res://addons/gd_rive/templates/personas"
	}

	for target_path in target_dirs.keys():
		if not DirAccess.dir_exists_absolute(target_path):
			var err = DirAccess.make_dir_recursive_absolute(target_path)
			if err != OK:
				push_error("Failed to create directory: " + target_path)

		# Copy pre-shipped files from template dir
		var template_path = target_dirs[target_path]

		if template_path and DirAccess.dir_exists_absolute(template_path):
			var dir = DirAccess.open(template_path)

			if dir:
				dir.list_dir_begin()
				var file_name = dir.get_next()

				while file_name != "":
					if file_name.ends_with(".txt") and not file_name.begins_with("."):
						var src = template_path + "/" + file_name
						var dst = target_path + "/" + file_name

						if not FileAccess.file_exists(dst):
							var src_file = FileAccess.open(src, FileAccess.READ)
							var content = src_file.get_as_text()
							src_file.close()

							var dst_file = FileAccess.open(dst, FileAccess.WRITE)
							dst_file.store_string(content)
							dst_file.close()
							print("Copied:", dst)
							
					file_name = dir.get_next()
				dir.list_dir_end()

func _load_file_list(file_type: String):
	file_selector.clear()
	var dir = DirAccess.open("res://data/" + file_type)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			if filename.ends_with(".txt"):
				file_selector.add_item(filename)
			filename = dir.get_next()
		dir.list_dir_end()

func _set_file_title(file_name: String):
	file_title_label.text = " Rive:  %s" % file_name

func _on_load_pressed():
	rive_engine.reset()
	
	rive_engine.get_all_brain_files()
	rive_engine.register_all_macros()
	
	var filename = file_selector.get_item_text(file_selector.get_selected())
	
	if is_persona:
		current_file_path = "res://data/personas/" + filename
	else:
		current_file_path = "res://data/rive/" + filename
		
	var file = FileAccess.open(current_file_path, FileAccess.READ)
	if file:
		text_edit.text = file.get_as_text()
		file.close()

	if current_file_path.contains("/personas/"):
		var persona_name = filename.get_basename()
		rive_engine.switch_to_persona(persona_name)
		file_icon.texture = PERSONA_ICON

	else:
		rive_engine.load_brain([current_file_path])
		file_icon.texture = BRAIN_ICON
	
	_set_file_title(filename)
	
	topic_tree.clear()
	var topics = rive_engine.get_topic_tree()
	topic_tree.make_tree(topics)

func _on_save_pressed():
	if current_file_path == "":
		show_save_dialog()
		
		return
		
	var file = FileAccess.open(current_file_path, FileAccess.WRITE)
	if file:
		file.store_string(text_edit.text)
		file.close()
		print("Saved: " + current_file_path)

func _on_test_pressed():
	var input = test_input.text.strip_edges()
	var response = "[No reply]"
	if input != "":
		response = rive_engine.reply("editor", input)
	output_label.text = "[center][color='#f5f5f5'][b]Reply:[/b][/color]    " + response + "[/center]"

func _on_topic_tree_item_activated():
	var item: TreeItem = topic_tree.get_selected()
	var is_topic = item.get_metadata(0).get("is_topic", true)

	if is_topic:
		return
	
	var topic = item.get_parent().get_text(0)
	rive_engine.set_topic("editor", topic)
	test_input.text = item.get_text(0)

func _on_vis_button_pressed():
	topic_list.visible = not topic_list.visible
	vis_button.icon = VIS_ON_ICON if not topic_list.visible else VIS_OFF_ICON
		
func _on_new_button_pressed():
	topic_tree.clear()
	current_file_path = ""
	text_edit.text = ""
	
func _on_rive_selector_toggled(toggled_on):
	is_persona = not toggled_on
	rive.texture = PERSONA_ICON if is_persona else BRAIN_ICON
	if is_persona:
		load_persona_file_list()
	else:
		load_brain_file_list()

func _on_help_button_pressed():
	help_requested.emit(true)
