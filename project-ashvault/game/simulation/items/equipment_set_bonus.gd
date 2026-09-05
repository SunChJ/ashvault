class_name EquipmentSetBonus
extends Resource

const Effect = preload("res://game/simulation/items/item_stat_effect.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")
var _frozen := false

var _set_id: String = ""
var _pieces: int = 2
var _effects: Array[Resource] = []

@export var set_id: String:
	get:
		return _set_id
	set(value):
		if not is_frozen():
			_set_id = value

@export var pieces: int:
	get:
		return _pieces
	set(value):
		if not is_frozen():
			_pieces = value

@export var effects: Array[Resource]:
	get:
		return _effects.duplicate()
	set(value):
		if not is_frozen():
			_effects = value.duplicate()


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	for effect: Resource in _effects:
		effect.freeze()
	_frozen = true


func validation_error() -> String:
	if not set_id.begins_with("set.") or not StableIdContract.is_valid(set_id) or not pieces in [2, 3, 4]:
		return "Set bonuses require a stable set ID and a 2/3/4-piece threshold."
	if effects.is_empty():
		return "Set thresholds must contribute at least one stat effect."
	return Effect.list_error(effects)
