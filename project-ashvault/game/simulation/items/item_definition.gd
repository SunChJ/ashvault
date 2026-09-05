class_name ItemDefinition
extends "res://game/content/content_definition.gd"

const Effect = preload("res://game/simulation/items/item_stat_effect.gd")
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


var _allowed_rarities: Array[String] = ["white", "blue", "gold"]
var _fixed_affixes: Array[String] = []
var _drop_source_id: String = ""
var _interaction_id: String = ""
var _rule_id: String = ""
var _set_id: String = ""

@export var allowed_rarities: Array[String]:
	get:
		return _allowed_rarities.duplicate()
	set(value):
		if not is_frozen():
			_allowed_rarities = value.duplicate()

@export var fixed_affixes: Array[String]:
	get:
		return _fixed_affixes.duplicate()
	set(value):
		if not is_frozen():
			_fixed_affixes = value.duplicate()

@export var drop_source_id: String:
	get:
		return _drop_source_id
	set(value):
		if not is_frozen():
			_drop_source_id = value

@export var interaction_id: String:
	get:
		return _interaction_id
	set(value):
		if not is_frozen():
			_interaction_id = value

@export var rule_id: String:
	get:
		return _rule_id
	set(value):
		if not is_frozen():
			_rule_id = value

@export var set_id: String:
	get:
		return _set_id
	set(value):
		if not is_frozen():
			_set_id = value


var _two_handed: bool = false
var _base_effects: Array[Resource] = []

@export var two_handed: bool:
	get:
		return _two_handed
	set(value):
		if not is_frozen():
			_two_handed = value

@export var base_effects: Array[Resource]:
	get:
		return _base_effects.duplicate()
	set(value):
		if not is_frozen():
			_base_effects = value.duplicate()


func validation_error() -> String:
	if not content_id.begins_with("item."):
		return "Item definition ID must use the item namespace."
	if display_name.strip_edges().is_empty():
		return "Item display name must not be empty."
	if not equipment_slot.begins_with("slot.") or not StableIdContract.is_valid(equipment_slot):
		return "Item equipment slot must be a stable slot ID."
	if max_sockets < 0 or max_sockets > 32:
		return "Item socket capacity must be between zero and 32."
	if two_handed and equipment_slot != "slot.weapon":
		return "Only weapons may occupy two hands."
	return Effect.list_error(base_effects)


func freeze() -> void:
	for effect: Resource in _base_effects:
		effect.freeze()
	super.freeze()
