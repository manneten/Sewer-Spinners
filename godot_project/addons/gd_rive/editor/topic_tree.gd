@tool
class_name TopicTree
extends Tree

func make_tree(topics: Dictionary):
	clear()
	var root = create_item() 
	root.set_text(0, "Topics")
	
	for topic_name in topics:
		var topic = create_item(root)
		topic.set_text(0, topic_name)
		topic.set_metadata(0, {"is_topic": true})
		
		for trigger_value in topics[topic_name]:
			var trigger = create_item(topic)
			trigger.set_text(0, trigger_value)
			trigger.set_metadata(0, {"is_topic": false})
			
			trigger.collapsed = true
			
		topic.collapsed = true
