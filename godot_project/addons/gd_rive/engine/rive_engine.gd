extends Node

var current_persona := ""

var topics = {}
var substitutions = {}
var arrays = {}
var bot_vars = {}
var user_vars = {}
var user_topics = {}
var object_macros = {}

var brain_files = []

signal topic_changed(topic_name: String)
signal persona_changed(persona_name: String)

func _ready() -> void:
	register_all_macros()
	brain_files = get_all_brain_files()

func get_all_brain_files() -> Array:
	var dir = DirAccess.open("res://data/rive")
	var files = []
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".txt"):
				files.append("res://data/rive/" + file_name)
			file_name = dir.get_next()
	return files

func set_default_brain(files: Array):
	brain_files = files

func load_brain(files: Array) -> void:
	for file in files:
		load_file(file)

func load_persona(file: String, with_brain: bool = true) -> void:
	if with_brain:
		load_brain(brain_files if brain_files.size() > 0 else get_all_brain_files())
		
	load_file(file)

func switch_to_persona(persona: String, with_brain: bool = true) -> void:
	reset()
	load_persona("res://data/personas/%s.txt" % persona, with_brain)
	current_persona = persona
	persona_changed.emit(current_persona)

func load_persona_with_own_brain(files: Array, persona: String):
	load_brain(files)
	load_persona(persona, false)

func reset() -> void:
	topics.clear()
	substitutions.clear()
	arrays.clear()
	
func load_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	var lines = []
	while not file.eof_reached():
		lines.append(file.get_line())
	_process_script(lines)

func get_all_topics() -> Array:
	return topics.keys()

func get_triggers_for(topic_name: String) -> Array:
	if not topics.has(topic_name):
		return []
	return topics[topic_name].keys()

func get_topic_tree() -> Dictionary:
	var result = {}
	for topic in topics.keys():
		result[topic] = get_triggers_for(topic)
	return result

func register_all_macros() -> void:
	object_macros.clear()
	var script_methods = RiveMacros.get_method_list()
	var base_class_methods = Node.new().get_method_list()
	
	for method_info in script_methods:
		var method_name = method_info["name"]
		var _flags = method_info["flags"]
		
		var is_user_defined = true
		for base_method_info in base_class_methods:
				if base_method_info["name"] == method_name:
					is_user_defined = false
					break

		if is_user_defined and not method_name.begins_with("_"):
				object_macros[method_name] = method_name

func export_state() -> Dictionary:
	return { 
		"persona": current_persona,
		"topics": topics,
		"substitutions": substitutions,
		"arrays": arrays,
		"bot_vars": bot_vars,
		"user_vars": user_vars,
		"user_topics": user_topics
	}
	
func restore_state(state: Dictionary) -> void:
	current_persona = state["persona"]
	topics = state["topics"]
	substitutions = state["substitutions"]
	arrays = state["arrays"]
	bot_vars = state["bot_vars"]
	user_vars = state["user_vars"]
	user_topics = state["user_topics"]
	register_all_macros()

func set_topic(username: String, new_topic: String) -> void:
	user_topics[username] = new_topic
	topic_changed.emit(new_topic)

func reply(username: String, message: String) -> String:
	# message = _apply_subs(message.strip_edges().to_lower())
	var original = message.strip_edges()
	var normalized = _normalize_message(_apply_subs(original))

	if not user_topics.has(username):
		user_topics[username] = "default"
		
	if not user_vars.has(username):
		user_vars[username] = {}
		
	var topic = user_topics[username]
	var match_data = _match_trigger(topic, normalized, username, original)
	
	var response = match_data["response"]
	var stars = match_data["stars"]

	if response == "":
		return "I don't know how to respond to that."

	return _process_reply(response, username, stars)

func is_ascii_alphanumeric(c: String) -> bool:
	var code := c.unicode_at(0)
	return (
			(code >= 48 and code <= 57) 
			or 
			(code >= 65 and code <= 90) 
			or 
			(code >= 97 and code <= 122)
		)

func _normalize_message(message: String) -> String:
	message = message.to_lower()
	
	var clean := ""
	
	for c in message:
		if is_ascii_alphanumeric(c) or c == " ":
			clean += c
			
		elif c == "'":  # allow apostrophes
			clean += c
	
	return clean.strip_edges()

