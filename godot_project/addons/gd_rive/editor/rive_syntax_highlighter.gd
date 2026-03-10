@tool
class_name RiveSyntaxHighlighter
extends SyntaxHighlighter

var lexer := RiveLexer.new()
var parser := RiveParser.new()
var renderer := RiveHighlighter.new()

func _get_line_syntax_highlighting(line_no: int) -> Dictionary:
	var line = get_text_edit().get_line(line_no)
	var tokens = lexer.lex(line)
	var parsed = parser.parse(tokens)
	
	return renderer.highlight(parsed, line.length())
