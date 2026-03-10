extends Node

var flags: Dictionary = {}
var data: Dictionary = {}

func set_flag(key: String, value: bool) -> void:
	flags[key] = value

func get_flag(key: String) -> bool:
	return flags.get(key, false)

func set_data(key: String, value) -> void:
	data[key] = value

func get_data(key: String):
	return data.get(key, null)

func export_state() -> Dictionary:
	return { 
		"flags": flags,
		"data": data,
	}
	
func restore_state(state) -> void:
	flags = state["flags"]
	data = state["data"]