func _process_script(lines: Array) -> void:
	var topic = "default"
	var trigger = ""
	var is_macro = false
	var current_macro = ""
	var macro_lines = []
	var last_reply_index = -1

	for line in lines:
		line = line.strip_edges()
		if line.begins_with("//") or line == "":

			continue

		if line.begins_with("> object"):
			is_macro = true
			current_macro = line.split(" ")[2]
			macro_lines = []

			continue

		elif line.begins_with("< object"):
			# end of macro definition
			is_macro = false
			for l in macro_lines:
				if l.begins_with("<call>") and l.ends_with("</call>"):
					var func_name = l.substr(6, l.length() - 13).strip_edges()
					object_macros[current_macro] = func_name
			current_macro = ""

			continue
	
		if is_macro:
			macro_lines.append(line)

			continue

		var code = line[0]
		var content = line.substr(1).strip_edges()
		match code:
			">":
				if content.begins_with("topic"):
					topic = content.split(" ")[1].strip_edges()
					if not topics.has(topic):
						topics[topic] = {}
			"<":
				topic = "default"
			"+":
				trigger = content
				if not topics[topic].has(trigger):
					topics[topic][trigger] = {}
					topics[topic][trigger]["replies"] = []
					topics[topic][trigger]["flags"] = {
						"allow_mid_wildcard": false  # default is false for safety
					}
			"-":
				topics[topic][trigger]["replies"].append(content)
				last_reply_index = topics[topic][trigger]["replies"].size() - 1
			"^":
				if last_reply_index >= 0 and topics[topic][trigger]["replies"].has(last_reply_index):
					var existing = topics[topic][trigger]["replies"][last_reply_index]
					topics[topic][trigger]["replies"][last_reply_index] = (existing + " " + content).strip_edges()
			"*":
				if not topics[topic][trigger].has("conditions"):
					topics[topic][trigger]["conditions"] = []

				if content.begins_with("*"):  # this is the fallback `**` line
					topics[topic][trigger]["fallback_condition"] = content.substr(2).strip_edges()
				else:
					topics[topic][trigger]["conditions"].append(content)
				# topics[topic][trigger]["conditions"].append(content)
			"!":
				if content.begins_with("flag"):
					var flag_line = content.replace("flag", "").strip_edges()
					var parts = flag_line.split("=", false)
					if parts.size() == 2 and trigger != "":
						var flag_key = parts[0].strip_edges()
						var flag_value = parts[1].strip_edges().to_lower() in ["true", "1", "yes"]
						topics[topic][trigger]["flags"][flag_key] = flag_value
				else:
					_parse_directive(content)

func _parse_directive(content: String) -> void:
	if content.begins_with("sub"):
		var parts = content.replace("sub", "").strip_edges().split("=", false)
		if parts.size() == 2:
			substitutions[parts[0].strip_edges()] = parts[1].strip_edges()
	elif content.begins_with("array"):
		var parts = content.replace("array", "").strip_edges().split("=", false)
		if parts.size() == 2:
			var key = parts[0].strip_edges()
			var values = parts[1].strip_edges().split(" ")
			arrays[key] = values
	elif content.begins_with("var"):
		var parts = content.replace("var", "").strip_edges().split("=", false)
		if parts.size() == 2:
			var key = parts[0].strip_edges()
			var raw_value = parts[1].strip_edges()
			# Parse values in {a|b|c} format into array, else store string
			if raw_value.begins_with("{") and raw_value.ends_with("}"):
				var inner = raw_value.substr(1, raw_value.length() - 2)
				var values = inner.split("|")
				bot_vars[key] = values as Array[String]
			else:
				bot_vars[key] = raw_value

func _apply_subs(message: String) -> String:
	for key in substitutions.keys():
		message = message.replace(key, substitutions[key])
	return message

