@tool
class_name TextField
extends HBoxContainer

@export var json_key : String
@export var field_name : String
var value : String:
	get: return $TextEntry.text
	set(string):
		value = string
		if !has_node("TextEntry"): return
		$TextEntry.text = string
		if is_inside_tree(): Global.emit_signal("tmb_updated")

func _ready(): $Label.text = field_name
