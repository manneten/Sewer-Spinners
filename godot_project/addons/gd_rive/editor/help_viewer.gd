@tool
class_name HelpViewer
extends HSplitContainer

@onready var tree: Tree = $HeadingsTree
@onready var help_text: RichTextLabel = %Helptextlabel

var heading_positions: Array = []  # Stores { title, line_index }

func _ready():
	load_help_file("res://addons/gd_rive/resources/persona_authoring_guide.txt")
	populate_tree()
	tree.item_selected.connect(_on_tree_item_selected)

func load_help_file(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open help file: %s" % path)
		return
	
	var content := file.get_as_text()
	file.close()
	
	# Load into RichTextLabel
	help_text.bbcode_enabled = true
	help_text.text = content
	
	# Build heading list
	heading_positions.clear()
	var lines := content.split("\n")
	var heading_regex := RegEx.new()
	#heading_regex.compile("\\[b\\](.*?)\\[/b\\]")  # captures bold text
	heading_regex.compile("^\\[b\\](.*?)\\[/b\\]")
	
	var bbcode_cleaner := RegEx.new()
	bbcode_cleaner.compile("\\[/?[a-zA-Z0-9=_ ]+\\]")
	
	for i in range(lines.size()):
		var line := lines[i]
		var _match := heading_regex.search(line)
		if _match:
			var title := _match.get_string(1).strip_edges()
			title = bbcode_cleaner.sub(title, "", true).strip_edges()
			heading_positions.append({ "title": title, "line": i })

func populate_tree():
	tree.clear()
	var root := tree.create_item()
	for heading in heading_positions:
		var item := tree.create_item(root)
		item.set_text(0, heading.title)
		item.set_metadata(0, heading.line)

func _on_tree_item_selected():
	var item := tree.get_selected()
	if not item:
		return
	var line_index: int = item.get_metadata(0)
	jump_to_line(line_index)

func jump_to_line(line_index: int):
	# Convert line index to character offset
	var lines := help_text.text.split("\n")
	var char_offset := 0
	for i in range(min(line_index, lines.size())):
		char_offset += lines[i].length() + 1  # +1 for newline
		
	help_text.scroll_to_line(line_index)  # Godot 4.x RichTextLabel supports this
