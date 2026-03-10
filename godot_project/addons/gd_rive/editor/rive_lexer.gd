class_name RiveLexer

enum FallBack {
	TRIGGER,
	REPLY,
	DIRECTIVE,
	ERROR
}

class Token:
	var type: String
	var start: int
	var end: int
	var value: String
	var fall_back: FallBack = FallBack.ERROR
	
func lex(line: String) -> Array:
	var matched_ranges: Array = []
	var tokens: Array = []
	var regexes = {
		"comment": "^//.*",
		"topic_open": "^> topic.*$",
		"topic_close": "^< topic",
		"prefix": "^[\\+\\-\\*\\!\\^]",
		# Compound-aware structural tokens
		"tag_open": "<(?=\\w+[\\s|\\-])",        # < followed by word and a space
		"tag_close": "(?<=\\s|\\-)\\w+>",      # word ending in >, with space before the word
		"tag_keyword": "(?<=<)[\\w+\\-]+(?=\\s)", #"(?<=<)\\w+(?=\\s|\\-)",  # word preceded by < and followed by space
		"not": "(?<=<condition )not\\b",
		"tag_property": "(?: ([a-zA-Z0-9_\\-]+))(?=>|\\=)", # word preceded by space and followed by >
		# Simple tags like <star>, <input>
		"tag": "<\\/?\\w+>",
		"tag_d_close": "(?<=)\\w+>>",
		"array": "@[a-zA-Z0-9_\\-]+",
		"operator": "=>",
		"equality_op": "(?:==|!=)",
		"equality_op_s": "(=)(?=<)",
		"constants": "(?<===|!=)\\s*(undefined|true|false)",
		"wild_card": "(?<=\\S)\\s*\\*\\s*|(?<=\\s)\\*(?=\\S)"
}
	
	for type in regexes.keys():
		var reg_ex = RegEx.new()
		if reg_ex.compile(regexes[type]) == OK:
			for match in reg_ex.search_all(line):
				var token = Token.new()
				token.type = type
				token.start = match.get_start()
				token.end = match.get_end()
				token.value = line.substr(match.get_start(), match.get_end() - match.get_start())
				tokens.append(token)
				matched_ranges.append(token)

	# Find unmatched text blocks
	matched_ranges.sort_custom(func(a, b): return a["start"] < b["start"])
	
	var unmatched_tokens: Array = []
	var last_index = 0
	var fall_back = FallBack.ERROR

	if line.left(1) in ["!"]:
		fall_back = FallBack.DIRECTIVE
	
	if line.left(1) in ["-", "^", "*"]:
		fall_back = FallBack.REPLY
		
	if line.left(1) == "+":
		fall_back = FallBack.TRIGGER
	
	for range in matched_ranges:
		print(range["start"])
		if last_index < range["start"]:
			var unmatched = Token.new()
			unmatched.type = "unmatched"
			unmatched.start = last_index
			unmatched.end = range["end"]
			unmatched.value = line.substr(unmatched.start, unmatched.end - unmatched.start)
			unmatched.fall_back = fall_back
			unmatched_tokens.append(unmatched)
			
		last_index = max(last_index, range["end"])
	
	# Add any remaining text after the last match
	if last_index < line.length():
		var unmatched = Token.new()
		unmatched.type = "unmatched"
		unmatched.start = last_index
		unmatched.end = line.length()
		unmatched.value = line.substr(unmatched.start, unmatched.end - unmatched.start)
		unmatched.fall_back = fall_back
		unmatched_tokens.append(unmatched)
	
	# Combine matched and unmatched tokens, sorted by start index
	tokens.append_array(unmatched_tokens)
	tokens.append_array(unmatched_tokens)
	tokens.sort_custom(func(a, b): return a.start < b.start)

	return tokens
	