func _match_trigger(topic: String, normalized: String, username: String, original: String) -> Dictionary:
	var result := { "response": "", "stars": [] }
	if not topics.has(topic):
		return result

	for trigger in topics[topic].keys():
		var data = topics[topic][trigger]
		var pattern = trigger

		# Replace @arrays with regex-safe groups
		for array_key in arrays.keys():
			var array_regex = "(?:" + "|".join(arrays[array_key]) + ")"
			pattern = pattern.replace("@" + array_key, array_regex)

		# Allow mid-line wildcard [*] if the flag is set
		var flags = data.get("flags", {})
		if flags.has("allow_mid_wildcard") and flags["allow_mid_wildcard"]:
			pattern = pattern.replace("[*]", ".*")

		# Standard RiveScript * becomes capture group
		pattern = pattern.replace("*", "(.*)")

		# Full match required
		var re = RegEx.new()
		var err = re.compile("^" + pattern + "$")
		if err != OK:
			continue

		var match = re.search(normalized)
		
		if match:
			
			#var stars = match.strings.slice(1)
			var stars = []
			var groups = match.get_group_count()
			
			for i in range(1, groups + 1):
				var raw = match.get_string(i)
				if raw == "":
					stars.append("")
					continue
					
				var original_index = normalized.find(raw)
				
				if original_index != -1:
					stars.append(original.substr(original_index, original.length()))
				else:
					stars.append(raw)  # fallback
			
			# Conditional check
			if data.has("conditions"):
				for cond in data["conditions"]:
					if _eval_condition(cond, username):
						result["response"] = cond.split("=>")[1].strip_edges()
						result["stars"] = stars
						return result

			# Fallback line
			if data.has("fallback_condition"):
				result["response"] = data["fallback_condition"]
				result["stars"] = stars
				return result

			# Default reply
			var replies = data["replies"]
			result["response"] = replies[randi() % replies.size()]
			result["stars"] = stars
			return result

	return result

func _match_trigger_basic(topic: String, message: String, username: String) -> Dictionary:
	var result := { "response": "", "stars": [] }
	if not topics.has(topic):
		return result

	for trigger in topics[topic].keys():
		var pattern = trigger
		for array_key in arrays.keys():
			pattern = pattern.replace("@" + array_key, "(" + "|".join(arrays[array_key]) + ")")
		
		var re = RegEx.new()
		re.compile("^" + pattern.replace("*", "(.*)") + "$")
		var match = re.search(message)
		if match:
			var stars = match.strings.slice(1)
			var data = topics[topic][trigger]
			
			if data.has("conditions"):
				for cond in data["conditions"]:
					if _eval_condition(cond, username):
						result["response"] = cond.split("=>")[1].strip_edges()
						result["stars"] = stars
						return result

			# EXPERIMENTAL
			if data.has("fallback_condition"):
				result["response"] = data["fallback_condition"]
				result["stars"] = stars
				return result

			var replies = data["replies"]
			result["response"] = replies[randi() % replies.size()]
			result["stars"] = stars
			return result

	return result

#func _match_trigger(topic: String, message: String, username: String) -> String:
	#if not topics.has(topic):
		#return ""
	#for trigger in topics[topic].keys():
		#var pattern = trigger
		#for array_key in arrays.keys():
			##pattern = pattern.replace("@" + array_key, "(" + ",".join(arrays[array_key]) + ")")
			#var array_regex = "(?:" + "|".join(arrays[array_key]) + ")"
			#pattern = pattern.replace("@" + array_key, array_regex)
		#var re = RegEx.new()
		#re.compile("^" + pattern.replace("*", "(.*)") + "$")
		#if re.search(message):
			#var data = topics[topic][trigger]
			#if data.has("conditions"):
				#for cond in data["conditions"]:
					#if _eval_condition(cond, username):
						#return cond.split("=>")[1].strip_edges()
				## fallback to replies if no condition matched
			#var replies = data["replies"]
			#return replies[randi() % replies.size()]
	#return ""

