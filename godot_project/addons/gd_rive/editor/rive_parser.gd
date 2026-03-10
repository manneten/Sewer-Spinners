class_name RiveParser

class ParsedUnit:
	var type: String
	var start: int
	var length: int
	var style: Dictionary

func parse(tokens: Array) -> Array:
	var blocks: Array = []
	
	for token in tokens:
		match token.type:
			"topic_open":
				var block = ParsedUnit.new()
				block.type = "topic_open"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": RiveColors.topic_color, "bold": true }
				blocks.append(block)
				
			"topic_close":
				var block = ParsedUnit.new()
				block.type = "topic_close"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": RiveColors.topic_color, "bold": true }
				blocks.append(block)
				
			"prefix":
				var block = ParsedUnit.new()
				block.type = "prefix"
				block.start = token.start
				block.length = 1
				block.style = { "color": get_prefix_color(token.value), "bold": true }
				blocks.append(block)
				
			"tag":
				var inner = token.value.strip_edges()
				var parts = inner.split(" ")
				
				var block_1 = ParsedUnit.new()
				block_1.type = "tag_open"
				block_1.start = token.start 
				block_1.length = 1
				block_1.style = { "color": RiveColors.tag_bracket_color, "bold": true }
				
				var block_2 = ParsedUnit.new()
				block_2.type = "tag_keyword"
				block_2.start = token.start + 1
				block_2.length = parts[0].length()
				block_2.style = { "color": get_keyword_color(parts[0]), "bold": true }
				
				var block_3 = ParsedUnit.new()
				block_3.type = "tag_close"
				block_3.start = token.end - 1
				block_3.length = 1
				block_3.style = { "color": RiveColors.tag_bracket_color, "bold": true }
				
				blocks.append_array([block_1, block_2, block_3])
				
			"tag_open":
				var block = ParsedUnit.new()
				block.type = "tag_open"
				block.start = token.start 
				block.length = 1
				block.style = { "color": RiveColors.tag_bracket_color, "bold": true }
				
				blocks.append(block)
				
			"tag_close", "tag_d_close":
				var block = ParsedUnit.new()
				block.type = "tag_close"
				block.start =  token.end - 1
				block.length = 1
				block.style = { "color": RiveColors.tag_bracket_color, "bold": true }
				
				blocks.append(block)
				
			"tag_keyword":
				var block = ParsedUnit.new()
				block.type = "tag_close"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": get_keyword_color(token.value), "bold": true }
				
				blocks.append(block)
				
			"tag_property":
				var block = ParsedUnit.new()
				block.type = "tag_property"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": get_keyword_color(token.value) }
				
				blocks.append(block)
				
			"array":
				var block = ParsedUnit.new()
				
				block.type = "array"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": RiveColors.directive_color, "bold": true }

				blocks.append(block)
				
			"operator":
				var block = ParsedUnit.new()
				
				block.type = "operator"
				block.start = token.start
				block.length = 2
				block.style = { "color": RiveColors.equalizer_color }

				blocks.append(block)
				
			"equality_op":
				var block = ParsedUnit.new()
				
				block.type = "equality_op"
				block.start = token.start
				block.length = 2
				block.style = { "color": RiveColors.equalizer_color }

				blocks.append(block)
				
			"equality_op_s":
				var block = ParsedUnit.new()
				
				block.type = "equality_op"
				block.start = token.start
				block.length = 1
				block.style = { "color": RiveColors.equalizer_color }

				blocks.append(block)
				
			"constants":
				var block = ParsedUnit.new()
				
				block.type = "constants"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": RiveColors.condition_color }

				blocks.append(block)
				
			"not":
				var block = ParsedUnit.new()
				
				block.type = "not"
				block.start = token.start
				block.length = 3
				block.style = { "color": RiveColors.equalizer_color, "bold": true }

				blocks.append(block)
				
			"wild_card":
				var block = ParsedUnit.new()
				
				block.type = "wild_card"
				block.start = token.start
				block.length = 1
				block.style = { "color": RiveColors.directive_color, "bold": true }

				blocks.append(block)
				
			"comment":
				var block = ParsedUnit.new()
				
				block.type = "comment"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": RiveColors.comment_color }

				blocks.append(block)
				
			"unmatched":
				var block = ParsedUnit.new()
				
				var block_colour = RiveColors.error_color
				
				if token.fall_back == RiveLexer.FallBack.DIRECTIVE:
					block_colour = RiveColors.directive_color
				
				if token.fall_back == RiveLexer.FallBack.TRIGGER:
					block_colour = RiveColors.trigger_color
					
				if token.fall_back == RiveLexer.FallBack.REPLY:
					block_colour = RiveColors.reply_color
				
				block.type = "unmatched"
				block.start = token.start
				block.length = token.end - token.start
				block.style = { "color": block_colour }

				blocks.append(block)
				
	return blocks

func get_prefix_color(char: String) -> Color:
	match char:
		"+": return RiveColors.trigger_color
		"-", "^": return RiveColors.reply_color
		"*": return RiveColors.condition_color
		"!": return RiveColors.directive_color
		
	return RiveColors.error_color

func get_keyword_color(keyword: String) -> Color:
	match keyword.replace("<", "").replace(">", "").replace("/", ""):
		"star": return RiveColors.built_ins_color
		"condition", "flag": return RiveColors.condition_color
		"set", "get", "call", "bot": return RiveColors.directive_color
		"topic": return RiveColors.topic_color
		
	if keyword in ["global", "call-global", "set-global", "get-global"]:
		return RiveColors.global_color
		
	return RiveColors.tag_keyword_color
