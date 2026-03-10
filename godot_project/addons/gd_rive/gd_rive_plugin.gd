@tool
extends EditorPlugin

var dock
var help_window: HelpDialog

const AUTOLOAD_PATH = "res://rive_engine"

func hide_help():
	if help_window and help_window.is_inside_tree():
		help_window.hide()
		# help_window.queue_free()

func _create_help_dialog():
	pass

func _enter_tree():
	# Load the editor scene
	dock = preload("res://addons/gd_rive/editor/rive_editor.tscn").instantiate()

	_ensure_required_directories()
	
	_ensure_required_auto_loads()
	
	add_autoload_singleton("RiveEngine", "res://addons/gd_rive/engine/rive_engine.gd")

	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)
	
	dock.help_requested.connect(_on_help_requested)
	
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
	
func _ensure_required_auto_loads():
	var autoload_files = {
		"RiveConditions": ["res://addons/gd_rive/engine/rive_conditions.gd", "res://rive_engine/rive_conditions.gd"],
		"RiveMacros": ["res://addons/gd_rive/engine/rive_macros.gd", "res://rive_engine/rive_macros.gd"]
	}

	if not DirAccess.dir_exists_absolute(AUTOLOAD_PATH):
		var err = DirAccess.make_dir_recursive_absolute(AUTOLOAD_PATH)
		
		for file in autoload_files.keys():
			if not FileAccess.file_exists(autoload_files[file][1]):
				var src_file = FileAccess.open(autoload_files[file][0], FileAccess.READ)
				var content = src_file.get_as_text()
				src_file.close()

				var dst_file = FileAccess.open(autoload_files[file][1], FileAccess.WRITE)
				dst_file.store_string(content)
				dst_file.close()
				print("Created:", autoload_files[file][1])
				
			add_autoload_singleton(file, autoload_files[file][1])

func _on_help_requested(requested: bool):
	if requested:
		if help_window and help_window.is_inside_tree():
			if not help_window.visible:
				help_window.show()
				
			help_window.popup_centered()
			help_window.grab_focus()
			
			return
			
		else:
			var scene = load("res://addons/gd_rive/editor/help_viewer.tscn")
			help_window = scene.instantiate()
			get_editor_interface().get_base_control().add_child(help_window)
			help_window.popup_centered()
			
			help_window.help_close_requested.connect(hide_help)
		
	else:
		hide_help()
	
func _exit_tree():
	remove_control_from_docks(dock)