func _eval_condition(condition: String, username: String) -> bool:
	# examples:
	# * <get var> == value => ...
	# * <condition flag> => ...
	# * <condition not flag> => ...
	# * <condition data.key == value> => ...

	condition = condition.strip_edges()
	var parts = condition.split("=>", false)
	if parts.size() != 2:
		return false

	var expr = parts[0].strip_edges().replace("*", "").strip_edges()
	var tokens = expr.split(" ")

	# 1. Handle <get var> style user variable comparisons
	if tokens.size() >= 3 and tokens[0].begins_with("<get"):
		var varname = tokens[0].substr(5, tokens[0].length() - 6)
		var op = tokens[1]
		var val = tokens[2]
		var user_val = user_vars.get(username, {}).get(varname, "")
		return _compare(user_val, val, op)
		# match op:
		# 	"==": return user_val == val
		# 	"!=": return user_val != val
		# 	"<": return user_val < val
		# 	">": return user_val > val
		# 	"<=": return user_val <= val
		# 	">=": return user_val >= val

	# 2. Handle <condition flag> or <condition not flag>
	elif tokens.size() == 1 and tokens[0].begins_with("<condition"):
		var raw = tokens[0].substr(10, tokens[0].length() - 11).strip_edges()
		var negate = false
		if raw.begins_with("not "):
			negate = true
			raw = raw.substr(4)
		var flag_value = RiveConditions.get_flag(raw)
		return not flag_value if negate else flag_value

	# 3. <condition data.key op value>
	elif tokens.size() == 3 and tokens[0].begins_with("<condition"):
		var raw = tokens[0].substr(10, tokens[0].length() - 11).strip_edges()
		if raw.begins_with("data."):
			var key = raw.substr(5)
			var op = tokens[1]
			var val = tokens[2]
			var stored = RiveConditions.get_data(key)
			return _compare(stored, val, op)

	# 4. <get-global [auto-load].[value] / op>
	elif tokens.size() >= 3 and tokens[0].begins_with("<get-global"):
		var raw = tokens[0].substr(11, tokens[0].length() - 12).strip_edges()
		var op = tokens[1]
		var val = tokens[2]
	
		# Handle e.g., Inventory.has_weapon("sword")
		var dot_index = raw.find(".")
		if dot_index == -1:
			return false
	
		var singleton = raw.substr(0, dot_index)
		expr = raw.substr(dot_index + 1)
	
		if Engine.has_singleton(singleton):
			var obj = Engine.get_singleton(singleton)
	
			# Handle method call
			if expr.ends_with(")"):  # likely a method
				var method_name = expr.get_slice("(", 0)
				var arg_raw = expr.get_slice("(", 1).trim_suffix(")").strip_edges()
				var args = Array(arg_raw.split(",", false)).map(func(a): return a.strip_edges())
				if obj.has_method(method_name):
					var result = obj.callv(method_name, args)
					return _compare(result, val, op)
			else:  # assume it's a property
				if obj.has_variable(expr):
					var result = obj.get(expr)
					return _compare(result, val, op)
	
	return false

func _compare(a, b: String, op: String) -> bool:
	# Try numeric comparison if possible
	if a is String and a.is_valid_float() and b.is_valid_float():
		var a_num = a.to_float()
		var b_num = b.to_float()
		match op:
			"==": return a_num == b_num
			"!=": return a_num != b_num
			"<": return a_num < b_num
			">": return a_num > b_num
			"<=": return a_num <= b_num
			">=": return a_num >= b_num
	else:
		match op:
			"==": return str(a) == b
			"!=": return str(a) != b
	return false

