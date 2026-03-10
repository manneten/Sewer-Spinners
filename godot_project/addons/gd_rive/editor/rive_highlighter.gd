class_name RiveHighlighter

func highlight(blocks: Array, line_length: int) -> Dictionary:
	var result := {}
	var covered := []
	
	for block in blocks:
		for i in range(block.start, block.start + block.length):
			covered.append(i)
			
		result[block.start] = block.style.duplicate()
		result[block.start]["length"] = block.length
		
	return result
