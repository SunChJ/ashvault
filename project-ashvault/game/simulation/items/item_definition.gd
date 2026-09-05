class_name ItemDefinition
extends "res://game/content/content_definition.gd"

const StableIdContract = preload("res://game/content/stable_id.gd")

var _display_name := ""
var _equipment_slot := ""
var _max_sockets := 0

@export var display_name: String:
	get:
		return _display_name
	set(value):
		if not is_frozen():
			_display_name = value

@export var equipment_slot: String:
	get:
		return _equipment_slot
	set(value):
		if not is_frozen():
			_equipment_slot = value

@export var max_sockets: int:
	get:
		return _max_sockets
	set(value):
		if not is_frozen():
			_max_sockets = value


func validation_error() -> String:
	if not content_id.begins_with("item."):
		return "Item definition ID must use the item namespace."
	if display_name.strip_edges().is_empty():
		return "Item display name must not be empty."
	if not equipment_slot.begins_with("slot.") or not StableIdContract.is_valid(equipment_slot):
		return "Item equipment slot must be a stable slot ID."
	if max_sockets < 0 or max_sockets > 32:
		return "Item socket capacity must be between zero and 32."
	return ""