func _process_reply(response: String, username: String, stars: Array = []) -> String:
	var result = response
	result = result.replace("<star>", stars[0] if stars.size() > 0 else "")
	
	for i in range(stars.size()):
		result = result.replace("<star" + str(i + 1) + ">", stars[i])
		
	while result.find("<set") != -1:
		var start = result.find("<set")
		var end = result.find(">", start)
		var inner = result.substr(start + 5, end - start - 5)
		var parts = inner.split("=", false)
		if parts.size() == 2:
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges()
			if key == "topic":
				set_topic(username, value)
			else:
				if not user_vars.has(username):
					user_vars[username] = {}
				user_vars[username][key] = value
			
		result = result.replace(result.substr(start, end - start + 1), "")
		
	while result.find("<get") != -1:
		var start = result.find("<get")
		var end = result.find(">", start)
		var key = result.substr(start + 5, end - start - 5).strip_edges()
		var value = user_vars.get(username, {}).get(key, "unknown")
		result = result.replace(result.substr(start, end - start + 1), value)
		
	while result.find("<bot") != -1:
		var start = result.find("<bot")
		var end = result.find(">", start)
		var key = result.substr(start + 5, end - start - 5).strip_edges()
		var value = ""
		if bot_vars.has(key):
			var options = bot_vars[key]
			if options is Array and options.size() > 0:
				value = options[randi() % options.size()]
			else:
				value = str(bot_vars[key])
		result = result.replace(result.substr(start, end - start + 1), value)

	while result.find("<call>") != -1:
		var start = result.find("<call>")
		var end = result.find("</call>", start)
		if end == -1:
			break  # malformed
		var macro_key = result.substr(start + 6, end - start - 6).strip_edges()
		var func_name = object_macros.get(macro_key, "")
		var value = "[undefined]"
	
		if RiveMacros.has_method(func_name):
			value = RiveMacros.call(func_name)
		result = result.replace(result.substr(start, end - start + 7), value)

	while result.find("<call-global>") != -1:
		var start = result.find("<call-global>")
		var end = result.find("</call-global>", start)
		if end == -1:
			break  # malformed tag
	
		var inner = result.substr(start + 13, end - start - 13).strip_edges()
		var return_value = "[undefined]"
	
		# Parse: Singleton.method(args)
		var dot_index = inner.find(".")
		if dot_index != -1:
			var singleton_name = inner.substr(0, dot_index)
			var call_expr = inner.substr(dot_index + 1)
	
			if Engine.has_singleton(singleton_name):
				var obj = Engine.get_singleton(singleton_name)
	
				if call_expr.ends_with(")"):  # method with args
					var method_name = call_expr.get_slice("(", 0)
					var args_str = call_expr.get_slice("(", 1).trim_suffix(")").strip_edges()
					var args = Array(args_str.split(",", false)).map(func(a): return a.strip_edges())
					if obj.has_method(method_name):
						return_value = str(obj.callv(method_name, args))
				else:  # treat as property
					if obj.has_variable(call_expr):
						return_value = str(obj.get(call_expr))
	
		result = result.replace(result.substr(start, end - start + 14), return_value)
	
	while result.find("<flag") != -1:
		var start = result.find("<flag")
		var end = result.find(">", start)
		if end == -1:
			break
		var inner = result.substr(start + 5, end - start - 5).strip_edges()
		var parts = inner.split("=", false)
		if parts.size() == 2:
			var flag = parts[0].strip_edges()
			var value = parts[1].strip_edges().to_lower() in ["true", "1", "yes"]
			RiveConditions.set_flag(flag, value)
		result = result.replace(result.substr(start, end - start + 1), "")

	while result.find("<data") != -1:
		var start = result.find("<data")
		var end = result.find(">", start)
		if end == -1:
			break
	
		var inner = result.substr(start + 5, end - start - 5).strip_edges()
		var parts = inner.split("=", false)
		if parts.size() == 2:
			var key = parts[0].strip_edges()
			var raw_value = parts[1].strip_edges()
	
			# Try to parse booleans or numbers
			var value: Variant = raw_value
			var lowered = raw_value.to_lower()
			if lowered in ["true", "false"]:
				value = (lowered == "true")
			elif raw_value.is_valid_float():
				value = raw_value.to_float()
			elif raw_value.is_valid_int():
				value = raw_value.to_int()
	
			RiveConditions.set_data(key, value)
	
		result = result.replace(result.substr(start, end - start + 1), "")

	while result.find("<global") != -1:
		var start = result.find("<global")
		var end = result.find(">", start)
		if end == -1:
			break
	
		var raw = result.substr(start + 7, end - start - 7).strip_edges()
		var dot_index = raw.find(".")
		if dot_index != -1:
			var singleton = raw.substr(0, dot_index)
			var expr = raw.substr(dot_index + 1)
	
			if Engine.has_singleton(singleton):
				var obj = Engine.get_singleton(singleton)
	
				if expr.ends_with(")"):
					var method = expr.get_slice("(", 0)
					var arg_str = expr.get_slice("(", 1).trim_suffix(")").strip_edges()
					var args = Array(arg_str.split(",", false)).map(func(a): return a.strip_edges())
					if obj.has_method(method):
						obj.callv(method, args)
	
		result = result.replace(result.substr(start, end - start + 1), "")		

	while result.find("<set-global") != -1:
		var start = result.find("<set-global")
		var end = result.find(">", start)
		if end == -1:
			break
	
		var inner = result.substr(start + 11, end - start - 11).strip_edges()
		var parts = inner.split("=", false)
		if parts.size() == 2:
			var left = parts[0].strip_edges()
			var value = parts[1].strip_edges()
	
			var dot_index = left.find(".")
			if dot_index != -1:
				var singleton = left.substr(0, dot_index)
				var prop = left.substr(dot_index + 1)
				if Engine.has_singleton(singleton):
					var obj = Engine.get_singleton(singleton)
					if obj.has_variable(prop):
						obj.set(prop, value)
	
		result = result.replace(result.substr(start, end - start + 1), "")
	
	# Replace @arrayname with a random item from arrays
	for array_key in arrays.keys():
		var placeholder = "@" + array_key
		if result.find(placeholder) != -1:
			var options = arrays[array_key]
			if options.size() > 0:
				result = result.replace(placeholder, options[randi() % options.size()])

	return result
